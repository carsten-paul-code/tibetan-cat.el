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
