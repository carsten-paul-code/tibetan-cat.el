;;; tibetan-utils.el --- Utility functions for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Common utility functions used throughout the Tibetan CAT system:
;; - Text segmentation
;; - String manipulation
;; - Buffer/window management

;;; Code:

(require 'cl-lib)

;; Forward declaration for org structure support
(declare-function tibetan-org-at-segment-p "tibetan-org-structure")
(declare-function tibetan-org-get-segment-text "tibetan-org-structure")
(declare-function tibetan-org-get-segment-id "tibetan-org-structure")
(declare-function tibetan-org-get-sentence-id "tibetan-org-structure")

;; ============================================================================
;; TEXT SEGMENTATION - UNIFIED INTERFACE
;; ============================================================================

(defun tibetan-get-current-line-as-segment ()
  "Get current line as a segment (for plain text without markers).
Returns cons cell (line-number . line-text) if line contains Tibetan text, nil otherwise."
  (save-excursion
    (beginning-of-line)
    (let* ((line-start (point))
           (line-end (line-end-position))
           (line-text (buffer-substring-no-properties line-start line-end))
           (line-num (line-number-at-pos)))
      ;; Check if line contains Tibetan characters (U+0F00-U+0FFF)
      (when (and (not (string-empty-p (string-trim line-text)))
                 (string-match-p "[ཀ-࿿]" line-text)
                 ;; Exclude org-mode headings
                 (not (string-match-p "^\\*+ " line-text))
                 ;; Exclude property drawers and other org syntax
                 (not (string-match-p "^[ \t]*:" line-text))
                 (not (string-match-p "^#\\+" line-text)))
        (cons (format "Line %d" line-num) (string-trim line-text))))))

(defun tibetan-get-current-segment-any-format ()
  "Get current segment ID and text from ANY format.
Tries in order:
1. Org structure (*** Segment N)
2. Old markers (〔seg:...〕)
3. Plain text line (for text-only documents)

Returns cons cell (seg-id . seg-text) or nil."
  (or
   ;; Try org structure first
   (when (and (derived-mode-p 'org-mode)
              (require 'tibetan-org-structure nil t)
              (fboundp 'tibetan-org-at-segment-p)
              (tibetan-org-at-segment-p))
     (let ((text (tibetan-org-get-segment-text))
           (seg-num (tibetan-org-get-segment-id))
           (sent-num (tibetan-org-get-sentence-id)))
       (when text
         (cons (format "Sentence %d, Segment %d" sent-num seg-num) text))))

   ;; Try old markers second
   (tibetan-get-current-segment)

   ;; Fall back to plain text line
   (tibetan-get-current-line-as-segment)))

(defun tibetan-get-current-segment ()
  "Get current segment ID and text.
Handles both old format 〔seg:ID〕 and new format 〔seg〕.
Returns cons cell (seg-id . seg-text) if point is within a segment, nil otherwise."
  (save-excursion
    (let ((pos (point))
          (case-fold-search t))
      ;; Try new format first: 〔seg〕...〔/seg〕 (no ID)
      (or (tibetan--get-segment-new-format pos)
          ;; Fall back to old format: 〔seg:ID〕...〔/seg〕
          (tibetan--get-segment-old-format pos)))))

(defun tibetan--get-segment-new-format (pos)
  "Get segment in new format 〔seg〕...〔/seg〕 at POS.
Returns (line-number . text) or nil."
  (save-excursion
    (goto-char pos)
    (when (re-search-backward "〔seg〕" nil t)
      (let ((seg-start (match-end 0))
            (seg-line (line-number-at-pos)))
        (when (re-search-forward "〔/seg〕" nil t)
          (let ((seg-end (match-beginning 0)))
            (when (and (>= pos seg-start) (<= pos seg-end))
              (cons (format "Line %d" seg-line)
                    (string-trim (buffer-substring-no-properties seg-start seg-end))))))))))

(defun tibetan--get-segment-old-format (pos)
  "Get segment in old format 〔seg:ID〕...〔/seg〕 at POS.
Returns (id . text) or nil."
  (save-excursion
    (goto-char pos)
    (when (re-search-backward "〔seg:\\([^〕]+\\)〕" nil t)
      (let ((seg-id (match-string 1))
            (seg-start (match-end 0)))
        (when (re-search-forward "〔/seg〕" nil t)
          (let ((seg-end (match-beginning 0)))
            (when (and (>= pos seg-start) (<= pos seg-end))
              (cons seg-id (string-trim (buffer-substring-no-properties seg-start seg-end))))))))))

(defun tibetan-get-all-segments ()
  "Get all segments in current buffer.
Handles both old format 〔seg:ID〕 and new format 〔seg〕.
Returns list of cons cells (seg-id . seg-text)."
  (save-excursion
    (goto-char (point-min))
    (let ((segments '())
          (case-fold-search t)
          (seg-count 0))
      ;; Match both 〔seg:ID〕 and 〔seg〕
      (while (re-search-forward "〔seg\\(?::\\([^〕]+\\)\\)?〕" nil t)
        (setq seg-count (1+ seg-count))
        (let ((seg-id (or (match-string 1) (format "seg-%d" seg-count)))
              (seg-start (match-end 0)))
          (when (re-search-forward "〔/seg〕" nil t)
            (let* ((seg-end (match-beginning 0))
                   (seg-text (string-trim (buffer-substring-no-properties seg-start seg-end))))
              (push (cons seg-id seg-text) segments)))))
      (nreverse segments))))

;; ============================================================================
;; STRING MANIPULATION
;; ============================================================================

(defun tibetan-normalize-text (text)
  "Normalize Tibetan TEXT for processing.
Replaces spaces with tsheg, removes extra whitespace."
  (when text
    (let ((normalized text))
      ;; Replace spaces with tsheg
      (setq normalized (replace-regexp-in-string " " "་" normalized))
      ;; Remove duplicate tsheg
      (setq normalized (replace-regexp-in-string "་+" "་" normalized))
      ;; Trim whitespace
      (setq normalized (string-trim normalized))
      normalized)))

(defun tibetan-split-into-syllables (text)
  "Split Tibetan TEXT into syllables.
Returns list of syllables."
  (when text
    (let ((normalized (tibetan-normalize-text text)))
      (split-string normalized "་" t))))

(defun tibetan-clean-text (text)
  "Remove Tibetan punctuation from TEXT.
Keeps only syllables and tsheg."
  (when text
    (replace-regexp-in-string "[།༎༏༐༑༔]" "" text)))

;; ============================================================================
;; WINDOW MANAGEMENT
;; ============================================================================

(defun tibetan-display-in-side-window (buffer-name)
  "Display BUFFER-NAME in a side window (right or below).
Returns the window."
  (let ((buf (get-buffer-create buffer-name)))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer))
    ;; Try to display on the right, fall back to below
    (or (display-buffer-in-side-window buf '((side . right) (window-width . 80)))
        (display-buffer-in-side-window buf '((side . bottom) (window-height . 20))))))

(defun tibetan-close-side-window (buffer-name)
  "Close side window displaying BUFFER-NAME."
  (let ((buf (get-buffer buffer-name)))
    (when buf
      (let ((win (get-buffer-window buf)))
        (when win
          (delete-window win))))))

;; ============================================================================
;; BUFFER CONTENT HELPERS
;; ============================================================================

(defun tibetan-insert-section (title &optional level)
  "Insert org-mode section with TITLE at LEVEL (default 2)."
  (let ((level (or level 2)))
    (insert (make-string level ?*) " " title "\n\n")))

(defun tibetan-insert-separator ()
  "Insert a visual separator line."
  (insert "───────────────────────────────────────────────────────────────\n"))

(provide 'tibetan-utils)
;;; tibetan-utils.el ends here
