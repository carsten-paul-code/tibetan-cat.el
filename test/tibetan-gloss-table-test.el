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

(provide 'tibetan-gloss-table-test)

;;; tibetan-gloss-table-test.el ends here
