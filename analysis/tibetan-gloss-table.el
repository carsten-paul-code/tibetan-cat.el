;;; tibetan-gloss-table.el --- Three-row gloss tables for analysis files -*- lexical-binding: t -*-

;;; Commentary:
;; 2026-09-15 (Carsten's §184-handout request):  the analysis file
;; gains a `** Gloss Table' section — per shad unit one real org
;; table with three rows:
;;
;;     | rang lugs      | su   | khas len  | ... |   ← Wylie (+clitic)
;;     | eigenes System | als  | behaupten | ... |   ← gloss
;;     | N              | TERM | V         | ... |   ← grammar label
;;
;; The data stream is `tibetan-reading--unit-tokens' (the same
;; token plists that drive the cascade Reading layer), so the table
;; and the flowing Interlinear line can never drift apart.
;;
;; This file holds the pure pieces:  the row-3 LABEL RESOLVER
;; (this commit) and the org-table renderer (next commit).  Label
;; precedence — native signals first, Claude POS second, `?' last:
;;
;;   1. particle        → its Bialek short label (ERG GEN TERM …,
;;                        CONV:* converbs), clitic labels appended
;;                        with a dot (bya ba'i → NMLZ.GEN shape)
;;   2. bare nominaliser after a verb → NMLZ
;;   3. verb            → V;  V.HON when the Hill gloss carries
;;                        "(hon.)"
;;   4. Claude Vocabulary POS field (EXACT key only — the M2
;;                        `mar'/`mar pas' lesson) → PN / PRON / N /
;;                        ADJ / ADV / CONJ / NUM / V, `.HON'
;;                        appended when the field says honorific
;;   5. fallback        → "?"

;;; Code:

(require 'cl-lib)
;; Nominaliser inventory — single source of truth lives with the
;; clause segmenter (DRY; the two must agree on what nominalises).
(require 'tibetan-clause-segmenter)
;; Token stream + gloss selection — the cascade Reading machinery
;; (dependency-light; every heavy lookup behind fboundp guards).
(require 'tibetan-reading)

(defun tibetan-gloss-table--claude-pos (wylie vocab-alist)
  "Claude's part-of-speech field for WYLIE from VOCAB-ALIST, or nil.
VOCAB-ALIST is the parsed Claude Vocabulary alist — (WYLIE-KEY .
FULL-LINE) pairs with lines shaped

    wylie-key, part-of-speech, \"gloss\", commentary

EXACT key match only (a bare token must not inherit an unrelated
MWU entry's classification — M2).  Returns the downcased text
between the key's first comma and the quoted gloss, trimmed; nil
when there is no entry or no POS field."
  (when (and wylie vocab-alist (listp vocab-alist))
    (let ((hit (assoc wylie vocab-alist)))
      (when hit
        (let ((line (cdr hit)))
          ;; The POS field lives between the first comma and the
          ;; opening quote — a comma INSIDE the gloss (\"I, me\")
          ;; can therefore never leak in (the §5.33-D2 pattern).
          (when (and (stringp line)
                     (string-match "," line)
                     (string-match-p "\"" line))
            (let* ((comma (string-match "," line))
                   (quote-pos (string-match "\"" line))
                   (field (and (< comma quote-pos)
                               (string-trim
                                (substring line (1+ comma) quote-pos)
                                "[ \t,]+" "[ \t,]+"))))
              (when (and field (not (string-empty-p field)))
                (downcase field)))))))))

(defun tibetan-gloss-table--pos-label (pos)
  "Map a Claude POS string to a table label, or nil when unmapped.
PN for proper nouns, PRON before the noun check (\"pronoun\"
contains \"noun\"), then N / ADJ / ADV / CONJ / NUM / V.  `.HON'
is appended when POS mentions an honorific."
  (when (stringp pos)
    (let* ((p (downcase pos))
           (base (cond ((string-match-p "proper" p)        "PN")
                       ((string-match-p "pronoun" p)       "PRON")
                       ((string-match-p "noun" p)          "N")
                       ((string-match-p "adjective" p)     "ADJ")
                       ((string-match-p "adverb" p)        "ADV")
                       ((string-match-p "conjunction" p)   "CONJ")
                       ((string-match-p "numeral\\|number" p) "NUM")
                       ((string-match-p "verb" p)          "V"))))
      (when base
        (if (string-match-p "hon" p)
            (concat base ".HON")
          base)))))

(defun tibetan-gloss-table--token-label (tok &optional vocab-alist)
  "The row-3 grammar label for token plist TOK.
TOK is a `tibetan-reading--unit-tokens' plist (:tibetan :wylie
:kind :label :meaning :prev-verb-p :curated-p :clitic).
VOCAB-ALIST is the parsed Claude Vocabulary for the Claude-POS
tier.  Precedence: native particle label → NMLZ (bare nominaliser
after a verb) → V/V.HON (Hill) → Claude POS mapping → \"?\".
A trailing clitic's label is dot-appended (NMLZ.GEN, N.GEN)."
  (let* ((kind (plist-get tok :kind))
         (clitic (plist-get tok :clitic))
         (base
          (cond
           ;; 1. Native particle label, verbatim (ERG / GEN / …,
           ;;    CONV:* converbs).
           ((eq kind 'particle) (plist-get tok :label))
           ;; 2. Bare nominaliser directly after a verb.  The raw
           ;;    :tibetan covers both the bare forms (པ/བ) and the
           ;;    case-merged ones (པའི …) — the segmenter's suffix
           ;;    inventory lists both spellings.
           ((and (eq kind 'word)
                 (plist-get tok :prev-verb-p)
                 (member (plist-get tok :tibetan)
                         tibetan-clause-seg--nominaliser-suffixes))
            "NMLZ")
           ;; 3. Verb: V, honorific per the Hill gloss.
           ((eq kind 'verb)
            (if (string-match-p "(hon\\.?)"
                                (or (plist-get tok :meaning) ""))
                "V.HON"
              "V"))
           ;; 4. Claude POS tier (exact key).
           (t (tibetan-gloss-table--pos-label
               (tibetan-gloss-table--claude-pos
                (plist-get tok :wylie) vocab-alist)))))
         (label (or base "?")))
    ;; A merged clitic keeps its case visible: NMLZ.GEN / N.GEN —
    ;; unless the clitic label is already the label itself (a
    ;; particle token never carries a clitic by construction).
    (if (and clitic (cdr clitic) (not (eq kind 'particle)))
        (concat label "." (cdr clitic))
      label)))

;; ----------------------------------------------------------------------------
;; org-table renderer (pure)
;; ----------------------------------------------------------------------------

(defun tibetan-gloss-table--cell (s)
  "S as a safe org-table cell: whitespace collapsed, `|' escaped
as the org entity `\\vert' (a literal bar would split the cell)."
  (let* ((flat (replace-regexp-in-string "[ \t\n]+" " " (or s "")))
         (safe (replace-regexp-in-string "|" "\\\\vert" flat)))
    (string-trim safe)))

(defun tibetan-gloss-table--unit-rows (unit-text &optional vocab-alist)
  "Three cell-string lists (Wylie / gloss / label) for UNIT-TEXT.
One column per `tibetan-reading--unit-tokens' token: row 1 the
plain Wylie with a merged clitic re-attached (rje'i), row 2 the
`tibetan-reading--gloss' display gloss (particle cells stay
empty — their information is the row-3 label), row 3 the
`tibetan-gloss-table--token-label' grammar label.  nil when the
unit yields no tokens."
  (let ((toks (tibetan-reading--unit-tokens unit-text)))
    (when toks
      (let (r1 r2 r3)
        (dolist (tok toks)
          (let ((particle-p (eq (plist-get tok :kind) 'particle))
                (clitic (plist-get tok :clitic)))
            (push (tibetan-gloss-table--cell
                   (concat (plist-get tok :wylie) (car clitic)))
                  r1)
            (push (tibetan-gloss-table--cell
                   (if particle-p "" (tibetan-reading--gloss tok)))
                  r2)
            (push (tibetan-gloss-table--cell
                   (tibetan-gloss-table--token-label tok vocab-alist))
                  r3)))
        (list (nreverse r1) (nreverse r2) (nreverse r3))))))

(defun tibetan-gloss-table--format-rows (rows)
  "ROWS (three equal-length cell lists) as one aligned org table.
Column width = the widest cell of the three rows, space-padded,
so the table reads aligned in the raw buffer too (the §184
handout alignment request)."
  (let* ((ncols (length (car rows)))
         (widths
          (cl-loop for i below ncols
                   collect (cl-loop for row in rows
                                    maximize (string-width
                                              (or (nth i row) ""))))))
    (mapconcat
     (lambda (row)
       (concat
        "| "
        (mapconcat
         #'identity
         (cl-loop for cell in row
                  for w in widths
                  collect (concat cell
                                  (make-string
                                   (- w (string-width cell)) ?\s)))
         " | ")
        " |"))
     rows "\n")))

(defun tibetan-gloss-table-render (units &optional vocab-alist)
  "One aligned three-row org table per shad unit in UNITS.
UNITS is an ordered list of shad-unit strings (shads kept, the
`tibetan-cascade-split-shad-units' contract).  Tables are joined
by a blank line; units without tokens are skipped; nil when
nothing renders.  VOCAB-ALIST feeds the Claude-POS label tier."
  (let ((tables
         (delq nil
               (mapcar (lambda (u)
                         (let ((rows (tibetan-gloss-table--unit-rows
                                      u vocab-alist)))
                           (and rows
                                (tibetan-gloss-table--format-rows rows))))
                       units))))
    (when tables
      (string-join tables "\n\n"))))

(provide 'tibetan-gloss-table)

;;; tibetan-gloss-table.el ends here
