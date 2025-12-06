;;; tibetan-doc-format.el --- Org document formatting for Tibetan texts -*- lexical-binding: t -*-

;;; Commentary:
;; Formats Tibetan text into org-mode documents ready for CAT workflow.
;;
;; Features:
;; - Line breaking at shad (།) or double-shad (༎)
;; - Segment marker insertion (〔seg:N〕)
;; - Folio marker handling (headings, inline, properties)
;; - Text type headers for CAT mode
;;
;; Usage:
;;   (tibetan-doc-format text source-info options)
;;   (tibetan-doc-format text source-info options output-path)

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CONSTANTS
;; ============================================================================

(defconst tibetan-doc-format-shad "།"
  "Tibetan single shad punctuation.")

(defconst tibetan-doc-format-double-shad "༎"
  "Tibetan double shad (nyis shad) punctuation.")

(defconst tibetan-doc-format-tsheg "་"
  "Tibetan tsheg (syllable separator).")

;; ============================================================================
;; TEXT SPLITTING
;; ============================================================================

(defun tibetan-doc-format--split-at-shad (text)
  "Split TEXT at single shad (།), creating one line per segment.
Preserves the shad at end of each segment."
  (let ((segments (split-string text "།" t "[ \t\n]+")))
    (mapcar (lambda (seg)
              (concat (string-trim seg) "།"))
            segments)))

(defun tibetan-doc-format--split-at-double-shad (text)
  "Split TEXT at double shad (༎), keeping single shad within lines.
Preserves the double-shad at end of each segment."
  (let ((segments (split-string text "༎" t "[ \t\n]+")))
    (mapcar (lambda (seg)
              (concat (string-trim seg) "༎"))
            segments)))

(defun tibetan-doc-format--split-preserve (text)
  "Split TEXT preserving original line breaks."
  (split-string text "\n" t "[ \t]+"))

(defun tibetan-doc-format--split-text (text line-break-style)
  "Split TEXT according to LINE-BREAK-STYLE.
Returns list of text segments."
  (pcase line-break-style
    ('shad (tibetan-doc-format--split-at-shad text))
    ('double-shad (tibetan-doc-format--split-at-double-shad text))
    ('preserve (tibetan-doc-format--split-preserve text))
    (_ (tibetan-doc-format--split-at-shad text))))

;; ============================================================================
;; SEGMENT MARKERS
;; ============================================================================

(defun tibetan-doc-format--add-segment-markers (lines &optional start-num)
  "Add 〔seg:N〕 markers to LINES.
START-NUM is the starting segment number (default 1).
Returns list of marked lines."
  (let ((n (or start-num 1)))
    (mapcar (lambda (line)
              (prog1
                  (format "〔seg:%d〕%s〔/seg〕" n (string-trim line))
                (setq n (1+ n))))
            lines)))

(defun tibetan-doc-format--segment-count (lines)
  "Count number of non-empty segments in LINES."
  (length (seq-filter (lambda (l) (not (string-empty-p (string-trim l)))) lines)))

;; ============================================================================
;; FOLIO MARKERS
;; ============================================================================

(defun tibetan-doc-format--folio-as-heading (folio-num)
  "Format FOLIO-NUM as org heading."
  (format "** Folio %s\n" folio-num))

(defun tibetan-doc-format--folio-inline (folio-num)
  "Format FOLIO-NUM as inline marker."
  (format "[F:%s] " folio-num))

(defun tibetan-doc-format--folio-as-property (folio-num)
  "Format FOLIO-NUM as property drawer opener."
  (format ":PROPERTIES:\n:FOLIO: %s\n:END:\n" folio-num))

(defun tibetan-doc-format--insert-folio (folio-num style)
  "Generate folio marker for FOLIO-NUM in STYLE."
  (pcase style
    ('heading (tibetan-doc-format--folio-as-heading folio-num))
    ('inline (tibetan-doc-format--folio-inline folio-num))
    ('property (tibetan-doc-format--folio-as-property folio-num))
    (_ (tibetan-doc-format--folio-as-heading folio-num))))

(defun tibetan-doc-format--extract-folio-markers (text)
  "Extract folio markers from TEXT.
Looks for patterns like [1a], [1b], (1a), (1b), F.1a, etc.
Returns alist of ((position . folio-num) ...)."
  (let ((markers '())
        (patterns '("\\[\\([0-9]+[ab]\\)\\]"      ; [1a], [1b]
                   "(\\([0-9]+[ab]\\))"           ; (1a), (1b)
                   "F\\.?\\([0-9]+[ab]\\)"        ; F.1a, F1a
                   "folio[ ]*\\([0-9]+[ab]\\)"))) ; folio 1a
    (dolist (pattern patterns)
      (save-match-data
        (let ((pos 0))
          (while (string-match pattern text pos)
            (push (cons (match-beginning 0) (match-string 1 text)) markers)
            (setq pos (match-end 0))))))
    (sort markers (lambda (a b) (< (car a) (car b))))))

;; ============================================================================
;; HEADER GENERATION
;; ============================================================================

(defun tibetan-doc-format--generate-header (source-info options)
  "Generate org file header from SOURCE-INFO and OPTIONS."
  (let ((title (or (plist-get source-info :title) "Tibetan Text"))
        (text-type (or (plist-get options :text-type) 'classical))
        (source-file (plist-get source-info :source-file))
        (folio-range (plist-get source-info :folio-range)))
    (concat
     (format "#+TITLE: %s\n" title)
     (format "#+TIBETAN_TEXT_TYPE: %s\n" text-type)
     (when source-file
       (format "#+SOURCE: %s\n" source-file))
     (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d"))
     "#+OPTIONS: toc:nil\n"
     "\n"
     "* Document Info\n"
     ":PROPERTIES:\n"
     (when source-file
       (format ":OCR_SOURCE: %s\n" source-file))
     (format ":CREATED: %s\n" (format-time-string "%Y-%m-%d %H:%M"))
     (when folio-range
       (format ":FOLIOS: %s\n" folio-range))
     ":END:\n")))

;; ============================================================================
;; BODY GENERATION
;; ============================================================================

(defun tibetan-doc-format--generate-body (text options)
  "Generate org body from TEXT with OPTIONS."
  (let* ((line-break (or (plist-get options :line-break) 'shad))
         (add-segments (plist-get options :segments))
         (folio-style (or (plist-get options :folio-style) 'heading))
         (lines (tibetan-doc-format--split-text text line-break))
         (folio-markers (tibetan-doc-format--extract-folio-markers text))
         (result ""))

    ;; Start text section
    (setq result (concat result "\n* Text\n\n"))

    ;; Process lines
    (if add-segments
        (let ((marked-lines (tibetan-doc-format--add-segment-markers lines)))
          (dolist (line marked-lines)
            (setq result (concat result line "\n"))))
      (dolist (line lines)
        (let ((trimmed (string-trim line)))
          (when (not (string-empty-p trimmed))
            (setq result (concat result trimmed "\n"))))))

    result))

;; ============================================================================
;; MAIN FORMATTING FUNCTION
;; ============================================================================

;;;###autoload
(defun tibetan-doc-format (text source-info options &optional output-path)
  "Format TEXT into org document.

SOURCE-INFO is plist with:
  :source-file   Original file path
  :title         Document title
  :folio-range   Range of folios (e.g., \"1a-5b\")

OPTIONS is plist with:
  :line-break    `shad' | `double-shad' | `preserve'
  :segments      t | nil (add segment markers)
  :folio-style   `heading' | `inline' | `property'
  :text-type     `classical' | `madhyamaka-verse' | `sutra' | `commentary'

OUTPUT-PATH is optional file path. If nil, generates path from source.

Returns path to created file."
  (let* ((output-file (or output-path
                         (tibetan-doc-format--generate-output-path source-info)))
         (header (tibetan-doc-format--generate-header source-info options))
         (body (tibetan-doc-format--generate-body text options)))

    (with-temp-file output-file
      (insert header)
      (insert body)
      (goto-char (point-min)))

    output-file))

(defun tibetan-doc-format--generate-output-path (source-info)
  "Generate output file path from SOURCE-INFO."
  (let* ((source-file (plist-get source-info :source-file))
         (title (plist-get source-info :title))
         (base-name (or (when source-file (file-name-base source-file))
                       title
                       "tibetan-text"))
         (dir (or (when source-file (file-name-directory source-file))
                 default-directory)))
    (expand-file-name (concat base-name "-prepared.org") dir)))

;; ============================================================================
;; INTERACTIVE COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-doc-format-buffer ()
  "Format current buffer's Tibetan text into org structure.
Prompts for formatting options."
  (interactive)
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (source-info (list :title (or (file-name-base buffer-file-name)
                                      "Formatted Text")
                           :source-file buffer-file-name))
         (options (tibetan-doc-format--prompt-options))
         (output-file (tibetan-doc-format text source-info options)))
    (find-file output-file)
    (message "Created: %s" output-file)))

;;;###autoload
(defun tibetan-doc-format-region (start end)
  "Format region between START and END into org document."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (source-info (list :title "Selected Text"
                           :source-file buffer-file-name))
         (options (tibetan-doc-format--prompt-options))
         (output-file (tibetan-doc-format text source-info options)))
    (find-file output-file)
    (message "Created: %s" output-file)))

(defun tibetan-doc-format--prompt-options ()
  "Prompt user for formatting options.
Returns options plist."
  (list
   :line-break (intern (completing-read
                        "Line breaks at: "
                        '("shad" "double-shad" "preserve")
                        nil t nil nil "shad"))
   :segments (yes-or-no-p "Add segment markers? ")
   :folio-style (intern (completing-read
                         "Folio style: "
                         '("heading" "inline" "property")
                         nil t nil nil "heading"))
   :text-type (intern (completing-read
                       "Text type: "
                       '("classical" "madhyamaka-verse" "sutra" "commentary")
                       nil t nil nil "classical"))))

;; ============================================================================
;; UTILITY FUNCTIONS
;; ============================================================================

(defun tibetan-doc-format-clean-ocr-artifacts (text)
  "Remove common OCR artifacts from TEXT.
Removes extra spaces, normalizes punctuation, etc."
  (let ((result text))
    ;; Normalize multiple spaces to single tsheg
    (setq result (replace-regexp-in-string "  +" "་" result))
    ;; Remove spaces around Tibetan punctuation
    (setq result (replace-regexp-in-string " *། *" "།" result))
    (setq result (replace-regexp-in-string " *༎ *" "༎" result))
    ;; Normalize tsheg spacing
    (setq result (replace-regexp-in-string "་་+" "་" result))
    ;; Remove trailing tshegs before punctuation
    (setq result (replace-regexp-in-string "་།" "།" result))
    (setq result (replace-regexp-in-string "་༎" "༎" result))
    result))

(defun tibetan-doc-format-normalize-text (text)
  "Normalize TEXT for consistent processing.
Converts various Unicode forms, normalizes spacing."
  (let ((result text))
    ;; Replace regular spaces with tshegs in Tibetan context
    (setq result (replace-regexp-in-string
                  "\\([ༀ-࿿]\\) +\\([ༀ-࿿]\\)"
                  "\\1་\\2"
                  result))
    ;; Clean OCR artifacts
    (setq result (tibetan-doc-format-clean-ocr-artifacts result))
    result))

(provide 'tibetan-doc-format)
;;; tibetan-doc-format.el ends here
