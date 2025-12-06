;;; student-homework-helper.el --- Help students prepare homework translations

;; This tool generates homework templates with automatic analysis at the top
;; Students can then edit and add their own work below

(require 'cl-lib)

;; Load dependencies
;; Note: tibetan-grammar-analyzer-enhanced.el is loaded by init.el
(when (file-exists-p "~/buddhist-studies/translation-tools/tibetan-verb-analyzer.el")
  (load-file "~/buddhist-studies/translation-tools/tibetan-verb-analyzer.el"))
(when (file-exists-p "~/buddhist-studies/translation-tools/tibetan-sentence-analyzer.el")
  (load-file "~/buddhist-studies/translation-tools/tibetan-sentence-analyzer.el"))
(when (file-exists-p "~/.emacs.d/modules/languages/dharmamitra.el")
  (load-file "~/.emacs.d/modules/languages/dharmamitra.el"))
(when (file-exists-p "~/.emacs.d/tibetan-segments-fixed.el")
  (load-file "~/.emacs.d/tibetan-segments-fixed.el"))

(defun tibetan-get-current-segment-info ()
  "Get information about current segment (ID and text).
Finds the segment that the cursor is currently on or nearest to."
  (save-excursion
    (let ((current-pos (point))
          (current-line-text (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position))))

      ;; First check if current line contains a segment tag
      (if (string-match "〔SEG:\\([^〕]+\\)〕\\([^〔]*\\)〔/SEG〕" current-line-text)
          ;; Current line has segment - use it
          (list (match-string 1 current-line-text)
                (string-trim (match-string 2 current-line-text)))

        ;; Not on segment line - search backward for nearest segment
        (when (re-search-backward "〔SEG:\\([^〕]+\\)〕\\([^〔]*\\)〔/SEG〕" nil t)
          (let ((seg-id (match-string 1))
                (seg-text (match-string 2))
                (seg-end (match-end 0)))

            ;; Check if there's a closer segment forward
            (let ((next-seg-pos (save-excursion
                                  (goto-char current-pos)
                                  (when (re-search-forward "〔SEG:" nil t)
                                    (match-beginning 0)))))

              ;; If cursor is closer to next segment, use that one
              (if (and next-seg-pos
                       (< (- next-seg-pos current-pos)
                          (- current-pos seg-end)))
                  ;; Use next segment
                  (progn
                    (goto-char next-seg-pos)
                    (when (re-search-forward "〔SEG:\\([^〕]+\\)〕\\([^〔]*\\)〔/SEG〕" nil t)
                      (list (match-string 1) (string-trim (match-string 2)))))

                ;; Use previous segment
                (list seg-id (string-trim seg-text))))))))

(defun tibetan-insert-homework-template-at-tr ()
  "Insert homework template at the 〔TR:〕 line after current segment.
Includes automatic analysis at top as reference."
  (interactive)
  (let* ((seg-info (tibetan-get-current-segment-info))
         (seg-id (car seg-info))
         (seg-text (cadr seg-info)))

    (unless seg-info
      (error "Not on a Tibetan segment! Place cursor on a 〔SEG:...〕 line."))

    ;; Find the 〔TR:〕 line after this segment
    (when (re-search-forward "〔TR:〕" nil t)
      (end-of-line)
      (newline)

      ;; Check if template already exists
      (let ((next-line-start (point)))
        (forward-line 1)
        (beginning-of-line)
        (when (looking-at "═")
          (when (yes-or-no-p "Template already exists here. Replace it? ")
            ;; Delete existing template
            (goto-char next-line-start)
            (when (re-search-forward "^〔\\(SEG\\|TR\\|FOLIO\\)" nil t)
              (beginning-of-line)
              (delete-region next-line-start (point)))
            (goto-char next-line-start)))
        (goto-char next-line-start))

      ;; Generate automatic analysis
      (let ((auto-translation "")
            (word-breakdown "")
            (grammar-analysis "")
            (grammar-notes ""))

        ;; Try to get automatic translation
        (when (fboundp 'dharmamitra-text-get-translation)
          (message "Fetching DharmaMitra translation for %s... (may take 3-5 seconds)" seg-id)
          (condition-case err
              (progn
                (setq auto-translation (dharmamitra-text-get-translation seg-text))
                (message "✓ DharmaMitra translation received"))
            (error
             (message "✗ DharmaMitra translation failed: %s" (error-message-string err))
             (setq auto-translation "[Translation not available - API error]"))))

        ;; Try to get enhanced grammar analysis
        (when (fboundp 'tibetan-create-enhanced-grammar-section)
          (condition-case err
              (progn
                (setq grammar-analysis (tibetan-create-enhanced-grammar-section seg-text))
                (message "✓ Grammar analysis completed (Schwieger framework)"))
            (error
             (message "✗ Grammar analysis failed: %s" (error-message-string err))
             (setq grammar-analysis ""))))

        ;; Try to get word-by-word breakdown
        (when (fboundp 'tibetan-smart-segment-words)
          (condition-case err
              (let ((words (tibetan-smart-segment-words seg-text)))
                (setq word-breakdown
                      (mapconcat
                       (lambda (word)
                         (let ((lookup (if (fboundp 'tibetan-lookup-word-enhanced)
                                          (tibetan-lookup-word-enhanced word)
                                        word)))
                           (format "%s (%s)" word lookup)))
                       words
                       " ")))
            (error
             (setq word-breakdown seg-text))))

        ;; Insert template
        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "AUTOMATIC ANALYSIS (Reference - Edit Below!)\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")

        (insert "SEGMENT: " seg-id "\n\n")

        (insert "TIBETAN:\n")
        (insert seg-text "\n\n")

        (insert "WORD BREAKDOWN:\n")
        (insert word-breakdown "\n\n")

        (insert "DHARMAMITRA TRANSLATION (Automatic Reference):\n")
        (when (or (not auto-translation) (string-empty-p auto-translation))
          (insert "[Fetching from DharmaMitra API... this may take a few seconds]\n"))
        (insert (or auto-translation "[Not available - check network connection]") "\n\n")

        ;; Insert enhanced grammar analysis (if available)
        (when (and grammar-analysis (not (string-empty-p grammar-analysis)))
          (insert grammar-analysis))

        ;; Insert student workspace
        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "YOUR WORK (Edit this section for homework)\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")

        (insert "ANALYSIS:\n")
        (insert "[Add your word-by-word analysis with grammatical glosses here]\n")
        (insert "[Example: rgyal (king) blon (minister) rnams (PLU) ...]\n\n")

        (insert "TRANSLATION:\n")
        (insert "[Write your English translation here]\n\n")

        (insert "NOTES:\n")
        (insert "- [Observation 1]\n")
        (insert "- [Observation 2]\n\n")

        (insert "QUESTIONS:\n")
        (insert "- [Question 1]\n")
        (insert "- [Question 2]\n\n")

        (insert "CORRECTIONS (from class):\n")
        (insert "[Add corrections during class discussion]\n\n")

        (message "✓ Homework template inserted! Edit the 'YOUR WORK' section.")))))

(defun tibetan-insert-sentence-homework-template ()
  "Insert homework template for complete sentence (multiple segments).
Shows sentence boundaries and complete sentence analysis at top."
  (interactive)
  (let* ((seg-info (tibetan-get-current-segment-info))
         (seg-id (car seg-info)))

    (unless seg-info
      (error "Not on a Tibetan segment! Place cursor on a 〔SEG:...〕 line."))

    ;; Get sentence boundaries
    (let* ((boundaries (tibetan-find-sentence-boundaries seg-id))
           (start-seg (nth 0 boundaries))
           (end-seg (nth 1 boundaries))
           (segments (nth 2 boundaries))
           (full-text (mapconcat #'cdr segments " ")))

      ;; Show sentence analysis in a buffer
      (with-current-buffer (get-buffer-create "*Homework Helper*")
        (erase-buffer)
        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "SENTENCE ANALYSIS FOR HOMEWORK\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")

        (insert (format "SENTENCE SPANS: %s → %s (%d segments)\n\n"
                       start-seg end-seg (length segments)))

        ;; List segments in sentence
        (insert "SEGMENTS IN THIS SENTENCE:\n")
        (dolist (seg segments)
          (insert (format "  • %s: %s\n" (car seg) (cdr seg))))
        (insert "\n")

        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "COMPLETE SENTENCE (TIBETAN)\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")
        (insert full-text "\n\n")

        ;; Automatic translation
        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "AUTOMATIC TRANSLATION (Reference)\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")

        (let ((auto-trans ""))
          (when (fboundp 'dharmamitra-text-get-translation)
            (condition-case err
                (setq auto-trans (dharmamitra-text-get-translation full-text))
              (error
               (setq auto-trans "[Translation not available]"))))
          (insert (or auto-trans "[Not available]") "\n\n"))

        ;; Grammatical structure
        (when (fboundp 'tibetan-identify-verbs-in-segment)
          (let ((verbs (tibetan-identify-verbs-in-segment full-text)))
            (when verbs
              (insert "═══════════════════════════════════════════════════════════════\n")
              (insert "GRAMMATICAL STRUCTURE\n")
              (insert "═══════════════════════════════════════════════════════════════\n\n")
              (insert (format "Verbs found: %d\n\n" (length verbs)))
              (dolist (verb-pair verbs)
                (let ((word (car verb-pair))
                      (info (cdr verb-pair)))
                  (insert (format "• %s - %s\n"
                                 word
                                 (plist-get info :english)))))
              (insert "\n"))))

        ;; Template for student work
        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "TEMPLATE FOR YOUR HOMEWORK\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")
        (insert "Copy this template to your file and fill it in:\n\n")
        (insert "---START TEMPLATE---\n\n")
        (insert "SENTENCE ANALYSIS:\n")
        (insert "[Analyze the complete sentence structure]\n\n")
        (insert "TRANSLATION:\n")
        (insert "[Your English translation of the complete sentence]\n\n")
        (insert "SEGMENT-BY-SEGMENT ANALYSIS:\n\n")
        (dolist (seg segments)
          (insert (format "〔SEG:%s〕\n" (car seg)))
          (insert "ANALYSIS:\n[Word-by-word analysis]\n\n")
          (insert "NOTES:\n[Your notes]\n\n"))
        (insert "OVERALL NOTES:\n")
        (insert "[Notes about the complete sentence]\n\n")
        (insert "QUESTIONS:\n")
        (insert "[Your questions]\n\n")
        (insert "---END TEMPLATE---\n\n")

        (insert "═══════════════════════════════════════════════════════════════\n")
        (insert "INSTRUCTIONS\n")
        (insert "═══════════════════════════════════════════════════════════════\n\n")
        (insert "1. Review the automatic analysis above as REFERENCE\n")
        (insert "2. Copy the template section\n")
        (insert "3. Paste into your file at the 〔TR:〕 section\n")
        (insert "4. Fill in your own analysis, translation, and notes\n")
        (insert "5. The automatic analysis is to help you, not replace your work!\n\n")

        (goto-char (point-min))
        (org-mode))

      (pop-to-buffer "*Homework Helper*")
      (message "Sentence analysis ready! Copy the template to your file."))))

(defun tibetan-homework-helper-menu ()
  "Interactive menu for homework preparation."
  (interactive)
  (let ((choice (read-char-choice
                 "Homework Helper Menu:
1 - Insert template for CURRENT segment (in-place)
2 - Show sentence analysis (complete sentence, in separate buffer)
3 - Quick analysis of current segment (show in *Analysis* buffer)
4 - Help: How to use these tools

Choose (1-4): "
                 '(?1 ?2 ?3 ?4))))
    (pcase choice
      (?1 (tibetan-insert-homework-template-at-tr))
      (?2 (tibetan-insert-sentence-homework-template))
      (?3 (if (fboundp 'tibetan-analyze-sentence)
              (tibetan-analyze-sentence)
            (message "Sentence analyzer not loaded")))
      (?4 (tibetan-homework-helper-help)))))

(defun tibetan-homework-helper-help ()
  "Show help for homework helper."
  (with-current-buffer (get-buffer-create "*Homework Helper - Help*")
    (erase-buffer)
    (insert "═══════════════════════════════════════════════════════════════\n")
    (insert "HOMEWORK HELPER - HOW TO USE\n")
    (insert "═══════════════════════════════════════════════════════════════\n\n")

    (insert "OPTION 1: Insert Template at 〔TR:〕 Line\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "1. Place cursor on a segment line:\n")
    (insert "   〔SEG:tibIII-1:015〕[Tibetan text]〔/SEG〕\n")
    (insert "   ↑ Cursor here\n\n")
    (insert "2. Press: M-x tibetan-insert-homework-template-at-tr\n")
    (insert "   (or use menu: M-x tibetan-homework-helper-menu, choose 1)\n\n")
    (insert "3. Template inserted at 〔TR:〕 line with:\n")
    (insert "   • Automatic analysis at TOP (reference)\n")
    (insert "   • Your workspace BELOW (edit this!)\n\n")
    (insert "4. Edit the 'YOUR WORK' section with your analysis\n\n\n")

    (insert "OPTION 2: Show Sentence Analysis (Complete Sentence)\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "1. Place cursor on any segment in a sentence\n\n")
    (insert "2. Press: M-x tibetan-insert-sentence-homework-template\n")
    (insert "   (or use menu: M-x tibetan-homework-helper-menu, choose 2)\n\n")
    (insert "3. Opens *Homework Helper* buffer showing:\n")
    (insert "   • Complete sentence (all segments)\n")
    (insert "   • Automatic translation (reference)\n")
    (insert "   • Grammatical structure\n")
    (insert "   • Template to copy\n\n")
    (insert "4. Copy template and paste into your file\n\n\n")

    (insert "OPTION 3: Quick Analysis\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "1. Place cursor on segment\n\n")
    (insert "2. Press: C-c u S (or menu option 3)\n\n")
    (insert "3. Opens *Sentence Analysis* buffer\n")
    (insert "   • Shows complete analysis\n")
    (insert "   • Use as reference\n")
    (insert "   • Don't copy directly to homework!\n\n\n")

    (insert "KEY BINDINGS (Add to init.el)\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "(global-set-key (kbd \"C-c h t\") 'tibetan-insert-homework-template-at-tr)\n")
    (insert "(global-set-key (kbd \"C-c h s\") 'tibetan-insert-sentence-homework-template)\n")
    (insert "(global-set-key (kbd \"C-c h m\") 'tibetan-homework-helper-menu)\n\n\n")

    (insert "WORKFLOW EXAMPLE\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "Assignment: Page 22, Line 5\n\n")
    (insert "1. Open file: C-x C-f Reading 1.org\n")
    (insert "2. Find segment: C-s tibIII-1:025\n")
    (insert "3. Insert template: C-c h t (or menu option 1)\n")
    (insert "4. See automatic analysis at top (reference)\n")
    (insert "5. Edit YOUR WORK section below:\n")
    (insert "   - Add your analysis\n")
    (insert "   - Write your translation\n")
    (insert "   - Add notes and questions\n")
    (insert "6. Save: C-x C-s\n")
    (insert "7. In class: Present your work\n")
    (insert "8. Add corrections to CORRECTIONS section\n\n\n")

    (insert "IMPORTANT NOTES\n")
    (insert "─────────────────────────────────────────────────────────────\n\n")
    (insert "✓ Automatic analysis is REFERENCE only\n")
    (insert "✓ Edit and improve it with your own understanding\n")
    (insert "✓ Add your own notes, questions, observations\n")
    (insert "✓ The 'YOUR WORK' section is what you submit/present\n")
    (insert "✓ Keep automatic analysis at top for comparison\n\n\n")

    (insert "═══════════════════════════════════════════════════════════════\n\n")
    (goto-char (point-min))
    (help-mode))
  (pop-to-buffer "*Homework Helper - Help*"))

(provide 'student-homework-helper)

;;; student-homework-helper.el ends here
