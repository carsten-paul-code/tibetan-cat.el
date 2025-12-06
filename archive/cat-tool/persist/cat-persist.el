;;; cat-persist.el --- Persistent analysis storage for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Persistent storage module for CAT analysis results.
;; Manages analysis files in an `analysis/` subfolder:
;; - seg-XXX.org for segment-level analysis
;; - verse-XXX.org or sentence-XXX.org for compound analysis
;;
;; Key features:
;; - Preserves user-written notes on re-analysis
;; - Hash-based change detection
;; - Org-mode formatted output

;;; Code:

(require 'cl-lib)
(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)
(require 'cat-display)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defvar cat-persist-analysis-folder "analysis"
  "Name of the folder to store analysis files.")

;; ============================================================================
;; FOLDER MANAGEMENT
;; ============================================================================

(defun cat-persist-get-folder ()
  "Get or create the analysis folder for current buffer.
Returns the folder path."
  (let* ((base-dir (file-name-directory (or buffer-file-name default-directory)))
         (folder (expand-file-name cat-persist-analysis-folder base-dir)))
    (unless (file-exists-p folder)
      (make-directory folder t)
      (message "Created analysis folder: %s" folder))
    folder))

(defun cat-persist-segment-file (seg-id)
  "Get the analysis file path for SEG-ID."
  (let ((folder (cat-persist-get-folder)))
    (expand-file-name (format "seg-%s.org" seg-id) folder)))

(defun cat-persist-compound-file (compound-id compound-type)
  "Get the analysis file path for COMPOUND-ID of COMPOUND-TYPE.
COMPOUND-TYPE is 'verse or 'sentence."
  (let ((folder (cat-persist-get-folder))
        (prefix (if (eq compound-type 'verse) "verse" "sentence")))
    (expand-file-name (format "%s-%s.org" prefix compound-id) folder)))

;; ============================================================================
;; HASH-BASED CHANGE DETECTION
;; ============================================================================

(defun cat-persist-hash-text (text)
  "Generate a hash for TEXT to detect changes."
  (md5 text))

(defun cat-persist-read-stored-hash (file)
  "Read the stored source hash from FILE.
Returns nil if file doesn't exist or has no hash."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+SOURCE_HASH:\\s-*\\(.+\\)$" nil t)
        (match-string 1)))))

(defun cat-persist-text-changed-p (text file)
  "Check if TEXT has changed compared to stored version in FILE."
  (let ((stored-hash (cat-persist-read-stored-hash file))
        (current-hash (cat-persist-hash-text text)))
    (or (null stored-hash)
        (not (string= stored-hash current-hash)))))

;; ============================================================================
;; USER NOTES PRESERVATION
;; ============================================================================

(defun cat-persist-extract-user-sections (file)
  "Extract user-written sections from existing analysis FILE.
Returns alist of (section-name . content) for user sections."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((sections '()))
        ;; Look for common user section headers
        (dolist (section '("Notes" "My Notes" "Translation Notes"
                          "Questions" "Comments" "Draft Translation"
                          "Working Translation" "My Translation"))
          (goto-char (point-min))
          (when (re-search-forward (format "^\\*+\\s-*%s" section) nil t)
            (let ((start (line-beginning-position))
                  (end (save-excursion
                        (if (re-search-forward "^\\*" nil t)
                            (line-beginning-position)
                          (point-max)))))
              (let ((content (buffer-substring-no-properties start end)))
                ;; Only keep if there's actual content beyond the header
                (when (string-match "\n.+" content)
                  (push (cons section content) sections))))))
        sections))))

;; ============================================================================
;; SEGMENT ANALYSIS GENERATION
;; ============================================================================

(defun cat-persist-generate-segment-analysis (seg-id tibetan-text)
  "Generate org-mode analysis content for segment SEG-ID with TIBETAN-TEXT."
  (let* ((parse-result (cat-parser-parse tibetan-text))
         (words (cat-parse-result-words parse-result))
         (multiword-units (cat-parse-result-multiword-units parse-result))
         (segments (cat-parse-result-segments parse-result))
         (wylie (cat-display-get-wylie tibetan-text))
         (particles (cat-grammar-analyze-text tibetan-text))
         (verbs (cat-parser-extract-verbs parse-result))
         (working-trans (cat-display-generate-translation parse-result verbs))
         (dm-trans (cat-display-get-dharmamitra tibetan-text))
         (hash (cat-persist-hash-text tibetan-text)))

    (with-temp-buffer
      ;; File header
      (insert (format "#+TITLE: Segment %s Analysis\n" seg-id))
      (insert (format "#+SOURCE_HASH: %s\n" hash))
      (insert (format "#+DATE: %s\n\n" (format-time-string "%Y-%m-%d %H:%M")))

      ;; Source text
      (insert "* Source Text\n\n")
      (insert tibetan-text)
      (insert "\n\n")

      ;; Wylie
      (insert "* Wylie Transliteration\n\n")
      (insert wylie)
      (insert "\n\n")

      ;; Segmentation
      (insert "* Segmentation\n\n")
      (insert (string-join segments " | "))
      (insert "\n\n")

      ;; Lexical units
      (when multiword-units
        (insert "* Lexical Units\n\n")
        (dolist (unit multiword-units)
          (let* ((form (nth 2 unit))
                 (data (nth 3 unit))
                 (english (alist-get 'english data))
                 (category (alist-get 'category data)))
            (insert (format "- *%s* :: %s"
                           form (or english "?")))
            (when category
              (insert (format " (%s)" category)))
            (insert "\n")))
        (insert "\n"))

      ;; Particles
      (insert "* Particles & Case Markers\n\n")
      (if particles
          (dolist (p particles)
            (insert (format "** %s" (cat-particle-particle p)))
            (when (cat-particle-root p)
              (insert (format " (after %s)" (cat-particle-root p))))
            (insert "\n")
            (insert (format "- Type :: %s\n" (cat-grammar-get-type-name (cat-particle-type p))))
            (insert (format "- Function :: %s\n" (cat-particle-function p)))
            (insert (format "- Reference :: %s\n\n" (cat-particle-reference p))))
        (insert "[No particles detected]\n\n"))

      ;; Verbs
      (when verbs
        (insert "* Verb Analysis\n\n")
        (dolist (verb verbs)
          (when (and verb (listp verb) (consp (car verb)))
            (let ((lemma (alist-get 'lemma verb))
                  (meaning (alist-get 'meaning verb))
                  (trans (alist-get 'transitivity verb))
                  (vol (alist-get 'volitionality verb))
                  (frame (alist-get 'case_frame verb)))
              (insert (format "** %s\n" lemma))
              (when meaning (insert (format "- Meaning :: %s\n" meaning)))
              (when trans (insert (format "- Transitivity :: %s\n" trans)))
              (when vol (insert (format "- Volitionality :: %s\n" vol)))
              (when frame (insert (format "- Case Frame :: %s\n" frame)))
              (insert "\n")))))

      ;; Translations
      (insert "* Translations\n\n")
      (insert "** Working Translation\n\n")
      (if working-trans
          (insert (format "%s\n\n" working-trans))
        (insert "[Could not generate]\n\n"))
      (insert "** DharmaMitra\n\n")
      (insert (or dm-trans "[Not available]"))
      (insert "\n\n")

      ;; Word-by-word gloss
      (insert "* Word-by-Word Gloss\n\n")
      (insert "| Tibetan | Meaning |\n")
      (insert "|---------|--------|\n")
      (dolist (seg segments)
        (let ((meaning (cat-parser-lookup-segment seg parse-result)))
          (insert (format "| %s | %s |\n" seg (or meaning "?")))))
      (insert "\n")

      ;; User notes section (placeholder)
      (insert "* Notes\n\n")
      (insert "[Your notes here]\n\n")

      (buffer-string))))

;; ============================================================================
;; MAIN PERSISTENCE FUNCTIONS
;; ============================================================================

(defun cat-persist-analyze-segment (seg-id tibetan-text)
  "Analyze and save segment SEG-ID with TIBETAN-TEXT.
Preserves existing user notes if file exists."
  (let* ((file (cat-persist-segment-file seg-id))
         (user-sections (cat-persist-extract-user-sections file))
         (content (cat-persist-generate-segment-analysis seg-id tibetan-text)))

    ;; Restore user sections if present
    (when user-sections
      (setq content
            (with-temp-buffer
              (insert content)
              ;; Find the Notes section and replace/append
              (goto-char (point-min))
              (when (re-search-forward "^\\* Notes\n\n\\[Your notes here\\]\n" nil t)
                (delete-region (match-beginning 0) (match-end 0))
                (dolist (section (reverse user-sections))
                  (insert (cdr section))))
              (buffer-string))))

    ;; Write file
    (with-temp-file file
      (insert content))

    (message "Saved analysis to %s" file)
    file))

(defun cat-persist-re-analyze-segment (seg-id tibetan-text)
  "Re-analyze segment SEG-ID preserving all user content.
Only regenerates auto-generated sections."
  (let* ((file (cat-persist-segment-file seg-id))
         (user-sections (cat-persist-extract-user-sections file)))

    ;; Generate fresh analysis
    (let ((content (cat-persist-generate-segment-analysis seg-id tibetan-text)))

      ;; Restore user sections
      (when user-sections
        (setq content
              (with-temp-buffer
                (insert content)
                (goto-char (point-min))
                (when (re-search-forward "^\\* Notes\n\n\\[Your notes here\\]\n" nil t)
                  (delete-region (match-beginning 0) (match-end 0))
                  (dolist (section (reverse user-sections))
                    (insert (cdr section))))
                (buffer-string))))

      ;; Write file
      (with-temp-file file
        (insert content))

      (message "Re-analyzed %s (preserved user notes)" seg-id)
      file)))

(defun cat-persist-open-segment-analysis (seg-id)
  "Open the analysis file for SEG-ID if it exists."
  (let ((file (cat-persist-segment-file seg-id)))
    (if (file-exists-p file)
        (find-file-other-window file)
      (message "No analysis file for segment %s" seg-id))))

;; ============================================================================
;; COMPOUND ANALYSIS
;; ============================================================================

(defun cat-persist-generate-compound-header (compound-id compound-type lines context)
  "Generate header for compound analysis.
COMPOUND-ID is the identifier, COMPOUND-TYPE is 'verse or 'sentence,
LINES is list of (seg-id . text), CONTEXT is the translation context."
  (with-temp-buffer
    (insert (format "#+TITLE: %s %s Analysis\n"
                   (if (eq compound-type 'verse) "Verse" "Sentence")
                   compound-id))
    (insert (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
    (insert (format "#+CONTEXT: %s\n\n" (or context "classical-prose")))

    ;; Full source text
    (insert "* Source Text\n\n")
    (dolist (line lines)
      (insert (cdr line))
      (insert "\n"))
    (insert "\n")

    (buffer-string)))

(defun cat-persist-generate-compound-analysis (compound-id compound-type lines context)
  "Generate compound analysis for COMPOUND-ID.
COMPOUND-TYPE is 'verse or 'sentence, LINES is list of (seg-id . text),
CONTEXT is the translation context plist."
  (with-temp-buffer
    ;; Header
    (insert (cat-persist-generate-compound-header compound-id compound-type lines context))

    ;; Per-line analysis
    (insert "* Line-by-Line Analysis\n\n")
    (dolist (line lines)
      (let* ((seg-id (car line))
             (text (cdr line))
             (parse-result (cat-parser-parse text))
             (wylie (cat-display-get-wylie text))
             (particles (cat-grammar-analyze-text text))
             (verbs (cat-parser-extract-verbs parse-result)))

        (insert (format "** Line %s\n\n" seg-id))
        (insert (format "#+begin_src tibetan\n%s\n#+end_src\n\n" text))
        (insert (format "Wylie: =%s=\n\n" wylie))

        ;; Particles for this line
        (when particles
          (insert "*** Particles\n")
          (dolist (p particles)
            (insert (format "- %s :: %s\n"
                           (cat-particle-particle p)
                           (cat-particle-function p))))
          (insert "\n"))

        ;; Verbs for this line
        (when verbs
          (insert "*** Verbs\n")
          (dolist (v verbs)
            (when (and v (listp v) (consp (car v)))
              (insert (format "- %s :: %s\n"
                             (alist-get 'lemma v)
                             (or (alist-get 'meaning v) "?")))))
          (insert "\n"))))

    ;; Combined translation section
    (insert "* Translation\n\n")
    (insert "** Draft Translation\n\n")
    (let* ((all-text (mapconcat #'cdr lines " "))
           (parse-result (cat-parser-parse all-text))
           (verbs (cat-parser-extract-verbs parse-result))
           (working (cat-display-generate-translation parse-result verbs)))
      (if working
          (insert (format "%s\n\n" working))
        (insert "[Generate translation here]\n\n")))

    (insert "** Notes\n\n")
    (insert "[Your translation notes here]\n\n")

    (buffer-string)))

(defun cat-persist-analyze-compound (compound-id compound-type lines context)
  "Analyze and save compound COMPOUND-ID.
COMPOUND-TYPE is 'verse or 'sentence, LINES is list of (seg-id . text),
CONTEXT is the translation context."
  (let* ((file (cat-persist-compound-file compound-id compound-type))
         (user-sections (cat-persist-extract-user-sections file))
         (content (cat-persist-generate-compound-analysis
                  compound-id compound-type lines context)))

    ;; Restore user sections
    (when user-sections
      (setq content
            (with-temp-buffer
              (insert content)
              (goto-char (point-min))
              (when (re-search-forward "^\\*\\* Notes\n\n\\[Your translation notes here\\]\n" nil t)
                (delete-region (match-beginning 0) (match-end 0))
                (dolist (section (reverse user-sections))
                  (insert (cdr section))))
              (buffer-string))))

    ;; Write file
    (with-temp-file file
      (insert content))

    (message "Saved %s analysis to %s"
            (if (eq compound-type 'verse) "verse" "sentence")
            file)
    file))

(provide 'cat-persist)
;;; cat-persist.el ends here
