;;; test-cat-parser.el --- Tests for cat-parser.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for CAT parser functions.
;; Run with: M-x ert-run-tests-batch-and-exit RET test-cat-parser RET

;;; Code:

(require 'ert)
(require 'cat-parser)

;; ============================================================================
;; PARSE RESULT STRUCTURE TESTS
;; ============================================================================

(ert-deftest test-cat-parser-parse-returns-struct ()
  "Test that parse returns a cat-parse-result struct."
  (let ((result (cat-parser-parse "བདག་གིས")))
    (should (cat-parse-result-p result))
    (should (cat-parse-result-words result))
    (should (cat-parse-result-segments result))))

(ert-deftest test-cat-parser-parse-words ()
  "Test that parse correctly extracts words."
  (let* ((result (cat-parser-parse "བདག་གིས་བྱས"))
         (words (cat-parse-result-words result)))
    (should (= (length words) 3))
    (should (string= (nth 0 words) "བདག"))
    (should (string= (nth 1 words) "གིས"))
    (should (string= (nth 2 words) "བྱས"))))

(ert-deftest test-cat-parser-parse-empty ()
  "Test parsing empty string."
  (let ((result (cat-parser-parse "")))
    (should (cat-parse-result-p result))
    (should (null (cat-parse-result-words result)))))

;; ============================================================================
;; MULTIWORD UNIT DETECTION TESTS
;; ============================================================================

(ert-deftest test-cat-parser-find-multiword-units-no-dict ()
  "Test multiword detection when dictionaries not loaded."
  (let ((cat-parser-compounds-dict nil)
        (cat-parser-proper-nouns-dict nil))
    ;; Should still work, just return empty
    (let ((units (cat-parser-find-multiword-units '("བདག" "གིས"))))
      (should (listp units)))))

(ert-deftest test-cat-parser-get-claimed-indices ()
  "Test claimed indices extraction."
  (let ((units '((0 2 "test" nil) (4 6 "test2" nil))))
    (let ((claimed (cat-parser-get-claimed-indices units)))
      (should (gethash 0 claimed))
      (should (gethash 1 claimed))
      (should-not (gethash 2 claimed))
      (should-not (gethash 3 claimed))
      (should (gethash 4 claimed))
      (should (gethash 5 claimed)))))

;; ============================================================================
;; SEGMENT BUILDING TESTS
;; ============================================================================

(ert-deftest test-cat-parser-build-segments-no-compounds ()
  "Test segment building without compounds."
  (let ((words '("བདག" "གིས" "བྱས"))
        (units nil))
    (let ((segments (cat-parser-build-segments words units)))
      (should (= (length segments) 3))
      (should (equal segments words)))))

(ert-deftest test-cat-parser-build-segments-with-compound ()
  "Test segment building with a compound."
  (let ((words '("གླེང" "གཞི" "ན"))
        (units '((0 2 "གླེང་གཞི" ((english . "nidana"))))))
    (let ((segments (cat-parser-build-segments words units)))
      (should (= (length segments) 2))
      (should (string= (nth 0 segments) "གླེང་གཞི"))
      (should (string= (nth 1 segments) "ན")))))

;; ============================================================================
;; WORD ANALYSIS TESTS
;; ============================================================================

(ert-deftest test-cat-parser-analyze-word-genitive ()
  "Test word analysis for genitive suffix."
  (let ((result (cat-parser-analyze-word "དེའི" nil nil)))
    (should (string= (alist-get 'type result) "word+genitive"))
    (should (string= (alist-get 'base result) "དེ"))
    (should (string= (alist-get 'particle result) "འི"))))

(ert-deftest test-cat-parser-analyze-word-nominalizer ()
  "Test word analysis for nominalizer suffix."
  (let ((result (cat-parser-analyze-word "བྱེད་པ" nil nil)))
    (should (string= (alist-get 'type result) "word+nominalizer"))
    (should (string= (alist-get 'particle result) "པ"))))

(ert-deftest test-cat-parser-analyze-word-case-particle ()
  "Test word analysis for standalone case particle."
  (let ((result (cat-parser-analyze-word "ལ" nil nil)))
    (should (string= (alist-get 'type result) "case_particle"))
    (should (string= (alist-get 'particle result) "ལ"))))

(ert-deftest test-cat-parser-analyze-word-plain ()
  "Test word analysis for plain word."
  (let ((result (cat-parser-analyze-word "བདག" nil nil)))
    (should (string= (alist-get 'type result) "word"))
    (should (string= (alist-get 'form result) "བདག"))))

;; ============================================================================
;; PARTICLE FUNCTION TESTS
;; ============================================================================

(ert-deftest test-cat-parser-particle-function-na ()
  "Test particle function description for ན."
  (let ((func (cat-parser-particle-function "ན")))
    (should (string-match-p "Locative" func))))

(ert-deftest test-cat-parser-particle-function-la ()
  "Test particle function description for ལ."
  (let ((func (cat-parser-particle-function "ལ")))
    (should (string-match-p "Dative" func))))

(ert-deftest test-cat-parser-particle-function-nas ()
  "Test particle function description for ནས."
  (let ((func (cat-parser-particle-function "ནས")))
    (should (string-match-p "Ablative" func))))

;; ============================================================================
;; LOOKUP TESTS
;; ============================================================================

(ert-deftest test-cat-parser-lookup-compound-no-dict ()
  "Test compound lookup when dict not loaded."
  (let ((cat-parser-compounds-dict nil))
    (should-not (cat-parser-lookup-compound "གླེང་གཞི"))))

(ert-deftest test-cat-parser-lookup-proper-noun-no-dict ()
  "Test proper noun lookup when dict not loaded."
  (let ((cat-parser-proper-nouns-dict nil))
    (should-not (cat-parser-lookup-proper-noun "ནཱ་ལེནྡྲ"))))

;; ============================================================================
;; FORMATTING TESTS
;; ============================================================================

(ert-deftest test-cat-parser-format-multiword-unit ()
  "Test multiword unit formatting."
  (let ((unit '(0 2 "གླེང་གཞི" ((english . "nidana") (category . "compound")))))
    (let ((formatted (cat-parser-format-multiword-unit unit)))
      (should (stringp formatted))
      (should (string-match-p "གླེང་གཞི" formatted))
      (should (string-match-p "nidana" formatted)))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest test-cat-parser-parse-full-sentence ()
  "Test parsing a full Tibetan sentence."
  (let* ((text "མ་སྨད་ཀྱིས་དེའི་ཕྱོགས་སུ")
         (result (cat-parser-parse text))
         (words (cat-parse-result-words result))
         (segments (cat-parse-result-segments result)))
    (should (> (length words) 3))
    (should (>= (length segments) 1))))

(ert-deftest test-cat-parser-segments-equals-words-no-compounds ()
  "Test that segments equal words when no compounds detected."
  (let ((cat-parser-compounds-dict nil)
        (cat-parser-proper-nouns-dict nil)
        (tibetan-comprehensive-vocabulary nil))
    (let* ((result (cat-parser-parse "བདག་གིས་བྱས"))
           (words (cat-parse-result-words result))
           (segments (cat-parse-result-segments result)))
      (should (equal words segments)))))

(provide 'test-cat-parser)
;;; test-cat-parser.el ends here
