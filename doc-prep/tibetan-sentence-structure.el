;;; tibetan-sentence-structure.el --- Add sentence structure to Tibetan documents -*- lexical-binding: t -*-

;;; Commentary:
;; Provides functions to automatically detect and add sentence-level structure
;; to existing Tibetan .org documents.
;;
;; Sentence boundaries are detected by:
;; - Double shad (།།) - definite sentence end
;; - Single shad (།) followed by sentence-final particles (སོ། ཏོ། ངོ། etc.)
;; - Main verb + final particle combinations
;;
;; Usage:
;;   M-x tibetan-add-sentence-structure   ; Adds ** Sentence headings above segments
;;   M-x tibetan-detect-sentence-boundaries  ; Preview where sentences would be
;;
;; After running tibetan-add-sentence-structure, the document will have:
;;   * Section
;;   ** Sentence 1
;;   *** Segment 1
;;   text
;;   *** Segment 2
;;   text
;;   ** Sentence 2
;;   *** Segment 3
;;   ...

;;; Code:

(require 'org)
(require 'cl-lib)

;; ============================================================================
;; SENTENCE BOUNDARY DETECTION
;; ============================================================================

(defvar tibetan-sentence-final-particles
  '("སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ"   ; Sentence-final particles
    "གོ" "བོ"                            ; More sentence finals
    "ཡིན" "མིན"                          ; Copulas (often end sentences)
    "ཡོད" "མེད")                         ; Existentials
  "Particles/words that often end sentences when followed by shad.")

(defvar tibetan-converb-particles
  '("ནས" "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང")
  "Converb particles that typically do NOT end sentences.")

(defun tibetan-is-sentence-boundary-p (text)
  "Determine if TEXT ends at a sentence boundary.
Returns t if this looks like a sentence end, nil otherwise."
  (when text
    (let ((trimmed (string-trim text)))
      (cond
       ;; Double shad is definite sentence boundary
       ((string-suffix-p "།།" trimmed) t)
       ((string-suffix-p "༎" trimmed) t)
       ;; Single shad with sentence-final particle before it
       ((and (string-suffix-p "།" trimmed)
             (let ((before-shad (replace-regexp-in-string "།+$" "" trimmed)))
               (cl-some (lambda (p) (string-suffix-p p before-shad))
                        tibetan-sentence-final-particles)))
        t)
       ;; Converbs don't end sentences
       ((cl-some (lambda (p)
                   (string-match-p (format "%s།*$" (regexp-quote p)) trimmed))
                 tibetan-converb-particles)
        nil)
       ;; Default: single shad might or might not be sentence boundary
       ;; Return 'maybe for manual review
       ((string-suffix-p "།" trimmed) 'maybe)
       (t nil)))))

(defun tibetan-detect-sentence-boundaries ()
  "Preview sentence boundaries in current buffer.
Shows which segments would start new sentences."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (error "This command only works in org-mode buffers"))

  (let ((boundaries '())
        (current-sent 1)
        (prev-was-boundary t))  ; First segment always starts a sentence

    (save-excursion
      (goto-char (point-min))
      ;; Find all segments
      (while (re-search-forward "^\\*\\*\\* Segment \\([0-9]+\\)" nil t)
        (let* ((seg-num (string-to-number (match-string 1)))
               (seg-text (save-excursion
                           (forward-line 1)
                           (let ((start (point)))
                             (if (re-search-forward "^\\*" nil t)
                                 (buffer-substring-no-properties start (line-beginning-position))
                               (buffer-substring-no-properties start (point-max))))))
               (is-boundary (tibetan-is-sentence-boundary-p seg-text)))

          (when prev-was-boundary
            (push (list :segment seg-num :sentence current-sent) boundaries)
            (setq current-sent (1+ current-sent)))

          (setq prev-was-boundary is-boundary))))

    ;; Display results
    (with-current-buffer (get-buffer-create "*Sentence Boundaries*")
      (erase-buffer)
      (insert "Detected Sentence Structure\n")
      (insert "===========================\n\n")
      (dolist (b (nreverse boundaries))
        (insert (format "Sentence %d starts at Segment %d\n"
                        (plist-get b :sentence)
                        (plist-get b :segment))))
      (insert (format "\nTotal: %d sentences detected\n" (1- current-sent)))
      (display-buffer (current-buffer)))))

;; ============================================================================
;; ADD SENTENCE STRUCTURE
;; ============================================================================

(defun tibetan-add-sentence-structure ()
  "Add ** Sentence N headings to organize segments into sentences.
Analyzes segment endings to detect sentence boundaries.
Transforms:
  ** Section
  *** Segment 1
  *** Segment 2
  ...
Into:
  ** Section
  *** Sentence 1
  **** Segment 1
  **** Segment 2 (if same sentence)
  *** Sentence 2
  **** Segment 3
  ..."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (error "This command only works in org-mode buffers"))

  ;; Confirm with user
  (unless (yes-or-no-p "Add sentence structure? This will modify segment headings. ")
    (user-error "Cancelled"))

  ;; Work backwards to avoid position issues
  (let ((changes '())
        (current-sent 1)
        (prev-was-boundary t)
        (segment-positions '()))

    ;; First pass: detect sentence starts and collect positions
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*\\*\\*\\) Segment \\([0-9]+\\)" nil t)
        (let* ((stars (match-string 1))
               (seg-num (string-to-number (match-string 2)))
               (seg-pos (match-beginning 0))
               (seg-text (save-excursion
                           (forward-line 1)
                           (let ((start (point)))
                             (if (re-search-forward "^\\*" nil t)
                                 (buffer-substring-no-properties start (line-beginning-position))
                               (buffer-substring-no-properties start (point-max))))))
               (is-boundary (tibetan-is-sentence-boundary-p seg-text))
               (starts-sentence prev-was-boundary))

          (push (list :pos seg-pos
                      :seg-num seg-num
                      :starts-sentence starts-sentence
                      :sentence-num (if starts-sentence current-sent nil))
                segment-positions)

          (when starts-sentence
            (setq current-sent (1+ current-sent)))

          (setq prev-was-boundary is-boundary))))

    ;; Second pass: make changes (working backwards)
    (dolist (seg (reverse segment-positions))
      (when (plist-get seg :starts-sentence)
        (let ((pos (plist-get seg :pos))
              (sent-num (plist-get seg :sentence-num)))
          (goto-char pos)
          ;; Insert sentence heading before this segment
          (insert (format "*** Sentence %d\n" sent-num))
          ;; Demote segment heading (*** -> ****)
          (forward-line 0)
          (when (looking-at "\\*\\*\\* Segment")
            (replace-match "**** Segment")))))

    (message "Added sentence structure: %d sentences" (1- current-sent))))

;; ============================================================================
;; MANUAL SENTENCE MARKING
;; ============================================================================

(defun tibetan-mark-sentence-start ()
  "Mark current segment as starting a new sentence.
Inserts a ** Sentence heading above the current segment."
  (interactive)
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))

    (unless (looking-at "\\*\\*\\*\\* Segment\\|\\*\\*\\* Segment")
      (error "Not on a Segment heading"))

    ;; Find the next available sentence number
    (let ((max-sent 0))
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Sentence \\([0-9]+\\)" nil t)
          (setq max-sent (max max-sent (string-to-number (match-string 1))))))

      ;; Insert sentence heading
      (let ((sent-num (1+ max-sent)))
        (beginning-of-line)
        (insert (format "*** Sentence %d\n" sent-num))
        ;; Demote segment if needed
        (when (looking-at "\\*\\*\\* Segment")
          (replace-match "**** Segment"))
        (message "Marked as start of Sentence %d" sent-num)))))

(defun tibetan-insert-sentence-heading ()
  "Interactively insert a sentence heading at point.
Prompts for sentence number."
  (interactive)
  (let ((sent-num (read-number "Sentence number: ")))
    (beginning-of-line)
    (insert (format "** Sentence %d\n" sent-num))
    (message "Inserted Sentence %d heading" sent-num)))

(provide 'tibetan-sentence-structure)
;;; tibetan-sentence-structure.el ends here
