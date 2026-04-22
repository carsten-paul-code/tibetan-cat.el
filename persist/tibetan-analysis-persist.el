;;; tibetan-analysis-persist.el --- Persistent segment analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Persists segment analysis to individual files, allowing users to add
;; notes, translations, and footnotes that survive re-analysis.
;;
;; Usage:
;;   C-c u A - Open/create analysis for current segment (side window)
;;   C-c u R - Re-analyze (regenerate auto section, keep notes)
;;
;; File structure:
;;   your-text.org
;;   analysis/
;;     seg-001.org
;;     seg-002.org
;;     ...

;;; Code:

(require 'cl-lib)
;; Only require org when not in batch mode (can hang in batch)
(unless noninteractive
  (require 'org))
(require 'md5)

;; Require modules for verb analysis (soft load - main loading via tibetan-cat.el)
(require 'tibetan-verb-classifier nil t)
(require 'tibetan-enhanced-display nil t)
(require 'tibetan-particles-bialek nil t)
(require 'tibetan-interlinear nil t)
;; Round-2 (clauses + NPs + argument structure) — used by the
;; `** Clause Structure' section.  Soft-required so a missing module
;; does not break analysis-file generation; the renderer falls back
;; to a placeholder line in that case.
(require 'tibetan-clause-segmenter nil t)
;; gptel for Claude translation (soft load - optional)
(require 'gptel nil t)

;; Forward declaration: `tibetan-vocab--corpus' is defined as a
;; `defvar-local' in `core/tibetan-vocabulary-detailed.el'.  Declared
;; here so the byte-compiler treats it as a special (dynamic) variable
;; when `tibetan-analysis-generate-content' let-binds it to thread the
;; `#+TIBETAN_CORPUS:' header through the dictionary ranker.
(defvar tibetan-vocab--corpus)


(defconst tibetan-analysis-version "1.0"
  "Version of the analysis file format.")

;; ============================================================================
;; DISPLAY SETTINGS - Smaller roman text
;; ============================================================================

(defcustom tibetan-analysis-roman-scale 0.65
  "Scale factor for non-Tibetan (roman) text in analysis buffers.
Values less than 1.0 make text smaller, e.g. 0.65 = 65% size."
  :type 'float
  :group 'tibetan-cat)

(defcustom tibetan-analysis-show-clause-structure t
  "When non-nil, the generated analysis file includes a `** Clause
Structure' section populated from `tibetan-analyze-round2'.

The section lists, per clause, the clause type (main vs. dependent
+ the converb that makes it dependent), the clause's main verb,
the NPs found inside it with their case tags (ERG/ABS/DAT/LOC/
TERM/GEN/INST/COM), and any semantic-role assignments derivable
from the verb's Hill-DB case frame (agent, patient, goal, …).

Set to nil to suppress the section; existing analysis files are
only affected the next time they are regenerated."
  :type 'boolean
  :group 'tibetan-cat)

(defface tibetan-analysis-tibetan-face
  '((t :inherit default))
  "Face for Tibetan text in analysis buffers."
  :group 'tibetan-cat)

(defface tibetan-analysis-roman-face
  '((t :inherit default))
  "Face for roman (non-Tibetan) text in analysis buffers."
  :group 'tibetan-cat)

(defvar-local tibetan-analysis--faces-setup nil
  "Non-nil if faces have already been set up for this buffer.")

(defun tibetan-analysis-setup-faces ()
  "Setup faces for analysis buffers.
Ensures Tibetan text remains readable at all heading levels and in
verbatim/code blocks which otherwise might use smaller fonts.
Only applies once per buffer to prevent accumulation."
  (unless tibetan-analysis--faces-setup
    ;; Ensure headings don't get too small (level 3+ used for dictionary entries)
    (face-remap-add-relative 'org-level-1 :height 1.1)
    (face-remap-add-relative 'org-level-2 :height 1.05)
    (face-remap-add-relative 'org-level-3 :height 1.0)  ; Keep readable for Tibetan headings

    ;; Ensure verbatim (=...=) and code (~...~) don't shrink - they contain Tibetan particles
    ;; Use variable-pitch to allow proper Tibetan font rendering
    (face-remap-add-relative 'org-verbatim :height 1.0)
    (face-remap-add-relative 'org-code :height 1.0)

    (setq tibetan-analysis--faces-setup t)))

;; Hook to apply faces when buffer is displayed
(defun tibetan-analysis-mode-hook ()
  "Hook to run when entering an analysis buffer."
  (when (and (buffer-file-name)
             (string-match "analysis/seg-[0-9]+\\.org$" (buffer-file-name)))
    (tibetan-analysis-setup-faces)))

(add-hook 'org-mode-hook 'tibetan-analysis-mode-hook)

;; ============================================================================
;; PATH AND FILENAME FUNCTIONS
;; ============================================================================

(defun tibetan-analysis-get-folder ()
  "Get the analysis folder path for current buffer.
Creates the folder if it doesn't exist.
Returns the folder path."
  (let* ((source-file (buffer-file-name))
         (source-dir (file-name-directory source-file))
         (analysis-dir (expand-file-name "analysis" source-dir)))
    (unless (file-exists-p analysis-dir)
      (make-directory analysis-dir t)
      (message "Created analysis folder: %s" analysis-dir))
    analysis-dir))

(defun tibetan-analysis--extract-segment-number (seg-id)
  "Extract segment number from SEG-ID.
SEG-ID can be:
- A number: 5
- A simple string: \"5\" or \"seg-005\"
- A compound string: \"Segment 5\" or \"Sentence 1, Segment 5\"
Returns the segment number as an integer."
  (cond
   ((numberp seg-id) seg-id)
   ((stringp seg-id)
    (cond
     ;; "Segment N" or "Sentence X, Segment N" - extract N after "Segment"
     ((string-match "Segment \\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; "seg-NNN" format
     ((string-match "seg-\\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; Plain number string
     ((string-match "^\\([0-9]+\\)$" seg-id)
      (string-to-number (match-string 1 seg-id)))
     ;; Any number as fallback
     ((string-match "\\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id)))
     (t 1)))
   (t 1)))

(defun tibetan-analysis-segment-filename (seg-id)
  "Generate analysis filename for SEG-ID.
SEG-ID can be a number or string like \\='1\\=' or \\='seg-001\\='.
Returns filename like \\='seg-001.org\\='."
  (let ((num (tibetan-analysis--extract-segment-number seg-id)))
    (format "seg-%03d.org" num)))

(defun tibetan-analysis-get-filepath (seg-id &optional source-file)
  "Get full filepath for analysis of SEG-ID.
If SOURCE-FILE is provided, includes short name suffix."
  (let* ((folder (tibetan-analysis-get-folder))
         (short-name (when source-file
                       (tibetan-analysis-make-short-name source-file)))
         (num (tibetan-analysis--extract-segment-number seg-id))
         (filename (if short-name
                       (format "seg-%03d-%s.org" num short-name)
                     (format "seg-%03d.org" num))))
    (expand-file-name filename folder)))

(defun tibetan-analysis-make-short-name (source-file)
  "Generate a short name suffix from SOURCE-FILE for analysis filenames.
E.g., \\='Tigress-Story-BlockPrint-Class.org\\=' -> \\='tigress\\='
      \\='Reading-Sa-skya-legs-bshad.org\\=' -> \\='saskya\\='
      \\='Reading-05-Padma.org\\=' -> \\='padma\\='."
  (when source-file
    (let* ((basename (file-name-sans-extension
                      (file-name-nondirectory source-file)))
           ;; Remove common prefixes
           (name (replace-regexp-in-string "^Reading-[0-9]*-?" "" basename))
           (name (replace-regexp-in-string "^Tigress-Story-" "" name))
           ;; Take first meaningful word
           (parts (split-string name "[-_]" t))
           (first-word (car parts)))
      (when first-word
        (downcase (substring first-word 0 (min 8 (length first-word))))))))

;; ============================================================================
;; HASH FUNCTIONS
;; ============================================================================

(defun tibetan-analysis-compute-hash (text)
  "Compute MD5 hash of TEXT for change detection."
  (md5 (encode-coding-string text 'utf-8)))

;; ============================================================================
;; FILE CREATION
;; ============================================================================

(defun tibetan-analysis-create-file (seg-id tibetan-text source-file auto-content)
  "Create a new analysis file for SEG-ID.
TIBETAN-TEXT is the Tibetan content.
SOURCE-FILE is the path to the source document.
AUTO-CONTENT is the generated analysis content (string)."
  (let* ((filepath (tibetan-analysis-get-filepath seg-id))
         (hash (tibetan-analysis-compute-hash tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         (source-name (file-name-nondirectory source-file))
         (seg-num (if (numberp seg-id) seg-id
                    (if (string-match "\\([0-9]+\\)" seg-id)
                        (string-to-number (match-string 1 seg-id))
                      1))))
    (with-temp-file filepath
      (insert (format "#+TITLE: Segment %d Analysis\n" seg-num))
      (insert "#+STARTUP: showall\n")
      (insert (format "#+SOURCE: [[file:../%s::*Segment %d][%s / Segment %d]]\n"
                      source-name seg-num source-name seg-num))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-analysis-version))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      ;; User-edited sections FIRST — `My Notes' and `Working
      ;; Translation' live immediately below the Tibetan so they are
      ;; within a glance and a scroll-pane of the source text during
      ;; class prep (matches Carsten's classroom flow 2026-04-22).
      ;; `Footnotes' stays at the bottom because it's typically
      ;; populated after the full analysis has been read.
      ;; `Auto-Analysis' is position-independent: regen locates it by
      ;; name via `tibetan-analysis-find-section-bounds', not by order.
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      (insert "* Footnotes\n\n"))
    filepath))

;; ============================================================================
;; FILE PARSING
;; ============================================================================

(defun tibetan-analysis-get-stored-hash (filepath)
  "Get the stored Tibetan hash from analysis file at FILEPATH."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH: \\(.+\\)$" nil t)
        (match-string 1)))))

(defun tibetan-analysis-check-sync (filepath tibetan-text)
  "Check if analysis at FILEPATH is in sync with TIBETAN-TEXT.
Returns t if in sync, nil if source has changed."
  (let ((stored-hash (tibetan-analysis-get-stored-hash filepath))
        (current-hash (tibetan-analysis-compute-hash tibetan-text)))
    (string= stored-hash current-hash)))

(defun tibetan-analysis-find-section-bounds (buffer section-name)
  "Find the start and end positions of SECTION-NAME in BUFFER.
Returns (START . END) or nil if not found."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (let ((start (line-beginning-position))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (cons start end))))))

(defun tibetan-analysis-get-user-sections (filepath)
  "Extract user sections from analysis file at FILEPATH.
Returns alist of (section-name . content) for My Notes,
Working Translation, Footnotes."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (let ((sections '()))
        (dolist (section-name '("My Notes" "Working Translation" "Footnotes"))
          (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) section-name)))
            (when bounds
              (let* ((start (car bounds))
                     (end (cdr bounds))
                     (content (buffer-substring-no-properties start end)))
                (push (cons section-name content) sections)))))
        (nreverse sections)))))

;; ============================================================================
;; REGENERATE AUTO-ANALYSIS
;; ============================================================================

(defun tibetan-analysis-regenerate-auto (filepath tibetan-text auto-content)
  "Regenerate the Auto-Analysis section in FILEPATH.
Preserves user sections (My Notes, Working Translation, Footnotes)
and reshapes the file into the canonical section order:

  * Tibetan Text
  * My Notes                     — user-edited (above Auto-Analysis
  * Working Translation            so notes sit beside the Tibetan
                                   during class-prep reading)
  * Auto-Analysis                — regenerated
  * Footnotes                    — user-edited, footnote-like tail

Any pre-existing section content for My Notes / Working Translation
/ Footnotes is preserved verbatim; only its position in the file
may change.  Files already in canonical order are left untouched
except for Auto-Analysis + header metadata.  Idempotent: repeated
runs produce identical output.

Updates `#+TIBETAN_HASH' and `#+LAST_ANALYZED' as a side-effect."
  (let* ((user-sections (tibetan-analysis-get-user-sections filepath))
         (my-notes
          (cdr (assoc "My Notes" user-sections)))
         (working-translation
          (cdr (assoc "Working Translation" user-sections)))
         (footnotes
          (cdr (assoc "Footnotes" user-sections)))
         (hash (tibetan-analysis-compute-hash tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         ;; Capture the existing file header (everything before the
         ;; first `* ' heading) so we keep `#+TITLE', `#+SOURCE' etc.
         (header
          (with-temp-buffer
            (insert-file-contents filepath)
            (goto-char (point-min))
            (if (re-search-forward "^\\* " nil t)
                (buffer-substring-no-properties
                 (point-min) (line-beginning-position))
              ""))))
    (with-current-buffer (find-file-noselect filepath)
      ;; Full rewrite into canonical order.  We read everything we
      ;; want to preserve into local vars above, erase the buffer,
      ;; then re-emit in the canonical shape — cleaner than trying
      ;; to splice with in-place edits when sections may be in any
      ;; pre-existing order.
      (erase-buffer)
      (insert header)
      ;; Ensure header ends with a blank line before `* '
      (unless (or (string-empty-p header)
                  (string-suffix-p "\n\n" header))
        (insert "\n"))
      ;; Update hash + date in the re-emitted header
      (goto-char (point-min))
      (if (re-search-forward "^#\\+TIBETAN_HASH: .+$" nil t)
          (replace-match (format "#+TIBETAN_HASH: %s" hash))
        ;; Insert missing hash line just after #+TITLE
        (goto-char (point-min))
        (when (re-search-forward "^#\\+TITLE:.+$" nil t)
          (end-of-line)
          (insert (format "\n#+TIBETAN_HASH: %s" hash))))
      (goto-char (point-min))
      (if (re-search-forward "^#\\+LAST_ANALYZED: .+$" nil t)
          (replace-match (format "#+LAST_ANALYZED: %s" date))
        (goto-char (point-max))
        (when (re-search-backward "^#\\+" nil t)
          (end-of-line)
          (insert (format "\n#+LAST_ANALYZED: %s" date))))
      ;; Now append sections in canonical order
      (goto-char (point-max))
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      ;; My Notes — preserved.  If not present before, emit an empty
      ;; placeholder so the section exists for the user to edit into.
      (insert (or my-notes "* My Notes\n\n\n"))
      (unless (string-suffix-p "\n\n" (or my-notes ""))
        (insert "\n"))
      (insert (or working-translation "* Working Translation\n\n\n"))
      (unless (string-suffix-p "\n\n" (or working-translation ""))
        (insert "\n"))
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      (insert (or footnotes "* Footnotes\n\n"))
      (save-buffer)
      (message "Re-analyzed segment. User notes preserved and reshaped."))))

;; ============================================================================
;; GENERATE AUTO-CONTENT - Improved format with inline annotations
;; ============================================================================

;; ============================================================================
;; REFERENCE TRANSLATION EXTRACTION
;; ============================================================================

(defun tibetan-analysis--find-resources-dir ()
  "Find the Resources directory for the current document.
Walks up from the source file directory, checking each ancestor
for a Resources/ subfolder (up to 5 levels).  This handles typical
layouts where the analysis file lives several levels below the
Resources folder, e.g.
  Tibetisch IV/Resources/
  Tibetisch IV/work in progress/analysis/seg-004.org"
  (let ((source-file (or (buffer-file-name)
                         (when (boundp 'tibetan-current-source-file)
                           tibetan-current-source-file))))
    (when source-file
      (let ((dir (file-name-directory source-file))
            (found nil)
            (levels 0))
        (while (and dir (not found) (< levels 5))
          (let ((candidate (expand-file-name "Resources/" dir)))
            (if (file-directory-p candidate)
                (setq found candidate)
              (let ((parent (file-name-directory (directory-file-name dir))))
                (if (or (not parent) (string= parent dir))
                    (setq dir nil)           ; reached filesystem root
                  (setq dir parent)))))
          (setq levels (1+ levels)))
        found))))

(defun tibetan-analysis--extract-pdf-text (pdf-path)
  "Extract text from a PDF file.
First checks for a cached .txt version (same name, .txt extension).
If no cache exists, tries pdftotext, then python3 + pymupdf.
Caches the result for future use.
Returns the full text as a string, or nil if extraction fails."
  (let* ((txt-cache (concat (file-name-sans-extension pdf-path) ".txt"))
         ;; Try cached text file first
         (cached-text (when (file-exists-p txt-cache)
                        (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents txt-cache)
                              (let ((text (string-trim (buffer-string))))
                                (unless (string-empty-p text)
                                  text)))
                          (error nil)))))
    (or cached-text
        ;; No cache — try extraction methods
        (let ((text
               (or
                ;; Method 1: pdftotext (poppler-utils, commonly available on macOS)
                (condition-case nil
                    (when (executable-find "pdftotext")
                      (with-temp-buffer
                        (when (= 0 (call-process "pdftotext" nil t nil
                                                  "-layout" pdf-path "-"))
                          (let ((result (string-trim (buffer-string))))
                            (unless (string-empty-p result) result)))))
                  (error nil))
                ;; Method 2: python3 + pymupdf
                (condition-case nil
                    (let ((script (format "
import sys
try:
    import fitz
    doc = fitz.open('%s')
    text = []
    for page in doc:
        text.append(page.get_text())
    doc.close()
    print('\\n'.join(text))
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
" (replace-regexp-in-string "'" "\\\\'" pdf-path))))
                      (with-temp-buffer
                        (when (= 0 (call-process "python3" nil t nil "-c" script))
                          (let ((result (string-trim (buffer-string))))
                            (unless (string-empty-p result) result)))))
                  (error nil)))))
          ;; Cache result for next time
          (when text
            (condition-case nil
                (with-temp-file txt-cache
                  (insert text))
              (error nil)))
          text))))

(defun tibetan-analysis--extract-segment-block (text seg-num)
  "Return only the block for SEG-NUM from multi-segment TEXT.
Recognizes org/markdown headings like `## Segment 4`, `** Segment 4`,
`# Segment 4`.  Matches up to the next heading at the same level, or
end of text.  Returns nil if no matching segment heading is found."
  (when (and text seg-num)
    (let ((case-fold-search t)
          (pattern (format "^\\(#+\\|\\*+\\)[ \t]+Segment[ \t]+%d\\b"
                           seg-num)))
      (when (string-match pattern text)
        (let* ((block-start (match-end 0))
               ;; Find next heading of any kind to bound the block
               (tail (substring text block-start))
               (next-heading
                (when (string-match "\n\\(#+\\|\\*+\\)[ \t]+Segment[ \t]+[0-9]+\\b"
                                    tail)
                  (match-beginning 0)))
               (block (if next-heading
                          (substring tail 0 next-heading)
                        tail)))
          (string-trim block))))))

(defun tibetan-analysis--filename-segment-number (basename)
  "Return the segment number encoded in BASENAME, or nil.
Recognises markers like Segment-04, segment_4, seg-4."
  (when (string-match
         "\\b\\(segment\\|seg\\)[-_ ]\\([0-9]+\\)"
         (downcase basename))
    (string-to-number (match-string 2 basename))))

(defun tibetan-analysis--find-reference-translations (_tibetan-text &optional seg-num source-text)
  "Search for reference translations for the current segment.

Two sources are consulted:
  (a) Inline 〔trans:N〕 … 〔/trans〕 blocks in SOURCE-TEXT (the raw
      class file), when it and SEG-NUM are provided.  These are the
      translations the user typed directly into the source file
      alongside each segment, and they take precedence because they
      represent the most current teaching/working translation for
      the passage.
  (b) External files in the Resources folder (.txt/.org/.md) and
      OCR'd PDFs whose filename hints at translation content.

If SEG-NUM is non-nil, Resources files are segment-scoped:
- Filenames containing `Segment-NN` / `seg-NN` are only included when NN
  matches SEG-NUM.
- Multi-segment files (like `Class-Translations.txt`) with `## Segment N`
  headings inside are narrowed to the matching block.
Files with neither filename marker nor internal segment heading are
included whole (e.g. the Blue Annals OCR).

Returns list of (source-name . translation-text) pairs."
  (let ((resources-dir (tibetan-analysis--find-resources-dir))
        (translations '()))
    ;; (a) Inline 〔trans:N〕 block from the source file.  Added first
    ;; so it ends up at the top of the list after `nreverse' below.
    (when (and source-text seg-num
               (fboundp 'tibetan-doc-format-get-translation))
      (condition-case nil
          (let ((inline (tibetan-doc-format-get-translation
                         source-text seg-num)))
            (when (and inline (not (string-empty-p inline)))
              (push (cons "Class Translation (inline)" inline)
                    translations)))
        (error nil)))
    (when resources-dir
      ;; Check for any text-based translation files
      (let ((files (directory-files resources-dir t "\\.\\(txt\\|org\\|md\\)$")))
        (dolist (file files)
          (let* ((basename (file-name-nondirectory file))
                 (file-seg (tibetan-analysis--filename-segment-number basename)))
            ;; Skip the wordlist (vocabulary, not translation)
            (unless (string-match-p "wordlist\\|wortliste\\|vocab" basename)
              (when (or (string-match-p "translat\\|übersetz\\|blue.?annals\\|class"
                                        (downcase basename))
                        file-seg)
                ;; Segment-scoped filenames: skip if wrong segment
                (unless (and seg-num file-seg (/= file-seg seg-num))
                  (condition-case nil
                      (with-temp-buffer
                        (insert-file-contents file nil 0 8000)
                        (let* ((full (string-trim (buffer-string)))
                               ;; If multi-segment file, narrow to current
                               ;; segment block; otherwise use the whole text.
                               (block (or (and seg-num
                                               (tibetan-analysis--extract-segment-block
                                                full seg-num))
                                          full))
                               (label (file-name-sans-extension basename))
                               (label (if (and seg-num
                                               (not file-seg)
                                               (tibetan-analysis--extract-segment-block
                                                full seg-num))
                                          (format "%s — Segment %d" label seg-num)
                                        label)))
                          (when (and block (not (string-empty-p block)))
                            (push (cons label block) translations))))
                    (error nil))))))))
      ;; Check for OCR'd PDFs (contain extractable text)
      (let ((pdfs (directory-files resources-dir t "\\.pdf$")))
        (dolist (pdf pdfs)
          (let ((basename (downcase (file-name-nondirectory pdf))))
            (cond
             ;; OCR'd Blue Annals extract
             ((string-match-p "ocr" basename)
              (let ((text (tibetan-analysis--extract-pdf-text pdf)))
                (when text
                  ;; Clean up OCR artifacts: normalize whitespace, strip headers
                  (let ((cleaned (replace-regexp-in-string
                                  "THE BLUE ANNALS\\s*\n" ""
                                  (replace-regexp-in-string
                                   "\\([0-9]+\\)\n" ""
                                   text))))
                    (push (cons (cond
                                 ((string-match-p "blue.?annals" basename)
                                  "Blue Annals (Roerich 1949)")
                                 (t (file-name-sans-extension
                                     (file-name-nondirectory pdf))))
                                (string-trim cleaned))
                          translations)))))
             ;; Large scanned PDFs without OCR — just note them
             ((and (> (file-attribute-size (file-attributes pdf)) 10000000)
                   (not (string-match-p "ocr" basename))
                   (string-match-p "blue\\|annals\\|deb.ther" basename))
              (push (cons "Blue Annals (Roerich 1949)"
                          "[Scanned PDF available — use BlueAnnals-Milarepa-OCR.pdf for extracted text]")
                    translations))
             ;; Other reference works could be detected here
             )))))
    (nreverse translations)))


;; Claude pipeline (prompt, request, parsing, migration, insertion,
;; vocabulary merge, Claude-specific readers / restorers) lives in
;; the sibling module.  Required here so the renderer and batch
;; code below can call it.
(require 'tibetan-analysis-claude)

(defun tibetan-analysis--ensure-vocabulary ()
  "Ensure vocabulary is loaded before analysis.

Short-circuits on the canonical `tibetan-glossaries-loaded' flag so a
batch reanalysis never re-emits the `Loading glossaries...' message
or replays the underlying I/O.  The hash-table-count fallback is
kept for sessions where the flag is not bound (older loaders)."
  (cond
   ;; Fast path: the loader already ran and recorded its success.
   ((and (boundp 'tibetan-glossaries-loaded) tibetan-glossaries-loaded)
    nil)
   ;; Hash already populated by some other path — trust it.
   ((and (boundp 'tibetan-comprehensive-vocabulary)
         tibetan-comprehensive-vocabulary
         (> (hash-table-count tibetan-comprehensive-vocabulary) 0))
    nil)
   (t
    (when (fboundp 'load-all-glossaries)
      (load-all-glossaries))
    (unless (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
      ;; Try loading from file
      (let ((glossary-file "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el"))
        (when (file-exists-p (expand-file-name glossary-file))
          (load-file (expand-file-name glossary-file))))))))

(defun tibetan-analysis--get-particle-annotation (word)
  "Get compact particle annotation for WORD.
Returns string like \\='(ERG)\\=' or \\='(LOC: if/when)\\=' or nil."
  (cond
   ;; Ergative
   ((member word '("ས" "གིས" "ཀྱིས" "གྱིས" "ཡིས"))
    "(ERG: by)")
   ;; Genitive
   ((member word '("འི" "གི" "ཀྱི" "གྱི" "ཡི"))
    "(GEN: of)")
   ;; Locative/Conditional
   ((string= word "ན")
    "(LOC: in/if/when)")
   ;; Dative
   ((string= word "ལ")
    "(DAT: to/at)")
   ;; Allative
   ((member word '("ར" "སུ" "ཏུ" "དུ"))
    "(ALL: toward)")
   ;; Ablative
   ((string= word "ནས")
    "(ABL: from/after)")
   ((string= word "ལས")
    "(ABL: from/than)")
   ;; Comitative
   ((string= word "དང")
    "(COM: and/with)")
   ;; Converbs
   ((member word '("སྟེ" "ཏེ" "དེ"))
    "(CONV: and then)")
   ((member word '("ཅིང" "ཞིང" "ཤིང"))
    "(CONV: while)")
   ;; Nominalizers
   ((member word '("པ" "བ"))
    "(NOM)")
   ((member word '("པོ" "བོ"))
    "(AGT: one who)")
   ;; Imperative
   ((member word '("ཅིག" "ཤིག" "ཞིག"))
    "(IMP)")
   ;; Topic
   ((string= word "ནི")
    "(TOP: as for)")
   (t nil)))

(defun tibetan-analysis--get-word-info (word multiword-units)
  "Get meaning and info for WORD, checking MULTIWORD-UNITS first.
Returns alist with keys: meaning, wylie, is-verb, verb-info."
  (let ((_info '())
        (meaning nil)
        (wylie nil))
    ;; Check multiword-units first
    (dolist (unit multiword-units)
      (when (string= (nth 2 unit) word)
        (let ((data (nth 3 unit)))
          (setq meaning (alist-get 'english data))
          (setq wylie (alist-get 'wylie data)))))
    ;; If not found, try vocabulary
    (unless meaning
      (when (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
        (setq meaning (gethash word tibetan-comprehensive-vocabulary))))
    ;; If still not found, try tibetan-lookup-word
    (unless meaning
      (when (fboundp 'tibetan-lookup-word)
        (setq meaning (tibetan-lookup-word word))))
    ;; Get wylie if not already set
    (unless wylie
      (when (fboundp 'tibetan-to-wylie-fixed)
        (condition-case nil
            (setq wylie (tibetan-to-wylie-fixed word))
          (error nil))))
    `((meaning . ,meaning)
      (wylie . ,wylie))))

(defun tibetan-analysis--format-word-with-wylie (word)
  "Return WORD in the canonical `SCRIPT [wylie]' display form.

Used by every generated-analysis section that mentions a Tibetan
word except the top-level `* Tibetan Text' section (which is kept
script-only by design).  Centralises the format so all sections
stay in lock-step; do NOT emit `script  wylie' pairs ad-hoc from
call sites.

Behaviour:
- If WORD is nil or empty, returns an empty string.
- If a Wylie conversion via `tibetan-to-wylie-fixed' is available
  and yields a non-empty string distinct from WORD, returns
  \"WORD [wylie]\".
- Otherwise returns WORD unchanged (e.g. WORD already Wylie, or
  converter unavailable, or converter echoes WORD)."
  (cond
   ((or (null word) (not (stringp word)) (string-empty-p word)) "")
   (t
    (let* ((w (string-trim word))
           (wylie (and (fboundp 'tibetan-to-wylie-fixed)
                       (condition-case nil
                           (tibetan-to-wylie-fixed w)
                         (error nil))))
           (wylie (and wylie (stringp wylie) (string-trim wylie))))
      (if (and wylie
               (not (string-empty-p wylie))
               (not (string= wylie w)))
          (format "%s [%s]" w wylie)
        w)))))

(defun tibetan-analysis--bialek-type (word)
  "Return the Bialek classification type string for WORD, or nil.

Single source of truth for particle / converb terminology in this
module.  Delegates to `tibetan-analyze-grammar-bialek' so the
Word/Particle List and the Grammatical Markers section stay in
lock-step.

Because bialek splits its input on tsheg (`་'), a tsheg-joined
compound like `བྱས་པས' gets split into (`བྱས' `པས') and neither
half alone carries enough context for the causal-converb detector
to fire.  We therefore try BOTH the original word and the
tsheg-removed form before giving up — so the full compound can
still be classified as a whole.  Returns the `type' field (index
2) of the first matching tuple."
  (when (and word (stringp word) (not (string-empty-p word))
             (fboundp 'tibetan-analyze-grammar-bialek))
    (let* ((try (lambda (s)
                  (car (condition-case nil
                           (tibetan-analyze-grammar-bialek s)
                         (error nil)))))
           (hit (or (funcall try word)
                    (funcall try (replace-regexp-in-string
                                  "་" "" word)))))
      (and hit (nth 2 hit)))))

(defun tibetan-analysis--render-clause-structure (words verbs multiword-units)
  "Return a string rendering of Round-2 clause structure for insertion
into the `** Clause Structure' section, or an empty string when no
analysis is available.

Uses `tibetan-analyze-round2' (clauses + NPs + argument structure).
Compact per-clause layout:

  Clause N [main|dependent · PARTICLE]: verb LEMMA [wylie] — meaning
    NPs: HEAD1 [wylie] (CASE), HEAD2 [wylie] (CASE), …
    Roles: role1 → HEAD1, role2 → HEAD2, …   (only when resolvable)

Every Tibetan token is routed through
`tibetan-analysis--format-word-with-wylie' so the output stays in
lock-step with the rest of the generated file."
  (if (not (and words verbs
                (fboundp 'tibetan-analyze-round2)))
      ""
    (let* ((r2 (condition-case nil
                   (tibetan-analyze-round2 words verbs multiword-units)
                 (error nil)))
           (clauses (alist-get 'clauses r2))
           (nps     (alist-get 'nps r2))
           (args    (alist-get 'argument-structure r2)))
      (if (not clauses)
          "[No clause structure detected]\n"
        (with-temp-buffer
          (let ((clause-idx 0))
            (dolist (clause clauses)
              (cl-incf clause-idx)
              (let* ((ctype (alist-get 'type clause))
                     (cv-type (alist-get 'converb-type clause))
                     (cv-part (alist-get 'converb-particle clause))
                     (verb    (alist-get 'verb clause))
                     (lemma   (and verb (alist-get 'lemma verb)))
                     (meaning (and verb (alist-get 'meaning verb)))
                     (c-start (alist-get 'start clause))
                     (c-end   (alist-get 'end clause))
                     (clause-nps
                      (cl-remove-if-not
                       (lambda (np)
                         (let ((s (alist-get 'start np))
                               (e (alist-get 'end np)))
                           (and s e c-start c-end
                                (>= s c-start) (<= e c-end))))
                       nps))
                     (clause-args (cl-find-if
                                   (lambda (a)
                                     (eq (alist-get 'clause a) clause))
                                   args)))
                (insert (format "Clause %d [%s" clause-idx
                                (if (eq ctype 'main) "main" "dependent")))
                (when (and (not (eq ctype 'main))
                           (or cv-type cv-part))
                  (insert " · ")
                  (when cv-part
                    (insert (tibetan-analysis--format-word-with-wylie
                             cv-part)))
                  (when (and cv-type
                             (not (and cv-part
                                       (string-match-p
                                        (regexp-quote (format "%s" cv-type))
                                        ""))))
                    (insert (format " (%s)" cv-type))))
                (insert "]")
                (when lemma
                  (insert (format ": verb %s"
                                  (tibetan-analysis--format-word-with-wylie
                                   lemma)))
                  (when (and meaning (not (string-empty-p meaning)))
                    (insert (format " — %s"
                                    (car (split-string meaning "," t))))))
                (insert "\n")
                (when clause-nps
                  (insert "    NPs: ")
                  (let ((first t))
                    (dolist (np clause-nps)
                      (unless first (insert ", "))
                      (setq first nil)
                      (let ((head (alist-get 'head np))
                            (kase (alist-get 'case np)))
                        (insert (tibetan-analysis--format-word-with-wylie
                                 head))
                        (insert (format " (%s)" (or kase "—"))))))
                  (insert "\n"))
                (let ((arg-list (and clause-args
                                     (alist-get 'arguments clause-args))))
                  (when arg-list
                    (insert "    Roles: ")
                    (let ((first t))
                      (dolist (a arg-list)
                        (unless first (insert ", "))
                        (setq first nil)
                        (let ((role (alist-get 'role a))
                              (np   (alist-get 'np a)))
                          (insert (format "%s → %s" role
                                          (tibetan-analysis--format-word-with-wylie
                                           (alist-get 'head np)))))))
                    (insert "\n"))))))
          (buffer-string))))))

(defun tibetan-analysis--get-grammatical-role (word root-form verb-table)
  "Determine grammatical role description for WORD with ROOT-FORM.

Uses VERB-TABLE for verb detection.  For particle / converb
classification, delegates to `tibetan-analyze-grammar-bialek' via
`tibetan-analysis--bialek-type' so the terminology matches the
Grammatical Markers section exactly (e.g. \\='GENITIVE (GEN)\\=',
\\='CONVERBIAL: CAUSAL CONVERB\\=').

Return value is a string such as \\='Transitive verb, CONVERBIAL:
CAUSAL CONVERB\\=', \\='GENITIVE (GEN)\\=', or \\='Noun\\=' — or
nil when nothing informative is available."
  ;; Strip Tibetan punctuation (shad, etc.) before comparison
  (let* ((word (replace-regexp-in-string "[།༎༏༐༑༔/]" "" word))
         (root-form (when root-form (replace-regexp-in-string "[།༎༏༐༑༔/]" "" root-form)))
         ;; Double-strip: for forms like sleb pa'i, strip-particles gives
         ;; `sleb pa` — we also need `sleb` so the verb DB lookup hits.
         (root-form-2 (when (and root-form (fboundp 'tibetan-strip-particles))
                        (let ((r2 (tibetan-strip-particles root-form)))
                          (and (not (string= r2 root-form))
                               (not (string-empty-p r2))
                               r2))))
         ;; Third strip: `tibetan-strip-particles' does not descend
         ;; through the bare nominaliser `པ'/`བ'.  Without this, a
         ;; verb-nominalised form like `སླེབ་པའི' resolves to
         ;; `སླེབ་པ' and the Hill-DB lookup never sees `སླེབ'.  Strip
         ;; a trailing `་པ'/`་བ'/`་པོ'/`་བོ' so the final verb lemma
         ;; surfaces for transitivity classification.
         (root-form-3 (let ((r (or root-form-2 root-form)))
                        (and r
                             (string-match-p "་\\(པོ\\|བོ\\|པ\\|བ\\)\\'" r)
                             (replace-regexp-in-string
                              "་\\(པོ\\|བོ\\|པ\\|བ\\)\\'" "" r))))
         (verb-info
          (or (and verb-table (gethash word verb-table))
              (and verb-table (gethash root-form verb-table))
              (and verb-table root-form-2 (gethash root-form-2 verb-table))
              (and verb-table root-form-3 (gethash root-form-3 verb-table))
              ;; Fallback: Hill 2010 verb database directly, so
              ;; forms like pham/'thon/sleb get tagged as verbs
              ;; even when the text-level verb extractor missed
              ;; them.  Use an alist shape compatible with the
              ;; (alist-get 'transitivity ...) accessor below.
              (and (fboundp 'tibetan-verb-lookup)
                   (or (tibetan-verb-lookup word)
                       (and root-form (tibetan-verb-lookup root-form))
                       (and root-form-2 (tibetan-verb-lookup root-form-2))
                       (and root-form-3 (tibetan-verb-lookup root-form-3))))))
         (bialek-type (tibetan-analysis--bialek-type word)))
    (cond
     ;; Recognised verb — combine transitivity with any bialek
     ;; classification carried by the word's particle tail.
     (verb-info
      (let* ((trans-raw (or (alist-get 'transitivity verb-info) ""))
             (trans (if (stringp trans-raw) trans-raw ""))
             ;; "Intransitive" contains "Transitive" as a substring —
             ;; check for "Intransitive" FIRST so pham/'thon/sleb etc.
             ;; aren't mislabelled as transitive.
             (verb-kind (cond
                         ((string-match-p "[Ii]ntransitive" trans) "Verb")
                         ((string-match-p "[Tt]ransitive" trans)
                          "Transitive verb")
                         (t "Verb"))))
        (if bialek-type
            (concat verb-kind ", " bialek-type)
          verb-kind)))
     ;; Non-verb: bialek classified it → use that label directly.
     (bialek-type bialek-type)
     ;; Last resort: treat as a noun.
     (t "Noun"))))

(defun tibetan-analysis--detect-verb-suffix (word _root-form)
  "Return a Bialek-terminology suffix label for WORD, or nil.

Thin adapter over `tibetan-analysis--bialek-type' so the suffix
label attached to a verb in the Sentence Structure / Word list
stays in lock-step with the Grammatical Markers section.  The
returned string, when non-nil, is prefixed with \", \" so callers
can concatenate it directly after a verb-kind label, e.g.
\\='Transitive verb, CONVERBIAL: CAUSAL CONVERB\\='.  Returns nil
when bialek has no classification for the word's particle tail
(e.g. a bare nominaliser on a verb stem, or an unusual suffix
bialek does not cover)."
  (let ((type (tibetan-analysis--bialek-type word)))
    (and type (concat ", " type))))

(defun tibetan-analysis--verb-morphology-gloss (root-form)
  "If ROOT-FORM (Tibetan script, particles stripped) is a verb in the
Hill 2010 database, return a morphology-aware English gloss.

Returned format, depending on whether ROOT-FORM is the lemma or an
inflected stem:

  Lemma form:        \"to do, to make\"
  Past stem:         \"pf. of byed — to do, to make\"
  Future stem:       \"ft. of byed — to do, to make\"
  Imperative stem:   \"imp. of byed — to do, to make\"
  Present stem:      (same as lemma when equal)

Returns nil if ROOT-FORM is not a verb. Used by the Word/Particle List
to make byas/byas pas/bstugs type entries show their underlying lemma
and canonical meaning, rather than falling back to dictionary glosses
like \"verb: do\" that hide the morphology."
  (when (and root-form
             (stringp root-form)
             (not (string-empty-p root-form))
             (fboundp 'tibetan-verb-lookup))
    (let* ((nom-stripped
            (replace-regexp-in-string "་?[པབ]$" "" root-form))
           ;; Which form did we actually find a verb for?
           (lookup-form
            (cond
             ((tibetan-verb-lookup root-form) root-form)
             ((and (not (string= nom-stripped root-form))
                   (not (string-empty-p nom-stripped))
                   (tibetan-verb-lookup nom-stripped))
              nom-stripped)
             (t nil)))
           (entry (and lookup-form (tibetan-verb-lookup lookup-form)))
           (lemma (and entry (cdr (assoc 'lemma entry))))
           (meaning (and entry (cdr (assoc 'meaning entry)))))
      (when (and lemma meaning)
        (let* ((past (cdr (assoc 'past_stem entry)))
               (future (cdr (assoc 'future_stem entry)))
               (imp (cdr (assoc 'imperative_stem entry)))
               (pres (cdr (assoc 'present_stem entry)))
               (lemma-wylie (when (fboundp 'tibetan-to-wylie-fixed)
                              (condition-case nil
                                  (string-trim (tibetan-to-wylie-fixed lemma))
                                (error nil))))
               ;; Which inflection is LOOKUP-FORM?
               (stem-label
                (cond
                 ((string= lookup-form lemma) nil)           ; lemma itself
                 ((and pres (string= lookup-form pres)) nil) ; present = lemma
                 ((and past (string= lookup-form past)) "pf.")
                 ((and future (string= lookup-form future)) "ft.")
                 ((and imp (string= lookup-form imp)) "imp.")
                 (t nil))))
          (if stem-label
              ;; Two-line format so the Word/Particle List renderer
              ;; puts the stem reference on line 1 after " — " and
              ;; the lemma gloss on an indented line 2, matching
              ;; Resources-style entries (e.g. "Pf. von X;\nmeaning").
              (format "%s of %s;\n%s"
                      stem-label
                      (or lemma-wylie lemma)
                      (string-trim meaning))
            (string-trim meaning)))))))

(defun tibetan-analysis--wylie-like-token-p (tok)
  "Return non-nil if TOK looks like a bare Wylie syllable rather than
a natural English/German word.  Used to strip compound-reference
tails that leak out of user wordlists, e.g. \"dice kha phung la thong\"
→ only \"dice\" is the real gloss."
  (and (stringp tok)
       (not (string-empty-p tok))
       (let ((lc (downcase tok)))
         (or
          ;; Wylie tokens often start with an apostrophe (e.g. 'dzugs, 'thon).
          (string-prefix-p "'" tok)
          ;; Closed set of short Wylie particles / very common syllables
          ;; that are unlikely to appear as content words in an English or
          ;; German gloss.
          (member lc
                  '("pa" "ba" "ma" "la" "na" "ra" "su" "du" "tu" "ru"
                    "nas" "las" "kyi" "kyis" "gyi" "gyis" "gi" "gis"
                    "yi" "ni" "te" "ste" "de" "so" "to" "no" "po" "bo"
                    "par" "bar" "cig" "zhig" "shig" "cing" "zhing" "shing"
                    "kyang" "yang" "dang" "dpe" "zhes" "ces" "ste"
                    "kha" "phung" "thong" "thub" "gyur" "sleb" "byed"
                    "pham" "rgyal" "dzugs" "dgon" "kho" "khos" "khyed"
                    "nga" "nyid" "gang" "khri" "mkha" "rig" "rigs"
                    "ko" "ron" "sa" "yul" "las" "rgyud" "brgyud"))
          ;; Wylie-distinctive digraphs at start or as whole token.
          (string-match-p "\\`\\(bzh\\|rdz\\|brts\\|bcu\\|bsk\\|bgy\\|mkh\\|'kh\\|sgr\\|rgy\\|brt\\)" lc)))))

(defun tibetan-analysis--strip-wylie-tail (gloss)
  "Remove trailing Wylie-only example tokens from GLOSS.
Some user wordlists embed compound cross-references directly after
the actual gloss (e.g. \"dice kha phung la thong\" where only
\"dice\" is the English meaning).  Walks tokens from the end, strips
consecutive Wylie-like tokens, and returns the trimmed gloss — but
only if at least one plain content token remains."
  (if (not (and gloss (stringp gloss) (not (string-empty-p gloss))))
      gloss
    (let* ((tokens (split-string (string-trim gloss) "[ \t]+" t))
           (n (length tokens))
           (i (1- n))
           (tail-count 0))
      (while (and (>= i 0)
                  (tibetan-analysis--wylie-like-token-p (nth i tokens)))
        (setq tail-count (1+ tail-count))
        (setq i (1- i)))
      (if (and (>= tail-count 2)
               (> (- n tail-count) 0))
          (string-join (cl-subseq tokens 0 (- n tail-count)) " ")
        gloss))))

(defun tibetan-analysis--cat-english-gloss (meaning)
  "Extract a short English gloss from MEANING for the CAT Gloss line.

MEANING is the enriched short-meaning produced by the Word/Particle
List renderer.  Handled shapes:

  1. Hill-morphology two-line form:  stem-ref + newline + gloss.
     Returns just the gloss.
  2. Curated bilingual entry with a DE // EN split on `//\\='.
     Returns the English side.
  3. Stem-reference only (German abbreviation, no English).
     Returns the stripped stem-ref phrase.
  4. Plain English gloss with sense separators.  Returns the first
     sense (up to `;\\=').
  5. RY-style `verb: do\\=' / `noun: X\\=' — strips the POS prefix.

Returns nil if MEANING is nil, empty, or a placeholder."
  (when (and meaning
             (stringp meaning)
             (not (string-empty-p meaning))
             (not (string= meaning "[look up]"))
             (not (string= meaning "[not found]")))
    (let ((m (string-trim meaning)))
      ;; If the gloss has a "German//English" split, prefer the English side.
      (when (string-match-p "//" m)
        (setq m (string-trim
                 (car (last (split-string m "//" t))))))
      ;; If the result begins with a stem reference followed by ";\n..."
      ;; (Hill morphology two-line form), drop the stem ref and keep
      ;; just the lemma meaning.
      (let ((case-fold-search t))
        (when (string-match
               "^\\(?:[Pp]f\\|[Pp]res\\|[Ff]t\\|[Ff]ut\\|[Ii]mp\\)\\.[ \t]+\\(?:of\\|von\\|zu\\)[ \t]+[^;]+;[ \t\n]*\\(.+\\)\\'"
               m)
          (setq m (string-trim (match-string 1 m)))))
      ;; Drop leading "1) "/"1. "/"1: " numbering.
      (setq m (replace-regexp-in-string "^[0-9]+[.):]\\s-*" "" m))
      ;; Drop RY-style POS prefixes ("verb: do", "noun: ...", "adj: ...").
      (setq m (replace-regexp-in-string
               "^\\(?:verb\\|noun\\|adj\\|adv\\|pron\\|part\\|particle\\):[ \t]*"
               "" m))
      ;; Keep only the first sense (before ';').
      (setq m (string-trim (car (split-string m ";" t))))
      ;; Squash internal whitespace/newlines.
      (setq m (replace-regexp-in-string "[ \t\n]+" " " m))
      ;; Strip any stray Wylie cross-reference tail that leaked in from
      ;; user wordlists (e.g. "dice kha phung la thong" → "dice").
      (setq m (tibetan-analysis--strip-wylie-tail m))
      (if (string-empty-p m) nil m))))

(defun tibetan-analysis--ing-form (verb)
  "Return a rough English -ing form of VERB.
Expects a bare infinitive stem like \"do\", \"make\", \"arrive\", \"lose\".
Handles the most common spelling adjustments (silent -e drop, doubled
final consonants, -ie → -y).  Intentionally simple — this is only ever
used for the best-effort CAT Gloss preview, not user-facing translation."
  (cond
   ((or (null verb) (string-empty-p verb)) verb)
   ;; Multi-word verb: "-ing" the first word.
   ((string-match-p " " verb)
    (let* ((words (split-string verb " " t))
           (head (car words))
           (tail (cdr words)))
      (string-join (cons (tibetan-analysis--ing-form head) tail) " ")))
   ;; tie → tying, lie → lying, die → dying
   ((string-match-p "ie\\'" verb)
    (concat (substring verb 0 -2) "ying"))
   ;; silent -e: make → making, give → giving
   ;; (but keep -ee, -ye, -oe like "see/dye/hoe")
   ((and (string-match-p "e\\'" verb)
         (not (string-match-p "[eyo]e\\'" verb)))
    (concat (substring verb 0 -1) "ing"))
   (t (concat verb "ing"))))

(defun tibetan-analysis--past-form (verb)
  "Return a best-effort English past participle of VERB.
Handles a small set of irregular classical Tibetan-relevant verbs
(\"do\" → \"done\", \"make\" → \"made\", \"go\" → \"gone\", \"come\" → \"come\",
\"lose\" → \"lost\", \"see\" → \"seen\", \"say\" → \"said\", \"be\" → \"been\",
\"arise\" → \"arisen\", \"fall\" → \"fallen\"); otherwise appends -ed with
the usual spelling adjustments.  Like `tibetan-analysis--ing-form', this
is only used for the CAT Gloss preview."
  (let* ((m '(("do" . "done") ("make" . "made") ("go" . "gone")
              ("come" . "come") ("lose" . "lost") ("see" . "seen")
              ("say" . "said") ("be" . "been") ("arise" . "arisen")
              ("fall" . "fallen") ("rise" . "risen") ("give" . "given")
              ("take" . "taken") ("stake" . "staked") ("wager" . "wagered")
              ("set" . "set") ("put" . "put") ("become" . "become")
              ("know" . "known") ("grow" . "grown") ("speak" . "spoken")
              ("write" . "written") ("hear" . "heard") ("tell" . "told")))
         (lower (and verb (downcase (string-trim verb))))
         (hit (and lower (assoc lower m))))
    (cond
     ((or (null verb) (string-empty-p verb)) verb)
     ;; Multi-word verb: past-form the head.
     ((string-match-p " " verb)
      (let* ((words (split-string verb " " t))
             (head (car words))
             (tail (cdr words)))
        (string-join (cons (tibetan-analysis--past-form head) tail) " ")))
     (hit (cdr hit))
     ;; -e already present: love → loved
     ((string-match-p "e\\'" verb) (concat verb "d"))
     ;; -y after consonant: try → tried
     ((string-match-p "[^aeiou]y\\'" verb)
      (concat (substring verb 0 -1) "ied"))
     (t (concat verb "ed")))))

(defun tibetan-analysis--build-cat-translation (vocab-pairs)
  "Build a CAT-suggested translation from VOCAB-PAIRS.
VOCAB-PAIRS is a list of (word . meaning) pairs.  MEANING is expected
to already be a short CAT-ready English gloss (see
`tibetan-analysis--cat-english-gloss').
Returns a rough English gloss with particle-aware phrasing.
Understands genitive (→ \\='of\\='), dative (→ \\='to/for\\='), topic
(→ \\='as for...\\='), causal converb -pas/-bas (→ \\='because ... /
by ...-ing\\='), sequential converb -te/-ste/-nas (→ \\='... and
then\\='), and other common Tibetan grammatical constructions."
  (let ((parts '())
        (prev-was-genitive nil))
    (dolist (pair vocab-pairs)
      (let* ((word (car pair))
             (meaning (cdr pair))
             ;; Strip punctuation for comparison
             (word-clean (replace-regexp-in-string "[།༎༏༐༑༔/]" "" word)))
        (cond
         ;; Skip entries with no useful meaning
         ((or (null meaning)
              (string= meaning "[look up]")
              (string= meaning "[not found]")))

         ;; Genitive particle (bare particle only — standalone ‘gi’,
         ;; ‘kyi’, ‘gyi’, ‘yi’, or ‘’i’).  Compound words with a
         ;; genitive suffix baked in (e.g. sleb pa'i, rnam pa'i) are
         ;; handled further down in the content-word branch so their
         ;; verb meaning is preserved.
         ((member word-clean '("གི" "ཀྱི" "གྱི" "ཡི" "འི"))
          (unless prev-was-genitive
            (push "of" parts))
          (setq prev-was-genitive t))

         ;; Topic marker: wrap as "As for X, ..."
         ((string= word-clean "ནི")
          (let ((so-far (string-join (nreverse parts) " ")))
            (setq parts (list (format "As for %s:" so-far)))))

         ;; Dative: "to/for"
         ((member word-clean '("ལ" "ར" "དུ" "ཏུ" "སུ" "རུ"))
          (push "to" parts)
          (setq prev-was-genitive nil))

         ;; Ablative: "from"
         ((member word-clean '("ནས" "ལས"))
          (push "from" parts)
          (setq prev-was-genitive nil))

         ;; Comitative: "and/with"
         ((string= word-clean "དང")
          (push "and" parts)
          (setq prev-was-genitive nil))

         ;; Ergative: "by"
         ((member word-clean '("གིས" "ཀྱིས" "གྱིས" "ཡིས" "ས"))
          (push "by" parts)
          (setq prev-was-genitive nil))

         ;; Regular content word: extract first short meaning.  Uses
         ;; the CAT English-gloss helper so Hill morphology glosses
         ;; ("pf. of X;\nmeaning") and German//English entries collapse
         ;; to a single short English sense.  Then apply converb-suffix
         ;; tweaks so forms like `byas pas`, `pham nas`, `'thon te`,
         ;; `sleb pa'i' read naturally in the CAT line.
         (t
          (let* ((cleaned
                  (or (tibetan-analysis--cat-english-gloss meaning)
                      (when (stringp meaning) (string-trim meaning))))
                 (trimmed (when cleaned
                            (string-trim
                             (car (split-string cleaned "," t))))))
            ;; If meaning already includes genitive phrasing, drop
            ;; the redundant "of" we pushed for the preceding particle.
            (when (and trimmed prev-was-genitive
                       (string-match-p "^\\(Of\\|of\\)" trimmed))
              (when (string= (car parts) "of")
                (pop parts)))
            (when trimmed
              ;; Converb / nominalizer+case suffixes embedded in the
              ;; content word.  Small set, conservative — we only
              ;; wrap the gloss if it looks like a verb ("to X").
              (let* ((verb-like
                      (string-match-p "\\`to[ \t]" trimmed))
                     (bare (if verb-like
                               (replace-regexp-in-string "\\`to[ \t]+" ""
                                                          trimmed)
                             trimmed))
                     (formatted
                      (cond
                       ((not verb-like) trimmed)
                       ;; Nominalized genitive (pa'i/ba'i):  "of X-ing".
                       ;; `ing-form' already appends "ing", so we use
                       ;; "%s" rather than "%sing" (otherwise we'd get
                       ;; "of doinging").
                       ((or (string-suffix-p "པའི" word-clean)
                            (string-suffix-p "བའི" word-clean))
                        (format "of %s" (tibetan-analysis--ing-form bare)))
                       ;; Nominalized terminative (par/bar):  "to X".
                       ((or (string-suffix-p "པར" word-clean)
                            (string-suffix-p "བར" word-clean))
                        (format "to %s" bare))
                       ;; Causal converb (pas/bas):  "by X-ing".
                       ((or (string-suffix-p "པས" word-clean)
                            (string-suffix-p "བས" word-clean))
                        (format "by %s" (tibetan-analysis--ing-form bare)))
                       ;; Sequential converbs (te/ste/nas/las):
                       ;; "having X'd, ..."
                       ((or (string-suffix-p "སྟེ" word-clean)
                            (string-suffix-p "ཏེ"  word-clean)
                            (string-suffix-p "ནས" word-clean)
                            (string-suffix-p "ལས" word-clean))
                        (format "having %s, " (tibetan-analysis--past-form bare)))
                       ;; Simultaneous converbs (cing/zhing/shing):
                       ;; "while X-ing".
                       ((or (string-suffix-p "ཅིང" word-clean)
                            (string-suffix-p "ཞིང" word-clean)
                            (string-suffix-p "ཤིང" word-clean))
                        (format "while %s" (tibetan-analysis--ing-form bare)))
                       ;; Bare nominalizer (pa/ba):  "(the) X-ing".
                       ((or (string-suffix-p "པ" word-clean)
                            (string-suffix-p "བ" word-clean))
                        (tibetan-analysis--ing-form bare))
                       (t trimmed))))
                (push formatted parts))))
          (setq prev-was-genitive nil)))))
    (if parts
        (string-join (nreverse parts) " ")
      "[Generate with C-c t g]")))

(defun tibetan-analysis--generate-particle-map (tibetan-text _particles verbs)
  "Generate a visual particle map for TIBETAN-TEXT.
PARTICLES is the parsed particles list, VERBS is the verb list.
Returns an org-formatted string with particles highlighted:
- =PARTICLE= for case markers (genitive, dative, etc.)
- ~CONVERB~ for converb particles
- *PARTICLE* for sentence-final particles
- [Ø ROLE] for zero-marked arguments

The particle token itself is upper-cased inside the markup so it
stays visible even when the surrounding buffer or export target
hasn't applied org's verbatim / code / bold faces — e.g. plain-text
viewers or PDF exports with a default theme that under-distinguishes
inline markup."
  (let* ((wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error tibetan-text)))
         ;; Define particle patterns to mark
         (case-particles '("'i" "gi" "kyi" "gyi" "yi"      ; genitive
                          "s" "gis" "kyis" "gyis" "yis"    ; ergative
                          "la" "r" "du" "tu" "su" "ru"     ; dative/terminative
                          "nas" "las"                       ; ablative
                          "dang"                            ; comitative
                          "ni"))                            ; topic marker
         (converb-particles '("cing" "zhing" "shing"       ; simultaneous
                             "ste" "te" "de"               ; sequential
                             "nas"))                        ; after-converb
         (final-particles '("ro" "so" "to" "no" "do" "'o" "ngo"))
         (result wylie))

    ;; Mark case particles with =PARTICLE=
    (dolist (p case-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "=%s=" (upcase p))
                    result)))

    ;; Mark converb particles with ~PARTICLE~
    (dolist (p converb-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "~%s~" (upcase p))
                    result)))

    ;; Mark sentence-final particles with *PARTICLE*
    (dolist (p final-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\(/\\|$\\)" (regexp-quote p))
                    (format "*%s*\\1" (upcase p))
                    result)))

    ;; Add zero-marker annotations for verbs that expect unmarked arguments
    (let ((zero-notes '()))
      (dolist (verb verbs)
        (when (and verb (listp verb) (consp (car verb)))
          (let* ((lemma (alist-get 'lemma verb))
                 (trans (alist-get 'transitivity verb))
                 (frame (alist-get 'case_frame verb)))
            ;; "Intransitive" contains "Transitive" as substring — check
            ;; Intransitive first so we don't add Ø-AGENT notes for
            ;; intransitive verbs like pham/'thon/sleb.
            (when (and lemma
                       (not (string-match-p "[Ii]ntransitive" (or trans "")))
                       (or (string-match-p "[Tt]ransitive" (or trans ""))
                           (string-match-p "Erg" (or frame ""))))
              (push (format "[Ø AGENT expected before %s]"
                           (condition-case nil
                               (tibetan-to-wylie-fixed lemma)
                             (error lemma)))
                    zero-notes)))))
      (when zero-notes
        (setq result (concat result "\n\n" (string-join (nreverse zero-notes) "\n")))))

    result))

(defun tibetan-analysis--strip-folio-markers (text)
  "Strip folio markers like (12a2), (16b5) etc. from TEXT.
These are editorial annotations from the Tibetan block print and
should not be processed as Tibetan text.  Also removes extra
whitespace left behind."
  (let ((cleaned (replace-regexp-in-string
                  "([0-9]+[ab][0-9]*)" ""
                  text)))
    ;; Clean up multiple spaces left by removal
    (replace-regexp-in-string "  +" " " (string-trim cleaned))))

(defun tibetan-analysis--filter-to-tibetan-lines (text)
  "Return TEXT with non-Tibetan content lines dropped.

Source files often interleave the Tibetan body with editorial
material that the analyser must NOT treat as input:
  - Parenthetical English descriptions on their own line,
    e.g. `(Homage / author's dedication verses)'.
  - Org-mode comment lines starting with `#'.
  - Blank separator lines.
  - Folio-marker-only lines.

Lines that contain no Tibetan character (anywhere in the U+0F00
block) are dropped entirely; lines that contain ANY Tibetan
character are kept verbatim.  The surviving lines are joined with
a single tsheg (U+0F0B) so that:
  1. `tibetan-parse-enhanced' — which splits on tsheg — tokenises
     the first word of each continuation line cleanly (a raw
     newline does NOT split, producing spurious compound tokens
     like `ལོ༎\\nརྒྱལ').
  2. `tibetan-to-wylie-fixed' emits a space between the two words
     (instead of the bare `lo//rgyal' it produces when the source
     contains only a newline, which looks like a typo to readers
     of the Wylie transliteration).

Without this filter, `tibetan-to-wylie-fixed' renders the
non-Tibetan portion as leading whitespace (producing a ~30-space
indent on sections like Wylie Transliteration) and
`tibetan-extract-vocabulary' tokenises the English words, matching
some of them against Wylie glossary entries (the English word
\"on\", for instance, matches the Wylie hash key and produces a
bogus \"set\" gloss)."
  (if (and text (stringp text))
      (let ((tibetan-char-re "[ༀ-࿿]")
            (kept '()))
        (dolist (line (split-string text "\n"))
          (when (string-match-p tibetan-char-re line)
            (push (string-trim line) kept)))
        (mapconcat #'identity (nreverse kept) "་"))
    text))

(defun tibetan-analysis--format-bilingual-gloss (gloss)
  "Reformat a German//English GLOSS for easy reading.
If GLOSS has the shape
  \"{DE-stem-ref}; {DE-meaning} // {EN-stem-ref}; {EN-meaning}\"
where both sides start with a matching verb-stem reference
(\"Pf. von ...\" + \"pf. of ...\", etc.), returns a two-line string
  \"{DE-stem-ref};\\n{DE-meaning} // {EN-meaning}\"
with the redundant English stem reference removed.
Plain \"German // English\" entries without a stem reference are
returned unchanged, since they're already compact.
Falls back to the original string when the pattern doesn't fit.

The stem-reference detection is deliberately conservative so we do
not mangle entries that happen to contain a period or semicolon for
unrelated reasons."
  (if (or (null gloss) (not (stringp gloss)) (not (string-match-p "//" gloss)))
      gloss
    (let* ((parts (split-string gloss "//"))
           (de (string-trim (nth 0 parts)))
           (en (string-trim (mapconcat #'identity (cdr parts) "//")))
           (stem-re "^\\(\\(?:[Pp]f\\|[Pp]res\\|[Ff]t\\|[Ff]ut\\|[Ii]mp\\)\\.[ \t]+\\(?:of\\|von\\|zu\\)[ \t]+[^;]+?\\)[ \t]*;[ \t]*\\(.*\\)$")
           (de-ref nil) (de-rest nil) (en-rest en))
      (when (and de (string-match stem-re de))
        (setq de-ref (string-trim (match-string 1 de)))
        (setq de-rest (string-trim (match-string 2 de))))
      (when (and de-ref en (string-match stem-re en))
        (setq en-rest (string-trim (match-string 2 en))))
      (cond
       ;; Resources-style stem-reference entry: split stem ref onto
       ;; its own line, drop redundant English stem ref.
       ((and de-ref de-rest (not (string-empty-p de-rest))
             en-rest (not (string-empty-p en-rest)))
        (format "%s;\n%s // %s" de-ref de-rest en-rest))
       (t gloss)))))

(defun tibetan-analysis--detailed-dict-is-particle-p (tibetan)
  "Return non-nil when TIBETAN is a pure case / converb particle.
Matches a single-syllable token (no tsheg / word break) whose text
appears in `tibetan-extract-vocab--particle-tails' — the same list
used by the MWU loop and vocabulary extractor.  Particle entries in
the Detailed Dictionary get a compact one-line rendering pointing
at the Particle Overview section instead of a verbose multi-source
dump."
  (and (stringp tibetan)
       (boundp 'tibetan-extract-vocab--particle-tails)
       (not (string-match-p "་" tibetan))
       (member (string-trim tibetan)
               tibetan-extract-vocab--particle-tails)))

(defun tibetan-analysis--render-detailed-dictionary
    (tibetan-text vocab-pairs &optional bialek-analysis)
  "Render the `** Detailed Dictionary' section for TIBETAN-TEXT.
Inserts into the current buffer.  TIBETAN-TEXT is the raw input
string; VOCAB-PAIRS is the segmentation's (word . gloss) alist used
as a legacy fallback when the multi-source helper is unavailable.
BIALEK-ANALYSIS, if non-nil, is the output of
`tibetan-analyze-grammar-bialek'; its grammatical tags let the
renderer split stem+particle compounds the same way the Interlinear
Gloss does, so a click on `[[term-mthu][mthu]]' in the Interlinear
lands on the `<<term-mthu>>' anchor emitted here (not a separate
`<<term-mthu-i>>' for the inflected form).  When the analysis is
omitted the renderer falls back to `tibetan-strip-particles' for a
narrower (unambiguous-particles-only) strip.

The section body is produced by `tibetan-vocab-extract-detailed'
when present, enriched via `tibetan-vocab-multisource-entries' for
the per-source breakdown (Resources / Steinert / Rangjung Yeshe /
DharmaMitra).  Entries backed by a curated Resources list get a
`★' marker on the head line.  Sanskrit is only emitted when the
source entry itself carries it.  The bilingual gloss formatter
keeps German // English pairs side by side."
  (insert "** Detailed Dictionary\n")
  (let ((vocab-list (condition-case nil
                        (when (fboundp 'tibetan-vocab-extract-detailed)
                          (tibetan-vocab-extract-detailed tibetan-text))
                      (error nil)))
        ;; Index bialek grammar tags so we can reuse the Interlinear's
        ;; stem/particle splitter.  (WORD → TAG-STRING), same shape the
        ;; Interlinear builds in `tibetan-interlinear-generate-gloss'.
        (bialek-by-word (make-hash-table :test 'equal))
        ;; Dedupe: track anchors already rendered this section so two
        ;; vocab entries that normalise to the same stem (e.g. a
        ;; segment containing both `mthu' and `mthu'i') only produce
        ;; one Detailed Dictionary block.
        (seen-anchors (make-hash-table :test 'equal)))
    (dolist (a bialek-analysis)
      (let ((word (nth 1 a))
            (type (nth 2 a)))
        (when (and word type)
          (puthash word type bialek-by-word))))
    (if vocab-list
        (progn
          (dolist (entry vocab-list)
            (let* ((raw-tibetan (plist-get entry :tibetan))
                   ;; Stem/particle split.  Two paths:
                   ;;   1. Prefer the Interlinear's splitter when we
                   ;;      have a bialek tag for this word — identical
                   ;;      semantics to the Interlinear anchor, so
                   ;;      `term-xxx' links round-trip correctly.
                   ;;   2. Fall back to `tibetan-strip-particles' when
                   ;;      no tag exists — conservative multi-char
                   ;;      particle strip keeps pre-existing behaviour.
                   (bialek-tag (gethash raw-tibetan bialek-by-word))
                   (stem-tibetan
                    (cond
                     ((and bialek-tag
                           (fboundp 'tibetan-interlinear--split-word-particle))
                      (car (tibetan-interlinear--split-word-particle
                            raw-tibetan bialek-tag)))
                     ((fboundp 'tibetan-strip-particles)
                      (let ((s (tibetan-strip-particles raw-tibetan)))
                        (if (and s (not (string-empty-p s))) s raw-tibetan)))
                     (t raw-tibetan)))
                   ;; Canonical tsheg-trim for the tibetan display — the
                   ;; stripper occasionally leaves a trailing `་'.
                   (tibetan
                    (replace-regexp-in-string "[་ \t]+$" ""
                                              (or stem-tibetan raw-tibetan)))
                   ;; Wylie for the stem.  Recompute from the stripped
                   ;; Tibetan rather than reusing the entry's `:wylie'
                   ;; (which was built from the particle-bearing form).
                   (wylie
                    (condition-case nil
                        (when (and tibetan (fboundp 'tibetan-to-wylie-fixed))
                          (downcase (string-trim
                                     (tibetan-to-wylie-fixed tibetan))))
                      (error (plist-get entry :wylie))))
                   ;; Multi-source lookup: already ranked (Thesaurus →
                   ;; Resources/Custom → corpus-specific → Hopkins2015
                   ;; → 84000Dict → RangjungYeshe → others → Bundled/
                   ;; DharmaMitra) and capped so the head of the list
                   ;; is the best-quality entry.  Sanskrit is emitted
                   ;; only when the source entry carries it natively
                   ;; AND it passes the real-Sanskrit filter.
                   (sources
                    (condition-case nil
                        (when (fboundp 'tibetan-vocab-multisource-entries)
                          (tibetan-vocab-multisource-entries tibetan))
                      (error nil)))
                   ;; Provided-list entry gets a ★ marker on the head
                   ;; line so students see at a glance that a curated
                   ;; gloss exists for this word.
                   (has-resources
                    (cl-some (lambda (s)
                               (let ((src (plist-get s :source)))
                                 (and src
                                      (string-prefix-p "Resources" src))))
                             sources))
                   ;; Genuine Sanskrit (if any source carries it) —
                   ;; displayed on the head line for instant visibility.
                   (sanskrit-on-head
                    (and (fboundp 'tibetan-vocab-find-sanskrit)
                         (tibetan-vocab-find-sanskrit sources)))
                   ;; Internal link target (matches the Interlinear
                   ;; Gloss's `[[term-xxx][wylie]]' link above).
                   (anchor
                    (and wylie (fboundp 'tibetan-vocab-term-anchor)
                         (tibetan-vocab-term-anchor wylie)))
                   ;; External Steinert URL — moved here from the
                   ;; Interlinear Gloss so the two-tier navigation is
                   ;; clear: Interlinear → Detailed Dictionary (shallow,
                   ;; same file); Detailed Dictionary → Steinert web
                   ;; (deep, external).
                   (steinert-url
                    (and wylie (fboundp 'tibetan-steinert-url-org)
                         (condition-case nil
                             (tibetan-steinert-url-org wylie)
                           (error nil)))))
              ;; Skip duplicates: a segment that contains `mthu' and
              ;; `mthu'i' both normalise to `term-mthu', render once.
              (unless (and anchor (gethash anchor seen-anchors))
                (when anchor (puthash anchor t seen-anchors))
              ;; Anchor target — invisible radio anchor that the
              ;; Interlinear link jumps to.  Kept on its own line so
              ;; it doesn't interfere with the visible head line.
              (when anchor
                (insert (format "<<%s>>\n" anchor)))
              ;; Dictionary-style head line:
              ;;   ◆ Tibetan [wylie] · Sanskrit ★ (Steinert ↗)
              (insert (format "◆ %s"
                              (if (and wylie (stringp wylie)
                                       (not (string-empty-p wylie))
                                       (not (string= wylie tibetan)))
                                  (format "%s [%s]" tibetan wylie)
                                (tibetan-analysis--format-word-with-wylie
                                 tibetan))))
              (when sanskrit-on-head
                (insert (format " · %s" sanskrit-on-head)))
              (when has-resources (insert " ★"))
              ;; External Steinert link as a small ↗ marker.  Clickable
              ;; org link syntax, kept short so the head line stays
              ;; scannable.
              (when steinert-url
                (if (string-match "\\[\\[\\([^]]+\\)\\]\\[" steinert-url)
                    (insert (format " ([[%s][Steinert ↗]])"
                                    (match-string 1 steinert-url)))))
              (if (tibetan-analysis--detailed-dict-is-particle-p tibetan)
                  ;; Particle: short compact entry, skip the multi-source dump.
                  ;; See `** Particle Overview' earlier in the file for
                  ;; the grammatical function.
                  (insert " — particle (see ** Grammar above)\n")
                (insert "\n")
                (if sources
                  (dolist (src sources)
                    (let* ((source-name (plist-get src :source))
                           (gloss (or (plist-get src :detailed)
                                      (plist-get src :primary)
                                      "[no gloss]"))
                           (skt (plist-get src :sanskrit))
                           (formatted
                            (tibetan-analysis--format-bilingual-gloss
                             gloss))
                           (lines (split-string formatted "\n")))
                      (insert (format "  [%s]\n" source-name))
                      (dolist (ln lines)
                        (insert (format "    %s\n" ln)))
                      ;; Sanskrit only when the entry itself supplied it.
                      (when (and skt
                                 (not (string-empty-p (string-trim skt))))
                        (insert (format "    Skt: %s\n" skt)))))
                ;; Fallback: legacy single-entry path if the
                ;; multi-source helper is unavailable.
                (let* ((detailed (plist-get entry :detailed))
                       (primary (plist-get entry :primary))
                       (sanskrit (plist-get entry :sanskrit))
                       (source (plist-get entry :source))
                       (meaning (or detailed primary "[not found]"))
                       (formatted
                        (tibetan-analysis--format-bilingual-gloss
                         meaning))
                       (lines (split-string formatted "\n")))
                  (dolist (ln lines)
                    (insert (format "  %s\n" ln)))
                  (when sanskrit
                    (insert (format "  Skt: %s\n" sanskrit)))
                  (when source
                    (insert (format "  [%s]\n" source))))))
              (insert "\n"))))
          (insert "\n"))
      ;; Fallback: use vocab-pairs if detailed system not available.
      (if vocab-pairs
          (progn
            (dolist (pair vocab-pairs)
              (let* ((word (car pair))
                     (meaning (cdr pair))
                     (root-form (tibetan-strip-particles word))
                     (head (if (and root-form
                                    (not (string-empty-p root-form))
                                    (not (string= root-form word)))
                               root-form
                             word)))
                (insert (format "◆ %s\n"
                                (tibetan-analysis--format-word-with-wylie
                                 head)))
                (insert (format "  %s\n\n" (or meaning "[not found]")))))
            (insert "\n"))
        (insert "[No dictionary entries available]\n\n")))))

(defun tibetan-analysis--render-grammar-section (tibetan-text particles verbs
                                                              bialek-analysis
                                                              &optional
                                                              claude-particles)
  "Render the merged `** Grammar' section body to the current buffer.

Pass 6b replaces three redundant sections (`** Particle Map',
`** Particle Overview', `** Grammatical Markers') with a single
`** Grammar' containing:

  *** Particle Map — the Wylie transliteration with particle markers
      (=CASE= for case particles, ~CONVERB~ for converbs, Ø for
      zero-marked arguments) — a quick visual scan of the grammar.

  *** Particles in This Segment — one line per Bialek particle
      detection: type, top-level Portfolio reference, translation
      hint.  Pass 6c augments this with per-occurrence function
      sub-IDs tagged by Claude + the matching Portfolio snippet,
      making the section self-contained for readers without access
      to the user's Portfolio source file.

TIBETAN-TEXT feeds the Particle Map's annotated Wylie.  PARTICLES
and VERBS come from the Bialek / verb-extraction pipeline.
BIALEK-ANALYSIS is the result of `tibetan-analyze-grammar-bialek'
— drives the compact particles list.

CLAUDE-PARTICLES, when non-nil, is a list of plists (parsed via
`tibetan-analysis--parse-claude-particles') carrying
`(:word W :particle P :sub-id ID :label L)' for each per-occurrence
function Claude identified.  When passed, each Bialek line gains a
specific sub-function heading and the matching Portfolio snippet
text.  When nil, falls back to the compact parser-only list."
  (insert "** Grammar\n")
  (insert "Three angles on the grammar of this segment: a visual\n")
  (insert "particle map, a compact reference of each particle\n")
  (insert "with its Portfolio section, and — in `** Claude Grammar'\n")
  (insert "below — a prose summary of the clause-chain.\n\n")
  ;; ------------------------------------------------------------------
  ;; Sub-section 1: Particle Map (annotated Wylie)
  ;; ------------------------------------------------------------------
  (insert "*** Particle Map\n")
  (insert "=CASE=: case marker · ~CONVERB~: converbial · Ø: zero-marked argument\n\n")
  (let ((annotated-wylie (tibetan-analysis--generate-particle-map
                          tibetan-text particles verbs)))
    (insert annotated-wylie)
    (insert "\n\n"))
  ;; ------------------------------------------------------------------
  ;; Sub-section 2: Particles in This Segment.
  ;;
  ;; Flow per bialek detection:
  ;;   1. Compute compact header line (particle type + Portfolio ref).
  ;;   2. Try to match against CLAUDE-PARTICLES on (word wylie, particle
  ;;      wylie) for a per-occurrence sub-ID + short label.
  ;;   3. On hit: look up the Portfolio snippet via
  ;;      `tibetan-interlinear-portfolio-function-snippet', emit the
  ;;      sub-section title + description inline.
  ;;   4. On miss: fall back to the translation-hint line.
  ;; ------------------------------------------------------------------
  (insert "*** Particles in This Segment\n")
  (if bialek-analysis
      (dolist (a bialek-analysis)
        (let* ((particle (nth 0 a))
               (word (nth 1 a))
               (type (nth 2 a))
               (trans-guide (nth 4 a))
               (function-desc (nth 3 a))
               (portfolio (nth 6 a))
               (word-wylie (condition-case nil
                               (downcase
                                (string-trim
                                 (tibetan-to-wylie-fixed word)))
                             (error nil)))
               (particle-wylie (condition-case nil
                                   (downcase
                                    (string-trim
                                     (tibetan-to-wylie-fixed particle)))
                                 (error nil)))
               (portfolio-key
                (and (fboundp 'tibetan-interlinear--portfolio-key)
                     (tibetan-interlinear--portfolio-key type)))
               ;; Find the Claude tuple (if any) that matches this
               ;; occurrence.  Match on WORD + PARTICLE Wylie.
               (claude-tuple
                (and claude-particles word-wylie particle-wylie
                     (cl-find-if
                      (lambda (p)
                        (and (equal (plist-get p :word) word-wylie)
                             (equal (plist-get p :particle)
                                    particle-wylie)))
                      claude-particles)))
               (sub-id (and claude-tuple (plist-get claude-tuple :sub-id)))
               (label  (and claude-tuple (plist-get claude-tuple :label)))
               (snippet (and portfolio-key sub-id
                             (fboundp 'tibetan-interlinear-portfolio-function-snippet)
                             (tibetan-interlinear-portfolio-function-snippet
                              portfolio-key sub-id))))
          ;; Header line: particle [wylie] in «word [wylie]» — TYPE [§X.Y]
          (insert (format "- %s in «%s» — %s"
                          (tibetan-analysis--format-word-with-wylie particle)
                          (tibetan-analysis--format-word-with-wylie word)
                          type))
          (when portfolio
            (insert (format "  [%s]" portfolio)))
          (insert "\n")
          ;; Claude-assigned sub-function + Portfolio snippet, if any.
          (cond
           ;; Full hit: sub-ID + Portfolio snippet (self-contained).
           (snippet
            (insert (format "  § %s %s — %s\n"
                            sub-id (car snippet)
                            (or label "")))
            (insert (format "    %s\n"
                            (tibetan-interlinear--truncate-para
                             (cdr snippet) 400))))
           ;; Partial hit: sub-ID from Claude but no Portfolio snippet
           ;; (Claude picked a broader ID than the parsed Portfolio
           ;; covers, or Portfolio cache is unavailable).
           (sub-id
            (insert (format "  § %s — %s\n" sub-id (or label ""))))
           ;; Fallback: translation hint from the bialek analyser.
           (t
            (let ((hint (or trans-guide function-desc)))
              (when (and hint (not (string-empty-p hint)))
                (insert (format "  → %s\n" hint))))))))
    (insert "[No grammatical markers detected]\n"))
  (insert "\n"))

(defconst tibetan-analysis--priority-section-order
  '("** Wylie Transliteration"
    "** Interlinear Gloss"
    "** Claude Translation"
    "** Grammar"
    "** Claude Grammar"
    "** Sentence Structure"
    "** Verb Classification (Hill 2010)")
  "Section headings (at org level-2) that should appear first in the
`* Auto-Analysis' output, in this exact order.  Any level-2 section
NOT listed here is kept and emitted afterwards in the order it was
generated.

Pass 6b (2026-04-22) redesign: the four redundant particle sections
— Particle Map, Particle Overview, Grammatical Markers, and the
segment-specific content of Claude Grammar — collapsed into a single
`** Grammar' section with three sub-headings (Particle Map, Particles
in This Segment, [future] Portfolio snippets).  Sentence Structure
and Clause Structure likewise merge into one `** Sentence Structure'
carrying per-clause verb + NP + role info.

`** Claude Grammar' remains a separate level-2 section placed
immediately after `** Grammar' in the read order — visually it
follows Grammar so the parser-side particle reference and Claude's
prose reading sit side by side without tangling the Claude write-
path.  A future pass can nest Claude Grammar into ** Grammar as a
sub-heading if desired; that requires rewiring the Claude scaffold
and is out of scope here.

Reader flow: Wylie → Interlinear Gloss (word-for-word) → Claude
Translation (fluent) → Grammar (particles + references) → Claude
Grammar (prose summary) → Sentence Structure (clause + arguments)
→ Verb Classification → Detailed Dictionary (deep reference).")

(defun tibetan-analysis--split-level2-sections (content)
  "Split CONTENT into an ordered list of level-2 section cons cells.
Each element is (HEADING . BODY), where HEADING is the full heading
line (e.g. `** Wylie Transliteration') and BODY is everything up to
the next `^\\*\\* ' heading or end of string.  Text that appears
before the first level-2 heading is returned under the special key
`t' (typically empty) so the caller can preserve it."
  (let ((result '())
        (preamble nil)
        (idx 0))
    (while (< idx (length content))
      (if (string-match "^\\*\\* .*$" content idx)
          (let* ((h-start (match-beginning 0))
                 (h-end (match-end 0))
                 (heading (match-string 0 content))
                 (next-start (or (and (string-match
                                       "^\\*\\* .*$" content (1+ h-end))
                                      (match-beginning 0))
                                 (length content)))
                 (body (substring content (1+ h-end) next-start)))
            (unless preamble
              (let ((pre (substring content 0 h-start)))
                (setq preamble pre)))
            (push (cons heading body) result)
            (setq idx next-start))
        ;; No more headings — everything that remains is trailing text.
        ;; If we never saw a heading, the whole thing is preamble.
        (unless preamble
          (setq preamble (substring content idx)))
        (setq idx (length content))))
    (cons (or preamble "") (nreverse result))))

(defun tibetan-analysis--extract-claude-grammar (sections)
  "If SECTIONS contains a `** Provided Translations' whose body holds a
`*** Claude Grammar' sub-heading, extract that subsection and return
a new list with:
  - a new `** Claude Grammar' level-2 entry carrying the promoted body
  - the original `** Provided Translations' with that sub-heading
    removed (the rest of its body preserved)
When no `*** Claude Grammar' is present the sections are returned
unchanged."
  (let ((found-body nil)
        (updated '()))
    (dolist (pair sections)
      (if (string= (car pair) "** Provided Translations")
          (let ((body (cdr pair)))
            (if (string-match
                 "^\\*\\*\\* Claude Grammar[ \t]*\n\\([\000-\377]*?\\)\\(\\(?:\n\\*\\*\\* \\)\\|\\'\\)"
                 body)
                (let* ((grammar-body (string-trim (match-string 1 body)))
                       (match-start (match-beginning 0))
                       (tail-start (match-beginning 2))
                       (new-body (concat (substring body 0 match-start)
                                         (substring body tail-start))))
                  (setq found-body grammar-body)
                  (push (cons (car pair) new-body) updated))
              (push pair updated)))
        (push pair updated)))
    (setq updated (nreverse updated))
    (if found-body
        (append updated
                (list (cons "** Claude Grammar"
                            (concat found-body "\n"))))
      updated)))

(defun tibetan-analysis--reorder-auto-content (content)
  "Reorder the level-2 sections of CONTENT into the priority order
defined by `tibetan-analysis--priority-section-order', keeping every
other section in its original relative position.

This also promotes `*** Claude Grammar' out of `** Provided
Translations' so it can slot into the priority list as a first-
class level-2 section."
  (let* ((split (tibetan-analysis--split-level2-sections content))
         (preamble (car split))
         (sections (tibetan-analysis--extract-claude-grammar (cdr split)))
         (priority-pairs '())
         (remaining '()))
    ;; Walk priority list and pull the matching sections out of SECTIONS.
    (dolist (p tibetan-analysis--priority-section-order)
      (let ((hit (cl-find p sections :key #'car :test #'string=)))
        (when hit
          (push hit priority-pairs)
          (setq sections (cl-remove p sections
                                    :key #'car :test #'string=)))))
    (setq priority-pairs (nreverse priority-pairs))
    (setq remaining sections)
    (concat preamble
            (mapconcat
             (lambda (pair)
               (concat (car pair) "\n" (cdr pair)))
             (append priority-pairs remaining)
             ""))))

(defvar tibetan-analysis--claude-particles-for-render nil
  "Dynamic binding: parsed Claude-particles list for the in-flight render.
Set by callers that have just read (or are about to re-insert) the
`*** Claude Particles' body — e.g. `tibetan-analysis-reanalyze-file'
reads the preserved Claude sections BEFORE calling
`tibetan-analysis-generate-content', so it can thread the parsed
particles through this var.  The Grammar renderer consults it to
attach per-occurrence Portfolio snippets; nil → compact parser-only
output, identical to Pass 6b behaviour.")

(defun tibetan-analysis-generate-content (tibetan-text &optional seg-id source-text source-file)
  "Generate auto-analysis content for TIBETAN-TEXT.
Returns the analysis as a string (org-mode formatted).

SEG-ID, if provided, enables segment-scoped reference translations
(per-segment Blue Annals files, narrowing multi-segment class files).

SOURCE-TEXT, if provided, is the full text of the source class file.
When SEG-ID resolves to a segment number, the 〔trans:SEG-NUM〕 block
inside SOURCE-TEXT is surfaced as an additional reference
translation.  This is how inline class-taught translations reach the
analysis buffer.  Batch callers that do not have the source buffer
handy may omit this argument; only the inline-trans surfacing is
affected, not the rest of the analysis.

SOURCE-FILE, if provided, is the absolute path to the source
document.  Its `#+TIBETAN_CORPUS:' header (if any) is read and
`tibetan-vocab--corpus' is dynamically bound for the duration of
analysis so the dictionary ranker promotes the matching Steinert
sub-dictionary into rank-3.  When omitted, the function falls back
to `buffer-file-name' (useful when called from inside a source-doc
buffer); when that too is nil, corpus-specific ranking simply
doesn't apply and the default ranking is used.

Claude-tagged per-particle functions (Pass 6c) are threaded in via
the dynamic `tibetan-analysis--claude-particles-for-render' — set
it with `let' around the call when Claude data is available."
  (let* ((resolved-src (or source-file
                           (and (boundp 'tibetan-current-source-file)
                                tibetan-current-source-file)
                           (buffer-file-name)))
         (corpus-val (and resolved-src
                          (fboundp 'tibetan-analysis--read-source-metadata)
                          (condition-case nil
                              (plist-get
                               (tibetan-analysis--read-source-metadata
                                resolved-src)
                               :corpus)
                            (error nil))))
         (tibetan-vocab--corpus
          (if (and corpus-val (stringp corpus-val)
                   (not (string-empty-p corpus-val)))
              corpus-val
            tibetan-vocab--corpus)))
  (condition-case err
      (progn
        ;; Drop non-Tibetan lines (English descriptions, # comments,
        ;; blank separators).  Required before Wylie conversion and
        ;; parser tokenisation so English words don't collide with
        ;; Wylie glossary keys.
        (setq tibetan-text (tibetan-analysis--filter-to-tibetan-lines
                            tibetan-text))
        ;; Strip folio markers before analysis (e.g. "(12a2)")
        (setq tibetan-text (tibetan-analysis--strip-folio-markers tibetan-text))

        ;; Ensure vocabulary is loaded
        (tibetan-analysis--ensure-vocabulary)

        (let* ((parsed (condition-case nil
                           (when (fboundp 'tibetan-parse-enhanced)
                             (tibetan-parse-enhanced tibetan-text))
                         (error nil)))
               (words (alist-get 'words parsed))
               (analysis (alist-get 'analysis parsed))
               (multiword-units (alist-get 'multiword-units parsed))
               (wylie-full (condition-case nil
                               (when (fboundp 'tibetan-to-wylie-fixed)
                                 (tibetan-to-wylie-fixed tibetan-text))
                             (error "[Wylie conversion error]")))
               (verbs (condition-case nil
                          (when (fboundp 'tibetan-extract-verbs-compound-aware)
                            (tibetan-extract-verbs-compound-aware tibetan-text words multiword-units))
                        (error nil)))
               (_zero-analysis (condition-case nil
                                   (when (and verbs multiword-units (fboundp 'tibetan-analyze-zero-markers))
                                     (tibetan-analyze-zero-markers verbs multiword-units words))
                                 (error nil)))
               (translation (condition-case nil
                                (when (fboundp 'tibetan-get-dharmamitra-translation)
                                  (tibetan-get-dharmamitra-translation tibetan-text))
                              (error nil)))
               (_claimed-indices (condition-case nil
                                     (when (fboundp 'tibetan-get-claimed-indices)
                                       (tibetan-get-claimed-indices multiword-units))
                                   (error nil)))
               (particles (when analysis (alist-get 'particles analysis)))
               ;; Build verb lookup table
               (verb-table (make-hash-table :test 'equal))
               ;; Extract vocabulary for DharmaMitra-style display
               (vocab-pairs (condition-case nil
                                (when (fboundp 'tibetan-extract-vocabulary)
                                  (tibetan-extract-vocabulary tibetan-text))
                              (error nil)))
               ;; Populated by the Word/Particle List loop below with
               ;; (word . short-English-gloss) pairs reflecting the same
               ;; Hill-morphology / Resources enrichment that shows up
               ;; in the Word/Particle List.  Reused by the CAT Gloss
               ;; section so the CAT line benefits from the enrichment
               ;; instead of pulling raw RY glosses.
               (enriched-vocab-pairs nil)
               ;; `word-clean' → t for every token whose primary
               ;; dictionary hit was Resources or Custom (the hand-
               ;; curated per-document vocabulary list).  Consumed
               ;; by the Interlinear renderer to prepend ★ to
               ;; authoritative entries, matching the marker the
               ;; legacy Word/Particle List used to show.
               (curated-words-hash (make-hash-table :test 'equal))
               (interlinear-marker nil))

          ;; Build verb lookup for quick access
          (dolist (verb verbs)
            (when (and verb (listp verb) (consp (car verb)))
              (let ((lemma (alist-get 'lemma verb)))
                (when lemma
                  (puthash lemma verb verb-table)))))

          (with-temp-buffer
            ;; ============================================================
            ;; SECTION 1: Wylie Transliteration
            ;; Reading the sequence first.
            ;; ============================================================
            (insert "** Wylie Transliteration\n")
            (insert (or wylie-full "[Not available]"))
            (insert "\n\n")

            ;; ============================================================
            ;; SECTION 1a: Interlinear Gloss + Particle Overview
            ;; Mark position — content inserted after the Word/Particle List
            ;; loop has built enriched-vocab-pairs and bialek-analysis.
            ;; ============================================================
            (setq interlinear-marker (copy-marker (point)))

            ;; ============================================================
            ;; SECTION 1b: Claude Translation (promoted to level 2)
            ;; Kept at the top so students see the fluent English rendering
            ;; right after the Wylie reading — before the word-by-word lists.
            ;; Populated asynchronously by `tibetan-analysis--insert-claude-sections'.
            ;; ============================================================
            (insert "** Claude Translation\n")
            (insert "[Requesting translation...]\n\n")

            ;; ============================================================
            ;; SECTION 2: Word / Particle List
            ;; Compact, numbered list for word-by-word reading in class.
            ;; Format:  N. Tibetan  wylie  [tag]  — short gloss [★ if Resources]
            ;; Glosses are pulled from the same layered lookup the Detailed
            ;; Dictionary uses (Resources → Custom → Bundled → Rangjung Yeshe
            ;; → DharmaMitra), so short glosses match the dictionary entries
            ;; below.  Falls back to vocab-pairs meaning if lookup misses.
            ;; Tag is shown only when informative (particle category, verb).
            ;; ============================================================
            ;; ============================================================
            ;; SECTION 2 (computation-only): build `enriched-vocab-pairs'
            ;; and `curated-words-hash' from the vocabulary layer.
            ;; ============================================================
            ;; Previously this loop also emitted a `** Word / Particle List'
            ;; section.  Removed 2026-04-21 per user feedback — the
            ;; Interlinear Gloss above carries the same information in a
            ;; denser, more readable form, and repeating it here just
            ;; duplicated the word-by-word listing.  We keep the ENTIRE
            ;; computation because:
            ;;   1. `enriched-vocab-pairs' is consumed by the CAT Gloss
            ;;      renderer (section 8b below) and by the Interlinear
            ;;      generator itself.
            ;;   2. `curated-words-hash' (new) is consumed by the Interlinear
            ;;      renderer to prepend ★ to Resources / Custom entries so
            ;;      students can spot authoritative, hand-curated glosses
            ;;      at a glance.
            (when vocab-pairs
              (let ((idx 1))
                (dolist (pair vocab-pairs)
                    (let* ((word (car pair))
                           (fallback-meaning (cdr pair))
                           ;; Strip shad/punctuation before lookup so ལ། → ལ,
                           ;; otherwise dictionary lookup misses and we fall
                           ;; through to noisy partial matches.
                           (word-clean (replace-regexp-in-string
                                        "[།༎༏༐༑ ]+$" ""
                                        (string-trim word)))
                           (root-form (tibetan-strip-particles word-clean))
                           (gram-role (tibetan-analysis--get-grammatical-role
                                       word-clean root-form verb-table))
                           ;; Formerly shown as `[TAG]' in the Word / Particle
                           ;; List heading (removed 2026-04-21).  Kept in the
                           ;; binding chain because `root-form' and
                           ;; `gram-role' remain useful further down for the
                           ;; `curated-source-p' / `verb-gloss' enrichment.
                           ;; Underscore prefix silences the byte-compiler.
                           (_tag (cond
                                  ((null gram-role) nil)
                                  ((member gram-role
                                           '("Noun" "?" "Unknown" "N")) nil)
                                  (t gram-role)))
                           ;; Primary lookup: route through the SAME multi-source
                           ;; pipeline that the Detailed Dictionary section uses,
                           ;; taking the first entry.  This is the Resources-first
                           ;; priority chain — without it, the Word/Particle List
                           ;; would silently pick a Steinert/IvesWaldo gloss while
                           ;; the Detailed Dictionary correctly shows the curated
                           ;; Resources entry, leaving the two sections out of
                           ;; lock-step.  Falls back to the stripped root form
                           ;; (e.g. སླེབ་པའི → སླེབ་པ).
                           (detailed-entry
                            (condition-case nil
                                (when (fboundp 'tibetan-vocab-multisource-entries)
                                  (or (car (tibetan-vocab-multisource-entries
                                            word-clean))
                                      (and root-form
                                           (not (string-empty-p root-form))
                                           (not (string= root-form word-clean))
                                           (car (tibetan-vocab-multisource-entries
                                                 root-form)))))
                              (error nil)))
                           ;; Multi-source labels Resources as "Resources (provided)";
                           ;; downstream checks need to recognise both that and the
                           ;; bare "Resources" / "Custom" labels older paths produced.
                           (source (and detailed-entry
                                        (plist-get detailed-entry :source)))
                           (curated-source-p
                            (and source
                                 (or (string-prefix-p "Resources" source)
                                     (string-prefix-p "Custom" source))))
                           ;; Resources/Custom entries are hand-curated and
                           ;; compact (German // English format), so use the
                           ;; full :detailed field — :primary is cut off at the
                           ;; first comma/period, which mangles German syn-lists
                           ;; and abbreviations like "Pf.".  For larger
                           ;; dictionaries (RY, DharmaMitra, Bundled), :primary
                           ;; is the appropriate short sense.
                           (clean-meaning
                            (when detailed-entry
                              (if curated-source-p
                                  (or (plist-get detailed-entry :detailed)
                                      (plist-get detailed-entry :primary))
                                (or (plist-get detailed-entry :primary)
                                    (plist-get detailed-entry :detailed)))))
                           ;; Fall back to the raw vocab-pairs meaning.
                           (raw-meaning (or clean-meaning
                                            (when (and fallback-meaning
                                                       (not (string= fallback-meaning
                                                                     "[look up]"))
                                                       (not (string= fallback-meaning
                                                                     "[not found]")))
                                              fallback-meaning)))
                           ;; Tidy the gloss without over-truncating.
                           (short-meaning
                            (when raw-meaning
                              (let ((m (string-trim raw-meaning)))
                                ;; Strip leading numbering like "1) " or "1. "
                                (setq m (replace-regexp-in-string
                                         "^[0-9]+[.):]\\s-*" "" m))
                                ;; For non-curated dictionaries, keep only the
                                ;; first sense (before ';' — proper sense
                                ;; separator).  Curated Resources entries are
                                ;; already compact, so leave intact.
                                (unless curated-source-p
                                  (setq m (string-trim
                                           (car (split-string m ";" t)))))
                                ;; Truncate only non-curated sources.  Resources
                                ;; and Custom entries are hand-written compact
                                ;; glosses — cutting them loses the critical
                                ;; "im Spiel einsetzen" / "to stake" sense.
                                (setq m (if (and (not curated-source-p)
                                                 (> (length m) 90))
                                            (concat (substring m 0 87) "…")
                                          m))
                                ;; Strip trailing Wylie cross-reference compounds
                                ;; that some user wordlists bake into the gloss
                                ;; (e.g. "dice kha phung la thong" → "dice").
                                (tibetan-analysis--strip-wylie-tail m))))
                           ;; Safety-net enrichment: if the gloss at this point
                           ;; is still a bare stem reference (e.g. "pf. of byed"),
                           ;; chase the base verb and append its meaning.  This
                           ;; catches cases where the text came through the
                           ;; vocab-pairs fallback path or any other route that
                           ;; bypassed `tibetan-vocab-lookup-detailed'-level
                           ;; enrichment. Skip if already enriched (em dash
                           ;; present after the reference).
                           (short-meaning
                            (if (and short-meaning
                                     (fboundp 'tibetan-vocab--extract-stem-reference)
                                     (fboundp 'tibetan-vocab--lookup-base-meaning)
                                     (not (string-match-p " — " short-meaning)))
                                (let ((stem-base
                                       (tibetan-vocab--extract-stem-reference
                                        short-meaning)))
                                  (if stem-base
                                      (let ((base-m
                                             (tibetan-vocab--lookup-base-meaning
                                              stem-base)))
                                        (if (and base-m
                                                 (not (string-empty-p base-m))
                                                 (not (tibetan-vocab--extract-stem-reference
                                                       base-m)))
                                            (format "%s — %s"
                                                    short-meaning
                                                    ;; Trim base gloss at first
                                                    ;; semicolon to keep it short.
                                                    (string-trim
                                                     (car (split-string base-m ";" t))))
                                          short-meaning))
                                    short-meaning))
                              short-meaning))
                           ;; Verb-morphology enrichment: when the stripped
                           ;; root is a verb in the Hill 2010 DB and the
                           ;; current gloss is either missing, unhelpful
                           ;; (e.g. RY "verb: do"), or short/non-curated,
                           ;; swap in a morphology-aware gloss built from
                           ;; the lemma and its stem class.  Resources and
                           ;; Custom entries are hand-curated and always win;
                           ;; we only augment if they don't already reference
                           ;; the verb lemma explicitly.
                           (verb-gloss
                            (tibetan-analysis--verb-morphology-gloss root-form))
                           (short-meaning
                            (cond
                             ;; No verb info → keep whatever we had.
                             ((null verb-gloss) short-meaning)
                             ;; No gloss at all yet → use verb gloss.
                             ((or (null short-meaning)
                                  (string-empty-p short-meaning))
                              verb-gloss)
                             ;; Curated Resources/Custom entry: don't replace
                             ;; the human-written bilingual gloss.
                             (curated-source-p
                              short-meaning)
                             ;; Current gloss already contains a stem
                             ;; reference ("pf. of X — ...") from the
                             ;; previous enrichment pass.  Leave it.
                             ((and (fboundp 'tibetan-vocab--extract-stem-reference)
                                   (tibetan-vocab--extract-stem-reference
                                    short-meaning))
                              short-meaning)
                             ;; Current gloss already echoes the Hill meaning.
                             ;; Look at the first *content* word (≥4 chars,
                             ;; not a function word) so "to" doesn't cause
                             ;; false matches between e.g. "to arrive" and
                             ;; "to extend to".
                             ((let* ((case-fold-search t)
                                     (words (split-string verb-gloss
                                                          "[ ,;—.]+" t))
                                     (distinctive
                                      (car (seq-filter
                                            (lambda (w)
                                              (and (>= (length w) 4)
                                                   (not (member (downcase w)
                                                                '("the" "verb"
                                                                  "noun")))))
                                            words))))
                                (and distinctive
                                     (string-match-p
                                      (regexp-quote distinctive)
                                      short-meaning)))
                              short-meaning)
                             ;; Otherwise, replace the non-curated gloss
                             ;; (typically RY's "verb: do"/"a loss") with
                             ;; the Hill-based morphology gloss.
                             (t verb-gloss))))
                      ;; Mark Resources / Custom entries in the curated hash
                      ;; so the Interlinear renderer can prepend ★.  The
                      ;; `source' variable is set earlier in this let* from
                      ;; `detailed-entry's :source plist field.
                      (when (and source
                                 (or (string-prefix-p "Resources" source)
                                     (string-prefix-p "Custom" source)))
                        (puthash word-clean t curated-words-hash))
                      ;; Record the enriched gloss for reuse by the CAT Gloss
                      ;; section and the Interlinear generator.  We store the
                      ;; ORIGINAL surface word (with particles still attached)
                      ;; so the CAT renderer can pattern-match on converb/case
                      ;; endings.
                      (push (cons word-clean short-meaning)
                            enriched-vocab-pairs)
                      (setq idx (1+ idx))))))
            (setq enriched-vocab-pairs (nreverse enriched-vocab-pairs))

            ;; ============================================================
            ;; SECTION 1a (deferred): Interlinear Gloss + Particle Overview
            ;; Now that enriched-vocab-pairs is ready, go back to the marker
            ;; position and insert the interlinear sections before Claude
            ;; Translation.
            ;; ============================================================
            (when (and enriched-vocab-pairs
                       (fboundp 'tibetan-interlinear-insert-sections))
              (let ((bialek-data (condition-case nil
                                     (when (fboundp 'tibetan-analyze-grammar-bialek)
                                       (tibetan-analyze-grammar-bialek tibetan-text))
                                   (error nil))))
                (save-excursion
                  (goto-char interlinear-marker)
                  (tibetan-interlinear-insert-sections
                   enriched-vocab-pairs
                   bialek-data
                   tibetan-text
                   vocab-pairs
                   curated-words-hash))))
            (when interlinear-marker
              (set-marker interlinear-marker nil))

            ;; ============================================================
            ;; SECTION 3b: Grammar (merged Particle Map + Particle
            ;; Overview + Grammatical Markers — Pass 6b, 2026-04-22).
            ;; Pass 6c adds the Claude-tagged particle functions +
            ;; Portfolio snippets when available via the dynamic var
            ;; `tibetan-analysis--claude-particles-for-render'.
            ;; ============================================================
            (let ((bialek-analysis (condition-case nil
                                       (when (fboundp 'tibetan-analyze-grammar-bialek)
                                         (tibetan-analyze-grammar-bialek tibetan-text))
                                     (error nil))))
              (tibetan-analysis--render-grammar-section
               tibetan-text particles verbs bialek-analysis
               tibetan-analysis--claude-particles-for-render))

            ;; ============================================================
            ;; SECTION 4: Sentence Structure (merged — Pass 6b, 2026-04-22)
            ;; ============================================================
            ;; Pass 6b merged the old skinny `** Sentence Structure'
            ;; (verb-then-arguments one-liner) into the Round-2 clause
            ;; structure — the Round-2 output ALREADY carries per-
            ;; clause verb + NPs + roles + converb dependency, which is
            ;; a strict superset of the old skinny line.  We rename
            ;; the merged view to `** Sentence Structure' because
            ;; that's the conceptual label students expect at this
            ;; level of analysis; `** Clause Structure' as a label is
            ;; retired.  The gate `tibetan-analysis-show-clause-
            ;; structure' still controls whether the section appears
            ;; at all (default t).
            (when tibetan-analysis-show-clause-structure
              (insert "** Sentence Structure\n")
              (let ((rendered (tibetan-analysis--render-clause-structure
                               words verbs multiword-units)))
                (if (and rendered (not (string-empty-p rendered)))
                    (insert rendered)
                  (insert "[Round-2 sentence structure unavailable]\n")))
              (insert "\n"))

            ;; ============================================================
            ;; SECTION 5: Verb Classification (Hill 2010) - detailed format
            ;; ============================================================
            (insert "** Verb Classification (Hill 2010)\n")
            ;; Only show full records here; `minimal' entries (from the
            ;; minor-verb / modal / reporting fallback sets) lack stem and
            ;; case-frame data — they'd render as noise.
            (let ((full-verbs (cl-remove-if (lambda (v)
                                              (alist-get 'minimal v))
                                            verbs)))
              (if full-verbs
                  (dolist (verb full-verbs)
                    (when (and verb (listp verb) (consp (car verb)))
                      (let* ((lemma (alist-get 'lemma verb))
                             (meaning (alist-get 'meaning verb))
                             (present (or (alist-get 'present_stem verb) "—"))
                             (past (or (alist-get 'past_stem verb) "—"))
                             (future (or (alist-get 'future_stem verb) "—"))
                             (imperative (or (alist-get 'imperative_stem verb) "—"))
                             (vol (or (alist-get 'volitionality verb) "?"))
                             (trans (or (alist-get 'transitivity verb) "?"))
                             (frame (or (alist-get 'case_frame verb) "?"))
                             (class (or (alist-get 'indigenous_class verb) "?")))
                        (insert (format "- %s"
                                        (tibetan-analysis--format-word-with-wylie
                                         lemma)))
                        (when meaning
                          (insert (format " — %s" meaning)))
                        (insert "\n")
                        (insert (format "  STEMS: %s / %s / %s / %s\n"
                                        (tibetan-analysis--format-word-with-wylie
                                         present)
                                        (tibetan-analysis--format-word-with-wylie
                                         past)
                                        (tibetan-analysis--format-word-with-wylie
                                         future)
                                        (tibetan-analysis--format-word-with-wylie
                                         imperative)))
                        (insert (format "  CLASS: %s, %s, %s\n" vol trans frame))
                        (insert (format "  TIBETAN: %s\n\n"
                                        (cond
                                         ((string= class "tha_dad_pa")
                                          "ཐ་དད་པ་ (transitive)")
                                         ((string= class "tha_mi_dad_pa")
                                          "ཐ་མི་དད་པ་ (intransitive)")
                                         (t "—")))))))
                (insert "[No Hill-DB verbs detected]\n")))
            (insert "\n")

            ;; NOTE: Zero-Marked NPs section removed - was producing confusing output

            ;; ============================================================
            ;; SECTION 7: Detailed Dictionary (rich entries with Sanskrit)
            ;; Rendered by the dedicated helper; kept as its own
            ;; function so the output stays testable in isolation and
            ;; the orchestrator can narrate sections one-per-call.
            ;; The bialek analysis is threaded through so the
            ;; renderer can split word+particle compounds the same
            ;; way the Interlinear does — anchoring `mthu'i' under
            ;; `<<term-mthu>>' so the Interlinear's jump link
            ;; resolves to the real stem entry.
            ;; ============================================================
            (let ((bialek-for-dd
                   (condition-case nil
                       (when (fboundp 'tibetan-analyze-grammar-bialek)
                         (tibetan-analyze-grammar-bialek tibetan-text))
                     (error nil))))
              (tibetan-analysis--render-detailed-dictionary
               tibetan-text vocab-pairs bialek-for-dd))

            ;; ============================================================
            ;; SECTION 8: Provided Translations (at end — combine step)
            ;; Shown last so students can compare their own word-by-word
            ;; rendering against external translations as a final check.
            ;; ============================================================
            (insert "** Provided Translations\n")
            ;; 8a: DharmaMitra AI translation
            (insert "*** DharmaMitra\n")
            (if (and translation
                     (not (string= translation "[Translation not available]"))
                     (not (string= translation "[DharmaMitra not loaded]")))
                (insert (format "%s\n" translation))
              (insert "[Not available — enable DharmaMitra access to generate]\n"))
            (insert "\n")
            ;; 8b: CAT rule-based gloss.  Prefer the enriched-vocab-pairs
            ;; built during the Word/Particle List pass — those meanings
            ;; already incorporate the Hill-morphology and Resources
            ;; enrichment, so the CAT line stops showing "defeat" for the
            ;; inflected past stem ཕམ and "to extend to" for སླེབ.  Falls
            ;; back to the raw vocab-pairs on legacy paths.
            (insert "*** CAT Gloss\n")
            (let* ((cat-input (or enriched-vocab-pairs vocab-pairs))
                   (cat-trans (when cat-input
                                (tibetan-analysis--build-cat-translation cat-input))))
              (insert (format "%s\n" (or cat-trans "[Generate with vocabulary analysis]"))))
            (insert "\n")
            ;; 8c: Claude Vocabulary section.  DharmaMitra-style word-by-word
            ;; analysis from Claude — the second tier in the three-tier
            ;; vocabulary ranking:
            ;;   1. Provided vocabulary (★ in the Word / Particle List)
            ;;   2. Claude (this section — contextual glosses with grammar)
            ;;   3. Steinert & Co. (URLs in the Word / Particle List)
            ;; Populated asynchronously by `tibetan-analysis--insert-claude-sections'.
            (insert "*** Claude Vocabulary\n")
            (insert "\n")
            ;; 8d: Claude Grammar section.  Translation is placed at the top
            ;; of the file (level 2, right after Wylie) so it's the first
            ;; thing students read; Grammar stays here at level 3 as a
            ;; sibling of DharmaMitra / CAT Gloss so the pedagogical block
            ;; is one cohesive unit.  Populated by
            ;; `tibetan-analysis--insert-claude-sections' from the same
            ;; Claude response that fills `** Claude Translation'.
            (insert "*** Claude Grammar\n")
            (insert "\n")
            ;; 8d: Reference translations from external sources
            (insert "*** Reference Translations\n")
            (let* ((seg-num (and seg-id
                                 (condition-case nil
                                     (tibetan-analysis--extract-segment-number seg-id)
                                   (error nil))))
                   (ref-translations
                    (tibetan-analysis--find-reference-translations
                     tibetan-text seg-num source-text)))
              (if ref-translations
                  (dolist (ref ref-translations)
                    (let ((source (car ref))
                          (text (cdr ref)))
                      (insert (format "**** %s\n%s\n\n" source text))))
                (insert "[Add reference translations here, e.g. from Blue Annals (Roerich), or other published translations]\n")))
            (insert "\n")

            ;; Reorder level-2 sections into the workshop-agreed
            ;; priority: Wylie → Particle Map → Interlinear Gloss →
            ;; Verb Classification → Claude Translation → Claude
            ;; Grammar, with the remaining sections retained in
            ;; their generated order afterwards.  Also promotes the
            ;; level-3 `*** Claude Grammar' out of `** Provided
            ;; Translations' so it can take its priority slot.
            (tibetan-analysis--reorder-auto-content (buffer-string)))))
    (error
     ;; On error, return a minimal analysis that STILL preserves the
     ;; most important user-facing sections:
     ;;   - Wylie Transliteration (computed independently, usually works)
     ;;   - Claude Translation placeholder (so `tibetan-auto-request-
     ;;     claude-translations' can still fire and fill it in)
     ;;   - Claude Grammar placeholder (likewise)
     ;; Followed by a visible `[ANALYSIS ERROR]' marker so the user can
     ;; spot the file and investigate.  Previously this emitted only
     ;; three stub sections (Wylie/Provided/Vocabulary) with `[Error]'
     ;; bodies, which meant a parser failure on ONE corner-case verb
     ;; form (e.g. YBh seg-30..34's `gyur pa'o') stripped an otherwise-
     ;; usable analysis file down to unusable scaffolding.
     (let ((wylie (condition-case nil
                      (when (and (stringp tibetan-text)
                                 (fboundp 'tibetan-to-wylie-fixed))
                        (tibetan-to-wylie-fixed tibetan-text))
                    (error nil))))
       (concat "** Wylie Transliteration\n"
               (or wylie "[Wylie conversion unavailable]")
               "\n\n"
               "** Claude Translation\n[Requesting translation...]\n\n"
               "** Claude Grammar\n\n\n"
               (format "** [Analysis error — partial file only]\nParser failure for this segment: %s\n\nThe structural analysis sections (Particle Map, Interlinear Gloss, Word/Particle List, Verb Classification, Grammatical Markers, Sentence Structure, Clause Structure, Detailed Dictionary) could not be generated.  The Tibetan Text and Claude sections above should still be usable.\n\nTo retry: `C-c u R' on this segment, or check the source segment's Tibetan for an unusual construction.\n"
                       (error-message-string err))))))))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-open-segment-analysis ()
  "Open or create analysis for current segment in side window.
If analysis exists, check if source has changed and warn."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data))
         ;; Capture full source buffer text so inline 〔trans:N〕
         ;; blocks from the class file can be surfaced as reference
         ;; translations.
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))

    (unless seg-data
      (error "Not in a segment"))

    (let* ((filepath (tibetan-analysis-get-filepath seg-id))
           (source-file (buffer-file-name))
           (exists (file-exists-p filepath)))

      (if exists
          ;; File exists - check sync and open
          (progn
            (unless (tibetan-analysis-check-sync filepath tibetan-text)
              (message "WARNING: Source text has changed since last analysis!"))
            (let ((buf (find-file-noselect filepath)))
              (with-current-buffer buf
                (tibetan-analysis-setup-faces)
                ;; Always land at the top of the analysis file.  Without
                ;; this, `save-place-mode' (or the mid-insert point left
                ;; by Claude's async callback before the last save)
                ;; would drop the cursor near the bottom — confusing
                ;; when you expect to see Tibetan Text first.
                (goto-char (point-min)))
              (display-buffer-in-side-window buf
                                             '((side . right)
                                               (window-width . 0.5)))))
        ;; Create new file
        (let* ((auto-content (tibetan-analysis-generate-content
                              tibetan-text seg-id source-text))
               (new-filepath (tibetan-analysis-create-file seg-id tibetan-text source-file auto-content)))
          (message "Created analysis file: %s" new-filepath)
          (let ((buf (find-file-noselect new-filepath)))
            (with-current-buffer buf
              (tibetan-analysis-setup-faces)
              (goto-char (point-min)))
            (display-buffer-in-side-window buf
                                           '((side . right)
                                             (window-width . 0.5))))
          ;; Request Claude translation asynchronously (never break on failure)
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text new-filepath)
            (error (message "Claude translation skipped: %s" (error-message-string err)))))))))

;;;###autoload
(defun tibetan-reanalyze-segment ()
  "Re-analyze current segment, preserving user notes.
Regenerates the Auto-Analysis section only."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data))
         ;; Same source-text capture as in `tibetan-open-segment-analysis'
         ;; so re-analysis picks up edits to the inline 〔trans:N〕 block.
         (source-text (buffer-substring-no-properties
                       (point-min) (point-max))))

    (unless seg-data
      (error "Not in a segment"))

    (let ((filepath (tibetan-analysis-get-filepath seg-id)))
      (unless (file-exists-p filepath)
        (error "No analysis file exists. Use C-c u A to create one first"))

      (when (yes-or-no-p "Re-analyze segment? (Auto section will be regenerated, notes preserved) ")
        (let ((auto-content (tibetan-analysis-generate-content
                             tibetan-text seg-id source-text)))
          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
          ;; Refresh the buffer if it's open
          (let ((buf (get-file-buffer filepath)))
            (when buf
              (with-current-buffer buf
                (revert-buffer t t))))
          ;; Request Claude translation asynchronously (never break on failure)
          (condition-case err
              (tibetan-analysis--request-claude-translation tibetan-text filepath)
            (error (message "Claude translation skipped: %s" (error-message-string err)))))))))

;; ============================================================================
;; BATCH RE-ANALYSIS
;; ============================================================================
;;
;; Entry points:
;;   `tibetan-analysis-reanalyze-file'  — headless single-file reanalysis.
;;   `tibetan-analysis-batch-reanalyze' — interactive batch over a folder.
;;
;; Both preserve:
;;   * `* My Notes'            (via `tibetan-analysis-get-user-sections')
;;   * `* Working Translation'
;;   * `* Footnotes'
;;   * `*** Claude' translation (captured before regen, restored after)
;;
;; CAT Gloss / DharmaMitra / Reference Translations are regenerated from
;; scratch — they are derived artefacts.  Set `:re-request-claude t' to
;; force a fresh Claude request instead of preserving the stored one.

(defun tibetan-analysis--read-section-body (filepath section-name)
  "Return the body of `* SECTION-NAME' in FILEPATH (nil if missing).
The body excludes the heading line itself and any trailing blank line.
Works for top-level (* …) sections."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (string-trim (buffer-substring-no-properties start end)))))))


(defun tibetan-analysis--seg-id-from-filename (filepath)
  "Return the numeric segment id encoded in FILEPATH's basename, or nil."
  (let ((base (file-name-nondirectory filepath)))
    (when (string-match "seg-\\([0-9]+\\)" base)
      (string-to-number (match-string 1 base)))))

(cl-defun tibetan-analysis-reanalyze-file
    (filepath &key source-file re-request-claude dry-run)
  "Re-run auto-analysis on an existing analysis FILEPATH.

Tibetan text is read from the file's own `* Tibetan Text' section;
segment id is parsed from the filename (`seg-NNN[-short].org').
SOURCE-FILE, when supplied, is the path of the original class file —
its buffer contents are scanned for inline 〔trans:N〕 blocks.

When RE-REQUEST-CLAUDE is non-nil, a fresh Claude request is dispatched
(asynchronously) after regeneration.  Otherwise the pre-existing
`*** Claude' translation is preserved.

With DRY-RUN non-nil, return a plist describing what would happen
without touching the file.  Otherwise return a plist:
  (:file F :seg-id ID :ok BOOL :error STR :claude-preserved BOOL)."
  (let* ((seg-id (tibetan-analysis--seg-id-from-filename filepath))
         (tibetan-text (tibetan-analysis--read-section-body
                        filepath "Tibetan Text"))
         (source-text
          (when (and source-file (file-readable-p source-file))
            (condition-case nil
                (with-temp-buffer
                  (insert-file-contents source-file)
                  (buffer-substring-no-properties (point-min) (point-max)))
              (error nil))))
         (existing-sections
          (and (not re-request-claude)
               (tibetan-analysis--read-claude-sections filepath)))
         (has-any-section
          (and existing-sections
               (or (plist-get existing-sections :translation)
                   (plist-get existing-sections :grammar)
                   (plist-get existing-sections :particles)
                   (plist-get existing-sections :context)))))
    (cond
     ((null seg-id)
      `(:file ,filepath :ok nil
              :error "Could not extract seg-id from filename"))
     ((or (null tibetan-text) (string-empty-p tibetan-text))
      `(:file ,filepath :seg-id ,seg-id :ok nil
              :error "No `* Tibetan Text' section or it is empty"))
     (dry-run
      `(:file ,filepath :seg-id ,seg-id :ok t :dry-run t
              :claude-preserved ,(and has-any-section t)))
     (t
      (condition-case err
          ;; Pass 6c: thread the preserved Claude Particles (if any)
          ;; through to the Grammar renderer via the dynamic var, so
          ;; the regenerated `*** Particles in This Segment' inherits
          ;; Claude's per-occurrence function-ID assignments and the
          ;; matching Portfolio snippets.  When no existing Claude
          ;; particles body is found, the dynamic binding is nil and
          ;; the renderer falls back to its compact parser-only list.
          (let* ((claude-particles-raw
                  (and existing-sections
                       (plist-get existing-sections :particles)))
                 (tibetan-analysis--claude-particles-for-render
                  (and claude-particles-raw
                       (fboundp 'tibetan-analysis--parse-claude-particles)
                       (tibetan-analysis--parse-claude-particles
                        claude-particles-raw)))
                 (auto-content (tibetan-analysis-generate-content
                                tibetan-text seg-id source-text)))
            (tibetan-analysis-regenerate-auto filepath tibetan-text
                                              auto-content)
            (when has-any-section
              (tibetan-analysis--restore-claude-sections
               filepath existing-sections))
            (when re-request-claude
              (condition-case e2
                  (tibetan-analysis--request-claude-translation
                   tibetan-text filepath)
                (error (message "Claude re-request failed for %s: %s"
                                (file-name-nondirectory filepath)
                                (error-message-string e2)))))
            `(:file ,filepath :seg-id ,seg-id :ok t
                    :claude-preserved ,(and has-any-section t)))
        (error
         `(:file ,filepath :seg-id ,seg-id :ok nil
                 :error ,(error-message-string err))))))))

(defun tibetan-analysis--folder-analysis-files (folder)
  "Return the list of seg-NNN*.org files under FOLDER, sorted by seg-id."
  (let* ((all (directory-files folder t "\\`seg-[0-9]+.*\\.org\\'"))
         (ordered
          (sort (copy-sequence all)
                (lambda (a b)
                  (< (or (tibetan-analysis--seg-id-from-filename a) 0)
                     (or (tibetan-analysis--seg-id-from-filename b) 0))))))
    ordered))

;;;###autoload
(cl-defun tibetan-analysis-batch-reanalyze
    (&key folder source-file re-request-claude dry-run)
  "Re-run auto-analysis on every `seg-NNN*.org' file in FOLDER.

FOLDER defaults to the analysis folder of the current buffer (see
`tibetan-analysis-get-folder').  SOURCE-FILE defaults to the current
buffer's file.  With RE-REQUEST-CLAUDE non-nil, a fresh Claude request
is dispatched for each file; otherwise the stored `*** Claude'
translation is preserved verbatim.  With DRY-RUN non-nil, no files
are written — a report is returned without touching anything.

User sections (My Notes, Working Translation, Footnotes) and the
`*** Claude' translation are preserved on every file.

Returns a plist summary:
  (:folder F :total N :ok N-ok :failed N-bad :results RESULTS)."
  (interactive
   (list :folder (let ((d (or (and (buffer-file-name)
                                   (tibetan-analysis-get-folder))
                              default-directory)))
                   (read-directory-name "Analysis folder: " d d t))
         :source-file (buffer-file-name)
         :re-request-claude
         (y-or-n-p "Also request a fresh Claude translation for each file? ")
         :dry-run nil))
  (let* ((folder (or folder
                     (and (buffer-file-name)
                          (tibetan-analysis-get-folder))
                     default-directory))
         (files (tibetan-analysis--folder-analysis-files folder))
         (results '())
         (n (length files))
         (i 0)
         (ok 0))
    (unless files
      (user-error "No analysis files (seg-NNN*.org) in %s" folder))
    (dolist (f files)
      (cl-incf i)
      (message "[%d/%d] %s %s"
               i n (if dry-run "dry-run" "reanalyzing")
               (file-name-nondirectory f))
      (let ((r (tibetan-analysis-reanalyze-file
                f
                :source-file source-file
                :re-request-claude re-request-claude
                :dry-run dry-run)))
        (push r results)
        (when (plist-get r :ok) (cl-incf ok))))
    (let ((summary `(:folder ,folder
                     :total ,n
                     :ok ,ok
                     :failed ,(- n ok)
                     :dry-run ,(and dry-run t)
                     :results ,(nreverse results))))
      (message "Batch reanalysis: %d/%d ok (%d failed)%s"
               ok n (- n ok) (if dry-run " — dry run" ""))
      summary)))

(provide 'tibetan-analysis-persist)
;;; tibetan-analysis-persist.el ends here
