;;; tibetan-wylie-test.el --- Tests for tibetan-wylie.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for Wylie transliteration functionality.
;; Tests cover basic consonants, vowels, stacks, and edge cases.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-wylie)

;; ============================================================================
;; BASIC CONSONANTS
;; ============================================================================

(ert-deftest tibetan-wylie-basic-consonants ()
  "Test basic consonant transliteration."
  (should (equal (tibetan-to-wylie "ཀ") "ka"))
  (should (equal (tibetan-to-wylie "ཁ") "kha"))
  (should (equal (tibetan-to-wylie "ག") "ga"))
  (should (equal (tibetan-to-wylie "པ") "pa"))
  (should (equal (tibetan-to-wylie "བ") "ba"))
  (should (equal (tibetan-to-wylie "མ") "ma")))

(ert-deftest tibetan-wylie-aspirates ()
  "Test aspirated consonants."
  (should (equal (tibetan-to-wylie "ཐ") "tha"))
  (should (equal (tibetan-to-wylie "ཕ") "pha"))
  (should (equal (tibetan-to-wylie "ཆ") "cha"))
  (should (equal (tibetan-to-wylie "ཚ") "tsha")))

;; ============================================================================
;; VOWELS
;; ============================================================================

(ert-deftest tibetan-wylie-vowels ()
  "Test vowel marks."
  (should (equal (tibetan-to-wylie "ཀི") "ki"))
  (should (equal (tibetan-to-wylie "ཀུ") "ku"))
  (should (equal (tibetan-to-wylie "ཀེ") "ke"))
  (should (equal (tibetan-to-wylie "ཀོ") "ko")))

(ert-deftest tibetan-wylie-implicit-a ()
  "Test implicit 'a' vowel handling."
  ;; Single consonant should have 'a'
  (should (equal (tibetan-to-wylie "བ") "ba"))
  ;; Consonant + vowel mark should NOT have extra 'a'
  (should (equal (tibetan-to-wylie "བི") "bi"))
  (should (not (string-match-p "ba" (tibetan-to-wylie "བི")))))

;; ============================================================================
;; SYLLABLE STRUCTURE
;; ============================================================================

(ert-deftest tibetan-wylie-root-suffix ()
  "Test root + suffix combinations."
  (should (equal (tibetan-to-wylie "དང") "dang"))
  (should (equal (tibetan-to-wylie "བར") "bar"))
  (should (equal (tibetan-to-wylie "པས") "pas")))

(ert-deftest tibetan-wylie-prefix-root ()
  "Test prefix + root combinations."
  (should (equal (tibetan-to-wylie "བདག") "bdag"))
  (should (equal (tibetan-to-wylie "གསད") "gsad")))

(ert-deftest tibetan-wylie-complex-syllables ()
  "Test complex syllable structures."
  ;; Prefix + root + suffix
  (should (equal (tibetan-to-wylie "བསམས") "bsams"))
  ;; Root + subscript
  (should (equal (tibetan-to-wylie "བྱང") "byang")))

;; ============================================================================
;; CONSONANT STACKS
;; ============================================================================

(ert-deftest tibetan-wylie-subscript-y ()
  "Test ya-btags (subscript y)."
  (should (equal (tibetan-to-wylie "ཀྱ") "kya"))
  (should (equal (tibetan-to-wylie "གྱ") "gya"))
  (should (equal (tibetan-to-wylie "བྱ") "bya")))

(ert-deftest tibetan-wylie-subscript-r ()
  "Test ra-btags (subscript r)."
  (should (equal (tibetan-to-wylie "ཀྲ") "kra"))
  (should (equal (tibetan-to-wylie "གྲ") "gra"))
  (should (equal (tibetan-to-wylie "བྲ") "bra")))

(ert-deftest tibetan-wylie-subscript-l ()
  "Test la-btags (subscript l)."
  (should (equal (tibetan-to-wylie "གླ") "gla"))
  (should (equal (tibetan-to-wylie "བླ") "bla")))

(ert-deftest tibetan-wylie-superscript-s ()
  "Test sa-mgo (superscript s)."
  (should (equal (tibetan-to-wylie "སྐ") "ska"))
  (should (equal (tibetan-to-wylie "སྒ") "sga"))
  (should (equal (tibetan-to-wylie "སྤ") "spa")))

(ert-deftest tibetan-wylie-superscript-r ()
  "Test ra-mgo (superscript r)."
  (should (equal (tibetan-to-wylie "རྐ") "rka"))
  (should (equal (tibetan-to-wylie "རྒ") "rga"))
  ;; ra + nga stack (was missing → produced "ra"+vowel, dropping ng).
  (should (equal (tibetan-to-wylie "རྔ") "rnga"))
  ;; Full word: རྔོག (rNgog, disciple of Marpa) must be "rngog", not "raog".
  (should (equal (tibetan-to-wylie-fixed "རྔོག") "rngog")))

;; ============================================================================
;; PUNCTUATION
;; ============================================================================

(ert-deftest tibetan-wylie-tsheg ()
  "Test tsheg (syllable separator)."
  (should (string-match-p " " (tibetan-to-wylie "བདག་")))
  (should (string-match-p " " (tibetan-to-wylie "བྱང་ཆུབ"))))

(ert-deftest tibetan-wylie-shad ()
  "Test shad (sentence marker)."
  (should (string-match-p "/" (tibetan-to-wylie "།")))
  (should (string-match-p "//" (tibetan-to-wylie "༎"))))

;; ============================================================================
;; MULTI-SYLLABLE WORDS
;; ============================================================================

(ert-deftest tibetan-wylie-common-words ()
  "Test common Tibetan words."
  ;; བྱང་ཆུབ་ = enlightenment
  (should (string-match-p "byang" (tibetan-to-wylie "བྱང་ཆུབ")))
  (should (string-match-p "chub" (tibetan-to-wylie "བྱང་ཆུབ")))
  ;; སེམས་ = mind
  (should (equal (tibetan-to-wylie "སེམས") "sems")))

(ert-deftest tibetan-wylie-bodhisattva ()
  "Test bodhisattva transliteration."
  ;; བྱང་ཆུབ་སེམས་དཔའ་
  (let ((result (tibetan-to-wylie "བྱང་ཆུབ་སེམས་དཔའ")))
    (should (string-match-p "byang" result))
    (should (string-match-p "sems" result))
    (should (string-match-p "dpa" result))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-wylie-empty-string ()
  "Test empty string handling."
  (should (equal (tibetan-to-wylie "") "")))

(ert-deftest tibetan-wylie-nil-input ()
  "Test nil input handling."
  ;; Should not error, should return empty or original
  (should (stringp (tibetan-to-wylie nil))))

(ert-deftest tibetan-wylie-mixed-content ()
  "Test mixed Tibetan and non-Tibetan content."
  ;; Should handle gracefully
  (should (stringp (tibetan-to-wylie "བདག test"))))

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(ert-deftest tibetan-wylie-safe-substring ()
  "Test safe substring extraction."
  (should (equal (tibetan-safe-substring "test" 0 2) "te"))
  (should (equal (tibetan-safe-substring "test" 0 100) "test"))
  (should (equal (tibetan-safe-substring "test" 10 20) ""))
  (should (equal (tibetan-safe-substring nil 0 1) ""))
  (should (equal (tibetan-safe-substring "" 0 1) "")))

(ert-deftest tibetan-wylie-is-prefix ()
  "Test prefix detection."
  ;; ག is valid prefix before ཅ
  (should (tibetan-is-prefix "ག" "ཅ"))
  ;; བ is valid prefix before ཀ
  (should (tibetan-is-prefix "བ" "ཀ"))
  ;; ཀ is NOT a valid prefix
  (should-not (tibetan-is-prefix "ཀ" "ག")))

;; ============================================================================
;; FIXED VERSION TESTS
;; ============================================================================

(ert-deftest tibetan-to-wylie-fixed-syllable-conversion ()
  "Test tibetan-to-wylie-fixed for proper syllable conversions with implicit 'a'."
  ;; Basic syllables with implicit 'a'
  (should (equal (tibetan-to-wylie-fixed "བདག") "bdag"))
  (should (equal (tibetan-to-wylie-fixed "དང") "dang"))
  (should (equal (tibetan-to-wylie-fixed "པས") "pas"))
  ;; Syllables with explicit vowels (no implicit 'a')
  (should (equal (tibetan-to-wylie-fixed "བི") "bi"))
  (should (equal (tibetan-to-wylie-fixed "སེམས") "sems"))
  ;; Syllables with punctuation
  (should (string-match-p "dang" (tibetan-to-wylie-fixed "དང་")))
  ;; Multi-syllable words
  (should (string-match-p "byang.*chub" (tibetan-to-wylie-fixed "བྱང་ཆུབ")))
  ;; Edge cases
  (should (equal (tibetan-to-wylie-fixed "") ""))
  (should (stringp (tibetan-to-wylie-fixed "བདག test"))))

(ert-deftest tibetan-syllable-to-wylie-root-handling ()
  "Test tibetan-syllable-to-wylie for correct root consonant handling and implicit 'a'."
  ;; Single root with implicit 'a'
  (should (equal (tibetan-syllable-to-wylie "བ") "ba"))
  (should (equal (tibetan-syllable-to-wylie "དང") "dang"))
  ;; Root with explicit vowel mark (no implicit 'a')
  (should (equal (tibetan-syllable-to-wylie "བི") "bi"))
  (should (equal (tibetan-syllable-to-wylie "དེ") "de"))
  ;; Prefix + root combinations (prefix gets no 'a', root gets 'a')
  (should (equal (tibetan-syllable-to-wylie "གསད") "gsad"))
  (should (equal (tibetan-syllable-to-wylie "བསམ") "bsam"))
  ;; Root + suffix combinations (root gets 'a' only if no vowel mark)
  (should (equal (tibetan-syllable-to-wylie "བར") "bar"))
  (should (equal (tibetan-syllable-to-wylie "དང") "dang"))
  ;; Subscript consonants
  (should (equal (tibetan-syllable-to-wylie "གྲ") "gra"))
  (should (equal (tibetan-syllable-to-wylie "བྲ") "bra"))
  (should (equal (tibetan-syllable-to-wylie "གླ") "gla"))
  ;; Empty and edge cases
  (should (equal (tibetan-syllable-to-wylie "") ""))
  (should (equal (tibetan-syllable-to-wylie "ི") "i")))

(ert-deftest tibetan-wylie-l-ca-subscript ()
  "ལྕ (la + subscript ca) — Milarepa seg-007 regression, ལྕགས→lcags."
  (should (equal (tibetan-syllable-to-wylie "ལྕ") "lca"))
  (should (equal (tibetan-syllable-to-wylie "ལྕགས") "lcags"))
  (should (equal (tibetan-syllable-to-wylie "ལྕེ") "lce")))

(ert-deftest tibetan-wylie-b-prefix-l-stack ()
  "བ prefix + ལ-headed stack — Milarepa seg-007 regression, བལྟམས→bltams."
  (should (equal (tibetan-syllable-to-wylie "བལྟ") "blta"))
  (should (equal (tibetan-syllable-to-wylie "བལྟམས") "bltams"))
  (should (equal (tibetan-syllable-to-wylie "བལྟས") "bltas")))

(ert-deftest tibetan-wylie-a-chen-no-double-a ()
  "Bare ཨ must transliterate as \"a\", not \"aa\" (Milarepa seg-011 regression)."
  (should (equal (tibetan-syllable-to-wylie "ཨ") "a"))
  ;; Compound where ཨ opens a syllable — was producing 'aa khu'i' before fix.
  (should (equal (tibetan-to-wylie-fixed "ཨ་ཁུ") "a khu"))
  (should (equal (tibetan-to-wylie-fixed "ཨ་ཁུའི") "a khu'i")))

(ert-deftest tibetan-wylie-a-chen-vowel-carrier ()
  "ཨ + vowel sign should emit only the vowel, not \"a\" + vowel.
ཨ is the vowel carrier (a-chen); when followed by a vowel sign the
\"a\" is silent and the vowel sign alone determines the value.
Regression: ཨོམ was producing \"aom\" instead of \"om\"."
  ;; Single-syllable vowel carrier cases
  (should (equal (tibetan-syllable-to-wylie "ཨོ") "o"))
  (should (equal (tibetan-syllable-to-wylie "ཨི") "i"))
  (should (equal (tibetan-syllable-to-wylie "ཨུ") "u"))
  (should (equal (tibetan-syllable-to-wylie "ཨེ") "e"))
  ;; ཨོམ = om (vowel carrier + o-sign + suffix ma)
  (should (equal (tibetan-syllable-to-wylie "ཨོམ") "om"))
  ;; Bare ཨ still = "a" (no vowel sign → carrier IS the vowel)
  (should (equal (tibetan-syllable-to-wylie "ཨ") "a"))
  ;; Multi-syllable: OM SWA STI mantra
  (should (equal (tibetan-to-wylie-fixed "ཨོམ་སྭ་སྟི") "om swa sti")))

;; ============================================================================
;; Regression — apostrophe-prefix (a-chung) + subjoined-consonant clusters
;; ============================================================================
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: the Wylie line rendered
;;   ... yin yin 'adra ba bslabs nas ...
;; instead of the expected
;;   ... yin yin 'dra ba bslabs nas ...
;;
;; Two distinct bugs surfaced:
;;
;;   Bug A (primary): `འདྲ' → `'adra' instead of `'dra'.
;;     The prefix-detection loop counts only chars in U+0F40..U+0F6C
;;     (main consonant block) and ignores the subjoined range
;;     U+0F90..U+0FBC.  For `འདྲ' (3 chars: `འ' main + `ད' main +
;;     `ྲ' subjoined) the count is 2, no vowel-after-second, so
;;     `འ' fails the is-prefix check and gets treated as a root —
;;     which means it receives an implicit `a' suffix.
;;
;;   Bug B (adjacent): `དྲུག' → `druag' instead of `drug'.
;;     The consonant-stacks table has a vowel-EMBEDDED entry
;;     `("དྲུ" . "dru")' (the wylie already carries the `u').
;;     When this stack matches, the implicit-a logic still runs
;;     because the next Tibetan char after the 3-stack is `ག'
;;     (a suffix, not a vowel sign) — so `is-root + not has-vowel-
;;     after' evaluates true and adds `a', producing `drua' + `g'.
;;
;; Fix targets:
;;   · Extend the prefix detector to count subjoined consonants.
;;   · Remove the vowel-embedded stacks `དྲུ'/`ཀྲུ' so `དྲུག'
;;     naturally decomposes as `དྲ' (stack) + `ུ' (vowel) + `ག'
;;     (suffix) via the normal three-step path.

(ert-deftest tibetan-wylie-a-prefix-with-subjoined-cluster ()
  "`འ' prefix followed by a consonant + subjoined-consonant cluster
must render as `'Cr' / `'Cl' / ..., not `'aCr'."
  (should (equal (tibetan-to-wylie-fixed "འདྲ")    "'dra"))
  (should (equal (tibetan-to-wylie-fixed "འདྲ་བ") "'dra ba"))
  ;; Adjacent cases that already worked — must keep working.
  (should (equal (tibetan-to-wylie-fixed "འགྲོ")   "'gro"))
  (should (equal (tibetan-to-wylie-fixed "འདི")    "'di"))
  (should (equal (tibetan-to-wylie-fixed "འོངས")   "'ongs")))

(ert-deftest tibetan-wylie-stack-plus-u-plus-suffix ()
  "`ད' + subjoined `ྲ' + vowel `ུ' + suffix `ག' = `drug', not
`druag'.  The stack-with-embedded-vowel regression."
  (should (equal (tibetan-to-wylie-fixed "དྲུག") "drug"))
  (should (equal (tibetan-to-wylie-fixed "ཀྲུ")  "kru"))
  ;; Adjacent — `དྲ' without vowel carries implicit `a' → `dra'.
  (should (equal (tibetan-to-wylie-fixed "དྲ")   "dra"))
  ;; Other roots with ra-subscript stay correct.
  (should (equal (tibetan-to-wylie-fixed "བྲུག") "brug"))
  (should (equal (tibetan-to-wylie-fixed "ཁྲུས") "khrus")))

(ert-deftest tibetan-wylie-a-prefix-full-sentence ()
  "Full-sentence regression from Milarepa seg-30 — `'adra ba' was
the rendering; expected `'dra ba'."
  (should
   (equal
    (tibetan-to-wylie-fixed "འདྲ་བ་བསླབས་")
    "'dra ba bslabs ")))

(provide 'tibetan-wylie-test)
;;; tibetan-wylie-test.el ends here
