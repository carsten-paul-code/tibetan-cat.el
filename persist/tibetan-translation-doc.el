;;; tibetan-translation-doc.el --- Stitch the user's translation out of cascade files -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit three-view plan (2026-09-15), view 3:  Carsten's own
;; German translation lives SENTENCE-WISE in the cascade analysis
;; files — `* Working Translation' carries the prose (with named org
;; footnote anchors `[fn:name]'), `* Footnotes' the definitions (the
;; §184-handout convention).  This module GENERATES the deliverable
;; views out of those slots:
;;
;;   - `tibetan-translation-doc-build' — the continuous translation
;;     document (§-grouped, footnotes namespaced per sentence and
;;     collected at the end), e.g. §§182–186 for thesis appendix A.1.
;;   - `tibetan-translation-doc-section-view' — one compiled per-§
;;     view (Tibetan + gloss tables + Claude/DM suggestions + his
;;     translation) for consultations and reading classes.
;;
;; Both outputs are GENERATED artifacts: a marker line in the header
;; identifies them, regeneration overwrites only marked files (never
;; a hand-owned document), and they contain ONLY Carsten's own text
;; plus tool output — the Lopez / Wangjié&Mulligan reference
;; translations are copyright-restricted and never leave the
;; comparative documents (they reach Claude prompt-only; see
;; `tibetan-cascade--section-refs-block').

;;; Code:

(require 'cl-lib)
;; The L1 body reader (Working Translation / Footnotes) lives with
;; the cascade machinery.  Soft — callers are fboundp-guarded.
(require 'tibetan-cascade nil t)

(declare-function tibetan-cascade--read-l1-body "tibetan-cascade"
                  (file heading))

(defun tibetan-translation-doc--source-outline (source-file)
  "Ordered §-outline of the cascade SOURCE-FILE.
Returns a list of plists (:lopez N :sent-nums (N1 N2 …)) — one per
`** Section' heading, N from the section drawer's :LOPEZ_SECTION:
property (nil when the drawer lacks it), sentence numbers from the
child `*** Sentence N' headings in file order.  Sentences BEFORE
any Section land in a leading (:lopez nil …) group.  nil when the
file has no sentences."
  (when (and source-file (stringp source-file)
             (file-exists-p source-file))
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (let ((groups nil)          ; reversed list of (LOPEZ . REV-SENTS)
            (current nil))        ; the open group, or nil before any
        (while (re-search-forward
                (concat "^\\(?:\\*\\{1,2\\} Section\\b.*\\)$"
                        "\\|^:LOPEZ_SECTION:[ \t]+\\([0-9]+\\)[ \t]*$"
                        "\\|^\\*\\{3\\} Sentence[ \t]+\\([0-9]+\\)\\b")
                nil t)
          (cond
           ((match-string 1)              ; drawer property of the
            (when current                 ; just-opened Section
              (setcar current (string-to-number (match-string 1)))))
           ((match-string 2)              ; a Sentence heading
            (unless current
              (setq current (cons nil nil))
              (push current groups))
            (setcdr current (cons (string-to-number (match-string 2))
                                  (cdr current))))
           (t                             ; a Section heading
            (setq current (cons nil nil))
            (push current groups))))
        (let (out)
          (dolist (g groups)
            (when (cdr g)                 ; drop sentence-less Sections
              (push (list :lopez (car g)
                          :sent-nums (nreverse (cdr g)))
                    out)))
          out)))))

(defun tibetan-translation-doc--working-translation (file)
  "FILE's `* Working Translation' body (trimmed), nil when empty."
  (and (fboundp 'tibetan-cascade--read-l1-body)
       (tibetan-cascade--read-l1-body file "Working Translation")))

(defun tibetan-translation-doc--footnote-definitions (file)
  "FILE's `* Footnotes' body verbatim (edge-trimmed), nil when empty."
  (and (fboundp 'tibetan-cascade--read-l1-body)
       (tibetan-cascade--read-l1-body file "Footnotes")))

(defun tibetan-translation-doc--namespace-footnotes (text prefix)
  "TEXT with every named org footnote label PREFIXed.
Rewrites `[fn:LABEL]' anchors, `[fn:LABEL] Definition' labels and
inline `[fn:LABEL:def]' forms to `[fn:PREFIXLABEL…]' — ONE regex
covers all three, because the label is always followed by `]' or
`:'.  Anonymous inline footnotes `[fn::…]' (empty label) stay
untouched.  Namespacing per sentence file (PREFIX like \"s012-\")
keeps labels collision-free when many files stitch into one
document."
  (replace-regexp-in-string
   "\\[fn:\\([-_[:alnum:]]+\\)\\([]:]\\)"
   (concat "[fn:" prefix "\\1\\2")
   (or text "") t))

(provide 'tibetan-translation-doc)

;;; tibetan-translation-doc.el ends here
