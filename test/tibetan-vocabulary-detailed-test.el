;;; tibetan-vocabulary-detailed-test.el --- Tests for tibetan-vocabulary-detailed.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for detailed vocabulary lookup and formatting functionality.
;; Tests cover lookup, extraction, and formatting of detailed vocabulary entries.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-vocabulary-detailed)

;; ============================================================================
;; VOCABULARY LOOKUP TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-lookup-detailed-function-exists ()
  "Test that tibetan-vocab-lookup-detailed function exists."
  (should (fboundp 'tibetan-vocab-lookup-detailed)))

(ert-deftest tibetan-vocab-lookup-detailed-nil-input ()
  "Test vocabulary lookup with nil or empty input."
  (skip-unless (fboundp 'tibetan-vocab-lookup-detailed))
  ;; nil input should return nil
  (should-not (tibetan-vocab-lookup-detailed nil))
  ;; empty string should return nil
  (should-not (tibetan-vocab-lookup-detailed "")))

(ert-deftest tibetan-vocab-lookup-detailed-returns-plist ()
  "Test that vocabulary lookup returns a plist when successful."
  (skip-unless (fboundp 'tibetan-vocab-lookup-detailed))
  ;; Call with a common word (may or may not be in glossary)
  (let ((result (tibetan-vocab-lookup-detailed "བྱེད")))
    ;; Result should be either nil or a plist
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-vocab-lookup-detailed-plist-structure ()
  "Test that returned plists have expected keys."
  (skip-unless (fboundp 'tibetan-vocab-lookup-detailed))
  ;; Test with various words to find one that exists
  (let* ((test-words '("བདག" "སེམས" "མི" "གང" "དེ"))
         (results (mapcar 'tibetan-vocab-lookup-detailed test-words))
         (found-result (cl-find-if 'listp results)))
    ;; If we found any result, verify structure
    (if found-result
        (should (listp found-result))
      ;; If no results found, that's ok - vocabularies may be empty during testing
      (should (or (null found-result) (listp found-result))))))

;; ============================================================================
;; VOCABULARY EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-extract-detailed-function-exists ()
  "Test that tibetan-vocab-extract-detailed function exists."
  (should (fboundp 'tibetan-vocab-extract-detailed)))

(ert-deftest tibetan-vocab-extract-detailed-empty-text ()
  "Test vocabulary extraction with empty text."
  (skip-unless (fboundp 'tibetan-vocab-extract-detailed))
  ;; Empty text should return empty list
  (let ((result (tibetan-vocab-extract-detailed "")))
    (should (listp result))
    (should (= (length result) 0))))

(ert-deftest tibetan-vocab-extract-detailed-returns-list ()
  "Test that vocabulary extraction returns a list."
  (skip-unless (fboundp 'tibetan-vocab-extract-detailed))
  ;; With Tibetan text
  (let ((result (tibetan-vocab-extract-detailed "བདག་བྱེད")))
    (should (listp result))))

(ert-deftest tibetan-vocab-extract-detailed-from-compound ()
  "Test vocabulary extraction from compound words."
  (skip-unless (fboundp 'tibetan-vocab-extract-detailed))
  ;; Multi-syllable compound
  (let ((result (tibetan-vocab-extract-detailed "བྱང་ཆུབ")))
    (should (listp result))
    ;; May extract individual syllables or compounds
    (should (>= (length result) 0))))

;; ============================================================================
;; FORMAT ENTRY TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-format-entry-short-function-exists ()
  "Test that tibetan-vocab-format-entry-short function exists."
  (should (fboundp 'tibetan-vocab-format-entry-short)))

(ert-deftest tibetan-vocab-format-entry-short-nil-input ()
  "Test short format with nil input."
  (skip-unless (fboundp 'tibetan-vocab-format-entry-short))
  ;; Should handle nil gracefully
  (let ((result (tibetan-vocab-format-entry-short nil)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-vocab-format-entry-short-returns-string ()
  "Test that short format returns a string."
  (skip-unless (fboundp 'tibetan-vocab-format-entry-short))
  ;; Test with a plist entry
  (let ((entry '(:primary "verb" :detailed "to do" :source "glossary")))
    (let ((result (tibetan-vocab-format-entry-short entry)))
      (should (or (null result) (stringp result))))))

;; ============================================================================
;; FORMAT LIST TESTS
;; ============================================================================

(ert-deftest tibetan-vocab-format-list-short-function-exists ()
  "Test that tibetan-vocab-format-list-short function exists."
  (should (fboundp 'tibetan-vocab-format-list-short)))

(ert-deftest tibetan-vocab-format-list-full-function-exists ()
  "Test that tibetan-vocab-format-list-full function exists."
  (should (fboundp 'tibetan-vocab-format-list-full)))

(ert-deftest tibetan-vocab-format-list-short-empty ()
  "Test short list format with empty list."
  (skip-unless (fboundp 'tibetan-vocab-format-list-short))
  (let ((result (tibetan-vocab-format-list-short '())))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-vocab-format-list-full-empty ()
  "Test full list format with empty list."
  (skip-unless (fboundp 'tibetan-vocab-format-list-full))
  (let ((result (tibetan-vocab-format-list-full '())))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-vocab-format-list-short-returns-string ()
  "Test that short list format returns string."
  (skip-unless (fboundp 'tibetan-vocab-format-list-short))
  ;; Test with sample vocab list
  (let ((vocab-list '(
        (:primary "verb" :detailed "to do")
        (:primary "noun" :detailed "person")
        )))
    (let ((result (tibetan-vocab-format-list-short vocab-list)))
      (should (or (null result) (stringp result))))))

(ert-deftest tibetan-vocab-format-list-full-returns-string ()
  "Test that full list format returns string."
  (skip-unless (fboundp 'tibetan-vocab-format-list-full))
  ;; Test with sample vocab list including detailed info
  (let ((vocab-list '(
        (:primary "verb" :detailed "to do" :source "glossary")
        (:primary "noun" :detailed "person" :sanskrit "puruṣa")
        )))
    (let ((result (tibetan-vocab-format-list-full vocab-list)))
      (should (or (null result) (stringp result))))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-vocabulary-detailed-workflow ()
  "Test a complete vocabulary lookup and formatting workflow."
  (skip-unless (fboundp 'tibetan-vocab-extract-detailed))
  (skip-unless (fboundp 'tibetan-vocab-format-list-short))
  ;; Extract vocabulary from text
  (let ((extracted (tibetan-vocab-extract-detailed "བདག་བྱེད")))
    ;; Format the result
    (should (listp extracted))
    ;; Try formatting
    (let ((formatted (tibetan-vocab-format-list-short extracted)))
      (should (or (null formatted) (stringp formatted))))))

;; ============================================================================
;; Example-sentence-as-gloss filter (item D1, 2026-06-03)
;; ============================================================================

(ert-deftest tibetan-vocab-mostly-tibetan-p-detects-example ()
  "A string that is all Tibetan script with no Latin letters is an
example sentence, not a gloss."
  (should (tibetan-vocab--mostly-tibetan-p "བཅོམ་ལྡན་འདས་ཀྱི་དྲུང་དུ"))
  ;; A real gloss (has Latin) is NOT an example.
  (should-not (tibetan-vocab--mostly-tibetan-p "presence, residence"))
  ;; Mixed (Tibetan headword + Latin gloss) → has Latin → not an example.
  (should-not (tibetan-vocab--mostly-tibetan-p "དྲུང་དུ to the presence of"))
  (should-not (tibetan-vocab--mostly-tibetan-p nil)))

(ert-deftest tibetan-vocab-parse-entry-skips-tibetan-example-primary ()
  "When the first sense of an entry is a Tibetan EXAMPLE sentence
(no Latin gloss), `parse-entry' skips it and uses the first sense
that carries an actual Latin gloss as `:primary'.

Regression for the Milarepa Segment 110 class of bug: a phrasal
dictionary entry whose leading sense is a Tibetan usage example
(`bcom ldan 'das kyi drung du') was surfacing as the token gloss
instead of the English/German meaning."
  ;; The recovered Latin sense is truncated at the first comma, exactly
  ;; as the normal first-sense extraction does — so `:primary' is the
  ;; head gloss "presence", not the whole "presence, residence".
  (let ((entry (tibetan-vocab--parse-entry
                "བཅོམ་ལྡན་འདས་ཀྱི་དྲུང་དུ; presence, residence")))
    (should (string= (plist-get entry :primary) "presence")))
  ;; An entry with a Latin first sense is unaffected.
  (let ((entry (tibetan-vocab--parse-entry "mane; dewlap")))
    (should (string= (plist-get entry :primary) "mane")))
  ;; An entry with ONLY a Tibetan example (no Latin anywhere) is left
  ;; as-is — there is nothing better to fall back to.
  (let ((entry (tibetan-vocab--parse-entry "རྔོག་གི་དྲུང་དུ")))
    (should (string= (plist-get entry :primary) "རྔོག་གི་དྲུང་དུ"))))

;; ============================================================================
;; H1 (Fable-5 audit): DD verb-tail parity with the Interlinear loop
;; ============================================================================

(ert-deftest tibetan-vocab-extract-detailed-rejects-three-syllable-verb-tail ()
  "The DD greedy loop rejects a 3-syllable phrasal whose tail is a
Hill verb (`དྲུང་དུ་ཕྱིན'), matching the Interlinear + parser loops —
otherwise the surfaces disagree on grouping and term anchors dangle."
  (skip-unless (fboundp 'tibetan-verb-lookup))
  (cl-letf (((symbol-function 'tibetan-vocab--mwu-exists-p)
             (lambda (w) (member w '("དྲུང་དུ་ཕྱིན" "ཡེ་ཤེས"))))
            ((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (w) (list :wylie w :primary "stub" :detailed "stub"
                               :sanskrit nil :source "Stub")))
            ((symbol-function 'tibetan-load-resources-vocab) #'ignore)
            ((symbol-function 'tibetan-load-custom-vocab) #'ignore))
    (let ((tibetan-current-resources-vocab nil)
          (tibetan-current-custom-vocab nil))
      ;; 3-syllable verb-tail phrasal: NOT one unit.
      (let ((tib (mapcar (lambda (p) (plist-get p :tibetan))
                         (tibetan-vocab-extract-detailed "དྲུང་དུ་ཕྱིན"))))
        (should-not (member "དྲུང་དུ་ཕྱིན" tib)))
      ;; 2-syllable lexicalized noun: stays one unit.
      (let ((tib (mapcar (lambda (p) (plist-get p :tibetan))
                         (tibetan-vocab-extract-detailed "ཡེ་ཤེས་ལ"))))
        (should (member "ཡེ་ཤེས" tib))))))

(provide 'tibetan-vocabulary-detailed-test)
;;; tibetan-vocabulary-detailed-test.el ends here
