;;; tibetan-doc-display.el --- Display settings for prepared Tibetan documents -*- lexical-binding: t -*-

;;; Commentary:
;; Provides font-lock rules and display settings for Tibetan prepared documents.
;; Makes segment markers (〔seg〕, 〔sent〕, etc.) smaller and less obtrusive
;; so the Tibetan text is more readable.

;;; Code:

(require 'org)

;; ============================================================================
;; FACES FOR SEGMENT MARKERS
;; ============================================================================

(defface tibetan-doc-marker-face
  '((t (:height 0.6
        :foreground "gray50"
        :weight light)))
  "Face for segment markers like 〔seg〕, 〔sent〕, 〔/seg〕.
Smaller and muted to not distract from Tibetan text."
  :group 'tibetan-cat)

(defface tibetan-doc-marker-tag-face
  '((t (:height 0.6
        :foreground "gray40"
        :weight light)))
  "Face for marker tags (seg, sent, verse, prose)."
  :group 'tibetan-cat)

(defface tibetan-doc-marker-attr-face
  '((t (:height 0.6
        :foreground "steel blue"
        :weight light)))
  "Face for marker attributes like :num or :comment-on."
  :group 'tibetan-cat)

;; ============================================================================
;; FONT-LOCK KEYWORDS
;; ============================================================================

(defvar tibetan-doc-font-lock-keywords
  '(;; Opening markers: 〔seg〕, 〔sent〕, 〔verse :num N〕, 〔prose :comment-on N〕
    ("\\(〔\\)\\(seg\\|sent\\|verse\\|prose\\)\\([^〕]*\\)\\(〕\\)"
     (1 'tibetan-doc-marker-face t)
     (2 'tibetan-doc-marker-tag-face t)
     (3 'tibetan-doc-marker-attr-face t)
     (4 'tibetan-doc-marker-face t))
    ;; Closing markers: 〔/seg〕, 〔/sent〕, etc.
    ("\\(〔/\\)\\(seg\\|sent\\|verse\\|prose\\)\\(〕\\)"
     (1 'tibetan-doc-marker-face t)
     (2 'tibetan-doc-marker-tag-face t)
     (3 'tibetan-doc-marker-face t))
    ;; Old format markers: 〔seg:N〕
    ("\\(〔seg:\\)\\([0-9]+\\)\\(〕\\)"
     (1 'tibetan-doc-marker-face t)
     (2 'tibetan-doc-marker-attr-face t)
     (3 'tibetan-doc-marker-face t))
    ;; Inline verse references: 〈v:N〉
    ("\\(〈v:\\)\\([0-9]+\\)\\(〉\\)"
     (1 'tibetan-doc-marker-face t)
     (2 'tibetan-doc-marker-attr-face t)
     (3 'tibetan-doc-marker-face t)))
  "Font-lock keywords for Tibetan document segment markers.")

;; ============================================================================
;; MINOR MODE
;; ============================================================================

(define-minor-mode tibetan-doc-display-mode
  "Minor mode for displaying Tibetan prepared documents.
Makes segment markers smaller and less obtrusive."
  :lighter " TibDoc"
  :group 'tibetan-cat
  (if tibetan-doc-display-mode
      (progn
        ;; Add our font-lock keywords
        (font-lock-add-keywords nil tibetan-doc-font-lock-keywords)
        ;; Refontify the buffer
        (when font-lock-mode
          (font-lock-flush)
          (font-lock-ensure)))
    ;; Remove our font-lock keywords
    (font-lock-remove-keywords nil tibetan-doc-font-lock-keywords)
    (when font-lock-mode
      (font-lock-flush)
      (font-lock-ensure))))

;; ============================================================================
;; AUTO-ENABLE FOR PREPARED DOCUMENTS
;; ============================================================================

(defun tibetan-doc-display--maybe-enable ()
  "Enable tibetan-doc-display-mode if buffer contains Tibetan segment markers."
  (when (and buffer-file-name
             (derived-mode-p 'org-mode)
             (save-excursion
               (goto-char (point-min))
               (or (re-search-forward "〔seg" nil t)
                   (re-search-forward "〔sent" nil t)
                   (re-search-forward "〔verse" nil t))))
    (tibetan-doc-display-mode 1)))

;; Hook into org-mode
(add-hook 'org-mode-hook #'tibetan-doc-display--maybe-enable)

;; ============================================================================
;; UTILITY FUNCTIONS
;; ============================================================================

(defun tibetan-doc-toggle-markers ()
  "Toggle visibility of segment markers in current buffer."
  (interactive)
  (if tibetan-doc-display-mode
      (tibetan-doc-display-mode -1)
    (tibetan-doc-display-mode 1))
  (message "Tibetan doc markers: %s"
           (if tibetan-doc-display-mode "scaled down" "normal size")))

(defun tibetan-doc-hide-markers ()
  "Hide segment markers completely (invisible)."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "〔[^〕]*〕" nil t)
      (put-text-property (match-beginning 0) (match-end 0) 'invisible t)))
  (message "Markers hidden. Use M-x tibetan-doc-show-markers to restore."))

(defun tibetan-doc-show-markers ()
  "Show all segment markers (remove invisible property)."
  (interactive)
  (remove-text-properties (point-min) (point-max) '(invisible nil))
  (message "Markers visible."))

(provide 'tibetan-doc-display)
;;; tibetan-doc-display.el ends here
