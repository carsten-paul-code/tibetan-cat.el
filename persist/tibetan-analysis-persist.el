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
;; GENERATE AUTO-CONTENT (matches C-c u I enhanced analysis)
;; ============================================================================

(defun tibetan-analysis-generate-content (tibetan-text)
  "Generate auto-analysis content for TIBETAN-TEXT.
Returns the analysis as a string (org-mode formatted).
Uses EXACT SAME analysis as C-c u I (tibetan-segment-info-enhanced)."
  (let* ((parsed (when (fboundp 'tibetan-parse-enhanced)
                   (tibetan-parse-enhanced tibetan-text)))
         (words (alist-get 'words parsed))
         (analysis (alist-get 'analysis parsed))
         (multiword-units (alist-get 'multiword-units parsed))
         (wylie (when (fboundp 'tibetan-to-wylie-fixed)
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
         ;; Get particles from analysis (SAME AS C-c u I)
         (particles (when analysis (alist-get 'particles analysis))))

    (with-temp-buffer
      ;; Wylie
      (insert "** Wylie Transliteration\n")
      (insert (or wylie "[Not available]"))
      (insert "\n\n")

      ;; Segmentation
      (insert "** Segmentation\n")
      (when (and words (fboundp 'tibetan-build-compound-aware-segments))
        (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
          (insert (string-join segments " | "))))
      (insert "\n\n")

      ;; Lexical Units (compounds & proper nouns)
      (insert "** Lexical Units\n")
      (if multiword-units
          (dolist (unit multiword-units)
            (let* ((form (nth 2 unit))
                   (data (nth 3 unit))
                   (wylie-val (alist-get 'wylie data))
                   (english (alist-get 'english data))
                   (sanskrit (alist-get 'sanskrit data))
                   (category (alist-get 'category data))
                   (wylie-display (or wylie-val
                                      (when (fboundp 'tibetan-to-wylie-fixed)
                                        (tibetan-to-wylie-fixed form))
                                      "?")))
              (insert (format "- %s [%s]\n" form wylie-display))
              (insert (format "  - Type: %s\n" (if category
                                                   (capitalize (replace-regexp-in-string "_" " " category))
                                                 "Vocabulary")))
              (insert (format "  - Meaning: %s\n" (or english "?")))
              (when sanskrit
                (insert (format "  - Sanskrit: %s\n" sanskrit)))))
        (insert "[No lexical units detected]\n"))
      (insert "\n")

      ;; Particles & Case Markers (SAME LOGIC AS C-c u I)
      (insert "** Particles & Case Markers\n")
      (let ((particles-found nil)
            (seen-particles (make-hash-table :test 'equal)))  ; Avoid duplicates

        ;; PASS 1: Check ALL words for case particles and converbs
        ;; (even if claimed by vocabulary - they're still grammatically particles)
        (when words
          (dolist (word words)
            (cond
             ;; Case particles
             ((and (member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
                   (not (gethash word seen-particles)))
              (puthash word t seen-particles)
              (setq particles-found t)
              (insert (format "- %s\n" word))
              (insert "  - Type: Case particle\n")
              (insert (format "  - Function: %s\n"
                             (cond
                              ((string= word "ན") "Locative: marks location or temporal/conditional setting")
                              ((string= word "ལ") "Dative-locative: marks recipient, goal, or location")
                              ((member word '("ར" "སུ" "ཏུ" "དུ")) "Allative: marks direction or goal")
                              ((string= word "ནས") "Ablative: marks source; also converb 'after V-ing'")
                              ((string= word "ལས") "Ablative: marks source, origin, or comparison")
                              ((string= word "དང") "Comitative/connective: 'with' or 'and'")
                              (t "Case marker"))))
              (insert (format "  - Reference: Bialek §4\n\n")))

             ;; Converb/continuative particles
             ((and (member word '("སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང" "ནས"))
                   (not (gethash (concat word "-converb") seen-particles)))
              (puthash (concat word "-converb") t seen-particles)
              (setq particles-found t)
              (insert (format "- %s\n" word))
              (insert "  - Type: Converb/Continuative particle\n")
              (insert (format "  - Function: %s\n"
                             (cond
                              ((member word '("སྟེ" "ཏེ" "དེ")) "Coordination: connects clauses; 'and then', 'having done'")
                              ((member word '("ཅིང" "ཞིང" "ཤིང")) "Simultaneous: 'while V-ing', lists actions")
                              ((string= word "ནས") "Sequential: 'after V-ing', 'having V-ed'")
                              (t "Clause connector"))))
              (insert (format "  - Reference: Bialek §8 (converbs)\n\n")))

             ;; Nominalizer particles
             ((and (member word '("པ" "བ" "པོ" "བོ" "མ" "མོ"))
                   (not (gethash word seen-particles)))
              (puthash word t seen-particles)
              (setq particles-found t)
              (insert (format "- %s\n" word))
              (insert "  - Type: Nominalizer\n")
              (insert (format "  - Function: %s\n"
                             (cond
                              ((member word '("པ" "བ")) "Creates noun from verb; 'the one who V-s', 'V-ing'")
                              ((member word '("པོ" "བོ")) "Agentive: 'one who V-s', masculine")
                              ((member word '("མ" "མོ")) "Feminine nominalizer or negation")
                              (t "Nominalizer"))))
              (insert (format "  - Reference: Bialek §6.2\n\n")))

             ;; Genitive particles attached to words
             ((and (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" word)
                   (not (gethash word seen-particles)))
              (puthash word t seen-particles)
              (setq particles-found t)
              (let ((base (match-string 1 word))
                    (particle (match-string 2 word)))
                (insert (format "- %s (after %s)\n" particle base))
                (insert "  - Type: Genitive (GEN)\n")
                (insert "  - Function: Marks possessor or modifier\n")
                (insert "  - Reference: Bialek §4.2.1\n\n"))))))

        ;; PASS 2: Check lexical units for embedded particles
        ;; (e.g., མཉན་ཡོད་ན has ན, པའི་ཚེ has འི in པའི)
        (dolist (unit multiword-units)
          (let* ((form (nth 2 unit))
                 (syllables (split-string form "་" t)))
            ;; Check if compound ends with a case particle
            (when (and (> (length syllables) 1)
                      (member (car (last syllables)) '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
                      (not (gethash (concat form "-embedded") seen-particles)))
              (puthash (concat form "-embedded") t seen-particles)
              (setq particles-found t)
              (let* ((particle (car (last syllables)))
                     (base-syllables (butlast syllables))
                     (base (string-join base-syllables "་")))
                (insert (format "- %s (after %s in compound %s)\n" particle base form))
                (insert "  - Type: Case particle (in lexical unit)\n")
                (insert (format "  - Function: %s\n"
                               (cond
                                ((string= particle "ན") "Locative: marks location or temporal/conditional setting")
                                ((string= particle "ལ") "Dative-locative: marks recipient, goal, or location")
                                ((member particle '("ར" "སུ" "ཏུ" "དུ")) "Allative: marks direction or goal")
                                ((string= particle "ནས") "Ablative: marks source; also converb 'after V-ing'")
                                ((string= particle "ལས") "Ablative: marks source, origin, or comparison")
                                ((string= particle "དང") "Comitative/connective: 'with' or 'and'")
                                (t "Case marker"))))
                (insert "\n")))
            ;; Check ALL syllables for genitive particles (not just last)
            ;; (e.g., པའི in པའི་ཚེ)
            (dolist (syl syllables)
              (when (and (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" syl)
                        (not (gethash (concat form "-" syl) seen-particles)))
                (puthash (concat form "-" syl) t seen-particles)
                (setq particles-found t)
                (let* ((base-in-syl (match-string 1 syl))
                       (particle (match-string 2 syl)))
                  (insert (format "- %s (after %s in compound %s)\n" particle base-in-syl form))
                  (insert "  - Type: Genitive (GEN) (in lexical unit)\n")
                  (insert "  - Function: Marks possessor or modifier\n")
                  (insert "  - Reference: Bialek §4.2.1\n\n"))))))

        (unless particles-found
          (insert "[No particles detected]\n")))
      (insert "\n")

      ;; Verb Analysis (full details like C-c u I)
      (insert "** Verb Analysis (Hill 2010)\n")
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
                (insert (format "*** %s\n" lemma))
                (when meaning
                  (insert (format "- Meaning: %s\n" meaning)))
                (insert (format "- Stems: %s / %s / %s / %s\n" present past future imperative))
                (insert (format "- Volitionality: %s\n" vol))
                (insert (format "- Transitivity: %s\n" trans))
                (insert (format "- Case frame: %s\n" frame))
                (insert (format "- Tibetan class: %s\n"
                                (cond
                                 ((string= class "tha_dad_pa") "ཐ་དད་པ་ (transitive)")
                                 ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (intransitive)")
                                 (t "—"))))
                (insert "\n"))))
        (insert "[No verbs detected]\n"))
      (insert "\n")

      ;; Zero Marker Analysis
      (insert "** Zero Marker Analysis\n")
      (if zero-analysis
          (dolist (item zero-analysis)
            (let ((form (alist-get 'form item))
                  (function (alist-get 'function item))
                  (gloss (alist-get 'gloss item))
                  (note (alist-get 'note item))
                  (verb-name (alist-get 'verb item)))
              (insert (format "- %s (Ø)\n" form))
              (insert (format "  - Function: %s\n" function))
              (when verb-name
                (insert (format "  - Verb: %s\n" verb-name)))
              (when gloss
                (insert (format "  - Gloss: %s\n" gloss)))
              (when note
                (insert (format "  - Note: %s\n" note)))))
        (insert "[No zero-marked NPs detected]\n"))
      (insert "\n")

      ;; Argument Structure (only verb arguments, not topics)
      (insert "** Argument Structure\n")
      (if (and verbs (fboundp 'tibetan-analyze-arguments))
          (let ((any-args nil))
            (dolist (verb verbs)
              (when (and verb (listp verb) (consp (car verb)))
                (let* ((lemma (alist-get 'lemma verb))
                       (frame (or (alist-get 'case_frame verb) "?"))
                       (meaning (alist-get 'meaning verb))
                       (arg-analysis (tibetan-analyze-arguments verb multiword-units words)))
                  (when arg-analysis
                    (setq any-args t)
                    (insert (format "*** %s [%s]" lemma frame))
                    (when meaning
                      (insert (format " \"%s\"" (car (split-string meaning "," t)))))
                    (insert "\n")
                    ;; Display each argument (only actual arguments, not topics)
                    (dolist (arg arg-analysis)
                      (let ((role (alist-get 'role arg))
                            (marker (alist-get 'marker arg))
                            (form (alist-get 'form arg))
                            (english (alist-get 'english arg))
                            (function (alist-get 'function arg))
                            (is-topic (alist-get 'is-topic arg)))
                        ;; Only display if NOT a topic
                        (unless is-topic
                          (insert (format "- %s (%s): %s"
                                         role
                                         (if (string= marker "Ø") "Ø" marker)
                                         form))
                          (when english
                            (insert (format " \"%s\"" english)))
                          (when function
                            (insert (format " — %s" function)))
                          (insert "\n"))))
                    (insert "\n")))))
            (unless any-args
              (insert "[No argument structures detected]\n")))
        (insert "[Argument analysis not available]\n"))
      (insert "\n")

      ;; Word-by-word Gloss
      (insert "** Word-by-Word Gloss\n")
      (when (and words (fboundp 'tibetan-build-compound-aware-segments))
        (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
          (dolist (seg segments)
            (let ((meaning
                   (or (let ((unit (cl-find-if (lambda (u) (string= (nth 2 u) seg))
                                               multiword-units)))
                         (when unit
                           (alist-get 'english (nth 3 unit))))
                       (when (boundp 'tibetan-comprehensive-vocabulary)
                         (gethash seg tibetan-comprehensive-vocabulary)))))
              (insert (format "- %s = %s\n" seg (or meaning "[?]")))))))
      (insert "\n")

      ;; DharmaMitra Translation
      (insert "** DharmaMitra Translation\n")
      (insert (or translation "[Not available]"))
      (insert "\n")

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
