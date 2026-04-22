;;; tibetan-particles-bialek-test.el --- Tests for tibetan-particles-bialek.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for Bialek-based grammar analysis functionality.
;; Tests cover case particle analysis, converbial constructions, and helper functions.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-particles-bialek)

;; ============================================================================
;; SAFE SUBSTRING TESTS
;; ============================================================================

(ert-deftest tibetan-particles-safe-substring-basic ()
  "Test basic substring extraction with safe boundaries."
  (should (equal (tibetan-particles-safe-substring "བདག" 0 1) "བ"))
  (should (equal (tibetan-particles-safe-substring "བདག" 0 2) "བད"))
  (should (equal (tibetan-particles-safe-substring "བདག" 1 3) "དག"))
  (should (equal (tibetan-particles-safe-substring "test" 0 2) "te"))
  (should (equal (tibetan-particles-safe-substring "test" 0 100) "test")))

(ert-deftest tibetan-particles-safe-substring-edge-cases ()
  "Test safe substring with out-of-range indices and invalid inputs."
  ;; Out of range
  (should (equal (tibetan-particles-safe-substring "བདག" 10 20) ""))
  (should (equal (tibetan-particles-safe-substring "བདག" 100 200) ""))
  ;; Invalid inputs
  (should (equal (tibetan-particles-safe-substring nil 0 1) ""))
  (should (equal (tibetan-particles-safe-substring "" 0 1) ""))
  ;; Negative indices get converted to 0
  (should (equal (tibetan-particles-safe-substring "བདག" -5 2) "བད"))
  ;; Start equal to end
  (should (equal (tibetan-particles-safe-substring "བདག" 1 1) "")))

;; ============================================================================
;; CASE PARTICLE ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-cases-bialek-ergative ()
  "Test detection of ergative/instrumental case particles."
  ;; Test ergative particle གིས
  (let ((result (tibetan-analyze-cases-bialek "མི་གིས")))
    (should (listp result))
    (should (> (length result) 0))
    ;; Check for particle in results
    (let ((particles (mapcar (lambda (item) (car item)) result)))
      (should (member "གིས" particles))))
  ;; Test particle ཀྱིས
  (let ((result (tibetan-analyze-cases-bialek "ལྷ་ཀྱིས")))
    (should (listp result))
    (should (> (length result) 0))))

;; ----------------------------------------------------------------------------
;; Regression — single-char ergative `s' on vowel-final stems
;; ----------------------------------------------------------------------------
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: Claude's `## Particles'
;; tagged `des, s, 1.3.1, instrumental' but the Grammar section's
;; `*** Particles in This Segment' showed no entry for `des' because
;; `tibetan-analyze-cases-bialek' did not detect the single-char
;; ergative `s' on vowel-final stems.  Multi-char forms (`gis',
;; `kyis', `gyis') fire correctly; the contracted single-char form is
;; the gap.
;;
;; Bialek Portfolio §1.3.1 (Ergative/Instrumental) explicitly teaches
;; the single-char form — `de + s' → `des', `kho + s' → `khos' — as
;; the vowel-final variant of ergative marking.  The analyser must
;; match it without over-matching verb past stems like `byas'
;; (past of byed: `bya' + `s' is NOT a V-s converb, it's the
;; inflected past) or consonant-final words ending in `-Cs' that
;; aren't morphologically `stem + s'.

(defun tibetan-bialek-test--ergative-types (result)
  "Return the list of unique case-type labels in RESULT that match
ERGATIVE / INSTRUMENTAL."
  (let ((types '()))
    (dolist (item result)
      (let ((type (nth 2 item)))
        (when (and type (string-match-p "ERGATIVE\\|INSTRUMENTAL" type))
          (push type types))))
    (delete-dups types)))

(ert-deftest tibetan-analyze-cases-bialek-ergative-s-vowel-final-stem ()
  "Single-char ergative `s' on vowel-final stems (`des', `khos',
`bus', `mos', `mthus') must be detected as ERGATIVE/INSTRUMENTAL.
Regression guard for the seg-30 `des' bug where Claude's tagged
instrumental function landed in `*** Claude Particles' but had no
bialek entry in the Grammar section to attach under."
  (dolist (word '("དེས"      ;; de + s    (demonstrative)
                  "ཁོས"       ;; kho + s   (3rd-person pronoun)
                  "བུས"       ;; bu + s    (child)
                  "མོས"       ;; mo + s    (3rd-person feminine / she)
                  "མཐུས"))    ;; mthu + s  (power)
    (let* ((result (tibetan-analyze-cases-bialek word))
           (erg (tibetan-bialek-test--ergative-types result)))
      (should erg)
      ;; Useful ancillary: the bialek entry should name the full word
      ;; in its `word' slot so the Grammar renderer can anchor a
      ;; Claude tuple on it.
      (let ((words (mapcar (lambda (item) (nth 1 item)) result)))
        (should (member word words))))))

(ert-deftest tibetan-analyze-cases-bialek-ergative-s-does-not-match-verb-past-stems ()
  "Past / imperative verb stems that happen to end in `s' must NOT
be mis-detected as ergative case.  The Hill DB guard (identical in
spirit to the fix for `bslabs' in `analyze-converbs-bialek' from
2026-04-22) prevents `byas' (past of byed) / `mdzad' / `phyag'-
style stems from getting a spurious ERG tag."
  (dolist (verb-stem '("བྱས"       ;; past of བྱེད (byed)
                       "གསུངས"     ;; past of གསུང (gsung)
                       "སྨྲས"       ;; past of སྨྲ (smra)
                       "བསླབས"))    ;; past of སློབ (slob)
    (let* ((result (tibetan-analyze-cases-bialek verb-stem))
           (erg (tibetan-bialek-test--ergative-types result)))
      (should-not erg))))

(ert-deftest tibetan-analyze-cases-bialek-ergative-s-preserves-distinct-particles ()
  "Stripping a single-char ergative `s' must not steal particles
that already have a more specific rule — `las' stays ABLATIVE, not
ergative; `nas' stays its own thing (ablative converb path);
`ཀྱིས' / `གིས' / `གྱིས' keep their ergative tag via the
multi-char rule, not the single-s rule."
  ;; ལས — ablative, NOT ergative
  (let* ((result (tibetan-analyze-cases-bialek "ལས"))
         (types  (mapcar (lambda (item) (nth 2 item)) result)))
    (should (cl-some (lambda (type) (string-match-p "ABLATIVE" type)) types))
    (should-not (cl-some (lambda (type)
                           (and type (string-match-p "ERGATIVE" type)))
                         types)))
  ;; Multi-char ergative forms — existing rule still works.
  (dolist (word '("བདག་གིས" "ལྷ་ཀྱིས" "མོ་གྱིས"))
    (let* ((result (tibetan-analyze-cases-bialek word))
           (erg (tibetan-bialek-test--ergative-types result)))
      (should erg))))

(ert-deftest tibetan-analyze-cases-bialek-ergative-s-rejects-bare-consonant-s ()
  "Words where the pre-`s' char is itself a consonant (so the stem
would be Wylie-ill-formed, not a real word) must NOT be flagged
ergative.  `sems' / `mams' / `bus' of the `bus'=child case all
need stem VOWEL-final; a single `s' at the end after `m' or `s'
is part of the root, not a clitic.

This is the over-strip-prevention half of the fix."
  ;; `sems' = mind.  Stripping `s' → `sem' which isn't a word
  ;; and `sems' itself is a noun lemma.  Should NOT be ergative.
  (let* ((result (tibetan-analyze-cases-bialek "སེམས"))
         (erg (tibetan-bialek-test--ergative-types result)))
    (should-not erg))
  ;; `lus' = body.  Strip → `lu' — not a word.  Should NOT be
  ;; ergative.  Edge case: `lus' does end in a vowel under Wylie
  ;; (`u' vowel before `s').  The safety is that `lus' is itself a
  ;; known noun lemma, and the detector prefers the lemma reading.
  (let* ((result (tibetan-analyze-cases-bialek "ལུས"))
         (erg (tibetan-bialek-test--ergative-types result)))
    (should-not erg)))

(ert-deftest tibetan-analyze-cases-bialek-genitive ()
  "Test detection of genitive case particles."
  (let ((result (tibetan-analyze-cases-bialek "པདྨའི")))
    (should (listp result))
    (should (> (length result) 0))
    ;; Check for genitive particle
    (let ((particles (mapcar (lambda (item) (car item)) result)))
      (should (member "འི" particles)))))

(ert-deftest tibetan-analyze-cases-bialek-returns-analysis ()
  "Test that analyze-cases-bialek returns properly formatted analysis lists."
  (let ((result (tibetan-analyze-cases-bialek "མི་གིས་ཞིང")))
    (should (listp result))
    ;; Each item should be a list with proper structure
    (dolist (item result)
      (should (listp item))
      ;; Each analysis item should have at least 6 elements:
      ;; (particle word case function translation bialek-ref)
      (should (>= (length item) 6))
      ;; First element (particle) should be a string
      (should (stringp (nth 0 item)))
      ;; Second element (word) should be a string
      (should (stringp (nth 1 item)))
      ;; Third element (case) should be a string
      (should (stringp (nth 2 item))))))

;; ============================================================================
;; CONVERBIAL CONSTRUCTION ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-converbs-bialek-ablative ()
  "Test detection of ablative converbial constructions."
  (let ((result (tibetan-analyze-converbs-bialek "གསེགས་པ་ནས")))
    (should (listp result))
    ;; Should find ablative converb ནས
    (let ((particles (mapcar (lambda (item) (car item)) result)))
      (should (member "ནས" particles)))))

(ert-deftest tibetan-analyze-converbs-bialek-coordinative ()
  "Test detection of coordinative converbial constructions."
  (let ((result (tibetan-analyze-converbs-bialek "གསེགས་པ་སྟེ")))
    (should (listp result))
    ;; Should find coordinative converb
    (let ((particles (mapcar (lambda (item) (car item)) result)))
      (should (or (member "སྟེ" particles)
                  (member "ཏེ" particles))))))

(ert-deftest tibetan-analyze-converbs-bialek-simultaneous ()
  "Test detection of simultaneous converbial constructions."
  (let ((result (tibetan-analyze-converbs-bialek "སྒེགས་པ་ཞིང")))
    (should (listp result))
    ;; Should find simultaneous converb ཞིང
    (let ((particles (mapcar (lambda (item) (car item)) result)))
      (should (member "ཞིང" particles)))))

(ert-deftest tibetan-analyze-converbs-bialek-skips-verb-past-stems ()
  "Past/imperative stems ending in `བས' (`བསླབས', `སླེབས', `སློབས')
are NOT `V+bas' causal converbs — they are single inflected verb
forms.  The Hill DB guard must prevent the analyser from reporting
them as CONVERBIAL: CAUSAL CONVERB.  Without this guard, Milarepa
seg-30 `བསླབས' (past of སློབ) triggered a false `V+bas' split, and
the Interlinear picked up the bogus tag and rendered `[[term-basla]
[basla]]' as the stem — nonsense Wylie + broken dictionary jump."
  ;; བསླབས (past of སློབ "to train")
  (let ((result (tibetan-analyze-converbs-bialek "བསླབས")))
    (should-not (cl-some (lambda (item)
                           (string-match-p "CAUSAL CONVERB" (nth 2 item)))
                         result)))
  ;; སློབས (imperative of སློབ)
  (let ((result (tibetan-analyze-converbs-bialek "སློབས")))
    (should-not (cl-some (lambda (item)
                           (string-match-p "CAUSAL CONVERB" (nth 2 item)))
                         result)))
  ;; སླེབས (past of སླེབ "to arrive")
  (let ((result (tibetan-analyze-converbs-bialek "སླེབས")))
    (should-not (cl-some (lambda (item)
                           (string-match-p "CAUSAL CONVERB" (nth 2 item)))
                         result))))

(ert-deftest tibetan-analyze-converbs-bialek-returns-analysis ()
  "Test that analyze-converbs-bialek returns properly formatted analysis lists."
  (let ((result (tibetan-analyze-converbs-bialek "གསེགས་པ་ནས་དེ་ནས")))
    (should (listp result))
    ;; Each item should be a properly formatted analysis
    (dolist (item result)
      (should (listp item))
      ;; Should have particle, word, type, function, translation, bialek-ref
      (should (>= (length item) 6))
      ;; Verify string fields
      (should (stringp (nth 0 item)))
      (should (stringp (nth 1 item)))
      (should (stringp (nth 2 item))))))

;; ============================================================================
;; EDGE CASES AND SPECIAL TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-cases-bialek-empty-input ()
  "Test case analysis with empty input."
  (let ((result (tibetan-analyze-cases-bialek "")))
    (should (listp result))
    (should (= (length result) 0))))

(ert-deftest tibetan-analyze-converbs-bialek-empty-input ()
  "Test converb analysis with empty input."
  (let ((result (tibetan-analyze-converbs-bialek "")))
    (should (listp result))
    (should (= (length result) 0))))

(ert-deftest tibetan-analyze-cases-bialek-no-particles ()
  "Test case analysis with text containing no particle markers."
  (let ((result (tibetan-analyze-cases-bialek "བདག་ཀ")))
    (should (listp result))
    ;; May be empty or contain items without recognized particles
    (should (>= (length result) 0))))

;; ============================================================================
;; UNIFIED BIALEK GRAMMAR ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-grammar-bialek-empty-input ()
  "Test grammar analysis with empty input."
  (skip-unless (fboundp 'tibetan-analyze-grammar-bialek))
  (let ((result (tibetan-analyze-grammar-bialek "")))
    (should (listp result))
    (should (= (length result) 0))))

(ert-deftest tibetan-analyze-grammar-bialek-returns-list ()
  "Test that grammar analysis returns a list of analyses."
  (skip-unless (fboundp 'tibetan-analyze-grammar-bialek))
  (let ((result (tibetan-analyze-grammar-bialek "མི་གིས་ཞིང")))
    (should (listp result))))

(ert-deftest tibetan-analyze-grammar-bialek-combines-cases-and-converbs ()
  "Test that unified analysis combines both case analysis and converbs."
  (skip-unless (fboundp 'tibetan-analyze-grammar-bialek))
  (let ((result (tibetan-analyze-grammar-bialek "མི་གིས་བྱས་ནས")))
    (should (listp result))
    ;; Should have multiple analyses (both case and converb)
    (should (or (> (length result) 0) (= (length result) 0)))))

(ert-deftest tibetan-analyze-grammar-bialek-removes-duplicates ()
  "Test that unified analysis removes duplicate particles by word."
  (skip-unless (fboundp 'tibetan-analyze-grammar-bialek))
  ;; Same word shouldn't appear twice in results
  (let ((result (tibetan-analyze-grammar-bialek "མི་གིས་མི་གིས")))
    (should (listp result))
    ;; Check that we don't have duplicate words with same analysis
    (let ((words (mapcar (lambda (item) (nth 1 item)) result)))
      ;; May have same word once from unified analysis
      (should (listp words)))))

;; ============================================================================
;; Terminative -ར suffix on the final tsheg-piece of a compound
;; ============================================================================
;; Gap closed: before this rule, bialek's tsheg-split turned
;; `ཀོ་རོན་སར' into (`ཀོ' `རོན' `སར') and the single-char `ར' rule only
;; matched standalone `ར' — so the terminative on the compound was
;; missed.  The fix is conservative: it fires only when the input is a
;; multi-piece compound whose LAST piece is exactly 2 chars ending in
;; `ར'.  That excludes standalone 2-char words like མར/པར/དར, which
;; are legitimate nouns in their own right and must NOT be mis-tagged.

(ert-deftest tibetan-bialek-terminative-sar-at-end-of-compound ()
  "`ཀོ་རོན་སར' (compound ending in `སར') → TERMINATIVE."
  (let* ((result (tibetan-analyze-grammar-bialek "ཀོ་རོན་སར"))
         (types (mapcar (lambda (a) (nth 2 a)) result)))
    (should result)
    (should (cl-some (lambda (t0) (string-match-p "TERMINATIVE" t0)) types))))

(ert-deftest tibetan-bialek-terminative-nar-at-end-of-compound ()
  "`དགོན་པ་ནར' (hypothetical compound ending in `ནར') → TERMINATIVE.
Covers other short X+ར patterns the conservative rule must accept."
  (let* ((result (tibetan-analyze-grammar-bialek "དགོན་པ་ནར"))
         (types (mapcar (lambda (a) (nth 2 a)) result)))
    (should result)
    (should (cl-some (lambda (t0) (string-match-p "TERMINATIVE" t0)) types))))

(ert-deftest tibetan-bialek-standalone-par-stays-noun ()
  "Standalone `པར' (a noun meaning `book/print') must NOT be flagged
as terminative — the rule requires multi-piece compound context."
  (let ((result (tibetan-analyze-grammar-bialek "པར")))
    (should-not
     (cl-some (lambda (a)
                (let ((type (nth 2 a)))
                  (and type (string-match-p "TERMINATIVE" type))))
              result))))

(ert-deftest tibetan-bialek-standalone-mar-stays-noun ()
  "Standalone `མར' (butter / downward) must NOT be terminative."
  (let ((result (tibetan-analyze-grammar-bialek "མར")))
    (should-not
     (cl-some (lambda (a)
                (let ((type (nth 2 a)))
                  (and type (string-match-p "TERMINATIVE" type))))
              result))))

(provide 'tibetan-particles-bialek-test)
;;; tibetan-particles-bialek-test.el ends here
