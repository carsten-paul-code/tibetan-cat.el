;;; tibetan-segment-migrate.el --- Migrate inline 〔seg:N〕 markers to Org headings -*- lexical-binding: t -*-

;;; Commentary:
;; Converts legacy doc-prep output of the form
;;
;;     〔seg:N〕TIBETAN TEXT〔/seg〕
;;     〔trans:N〕TRANSLATION〔/trans〕
;;
;; into the heading-based structure expected by the CAT tool's
;; persistent analysis and sentence-structure modules:
;;
;;     *** Segment N
;;     TIBETAN TEXT
;;
;;     **** Working Translation
;;     TRANSLATION
;;
;; Empty 〔trans:N〕 blocks are preserved as an empty Working
;; Translation heading so the editor can fill them in later.
;;
;; Usage:
;;   M-x tibetan-migrate-inline-segments-to-headings
;;     (operates on the current buffer; wrap in save-excursion)
;;
;; The transformation is idempotent: running it on an already-
;; migrated buffer leaves it unchanged, because no 〔seg:N〕 tags
;; remain to match.

;;; Code:

(require 'subr-x)

(defconst tibetan-migrate--segment-block-regex
  (concat "〔seg:\\([0-9]+\\)〕"
          "\\(\\(?:.\\|\n\\)*?\\)"
          "〔/seg〕"
          "[[:space:]\n]*"
          "〔trans:[0-9]+〕"
          "\\(\\(?:.\\|\n\\)*?\\)"
          "〔/trans〕")
  "Regex matching one 〔seg:N〕 … 〔/seg〕 + 〔trans:N〕 … 〔/trans〕 block.
Group 1: the segment number.
Group 2: the Tibetan text.
Group 3: the translation text.")

(defun tibetan-migrate--format-segment (n tibetan trans)
  "Format one migrated segment block.
N is the segment number (string).  TIBETAN and TRANS are the
raw texts extracted from the inline tags; leading/trailing
whitespace is trimmed.  An empty TRANS still produces a
\"**** Working Translation\" heading so the translator can fill
it in later."
  (let ((tib (string-trim (or tibetan "")))
        (tr (string-trim (or trans ""))))
    (concat (format "*** Segment %s\n" n)
            tib
            (if (string-empty-p tib) "" "\n")
            "\n**** Working Translation\n"
            (if (string-empty-p tr) "" (concat tr "\n")))))

(defun tibetan-migrate--convert-string (text)
  "Return TEXT with every inline segment block replaced by Org headings.
Operates on strings directly (not via `replace-match') to avoid
edge cases in Emacs' replacement machinery when the replacement
spans multiple lines."
  (let ((out "")
        (pos 0))
    (while (string-match tibetan-migrate--segment-block-regex text pos)
      (let ((mstart (match-beginning 0))
            (mend   (match-end 0))
            (n   (match-string 1 text))
            (tib (match-string 2 text))
            (tr  (match-string 3 text)))
        (setq out (concat out
                          (substring text pos mstart)
                          (tibetan-migrate--format-segment n tib tr)))
        (setq pos mend)))
    (concat out (substring text pos))))

;;;###autoload
(defun tibetan-migrate-inline-segments-to-headings ()
  "Convert all inline 〔seg:N〕 / 〔trans:N〕 markers in the current buffer
to the heading-based structure *** Segment N / **** Working Translation.

Idempotent: a buffer with no remaining inline tags is left unchanged."
  (interactive)
  (let ((new (tibetan-migrate--convert-string (buffer-string))))
    (unless (string= new (buffer-string))
      (let ((p (point)))
        (erase-buffer)
        (insert new)
        (goto-char (min p (point-max)))))))

(provide 'tibetan-segment-migrate)
;;; tibetan-segment-migrate.el ends here
