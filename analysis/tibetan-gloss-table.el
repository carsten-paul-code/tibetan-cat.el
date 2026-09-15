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

(provide 'tibetan-gloss-table)

;;; tibetan-gloss-table.el ends here
