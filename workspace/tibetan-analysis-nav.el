;;; tibetan-analysis-nav.el --- Source↔analysis navigation -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit three-view plan (2026-09-15), view 1 ergonomics for
;; the single-screen workflow: the source file is mostly a POINTER
;; into the analysis, so moving between the two (and between
;; neighbouring sentence files) must be one keystroke.
;;
;;   C-c u j  jump from an analysis buffer to its source heading
;;   C-c u n  next sentence's analysis file
;;   C-c u p  previous sentence's analysis file
;;
;; All three lean on the #+SOURCE link every scaffold writes and on
;; the suffix-aware resolvers in tibetan-sentence-persist.el.

;;; Code:

(require 'cl-lib)

(declare-function tibetan-sentence--sent-id-from-filename
                  "tibetan-sentence-persist" (filepath))
(declare-function tibetan-sentence--filepath "tibetan-sentence-persist"
                  (sent-num &optional folder source-file))
(declare-function tibetan-sentence--source-file-from-analysis
                  "tibetan-sentence-persist" (filepath))
(declare-function org-reveal "org" (&optional siblings))

(defun tibetan-analysis-nav--source-link (file)
  "FILE's `#+SOURCE:' link as (PATH . TARGET), or nil.
PATH is the absolute source path; TARGET the `::*HEADING' search
text (nil when the link carries none).  Reads only the header
region."
  (when (and file (stringp file) (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file nil 0 4096)
      (goto-char (point-min))
      (when (re-search-forward
             "^#\\+SOURCE: \\[\\[file:\\([^]:]+\\)\\(?:::\\*\\([^]]+\\)\\)?\\]"
             nil t)
        (cons (expand-file-name (match-string 1)
                                (file-name-directory file))
              (match-string 2))))))

;;;###autoload
(defun tibetan-analysis-jump-to-source ()
  "Jump from this analysis buffer to its source heading.
Follows the `#+SOURCE:' link (sent / seg / par files alike),
reusing the source's window when it is already visible — the
single-screen workflow's back-pointer."
  (interactive)
  (let ((f (buffer-file-name)))
    (unless f
      (user-error "Buffer besucht keine Datei"))
    (let ((link (tibetan-analysis-nav--source-link f)))
      (unless link
        (user-error "Kein #+SOURCE-Link in %s"
                    (file-name-nondirectory f)))
      (unless (file-exists-p (car link))
        (user-error "Quelle fehlt: %s" (car link)))
      (pop-to-buffer (find-file-noselect (car link))
                     '((display-buffer-reuse-window
                        display-buffer-use-some-window
                        display-buffer-same-window)))
      (when (cdr link)
        (goto-char (point-min))
        (when (re-search-forward
               (format "^\\*+ %s\\b" (regexp-quote (cdr link))) nil t)
          (beginning-of-line)
          (when (fboundp 'org-reveal)
            (ignore-errors (org-reveal))))))))

(provide 'tibetan-analysis-nav)

;;; tibetan-analysis-nav.el ends here
