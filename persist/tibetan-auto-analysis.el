;;; tibetan-auto-analysis.el --- Automatic batch analysis generation -*- lexical-binding: t -*-

;;; Commentary:
;; Automatically generates analysis files for all segments and sentences
;; in a prepared Tibetan document.
;;
;; Usage:
;;   C-c u P  - Prepare document (tibetan-prepare-document)
;;   C-c u B  - Auto-analyze all (tibetan-auto-analyze-document)
;;
;; The auto-analyze command will:
;; 1. Create analysis/seg-NNN-*.org files for each segment
;; 2. Create analysis/sent-NNN-*.org files for each sentence
;; 3. Show progress as it processes
;; 4. Skip existing files (unless force flag is used)

;;; Code:

(require 'cl-lib)
;; Only require org when not in batch mode (can hang in batch)
(unless noninteractive
  (require 'org))

;; Load dependencies
(require 'tibetan-org-structure nil t)
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-clause-analysis nil t)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defcustom tibetan-auto-skip-existing t
  "If non-nil, skip analysis files that already exist.
Set to nil to regenerate all files."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-generate-sentences t
  "If non-nil, also generate sentence-level clause analysis files."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-show-progress t
  "If non-nil, show progress messages during batch analysis."
  :type 'boolean
  :group 'tibetan-cat)

;; ============================================================================
;; PROGRESS REPORTING
;; ============================================================================

(defvar tibetan-auto--progress-callback nil
  "Callback function for progress reporting.
Called with (CURRENT TOTAL MESSAGE).")

(defun tibetan-auto--report-progress (current total message)
  "Report progress: CURRENT of TOTAL, with MESSAGE."
  (when tibetan-auto-show-progress
    (message "%s... (%d/%d)" message current total))
  (when tibetan-auto--progress-callback
    (funcall tibetan-auto--progress-callback current total message)))

(defmacro tibetan-auto--with-progress (callback total &rest body)
  "Execute BODY with progress CALLBACK for TOTAL items."
  (declare (indent 2))
  `(let ((tibetan-auto--progress-callback ,callback))
     ,@body))

;; ============================================================================
;; COUNTING FUNCTIONS
;; ============================================================================

(defun tibetan-auto--count-segments ()
  "Count number of segments in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^\\*\\*\\* Segment [0-9]+" nil t)
        (setq count (1+ count)))
      count)))

(defun tibetan-auto--count-sentences ()
  "Count number of sentences in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^\\*\\* Sentence [0-9]+" nil t)
        (setq count (1+ count)))
      count)))

;; ============================================================================
;; COLLECTION FUNCTIONS
;; ============================================================================

(defun tibetan-auto--collect-segments ()
  "Collect all segments from current buffer.
Returns alist of (SEGMENT-NUMBER . TIBETAN-TEXT)."
  (save-excursion
    (goto-char (point-min))
    (let ((segments '()))
      (while (re-search-forward "^\\*\\*\\* Segment \\([0-9]+\\)" nil t)
        (let* ((seg-num (string-to-number (match-string 1)))
               (text (tibetan-org-get-segment-text)))
          (when text
            (push (cons seg-num text) segments))))
      (nreverse segments))))

(defun tibetan-auto--collect-sentences ()
  "Collect all sentences from current buffer.
Returns alist of (SENTENCE-NUMBER . COMBINED-TEXT)."
  (save-excursion
    (goto-char (point-min))
    (let ((sentences '()))
      (while (re-search-forward "^\\*\\* Sentence \\([0-9]+\\)" nil t)
        (let* ((sent-num (string-to-number (match-string 1)))
               (start-pos (point)))
          ;; Move to sentence heading
          (beginning-of-line)
          ;; Get combined text from all segments
          (when (tibetan-org-at-sentence-p)
            (let ((text (tibetan-org-get-sentence-text)))
              (when text
                (push (cons sent-num text) sentences))))
          ;; Move past this sentence for next iteration
          (goto-char start-pos)))
      (nreverse sentences))))

;; ============================================================================
;; SKIP LOGIC
;; ============================================================================

(defun tibetan-auto--should-skip-p (filepath)
  "Return t if we should skip generating FILEPATH."
  (and tibetan-auto-skip-existing
       (file-exists-p filepath)))

;; ============================================================================
;; FILENAME GENERATION
;; ============================================================================

(defun tibetan-auto--sentence-filename (sent-num source-file)
  "Generate filename for sentence SENT-NUM analysis.
SOURCE-FILE is used to generate a unique suffix."
  (let ((short-name (tibetan-analysis-make-short-name source-file)))
    (if short-name
        (format "sent-%03d-%s.org" sent-num short-name)
      (format "sent-%03d.org" sent-num))))

(defun tibetan-auto--sentence-filepath (sent-num)
  "Get full filepath for sentence SENT-NUM analysis."
  (let* ((folder (tibetan-analysis-get-folder))
         (source-file (buffer-file-name))
         (filename (tibetan-auto--sentence-filename sent-num source-file)))
    (expand-file-name filename folder)))

;; ============================================================================
;; SENTENCE ANALYSIS GENERATION
;; ============================================================================

(defun tibetan-auto--generate-sentence-analysis (sent-num tibetan-text)
  "Generate sentence analysis content for SENT-NUM with TIBETAN-TEXT.
Returns the analysis as an org-mode formatted string."
  (let* ((clause-analysis (if (fboundp 'tibetan-analyze-clause-structure)
                              (tibetan-analyze-clause-structure tibetan-text)
                            "[Clause analysis not available]"))
         (converbs (when (fboundp 'tibetan-detect-converbs)
                     (tibetan-detect-converbs tibetan-text)))
         (main-verb (when (fboundp 'tibetan-find-main-verb)
                      (tibetan-find-main-verb tibetan-text))))
    (with-temp-buffer
      (insert "** Clause Structure\n\n")
      (insert clause-analysis)
      (insert "\n\n")

      ;; Main verb details
      (insert "** Main Verb\n\n")
      (if main-verb
          (insert (format "- Verb: %s\n- Position: %d\n"
                          (plist-get main-verb :verb)
                          (plist-get main-verb :position)))
        (insert "[No main verb identified]\n"))
      (insert "\n")

      ;; Converb list
      (insert "** Converbs (Dependent Clauses)\n\n")
      (if converbs
          (dolist (conv converbs)
            (insert (format "- %s (%s): %s\n"
                            (plist-get conv :particle)
                            (plist-get conv :type)
                            (plist-get conv :stem))))
        (insert "[No converbs detected]\n"))
      (insert "\n")

      (buffer-string))))

(defun tibetan-auto--create-sentence-file (sent-num tibetan-text source-file)
  "Create sentence analysis file for SENT-NUM.
TIBETAN-TEXT is the combined sentence text.
SOURCE-FILE is the path to the source document."
  (let* ((filepath (tibetan-auto--sentence-filepath sent-num))
         (content (tibetan-auto--generate-sentence-analysis sent-num tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         (source-name (file-name-nondirectory source-file)))
    (with-temp-file filepath
      (insert (format "#+TITLE: Sentence %d Analysis\n" sent-num))
      (insert "#+STARTUP: overview\n")
      (insert (format "#+SOURCE: [[file:../%s::*Sentence %d][%s / Sentence %d]]\n"
                      source-name sent-num source-name sent-num))
      (insert (format "#+CREATED: %s\n" date))
      (insert "\n")
      (insert "* Tibetan Text\n\n")
      (insert tibetan-text)
      (insert "\n\n")
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert content)
      (insert "\n")
      (insert "* Grammar Notes\n\n\n")
      (insert "* Translation\n\n\n"))
    filepath))

;; ============================================================================
;; MAIN AUTO-ANALYZE FUNCTION
;; ============================================================================

(defun tibetan-auto-analyze-document (&optional force)
  "Automatically generate analysis files for all segments and sentences.

With prefix argument FORCE, regenerate all files even if they exist.
Otherwise, skips existing files based on `tibetan-auto-skip-existing'.

Creates:
- analysis/seg-NNN-*.org for each segment (word-by-word analysis)
- analysis/sent-NNN-*.org for each sentence (clause analysis)

Progress is shown in the echo area."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))

  (let* ((tibetan-auto-skip-existing (not force))
         (source-file (buffer-file-name))
         (segments (tibetan-auto--collect-segments))
         (sentences (when tibetan-auto-generate-sentences
                      (tibetan-auto--collect-sentences)))
         (total-segs (length segments))
         (total-sents (length sentences))
         (total (+ total-segs total-sents))
         (created-segs 0)
         (created-sents 0)
         (skipped 0)
         (current 0))

    (when (= total 0)
      (error "No segments or sentences found. Run tibetan-prepare-document first"))

    (message "Starting auto-analysis: %d segments, %d sentences..."
             total-segs total-sents)

    ;; Ensure analysis folder exists
    (tibetan-analysis-get-folder)

    ;; Process segments
    (dolist (seg segments)
      (setq current (1+ current))
      (let* ((seg-num (car seg))
             (seg-text (cdr seg))
             (filepath (tibetan-analysis-get-filepath seg-num source-file)))

        (tibetan-auto--report-progress current total
                                        (format "Segment %d" seg-num))

        (if (tibetan-auto--should-skip-p filepath)
            (setq skipped (1+ skipped))
          ;; Generate analysis
          (let ((auto-content (tibetan-analysis-generate-content seg-text)))
            (tibetan-analysis-create-file seg-num seg-text source-file auto-content)
            (setq created-segs (1+ created-segs))))))

    ;; Process sentences
    (when tibetan-auto-generate-sentences
      (dolist (sent sentences)
        (setq current (1+ current))
        (let* ((sent-num (car sent))
               (sent-text (cdr sent))
               (filepath (tibetan-auto--sentence-filepath sent-num)))

          (tibetan-auto--report-progress current total
                                          (format "Sentence %d" sent-num))

          (if (tibetan-auto--should-skip-p filepath)
              (setq skipped (1+ skipped))
            ;; Generate sentence analysis
            (tibetan-auto--create-sentence-file sent-num sent-text source-file)
            (setq created-sents (1+ created-sents))))))

    ;; Report results
    (message "Auto-analysis complete: %d segment files, %d sentence files created (%d skipped)"
             created-segs created-sents skipped)))


;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(global-set-key (kbd "C-c u B") 'tibetan-auto-analyze-document)

(provide 'tibetan-auto-analysis)
;;; tibetan-auto-analysis.el ends here
