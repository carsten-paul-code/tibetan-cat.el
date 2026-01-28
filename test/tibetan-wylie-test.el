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
  (should (equal (tibetan-to-wylie "རྒ") "rga")))

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

(provide 'tibetan-wylie-test)
;;; tibetan-wylie-test.el ends here
