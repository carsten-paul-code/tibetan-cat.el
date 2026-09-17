;;; tibetan-gloss-table-test.el --- Tests for the gloss-table module -*- lexical-binding: t -*-

;;; Commentary:
;; 2026-09-15:  §184-handout-style three-row gloss tables.  This
;; file covers the pure label resolver (native tier → Claude-POS
;; tier → "?") and, from the next commit on, the org-table
;; renderer.  Pure tests: token plists are hand-built, the Claude
;; vocabulary alist is passed in directly — no dictionaries, no
;; disk, no network.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-gloss-table)

;; ----------------------------------------------------------------------------
;; Claude POS extraction (exact key, field between comma and quote)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-gloss-table-claude-pos-extracts-field ()
  "POS = the downcased, trimmed text between the key's first comma
and the quoted gloss of the EXACT-key vocabulary line."
  (should (equal "noun (honorific)"
                 (tibetan-gloss-table--claude-pos
                  "bzhed pa"
                  '(("bzhed pa" . "bzhed pa, Noun (honorific), \"Auffassung\", hon. für 'dod pa"))))))

(ert-deftest tibetan-gloss-table-claude-pos-exact-key-only ()
  "A bare token must NOT inherit an MWU entry's POS (M2's
`mar'/`mar pas' lesson): prefix matches return nil."
  (should-not (tibetan-gloss-table--claude-pos
               "mar"
               '(("mar pas" . "mar pas, proper noun, \"Mar pa (ERG)\", the translator")))))

(ert-deftest tibetan-gloss-table-claude-pos-nil-cases ()
  "No alist, no entry, or a line without a quoted gloss → nil."
  (should-not (tibetan-gloss-table--claude-pos "kha" nil))
  (should-not (tibetan-gloss-table--claude-pos
               "kha" '(("zhal" . "zhal, noun, \"mouth (hon.)\", x"))))
  (should-not (tibetan-gloss-table--claude-pos
               "kha" '(("kha" . "kha malformed line without quotes")))))

;; ----------------------------------------------------------------------------
;; POS → label mapping
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-gloss-table-pos-label-mapping ()
  "The handout label inventory: PN / PRON / N / ADJ / ADV / CONJ /
NUM / V, with `proper' and `pronoun' checked BEFORE the bare
`noun' substring."
  (should (equal "PN"   (tibetan-gloss-table--pos-label "proper noun")))
  (should (equal "PRON" (tibetan-gloss-table--pos-label "pronoun")))
  (should (equal "N"    (tibetan-gloss-table--pos-label "noun")))
  (should (equal "ADJ"  (tibetan-gloss-table--pos-label "adjective")))
  (should (equal "ADV"  (tibetan-gloss-table--pos-label "adverb")))
  (should (equal "CONJ" (tibetan-gloss-table--pos-label "conjunction")))
  (should (equal "NUM"  (tibetan-gloss-table--pos-label "numeral")))
  (should (equal "V"    (tibetan-gloss-table--pos-label "verb")))
  (should-not (tibetan-gloss-table--pos-label "interjection"))
  (should-not (tibetan-gloss-table--pos-label nil)))

(ert-deftest tibetan-gloss-table-pos-label-honorific-suffix ()
  "An honorific mention in the POS field dot-appends `.HON' —
`bzhed pa' renders N.HON in the §184 handout."
  (should (equal "N.HON" (tibetan-gloss-table--pos-label "noun (honorific)")))
  (should (equal "V.HON" (tibetan-gloss-table--pos-label "honorific verb"))))

;; ----------------------------------------------------------------------------
;; Token label resolver — native tier
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-gloss-table-token-label-particle-native ()
  "A particle token carries its Bialek short label verbatim —
case labels and CONV:* converbs alike."
  (should (equal "GEN"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "གི" :wylie "gi" :kind particle :label "GEN"))))
  (should (equal "CONV:nas"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "ནས" :wylie "nas" :kind particle
                    :label "CONV:nas" :prev-verb-p t)))))

(ert-deftest tibetan-gloss-table-token-label-nominaliser-after-verb ()
  "A bare nominaliser directly after a verb labels NMLZ (the
handout's `bya ba' tier); the same token elsewhere does NOT."
  (should (equal "NMLZ"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "པ" :wylie "pa" :kind word :prev-verb-p t))))
  (should (equal "?"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "པ" :wylie "pa" :kind word :prev-verb-p nil)))))

(ert-deftest tibetan-gloss-table-token-label-verb-and-honorific ()
  "Verb tokens label V; a Hill gloss carrying \"(hon.)\" labels
V.HON (mdzad in the handout)."
  (should (equal "V"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "བྱས" :wylie "byas" :kind verb
                    :meaning "to do, to act"))))
  (should (equal "V.HON"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "མཛད" :wylie "mdzad" :kind verb
                    :meaning "to do, to act (hon.)")))))

;; ----------------------------------------------------------------------------
;; Token label resolver — Claude tier + fallback + clitics
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-gloss-table-token-label-claude-pos-tier ()
  "A plain word with a Claude Vocabulary entry takes the mapped
Claude POS label (exact key)."
  (should (equal "ADV"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "མཐར་ཐུག" :wylie "mthar thug" :kind word)
                  '(("mthar thug" . "mthar thug, adverb, \"letztgültig\", x"))))))

(ert-deftest tibetan-gloss-table-token-label-native-beats-claude ()
  "Native signals outrank Claude POS: a verb token stays V even
when the Claude entry classifies it a noun."
  (should (equal "V"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "ལེན" :wylie "len" :kind verb :meaning "to take")
                  '(("len" . "len, noun, \"taking\", nominal use"))))))

(ert-deftest tibetan-gloss-table-token-label-fallback ()
  "No native signal, no Claude entry → \"?\" (never nil, never
empty — the table column must stay visible)."
  (should (equal "?"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "ཟོག" :wylie "zog" :kind word))))
  (should (equal "?"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "ཟོག" :wylie "zog" :kind word)
                  '(("gzhan" . "gzhan, noun, \"other\", x"))))))

(ert-deftest tibetan-gloss-table-token-label-clitic-appended ()
  "A trailing clitic's label is dot-appended: bya-ba'i → NMLZ.GEN,
a Claude-classified noun with 'i → N.GEN."
  (should (equal "NMLZ.GEN"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "པའི" :wylie "pa" :kind word :prev-verb-p t
                    :clitic ("'i" . "GEN")))))
  (should (equal "N.GEN"
                 (tibetan-gloss-table--token-label
                  '(:tibetan "རྗེའི" :wylie "rje" :kind word
                    :clitic ("'i" . "GEN"))
                  '(("rje" . "rje, noun, \"lord\", x"))))))

;; ----------------------------------------------------------------------------
;; org-table renderer
;; ----------------------------------------------------------------------------

(defconst tibetan-gloss-table-test--toks-a
  '((:tibetan "རྗེ" :wylie "rje" :kind word :meaning "Ehrwürdiger")
    (:tibetan "ཡི" :wylie "yi" :kind particle :label "GEN"
      :meaning "GENITIVE")
    (:tibetan "མཛད" :wylie "mdzad" :kind verb
      :meaning "to do, to act (hon.)"))
  "Canned token stream: word + particle + honorific verb.")

(defconst tibetan-gloss-table-test--toks-b
  '((:tibetan "པའི" :wylie "pa" :kind word :prev-verb-p t
      :clitic ("'i" . "GEN") :meaning nil))
  "Canned token stream: nominaliser with merged genitive clitic.")

(defmacro tibetan-gloss-table-test--with-tokens (streams &rest body)
  "Stub the reading-layer feeders: `tibetan-reading--unit-tokens'
pops one canned stream from STREAMS per call (an alist of
UNIT-TEXT → token list), `tibetan-reading--gloss' returns the
token's :meaning verbatim.  Keeps the renderer tests pure — no
dictionaries, no Wylie converter."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'tibetan-reading--unit-tokens)
              (lambda (unit) (cdr (assoc unit ,streams))))
             ((symbol-function 'tibetan-reading--gloss)
              (lambda (tok) (plist-get tok :meaning))))
     ,@body))

(ert-deftest tibetan-gloss-table-render-three-aligned-rows ()
  "One unit renders ONE org table: exactly three `|'-rows, one
column per token, all rows the same width (aligned — the §184
handout request) and the same column count."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a))
    (let ((out (tibetan-gloss-table-render '("U1"))))
      (should out)
      (let ((lines (split-string out "\n")))
        (should (= 3 (length lines)))
        (dolist (l lines)
          (should (string-prefix-p "| " l))
          (should (string-suffix-p " |" l))
          ;; 3 columns → 4 pipes.
          (should (= 4 (cl-count ?| l))))
        ;; Aligned: identical rendered width for all three rows.
        (should (= 1 (length (delete-dups
                              (mapcar #'string-width lines)))))))))

(ert-deftest tibetan-gloss-table-render-row-contents ()
  "Row 1 = plain Wylie, row 2 = display gloss with EMPTY particle
cells, row 3 = grammar labels."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a))
    (let* ((out (tibetan-gloss-table-render '("U1")))
           (lines (split-string out "\n"))
           (cells (mapcar (lambda (l)
                            (mapcar #'string-trim
                                    (butlast (cdr (split-string l "|")))))
                          lines)))
      (should (equal '("rje" "yi" "mdzad") (nth 0 cells)))
      ;; Particle gloss cell EMPTY (its information is the label).
      (should (equal '("Ehrwürdiger" "" "to do, to act (hon.)")
                     (nth 1 cells)))
      (should (equal '("?" "GEN" "V.HON") (nth 2 cells))))))

(ert-deftest tibetan-gloss-table-render-clitic-and-no-markup ()
  "A merged clitic re-attaches in the Wylie row (pa'i) and no
cell carries emphasis/link markup."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-b))
    (let ((out (tibetan-gloss-table-render '("U1"))))
      (should (string-match-p "| pa'i *|" out))
      (should (string-match-p "| NMLZ\\.GEN *|" out))
      (dolist (bad '("=" "~" "!" "\\[\\["))
        (should-not (string-match-p bad out))))))

(ert-deftest tibetan-gloss-table-cell-strips-literal-escape-sequences ()
  "A gloss carrying LITERAL backslash-escape sequences (\\n, \\t —
serialization junk from upstream vocabulary strings) renders
without them: `contemplate\\n' must not put a backslash-n into
the org cell (SS15 review, par-015 Segment 154)."
  (tibetan-gloss-table-test--with-tokens
      '(("U1" . ((:tibetan "བསམ" :wylie "bsam" :kind word
                  :meaning "think; contemplate\\n"))))
    (let ((out (tibetan-gloss-table-render '("U1"))))
      (should (string-match-p "contemplate" out))
      (should-not (string-match-p "\\\\n" out)))))

(ert-deftest tibetan-gloss-table-cell-gloss-capped-with-ellipsis ()
  "Row-2 gloss cells are capped at
`tibetan-gloss-table-cell-gloss-width' and marked with a trailing
`…' — the table is the at-a-glance form; the full gloss stays in
Claude Vocabulary / Interlinear (SS15 review, 2026-09-17).  Cut
prefers a word boundary; dangling punctuation before the `…' is
stripped.  Rows 1 and 3 are untouched."
  (tibetan-gloss-table-test--with-tokens
      '(("U1" . ((:tibetan "འདས" :wylie "'das" :kind word
                  :meaning "pf. of 'da'; to die (DE: Pf. von 'da'; sterben)"))))
    (let* ((tibetan-gloss-table-cell-gloss-width 25)
           (out (tibetan-gloss-table-render '("U1")))
           (lines (split-string out "\n"))
           (gloss (string-trim
                   (car (butlast (cdr (split-string (nth 1 lines) "|")))))))
      ;; Budget + ellipsis, no dangling `(DE:' fragment.
      (should (<= (length gloss) 26))
      (should (string-suffix-p "…" gloss))
      (should-not (string-match-p "(DE:…" gloss))
      ;; Row 1 keeps the full Wylie.
      (should (string-match-p "'das" (nth 0 lines))))))

(ert-deftest tibetan-gloss-table-cell-gloss-short-untouched ()
  "A gloss within the cell budget renders verbatim — no ellipsis,
no cut."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a))
    (let* ((tibetan-gloss-table-cell-gloss-width 25)
           (out (tibetan-gloss-table-render '("U1"))))
      (should (string-match-p "| Ehrwürdiger " out))
      (should-not (string-match-p "…" out)))))

(ert-deftest tibetan-gloss-table-render-escapes-pipe ()
  "A `|' inside a gloss must not split the cell — escaped as the
org \\vert entity, keeping every row at the unit's column count."
  (tibetan-gloss-table-test--with-tokens
      '(("U1" . ((:tibetan "ཚེ" :wylie "tshe" :kind word
                  :meaning "life | lifespan"))))
    (let ((out (tibetan-gloss-table-render '("U1"))))
      (should (string-match-p "\\\\vert" out))
      (dolist (l (split-string out "\n"))
        (should (= 2 (cl-count ?| l)))))))

(ert-deftest tibetan-gloss-table-render-two-units-two-tables ()
  "Two shad units render two SEPARATE tables, blank-line joined;
a tokenless unit is skipped."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a)
        ("U2" . nil)
        ("U3" . ,tibetan-gloss-table-test--toks-b))
    (let ((out (tibetan-gloss-table-render '("U1" "U2" "U3"))))
      (should (string-match-p "\n\n" out))
      (should (= 6 (length (seq-filter
                            (lambda (l) (string-prefix-p "|" l))
                            (split-string out "\n"))))))))

(ert-deftest tibetan-gloss-table-render-nothing-renders-nil ()
  "All units tokenless → nil (the emitter then skips the section
body entirely)."
  (tibetan-gloss-table-test--with-tokens '(("U1" . nil))
    (should-not (tibetan-gloss-table-render '("U1")))
    (should-not (tibetan-gloss-table-render nil))))

;; ----------------------------------------------------------------------------
;; Width wrap (2026-09-16 — §185 review: 30-column tables wrap
;; unreadably.  2026-09-17 — §15 review: the stacked blocks with
;; PRIVATE column widths fragmented the segment; a wide unit now
;; wraps into hline-separated bands of ONE org table that share a
;; single column grid.)
;; ----------------------------------------------------------------------------

(defconst tibetan-gloss-table-test--toks-wide
  '((:tibetan "ཀ" :wylie "kha-chig" :kind word
     :meaning "erstes Wort mit langer Glosse")
    (:tibetan "ཁ" :wylie "kha-gnyis" :kind word
     :meaning "zweites Wort mit langer Glosse")
    (:tibetan "ག" :wylie "kha-gsum" :kind word
     :meaning "drittes Wort mit langer Glosse")
    (:tibetan "ང" :wylie "kha-bzhi" :kind word
     :meaning "viertes Wort mit langer Glosse"))
  "Canned token stream: four words whose glosses overflow a
70-column budget together.")

(defun tibetan-gloss-table-test--pipe-positions (line)
  "The column positions of every `|' in LINE."
  (cl-loop for ch across line
           for i from 0
           when (eq ch ?|) collect i))

(ert-deftest tibetan-gloss-table-wraps-wide-unit-into-banded-table ()
  "A unit wider than `tibetan-gloss-table-max-width' renders as
ONE org table: 3-row bands separated by hline rows (no blank line
inside the unit), every line within budget, all tokens present in
order."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-wide))
    (let* ((tibetan-gloss-table-max-width 70)
           (tibetan-gloss-table-cell-gloss-width 25)
           (out (tibetan-gloss-table-render '("U1")))
           (lines (split-string out "\n"))
           (hlines (seq-filter (lambda (l) (string-match-p "^|-" l)) lines))
           (cell-lines (seq-filter (lambda (l) (string-prefix-p "| " l))
                                   lines)))
      ;; One table: bands are hline-joined, never blank-line-joined.
      (should-not (string-match-p "\n\n" out))
      (should (>= (length hlines) 1))
      (should (= 0 (mod (length cell-lines) 3)))
      (should (= (length hlines) (1- (/ (length cell-lines) 3))))
      ;; Budget: keine Zeile breiter als max-width.
      (dolist (l lines)
        (should (<= (string-width l) 70)))
      ;; Alle Tokens, in Reihenfolge (Zeile 1 der Bänder konkateniert).
      (let ((row1 (mapconcat #'identity
                             (cl-loop for i from 0 below (length cell-lines)
                                      when (= 0 (mod i 3))
                                      collect (nth i cell-lines))
                             " ")))
        (should (string-match-p
                 "kha-chig.*kha-gnyis.*kha-gsum.*kha-bzhi" row1))))))

(ert-deftest tibetan-gloss-table-bands-share-one-column-grid ()
  "The SS15 complaint, locked: every row of a wrapped table —
cell rows AND hlines, across all bands — carries its pipes at
IDENTICAL column positions, so the whole segment reads as one
aligned grid."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-wide))
    (let* ((tibetan-gloss-table-max-width 70)
           (tibetan-gloss-table-cell-gloss-width 25)
           (out (tibetan-gloss-table-render '("U1")))
           (lines (split-string out "\n"))
           (positions
            (delete-dups
             (mapcar (lambda (l)
                       (mapcar (lambda (p) p)
                               (tibetan-gloss-table-test--pipe-positions
                                (replace-regexp-in-string "\\+" "|" l))))
                     lines))))
      (should (= 1 (length positions))))))

(ert-deftest tibetan-gloss-table-last-band-padded-with-empty-cells ()
  "A band count that doesn't divide the token count pads the last
band with EMPTY cells — every row keeps the full pipe count (org
aligns the table as one grid)."
  (tibetan-gloss-table-test--with-tokens
      '(("U1" . ((:tibetan "ཀ" :wylie "aaaa" :kind word :meaning "eins zwei drei")
                 (:tibetan "ཁ" :wylie "bbbb" :kind word :meaning "vier fünf sechs")
                 (:tibetan "ག" :wylie "cccc" :kind word :meaning "sieben acht"))))
    (let* ((tibetan-gloss-table-max-width 46)
           (out (tibetan-gloss-table-render '("U1")))
           (lines (split-string out "\n"))
           (counts (delete-dups
                    (mapcar (lambda (l)
                              (+ (cl-count ?| l) (cl-count ?+ l)))
                            lines))))
      ;; 3 tokens, 2 per band → 2 bands, last padded: uniform pipe count.
      (should (string-match-p "^|-" out))
      (should (= 1 (length counts))))))

(ert-deftest tibetan-gloss-table-wrap-keeps-narrow-tables-whole ()
  "A unit within budget renders as ONE 3-row block without any
hline — byte-identical to the pre-wrap output."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a))
    (let* ((tibetan-gloss-table-max-width 100)
           (out (tibetan-gloss-table-render '("U1"))))
      (should (= 3 (length (split-string out "\n"))))
      (should-not (string-match-p "^|-" out)))))

(ert-deftest tibetan-gloss-table-wrap-single-column-may-overflow ()
  "A single over-wide column still renders (one column per band
minimum) — never an infinite loop, never a dropped token."
  (tibetan-gloss-table-test--with-tokens
      '(("U1" . ((:tibetan "ཀ" :wylie "kha" :kind word
                  :meaning "eine absurd lange Glosse die jedes Budget sprengt"))))
    (let* ((tibetan-gloss-table-max-width 20)
           (tibetan-gloss-table-cell-gloss-width 80)
           (out (tibetan-gloss-table-render '("U1"))))
      (should (string-match-p "absurd lange Glosse" out)))))

;; ----------------------------------------------------------------------------
;; Captioned renderer (cascade Reading layer, 2026-09-15)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-gloss-table-render-captioned-captions-per-unit ()
  "Cascade shape ((GLOBAL-NUM . TEXT)…): each unit's table is
preceded by a plain `Unit K — Segment N' caption line (matching
the ⟦N⟧ rendering keys), blocks blank-line separated."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a)
        ("U2" . ,tibetan-gloss-table-test--toks-b))
    (let ((out (tibetan-gloss-table-render-captioned
                '((105 . "U1") (106 . "U2")))))
      (should out)
      (should (string-match-p "^Unit 1 — Segment 105$" out))
      (should (string-match-p "^Unit 2 — Segment 106$" out))
      ;; Caption directly above its table.
      (should (string-match-p "^Unit 1 — Segment 105\n| " out))
      (should (string-match-p "^Unit 2 — Segment 106\n| " out))
      ;; No headings — plain lines only (§5.51 collision lesson).
      (should-not (string-match-p "^\\*" out)))))

(ert-deftest tibetan-gloss-table-render-captioned-skips-tokenless ()
  "A token-less unit drops caption AND table together; the ordinal
keeps counting the RENDERED units, the segment number stays the
global key."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a)
        ("U2" . nil)
        ("U3" . ,tibetan-gloss-table-test--toks-b))
    (let ((out (tibetan-gloss-table-render-captioned
                '((105 . "U1") (106 . "U2") (107 . "U3")))))
      (should (string-match-p "Segment 105$" out))
      (should-not (string-match-p "Segment 106" out))
      (should (string-match-p "Segment 107$" out))))
  ;; All units token-less → nil (the emitter then omits the section).
  (tibetan-gloss-table-test--with-tokens '(("U1" . nil))
    (should-not (tibetan-gloss-table-render-captioned '((105 . "U1"))))))

(ert-deftest tibetan-gloss-table-render-captioned-heading-level ()
  "With HEADING-LEVEL, captions become org headings `*** Segment N'
(the handout form — foldable per segment); the plain `Unit K —'
prefix disappears."
  (tibetan-gloss-table-test--with-tokens
      `(("U1" . ,tibetan-gloss-table-test--toks-a)
        ("U2" . ,tibetan-gloss-table-test--toks-b))
    (let ((out (tibetan-gloss-table-render-captioned
                '((1718 . "U1") (1719 . "U2")) nil 3)))
      (should (string-match-p "^\\*\\*\\* Segment 1718$" out))
      (should (string-match-p "^\\*\\*\\* Segment 1719$" out))
      (should (string-match-p "^\\*\\*\\* Segment 1718\n| " out))
      (should-not (string-match-p "^Unit [0-9]" out)))))

(ert-deftest tibetan-gloss-table-render-captioned-forwards-vocab ()
  "The vocab-alist reaches the per-token label resolver (Claude-POS
tier) unchanged."
  (let (seen)
    (cl-letf (((symbol-function 'tibetan-reading--unit-tokens)
               (lambda (_u) (list '(:tibetan "ཁ" :wylie "kha" :kind word))))
              ((symbol-function 'tibetan-reading--gloss)
               (lambda (_tok) nil))
              ((symbol-function 'tibetan-gloss-table--token-label)
               (lambda (_tok vocab) (setq seen vocab) "N")))
      (tibetan-gloss-table-render-captioned
       '((105 . "U1")) '(("kha" . "kha, noun, \"mouth\", x")))
      (should (equal '(("kha" . "kha, noun, \"mouth\", x")) seen)))))

(provide 'tibetan-gloss-table-test)

;;; tibetan-gloss-table-test.el ends here
