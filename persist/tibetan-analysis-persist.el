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
(require 'org)
(require 'md5)

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

(defface tibetan-analysis-tibetan-face
  '((t :inherit default))
  "Face for Tibetan text in analysis buffers."
  :group 'tibetan-cat)

(defface tibetan-analysis-roman-face
  '((t :inherit default))
  "Face for roman (non-Tibetan) text in analysis buffers."
  :group 'tibetan-cat)

(defun tibetan-analysis-setup-faces ()
  "Setup faces for analysis buffers with specific point sizes.
Sets body text to 10pt and headings to max 12pt for Latin fonts."
  ;; Set default (body) text to 10pt
  ;; In Emacs, :height 100 = 10pt (each 10 units = 1pt)
  (face-remap-add-relative 'default :height 100)

  ;; Set heading sizes (12pt max for level 1-2, smaller for others)
  (face-remap-add-relative 'org-level-1 :height 120)  ; 12pt
  (face-remap-add-relative 'org-level-2 :height 120)  ; 12pt
  (face-remap-add-relative 'org-level-3 :height 110)  ; 11pt
  (face-remap-add-relative 'org-level-4 :height 100)  ; 10pt
  (face-remap-add-relative 'org-level-5 :height 100)  ; 10pt
  (face-remap-add-relative 'org-level-6 :height 100)  ; 10pt
  (face-remap-add-relative 'org-level-7 :height 100)  ; 10pt
  (face-remap-add-relative 'org-level-8 :height 100)  ; 10pt

  ;; Set other org elements to body size (10pt)
  (face-remap-add-relative 'org-block :height 100)
  (face-remap-add-relative 'org-code :height 100)
  (face-remap-add-relative 'org-table :height 100)
  (face-remap-add-relative 'org-verbatim :height 100)
  (face-remap-add-relative 'org-special-keyword :height 100)
  (face-remap-add-relative 'org-meta-line :height 100)
  (face-remap-add-relative 'org-drawer :height 100)
  (face-remap-add-relative 'org-property-value :height 100))
  ;; Note: Tibetan text should automatically remain legible due to
  ;; font characteristics, but if needed we can add specific handling

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

(defun tibetan-analysis-segment-filename (seg-id)
  "Generate analysis filename for SEG-ID.
SEG-ID can be a number or string like '1' or 'seg-001'.
Returns filename like 'seg-001.org'."
  (let ((num (cond
              ((numberp seg-id) seg-id)
              ((string-match "\\([0-9]+\\)" seg-id)
               (string-to-number (match-string 1 seg-id)))
              (t 1))))
    (format "seg-%03d.org" num)))

(defun tibetan-analysis-get-filepath (seg-id)
  "Get full filepath for analysis of SEG-ID."
  (let ((folder (tibetan-analysis-get-folder))
        (filename (tibetan-analysis-segment-filename seg-id)))
    (expand-file-name filename folder)))

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
  (when (file-exists-p filepath)
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
Returns alist of (section-name . content) for My Notes, Working Translation, Footnotes."
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

(defun tibetan-analysis--ensure-vocabulary ()
  "Ensure vocabulary is loaded before analysis."
  (unless (and (boundp 'tibetan-comprehensive-vocabulary)
               tibetan-comprehensive-vocabulary
               (> (hash-table-count tibetan-comprehensive-vocabulary) 0))
    (when (fboundp 'load-all-glossaries)
      (load-all-glossaries))
    (unless (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
      ;; Try loading from file
      (let ((glossary-file "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el"))
        (when (file-exists-p (expand-file-name glossary-file))
          (load-file (expand-file-name glossary-file)))))))

(defun tibetan-analysis--get-particle-annotation (word)
  "Get compact particle annotation for WORD.
Returns string like '(ERG)' or '(LOC: if/when)' or nil."
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
  (let ((info '())
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

(defun tibetan-analysis-generate-content (tibetan-text)
  "Generate auto-analysis content for TIBETAN-TEXT.
Returns the analysis as a string (org-mode formatted).
New compact format with inline annotations."
  ;; Ensure vocabulary is loaded
  (tibetan-analysis--ensure-vocabulary)

  (let* ((parsed (when (fboundp 'tibetan-parse-enhanced)
                   (tibetan-parse-enhanced tibetan-text)))
         (words (alist-get 'words parsed))
         (analysis (alist-get 'analysis parsed))
         (multiword-units (alist-get 'multiword-units parsed))
         (wylie-full (when (fboundp 'tibetan-to-wylie-fixed)
                       (condition-case nil
                           (tibetan-to-wylie-fixed tibetan-text)
                         (error "[Wylie conversion error]"))))
         (verbs (when (fboundp 'tibetan-extract-verbs-compound-aware)
                  (tibetan-extract-verbs-compound-aware tibetan-text words multiword-units)))
         (zero-analysis (when (and verbs multiword-units (fboundp 'tibetan-analyze-zero-markers))
                          (tibetan-analyze-zero-markers verbs multiword-units words)))
         (translation (when (fboundp 'tibetan-get-dharmamitra-translation)
                        (tibetan-get-dharmamitra-translation tibetan-text)))
         (claimed-indices (when (fboundp 'tibetan-get-claimed-indices)
                            (tibetan-get-claimed-indices multiword-units)))
         (particles (when analysis (alist-get 'particles analysis)))
         ;; Build verb lookup table (keyed by SURFACE FORM, not lemma)
         (verb-table (make-hash-table :test 'equal))
         ;; Also collect the surface forms that matched
         (verb-surface-forms '()))

    ;; Build verb lookup - we need to store by surface form for annotation
    ;; First, collect what surface forms matched verbs
    (when words
      (dolist (word words)
        (let ((clean (string-trim word)))
          (when (and (not (string-empty-p clean))
                     (fboundp 'tibetan-verb-lookup))
            (let ((entry (tibetan-verb-lookup clean)))
              (when entry
                (puthash clean entry verb-table)
                (push clean verb-surface-forms)))))))

    (with-temp-buffer
      ;; ============================================================
      ;; SECTION 1: Annotated Text (compact format with inline info)
      ;; ============================================================
      (insert "** Annotated Text\n")
      (insert "#+BEGIN_EXAMPLE\n")
      (when (and words (fboundp 'tibetan-build-compound-aware-segments))
        (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
          (dolist (seg segments)
            (let* ((info (tibetan-analysis--get-word-info seg multiword-units))
                   (meaning (alist-get 'meaning info))
                   (wylie-seg (alist-get 'wylie info))
                   (particle-annot (tibetan-analysis--get-particle-annotation seg))
                   (verb-info (gethash seg verb-table))
                   (annotation-parts '()))
              ;; Build annotation string
              (when wylie-seg
                (push (format "[%s]" wylie-seg) annotation-parts))
              (when meaning
                (push (format "\"%s\"" (if (> (length meaning) 30)
                                           (concat (substring meaning 0 27) "...")
                                         meaning))
                      annotation-parts))
              (when particle-annot
                (push particle-annot annotation-parts))
              (when verb-info
                (let ((trans (alist-get 'transitivity verb-info)))
                  (push (format "V:%s" (if (and trans (string-match-p "Transitive" trans))
                                          "tr" "intr"))
                        annotation-parts)))
              ;; Output line
              (insert (format "%s %s\n" seg
                             (if annotation-parts
                                 (string-join (nreverse annotation-parts) " ")
                               "")))))))
      (insert "#+END_EXAMPLE\n\n")

      ;; Full Wylie for reference
      (insert "** Full Wylie\n")
      (insert (or wylie-full "[Not available]"))
      (insert "\n\n")

      ;; ============================================================
      ;; SECTION 2: Translations (immediately visible)
      ;; ============================================================
      (insert "** Translations\n")
      (insert (format "- DharmaMitra: %s\n" (or translation "[Not available]")))
      (insert "- CAT Suggested: [Generate with C-c u t]\n")
      (insert "\n")

      ;; ============================================================
      ;; SECTION 3: Sentence Structure (grammatical analysis)
      ;; ============================================================
      (insert "** Sentence Structure\n")
      (if (and (> (hash-table-count verb-table) 0) (fboundp 'tibetan-analyze-arguments))
          (let ((any-structure nil))
            (maphash
             (lambda (surface-form verb)
               (let* ((lemma (alist-get 'lemma verb))
                      (meaning (alist-get 'meaning verb))
                      (frame (or (alist-get 'case_frame verb) "?"))
                      (trans (alist-get 'transitivity verb))
                      (arg-analysis (tibetan-analyze-arguments verb multiword-units words)))
                 (when lemma
                   (setq any-structure t)
                   ;; Display predicate first
                   (insert (format "- PREDICATE: %s" lemma))
                   (when meaning
                     (insert (format " \"%s\"" (car (split-string meaning "," t)))))
                   (when trans
                     (insert (format " [%s]" (if (string-match-p "Transitive" trans) "tr" "intr"))))
                   (insert "\n")
                   ;; Display arguments
                   (dolist (arg arg-analysis)
                     (let ((role (alist-get 'role arg))
                           (marker (alist-get 'marker arg))
                           (form (alist-get 'form arg))
                           (english (alist-get 'english arg))
                           (is-topic (alist-get 'is-topic arg)))
                       (unless is-topic
                         (insert (format "  - %s: %s" role form))
                         (when english (insert (format " \"%s\"" english)))
                         (insert (format " (%s)\n" (if (string= marker "Ø") "Ø" marker))))))
                   (insert "\n"))))
             verb-table)
            (unless any-structure
              (insert "[Structure analysis pending]\n")))
        (insert "[No verb-based structure detected]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 4: Verb Details (Hill 2010) - collapsed by default
      ;; ============================================================
      (insert "** Verb Details (Hill 2010)\n")
      (if (> (hash-table-count verb-table) 0)
          (maphash
           (lambda (surface-form verb)
             (let* ((lemma (alist-get 'lemma verb))
                    (meaning (alist-get 'meaning verb))
                    (present (or (alist-get 'present_stem verb) "—"))
                    (past (or (alist-get 'past_stem verb) "—"))
                    (future (or (alist-get 'future_stem verb) "—"))
                    (imperative (or (alist-get 'imperative_stem verb) "—"))
                    (frame (or (alist-get 'case_frame verb) "?")))
               (insert (format "- %s: %s / %s / %s / %s [%s]\n"
                              lemma present past future imperative frame))
               (when meaning
                 (insert (format "  %s\n" meaning)))))
           verb-table)
        (insert "[No verbs]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 5: Zero Markers & Special Notes
      ;; ============================================================
      (when zero-analysis
        (insert "** Zero-Marked NPs\n")
        (dolist (item zero-analysis)
          (let ((form (alist-get 'form item))
                (function (alist-get 'function item))
                (gloss (alist-get 'gloss item)))
            (insert (format "- %s (Ø): %s" form function))
            (when gloss (insert (format " — %s" gloss)))
            (insert "\n")))
        (insert "\n"))

      (buffer-string))))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

(defun tibetan-open-segment-analysis ()
  "Open or create analysis for current segment in side window.
If analysis exists, check if source has changed and warn."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data)))

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
        (let* ((auto-content (tibetan-analysis-generate-content tibetan-text))
               (new-filepath (tibetan-analysis-create-file seg-id tibetan-text source-file auto-content)))
          (message "Created analysis file: %s" new-filepath)
          (let ((buf (find-file-noselect new-filepath)))
            (with-current-buffer buf
              (tibetan-analysis-setup-faces))
            (display-buffer-in-side-window buf
                                           '((side . right)
                                             (window-width . 0.5)))))))))

(defun tibetan-reanalyze-segment ()
  "Re-analyze current segment, preserving user notes.
Regenerates the Auto-Analysis section only."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data)))

    (unless seg-data
      (error "Not in a segment"))

    (let ((filepath (tibetan-analysis-get-filepath seg-id)))
      (unless (file-exists-p filepath)
        (error "No analysis file exists. Use C-c u A to create one first"))

      (when (yes-or-no-p "Re-analyze segment? (Auto section will be regenerated, notes preserved) ")
        (let ((auto-content (tibetan-analysis-generate-content tibetan-text)))
          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
          ;; Refresh the buffer if it's open
          (let ((buf (get-file-buffer filepath)))
            (when buf
              (with-current-buffer buf
                (revert-buffer t t)))))))))

(provide 'tibetan-analysis-persist)
;;; tibetan-analysis-persist.el ends here
