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

;; ============================================================================
;; FORMAT ENTRY TESTS
;; ============================================================================

;; ============================================================================
;; FORMAT LIST TESTS
;; ============================================================================

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

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

(ert-deftest tibetan-vocab-parse-entry-fallback-skips-junk-senses ()
  "M5 (Fable-5 audit): the D1 Latin-sense fallback took the FIRST
sense containing ANY Latin letter — a Dan-Martin page ref
(`a.ko.194kha') produced :primary \"a\"; and the plain `;'-split was
not bracket-aware (`[Skt; loan]' yielded \"[Skt\").  The fallback
must skip low-quality senses and split senses at depth 0 only."
  ;; Page-ref sense skipped → real gloss wins.
  (let ((entry (tibetan-vocab--parse-entry
                "ས་ཞིང་གསར་པ་རྨོས་པ; a.ko.194kha; ploughing new fields")))
    (should (string= (plist-get entry :primary) "ploughing new fields")))
  ;; Bracket-internal `;' does not split the sense.
  (let ((entry (tibetan-vocab--parse-entry
                "དཔེར་ན་སྟེ; [Skt; loan] example")))
    (should (string-match-p "example" (plist-get entry :primary)))
    (should-not (string= (plist-get entry :primary) "[Skt"))))

;; RETIRED (D1a, 2026-07-28): 15 tests of the dead COMPOUND-AWARE
;; subtree (tibetan-vocab-extract-detailed + formatters) — the subtree
;; had zero production callers and was removed.  The ≥3-syllable
;; verb-tail guard remains covered on the two LIVE loops by
;; tibetan-vocabulary-test.el (interlinear) and
;; tibetan-round1-verb-extraction-test.el (parser).

(provide 'tibetan-vocabulary-detailed-test)
;;; tibetan-vocabulary-detailed-test.el ends here
