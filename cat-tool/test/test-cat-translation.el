;;; test-cat-translation.el --- Tests for cat-translation.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for CAT translation functions.
;; Run with: M-x ert-run-tests-batch-and-exit RET test-cat-translation RET

;;; Code:

(require 'ert)
(require 'cat-translation)

;; ============================================================================
;; CONTEXT TESTS
;; ============================================================================

(ert-deftest test-cat-translation-get-context ()
  "Test context retrieval."
  (let ((ctx (cat-translation-get-context 'bhutan-kagyu-madhyamaka)))
    (should ctx)
    (should (eq (car ctx) 'bhutan-kagyu-madhyamaka))))

(ert-deftest test-cat-translation-get-context-unknown ()
  "Test retrieval of unknown context returns nil."
  (should-not (cat-translation-get-context 'unknown-context)))

;; ============================================================================
;; GLOSS BUILDING TESTS
;; ============================================================================

(ert-deftest test-cat-translation-build-gloss ()
  "Test gloss building from parse result."
  (let* ((result (cat-parser-parse "བདག་གིས"))
         (gloss (cat-translation-build-gloss result)))
    (should (listp gloss))
    (should (>= (length gloss) 2))
    ;; Each item should be a cons cell
    (should (consp (car gloss)))))

(ert-deftest test-cat-translation-gloss-to-string ()
  "Test gloss to string conversion."
  (let ((gloss '(("བདག" . "I") ("གིས" . "ERG"))))
    (let ((str (cat-translation-gloss-to-string gloss)))
      (should (stringp str))
      (should (string-match-p "བདག=I" str))
      (should (string-match-p "གིས=ERG" str)))))

(ert-deftest test-cat-translation-gloss-to-string-custom-sep ()
  "Test gloss to string with custom separator."
  (let ((gloss '(("a" . "1") ("b" . "2"))))
    (let ((str (cat-translation-gloss-to-string gloss " / ")))
      (should (string-match-p "a=1 / b=2" str)))))

;; ============================================================================
;; CLEAN MEANING TESTS
;; ============================================================================

(ert-deftest test-cat-translation-clean-meaning-simple ()
  "Test cleaning simple meaning."
  (should (string= (cat-translation-clean-meaning "I") "I")))

(ert-deftest test-cat-translation-clean-meaning-comma ()
  "Test cleaning meaning with comma."
  (should (string= (cat-translation-clean-meaning "I, me, self") "I")))

(ert-deftest test-cat-translation-clean-meaning-semicolon ()
  "Test cleaning meaning with semicolon."
  (should (string= (cat-translation-clean-meaning "I; self") "I")))

(ert-deftest test-cat-translation-clean-meaning-whitespace ()
  "Test cleaning meaning with whitespace."
  (should (string= (cat-translation-clean-meaning "  I  ") "I")))

;; ============================================================================
;; CONTENT WORD EXTRACTION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-extract-content-words ()
  "Test content word extraction filters particles."
  (let ((gloss '(("བདག" . "I") ("གིས" . "?") ("ནི" . "topic"))))
    (let ((content (cat-translation-extract-content-words gloss)))
      ;; Should only have བདག
      (should (= (length content) 1))
      (should (string= (caar content) "བདག")))))

(ert-deftest test-cat-translation-extract-content-words-skip-unknown ()
  "Test that unknown words are filtered."
  (let ((gloss '(("བདག" . "I") ("xyz" . "?"))))
    (let ((content (cat-translation-extract-content-words gloss)))
      (should (= (length content) 1)))))

(ert-deftest test-cat-translation-extract-content-words-skip-empty ()
  "Test that empty meanings are filtered."
  (let ((gloss '(("བདག" . "I") ("xyz" . ""))))
    (let ((content (cat-translation-extract-content-words gloss)))
      (should (= (length content) 1)))))

;; ============================================================================
;; CONNECTOR DETECTION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-detect-connector-nas ()
  "Test sequential connector detection for ནས."
  (should (eq (cat-translation-detect-connector "བྱས་ནས" nil) 'sequential)))

(ert-deftest test-cat-translation-detect-connector-ste ()
  "Test sequential connector detection for སྟེ."
  (should (eq (cat-translation-detect-connector "བྱས་སྟེ" nil) 'sequential)))

(ert-deftest test-cat-translation-detect-connector-zhing ()
  "Test simultaneous connector detection for ཞིང."
  (should (eq (cat-translation-detect-connector "བྱེད་ཞིང" nil) 'simultaneous)))

(ert-deftest test-cat-translation-detect-connector-pas ()
  "Test causal connector detection for པས."
  (should (eq (cat-translation-detect-connector "བྱས་པས" nil) 'causal)))

(ert-deftest test-cat-translation-detect-connector-na ()
  "Test conditional connector detection for ན."
  (should (eq (cat-translation-detect-connector "བྱས་ན" nil) 'conditional)))

(ert-deftest test-cat-translation-detect-connector-dang ()
  "Test conjunction connector detection for དང."
  (should (eq (cat-translation-detect-connector "དང" nil) 'conjunction)))

(ert-deftest test-cat-translation-detect-connector-none ()
  "Test no connector for plain word."
  (should-not (cat-translation-detect-connector "བདག" nil)))

;; ============================================================================
;; CONNECTOR APPLICATION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-apply-connector-first ()
  "Test connector application for first line."
  (let ((result (cat-translation-apply-connector "did something" nil t nil)))
    (should (string-match-p "^D" result))))  ; Capitalized

(ert-deftest test-cat-translation-apply-connector-last ()
  "Test connector application for last line."
  (let ((result (cat-translation-apply-connector "did something" nil nil t)))
    (should (string-match-p "\\.$" result))))  ; Period at end

(ert-deftest test-cat-translation-apply-connector-sequential ()
  "Test sequential connector application."
  (let ((result (cat-translation-apply-connector "Did something" 'sequential nil nil)))
    (should (string-match-p "Having" result))))

(ert-deftest test-cat-translation-apply-connector-simultaneous ()
  "Test simultaneous connector application."
  (let ((result (cat-translation-apply-connector "Did something" 'simultaneous nil nil)))
    (should (string-match-p "while" result))))

(ert-deftest test-cat-translation-apply-connector-causal ()
  "Test causal connector application."
  (let ((result (cat-translation-apply-connector "Did something" 'causal nil nil)))
    (should (string-match-p "because" result))))

;; ============================================================================
;; BASIC TRANSLATION GENERATION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-generate-basic ()
  "Test basic translation generation."
  ;; Create a mock vocabulary
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "I, self" tibetan-comprehensive-vocabulary)
    (puthash "བྱས" "did, made" tibetan-comprehensive-vocabulary)
    (let* ((result (cat-parser-parse "བདག་བྱས"))
           (trans (cat-translation-generate-basic result)))
      (should (stringp trans))
      (should (> (length trans) 0)))))

(ert-deftest test-cat-translation-generate-basic-capitalized ()
  "Test that basic translation is capitalized."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "self" tibetan-comprehensive-vocabulary)
    (let* ((result (cat-parser-parse "བདག"))
           (trans (cat-translation-generate-basic result)))
      (when (> (length trans) 0)
        (should (string-match-p "^[A-Z]" trans))))))

;; ============================================================================
;; GRAMMAR-AWARE TRANSLATION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-generate-with-grammar ()
  "Test grammar-aware translation generation."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "I" tibetan-comprehensive-vocabulary)
    (let* ((result (cat-parser-parse "བདག་གིས"))
           (particles (cat-grammar-analyze-text "བདག་གིས"))
           (trans (cat-translation-generate-with-grammar result particles)))
      (should (stringp trans)))))

;; ============================================================================
;; MAIN INTERFACE TESTS
;; ============================================================================

(ert-deftest test-cat-translation-suggest ()
  "Test main translation suggestion interface."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "I" tibetan-comprehensive-vocabulary)
    (let ((suggestion (cat-translation-suggest "བདག")))
      (should (listp suggestion))
      (should (assq :basic suggestion))
      (should (assq :grammar-aware suggestion))
      (should (assq :gloss suggestion))
      (should (assq :particles suggestion)))))

(ert-deftest test-cat-translation-suggest-empty ()
  "Test suggestion for empty text."
  (let ((suggestion (cat-translation-suggest "")))
    (should (listp suggestion))))

;; ============================================================================
;; COMPOUND TRANSLATION TESTS
;; ============================================================================

(ert-deftest test-cat-translation-generate-compound ()
  "Test compound/verse translation generation."
  (let ((tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (puthash "བདག" "I" tibetan-comprehensive-vocabulary)
    (puthash "བྱས" "did" tibetan-comprehensive-vocabulary)
    (let* ((lines '(("1" . "བདག") ("2" . "བྱས")))
           (trans (cat-translation-generate-compound lines 'classical-prose)))
      (should (stringp trans))
      (should (> (length trans) 0)))))

(provide 'test-cat-translation)
;;; test-cat-translation.el ends here
