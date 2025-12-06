;;; test-cat-utils.el --- Tests for cat-utils.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for CAT utility functions.
;; Run with: M-x ert-run-tests-batch-and-exit RET test-cat-utils RET

;;; Code:

(require 'ert)
(require 'cat-utils)

;; ============================================================================
;; SAFE SUBSTRING TESTS
;; ============================================================================

(ert-deftest test-cat-safe-substring-basic ()
  "Test basic substring extraction."
  (should (string= (cat-safe-substring "hello" 0 3) "hel"))
  (should (string= (cat-safe-substring "hello" 1 4) "ell"))
  (should (string= (cat-safe-substring "hello" 0) "hello")))

(ert-deftest test-cat-safe-substring-empty ()
  "Test substring on empty string."
  (should (string= (cat-safe-substring "" 0 0) ""))
  (should (string= (cat-safe-substring "" 0) "")))

(ert-deftest test-cat-safe-substring-out-of-range ()
  "Test substring with out-of-range indices."
  (should (string= (cat-safe-substring "hi" 0 10) "hi"))
  (should (string= (cat-safe-substring "hi" 5 10) ""))
  (should (string= (cat-safe-substring "hi" -1 2) "hi")))

(ert-deftest test-cat-safe-substring-tibetan ()
  "Test substring on Tibetan multi-byte text."
  (let ((text "སུ"))  ; Single Tibetan syllable
    (should (string= (cat-safe-substring text 0 1) "ས"))
    (should (string= (cat-safe-substring text 0 2) "སུ"))
    ;; Out of range should not error
    (should (stringp (cat-safe-substring text 0 10)))))

(ert-deftest test-cat-safe-substring-tibetan-word ()
  "Test substring on longer Tibetan word."
  (let ((text "བདག་གིས"))  ; "bdag gis" - I + ergative
    (should (> (length text) 0))
    ;; Should not error even with wrong indices
    (should (stringp (cat-safe-substring text 0 100)))
    (should (stringp (cat-safe-substring text 50 100)))))

;; ============================================================================
;; STRIP PARTICLE SUFFIX TESTS
;; ============================================================================

(ert-deftest test-cat-strip-particle-suffix-basic ()
  "Test basic particle stripping."
  (should (string= (cat-strip-particle-suffix "བདག་གིས" "གིས") "བདག་"))
  (should (string= (cat-strip-particle-suffix "hello" "lo") "hel")))

(ert-deftest test-cat-strip-particle-suffix-no-match ()
  "Test stripping when particle not present."
  (should (string= (cat-strip-particle-suffix "བདག" "གིས") "བདག")))

;; ============================================================================
;; TEXT SEGMENTATION TESTS
;; ============================================================================

(ert-deftest test-cat-segment-text-basic ()
  "Test basic text segmentation."
  (let ((result (cat-segment-text "བདག་གིས་བྱས")))
    (should (= (length result) 3))
    (should (string= (nth 0 result) "བདག"))
    (should (string= (nth 1 result) "གིས"))
    (should (string= (nth 2 result) "བྱས"))))

(ert-deftest test-cat-segment-text-with-punctuation ()
  "Test segmentation removes punctuation."
  (let ((result (cat-segment-text "བདག་གིས།")))
    (should (= (length result) 2))
    (should (string= (nth 0 result) "བདག"))
    (should (string= (nth 1 result) "གིས"))))

(ert-deftest test-cat-segment-text-empty ()
  "Test segmentation of empty string."
  (should (null (cat-segment-text "")))
  (should (null (cat-segment-text "།"))))

;; ============================================================================
;; PARTICLE DETECTION TESTS
;; ============================================================================

(ert-deftest test-cat-detect-ergative ()
  "Test ergative particle detection."
  (let ((result (cat-detect-ergative "བདག་གིས")))
    (should result)
    (should (string= (car result) "གིས"))
    (should (string= (cdr result) "བདག་"))))

(ert-deftest test-cat-detect-ergative-kyis ()
  "Test ergative ཀྱིས detection."
  (let ((result (cat-detect-ergative "མ་སྨད་ཀྱིས")))
    (should result)
    (should (string= (car result) "ཀྱིས"))))

(ert-deftest test-cat-detect-genitive ()
  "Test genitive particle detection."
  (let ((result (cat-detect-genitive "དེའི")))
    (should result)
    (should (string= (car result) "འི"))
    (should (string= (cdr result) "དེ"))))

(ert-deftest test-cat-detect-dative ()
  "Test dative particle detection."
  (let ((result (cat-detect-dative "ཕྱོགས་སུ")))
    (should result)
    (should (string= (car result) "སུ"))))

(ert-deftest test-cat-detect-no-particle ()
  "Test detection returns nil when no particle."
  (should-not (cat-detect-ergative "བདག"))
  (should-not (cat-detect-genitive "བདག"))
  (should-not (cat-detect-dative "བདག")))

;; ============================================================================
;; DISPLAY FORMATTING TESTS
;; ============================================================================

(ert-deftest test-cat-separator-line ()
  "Test separator line constant."
  (should (stringp cat-separator-line))
  (should (> (length cat-separator-line) 20)))

(ert-deftest test-cat-insert-separator ()
  "Test separator insertion."
  (with-temp-buffer
    (cat-insert-separator)
    (should (> (buffer-size) 0))
    (should (string-match-p "─" (buffer-string)))))

(ert-deftest test-cat-insert-header ()
  "Test header insertion."
  (with-temp-buffer
    (cat-insert-header "Test Header")
    (should (string-match-p "TEST HEADER" (buffer-string)))
    (should (string-match-p "─" (buffer-string)))))

;; ============================================================================
;; VOCABULARY LOOKUP TESTS
;; ============================================================================

(ert-deftest test-cat-lookup-word-not-bound ()
  "Test lookup when vocabulary not loaded."
  (let ((tibetan-comprehensive-vocabulary nil))
    (should-not (cat-lookup-word "བདག"))))

;; ============================================================================
;; CONTEXT DETECTION TESTS
;; ============================================================================

(ert-deftest test-cat-madhyamaka-context-p ()
  "Test Madhyamaka context detection."
  (let ((tibetan-text-context 'bhutan-kagyu-madhyamaka))
    (should (cat-madhyamaka-context-p)))
  (let ((tibetan-text-context 'classical-prose))
    (should-not (cat-madhyamaka-context-p))))

(ert-deftest test-cat-verse-context-p ()
  "Test verse context detection."
  (let ((tibetan-text-context 'bhutan-kagyu-madhyamaka))
    (should (cat-verse-context-p)))
  (let ((tibetan-text-context 'classical-prose))
    (should-not (cat-verse-context-p))))

(provide 'test-cat-utils)
;;; test-cat-utils.el ends here
