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

;; Require modules for verb analysis (soft load - main loading via tibetan-cat.el)
(require 'tibetan-verb-classifier nil t)
(require 'tibetan-enhanced-display nil t)
(require 'tibetan-particles-bialek nil t)

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
             (string-match "analysis/seg-[0-9]+" (buffer-file-name)))
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

(defun tibetan-analysis-make-short-name (filename)
  "Create a short identifier from FILENAME for use in segment filenames.
E.g., 'Reading-Sa-skya-legs-bshad.org' -> 'saskya'
      'Tigress-Story-BlockPrint-Class.org' -> 'tigress'"
  (when filename
    (let* ((base (file-name-sans-extension (file-name-nondirectory filename)))
           ;; Convert to lowercase and extract key part
           (lower (downcase base))
           ;; Common patterns to extract
           (short (cond
                   ;; Tigress story
                   ((string-match "tigress" lower) "tigress")
                   ;; Sa skya legs bshad
                   ((string-match "sa.?skya\\|saskya\\|legs.?bshad" lower) "saskya")
                   ;; Reading files - use first meaningful word
                   ((string-match "reading.?\\([0-9]+\\)" lower)
                    (format "reading%s" (match-string 1 lower)))
                   ;; Default: take first 8 chars of alphanumeric
                   (t (let ((clean (replace-regexp-in-string "[^a-z0-9]" "" lower)))
                        (substring clean 0 (min 8 (length clean))))))))
      short)))

(defun tibetan-analysis-segment-filename (seg-id &optional source-file)
  "Generate analysis filename for SEG-ID.
SEG-ID can be a number or string like '1' or 'seg-001'.
SOURCE-FILE, if provided, adds a short identifier suffix.
Returns filename like 'seg-001-tigress.org' or 'seg-001.org'."
  (let* ((num (cond
               ((numberp seg-id) seg-id)
               ;; Extract segment number specifically (not sentence number)
               ((string-match "Segment \\([0-9]+\\)" seg-id)
                (string-to-number (match-string 1 seg-id)))
               ;; Fallback: try any number
               ((string-match "\\([0-9]+\\)" seg-id)
                (string-to-number (match-string 1 seg-id)))
               (t 1)))
         (short-name (tibetan-analysis-make-short-name source-file)))
    (if short-name
        (format "seg-%03d-%s.org" num short-name)
      (format "seg-%03d.org" num))))

(defun tibetan-analysis-get-filepath (seg-id &optional source-file)
  "Get full filepath for analysis of SEG-ID.
SOURCE-FILE, if provided, is used to generate a unique suffix.
Also checks for legacy files without suffix for backward compatibility."
  (let* ((folder (tibetan-analysis-get-folder))
         (src (or source-file (buffer-file-name)))
         (filename-new (tibetan-analysis-segment-filename seg-id src))
         (filepath-new (expand-file-name filename-new folder))
         ;; Legacy filename without suffix
         (num (cond
               ((numberp seg-id) seg-id)
               ;; Extract segment number specifically (not sentence number)
               ((string-match "Segment \\([0-9]+\\)" seg-id)
                (string-to-number (match-string 1 seg-id)))
               ;; Fallback: try any number
               ((string-match "\\([0-9]+\\)" seg-id)
                (string-to-number (match-string 1 seg-id)))
               (t 1)))
         (filename-old (format "seg-%03d.org" num))
         (filepath-old (expand-file-name filename-old folder)))
    ;; Return new path if it exists, else old path if it exists, else new path
    (cond
     ((file-exists-p filepath-new) filepath-new)
     ((file-exists-p filepath-old) filepath-old)
     (t filepath-new))))

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
                    (cond
                     ;; Extract segment number specifically (not sentence number)
                     ((string-match "Segment \\([0-9]+\\)" seg-id)
                      (string-to-number (match-string 1 seg-id)))
                     ;; Fallback: try any number
                     ((string-match "\\([0-9]+\\)" seg-id)
                      (string-to-number (match-string 1 seg-id)))
                     (t 1)))))
    (with-temp-file filepath
      (insert (format "#+TITLE: Segment %d Analysis\n" seg-num))
      (insert "#+STARTUP: overview\n")
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
  (condition-case err
      (progn
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
               (zero-analysis (condition-case nil
                                  (when (and verbs multiword-units (fboundp 'tibetan-analyze-zero-markers))
                                    (tibetan-analyze-zero-markers verbs multiword-units words))
                                (error nil)))
               (translation (condition-case nil
                                (when (fboundp 'tibetan-get-dharmamitra-translation)
                                  (tibetan-get-dharmamitra-translation tibetan-text))
                              (error nil)))
               (claimed-indices (condition-case nil
                                    (when (fboundp 'tibetan-get-claimed-indices)
                                      (tibetan-get-claimed-indices multiword-units))
                                  (error nil)))
               (particles (when analysis (alist-get 'particles analysis)))
               ;; Build verb lookup table
               (verb-table (make-hash-table :test 'equal)))

    ;; Build verb lookup for quick access
    (dolist (verb verbs)
      (when (and verb (listp verb) (consp (car verb)))
        (let ((lemma (alist-get 'lemma verb)))
          (when lemma
            (puthash lemma verb verb-table)))))

    (with-temp-buffer
      ;; ============================================================
      ;; SECTION 1: Annotated Text (compact format with inline info)
      ;; ============================================================
      (insert "** Annotated Text\n")
      (insert "#+BEGIN_EXAMPLE\n")
      (when (and words (fboundp 'tibetan-build-compound-aware-segments))
        (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
          (dolist (seg segments)
            ;; Wrap each segment in error handler so one failure doesn't break all
            (condition-case seg-err
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
                                               (concat (substring meaning 0 (min 27 (length meaning))) "...")
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
                                   ""))))
              (error
               ;; On error, just output the segment without annotations
               (insert (format "%s [error]\n" seg)))))))
      (insert "#+END_EXAMPLE\n\n")

      ;; Wylie (for reading aloud in class) - shows the Tibetan text
      (insert "** Wylie (for reading aloud)\n")
      (insert tibetan-text)
      (insert "\n\n")

      ;; Transliteration for reference
      (insert "** Transliteration\n")
      (insert (or wylie-full "[Not available]"))
      (insert "\n\n")

      ;; ============================================================
      ;; SECTION 2: Translations (immediately visible)
      ;; ============================================================
      (insert "** Translations\n")
      (insert (format "- DharmaMitra: %s\n" (or translation "[Not available]")))
      (insert "- CAT Suggested: [Generate with C-c t g]\n")
      (insert "\n")

      ;; ============================================================
      ;; SECTION 3: Grammatical Analysis (Bialek)
      ;; ============================================================
      (insert "** Grammatical Analysis (Bialek)\n")
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
                    (reference (nth 5 a)))
                (insert (format "- %s in '%s'\n" particle word))
                (insert (format "  TYPE: %s\n" type))
                (insert (format "  FUNCTION: %s\n" function))
                (insert (format "  TRANSLATION: %s\n" trans-guide))
                (insert (format "  REFERENCE: %s\n\n" reference))))
          (insert "[No grammatical markers detected]\n")))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 4: Sentence Structure (verb-argument analysis)
      ;; ============================================================
      (insert "** Sentence Structure\n")
      (if (and verbs (fboundp 'tibetan-analyze-arguments))
          (let ((any-structure nil))
            (dolist (verb verbs)
              (when (and verb (listp verb) (consp (car verb)))
                (let* ((lemma (alist-get 'lemma verb))
                       (meaning (alist-get 'meaning verb))
                       (frame (or (alist-get 'case_frame verb) "?"))
                       (trans (alist-get 'transitivity verb))
                       (arg-analysis (tibetan-analyze-arguments verb multiword-units words)))
                  (when (or arg-analysis lemma)
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
                    (insert "\n")))))
            (unless any-structure
              (insert "[Structure analysis pending]\n")))
        (insert "[No verb-based structure detected]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 5: Verb Classification (Hill 2010)
      ;; ============================================================
      (insert "** Verb Classification (Hill 2010)\n")
      (if verbs
          (dolist (verb verbs)
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
                (insert (format "- %s" lemma))
                (when meaning
                  (insert (format " — %s" meaning)))
                (insert "\n")
                (insert (format "  STEMS: %s / %s / %s / %s\n" present past future imperative))
                (insert (format "  CLASSIFICATION: %s, %s, %s\n" vol trans frame))
                ;; Add controllability mapping (Schwieger/Bialek terminology)
                (insert (format "  CONTROLLABILITY: %s\n"
                               (cond
                                ((string= vol "Volitional") "Controllable (བྱེད་པ་པོ་ can control)")
                                ((string= vol "Non-volitional") "Uncontrollable (བྱེད་པ་པོ་ cannot control)")
                                ((string= vol "Both") "Context-dependent")
                                (t "?"))))
                (insert (format "  TIBETAN CLASS: %s\n\n"
                               (cond
                                ((string= class "tha_dad_pa") "ཐ་དད་པ་ (transitive)")
                                ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (intransitive)")
                                (t "—")))))))
        (insert "[No verbs]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 6: Zero Markers & Special Notes
      ;; ============================================================
      (when zero-analysis
        (insert "** Zero-Marked NPs\n")
        (dolist (item zero-analysis)
          (let ((form (alist-get 'form item))
                (function (alist-get 'function item))
                (position (alist-get 'position item))
                (distance (alist-get 'distance-from-verb item))
                (gloss (alist-get 'gloss item)))
            (insert (format "- %s (Ø)" form))
            ;; Show position info if available
            (when (and position distance)
              (insert (format " [word #%d, %d before verb]" position distance)))
            (insert (format ": %s" function))
            (when gloss (insert (format " — %s" gloss)))
            (insert "\n")))
        (insert "\n"))

      (buffer-string))))
    (error
     ;; On error, return minimal analysis with error info
     (format "** Annotated Text\n%s\n\n** Full Wylie\n[Error during analysis]\n\n** Verb Details\n[Error: %s]\n\n** Sentence Structure\n[Analysis error]\n"
             tibetan-text (error-message-string err)))))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

(defun tibetan-open-segment-analysis ()
  "Open or create analysis based on current position.

Context-aware behavior:
- On *** Segment heading: word-by-word segment analysis
- On ** Sentence heading: clause structure analysis (main verb, converbs)

This is the main entry point for C-c u A."
  (interactive)
  (require 'tibetan-org-structure nil t)

  ;; Determine context: segment or sentence?
  (cond
   ;; At a segment (level 3) - do word-by-word analysis
   ((and (fboundp 'tibetan-org-at-segment-p)
         (tibetan-org-at-segment-p))
    (tibetan--open-segment-word-analysis))

   ;; At a sentence (level 2) - do clause analysis
   ((and (fboundp 'tibetan-org-at-sentence-p)
         (tibetan-org-at-sentence-p))
    (tibetan--open-sentence-clause-analysis))

   ;; Fallback to old behavior (try segment)
   (t
    (tibetan--open-segment-word-analysis))))

(defun tibetan--open-segment-word-analysis ()
  "Open or create word-by-word analysis for current segment.
Called when cursor is on a *** Segment heading."
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

(defun tibetan--open-sentence-clause-analysis ()
  "Open clause structure analysis for current sentence.
Called when cursor is on a ** Sentence heading.
Shows main verb, converbs, and clause dependencies."
  (require 'tibetan-clause-analysis nil t)

  (let* ((sent-data (tibetan-org-get-sentence-data))
         (sent-id (car sent-data))
         (tibetan-text (cdr sent-data)))

    (unless sent-data
      (error "Not in a sentence heading"))

    ;; Generate clause analysis
    (let* ((analysis-text
            (if (fboundp 'tibetan-analyze-clause-structure)
                (tibetan-analyze-clause-structure tibetan-text)
              "Clause analysis module not loaded."))
           (segments (tibetan-org-get-sentence-segments))
           (buf-name (format "*Clause Analysis: %s*" sent-id)))

      ;; Create or reuse buffer
      (let ((buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (erase-buffer)
          (org-mode)

          ;; Header
          (insert (format "#+TITLE: Clause Analysis - %s\n\n" sent-id))

          ;; Original text
          (insert "* Tibetan Text\n\n")
          (insert tibetan-text)
          (insert "\n\n")

          ;; Segments breakdown
          (insert "* Segments\n\n")
          (let ((n 0))
            (dolist (seg segments)
              (setq n (1+ n))
              (insert (format "%d. %s\n" n seg))))
          (insert "\n")

          ;; Clause analysis
          (insert "* Clause Structure\n\n")
          (insert analysis-text)

          ;; Grammar notes placeholder
          (insert "\n* Grammar Notes\n\n")
          (insert "Add your notes about the sentence structure here.\n\n")

          ;; Translation section
          (insert "* Translation\n\n")
          (insert "Your translation of the complete sentence:\n\n")

          ;; Setup faces
          (tibetan-analysis-setup-faces)
          (goto-char (point-min)))

        ;; Display in side window
        (display-buffer-in-side-window buf
                                       '((side . right)
                                         (window-width . 0.5)))
        (message "Showing clause analysis for %s (%d segments)"
                 sent-id (length segments))))))

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
