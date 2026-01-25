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
(require 'tibetan-vocabulary-detailed nil t)

(defconst tibetan-analysis-version "1.0"
  "Version of the analysis file format.")

;; ============================================================================
;; RESOURCES FOLDER VOCABULARY INTEGRATION
;; ============================================================================

(defvar tibetan-analysis-resources-vocab nil
  "Hash table of vocabulary from Resources folder.
Loaded when analysis is opened, keyed by Tibetan text.")

(defun tibetan-analysis-find-resources-folder ()
  "Find the Resources folder relative to current buffer.
Looks for ../Resources/ relative to the Work in progress folder."
  (let* ((buf-file (buffer-file-name))
         (buf-dir (when buf-file (file-name-directory buf-file))))
    (when buf-dir
      (let ((resources-dir (expand-file-name "../Resources" buf-dir)))
        (when (file-directory-p resources-dir)
          resources-dir)))))

(defun tibetan-analysis-load-resources-vocab ()
  "Load vocabulary from Resources folder if available.
Parses PDF word lists and org vocabulary files.
Returns hash table of tibetan -> (meaning . source) pairs."
  (let ((resources-dir (tibetan-analysis-find-resources-folder))
        (vocab-hash (make-hash-table :test 'equal)))
    (when resources-dir
      ;; Look for org files with vocabulary lists
      (dolist (file (directory-files resources-dir t "\\.org$"))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          ;; Parse org description lists: - tibetan :: meaning
          (while (re-search-forward "^- \\*?\\([^:*]+\\)\\*? *:: *\\(.+\\)$" nil t)
            (let ((term (string-trim (match-string 1)))
                  (meaning (string-trim (match-string 2))))
              (puthash term (cons meaning (file-name-nondirectory file)) vocab-hash)))))
      ;; Also check for Wortliste/word list text files
      (dolist (file (directory-files resources-dir t "\\(Wortliste\\|word.*list\\).*\\.txt$"))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          ;; Try common formats:
          ;; tibetan = meaning
          ;; tibetan: meaning
          (while (re-search-forward "^\\([^=:\n]+\\)[=:] *\\(.+\\)$" nil t)
            (let ((term (string-trim (match-string 1)))
                  (meaning (string-trim (match-string 2))))
              (puthash term (cons meaning (file-name-nondirectory file)) vocab-hash))))))
    vocab-hash))

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
Sets body text to 10pt, headings to max 12pt for Latin fonts,
and Tibetan script significantly larger for better readability."
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
  (face-remap-add-relative 'org-property-value :height 100)

  ;; Make Tibetan script significantly larger (180 = 1.8x)
  ;; This uses a font-lock rule to detect Tibetan Unicode range
  (font-lock-add-keywords nil
    '(("[ༀ-࿿]+" . 'tibetan-analysis-tibetan-face)))
  (face-remap-add-relative 'tibetan-analysis-tibetan-face :height 180))

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
      (insert "#+STARTUP: showall\n")
      (insert (format "#+SOURCE: [[file:../%s::*Segment %d][%s / Segment %d]]\n"
                      source-name seg-num source-name seg-num))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-analysis-version))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      ;; Tibetan Text section with Wylie subsection
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      ;; Auto-generated analysis content (no wrapper section)
      (insert auto-content)
      (insert "\n")
      ;; User sections
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      (insert "* Footnotes\n\n")
      ;; Detailed vocabulary with full dictionary entries (auto-generated)
      (insert "* Detailed Vocabulary\n")
      (insert "Full dictionary entries for reference:\n\n")
      (let ((vocab (condition-case nil
                       (when (fboundp 'tibetan-extract-vocabulary)
                         (tibetan-extract-vocabulary tibetan-text))
                     (error nil))))
        (if vocab
            (insert (tibetan-vocab-format-detailed-list vocab t))
          (insert "[No vocabulary]")))
      (insert "\n\n"))
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

(defun tibetan-analysis--get-particle-annotation (word &optional context)
  "Get compact particle annotation for WORD.
CONTEXT, if provided, helps determine the specific function.
Returns string like '(ERG)' or '(LOC: if/when)' or nil.
Note: Particles like པ/བ are handled in context as suffixes, not standalone."
  (cond
   ;; Ergative/Instrumental
   ((member word '("ས" "གིས" "ཀྱིས" "གྱིས" "ཡིས"))
    "(ERG/INST: by/with)")
   ;; Genitive
   ((member word '("འི" "གི" "ཀྱི" "གྱི" "ཡི"))
    "(GEN: of/'s)")
   ;; Locative/Conditional
   ((string= word "ན")
    "(LOC: in/if/when)")
   ;; Dative (only ལ)
   ((string= word "ལ")
    "(DAT: to/for/at)")
   ;; Terminative (NOT dative!) - ར/སུ/ཏུ/དུ mark goal/direction/manner
   ((member word '("ར" "སུ" "ཏུ" "དུ"))
    "(TERM: toward/into/as)")
   ;; Ablative
   ((string= word "ནས")
    "(ABL: from/after)")
   ((string= word "ལས")
    "(ABL: from/than)")
   ;; Comitative
   ((string= word "དང")
    "(COM: and/with)")
   ;; Converbs - provide translation hints
   ((member word '("སྟེ" "ཏེ" "དེ"))
    "(CONV: and/then/since)")
   ((member word '("ཅིང" "ཞིང" "ཤིང"))
    "(CONV: while/-ing)")
   ;; Note: པ/བ as standalone words are rarely particles
   ;; They're usually part of verb forms like བཞུགས་པའི - these are handled contextually
   ;; Don't annotate standalone པ/བ to avoid confusion
   ;; ((member word '("པ" "བ"))
   ;;  nil)  ; Skip - handled in context
   ;; Agent nominalizer (one who does X)
   ((member word '("པོ" "བོ"))
    "(AGT: one who)")
   ;; Imperative/Indefinite markers
   ((member word '("ཅིག" "ཤིག" "ཞིག"))
    "(IMP/INDEF: a/one)")
   ;; Topic
   ((string= word "ནི")
    "(TOP: as for)")
   ;; Comparative particle
   ((string= word "བས")
    "(COMP: than)")
   ;; Sentence-final particles - don't annotate, they're punctuation-like
   ((member word '("སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ"))
    nil)
   (t nil)))

(defun tibetan-analysis--get-word-info (word multiword-units)
  "Get meaning and info for WORD, checking MULTIWORD-UNITS first.
Returns alist with keys: meaning, wylie, is-verb, verb-info.
Also handles common suffixed forms like པའི་ཚེ (when/at the time)."
  (let ((info '())
        (meaning nil)
        (wylie nil))
    ;; Check multiword-units first
    (dolist (unit multiword-units)
      (when (string= (nth 2 unit) word)
        (let ((data (nth 3 unit)))
          (setq meaning (alist-get 'english data))
          (setq wylie (alist-get 'wylie data)))))
    ;; Special handling for common suffixed constructions
    (unless meaning
      (cond
       ;; པའི་ཚེ / བའི་ཚེ = "when/at the time of"
       ((or (string-suffix-p "པའི་ཚེ" word) (string-suffix-p "བའི་ཚེ" word))
        (setq meaning "when/at the time when"))
       ;; པའི / བའི after verb = "the one who / that which"
       ((and (> (length word) 3)
             (or (string-suffix-p "པའི" word) (string-suffix-p "བའི" word)))
        nil)  ; Let regular lookup handle it
       ;; ཅན = "having/possessing"
       ((string-suffix-p "ཅན" word)
        (let ((root (substring word 0 (- (length word) 2))))
          (when (> (length root) 0)
            (setq meaning (format "having %s" (or (tibetan-lookup-word root) root))))))))
    ;; If not found, try Resources vocabulary first (via tibetan-lookup-word)
    (unless meaning
      (when (fboundp 'tibetan-lookup-word)
        (setq meaning (tibetan-lookup-word word))))
    ;; If not found, try comprehensive vocabulary directly
    (unless meaning
      (when (and (boundp 'tibetan-comprehensive-vocabulary)
                 tibetan-comprehensive-vocabulary)
        (setq meaning (gethash word tibetan-comprehensive-vocabulary))))
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
      ;; SECTION 1: Wylie Transliteration (subsection under Tibetan Text)
      ;; ============================================================
      (insert "** Wylie Transliteration\n")
      (insert (or wylie-full "[Not available]"))
      (insert "\n\n")

      ;; ============================================================
      ;; SECTION 2: Translations
      ;; ============================================================
      (insert "** Translations\n")
      (insert (format "- DharmaMitra: %s\n" (or translation "[Not available]")))
      ;; Auto-generate CAT translation if function is available
      (let ((cat-translation (condition-case nil
                                 (when (fboundp 'tibetan-cat-generate-translation)
                                   (tibetan-cat-generate-translation tibetan-text))
                               (error nil))))
        (insert (format "- CAT Suggested: %s\n" (or cat-translation "[Generate with C-c u t]"))))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 3: Vocabulary (short format - primary meanings)
      ;; ============================================================
      (insert "** Vocabulary\n")
      (let ((vocab-list (condition-case nil
                            (when (fboundp 'tibetan-vocab-extract-detailed)
                              (tibetan-vocab-extract-detailed tibetan-text))
                          (error nil))))
        (if vocab-list
            (progn
              (dolist (entry vocab-list)
                (let* ((tibetan (plist-get entry :tibetan))
                       (wylie (plist-get entry :wylie))
                       (primary (plist-get entry :primary))
                       (source (plist-get entry :source)))
                  (insert (format "- %s /*%s*/ — %s"
                                  tibetan
                                  (or wylie "?")
                                  (or primary "[not found]")))
                  (when (and source (string= source "Resources"))
                    (insert " ★"))
                  (insert "\n")))
              (insert "\n"))
          ;; Fallback to old system
          (let ((vocab (condition-case nil
                           (when (fboundp 'tibetan-extract-vocabulary)
                             (tibetan-extract-vocabulary tibetan-text))
                         (error nil))))
            (if vocab
                (dolist (word-pair vocab)
                  (insert (format "- %s — %s\n" (car word-pair) (cdr word-pair))))
              (insert "[Vocabulary lookup failed]\n")))
          (insert "\n")))

      ;; ============================================================
      ;; SECTION 3b: Detailed Dictionary (full entries)
      ;; ============================================================
      (insert "** Detailed Dictionary\n")
      (let ((vocab-list (condition-case nil
                            (when (fboundp 'tibetan-vocab-extract-detailed)
                              (tibetan-vocab-extract-detailed tibetan-text))
                          (error nil))))
        (if vocab-list
            (dolist (entry vocab-list)
              (let* ((tibetan (plist-get entry :tibetan))
                     (wylie (plist-get entry :wylie))
                     (primary (plist-get entry :primary))
                     (detailed (plist-get entry :detailed))
                     (sanskrit (plist-get entry :sanskrit))
                     (source (plist-get entry :source)))
                (insert (format "*** %s" tibetan))
                (when wylie (insert (format "  [%s]" wylie)))
                (when (and source (string= source "Resources"))
                  (insert " ★"))
                (insert "\n")
                (insert (format "  %s\n" (or primary "[not found]")))
                (when (and detailed
                           (not (string= detailed primary))
                           (> (length detailed) (length primary)))
                  (insert (format "  Full: %s\n"
                                  (if (> (length detailed) 300)
                                      (concat (substring detailed 0 297) "...")
                                    detailed))))
                (when sanskrit
                  (insert (format "  Sanskrit: %s\n" sanskrit)))
                (insert "\n")))
          (insert "[Detailed dictionary not available]\n"))
        (insert "\n"))

      ;; ============================================================
      ;; SECTION 4: Grammatical Analysis (Bialek)
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
      ;; SECTION 5: Sentence Structure (enhanced verb-argument analysis)
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
                    ;; Display arguments with grammatical function labels
                    (dolist (arg arg-analysis)
                      (let* ((role (alist-get 'role arg))
                             (marker (alist-get 'marker arg))
                             (form (alist-get 'form arg))
                             (english (alist-get 'english arg))
                             (function (alist-get 'function arg))
                             (is-topic (alist-get 'is-topic arg))
                             ;; Determine grammatical function (SUBJECT/DIRECT OBJECT/INDIRECT OBJECT)
                             (gram-function (cond
                                            ((string= role "ERGATIVE") "SUBJECT (agent)")
                                            ((string= role "ABSOLUTIVE")
                                             (if (string-match-p "Transitive" (or trans ""))
                                                 "DIRECT OBJECT (patient)"
                                               "SUBJECT (experiencer)"))
                                            ((string= role "DATIVE") "INDIRECT OBJECT (recipient/goal)")
                                            ((string= role "TOPIC") "TOPIC (discourse focus)")
                                            (t role))))
                        (unless is-topic
                          (insert (format "  - %s: %s" gram-function form))
                          (when english (insert (format " \"%s\"" english)))
                          (insert (format " (%s)\n" (if (string= marker "Ø") "Ø - zero-marked" marker))))))
                    (insert "\n")))))
            (unless any-structure
              (insert "[Structure analysis pending]\n")))
        (insert "[No verb-based structure detected]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 5b: Converb/Dependent Clause Analysis
      ;; ============================================================
      (let ((converbs (condition-case nil
                          (when (fboundp 'tibetan-analyze-converbs-bialek)
                            (tibetan-analyze-converbs-bialek tibetan-text))
                        (error nil))))
        (when converbs
          (insert "** Converbial Constructions\n")
          (insert "  (These are DEPENDENT CLAUSES that modify the main verb)\n\n")
          (dolist (conv converbs)
            (let ((particle (nth 0 conv))
                  (word (nth 1 conv))
                  (type (nth 2 conv))
                  (function (nth 3 conv))
                  (translation (nth 4 conv)))
              (insert (format "- %s (%s)\n" word particle))
              (insert (format "  TYPE: %s\n" type))
              (insert (format "  FUNCTION: %s\n" function))
              (insert (format "  TRANSLATION: %s\n\n" translation))))
          (insert "\n")))

      ;; ============================================================
      ;; SECTION 6: Verb Classification (Hill 2010)
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
                (tibetan-analysis-setup-faces)
                ;; Apply startup visibility (expand all sections per #+STARTUP: showall)
                (when (derived-mode-p 'org-mode)
                  (org-show-all)))
              (display-buffer-in-side-window buf
                                             '((side . right)
                                               (window-width . 0.5)))))
        ;; Create new file
        (let* ((auto-content (tibetan-analysis-generate-content tibetan-text))
               (new-filepath (tibetan-analysis-create-file seg-id tibetan-text source-file auto-content)))
          (message "Created analysis file: %s" new-filepath)
          (let ((buf (find-file-noselect new-filepath)))
            (with-current-buffer buf
              (tibetan-analysis-setup-faces)
              ;; Apply startup visibility (expand all sections per #+STARTUP: showall)
              (when (derived-mode-p 'org-mode)
                (org-show-all)))
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

;; ============================================================================
;; BATCH ANALYSIS - Analyze all segments in a file
;; ============================================================================

(defun tibetan-collect-all-segments ()
  "Collect all segments from current buffer.
Returns list of (seg-id . tibetan-text) cons cells."
  (require 'tibetan-org-structure nil t)
  (let ((segments '()))
    (save-excursion
      (goto-char (point-min))
      ;; Find all *** Segment headings
      (while (re-search-forward "^\\*\\*\\* Segment \\([0-9]+\\)" nil t)
        (let* ((seg-num (string-to-number (match-string 1)))
               (heading-text (org-get-heading t t t t)))
          ;; Move into the segment to get the text
          (when (tibetan-org-at-segment-p)
            (let ((text (tibetan-org-get-segment-text))
                  (sent-num (tibetan-org-get-sentence-id))
                  (section-name (tibetan-org-get-parent-section-name)))
              (when text
                ;; Build segment ID
                (let ((seg-id (cond
                               ((and sent-num seg-num)
                                (format "Sentence %d, Segment %d" sent-num seg-num))
                               ((and section-name seg-num)
                                (format "%s, Segment %d" section-name seg-num))
                               (t
                                (format "Segment %d" seg-num)))))
                  (push (cons seg-id text) segments))))))))
    (nreverse segments)))

(defun tibetan-analyze-all-segments ()
  "Analyze all segments in the current buffer and create analysis files.

Prompts whether to regenerate existing analysis files.
Creates an analysis file for each *** Segment heading found.
Shows progress in the echo area.

This is also available via Menu: Tibetan > Batch Analyze All Segments"
  (interactive)
  (require 'tibetan-org-structure nil t)
  (unless (derived-mode-p 'org-mode)
    (error "This command only works in org-mode buffers"))

  (let* ((source-file (buffer-file-name))
         (segments (tibetan-collect-all-segments))
         (total (length segments))
         (created 0)
         (updated 0)
         (skipped 0)
         (errors '())
         ;; Count existing files
         (existing-count 0))

    (unless segments
      (error "No segments found in buffer"))

    ;; Count how many analysis files already exist
    (dolist (seg segments)
      (let* ((seg-id (car seg))
             (filepath (tibetan-analysis-get-filepath seg-id source-file)))
        (when (file-exists-p filepath)
          (setq existing-count (1+ existing-count)))))

    ;; Prompt user about what to do with existing files
    (let ((reanalyze nil))
      (when (> existing-count 0)
        (let ((choice (read-char-choice
                       (format "Found %d segments (%d already have analysis files).
[n] Create new only (skip existing)
[r] Re-analyze existing (preserve notes)
[c] Cancel
Choice: " total existing-count)
                       '(?n ?r ?c))))
          (cond
           ((eq choice ?c)
            (user-error "Cancelled"))
           ((eq choice ?r)
            (setq reanalyze t)))))

      (message "Analyzing %d segments..." total)

      ;; Ensure analysis folder exists
      (let ((folder (tibetan-analysis-get-folder)))
        (unless (file-exists-p folder)
          (make-directory folder t)))

      ;; Process each segment
      (let ((n 0))
        (dolist (seg segments)
          (setq n (1+ n))
          (let* ((seg-id (car seg))
                 (tibetan-text (cdr seg))
                 (filepath (tibetan-analysis-get-filepath seg-id source-file))
                 (exists (file-exists-p filepath)))

            (message "Processing %d/%d: %s..." n total seg-id)

            (condition-case err
                (if exists
                    ;; File exists
                    (if reanalyze
                        ;; Regenerate auto-analysis section
                        (let ((auto-content (tibetan-analysis-generate-content tibetan-text)))
                          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
                          (setq updated (1+ updated)))
                      ;; Skip existing files
                      (setq skipped (1+ skipped)))
                  ;; Create new file
                  (let ((auto-content (tibetan-analysis-generate-content tibetan-text)))
                    (tibetan-analysis-create-file seg-id tibetan-text source-file auto-content)
                    (setq created (1+ created))))
              (error
               (push (format "%s: %s" seg-id (error-message-string err)) errors)))))))

    ;; Report results
    (if errors
        (message "Done. Created: %d, Updated: %d, Skipped: %d, ERRORS: %d\n%s"
                 created updated skipped (length errors)
                 (mapconcat 'identity errors "\n"))
      (message "Done! Created: %d, Updated: %d, Skipped: %d" created updated skipped))))

;; Keep alias for backwards compatibility
(defalias 'tibetan-reanalyze-all-segments 'tibetan-analyze-all-segments)

;; ============================================================================
;; DHARMAMITRA RE-REQUEST
;; ============================================================================

(defun tibetan-refresh-dharmamitra-translation ()
  "Re-request DharmaMitra translation for the current analysis file.
Works when called from within an analysis buffer.
Updates the DharmaMitra line in the ** Translations section."
  (interactive)
  ;; Check we're in an analysis file
  (unless (and buffer-file-name
               (string-match-p "/analysis/" buffer-file-name)
               (string-match-p "\\.org$" buffer-file-name))
    (error "This command must be run from within an analysis file"))

  ;; Get the Tibetan text from the file
  (let ((tibetan-text nil))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text$" nil t)
        (forward-line 1)
        (let ((start (point)))
          (if (re-search-forward "^\\* " nil t)
              (setq tibetan-text (string-trim
                                  (buffer-substring-no-properties
                                   start (line-beginning-position))))
            (setq tibetan-text (string-trim
                                (buffer-substring-no-properties
                                 start (point-max))))))))

    (unless tibetan-text
      (error "Could not find Tibetan text in this analysis file"))

    ;; Request new translation
    (message "Requesting DharmaMitra translation...")
    (let ((new-translation
           (if (fboundp 'tibetan-get-dharmamitra-translation)
               (tibetan-get-dharmamitra-translation tibetan-text)
             "[DharmaMitra not available]")))

      ;; Update the DharmaMitra line in the file
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^- DharmaMitra: .*$" nil t)
            (replace-match (format "- DharmaMitra: %s" new-translation))
          ;; If no DharmaMitra line exists, add it after ** Translations
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\* Translations$" nil t)
            (forward-line 1)
            (insert (format "- DharmaMitra: %s\n" new-translation)))))

      (save-buffer)
      (message "DharmaMitra translation updated: %s"
               (if (> (length new-translation) 60)
                   (concat (substring new-translation 0 57) "...")
                 new-translation)))))

(defun tibetan-copy-dharmamitra-to-working ()
  "Copy DharmaMitra translation to the Working Translation section.
Useful as a starting point for your own translation."
  (interactive)
  ;; Get DharmaMitra translation
  (let ((dm-trans nil))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^- DharmaMitra: \\(.+\\)$" nil t)
        (setq dm-trans (match-string 1))))

    (unless dm-trans
      (error "No DharmaMitra translation found. Try C-c u D to request one."))

    ;; Find Working Translation section and insert
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward "^\\* Working Translation$" nil t)
          (progn
            (forward-line 1)
            ;; Skip any existing content markers
            (when (looking-at "^$")
              (forward-line 1))
            (insert (format "\n[DharmaMitra suggestion:]\n%s\n\n" dm-trans))
            (save-buffer)
            (message "DharmaMitra translation copied to Working Translation section"))
        (error "Could not find Working Translation section")))))

(provide 'tibetan-analysis-persist)
;;; tibetan-analysis-persist.el ends here
