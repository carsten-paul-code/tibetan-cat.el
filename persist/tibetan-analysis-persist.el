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
SEG-ID can be a number or string like '1' or 'seg-001'.
Returns filename like 'seg-001.org'."
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
E.g., 'Tigress-Story-BlockPrint-Class.org' -> 'tigress'
      'Reading-Sa-skya-legs-bshad.org' -> 'saskya'
      'Reading-05-Padma.org' -> 'padma'"
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

(defun tibetan-analysis--get-grammatical-role (word root-form verb-table)
  "Determine grammatical role description for WORD with ROOT-FORM.
Uses VERB-TABLE for verb detection.
Returns a string like 'Noun', 'Verb in conjunctive form', 'Genitive particle', etc."
  (let ((role nil)
        (verb-info (or (gethash word verb-table) (gethash root-form verb-table))))
    (cond
     ;; Check if it's a recognized verb
     (verb-info
      (let ((trans (or (alist-get 'transitivity verb-info) ""))
            (suffix-type (tibetan-analysis--detect-verb-suffix word root-form)))
        (setq role (concat (if (string-match-p "Transitive" trans) "Transitive verb" "Verb")
                          (or suffix-type "")))))

     ;; Sentence-final particles
     ((member word '("རོ" "སོ" "ཏོ" "ནོ" "དོ" "འོ" "ངོ"))
      (setq role "Sentence-final particle"))

     ;; Topic marker
     ((string= word "ནི")
      (setq role "Topic particle"))

     ;; Converbs (standalone)
     ((member word '("ཅིང" "ཞིང" "ཤིང"))
      (setq role "Simultaneous converb"))
     ((member word '("སྟེ" "ཏེ" "དེ"))
      (setq role "Sequential converb"))

     ;; Genitive particles
     ((or (member word '("གི" "ཀྱི" "གྱི" "ཡི"))
          (string-suffix-p "འི" word))
      (setq role "Genitive particle"))

     ;; Ergative/instrumental particles
     ((member word '("གིས" "ཀྱིས" "གྱིས" "ཡིས" "ས"))
      (setq role "Ergative/instrumental particle"))

     ;; Dative/locative particles
     ((member word '("ལ" "ར" "དུ" "ཏུ" "སུ" "རུ"))
      (setq role "Locative particle"))

     ;; Ablative
     ((member word '("ནས" "ལས"))
      (setq role "Ablative particle"))

     ;; Conditional
     ((string= word "ན")
      (setq role "Conditional/locative particle"))

     ;; Concessive
     ((member word '("ཀྱང" "ཡང" "འང"))
      (setq role "Concessive particle"))

     ;; Nominalizers
     ((member word '("པ" "བ"))
      (setq role "Nominalizer"))
     ((member word '("པོ" "བོ"))
      (setq role "Agentive nominalizer"))

     ;; Question particles
     ((member word '("དམ" "གམ" "ངམ" "ནམ" "བམ" "འམ"))
      (setq role "Question particle"))

     ;; Imperative particles
     ((member word '("ཅིག" "ཤིག" "ཞིག"))
      (setq role "Imperative particle"))

     ;; Default: noun
     (t (setq role "Noun")))

    role))

(defun tibetan-analysis--detect-verb-suffix (word root-form)
  "Detect verb suffix type by comparing WORD to ROOT-FORM.
Returns a suffix description string or nil."
  (cond
   ;; Word ends with converb particle
   ((string-suffix-p "ཅིང" word) ", conjunctive form (simultaneous)")
   ((string-suffix-p "ཞིང" word) ", conjunctive form (simultaneous)")
   ((string-suffix-p "སྟེ" word)  ", sequential converb form")
   ((string-suffix-p "ཏེ" word)  ", sequential converb form")
   ;; Word ends with nominalized + case
   ((string-suffix-p "བར" word)  ", nominalized form with terminative")
   ((string-suffix-p "པར" word)  ", nominalized form with terminative")
   ;; Word ends with genitive on nominalized form
   ((string-suffix-p "པའི" word) ", nominalized genitive form")
   ((string-suffix-p "བའི" word) ", nominalized genitive form")
   ;; Word ends with causal converb
   ((string-suffix-p "པས" word)  ", causal converb form")
   ((string-suffix-p "བས" word)  ", causal converb form")
   ;; Sentence-final ro/so etc.
   ((string-suffix-p "རོ" word)  ", with assertive sentence-final particle")
   ((string-suffix-p "སོ" word)  ", with assertive sentence-final particle")
   (t nil)))

(defun tibetan-analysis--build-cat-translation (vocab-pairs)
  "Build a CAT-suggested translation from VOCAB-PAIRS.
VOCAB-PAIRS is a list of (word . meaning) pairs.
Returns a rough English gloss string."
  (let ((parts '()))
    (dolist (pair vocab-pairs)
      (let ((meaning (cdr pair)))
        (when (and meaning (not (string= meaning "[look up]"))
                   (not (string= meaning "[not found]")))
          ;; Extract first short meaning
          (let ((short (car (split-string meaning "[;|,]" t))))
            (when short
              (push (string-trim short) parts))))))
    (if parts
        (string-join (nreverse parts) " ")
      "[Generate with C-c t g]")))

(defun tibetan-analysis--generate-particle-map (tibetan-text particles verbs)
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
                          "dang"))                          ; comitative
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
            (when (and lemma (or (string-match-p "Transitive" (or trans ""))
                                 (string-match-p "Erg" (or frame ""))))
              (push (format "[Ø AGENT expected before %s]"
                           (condition-case nil
                               (tibetan-to-wylie-fixed lemma)
                             (error lemma)))
                    zero-notes)))))
      (when zero-notes
        (setq result (concat result "\n\n" (string-join (nreverse zero-notes) "\n")))))

    result))

(defun tibetan-analysis-generate-content (tibetan-text)
  "Generate auto-analysis content for TIBETAN-TEXT.
Returns the analysis as a string (org-mode formatted).
DharmaMitra-style vocabulary with lemma forms and grammatical roles."
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
               (verb-table (make-hash-table :test 'equal))
               ;; Extract vocabulary for DharmaMitra-style display
               (vocab-pairs (condition-case nil
                                (when (fboundp 'tibetan-extract-vocabulary)
                                  (tibetan-extract-vocabulary tibetan-text))
                              (error nil))))

          ;; Build verb lookup for quick access
          (dolist (verb verbs)
      (when (and verb (listp verb) (consp (car verb)))
        (let ((lemma (alist-get 'lemma verb)))
          (when lemma
            (puthash lemma verb verb-table)))))

    (with-temp-buffer
      ;; ============================================================
      ;; SECTION 1: Wylie Transliteration
      ;; ============================================================
      (insert "** Wylie Transliteration\n")
      (insert (or wylie-full "[Not available]"))
      (insert "\n\n")

      ;; ============================================================
      ;; SECTION 2: Translations
      ;; ============================================================
      (insert "** Translations\n")
      (when (and translation
                 (not (string= translation "[Translation not available]"))
                 (not (string= translation "[DharmaMitra not loaded]")))
        (insert (format "- DharmaMitra: %s\n" translation)))
      ;; Build CAT suggested translation from vocabulary
      (let ((cat-trans (when vocab-pairs
                         (tibetan-analysis--build-cat-translation vocab-pairs))))
        (insert (format "- CAT Suggested: %s\n" (or cat-trans "[Generate with C-c t g]"))))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 3: Vocabulary (DharmaMitra style - clean table format)
      ;; ============================================================
      (insert "** Vocabulary\n")
      (if vocab-pairs
          (progn
            ;; DharmaMitra format: word, lemma, wylie, grammatical role, 'meaning'
            (dolist (pair vocab-pairs)
              (let* ((word (car pair))
                     (meaning (cdr pair))
                     (root-form (tibetan-strip-particles word))
                     ;; Get Wylie for the word form
                     (wylie-word (condition-case nil
                                     (when (fboundp 'tibetan-to-wylie-fixed)
                                       (tibetan-to-wylie-fixed word))
                                   (error nil)))
                     ;; Determine grammatical role
                     (gram-role (tibetan-analysis--get-grammatical-role
                                 word root-form verb-table))
                     ;; Lemma (root form) - same as word if no particles stripped
                     (lemma (if (and root-form
                                     (not (string= root-form word))
                                     (not (string-empty-p root-form)))
                                root-form
                              word))
                     ;; Clean meaning: extract first short definition
                     (short-meaning (when (and meaning
                                               (not (string= meaning "[look up]"))
                                               (not (string= meaning "[not found]")))
                                      (let ((m (car (split-string meaning "[;,]" t))))
                                        (when m (format "'%s'" (string-trim m)))))))
                ;; Format: word, lemma, wylie, role, 'meaning'
                (insert (format "- %s, %s, %s, %s"
                                word
                                lemma
                                (or wylie-word "?")
                                (or gram-role "?")))
                (when short-meaning
                  (insert (format ", %s" short-meaning)))
                (insert "\n"))))
        (insert "[Vocabulary extraction not available]\n"))
      (insert "\n")

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
                    (trans-guide (nth 4 a)))
                ;; Format: particle in "word" → TYPE: translation
                ;; Don't use =...= for Tibetan as it forces monospace font
                (insert (format "- %s in «%s» → %s: %s\n"
                                particle word type
                                (or trans-guide function)))))
          (insert "[No grammatical markers detected]\n")))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 4: Sentence Structure - compact argument analysis
      ;; ============================================================
      (insert "** Sentence Structure\n")
      (if (and verbs (fboundp 'tibetan-analyze-arguments))
          (let ((any-structure nil))
            (dolist (verb verbs)
              (when (and verb (listp verb) (consp (car verb)))
                (let* ((lemma (alist-get 'lemma verb))
                       (meaning (alist-get 'meaning verb))
                       (arg-analysis (tibetan-analyze-arguments verb multiword-units words)))
                  (when (or arg-analysis lemma)
                    (setq any-structure t)
                    ;; Show verb with arguments inline
                    (insert (format "- %s" lemma))
                    (when meaning
                      (insert (format " '%s'" (car (split-string meaning "," t)))))
                    (insert ":")
                    ;; Arguments on same line if few
                    (let ((args-shown 0))
                      (dolist (arg arg-analysis)
                        (let ((role (alist-get 'role arg))
                              (marker (alist-get 'marker arg))
                              (form (alist-get 'form arg))
                              (is-topic (alist-get 'is-topic arg)))
                          (unless is-topic
                            (insert (format " %s(%s)" form (or marker "Ø")))
                            (setq args-shown (1+ args-shown))))))
                    (insert "\n")))))
            (unless any-structure
              (insert "[No argument structure detected]\n")))
        (insert "[No verbs detected]\n"))
      (insert "\n")

      ;; ============================================================
      ;; SECTION 5: Verb Classification (Hill 2010) - detailed format
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
                (insert (format "  CLASS: %s, %s, %s\n" vol trans frame))
                (insert (format "  TIBETAN: %s\n\n"
                               (cond
                                ((string= class "tha_dad_pa") "ཐ་དད་པ་ (transitive)")
                                ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (intransitive)")
                                (t "—")))))))
        (insert "[No verbs detected]\n"))
      (insert "\n")

      ;; NOTE: Zero-Marked NPs section removed - was producing confusing output

      ;; ============================================================
      ;; SECTION 7: Detailed Dictionary
      ;; ============================================================
      (when vocab-pairs
        (insert "** Detailed Dictionary\n")
        (insert "Full dictionary entries for reference:\n\n")
        (dolist (pair vocab-pairs)
          (let* ((word (car pair))
                 (meaning (cdr pair))
                 (root-form (tibetan-strip-particles word))
                 (wylie-word (condition-case nil
                                 (when (fboundp 'tibetan-to-wylie-fixed)
                                   (tibetan-to-wylie-fixed
                                    (if (and root-form (not (string-empty-p root-form))
                                             (not (string= root-form word)))
                                        root-form word)))
                               (error nil)))
                 ;; Try to get fuller entry from glossary
                 (full-entry (when (and (boundp 'tibetan-comprehensive-vocabulary)
                                       tibetan-comprehensive-vocabulary)
                               (or (gethash word tibetan-comprehensive-vocabulary)
                                   (gethash root-form tibetan-comprehensive-vocabulary))))
                 (full-meaning (cond
                                ((and full-entry (listp full-entry))
                                 (mapconcat #'identity full-entry "; "))
                                ((stringp full-entry) full-entry)
                                (t nil)))
                 (display-form (if (and root-form
                                       (not (string= root-form word))
                                       (not (string-empty-p root-form)))
                                  root-form word)))
            (insert (format "*** %s  [%s]\n" display-form (or wylie-word "?")))
            (insert (format "  %s\n" (or meaning "[not found]")))
            (when (and full-meaning (not (string= full-meaning (or meaning ""))))
              (insert (format "  Full: %s\n" full-meaning)))
            (insert "\n")))
        (insert "\n"))

      (buffer-string))))
    (error
     ;; On error, return minimal analysis with error info
     (format "** Wylie Transliteration\n[Error during analysis]\n\n** Translations\n- [Error: %s]\n\n** Vocabulary\n[Error]\n"
             (error-message-string err)))))

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
