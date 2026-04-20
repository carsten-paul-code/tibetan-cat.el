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

;; ============================================================================
;; BARE-SEG MIGRATOR (for documents with 〔seg:N〕…〔/seg〕 only, no trans)
;; ============================================================================
;;
;; The Thar-rgyan / Josefine pipeline produces a different inline form:
;; only 〔seg:N〕…〔/seg〕 (no translation wrapper), plus Tibetan-title
;; headings that carry an inline 〔/seg〕 closer at the end of the heading
;; line to mark where the previous segment ends.  In addition, the very
;; first segment often contains document-level `#+KEYWORD:' metadata that
;; should live in the document header rather than inside a segment.
;;
;; The bare-seg migrator normalises all of this into the Milarepa-style
;; structure:
;;
;;     #+TITLE: …                   ← hoisted from seg:1 body
;;     #+AUTHOR: …                  ← hoisted
;;     #+TIBETAN_CLAUDE_CONTEXT: …  ← hoisted
;;
;;     * Document Info              ← preserved (has no 〔/seg〕 on its line)
;;     * Text                       ← preserved
;;     ** མཚན་བྱང་།                ← flattened from `*'/`**'/`***' Tibetan title
;;     *** Segment 1                ← fresh numbering from 1
;;     (Title)
;;     <Tibetan body>
;;     ** མཆོད་བརྗོད།
;;     *** Segment 2
;;     …
;;
;; See `tibetan-migrate--convert-bare-string' for the orchestration and
;; the three helpers `--split-and-flatten-title-headings',
;; `--hoist-metadata-from-body', and `--convert-bare-seg-blocks'.

(defconst tibetan-migrate--bare-seg-regex
  (concat "〔seg:\\([0-9]+\\)〕"
          "\\(\\(?:.\\|\n\\)*?\\)"
          "〔/seg〕")
  "Regex matching one 〔seg:N〕 … 〔/seg〕 block (no trans required).
Group 1: the original segment number (discarded on migration).
Group 2: the body text between markers.")

(defconst tibetan-migrate--keyword-line-regex
  "^#\\+[A-Z][A-Z0-9_]*:.*$"
  "Regex matching an Org `#+KEYWORD: value' document-level metadata line.
Deliberately excludes block markers like `#+BEGIN_SRC' (which have no
colon immediately after the keyword name).")

(defun tibetan-migrate--split-and-flatten-title-headings (text)
  "Step 1 of the bare-seg migration.

For every heading line of the shape `^\\*+ <title>〔/seg〕$', emit TWO
lines in its place:

  1. `〔/seg〕' on its own line (so the previous segment closes cleanly
     at the start of the next regex iteration).
  2. `** <title>' — the heading flattened to uniform level 2,
     regardless of the original `*' / `**' / `***' depth.

Heading lines WITHOUT an inline 〔/seg〕 (e.g. `* Document Info',
`* Text', `* NOTES') are left alone — they are structural, not
Tibetan section titles."
  (replace-regexp-in-string
   "^\\*+ \\(.*?\\)〔/seg〕[[:space:]]*$"
   "〔/seg〕\n** \\1"
   text))

(defun tibetan-migrate--hoist-metadata-from-body (body)
  "Split BODY into hoisted metadata and remaining narrative.

Walks BODY line by line and returns a cons cell (METAS . REST):
  METAS — a list of `#+KEYWORD: value' lines encountered (in order).
  REST  — BODY with those lines removed, trailing blank lines
          collapsed, then trimmed.

Used by the bare-seg migrator so any `#+KEYWORD:' lines that the
original pipeline accidentally embedded in a segment body (typically
seg:1 containing the document's `#+TITLE' etc.) can be promoted to
the document header and the segment body can be evaluated on what
remains."
  (let ((metas '())
        (rest '()))
    (dolist (line (split-string body "\n"))
      (if (string-match tibetan-migrate--keyword-line-regex line)
          (push line metas)
        (push line rest)))
    (cons (nreverse metas)
          (string-trim
           (mapconcat #'identity (nreverse rest) "\n")))))

(defun tibetan-migrate--convert-bare-seg-blocks (text)
  "Step 2 of the bare-seg migration.

Scan TEXT for `〔seg:N〕 … 〔/seg〕' blocks, hoist any `#+KEYWORD:'
lines from their bodies, and emit `*** Segment M' headings for the
non-empty survivors (M counts from 1 in the order encountered).

Returns a cons cell (METAS . OUT) where:
  METAS — hoisted `#+KEYWORD:' lines across all segments, in order.
  OUT   — TEXT with every seg-block replaced; original `N' values
          are discarded and replaced with the fresh sequence.

A segment whose body becomes empty after metadata hoisting is
dropped entirely — it does NOT get a `*** Segment M' heading."
  (let ((out "")
        (pos 0)
        (m 0)
        (metas '()))
    (while (string-match tibetan-migrate--bare-seg-regex text pos)
      (let* ((mstart (match-beginning 0))
             (mend   (match-end 0))
             (body   (match-string 2 text))
             (split  (tibetan-migrate--hoist-metadata-from-body body))
             (segment-metas (car split))
             (segment-body  (cdr split)))
        (setq metas (append metas segment-metas))
        (setq out (concat out (substring text pos mstart)))
        (unless (string-empty-p segment-body)
          (setq m (1+ m))
          (setq out
                (concat out
                        (format "*** Segment %d\n%s\n" m segment-body))))
        (setq pos mend)))
    (setq out (concat out (substring text pos)))
    (cons metas out)))

(defun tibetan-migrate--collapse-excess-blank-lines (text)
  "Collapse runs of 3+ blank lines in TEXT down to 2.
Keeps the output tidy after the heading-splitting pass has inserted
`〔/seg〕' lines that later disappear, and after segments are removed."
  (replace-regexp-in-string "\n\n\n+" "\n\n" text))

(defun tibetan-migrate--convert-bare-string (text)
  "Return TEXT migrated from the bare-seg layout to `*** Segment M'.

Pipeline:
  1. Split + flatten Tibetan-title heading lines.
  2. Convert `〔seg:N〕 … 〔/seg〕' blocks to `*** Segment M' headings,
     hoisting `#+KEYWORD:' metadata lines out of segment bodies.
  3. Prepend the hoisted metadata block above the first heading line.
  4. Collapse excess blank-line runs.

The transformation is idempotent: a TEXT already in the target
shape contains no `〔' characters, so every helper short-circuits."
  (let* ((step1 (tibetan-migrate--split-and-flatten-title-headings text))
         (step2 (tibetan-migrate--convert-bare-seg-blocks step1))
         (metas (car step2))
         (body  (cdr step2))
         (header (if metas
                     (concat (mapconcat #'identity metas "\n") "\n")
                   "")))
    ;; Insert hoisted metadata above the first heading, preserving any
    ;; original `#+KEYWORD:' lines that already lived at the top.
    (let* ((combined (concat header body))
           ;; If hoisting produced duplicate keywords (e.g. the source
           ;; already had `#+TITLE' at the top AND seg:1 had another
           ;; `#+TITLE' inside it), we leave both — the user will see
           ;; the duplication on review.  Collapsing duplicates requires
           ;; value-aware merging that would risk silently losing work.
           (tidy (tibetan-migrate--collapse-excess-blank-lines combined)))
      tidy)))

;;;###autoload
(defun tibetan-migrate-bare-segments-to-headings ()
  "Convert `〔seg:N〕 … 〔/seg〕' markers in the current buffer to
`*** Segment M' headings, flatten Tibetan-title heading lines to
`** Section', and hoist `#+KEYWORD:' metadata to the document header.

Use this for documents prepared with the bare-seg pipeline (no
`〔trans:N〕' pairs), typically identified by inline `〔/seg〕' markers
at the end of Tibetan-title heading lines.  See also
`tibetan-migrate-inline-segments-to-headings' for the paired variant.

Idempotent: a buffer without any `〔' markers is left unchanged."
  (interactive)
  (let ((new (tibetan-migrate--convert-bare-string (buffer-string))))
    (unless (string= new (buffer-string))
      (let ((p (point)))
        (erase-buffer)
        (insert new)
        (goto-char (min p (point-max)))))))

(provide 'tibetan-segment-migrate)
;;; tibetan-segment-migrate.el ends here
