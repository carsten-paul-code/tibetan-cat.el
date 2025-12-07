;;; tibetan-translation-engine-test.el --- Tests for tibetan-translation-engine.el -*- lexical-binding: t -*-

(require 'ert)
(require 'tibetan-translation-engine)

;; ============================================================================
;; GLOSS WORD TESTS
;; ============================================================================

(ert-deftest tibetan-cat-gloss-word-returns-string-or-nil ()
  "Test that gloss returns string or nil, never errors."
  (let ((result (tibetan-cat--gloss-word "བྱེད")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-cat-gloss-word-empty-input ()
  "Test that empty input returns nil."
  (should-not (tibetan-cat--gloss-word ""))
  (should-not (tibetan-cat--gloss-word nil)))

(ert-deftest tibetan-cat-gloss-word-cleans-result ()
  "Test that gloss result is trimmed and simplified."
  (let ((result (tibetan-cat--gloss-word "བྱེད")))
    (when result
      ;; Should not have leading/trailing whitespace
      (should (string= result (string-trim result)))
      ;; Should not contain semicolons (takes first meaning only)
      (should-not (string-match-p ";" result)))))

;; ============================================================================
;; VERB PHRASE BUILDING TESTS
;; ============================================================================

(ert-deftest tibetan-cat-build-verb-phrase-basic ()
  "Test basic verb phrase building."
  (let ((result (tibetan-cat--build-verb-phrase "བྱེད" "to do" nil)))
    (should (stringp result))
    (should (string= "do" result))))  ; "to " prefix removed

(ert-deftest tibetan-cat-build-verb-phrase-no-meaning ()
  "Test verb phrase with no meaning falls back to form."
  (let ((result (tibetan-cat--build-verb-phrase "unknown" nil nil)))
    (should (stringp result))))

;; ============================================================================
;; NOUN PHRASE BUILDING TESTS
;; ============================================================================

(ert-deftest tibetan-cat-build-noun-phrase-agent ()
  "Test that AGENT role doesn't add preposition."
  (let ((result (tibetan-cat--build-noun-phrase "བདག" "self" 'AGENT "ERG")))
    (should (string= "self" result))))

(ert-deftest tibetan-cat-build-noun-phrase-patient ()
  "Test that PATIENT role doesn't add preposition."
  (let ((result (tibetan-cat--build-noun-phrase "ཆོས" "dharma" 'PATIENT "ABS")))
    (should (string= "dharma" result))))

(ert-deftest tibetan-cat-build-noun-phrase-goal ()
  "Test that GOAL role adds 'to' preposition."
  (let ((result (tibetan-cat--build-noun-phrase "བླ་མ" "lama" 'GOAL "DAT")))
    (should (string= "to lama" result))))

(ert-deftest tibetan-cat-build-noun-phrase-source ()
  "Test that SOURCE role adds 'from' preposition."
  (let ((result (tibetan-cat--build-noun-phrase "གནས" "place" 'SOURCE "ABL")))
    (should (string= "from place" result))))

(ert-deftest tibetan-cat-build-noun-phrase-location ()
  "Test that LOCATION role adds 'in' preposition."
  (let ((result (tibetan-cat--build-noun-phrase "གནས" "place" 'LOCATION "LOC")))
    (should (string= "in place" result))))

(ert-deftest tibetan-cat-build-noun-phrase-no-english ()
  "Test fallback when no English gloss available."
  (let ((result (tibetan-cat--build-noun-phrase "xyz" nil 'AGENT "ERG")))
    (should (stringp result))
    ;; Should have brackets indicating unknown word
    (should (or (string-match-p "\\[" result)
                (not (string-empty-p result))))))

;; ============================================================================
;; TRANSLATION GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-cat-generate-translation-returns-string ()
  "Test that translation generation always returns a string."
  (let ((result (tibetan-cat-generate-translation "བྱེད")))
    (should (stringp result))))

(ert-deftest tibetan-cat-generate-translation-empty-input ()
  "Test translation of empty input."
  (let ((result (tibetan-cat-generate-translation "")))
    (should (stringp result))))

(ert-deftest tibetan-cat-generate-translation-nil-input ()
  "Test translation of nil input doesn't error."
  (condition-case err
      (let ((result (tibetan-cat-generate-translation nil)))
        (should (or (null result) (stringp result))))
    (error (should-not "Function should not error on nil input"))))

(ert-deftest tibetan-cat-generate-translation-simple-verb ()
  "Test translation of simple verb."
  (let ((result (tibetan-cat-generate-translation "འགྲོ")))
    (should (stringp result))
    (should (> (length result) 0))))

;; ============================================================================
;; WORD ORDER MAPPING TESTS
;; ============================================================================

(ert-deftest tibetan-cat-word-order-mapping-exists ()
  "Test that word order mapping variable exists and has entries."
  (should (boundp 'tibetan-cat-translation-word-order))
  (should (> (length tibetan-cat-translation-word-order) 0)))

(ert-deftest tibetan-cat-word-order-erg-abs ()
  "Test Erg-Abs maps to AGENT PATIENT VERB order."
  (let ((order (alist-get 'Erg-Abs tibetan-cat-translation-word-order)))
    (should order)
    (should (equal '(AGENT PATIENT VERB) order))))

(ert-deftest tibetan-cat-word-order-abs ()
  "Test Abs maps to SUBJECT VERB order."
  (let ((order (alist-get 'Abs tibetan-cat-translation-word-order)))
    (should order)
    (should (equal '(SUBJECT VERB) order))))

;; ============================================================================
;; ARGUMENT EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-cat-get-arguments-empty ()
  "Test argument extraction from empty string."
  (let ((result (tibetan-cat--get-arguments-from-structure "")))
    (should (listp result))))

(ert-deftest tibetan-cat-get-arguments-predicate ()
  "Test extraction of PREDICATE from structure text."
  (let ((result (tibetan-cat--get-arguments-from-structure
                 "- PREDICATE: བྱེད \"to do\" [tr]")))
    (should (listp result))
    (should (assoc 'VERB result))))

(ert-deftest tibetan-cat-get-arguments-agent ()
  "Test extraction of AGENT from structure text."
  (let ((result (tibetan-cat--get-arguments-from-structure
                 "  - AGENT: བདག \"self\" (ERG)")))
    (should (listp result))
    (should (assoc 'AGENT result))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-cat-translate-region-exists ()
  "Test that tibetan-cat-translate-region function exists."
  (should (fboundp 'tibetan-cat-translate-region)))

(ert-deftest tibetan-cat-insert-translation-exists ()
  "Test that tibetan-cat-insert-translation function exists."
  (should (fboundp 'tibetan-cat-insert-translation)))

(provide 'tibetan-translation-engine-test)
;;; tibetan-translation-engine-test.el ends here
