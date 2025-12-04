;;; tibetan-org-structure.el --- Org-mode structure support for Tibetan CAT -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Carsten Paul
;; Keywords: Tibetan, org-mode, structure
;; Version: 1.1.0

;;; Commentary:

;; This module provides support for working with Tibetan texts structured
;; in org-mode format:
;;
;; * Title
;; ** Sentence 1
;; *** Segment 1
;; Tibetan text here
;; *** Segment 2
;; More text
;; ** Sentence 2
;; ...
;;
;; Functions:
;; - Get segment text from current heading
;; - Get all segments in current sentence
;; - Navigate between segments/sentences

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'tibetan-utils)

;;; Detection Functions

(defun tibetan-org-at-segment-p ()
  "Return t if point is in or under a segment heading (*** Segment).
Works both when cursor is on the heading line or in the content below it."
  (save-excursion
    (condition-case nil
        (progn
          ;; Try to go back to the current or parent heading
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (and (= (org-current-level) 3)
               (string-match-p "Segment" (org-get-heading t t t t))))
      (error nil))))

(defun tibetan-org-at-sentence-p ()
  "Return t if point is in or under a sentence heading (** Sentence).
Works both when cursor is on the heading line or in the content below it."
  (save-excursion
    (condition-case nil
        (progn
          ;; Try to go back to the current or parent heading
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (and (= (org-current-level) 2)
               (string-match-p "Sentence" (org-get-heading t t t t))))
      (error nil))))

;;; Segment Functions

(defun tibetan-org-get-segment-text ()
  "Get Tibetan text from current segment.
Works when positioned anywhere in or under a *** Segment heading.
Returns nil if not in a segment (no error raised)."
  (condition-case nil
      (save-excursion
        (when (tibetan-org-at-segment-p)
          ;; Move to heading (handles both on heading and in content)
          (unless (org-at-heading-p)
            (org-back-to-heading t))

          ;; Get the subtree content
          (let ((element (org-element-at-point)))
            (when element
              ;; Get the content between heading and next heading/end
              (let* ((begin (org-element-property :contents-begin element))
                     (end (org-element-property :contents-end element)))
                ;; Safety check: ensure positions are valid before accessing buffer
                (when (and begin end
                           (>= begin (point-min))
                           (<= end (point-max))
                           (< begin end))
                  (let ((content (buffer-substring-no-properties begin end)))
                    (when content
                      (string-trim content)))))))))
    (error nil)))

(defun tibetan-org-get-segment-id ()
  "Get segment ID (number) from current segment."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (when (tibetan-org-at-segment-p)
      (let ((heading (org-get-heading t t t t)))
        (when (string-match "Segment \\([0-9]+\\)" heading)
          (string-to-number (match-string 1 heading)))))))

;;; Sentence Functions

(defun tibetan-org-get-sentence-segments ()
  "Get all segment texts from current sentence.
Returns a list of strings, one per segment.
Works when positioned anywhere in or under a sentence."
  (save-excursion
    ;; First, ensure we're on a heading
    (unless (org-at-heading-p)
      (org-back-to-heading t))

    (unless (or (tibetan-org-at-sentence-p)
                (tibetan-org-at-segment-p))
      (error "Not in a sentence or segment"))

    ;; Move to sentence heading (level 2)
    (when (tibetan-org-at-segment-p)
      (org-up-heading-safe))

    (unless (tibetan-org-at-sentence-p)
      (error "Could not find sentence heading"))

    ;; Collect all segments under this sentence
    (let ((segments '())
          (sentence-level (org-current-level)))

      (org-map-entries
       (lambda ()
         (when (and (= (org-current-level) (1+ sentence-level))
                    (tibetan-org-at-segment-p))
           (let ((text (tibetan-org-get-segment-text)))
             (when text
               (push (cons (tibetan-org-get-segment-id) text) segments)))))
       nil 'tree)

      ;; Sort by segment number and return just the text
      (mapcar #'cdr (sort segments (lambda (a b) (< (car a) (car b))))))))

(defun tibetan-org-get-sentence-id ()
  "Get sentence ID (number) from current sentence.
Works when positioned anywhere in or under a sentence."
  (save-excursion
    ;; First, ensure we're on a heading
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    ;; If we're at a segment, move up to sentence
    (when (tibetan-org-at-segment-p)
      (org-up-heading-safe))
    (when (tibetan-org-at-sentence-p)
      (let ((heading (org-get-heading t t t t)))
        (when (string-match "Sentence \\([0-9]+\\)" heading)
          (string-to-number (match-string 1 heading)))))))

;;; Navigation Functions

(defun tibetan-org-next-segment ()
  "Move to next segment heading."
  (interactive)
  (when (tibetan-org-at-segment-p)
    (org-forward-heading-same-level 1)))

(defun tibetan-org-previous-segment ()
  "Move to previous segment heading."
  (interactive)
  (when (tibetan-org-at-segment-p)
    (org-backward-heading-same-level 1)))

(defun tibetan-org-next-sentence ()
  "Move to next sentence heading."
  (interactive)
  (when (tibetan-org-at-sentence-p)
    (org-forward-heading-same-level 1))
  (when (tibetan-org-at-segment-p)
    (org-up-heading-safe)
    (org-forward-heading-same-level 1)))

(defun tibetan-org-previous-sentence ()
  "Move to previous sentence heading."
  (interactive)
  (when (tibetan-org-at-sentence-p)
    (org-backward-heading-same-level 1))
  (when (tibetan-org-at-segment-p)
    (org-up-heading-safe)
    (org-backward-heading-same-level 1)))

;;; Display Functions

(defun tibetan-org-show-segment-info ()
  "Show information about current segment."
  (interactive)
  (if (tibetan-org-at-segment-p)
      (let ((seg-id (tibetan-org-get-segment-id))
            (sent-id (tibetan-org-get-sentence-id))
            (text (tibetan-org-get-segment-text)))
        (message "Sentence %d, Segment %d: %s"
                 sent-id seg-id
                 (if (> (length text) 50)
                     (concat (substring text 0 47) "...")
                   text)))
    (message "Not in a segment heading")))

(defun tibetan-org-show-sentence-info ()
  "Show information about current sentence."
  (interactive)
  (let ((sent-id (tibetan-org-get-sentence-id))
        (segments (tibetan-org-get-sentence-segments)))
    (if segments
        (message "Sentence %d has %d segments"
                 sent-id (length segments))
      (message "Not in a sentence heading"))))

;;; Integration with Existing CAT Functions

(defun tibetan-org-segment-for-analysis ()
  "Get segment text for analysis.
Returns segment text if in org structure, nil otherwise.
This integrates with tibetan-classroom.el."
  (when (and (derived-mode-p 'org-mode)
             (tibetan-org-at-segment-p))
    (tibetan-org-get-segment-text)))

(defun tibetan-org-segments-for-workspace ()
  "Get sentence segments for workspace.
Returns list of segment texts if in org structure, nil otherwise.
This integrates with tibetan-sentence-workspace.el."
  (when (and (derived-mode-p 'org-mode)
             (or (tibetan-org-at-sentence-p)
                 (tibetan-org-at-segment-p)))
    (tibetan-org-get-sentence-segments)))

(provide 'tibetan-org-structure)
;;; tibetan-org-structure.el ends here
