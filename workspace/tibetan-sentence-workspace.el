;;; tibetan-sentence-workspace.el --- Sentence preparation workspace for translation portfolio -*- lexical-binding: t -*-

;;; Commentary:
;; Creates editable workspace for sentence translation with:
;; - Line-by-line Tibetan/Wylie/Vocabulary
;; - Context-aware grammatical analysis per segment
;; - Translation and notes sections
;;
;; Bound to C-c s w

;;; Code:

(require 'cl-lib)
(require 'tibetan-utils)
(require 'tibetan-wylie)
(require 'tibetan-vocabulary)
(require 'tibetan-particles-bialek)      ; New Bialek-based grammar analysis
(require 'tibetan-translation-suggest)   ; Translation suggestion engine
(require 'tibetan-org-structure)

;; ============================================================================
;; SENTENCE DETECTION - UNIFIED
;; ============================================================================

(defun tibetan-get-sentence-at-point-any-format ()
  "Get sentence data from ANY format (org structure or old markers).
Returns plist with :number, :segments, :start, :end."
  (or
   ;; Try org structure first
   (when (and (derived-mode-p 'org-mode)
              (or (tibetan-org-at-sentence-p)
                  (tibetan-org-at-segment-p)))
     (let ((sent-num (tibetan-org-get-sentence-id))
           (segments-text (tibetan-org-get-sentence-segments)))
       (when segments-text
         (let ((segments '()))
           (dotimes (i (length segments-text))
             (push (cons (number-to-string (1+ i))
                        (nth i segments-text))
                   segments))
           (list :number (number-to-string sent-num)
                 :segments (nreverse segments)
                 :start (point-min)
                 :end (point-max))))))

   ;; Fall back to old markers
   (tibetan-get-sentence-at-point)))

(defun tibetan-get-sentence-at-point ()
  "Get the current sentence (segments between ‖SEN‖ markers or sentence boundaries)."
  (save-excursion
    (let ((start-pos nil)
          (end-pos nil)
          (segments '())
          (sentence-num nil))

      ;; If on heading, move to next line first
      (when (looking-at "^\\*\\* Sentence")
        (forward-line 1))

      ;; Find sentence start (look backward for heading)
      (if (re-search-backward "^\\*\\* Sentence \\([0-9]+\\)" nil t)
          (progn
            (setq sentence-num (match-string 1))
            (message "DEBUG: Found sentence %s" sentence-num)
            (forward-line 1)
            (setq start-pos (point)))
        (message "DEBUG: No sentence heading found backward from point %d" (point)))

      ;; Find sentence end (look forward for ‖SEN‖ or next sentence heading)
      (when start-pos
        (if (re-search-forward "\\(‖SEN‖\\)\\|\\(^\\*\\* Sentence [0-9]+\\)" nil t)
            (progn
              ;; If found ‖SEN‖, include the segment it's in by finding closing tag
              (if (match-beginning 1)  ; matched ‖SEN‖
                  (if (re-search-forward "〔/SEG〕" nil t)
                      (setq end-pos (point))
                    (setq end-pos (match-end 0)))
                ;; matched next sentence heading
                (setq end-pos (match-beginning 0)))
              (message "DEBUG: Sentence ends at %d" end-pos))
          (setq end-pos (point-max))
          (message "DEBUG: No end marker, using point-max")))

      ;; Extract all segments in this sentence
      (when (and start-pos end-pos)
        (goto-char start-pos)
        (while (re-search-forward "〔SEG:\\([^〕]+\\)〕\\([^〔]*\\)〔/SEG〕" end-pos t)
          (let* ((seg-id (match-string 1))
                 (seg-text-raw (match-string 2))
                 ;; Clean up: remove ‖SEN‖ marker and segment tags
                 (seg-text (string-trim
                           (replace-regexp-in-string "‖SEN‖\\|〔SEG:[^〕]+〕\\|〔/SEG〕" "" seg-text-raw))))
            (message "DEBUG: Found segment %s" seg-id)
            (push (cons seg-id seg-text) segments))))

      (message "DEBUG: Total segments found: %d" (length segments))
      (when segments
        (list :number sentence-num
              :segments (nreverse segments)
              :start start-pos
              :end end-pos)))))

;; ============================================================================
;; WORKSPACE BUFFER
;; ============================================================================

(defun tibetan-create-sentence-workspace (sentence-data)
  "Create workspace buffer for SENTENCE-DATA."
  (let* ((sentence-num (plist-get sentence-data :number))
         (segments (plist-get sentence-data :segments))
         (buffer-name (format "*Sentence %s Workspace*" sentence-num))
         (workspace-file (format "sentence-%s-workspace.org" sentence-num)))

    (with-current-buffer (get-buffer-create buffer-name)
      (erase-buffer)
      (org-mode)

      ;; Header with export options for clean PDF
      (insert (format "#+TITLE: Sentence %s - Translation Workspace\n" sentence-num))
      (insert "#+DATE: " (format-time-string "%Y-%m-%d") "\n")
      (insert "#+OPTIONS: toc:nil title:nil author:nil date:nil\n")
      (insert "#+LATEX_HEADER: \\usepackage[margin=1in]{geometry}\n")
      (insert "#+LATEX_HEADER: \\usepackage{fontspec}\n")
      (insert "#+LATEX_HEADER: \\setmainfont{Tibetan Machine Uni}[Script=Tibetan]\n")
      (insert "#+LATEX_HEADER: \\usepackage{polyglossia}\n")
      (insert "#+LATEX_HEADER: \\setdefaultlanguage{english}\n")
      (insert "#+LATEX_HEADER: \\setotherlanguage{tibetan}\n\n")

      ;; Process each segment line-by-line
      (insert "* Sentence Text\n\n")

      ;; Tibetan section - one line per segment
      (insert "** Tibetan\n")
      (dolist (seg segments)
        (insert (cdr seg) "\n"))
      (insert "\n")

      ;; Wylie section - one line per segment (aligned with Tibetan)
      (insert "** Wylie (for reading aloud)\n")
      (dolist (seg segments)
        (let ((seg-text (cdr seg))
              (wylie nil))
          (condition-case err
              (progn
                (if (fboundp 'tibetan-to-wylie-fixed)
                    (setq wylie (tibetan-to-wylie-fixed seg-text))
                  (setq wylie "[Wylie converter not loaded]")))
            (error
             (setq wylie (format "[Wylie error: %s]" (error-message-string err)))))
          (insert wylie "\n")))
      (insert "\n")

      ;; Vocabulary section - one line per segment (aligned with Tibetan)
      (insert "** Vocabulary\n")
      (dolist (seg segments)
        (let* ((seg-text (cdr seg))
               (vocab (tibetan-extract-vocabulary seg-text)))
          (when vocab
            (dolist (word-pair vocab)
              (insert (format "%s (%s) " (car word-pair) (cdr word-pair)))))
          (insert "\n")))
      (insert "\n")

      ;; Grammatical Analysis section - detailed per segment with Bialek framework
      (insert "** Grammatical Analysis (Bialek Framework)\n\n")
      (dolist (seg segments)
        (let* ((seg-id (car seg))
               (seg-text (cdr seg))
               (grammar (when (fboundp 'tibetan-analyze-grammar-bialek)
                          (tibetan-analyze-grammar-bialek seg-text)))
               (vocab (tibetan-extract-vocabulary seg-text))
               (suggestion (when (fboundp 'tibetan-suggest-translation)
                            (tibetan-suggest-translation seg-text vocab grammar))))
          (insert (format "*** Segment %s: %s\n\n" seg-id seg-text))

          ;; Grammar analysis
          (if grammar
              (progn
                (insert "**** Grammatical Markers\n\n")
                (dolist (a grammar)
                  (let ((particle (nth 0 a))
                        (word (nth 1 a))
                        (type (nth 2 a))
                        (function (nth 3 a))
                        (trans-guide (nth 4 a))
                        (reference (nth 5 a)))
                    (insert (format "***** %s in '%s'\n" particle word))
                    (insert (format "- TYPE: %s\n" type))
                    (insert (format "- FUNCTION: %s\n" function))
                    (insert (format "- TRANSLATION: %s\n" trans-guide))
                    (insert (format "- REFERENCE: %s\n\n" reference)))))
            (insert "No grammatical markers detected in this segment.\n\n"))

          ;; Translation suggestion for this segment
          (when suggestion
            (insert "**** Translation Suggestion\n\n")
            (insert suggestion)
            (insert "\n\n"))))

      (insert "\n")

      ;; Translation section
      (insert "* My Translation\n\n")
      (insert "[Write your translation here]\n\n")

      ;; Other translations for reference
      (insert "* Reference Translations\n\n")
      (insert "** OpenL Translation\n\n")
      (insert "[Paste OpenL translation here]\n\n")
      (insert "** ChatGPT/Claude Translation\n\n")
      (insert "[Paste AI translation here]\n\n")
      (insert "** Other Sources\n\n")
      (insert "[Add other translations here]\n\n")

      ;; Notes section
      (insert "* Notes\n\n")
      (insert "[Add your notes and analysis here]\n\n")

      (goto-char (point-min))
      (search-forward "[Write your translation here]" nil t)
      (beginning-of-line)

      ;; Set local variable for workspace file
      (setq-local tibetan-workspace-file
                  (expand-file-name workspace-file
                                   (file-name-directory (or buffer-file-name default-directory))))

      (current-buffer))))

;; ============================================================================
;; MAIN COMMAND
;; ============================================================================

(defun tibetan-prepare-sentence ()
  "Open sentence preparation workspace.
Creates editable workspace with translation, notes, and vocabulary reference.
Works with both org structure (** Sentence) and old markers."
  (interactive)
  (let ((sentence-data (tibetan-get-sentence-at-point-any-format)))
    (if (not sentence-data)
        (error "Not in a sentence. Position cursor in ** Sentence heading or old markers.")

      (let* ((workspace-buffer (tibetan-create-sentence-workspace sentence-data))
             (source-buffer (current-buffer)))

        ;; Auto-analysis now works WITH workspace (no need to disable)
        ;; The analysis window updates independently without destroying workspace

        ;; DON'T delete other windows - split current window to add workspace below
        ;; This allows segment analysis window (RIGHT) to stay open
        (let ((current-win (selected-window)))
          (let ((bottom-window (split-window current-win nil 'below)))
            ;; Show workspace in bottom window
            (set-window-buffer bottom-window workspace-buffer)
            ;; Keep cursor in current window (source)
            (select-window current-win)))

        (message "✓ Sentence %s workspace open BELOW. Edit there, press C-c C-c to save."
                (plist-get sentence-data :number))))))

(defun tibetan-save-workspace ()
  "Save current workspace to file."
  (interactive)
  (when (and (boundp 'tibetan-workspace-file) tibetan-workspace-file)
    (write-file tibetan-workspace-file)
    (message "Workspace saved to %s" tibetan-workspace-file)))

(defun tibetan-export-workspace-pdf ()
  "Export current workspace to PDF for classroom reference.
Uses minimal LaTeX setup - no title page, no TOC."
  (interactive)
  (if (not (and (boundp 'tibetan-workspace-file) tibetan-workspace-file))
      (error "Not in a workspace buffer. Save workspace first with C-c C-c")
    ;; Save first
    (write-file tibetan-workspace-file)
    (message "Exporting to PDF...")
    ;; Export to PDF using org-mode's LaTeX export with minimal options
    (condition-case err
        (progn
          (require 'ox-latex)
          ;; Set buffer-local export options for clean PDF
          (save-excursion
            (goto-char (point-min))
            ;; Add export options at top if not already present
            (unless (re-search-forward "^#\\+OPTIONS:" nil t)
              (goto-char (point-min))
              (forward-line 2)  ; After #+TITLE and #+DATE
              (insert "#+OPTIONS: toc:nil title:nil author:nil date:nil\n")
              (insert "#+LATEX_HEADER: \\usepackage[margin=1in]{geometry}\n")
              (insert "#+LATEX_HEADER: \\usepackage{fontspec}\n")
              (insert "#+LATEX_HEADER: \\setmainfont{Kailasa}\n\n")))
          (org-latex-export-to-pdf)
          (message "✓ PDF exported: %s"
                   (replace-regexp-in-string "\\.org$" ".pdf" tibetan-workspace-file)))
      (error
       (message "PDF export failed: %s. Make sure LaTeX (XeLaTeX) is installed."
                (error-message-string err))))))

(defun tibetan-export-any-org-to-pdf ()
  "Export ANY org file to PDF with minimal LaTeX setup.
Works for any .org file, not just workspace files.
No title page, no TOC."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (error "Not in an org-mode buffer"))

  (unless buffer-file-name
    (error "Buffer not associated with a file. Save it first."))

  ;; Save the buffer first
  (save-buffer)

  (message "Exporting %s to PDF..." (file-name-nondirectory buffer-file-name))

  ;; Use let-binding to temporarily set export options without modifying buffer
  (let ((org-export-with-toc nil)
        (org-export-with-title nil)
        (org-export-with-author nil)
        (org-export-with-date nil)
        (org-latex-compiler "xelatex")
        (org-latex-pdf-process
         '("xelatex -interaction nonstopmode -output-directory %o %f"
           "xelatex -interaction nonstopmode -output-directory %o %f")))

    (condition-case err
        (progn
          (require 'ox-latex)

          ;; Add Tibetan font support to LaTeX class
          (unless (assoc "tibetan-article" org-latex-classes)
            (add-to-list 'org-latex-classes
                         '("tibetan-article"
                           "\\documentclass[11pt]{article}
\\usepackage[margin=1in]{geometry}
\\usepackage{fontspec}
\\newfontfamily\\tibetanfont{Tibetan Machine Uni}
\\setmainfont{Tibetan Machine Uni}[Script=Tibetan]
\\usepackage{polyglossia}
\\setdefaultlanguage{english}
\\setotherlanguage{tibetan}"
                           ("\\section{%s}" . "\\section*{%s}")
                           ("\\subsection{%s}" . "\\subsection*{%s}")
                           ("\\subsubsection{%s}" . "\\subsubsection*{%s}"))))

          ;; Export with custom class
          (let ((org-latex-default-class "tibetan-article"))
            (org-latex-export-to-pdf))

          (message "✓ PDF exported: %s"
                   (replace-regexp-in-string "\\.org$" ".pdf" buffer-file-name)))
      (error
       (message "PDF export failed: %s. Make sure XeLaTeX is installed."
                (error-message-string err))))))

;; ============================================================================
;; KEY BINDINGS
;; ============================================================================

(global-set-key (kbd "C-c s w") 'tibetan-prepare-sentence)      ; sentence workspace
(with-eval-after-load 'org
  (define-key org-mode-map (kbd "C-c C-c") 'tibetan-save-workspace))
(global-set-key (kbd "C-c s p") 'tibetan-export-workspace-pdf)  ; export workspace to PDF
(global-set-key (kbd "C-c e p") 'tibetan-export-any-org-to-pdf) ; export ANY org to PDF

(provide 'tibetan-sentence-workspace)
;;; tibetan-sentence-workspace.el ends here
