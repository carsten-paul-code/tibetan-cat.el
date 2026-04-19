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
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n\n")
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
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
Preserves user sections (My Notes, Working Translation, Footnotes).
Updates hash and last-analyzed date."
  (let ((user-sections (tibetan-analysis-get-user-sections filepath))
        (hash (tibetan-analysis-compute-hash tibetan-text))
        (date (format-time-string "%Y-%m-%d")))
    (with-current-buffer (find-file-noselect filepath)
      ;; Update hash
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH: .+$" nil t)
        (replace-match (format "#+TIBETAN_HASH: %s" hash)))

      ;; Update last-analyzed date
      (goto-char (point-min))
      (when (re-search-forward "^#\\+LAST_ANALYZED: .+$" nil t)
        (replace-match (format "#+LAST_ANALYZED: %s" date)))

      ;; Update Tibetan text
      (let ((tib-bounds (tibetan-analysis-find-section-bounds (current-buffer) "Tibetan Text")))
        (when tib-bounds
          (goto-char (car tib-bounds))
          (delete-region (car tib-bounds) (cdr tib-bounds))
          (insert "* Tibetan Text\n")
          (insert tibetan-text)
          (insert "\n\n")))

      ;; Update Auto-Analysis section
      (let ((auto-bounds (tibetan-analysis-find-section-bounds (current-buffer) "Auto-Analysis")))
        (when auto-bounds
          (goto-char (car auto-bounds))
          (delete-region (car auto-bounds) (cdr auto-bounds))
          (insert "* Auto-Analysis\n")
          (insert ":PROPERTIES:\n")
          (insert ":GENERATED: t\n")
          (insert ":END:\n\n")
          (insert auto-content)
          (insert "\n\n")))

      ;; Restore user sections (in case they got clobbered)
      (dolist (section user-sections)
        (let ((name (car section))
              (content (cdr section)))
          (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) name)))
            (unless bounds
              ;; Section missing, add it at end
              (goto-char (point-max))
              (insert content)))))

      (save-buffer)
      (message "Re-analyzed segment. User notes preserved."))))

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
  "If BASENAME contains a segment marker like Segment-04 / seg-4, return the number."
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

;; ============================================================================
;; CLAUDE TRANSLATION (via gptel)
;; ============================================================================

(defvar tibetan-analysis--claude-system-prompt
  "You are a specialist in Classical Tibetan (chos skad) translation \
and philology, acting as a teaching assistant for a graduate classroom.

Produce THREE sections, separated by the exact markdown headings \
shown below, in this order and nothing else:

## Translation
A clear, idiomatic English rendering of the passage.
- Preserve technical Buddhist terminology (use Sanskrit where standard, \
e.g. dharma, bodhisattva, samādhi), with English gloss in parentheses \
on first occurrence only.
- Render particles and syntactic structures idiomatically, not literally.
- Honorific forms (zhu, gsol, mdzad, etc.) should be reflected in the \
register.
- Keep the translation fluent and readable, not word-for-word.
- When a glossary for this passage is provided in the user prompt, \
prefer those renderings for proper names and technical terms.
- When ±2 surrounding segments are provided, use them as context to \
resolve ambiguous pronouns, discourse particles, and sentence-internal \
reference — but translate ONLY the target passage.
- No commentary in this section.

## Vocabulary
Word-by-word analysis in DharmaMitra style.  For EACH word or \
compound in the passage, produce exactly one line with four fields \
separated by comma-space:

  wylie, grammatical-category, \"meaning\", contextual-note

Fields:
  1. wylie — EWTS romanisation, lowercase, e.g. \"mnyam med\".
  2. grammatical-category — one of: noun, proper noun, adjective, \
adverb, verb (hon.), verb, transitive verb, intransitive verb, \
converb, nominalizer, genitive, ergative/instrumental, terminative, \
ablative, locative, dative, particle, sentence-final particle, \
negation, conjunction, relative clause marker, or a similarly \
concise label.
  3. meaning — short English gloss in double quotes.  \
When a glossary entry is provided in the user prompt, prefer that \
rendering; otherwise give the contextually best fitting sense.
  4. contextual-note (optional) — e.g. \"epithet of ...\", \
\"honorific of byed pa\", \"marks the agent of mdzad\".  Omit \
the trailing comma when this field is absent.

Keep multi-word expressions (proper names, verb + nominaliser, \
particle compounds like \"pa'i\") together on one line.  \
Order follows the passage left-to-right.

Example:
  mnyam med, adjective, \"peerless\", epithet — literally \"without equal\"
  'gro ba'i, genitive, \"of beings\"
  mgon po, noun, \"protector\"

## Grammar
Explain the grammatical structure pedagogically for readers learning \
Classical Tibetan. Name the metalanguage explicitly (Ergativ, Ablativ, \
Dativ, Terminativ, Instrumental, Komitativ, Genitiv; converb type \
— ablative / causal / simultaneous / conditional / concessive / \
coordinative; nominalizer; finite verb; honorific stem). Reference the \
actual Tibetan forms in parentheses. If the passage is verse \
(consistent pāda-length lines bounded by shad), note the line structure \
and any recurring rhetorical formula spanning the stanza; if prose, \
focus on the clause chain and converb function within the narrative \
sequence. You will be given the parser's own analysis in the user \
prompt — treat it as ground truth for case and verb tagging; your \
job is to narrate it pedagogically, not to contradict it. If you \
disagree with a tag, flag the disagreement rather than silently \
overruling it.

Use only these three headings. No preamble, no closing remarks.

Genre, period and context hints (if any) are supplied below by the \
source file via `#+TIBETAN_CLAUDE_CONTEXT:' headers. Do NOT assume a \
specific genre unless such context is given."
  "System prompt for Claude translation + grammar + vocabulary of classical Tibetan.
Requests a three-section markdown response that is parsed by
`tibetan-analysis--parse-claude-sections' and placed into
`** Claude Translation' (at level 2, right after Wylie),
`*** Claude Vocabulary' (at level 3, inside Provided Translations,
before Grammar), and `*** Claude Grammar' (at level 3, inside
Provided Translations).  The Vocabulary section produces
DharmaMitra-style word-by-word analysis as the second tier
(after provided vocabulary, before Steinert dictionary entries).
Genre-specific assumptions come from the source file's
`#+TIBETAN_CLAUDE_CONTEXT:' headers, not from hardcoded defaults.")

;; ----------------------------------------------------------------------------
;; Source-aware prompt enrichment (workshop-ready)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-source-metadata (source-file)
  "Return a plist of prompt-relevant metadata extracted from SOURCE-FILE.
Keys:
  :title           value of the first `#+TITLE:' line
  :work            :WORK from the first :PROPERTIES: drawer
  :author          :AUTHOR from the first :PROPERTIES: drawer
  :sources         :SOURCES from the first :PROPERTIES: drawer
  :claude-context  list of all `#+TIBETAN_CLAUDE_CONTEXT:' values in order
  :vocab-file      value of `#+TIBETAN_VOCAB_FILE:' (relative to SOURCE-FILE)

Safe when SOURCE-FILE is nil or does not exist — returns an empty plist."
  (let (title work author sources ctx vocab)
    (when (and source-file (file-exists-p source-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents source-file)
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
              (setq title (string-trim (match-string 1))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TIBETAN_VOCAB_FILE:[ \t]*\\(.*\\)$" nil t)
              (setq vocab (string-trim (match-string 1))))
            (goto-char (point-min))
            (while (re-search-forward
                    "^#\\+TIBETAN_CLAUDE_CONTEXT:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (push val ctx))))
            (setq ctx (nreverse ctx))
            ;; First :PROPERTIES: drawer
            (goto-char (point-min))
            (when (re-search-forward "^:PROPERTIES:$" nil t)
              (let ((drawer-end (save-excursion
                                  (re-search-forward "^:END:$" nil t))))
                (when drawer-end
                  (save-restriction
                    (narrow-to-region (point) drawer-end)
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:WORK:[ \t]*\\(.*\\)$" nil t)
                      (setq work (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:AUTHOR:[ \t]*\\(.*\\)$" nil t)
                      (setq author (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:SOURCES:[ \t]*\\(.*\\)$" nil t)
                      (setq sources (string-trim (match-string 1)))))))))
        (error nil))) ;; close condition-case and outer `when source-file'
    (list :title title
          :work work
          :author author
          :sources sources
          :claude-context ctx
          :vocab-file vocab)))


(defun tibetan-analysis--source-file-from-analysis (analysis-file)
  "Return the absolute source file referenced by ANALYSIS-FILE.
Reads the `#+SOURCE:' header (an org link of the form
`[[file:../foo.org::*Segment N][…]]') and resolves it relative to
the directory of ANALYSIS-FILE.  Returns nil if nothing is found."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^#\\+SOURCE:[ \t]*\\[\\[file:\\([^]:]+\\)" nil t)
            (let ((rel (match-string 1)))
              (expand-file-name rel (file-name-directory analysis-file)))))
      (error nil))))

(defun tibetan-analysis--match-resources-vocab (tibetan-text vocab-file)
  "Return a list of (TERM . GLOSS) from VOCAB-FILE that occur in TIBETAN-TEXT.
VOCAB-FILE is an org file containing a table whose first column is the
Tibetan term and second column is the gloss."
  (let (matches)
    (when (and tibetan-text vocab-file (file-exists-p vocab-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents vocab-file)
            (goto-char (point-min))
            (while (re-search-forward
                    "^[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|"
                    nil t)
              (let ((term (string-trim (match-string 1)))
                    (gloss (string-trim (match-string 2))))
                (when (and (not (string-empty-p term))
                           ;; Skip header separator / "Term" header row
                           (not (string-match-p "\\`-+\\'" term))
                           (not (string= term "Term"))
                           ;; Must contain at least one Tibetan char
                           (string-match-p "[\u0F00-\u0FFF]" term)
                           (string-match-p (regexp-quote term) tibetan-text))
                  (push (cons term gloss) matches)))))
        (error nil)))
    (nreverse matches)))

(defun tibetan-analysis--read-analysis-parser-sections (analysis-file)
  "Return a plist of parser-output sections extracted from ANALYSIS-FILE.
Used to give Claude the tool's own grammatical analysis as grounding
for the Grammar section of the three-section response.  Keys:
  :grammatical-markers   body of `** Grammatical Markers'
  :clause-structure      body of `** Clause Structure'
  :verb-classification   body of `** Verb Classification (Hill 2010)'
  :sentence-structure    body of `** Sentence Structure'
Any missing section is nil.  Safe when ANALYSIS-FILE is nil or absent."
  (let (markers clauses verbs sentences)
    (when (and analysis-file (file-exists-p analysis-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents analysis-file)
            (cl-labels
                ((body-of (heading-re)
                   (save-excursion
                     (goto-char (point-min))
                     (when (re-search-forward heading-re nil t)
                       (forward-line 1)
                       (let ((start (point))
                             (end (save-excursion
                                    (if (re-search-forward
                                         "^\\*\\* [^ \t\n]\\|^\\* [^ \t\n]"
                                         nil t)
                                        (line-beginning-position)
                                      (point-max)))))
                         (let ((body (string-trim
                                      (buffer-substring-no-properties
                                       start end))))
                           (unless (string-empty-p body) body)))))))
              (setq markers   (body-of "^\\*\\* Grammatical Markers$")
                    clauses   (body-of "^\\*\\* Clause Structure$")
                    verbs     (body-of
                               "^\\*\\* Verb Classification[^\n]*$")
                    sentences (body-of "^\\*\\* Sentence Structure$"))))
        (error nil)))
    (list :grammatical-markers markers
          :clause-structure    clauses
          :verb-classification verbs
          :sentence-structure  sentences)))

(defun tibetan-analysis--format-parser-grounding (parser-sections)
  "Format PARSER-SECTIONS (plist from `--read-analysis-parser-sections')
as a single text block suitable for embedding in the Claude user
prompt.  Returns nil when every section is empty."
  (let ((parts '())
        (markers (plist-get parser-sections :grammatical-markers))
        (clauses (plist-get parser-sections :clause-structure))
        (verbs   (plist-get parser-sections :verb-classification)))
    (when markers
      (push (concat "Grammatical markers (parser output):\n" markers)
            parts))
    (when clauses
      (push (concat "Clause structure (parser output):\n" clauses)
            parts))
    (when verbs
      (push (concat "Verb classification (parser output):\n" verbs)
            parts))
    (when parts
      (concat "\n\nParser analysis (ground truth for case and verb "
              "tagging — narrate this pedagogically, flag disagreements "
              "rather than silently overruling):\n\n"
              (mapconcat #'identity (nreverse parts) "\n\n")))))

;; ----------------------------------------------------------------------------
;; Per-segment vocabulary matches (from the analysis file itself)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-word-particle-list (analysis-file)
  "Return the body of `** Word / Particle List' in ANALYSIS-FILE, or nil.
This is the compact, numbered vocabulary list the tool generates for
each segment: `N. Tibetan [wylie]  [tag] — short gloss'.  Safe when
ANALYSIS-FILE is nil or does not exist."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^\\*\\* Word / Particle List$" nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (save-excursion
                          (if (re-search-forward
                               (tibetan-analysis--claude-stop-re 2) nil t)
                              (line-beginning-position)
                            (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (or (string-empty-p body)
                          ;; Skip obvious placeholders
                          (string-match-p "\\`\\[" body))
                body))))
      (error nil))))

(defun tibetan-analysis--format-segment-vocabulary (analysis-file)
  "Return the per-segment vocabulary block for the Claude user prompt.
Draws from the `** Word / Particle List' section of ANALYSIS-FILE (the
tool's own per-segment matches, already enriched with Hill morphology
and Resources entries).  Returns nil when the section is missing or
empty so the prompt builder can skip it cleanly."
  (let ((body (tibetan-analysis--read-word-particle-list analysis-file)))
    (when body
      (concat "\n\nPer-segment vocabulary matches (from the analysis "
              "file — the tool's own layered lookup across Resources, "
              "Hopkins, Bialek, and bundled glossaries).  Prefer these "
              "glosses when they clearly fit; treat particle tags as "
              "authoritative.\n\n" body))))

;; ----------------------------------------------------------------------------
;; Surrounding-segments context (±2 neighbors from the same analysis folder)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--neighbor-analysis-file (analysis-file seg-id)
  "Return the existing `seg-SEG-ID*.org' neighbor of ANALYSIS-FILE, or nil.
Looks in the same directory; if multiple variants exist (e.g. with a
short-title suffix), picks the one whose basename matches the exact
`seg-NNN' prefix first, otherwise falls back to directory-files
ordering.  SEG-ID is an integer."
  (when (and analysis-file seg-id)
    (let* ((dir (file-name-directory analysis-file))
           (prefix (format "seg-%03d" seg-id))
           ;; Accept either `seg-012.org' or `seg-012-short-title.org'.
           (candidates
            (and (file-directory-p dir)
                 (directory-files
                  dir t
                  (concat "\\`"
                          (regexp-quote prefix)
                          "\\(\\.org\\'\\|-\\)")))))
      (car candidates))))

(defun tibetan-analysis--format-neighbor-segment
    (analysis-file seg-id offset)
  "Return a text block describing ANALYSIS-FILE's neighbor at OFFSET.
Reads `* Tibetan Text' (required) and `* Working Translation'
(optional) from the neighbor file.  OFFSET is the signed distance
(e.g. -1 for preceding, +1 for following).  Returns nil when the
neighbor does not exist or has no Tibetan text."
  (let* ((neighbor-id (+ seg-id offset))
         (neighbor (tibetan-analysis--neighbor-analysis-file
                    analysis-file neighbor-id)))
    (when (and neighbor (file-exists-p neighbor))
      (let* ((tibetan (tibetan-analysis--read-section-body
                       neighbor "Tibetan Text"))
             (working (tibetan-analysis--read-section-body
                       neighbor "Working Translation"))
             (label (format "Segment %d (%s %d)"
                            neighbor-id
                            (if (< offset 0) "−" "+")
                            (abs offset))))
        (when (and tibetan (not (string-empty-p (string-trim tibetan))))
          (concat label "\n"
                  "  Tibetan: " (string-trim tibetan)
                  (when (and working
                             (not (string-empty-p (string-trim working))))
                    (concat "\n  Working translation: "
                            (string-trim working)))))))))

(defun tibetan-analysis--format-surrounding-segments (analysis-file)
  "Return a ±2 surrounding-segments block for the Claude user prompt.
For each of offsets -2, -1, +1, +2 that resolves to an existing
neighbor file (see `--neighbor-analysis-file'), include its Tibetan
text and Working Translation (if non-empty).  Returns nil when no
neighbors could be resolved so the prompt stays lean for isolated
segments."
  (when analysis-file
    (let ((seg-id (tibetan-analysis--seg-id-from-filename analysis-file)))
      (when seg-id
        (let ((parts '()))
          (dolist (offset '(-2 -1 1 2))
            (let ((block (tibetan-analysis--format-neighbor-segment
                          analysis-file seg-id offset)))
              (when block (push block parts))))
          (when parts
            (concat "\n\nSurrounding segments (±2) — context only; "
                    "translate ONLY the target passage.  Use these to "
                    "resolve pronouns, discourse particles, and "
                    "sentence-internal reference across segment "
                    "boundaries.\n\n"
                    (mapconcat #'identity (nreverse parts) "\n\n"))))))))

(defun tibetan-analysis--build-claude-prompts
    (tibetan-text source-file &optional analysis-file)
  "Build (SYSTEM . USER) Claude prompts for TIBETAN-TEXT.
SOURCE-FILE, if non-nil, supplies genre/author/context metadata and a
Resources vocabulary file.  ANALYSIS-FILE, if non-nil, supplies four
forms of grounding:
  1. the parser's own output (grammatical markers, clause structure,
     verb classification) for the Grammar section;
  2. the tool's per-segment `** Word / Particle List' matches as a
     vocabulary hint for the Translation section;
  3. ±2 surrounding segments (Tibetan + Working Translation if present)
     from the same analysis folder so Claude can resolve anaphora and
     discourse without over-interpreting an isolated line;
  4. the file's own seg-id (used to resolve the neighbors in (3))."
  (let* ((meta   (tibetan-analysis--read-source-metadata source-file))
         (title  (plist-get meta :title))
         (work   (plist-get meta :work))
         (author (plist-get meta :author))
         (ctx    (plist-get meta :claude-context))
         (vocab-rel (plist-get meta :vocab-file))
         (vocab-file (and vocab-rel source-file
                          (expand-file-name
                           vocab-rel (file-name-directory source-file))))
         (glossary (and vocab-file
                        (tibetan-analysis--match-resources-vocab
                         tibetan-text vocab-file)))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error nil)))
         (src-block
          (let (parts)
            (when work   (push (format "Work: %s" work) parts))
            (when (and author (not (and work (string= work author))))
              (push (format "Author: %s" author) parts))
            (when (and title (not work)) (push (format "Title: %s" title) parts))
            (when ctx
              (push "Context from source file:" parts)
              (dolist (line ctx)
                (push (format "  - %s" line) parts)))
            (when parts
              (concat "\n\nSource metadata for this passage:\n"
                      (mapconcat #'identity (nreverse parts) "\n")))))
         (system (concat tibetan-analysis--claude-system-prompt
                         (or src-block "")))
         (glossary-block
          (when glossary
            (concat
             "\n\nGlossary for this passage — authoritative. "
             "Prefer these renderings in the Translation section; "
             "treat proper names and epithets as single tokens in the "
             "Grammar section.\n"
             (mapconcat (lambda (kv)
                          (format "  - %s = %s" (car kv) (cdr kv)))
                        glossary "\n"))))
         (vocab-block
          (tibetan-analysis--format-segment-vocabulary analysis-file))
         (surrounding-block
          (tibetan-analysis--format-surrounding-segments analysis-file))
         (grounding-block
          (tibetan-analysis--format-parser-grounding
           (tibetan-analysis--read-analysis-parser-sections analysis-file)))
         (user (concat "Classical Tibetan passage:\n\n"
                       tibetan-text
                       (if wylie (format "\n\nWylie: %s" wylie) "")
                       (or glossary-block "")
                       (or vocab-block "")
                       (or surrounding-block "")
                       (or grounding-block "")
                       "\n\nProduce the three sections now.")))
    (cons system user)))

(defun tibetan-analysis--read-authinfo-key (host)
  "Read password for HOST from ~/.authinfo or ~/.authinfo.gpg.
Parses the file directly for reliability.
Returns the password string or nil."
  (let ((authinfo-files (list (expand-file-name "~/.authinfo")
                              (expand-file-name "~/.authinfo.gpg"))))
    (cl-loop for file in authinfo-files
             when (file-exists-p file)
             do (condition-case nil
                    (with-temp-buffer
                      (insert-file-contents file)
                      (goto-char (point-min))
                      (when (re-search-forward
                             (format "machine %s.*?password \\(\\S-+\\)"
                                     (regexp-quote host))
                             nil t)
                        (cl-return (match-string 1))))
                  (error nil)))))

(defun tibetan-analysis--ensure-gptel-ready ()
  "Ensure gptel is configured with Anthropic backend and API key.
Sets up the backend if claude-integration.el was not loaded.
Reads the API key from ~/.authinfo or environment.
Returns non-nil if gptel is ready to use."
  (when (featurep 'gptel)
    ;; Step 1: Ensure API key is set
    (unless (and (boundp 'gptel-api-key)
                 gptel-api-key
                 (stringp gptel-api-key)
                 (not (string-empty-p gptel-api-key)))
      ;; Read directly from ~/.authinfo (most reliable)
      (let ((key (tibetan-analysis--read-authinfo-key "api.anthropic.com")))
        (when key
          (setq gptel-api-key key)))
      ;; Fallback: environment variable
      (unless (and (boundp 'gptel-api-key) gptel-api-key)
        (let ((env-key (getenv "ANTHROPIC_API_KEY")))
          (when (and env-key (not (string-empty-p env-key)))
            (setq gptel-api-key env-key)))))

    ;; Step 2: Ensure Anthropic backend is configured
    (when (and (boundp 'gptel-api-key)
               gptel-api-key
               (stringp gptel-api-key))
      (unless (and (boundp 'gptel-backend)
                   gptel-backend
                   ;; Check name field for Anthropic/Claude
                   (ignore-errors
                     (string-match-p "Claude\\|Anthropic"
                                     (format "%s" gptel-backend))))
        ;; Configure Anthropic backend
        (when (fboundp 'gptel-make-anthropic)
          (setq gptel-backend (gptel-make-anthropic "Claude"
                                :stream t
                                :key gptel-api-key))
          (unless (and (boundp 'gptel-model) gptel-model)
            (setq gptel-model "claude-sonnet-4-20250514"))))
      t)))

(defun tibetan-analysis--write-claude-failure-stub (analysis-file msg)
  "Write MSG into the *** Claude Translation section of ANALYSIS-FILE.
Only writes if that section is currently empty, missing, or already
holds a prior failure stub — never overwrites a real Claude response.
This is what callers should do from a queue :on-fail handler so the
user can see at a glance which segments still need a real Claude pass."
  (when (and analysis-file (file-exists-p analysis-file))
    (let* ((existing (ignore-errors
                       (tibetan-analysis--read-claude-sections
                        analysis-file)))
           (translation (and existing (plist-get existing :translation)))
           (trimmed (and translation (string-trim translation))))
      (when (or (null trimmed)
                (string-empty-p trimmed)
                (string-prefix-p "[Claude" trimmed)
                (string-prefix-p "[Requesting translation" trimmed))
        (let ((buf (or (find-buffer-visiting analysis-file)
                       (find-file-noselect analysis-file))))
          (with-current-buffer buf
            (when (fboundp 'tibetan-analysis--ensure-claude-headings)
              (tibetan-analysis--ensure-claude-headings buf))
            (when (fboundp 'tibetan-analysis--replace-claude-section-body)
              (tibetan-analysis--replace-claude-section-body
               buf "Claude Translation" msg))
            (save-buffer)))))))

(defun tibetan-analysis--claude-status-rate-limited-p (info)
  "Non-nil when gptel callback INFO indicates HTTP 429 (rate limited)."
  (let ((s (and (listp info) (plist-get info :status))))
    (and s (stringp s) (string-match-p "\\b429\\b" s))))

(defun tibetan-analysis--request-claude-translation
    (tibetan-text analysis-file &optional source-file)
  "Request a Claude translation of TIBETAN-TEXT asynchronously.
When the response arrives, insert it into ANALYSIS-FILE under the
*** Claude heading in the Provided Translations section.

If SOURCE-FILE is given (or can be derived from ANALYSIS-FILE's
`#+SOURCE:' link), its `#+TIBETAN_CLAUDE_CONTEXT:' headers,
:WORK/:AUTHOR properties and a Resources vocabulary file are folded
into the prompts so Claude gets genre / author / glossary context.

Requests go through `tibetan-claude-queue' so concurrent requests
are capped (see `tibetan-claude-queue-concurrency') and HTTP 429
responses are retried with exponential backoff (see
`tibetan-claude-queue-max-retries').  When retries are exhausted, a
visible placeholder is written into the *** Claude Translation
section so the segment is easy to find and re-run later via C-c u R.

Requires gptel and a configured Anthropic API key.  Never signals —
failures are reported via `message' and the placeholder."
  (require 'tibetan-claude-queue)
  (let ((label (and analysis-file
                    (file-name-nondirectory analysis-file))))
    (tibetan-claude-queue-submit
     (lambda (done)
       (condition-case err
           (progn
             (unless (and (featurep 'gptel) (fboundp 'gptel-request))
               (error "gptel not loaded"))
             (tibetan-analysis--ensure-gptel-ready)
             (let* ((src (or source-file
                             (tibetan-analysis--source-file-from-analysis
                              analysis-file)))
                    (prompts (tibetan-analysis--build-claude-prompts
                              tibetan-text src analysis-file))
                    (system-prompt (car prompts))
                    (user-prompt   (cdr prompts)))
               (gptel-request
                user-prompt
                :system system-prompt
                :callback
                (lambda (response info)
                  (cond
                   ;; Success: have a non-empty response body.
                   ((and response (stringp response)
                         (not (string-empty-p response)))
                    (condition-case e
                        (tibetan-analysis--insert-claude-translation
                         response analysis-file)
                      (error
                       (message "Claude insert failed for %s: %s"
                                (or label "<file>")
                                (error-message-string e))))
                    (funcall done '(:status ok)))
                   ;; HTTP 429 — let the queue retry.
                   ((tibetan-analysis--claude-status-rate-limited-p info)
                    (funcall done '(:status rate-limited)))
                   ;; Anything else — non-retryable from our point of view.
                   (t
                    (funcall done
                             (list :status 'error
                                   :error (format "%s"
                                                  (or (and (listp info)
                                                           (plist-get info :status))
                                                      "no response")))))))) ))
         (error
          (funcall done (list :status 'error
                              :error (error-message-string err))))))
     :label label
     :on-fail
     (lambda (status)
       (let* ((kind (plist-get status :status))
              (msg (cond
                    ((eq kind 'rate-limited)
                     "[Claude request failed: rate-limited (HTTP 429) after retries — re-run C-c u R later]")
                    (t (format "[Claude request failed: %s — re-run C-c u R later]"
                               (or (plist-get status :error) "unknown"))))))
         (tibetan-analysis--write-claude-failure-stub
          analysis-file msg))))))

(defun tibetan-analysis--parse-claude-sections (response)
  "Split RESPONSE on `## Translation/Vocabulary/Grammar/Context' markdown headings.
Returns a plist `(:translation STR :vocabulary STR :grammar STR :context STR)'.
Missing sections are nil (not empty string) so the writer can leave
the old org body in place when Claude omitted a section.  When
RESPONSE contains no recognised heading, the whole (trimmed) string is
returned as `:translation' — this keeps backwards compatibility with
legacy single-translation responses."
  (let ((result (list :translation nil :vocabulary nil :grammar nil :context nil))
        (re "^## \\(Translation\\|Vocabulary\\|Grammar\\|Context\\)[ \t]*$"))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (if (not (re-search-forward re nil t))
            ;; Legacy response — whole thing is the translation.
            (setq result (plist-put result :translation
                                    (string-trim response)))
          ;; Structured response — walk the headings.
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              (push (list (intern (downcase (match-string 1)))
                          (match-end 0))
                    matches))
            (setq matches (nreverse matches))
            (cl-loop for (cell . rest) on matches
                     for key = (car cell)
                     for start = (cadr cell)
                     for end = (if rest
                                   (save-excursion
                                     (goto-char (cadr (car rest)))
                                     (beginning-of-line)
                                     (point))
                                 (point-max))
                     for body = (string-trim
                                 (buffer-substring-no-properties
                                  start end))
                     do (setq result
                              (plist-put result
                                         (intern (format ":%s" key))
                                         (and (not (string-empty-p body))
                                              body))))))))
    result))

(defconst tibetan-analysis--claude-section-order
  '((:translation "Claude Translation" 2)
    (:vocabulary  "Claude Vocabulary"  3)
    (:grammar     "Claude Grammar"     3))
  "Canonical order, heading names, and org levels for Claude sections.
Each entry is (KEY HEADING LEVEL).  The Translation sits at level 2
right after `** Wylie Transliteration' for high-visibility reading;
Vocabulary and Grammar stay at level 3 inside `** Provided
Translations'.  Vocabulary (DharmaMitra-style word-by-word from Claude)
sits between DharmaMitra and Claude Grammar.  The writer, reader,
scaffolding, and migration all consult this list so levels stay
consistent everywhere.")

(defun tibetan-analysis--claude-heading-re (heading level)
  "Regexp that anchors `HEADING' at org LEVEL at beginning-of-line."
  (format "^%s %s$"
          (regexp-quote (make-string level ?*))
          (regexp-quote heading)))

(defun tibetan-analysis--claude-stop-re (level)
  "Regexp matching the start of any heading at org LEVEL or shallower."
  ;; `*\\{1,N\\}' plus a mandatory non-`*' follower so `**' doesn't
  ;; match inside `***'.
  (format "^\\*\\{1,%d\\}[^*\n]" level))

(defun tibetan-analysis--claude-segment-layout-p (buffer)
  "Return non-nil if BUFFER uses the segment-level analysis layout.
The distinguishing marker is `** Wylie Transliteration' at org
level 2 — present in per-segment analysis files (seg-NNN*.org) but
not in sentence-level files (sent-NNN*.org), which use `* Wylie' at
level 1.  Empty / brand-new buffers default to segment layout so
fresh scaffolds get Translation promoted to level 2."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (or (re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
          ;; Fresh scaffold not yet populated — treat as segment.
          (= (buffer-size) 0)))))

(defun tibetan-analysis--migrate-legacy-claude-headings (buffer)
  "Migrate legacy `*** Claude' / `*** Claude Translation' in BUFFER.
Segment-layout buffers (with `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
2. Move `*** Claude Translation' (level-3, legacy placement under
   `** Provided Translations') to a new `** Claude Translation'
   (level-2) directly after `** Wylie Transliteration', preserving
   its body.

Sentence-layout buffers (no `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
No level promotion — the sentence layout keeps Claude at level 3.

Both branches are no-ops when nothing to migrate."
  (with-current-buffer buffer
    (save-excursion
      ;; Step 1 (both layouts): bare `*** Claude' → `*** Claude Translation'
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\*\\* Claude$" nil t)
        (replace-match "*** Claude Translation" t t))
      ;; Step 2 (segment only): promote level-3 Translation → level-2
      (when (tibetan-analysis--claude-segment-layout-p buffer)
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Translation$" nil t))
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Translation$" nil t)
            (let* ((heading-start (line-beginning-position))
                   (body-start (progn (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties body-start body-end))))
              (delete-region heading-start body-end)
              (tibetan-analysis--insert-claude-translation-heading
               (current-buffer) body))))))))

(defun tibetan-analysis--insert-claude-translation-heading (buffer body)
  "Insert `** Claude Translation' with BODY into BUFFER at the top.
Placement rule: right after `** Wylie Transliteration' and its body
if that heading exists; otherwise right after the first `* ' top-level
heading; otherwise at point-max.  BODY may be empty — the heading is
still created with two trailing newlines."
  (with-current-buffer buffer
    (save-excursion
      (let ((content (if (and body (not (string-empty-p (string-trim body))))
                         (format "** Claude Translation\n%s\n\n"
                                 (string-trim body))
                       "** Claude Translation\n\n\n")))
        (goto-char (point-min))
        (cond
         ;; Prefer: end of the ** Wylie Transliteration section
         ((re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
          (forward-line 1)
          (if (re-search-forward
               (tibetan-analysis--claude-stop-re 2) nil t)
              (beginning-of-line)
            (goto-char (point-max)))
          (insert content))
         ;; Fallback: after the first top-level heading's opening line
         ((re-search-forward "^\\* " nil t)
          (forward-line 1)
          (insert content))
         (t
          (goto-char (point-max))
          (insert content)))))))

(defun tibetan-analysis--ensure-claude-headings (buffer)
  "Ensure the Claude Translation / Vocabulary / Grammar headings exist in BUFFER.

Segment-layout target (detected via `** Wylie Transliteration'):
  - `** Claude Translation'   at org level 2, right after Wylie.
  - `*** Claude Vocabulary'   at org level 3, inside
    `** Provided Translations' (after `*** DharmaMitra' if present,
    before `*** Claude Grammar').
  - `*** Claude Grammar'      at org level 3, inside
    `** Provided Translations' (before `*** Reference Translations'
    if present, otherwise appended).

Sentence-layout target (no `** Wylie Transliteration'):
  - `*** Claude Translation' at org level 3 (siblings under whatever
    parent the sentence scaffold provides).
  - `*** Claude Vocabulary'  at org level 3.
  - `*** Claude Grammar'     at org level 3.
  - `*** Claude Context'     at org level 3 — preserved for sentence
    files which still use the three/four-section layout.

Performs legacy-layout migration first (via
`tibetan-analysis--migrate-legacy-claude-headings'), then creates
whichever target heading is still missing.  Idempotent."
  (with-current-buffer buffer
    ;; Step 1 — migrate legacy layouts into the target shape.
    (tibetan-analysis--migrate-legacy-claude-headings buffer)
    (save-excursion
      (cond
       ;; -------------------------------------------------------------
       ;; SEGMENT LAYOUT: Translation at level 2, Vocab/Grammar at 3.
       ;; -------------------------------------------------------------
       ((tibetan-analysis--claude-segment-layout-p buffer)
        ;; Ensure `** Claude Translation' exists.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Translation$" nil t))
          (tibetan-analysis--insert-claude-translation-heading
           buffer nil))
        ;; Ensure `*** Claude Vocabulary' exists (before Grammar).
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\*\\* Claude Vocabulary$" nil t))
          (goto-char (point-min))
          (cond
           ;; Prefer: inside `** Provided Translations', after
           ;; `*** DharmaMitra' if present, else before Grammar.
           ((re-search-forward "^\\*\\* Provided Translations$" nil t)
            (let* ((section-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 2) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (mitra-end
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* DharmaMitra$" section-end t)
                        (forward-line 1)
                        (if (re-search-forward
                             (tibetan-analysis--claude-stop-re 3)
                             section-end t)
                            (line-beginning-position)
                          section-end))))
                   (grammar-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Claude Grammar$" section-end t)
                        (line-beginning-position))))
                   (ref-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Reference Translations$"
                             section-end t)
                        (line-beginning-position)))))
              (goto-char (or mitra-end grammar-pos ref-pos section-end))
              (insert "*** Claude Vocabulary\n\n\n")))
           ;; Fallback: after the Translation heading.
           (t
            (goto-char (point-min))
            (if (re-search-forward "^\\*\\* Claude Translation$" nil t)
                (progn
                  (forward-line 1)
                  (if (re-search-forward
                       (tibetan-analysis--claude-stop-re 2) nil t)
                      (beginning-of-line)
                    (goto-char (point-max)))
                  (insert "*** Claude Vocabulary\n\n\n"))
              (goto-char (point-max))
              (insert "\n*** Claude Vocabulary\n\n")))))
        ;; Ensure `*** Claude Grammar' exists.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t))
          (goto-char (point-min))
          (cond
           ;; Prefer: inside `** Provided Translations', before
           ;; `*** Reference Translations' if present, after Vocabulary.
           ((re-search-forward "^\\*\\* Provided Translations$" nil t)
            (let* ((section-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 2) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (vocab-end
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Claude Vocabulary$" section-end t)
                        (forward-line 1)
                        (if (re-search-forward
                             (tibetan-analysis--claude-stop-re 3)
                             section-end t)
                            (line-beginning-position)
                          section-end))))
                   (ref-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Reference Translations$"
                             section-end t)
                        (line-beginning-position)))))
              (goto-char (or vocab-end ref-pos section-end))
              (insert "*** Claude Grammar\n\n\n")))
           ;; Fallback: after the Translation heading we just ensured.
           (t
            (goto-char (point-min))
            (if (re-search-forward "^\\*\\* Claude Translation$" nil t)
                (progn
                  (forward-line 1)
                  (if (re-search-forward
                       (tibetan-analysis--claude-stop-re 2) nil t)
                      (beginning-of-line)
                    (goto-char (point-max)))
                  (insert "*** Claude Grammar\n\n\n"))
              (goto-char (point-max))
              (insert "\n*** Claude Grammar\n\n"))))))
       ;; -------------------------------------------------------------
       ;; SENTENCE / LEGACY LAYOUT: all four headings at level 3.
       ;; -------------------------------------------------------------
       (t
        (let ((prev "Claude Translation"))
          (dolist (heading '("Claude Translation" "Claude Vocabulary" "Claude Grammar" "Claude Context"))
            (unless (save-excursion
                      (goto-char (point-min))
                      (re-search-forward
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       nil t))
              (goto-char (point-min))
              (cond
               ;; Place after previous sibling if it exists.
               ((re-search-forward
                 (format "^\\*\\*\\* %s$" (regexp-quote prev)) nil t)
                (forward-line 1)
                (if (re-search-forward
                     (tibetan-analysis--claude-stop-re 3) nil t)
                    (beginning-of-line)
                  (goto-char (point-max)))
                (insert (format "*** %s\n\n\n" heading)))
               ;; No previous sibling — append at end of buffer.
               (t
                (goto-char (point-max))
                (insert (format "\n*** %s\n\n" heading)))))
            (setq prev heading))))))))

(defun tibetan-analysis--replace-claude-section-body
    (buffer heading body &optional level)
  "Replace the body under `HEADING' at org LEVEL in BUFFER with BODY.
LEVEL defaults to 3 for backwards compatibility.  Leaves the heading
itself in place; body is trimmed + terminated with one trailing blank
line."
  (let ((level (or level 3)))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward
               (tibetan-analysis--claude-heading-re heading level)
               nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward
                          (tibetan-analysis--claude-stop-re level) nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            (insert (format "%s\n\n" (string-trim body)))))))))

(defun tibetan-analysis--claude-effective-section-order (buffer)
  "Return the layout-appropriate Claude section-order for BUFFER.

Segment layout (per-segment analysis files):
  `** Claude Translation' (level 2), `*** Claude Grammar' (level 3).
  Context is dropped — the segment workflow is two-section only.

Sentence / legacy layout (sentence analysis files, or any buffer
without the segment-layout marker):
  Translation / Grammar / Context all at level 3 — preserves the
  existing sentence-level three-section workflow unchanged.

Callers that write Claude output (insert, restore) use this list so
a single buffer's layout drives heading levels consistently."
  (if (tibetan-analysis--claude-segment-layout-p buffer)
      tibetan-analysis--claude-section-order
    '((:translation "Claude Translation" 3)
      (:vocabulary  "Claude Vocabulary"  3)
      (:grammar     "Claude Grammar"     3)
      (:context     "Claude Context"     3))))

(defun tibetan-analysis--insert-claude-sections (response analysis-file)
  "Parse RESPONSE and write its sections into ANALYSIS-FILE.
RESPONSE is the raw markdown returned by Claude; it is split by
`tibetan-analysis--parse-claude-sections'.  Each section named in
the buffer's effective section-order (see
`tibetan-analysis--claude-effective-section-order') that the parser
filled in is written under its corresponding org heading at the
configured level.  Legacy `*** Claude' and `*** Claude Translation'
placements are migrated to the current two-section segment layout on
first write; sentence files keep the legacy three-section layout."
  (when (and response (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis--parse-claude-sections response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        (tibetan-analysis--ensure-claude-headings buf)
        (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
          (let ((key (nth 0 entry))
                (heading (nth 1 entry))
                (level (nth 2 entry)))
            (when (plist-get sections key)
              (tibetan-analysis--replace-claude-section-body
               buf heading (plist-get sections key) level))))
        ;; Merge Claude Vocabulary into the Word / Particle List as
        ;; ◇ tier-2 lines beneath each matching entry.
        (when (plist-get sections :vocabulary)
          (tibetan-analysis--merge-claude-vocabulary
           buf (plist-get sections :vocabulary)))
        (save-buffer))
      (message "Claude sections inserted into %s"
               (file-name-nondirectory analysis-file)))))

;; ---------------------------------------------------------------------------
;; Claude Vocabulary → Word / Particle List merge
;; ---------------------------------------------------------------------------

(defun tibetan-analysis--parse-claude-vocabulary (vocab-text)
  "Parse VOCAB-TEXT (the `## Vocabulary' body) into an alist.
Each entry is (WYLIE-KEY . FULL-LINE) where WYLIE-KEY is the
lowercase, trimmed first field (before the first comma) and
FULL-LINE is the original line.  Blank lines and lines starting
with `---' are skipped."
  (let ((result '()))
    (when (and vocab-text (stringp vocab-text)
               (not (string-empty-p vocab-text)))
      (dolist (line (split-string vocab-text "\n" t))
        (let ((trimmed (string-trim line)))
          (unless (or (string-empty-p trimmed)
                      (string-prefix-p "---" trimmed))
            (when (string-match "\\`\\([^,]+\\)," trimmed)
              (let ((key (downcase (string-trim (match-string 1 trimmed)))))
                (push (cons key trimmed) result)))))))
    (nreverse result)))

(defun tibetan-analysis--merge-claude-vocabulary (buffer vocab-text)
  "Merge parsed Claude vocabulary lines into `** Word / Particle List' in BUFFER.
For each entry in the word list, looks up a matching Claude vocabulary
line (by Wylie key) and inserts it as a `    ◇ ...' tier-2 line
right after the existing gloss.  Existing ◇ lines are removed first
for idempotency.

VOCAB-TEXT is the raw body of the `## Vocabulary' / `*** Claude Vocabulary'
section.  When nil or empty, this function is a no-op."
  (when (and vocab-text (stringp vocab-text)
             (not (string-empty-p (string-trim vocab-text))))
    (let ((entries (tibetan-analysis--parse-claude-vocabulary vocab-text)))
      (when entries
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^\\*\\* Word / Particle List$" nil t)
              (forward-line 1)
              (let ((section-end
                     (save-excursion
                       (if (re-search-forward
                            (tibetan-analysis--claude-stop-re 2) nil t)
                           (line-beginning-position)
                         (point-max)))))
                ;; Pass 1: strip existing ◇ lines (idempotent re-merge).
                (save-excursion
                  (while (re-search-forward "^    ◇ .*\n?" section-end t)
                    (replace-match "")
                    ;; Recalculate end after deletion.
                    (setq section-end
                          (save-excursion
                            (goto-char (point-min))
                            (if (and (re-search-forward
                                      "^\\*\\* Word / Particle List$" nil t)
                                     (forward-line 1)
                                     (re-search-forward
                                      (tibetan-analysis--claude-stop-re 2)
                                      nil t))
                                (line-beginning-position)
                              (point-max))))))
                ;; Pass 2: insert ◇ lines after matching entries.
                ;; Each word-list entry starts with " N." and has
                ;; a Wylie key in [brackets].  We use a marker for
                ;; section-end so insertions don't invalidate it.
                (goto-char (point-min))
                (re-search-forward "^\\*\\* Word / Particle List$" nil t)
                (forward-line 1)
                (let ((end-marker
                       (let ((pos (save-excursion
                                    (if (re-search-forward
                                         (tibetan-analysis--claude-stop-re 2)
                                         nil t)
                                        (line-beginning-position)
                                      (point-max)))))
                         (copy-marker pos))))
                  (while (re-search-forward
                          "^[ \t]*[0-9]+\\..*\\[\\([^]]+\\)\\]"
                          end-marker t)
                    (let* ((wylie-key (downcase
                                       (string-trim (match-string 1))))
                           (match (assoc wylie-key entries)))
                      (when match
                        ;; Find the end of this entry (next numbered
                        ;; line or section boundary).
                        (let ((entry-end
                               (save-excursion
                                 (forward-line 1)
                                 ;; Skip continuation lines (indented,
                                 ;; starting with spaces + text).
                                 (while (and (< (point) end-marker)
                                             (looking-at "^    "))
                                   (forward-line 1))
                                 (point))))
                          (goto-char entry-end)
                          (insert (format "    ◇ %s\n" (cdr match)))))))
                  (set-marker end-marker nil))))))))))

;; Backwards-compatible alias — callers outside this module may still
;; refer to the old one-section name.  New code should use
;; `tibetan-analysis--insert-claude-sections'.
(defalias 'tibetan-analysis--insert-claude-translation
  'tibetan-analysis--insert-claude-sections)

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
  "Extract a short English gloss from MEANING suitable for the CAT Gloss line.

Input MEANING is the enriched `short-meaning' produced by the
Word/Particle List renderer.  It may be one of:

  1. A Hill-morphology gloss like
        \"pf. of byed;\\nto do, to make\"
     Returns:  \"to do, to make\"
  2. A curated German//English entry like
        \"Pf. von 'dzugs;\\nim Spiel einsetzen // to stake, to wager\"
     or
        \"blauer Lotus // blue lotus\"
     Returns the English side (text after the last `//').
  3. A stem-reference only entry (German abbrev. no English),
     e.g. \"Pf. von 'dzugs\".  Returns the stripped stem-ref phrase
     so the CAT Gloss still shows something meaningful.
  4. A plain English gloss with sense separators.  Returns the first
     sense (up to `;').
  5. An RY-style \"verb: do\" / \"noun: X\" format — strip the
     \"verb: \"/\"noun: \" prefix so CAT output reads cleanly.

Returns nil if MEANING is nil/empty/a placeholder."
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
Understands genitive (→ 'of'), dative (→ 'to/for'), topic (→ 'as for...'),
causal converb -pas/-bas (→ 'because ... / by ...-ing'), sequential
converb -te/-ste/-nas (→ '... and then'), and other common Tibetan
grammatical constructions."
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
- [Ø ROLE] for zero-marked arguments"
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

    ;; Mark case particles with =...=
    (dolist (p case-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "=%s=" p)
                    result)))

    ;; Mark converb particles with ~...~
    (dolist (p converb-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\b" (regexp-quote p))
                    (format "~%s~" p)
                    result)))

    ;; Mark sentence-final particles with *...*
    (dolist (p final-particles)
      (setq result (replace-regexp-in-string
                    (format "\\b%s\\(/\\|$\\)" (regexp-quote p))
                    (format "*%s*\\1" p)
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

(defun tibetan-analysis-generate-content (tibetan-text &optional seg-id source-text)
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
affected, not the rest of the analysis."
  (condition-case err
      (progn
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
      (insert "** Word / Particle List\n")
      (if vocab-pairs
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
                     (tag (cond
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
                ;; Display the punctuation-stripped form so ལ། renders
                ;; as ལ [la], not as ལ། [la/].  `word-clean' already has
                ;; trailing shad / punctuation removed higher up.
                ;;
                ;; DharmaMitra-style format:
                ;;   N. Tibetan [wylie] ([[steinert-url][Steinert]])  [tag]
                ;;      ★/◇ gloss
                ;; The Steinert URL links to the web dictionary for the
                ;; stripped root form (particles don't have useful entries).
                (let* ((wylie-key
                        (condition-case nil
                            (when (fboundp 'tibetan-to-wylie-fixed)
                              (downcase
                               (string-trim
                                (tibetan-to-wylie-fixed word-clean))))
                          (error nil)))
                       (steinert-link
                        (when (and wylie-key
                                   (fboundp 'tibetan-steinert-url-org)
                                   ;; Skip Steinert links for pure
                                   ;; particles / grammatical affixes.
                                   (not (member tag
                                                '("GENITIVE (GEN)"
                                                  "CONVERBIAL: ABLATIVE CONVERB"
                                                  "CONVERBIAL: SIMULTANEOUS CONVERB"
                                                  "CONVERBIAL: CONCESSIVE CONVERB"
                                                  "CONVERBIAL: CONDITIONAL CONVERB"))))
                          (tibetan-steinert-url-org wylie-key))))
                  (insert (format "%2d. %s" idx
                                  (tibetan-analysis--format-word-with-wylie
                                   word-clean)))
                  (when steinert-link
                    (insert (format " (%s)" steinert-link)))
                  (when tag
                    (insert (format "  [%s]" tag)))
                  (when (and short-meaning (not (string-empty-p short-meaning)))
                    ;; Put translation(s) on an indented continuation line
                    ;; for every entry so they're visually easy to spot.
                    ;; Stem-reference entries ("Pf. von X; DE // EN") keep
                    ;; the stem ref on line 1 after " — " and move the
                    ;; bilingual translation to an indented line 2.
                    (let ((display-meaning
                           (tibetan-analysis--format-bilingual-gloss
                            short-meaning)))
                      (if (string-match-p "\n" display-meaning)
                          ;; Multi-line (stem-ref split): first chunk on
                          ;; same line after " — ", rest indented.
                          (let* ((lines (split-string display-meaning "\n"))
                                 (first (car lines))
                                 (rest (cdr lines)))
                            (insert (format "  — %s" first))
                            (dolist (ln rest)
                              (insert (format "\n    %s" ln))))
                        ;; Single-line gloss: move to its own indented
                        ;; line for consistency with stem-ref entries.
                        (insert (format "\n    — %s" display-meaning)))))
                  (when (and source (string-prefix-p "Resources" source))
                    (insert " ★"))
                  (insert "\n"))
                ;; Record the enriched gloss for reuse by the CAT Gloss
                ;; section.  We store the ORIGINAL surface word (with
                ;; particles still attached) so the CAT renderer can
                ;; pattern-match on converb/case endings.
                (push (cons word-clean short-meaning)
                      enriched-vocab-pairs)
                (setq idx (1+ idx)))))
        (insert "[Word list extraction not available]\n"))
      (setq enriched-vocab-pairs (nreverse enriched-vocab-pairs))
      (insert "\n")

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
             vocab-pairs))))
      (when interlinear-marker
        (set-marker interlinear-marker nil))

      ;; ============================================================
      ;; SECTION 3b: Particle Map - visual particle identification
      ;; ============================================================
      (insert "** Particle Map\n")
      (insert "Wylie with particles marked: =CASE= for case markers, ~CONVERB~ for converbs, Ø for zero-marked agents/patients\n\n")
      ;; Generate annotated Wylie showing particles
      (let ((annotated-wylie (tibetan-analysis--generate-particle-map tibetan-text particles verbs)))
        (insert annotated-wylie)
        (insert "\n\n"))

      ;; ============================================================
      ;; SECTION 4: Grammatical Analysis (Bialek) - compact format
      ;; ============================================================
      (insert "** Grammatical Markers\n")
      (let ((bialek-analysis (condition-case nil
                                (when (fboundp 'tibetan-analyze-grammar-bialek)
                                  (tibetan-analyze-grammar-bialek tibetan-text))
                              (error nil))))
        (if bialek-analysis
            (dolist (a bialek-analysis)
              (let ((particle (nth 0 a))
                    (word (nth 1 a))
                    (type (nth 2 a))
                    (function (nth 3 a))
                    (trans-guide (nth 4 a))
                    (portfolio (nth 6 a)))
                ;; Format: particle [wylie] in «word [wylie]» → TYPE: translation.
                ;; Don't use =...= for Tibetan as it forces monospace font.
                (insert (format "- %s in «%s» → %s: %s"
                                (tibetan-analysis--format-word-with-wylie
                                 particle)
                                (tibetan-analysis--format-word-with-wylie
                                 word)
                                type
                                (or trans-guide function)))
                (when portfolio
                  (insert (format " [%s]" portfolio)))
                (insert "\n")))
          (insert "[No grammatical markers detected]\n")))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 4: Sentence Structure — per-clause verb lines
      ;; ============================================================
      ;; Round 1 annotations from the extractor are used here:
      ;;   • Modal / reporting verbs are hidden from the main list
      ;;     and shown as annotations on the content verb they chain to.
      ;;   • Negation (ma-/mi-) is displayed as `NEG` on the verb.
      ;;   • Suffix type (converb / nominalizer / ...) is shown alongside
      ;;     the lemma so the clause role is obvious.
      ;;   • Arguments are sorted by source-pos and only include units
      ;;     that sit inside this verb's clause (see `analyze-arguments').
      (insert "** Sentence Structure\n")
      (if (and verbs (fboundp 'tibetan-analyze-arguments))
          (let* ((content-verbs
                  (cl-remove-if (lambda (v)
                                  (or (alist-get 'is-modal v)
                                      (alist-get 'is-reporter v)))
                                verbs))
                 (any-structure nil))
            (dolist (verb content-verbs)
              (when (and verb (listp verb) (consp (car verb)))
                (let* ((lemma (alist-get 'lemma verb))
                       (meaning (alist-get 'meaning verb))
                       (suffix (alist-get 'suffix-type verb))
                       (negated (alist-get 'negated verb))
                       (modal-of (alist-get 'modal-of verb))
                       (reports-p (alist-get 'reports-p verb))
                       (arg-analysis (tibetan-analyze-arguments
                                      verb multiword-units words verbs)))
                  (when (or arg-analysis lemma)
                    (setq any-structure t)
                    (insert "- ")
                    (when negated (insert "NEG "))
                    (insert (tibetan-analysis--format-word-with-wylie lemma))
                    (when (and meaning (not (string-empty-p meaning)))
                      (insert (format " '%s'"
                                      (car (split-string meaning "," t)))))
                    (when suffix
                      ;; suffix already starts with ", "; skip its leading comma
                      (let ((s (if (string-prefix-p ", " suffix)
                                   (substring suffix 2)
                                 suffix)))
                        (insert (format " [%s]" s))))
                    (when modal-of
                      (insert (format " +MODAL:%s" modal-of)))
                    (when reports-p
                      (insert (format " +SAYS:%s" reports-p)))
                    (insert ":")
                    (dolist (arg arg-analysis)
                      (let ((marker (alist-get 'marker arg))
                            (form (alist-get 'form arg))
                            (is-topic (alist-get 'is-topic arg)))
                        (unless is-topic
                          (insert (format " %s(%s)" form (or marker "Ø"))))))
                    (insert "\n")))))
            (unless any-structure
              (insert "[No argument structure detected]\n")))
        (insert "[No verbs detected]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 4b: Clause Structure (Round-2) — optional
      ;; ============================================================
      ;; Gate on `tibetan-analysis-show-clause-structure' so users who
      ;; prefer the compact legacy view can opt out without losing
      ;; the Sentence Structure section above.
      (when tibetan-analysis-show-clause-structure
        (insert "** Clause Structure\n")
        (let ((rendered (tibetan-analysis--render-clause-structure
                         words verbs multiword-units)))
          (if (and rendered (not (string-empty-p rendered)))
              (insert rendered)
            (insert "[Round-2 clause structure unavailable]\n")))
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
      ;; ============================================================
      (insert "** Detailed Dictionary\n")
      (let ((vocab-list (condition-case nil
                            (when (fboundp 'tibetan-vocab-extract-detailed)
                              (tibetan-vocab-extract-detailed tibetan-text))
                          (error nil))))
        (if vocab-list
            (progn
              (dolist (entry vocab-list)
                (let* ((tibetan (plist-get entry :tibetan))
                       (wylie (plist-get entry :wylie))
                       ;; Multi-source lookup: provided list first, then
                       ;; Steinert block, then Rangjung Yeshe, others
                       ;; only when they add a genuinely different gloss.
                       ;; Sanskrit is emitted only when carried natively
                       ;; by the source entry.
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
                                 sources)))
                  ;; Dictionary-style head line: ◆ word [wylie] ★
                  ;; Route through the formatter so this stays in lock-step
                  ;; with every other section.  If the multi-source entry
                  ;; already carries a wylie string, let it win — otherwise
                  ;; the formatter computes one from the Tibetan head.
                  (insert (format "◆ %s"
                                  (if (and wylie (stringp wylie)
                                           (not (string-empty-p wylie))
                                           (not (string= wylie tibetan)))
                                      (format "%s [%s]" tibetan wylie)
                                    (tibetan-analysis--format-word-with-wylie
                                     tibetan))))
                  (when has-resources (insert " ★"))
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
                        (insert (format "  [%s]\n" source)))))
                  (insert "\n")))
              (insert "\n"))
          ;; Fallback: use vocab-pairs if detailed system not available
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
            (insert "[No dictionary entries available]\n\n"))))

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

      (buffer-string))))
    (error
     ;; On error, return minimal analysis with error info
     (format "** Wylie Transliteration\n[Error during analysis]\n\n** Provided Translations\n- [Error: %s]\n\n** Vocabulary\n[Error]\n"
             (error-message-string err)))))

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
                (tibetan-analysis-setup-faces))
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
              (tibetan-analysis-setup-faces))
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

(defun tibetan-analysis--read-claude-section-body (filepath heading &optional level)
  "Return the non-placeholder body under `HEADING' in FILEPATH, or nil.
LEVEL is the org heading level to look for (defaults to 3 for
backwards compatibility).  When nil is passed explicitly as LEVEL,
the reader tries level 2 first and falls back to level 3 — this is
useful during the Claude Translation migration, when an old file may
still carry a level-3 heading.  Skips placeholder `[Requesting …]'
and known error markers so we don't re-persist dead content."
  (when (file-exists-p filepath)
    (let ((levels (cond
                   ((null level) '(2 3))
                   ((listp level) level)
                   (t (list level)))))
      (cl-loop for lvl in levels
               for body = (with-temp-buffer
                            (insert-file-contents filepath)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   (tibetan-analysis--claude-heading-re
                                    heading lvl)
                                   nil t)
                              (forward-line 1)
                              (let* ((start (point))
                                     (end (save-excursion
                                            (if (re-search-forward
                                                 (tibetan-analysis--claude-stop-re
                                                  lvl)
                                                 nil t)
                                                (line-beginning-position)
                                              (point-max))))
                                     (b (string-trim
                                         (buffer-substring-no-properties
                                          start end))))
                                (unless
                                    (or (string-empty-p b)
                                        (string-match-p "\\`\\[Requesting" b)
                                        (string-match-p "\\`\\[Claude unavailable" b)
                                        (string-match-p "\\`\\[Claude request failed" b)
                                        (string-match-p "\\`\\[Translation not available" b))
                                  b))))
               when body return body))))

(defun tibetan-analysis--read-claude-sections (filepath)
  "Return preserved Claude content in FILEPATH as a plist.
Keys: `:translation', `:vocabulary', `:grammar', each a non-empty
string or nil.  Reads from the new mixed-level layout
\(`** Claude Translation', `*** Claude Vocabulary',
`*** Claude Grammar'); falls back to the legacy level-3 heading
for `:translation' so old analysis files do not lose their work on
reanalysis.  A legacy `*** Claude Context' body is still read when
present and returned as `:context' for round-trip safety, but it is
never written back."
  (let ((translation
         (or
          ;; New layout: `** Claude Translation' (level 2)
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 2)
          ;; Legacy level-3 placement
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 3)
          ;; Pre-three-section legacy heading
          (tibetan-analysis--read-claude-section-body
           filepath "Claude" 3)))
        (vocabulary (tibetan-analysis--read-claude-section-body
                     filepath "Claude Vocabulary" 3))
        (grammar (tibetan-analysis--read-claude-section-body
                  filepath "Claude Grammar" 3))
        ;; Preserve legacy Context body for round-trip safety; the
        ;; writer never emits a Context heading so this only surfaces
        ;; when an older analysis file still has one.
        (context (tibetan-analysis--read-claude-section-body
                  filepath "Claude Context" 3)))
    (list :translation translation
          :vocabulary  vocabulary
          :grammar     grammar
          :context     context)))

;; Backwards-compatible single-section reader — returns just the
;; translation body so legacy callers keep working.
(defun tibetan-analysis--read-claude-translation (filepath)
  "Return the preserved Claude translation in FILEPATH, or nil.
Legacy wrapper around `tibetan-analysis--read-claude-sections' that
returns only the `:translation' slot for callers that have not been
migrated yet."
  (plist-get (tibetan-analysis--read-claude-sections filepath) :translation))

(defun tibetan-analysis--restore-claude-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's Claude headings.
SECTIONS has keys :translation, :vocabulary, :grammar, and optionally
:context (legacy); any nil slot leaves the corresponding org body
untouched.  Creates the target headings (`** Claude Translation',
`*** Claude Vocabulary', `*** Claude Grammar') if they are missing,
migrating legacy layouts on first encounter.  A :context value is
only written when a `*** Claude Context' heading is already present
in the file — legacy files keep their Context body intact, but the
restore path will not create a new Context heading."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        (tibetan-analysis--ensure-claude-headings buf)
        (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
          (let ((key (nth 0 entry))
                (heading (nth 1 entry))
                (level (nth 2 entry)))
            (when (plist-get sections key)
              (tibetan-analysis--replace-claude-section-body
               buf heading (plist-get sections key) level))))
        ;; Backwards-compatible :context round-trip for segment layout:
        ;; the effective section order drops :context for segment buffers,
        ;; but if a legacy `*** Claude Context' heading is present on disk
        ;; we preserve the body round-trip instead of silently dropping it.
        (when (and (plist-get sections :context)
                   (tibetan-analysis--claude-segment-layout-p buf))
          (save-excursion
            (goto-char (point-min))
            (when (re-search-forward "^\\*\\*\\* Claude Context$" nil t)
              (tibetan-analysis--replace-claude-section-body
               buf "Claude Context" (plist-get sections :context) 3))))
        ;; Merge Claude Vocabulary into the Word / Particle List as
        ;; ◇ tier-2 lines (same as the insert path).
        (when (plist-get sections :vocabulary)
          (tibetan-analysis--merge-claude-vocabulary
           buf (plist-get sections :vocabulary)))
        (save-buffer)))))

;; Backwards-compatible single-section restore — wraps the translation
;; string in a plist so old callers keep working.
(defun tibetan-analysis--restore-claude-translation (filepath translation)
  "Write TRANSLATION back under `*** Claude Translation' in FILEPATH.
Legacy wrapper around `tibetan-analysis--restore-claude-sections'."
  (tibetan-analysis--restore-claude-sections
   filepath (list :translation translation)))

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
          (let ((auto-content (tibetan-analysis-generate-content
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
