;;; tibetan-interlinear-test.el --- Tests for tibetan-interlinear.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for the interlinear gloss and particle overview module.
;; Tests cover:
;;   1. Word/particle splitting
;;   2. Portfolio parser
;;   3. Interlinear gloss generation
;;   4. Particle Overview generation

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-interlinear)

;; ============================================================================
;; WORD/PARTICLE SPLITTING
;; ============================================================================

(ert-deftest tibetan-interlinear-split-concessive ()
  "Split verb+kyang into stem and concessive particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "སྐྱེས་གྱུར་ཀྱང" "CONCESSIVE PARTICLE")))
    (should (equal (car result) "སྐྱེས་གྱུར"))
    (should (equal (cadr result) "ཀྱང"))
    (should (equal (cddr result) "CONC"))))

(ert-deftest tibetan-interlinear-split-genitive ()
  "Split noun+kyi into stem and genitive particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "བློ་རྒོད་ཀྱི" "GENITIVE (GEN)")))
    (should (equal (car result) "བློ་རྒོད"))
    (should (equal (cadr result) "ཀྱི"))
    (should (equal (cddr result) "GEN"))))

(ert-deftest tibetan-interlinear-split-ergative ()
  "Split noun+kyis into stem and ergative particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "རྡོས་ཀྱིས" "ERGATIVE/INSTRUMENTAL (ERG/INST)")))
    (should (equal (car result) "རྡོས"))
    (should (equal (cadr result) "ཀྱིས"))
    (should (equal (cddr result) "ERG"))))

(ert-deftest tibetan-interlinear-split-ablative-converb ()
  "Split verb+nas into stem and ablative converb particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "ཤེས་ནས" "CONVERBIAL: ABLATIVE CONVERB")))
    (should (equal (car result) "ཤེས"))
    (should (equal (cadr result) "ནས"))
    (should (string-match-p "nas" (cddr result)))))

(ert-deftest tibetan-interlinear-split-no-particle ()
  "Pure lexical word returns whole word as stem, nil particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "འཁོར་བ" nil)))
    (should (equal (car result) "འཁོར་བ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-noun-tag-no-split ()
  "Word tagged as Noun should not be split."
  (let ((result (tibetan-interlinear--split-word-particle
                 "སྡུག་བསྔལ" "Noun")))
    (should (equal (car result) "སྡུག་བསྔལ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-verb-tag-no-split ()
  "Word tagged as Verb should not be split."
  (let ((result (tibetan-interlinear--split-word-particle
                 "འདྲ" "Verb")))
    (should (equal (car result) "འདྲ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-terminative ()
  "Split terminative particle du."
  (let ((result (tibetan-interlinear--split-word-particle
                 "གནས་སུ" "TERMINATIVE (ALL)")))
    (should (equal (car result) "གནས"))
    (should (equal (cadr result) "སུ"))
    (should (equal (cddr result) "TERM"))))

(ert-deftest tibetan-interlinear-split-pure-standalone-particle ()
  "A word that IS a known particle (e.g. `ནས' standing alone as
ablative converb, not bolted onto a verb stem) returns a split with
nil stem and (WORD . LABEL) particle info.  This makes the
renderer emit a compact `nas [ABL/CONV:nas]' — no jump link, no
dictionary gloss — instead of treating the bare particle as a
content word."
  (let ((result (tibetan-interlinear--split-word-particle
                 "ནས" "CONVERBIAL: ABLATIVE CONVERB")))
    (should (null (car result)))                         ; no stem
    (should (equal (cadr result) "ནས"))                 ; whole word is particle
    (should (equal (cddr result) "ABL/CONV:nas")))      ; compact label
  ;; Same for bare `ལ' (dative)
  (let ((result (tibetan-interlinear--split-word-particle "ལ" "DATIVE (DAT)")))
    (should (null (car result)))
    (should (equal (cadr result) "ལ"))
    (should (equal (cddr result) "DAT"))))

(ert-deftest tibetan-interlinear-split-bslabs-not-causal-converb ()
  "The past stem `བསླབས' (of སློབ) must NOT be split into
`བསླ' + `བས' as a V+bas causal converb — it's a single verb form.
This depends on the Hill verb DB guard in
`tibetan-analyze-converbs-bialek'; here we verify that when no
bialek tag is supplied the Interlinear splitter treats the word as
lexical (no split)."
  (let ((result (tibetan-interlinear--split-word-particle "བསླབས" nil)))
    (should (equal (car result) "བསླབས"))
    (should (null (cdr result)))))

;; ============================================================================
;; PORTFOLIO PARSER
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-parse-basic ()
  "Parse a minimal Portfolio org file."
  (let ((test-file (make-temp-file "portfolio-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Part 1: Case Suffixes\n\n")
            (insert "** 1.1 Genitive\n\n")
            (insert "The genitive suffixes establish a dependency relation.\n\n")
            (insert "*** 1.1.1 Genitive Attribute\n\n")
            (insert "Marks a nominal attribute.\n\n")
            (insert "- example 1\n\n")
            (insert "*** 1.1.2 Genitive with Postpositions\n\n")
            (insert "Connects a noun to a postposition.\n\n")
            (insert "** 1.3 Ergative\n\n")
            (insert "The ergative marks the agent of a transitive verb.\n\n")
            (insert "*** 1.3.1 Subject (Agent)\n\n")
            (insert "Marks the volitional agent.\n"))
          (let ((result (tibetan-interlinear--parse-portfolio test-file)))
            ;; Should have two entries
            (should (= (length result) 2))
            ;; First: genitive
            (let ((gen (cdr (assoc "genitive" result))))
              (should gen)
              (should (equal (plist-get gen :section) "1.1"))
              (should (string-match-p "Genitive" (plist-get gen :title)))
              (should (string-match-p "dependency" (plist-get gen :intro)))
              ;; Should have 2 sub-functions
              (should (= (length (plist-get gen :functions)) 2)))
            ;; Second: ergative
            (let ((erg (cdr (assoc "ergative" result))))
              (should erg)
              (should (equal (plist-get erg :section) "1.3"))
              (should (= (length (plist-get erg :functions)) 1)))))
      (delete-file test-file))))

(ert-deftest tibetan-interlinear-portfolio-parse-converbs ()
  "Parse converb sections from Portfolio."
  (let ((test-file (make-temp-file "portfolio-conv" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Part 2: Converb Constructions\n\n")
            (insert "** 2.1 Verb Stem + /kyang/\n\n")
            (insert "The concessive converb expresses although.\n\n")
            (insert "** 2.3 Verb Stem + /cing/\n\n")
            (insert "The coordinative converb connects simultaneous events.\n"))
          (let ((result (tibetan-interlinear--parse-portfolio test-file)))
            (should (= (length result) 2))
            (should (assoc "converb-kyang" result))
            (should (assoc "converb-cing" result))
            (should (string-match-p "concessive"
                                    (plist-get (cdr (assoc "converb-kyang" result))
                                               :intro)))))
      (delete-file test-file))))

(ert-deftest tibetan-interlinear-portfolio-nil-file ()
  "Nil or missing file returns nil."
  (should (null (tibetan-interlinear--parse-portfolio nil)))
  (should (null (tibetan-interlinear--parse-portfolio "/nonexistent/file.org"))))

;; ============================================================================
;; PORTFOLIO KEY MAPPING
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-key-mapping ()
  "Bialek type labels map to correct portfolio keys."
  (should (equal (tibetan-interlinear--portfolio-key "GENITIVE (GEN)")
                 "genitive"))
  (should (equal (tibetan-interlinear--portfolio-key "ERGATIVE/INSTRUMENTAL (ERG/INST)")
                 "ergative"))
  (should (equal (tibetan-interlinear--portfolio-key "TERMINATIVE (ALL)")
                 "terminative"))
  (should (equal (tibetan-interlinear--portfolio-key "CONCESSIVE PARTICLE")
                 "converb-kyang"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: ABLATIVE CONVERB")
                 "converb-nas"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: COORDINATIVE CONVERB")
                 "converb-ste"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: SIMULTANEOUS CONVERB")
                 "converb-cing"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: CAUSAL CONVERB")
                 "converb-pas"))
  (should (equal (tibetan-interlinear--portfolio-key "DATIVE (DAT)")
                 "dative"))
  (should (equal (tibetan-interlinear--portfolio-key "LOCATIVE (LOC)")
                 "locative"))
  (should (equal (tibetan-interlinear--portfolio-key "TOPIC (TOP)")
                 "topic"))
  (should (equal (tibetan-interlinear--portfolio-key "COMITATIVE (COM)")
                 "comitative")))

;; ============================================================================
;; GLOSS TRUNCATION
;; ============================================================================

(ert-deftest tibetan-interlinear-truncate-gloss ()
  "Gloss truncation respects word boundaries."
  ;; Short enough — unchanged
  (should (equal (tibetan-interlinear--truncate-gloss "suffering" 30)
                 "suffering"))
  ;; Needs truncation — cut at word boundary
  (let ((long "cyclic existence; cycle of powerless birth"))
    (should (<= (length (tibetan-interlinear--truncate-gloss long 20)) 21))
    ;; Single long word without spaces — falls back to char-level cut + ellipsis
    (let ((truncated (tibetan-interlinear--truncate-gloss "abcdefghijklmnop" 10)))
      (should (string-suffix-p "…" truncated))
      (should (<= (length truncated) 10)))
    ;; Multi-word string — cuts at word boundary, result is prefix of original
    (let ((truncated (tibetan-interlinear--truncate-gloss
                      "cyclic existence and rebirth" 20)))
      (should (<= (length truncated) 20))
      ;; Should be "cyclic existence" — clean word boundary, no ellipsis
      (should (string-prefix-p truncated "cyclic existence and rebirth"))
      (should (not (string-suffix-p "…" truncated))))))

;; ============================================================================
;; INTERLINEAR FORMAT ENTRY
;; ============================================================================

(ert-deftest tibetan-interlinear-format-entry-lexical ()
  "Lexical word with internal term-anchor link and gloss.
Pass 5a (2026-04-22) swapped the external Steinert URL for an
internal `[[term-xxx][wylie]]' org link targeting the `<<term-xxx>>'
radio anchor emitted by the Detailed Dictionary section below.  The
link must wrap ONLY the Wylie; the English gloss sits outside the
link as readable plain text."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "'khor ba"
                 "term-khor-ba"
                 "cyclic existence"
                 nil nil)))
    ;; Internal link wraps the wylie alone.
    (should (string-match-p "\\[\\[term-khor-ba\\]\\['khor ba\\]\\]"
                            result))
    ;; Gloss sits outside the link (space then bracketed gloss).
    (should (string-match-p "\\]\\] \\[cyclic existence\\]" result))
    ;; And specifically NOT the old nested form `wylie[gloss]` inside
    ;; the link body.
    (should-not (string-match-p "'khor ba\\[cyclic existence\\]\\]\\]"
                                result))))

(ert-deftest tibetan-interlinear-format-entry-nil-anchor-plain-wylie ()
  "With TERM-ANCHOR=nil, the stem is rendered as plain Wylie (no link).
Used by callers that skip pure function words with no Detailed
Dictionary entry to jump to."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "'khor ba" nil "cyclic existence" nil nil)))
    ;; No `[[...][...]]` link around the Wylie.
    (should-not (string-match-p "\\[\\[.*\\]\\['khor ba\\]\\]" result))
    ;; The Wylie and gloss still appear.
    (should (string-match-p "'khor ba \\[cyclic existence\\]" result))))

(ert-deftest tibetan-interlinear-format-entry-with-particle ()
  "Entry with both lexical stem and particle.
Links wrap only the Wylie for both stem and particle; the English
gloss and the Bialek label sit outside their respective links."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "blo rgod" nil "agitated mind"
                 "kyi" "GEN")))
    ;; Stem: wylie then plain bracketed gloss.
    (should (string-match-p "blo rgod \\[agitated mind\\]" result))
    ;; Particle: plain Wylie + label (no link — `particle:X' targets
    ;; don't exist, so we used to break org-export on resolve).
    (should (string-match-p "kyi \\[GEN\\]" result))
    (should-not (string-match-p "\\[\\[particle:" result))))

(ert-deftest tibetan-interlinear-format-entry-no-gloss ()
  "Entry without gloss shows just the wylie."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "ma" nil nil nil nil)))
    (should (equal result "ma"))))

(ert-deftest tibetan-interlinear-format-gloss-with-brackets-sanitised ()
  "A gloss that is itself `[X]' must not produce `[[X]]' in the output.
Rangjung Yeshe has entries whose gloss is literally bracketed
(e.g. `[value-big]', `[R]', `[accusative, adverbial]').  Wrapping
such a gloss naïvely in `[...]' would create `[[value-big]]',
which org-mode reads as a link target and causes
`Org export aborted.  Unable to resolve link: \"value-big\"'.
The formatter must rewrite brackets to parens."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "rin chen" nil "[value-big]" nil nil)))
    ;; The bracketed gloss is present but wrapped as (value-big) inside
    ;; the outer [...].
    (should (string-match-p "\\[(value-big)\\]" result))
    ;; And the pathological [[value-big]] sequence must NOT appear.
    (should-not (string-match-p "\\[\\[value-big\\]\\]" result))))

(ert-deftest tibetan-interlinear-prefer-english-bilingual ()
  "Bilingual `DE // EN' glosses are reduced to the English half."
  (should (equal "name of a person; the cotton-clad"
                 (tibetan-interlinear--prefer-english
                  "Personenname; der baumwollgewandete [Yogin] aus der Mid-la-Familie // name of a person; the cotton-clad"))))

(ert-deftest tibetan-interlinear-prefer-english-passthrough ()
  "A monolingual gloss (no `//') is returned unchanged."
  (should (equal "wisdom" (tibetan-interlinear--prefer-english "wisdom")))
  (should (equal "jewel; precious"
                 (tibetan-interlinear--prefer-english "jewel; precious"))))

(ert-deftest tibetan-interlinear-truncate-uses-english-half ()
  "Truncation for an interlinear-width bilingual gloss pulls text from
the English side — the German half is no longer stranded."
  (let ((result
         (tibetan-interlinear--truncate-gloss
          "Personenname; der baumwollgewandete Yogin // name of a person; the cotton-clad yogin"
          30)))
    (should (string-match-p "person" result))
    (should-not (string-match-p "Personenname" result))
    (should-not (string-match-p "baumwoll" result))))

(ert-deftest tibetan-interlinear-format-gloss-mixed-brackets-sanitised ()
  "Brackets that appear INSIDE a longer gloss are also rewritten, so
`[la] [(1) [accusative, adverbial]]' does not contain a stray `[[…]]'
sequence either."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "la" nil "(1) [accusative, adverbial]" nil nil)))
    (should-not (string-match-p "\\[\\[" result))
    (should-not (string-match-p "\\]\\]" result))
    ;; Core content still readable.
    (should (string-match-p "accusative" result))))

(ert-deftest tibetan-interlinear-format-gloss-curated-gets-star ()
  "When CURATED-P is non-nil, the formatter prepends `★' before the
gloss so students can spot authoritative Resources / Custom entries
at a glance.  Regression guard for the 2026-04-22 Word/Particle List
removal — the ★ marker that the removed section provided must now
live in the Interlinear output instead."
  (let ((non-curated (tibetan-interlinear--format-gloss-entry
                      "mid la ras pa" nil "name of a person"
                      nil nil nil))
        (curated (tibetan-interlinear--format-gloss-entry
                  "mid la ras pa" nil "name of a person"
                  nil nil t)))
    (should-not (string-match-p "★" non-curated))
    (should (string-match-p "★" curated))
    ;; Both contain the gloss body.
    (should (string-match-p "name of a person" non-curated))
    (should (string-match-p "name of a person" curated))))

(ert-deftest tibetan-interlinear-format-gloss-curated-uses-longer-budget ()
  "Curated entries get 60 chars of truncation budget (vs 30 for
non-curated) so hand-written bilingual Resources glosses don't get
cut off mid-phrase in the interlinear."
  (let* ((long-gloss "name of a person; the cotton-clad yogin from the Mid la family")
         (short (tibetan-interlinear--format-gloss-entry
                 "mid la ras pa" nil long-gloss nil nil nil))
         (long  (tibetan-interlinear--format-gloss-entry
                 "mid la ras pa" nil long-gloss nil nil t)))
    ;; Non-curated truncates before \"cotton-clad\".
    (should-not (string-match-p "cotton" short))
    ;; Curated keeps enough room to include it.
    (should (string-match-p "cotton" long))))

;; ============================================================================
;; PASS 6c: Portfolio sub-function snippet lookup
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-snippet-lookup ()
  "`tibetan-interlinear-portfolio-function-snippet' walks the parsed
Portfolio cache keyed by PORTFOLIO-KEY (e.g. \"terminative\") and
SUB-ID (e.g. \"1.5.1\") and returns `(SUB-TITLE . DESCRIPTION)' or
nil.  Stubbed cache so the test doesn't depend on the user's
actual Portfolio file loaded."
  (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
             (lambda ()
               '(("terminative"
                  :section "1.5"
                  :title "Terminative"
                  :intro "Terminative suffixes mark destination, time, etc."
                  :functions
                  ((("1.5.1" . "Place / Location")
                    . "Marks a place reached or destination, e.g. Englisch `to'.")
                   (("1.5.3" . "Time")
                    . "Marks a point in time, e.g. `at noon'.")))
                 ("converb-nas"
                  :section "2.11"
                  :title "Verb Stem + /nas/"
                  :intro "V+nas marks temporal sequence or cause."
                  :functions
                  ((("2.11.1" . "Sequential Temporal")
                    . "Earlier action in a sequence — `having done X, then Y'.")
                   (("2.11.2" . "Causal")
                    . "Reason for the main verb — `because X, Y happened'.")))))))
    ;; Hit: terminative 1.5.1 → Place / Location.
    (let ((snip (tibetan-interlinear-portfolio-function-snippet
                 "terminative" "1.5.1")))
      (should snip)
      (should (equal (car snip) "Place / Location"))
      (should (string-match-p "place reached" (cdr snip))))
    ;; Hit: converb-nas 2.11.2 → Causal.
    (let ((snip (tibetan-interlinear-portfolio-function-snippet
                 "converb-nas" "2.11.2")))
      (should snip)
      (should (equal (car snip) "Causal")))
    ;; Miss: broader sub-ID (`1.5' alone) returns nil, caller falls back.
    (should (null (tibetan-interlinear-portfolio-function-snippet
                   "terminative" "1.5")))
    ;; Miss: unknown portfolio key returns nil.
    (should (null (tibetan-interlinear-portfolio-function-snippet
                   "unknown-thing" "1.1.1")))
    ;; Nil inputs don't crash.
    (should (null (tibetan-interlinear-portfolio-function-snippet nil "1.1.1")))
    (should (null (tibetan-interlinear-portfolio-function-snippet "terminative" nil)))))

;; ============================================================================
;; PASS 7: Portfolio reference block for Claude system prompt
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-reference-block-empty-when-no-portfolio ()
  "Without a loaded Portfolio, the reference-block generator returns
an empty string — callers inject it unconditionally and the Claude
prompt simply omits the section when there's nothing to say."
  (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
             (lambda () nil)))
    (should (equal "" (tibetan-interlinear-portfolio-reference-block)))))

(ert-deftest tibetan-interlinear-portfolio-reference-block-lists-sections ()
  "The reference block lists each parsed Portfolio section with its
ACTUAL section number + title — from the parsed cache, not a
hardcoded Bialek-canonical list.  When Carsten's Portfolio has
Terminative at §1.6 (rather than §1.5 as in some Bialek textbook
numbering), the block says `§1.6 Terminative' exactly."
  (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
             (lambda ()
               '(("genitive"
                  :section "1.1"
                  :title "Genitive"
                  :intro "..."
                  :functions
                  ((("1.1.1" . "Genitive Attribute") . "Attributive desc.")
                   (("1.1.2" . "Genitive with Postpositions") . "With pp.")))
                 ("ergative"
                  :section "1.3"
                  :title "Ergative"
                  :intro "..."
                  :functions
                  ((("1.3.1" . "Subject of Transitive Verbs") . "Agent.")))
                 ("dative"
                  :section "1.5"
                  :title "Dative"
                  :intro "..."
                  :functions nil)
                 ("terminative"
                  :section "1.6"
                  :title "Terminative"
                  :intro "..."
                  :functions
                  ((("1.6.1" . "Place / Location") . "Place.")
                   (("1.6.3" . "Time")             . "Time.")))))))
    (let ((block (tibetan-interlinear-portfolio-reference-block)))
      ;; Must mention every parsed section with its actual number.
      (should (string-match-p "§1\\.1 Genitive" block))
      (should (string-match-p "§1\\.3 Ergative" block))
      (should (string-match-p "§1\\.5 Dative" block))
      (should (string-match-p "§1\\.6 Terminative" block))
      ;; Sub-section IDs from each section appear.
      (should (string-match-p "1\\.1\\.1 Genitive Attribute" block))
      (should (string-match-p "1\\.6\\.1 Place / Location" block))
      (should (string-match-p "1\\.6\\.3 Time" block))
      ;; CRITICAL: the Bialek-canonical `1.5.1 Terminative-Place'
      ;; number (which Claude has been outputting as a guess) must NOT
      ;; appear as a Portfolio sub-ID — Carsten's Portfolio puts this
      ;; under §1.6.1, not §1.5.1.
      (should-not (string-match-p "1\\.5\\.1.*Terminative" block)))))

(ert-deftest tibetan-interlinear-portfolio-reference-block-instructs-claude ()
  "The reference block carries an instruction that tells Claude to use
the EXACT section IDs listed — not to extrapolate or guess based on
textbook numbering."
  (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
             (lambda ()
               '(("genitive" :section "1.1" :title "Genitive"
                  :intro "." :functions nil)))))
    (let ((block (tibetan-interlinear-portfolio-reference-block)))
      (should (string-match-p "EXACT" block)))))

(ert-deftest tibetan-interlinear-portfolio-reference-block-sections-without-functions ()
  "A Portfolio section whose `:functions' alist is empty still appears
in the reference — just without sub-IDs.  When Claude tags a
particle for such a section, it'll use the top-level §N.N only,
which is still useful.  Avoids silently dropping sections and
confusing Claude about which particles are covered at all."
  (cl-letf (((symbol-function 'tibetan-interlinear--get-portfolio)
             (lambda ()
               '(("elative" :section "1.8" :title "Elative"
                  :intro "." :functions nil)))))
    (let ((block (tibetan-interlinear-portfolio-reference-block)))
      (should (string-match-p "§1\\.8 Elative" block)))))

(provide 'tibetan-interlinear-test)
;;; tibetan-interlinear-test.el ends here
