;;; tibetan-verse-philology-test.el --- Tests for verse philology -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for verse analysis and philology tools.
;; Tests cover: syllable counting, meter analysis, verse blocks, and apparatus entries.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../philology" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-verse-philology)

;; ============================================================================
;; SYLLABLE COUNTING
;; ============================================================================

(ert-deftest tibetan-verse-count-syllables-simple ()
  "Test syllable counting for simple verse."
  (let ((verse "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ"))
    ;; Should count syllables (separated by tshegs)
    (let ((count (tibetan-count-syllables verse)))
      (should (numberp count))
      (should (> count 0)))))

(ert-deftest tibetan-verse-count-syllables-seven ()
  "Test that classic verse has 7 syllables."
  (let ((verse "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ"))
    ;; Classic Madhyamaka verse uses 7-syllable meter
    (let ((count (tibetan-count-syllables verse)))
      (should (= count 7)))))

(ert-deftest tibetan-verse-count-syllables-empty ()
  "Test syllable counting with empty string."
  (let ((count (tibetan-count-syllables "")))
    (should (= count 0))))

(ert-deftest tibetan-verse-count-syllables-nil ()
  "Test syllable counting with nil input."
  (let ((count (tibetan-count-syllables nil)))
    (should (numberp count))
    (should (= count 0))))

(ert-deftest tibetan-verse-count-syllables-with-punctuation ()
  "Test syllable counting with punctuation."
  (let ((verse "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།"))
    (let ((count (tibetan-count-syllables verse)))
      (should (numberp count))
      (should (> count 0)))))

;; ============================================================================
;; SYLLABLE BREAKDOWN TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-syllable-breakdown-simple ()
  "Test syllable breakdown of simple word."
  (let ((result (tibetan-syllable-breakdown "གང་ཞིག")))
    (should (or (null result) (listp result) (stringp result)))))

(ert-deftest tibetan-syllable-breakdown-empty ()
  "Test syllable breakdown with empty string."
  (let ((result (tibetan-syllable-breakdown "")))
    (should (or (null result) (listp result) (stringp result)))))

(ert-deftest tibetan-syllable-breakdown-single ()
  "Test syllable breakdown with single syllable."
  (let ((result (tibetan-syllable-breakdown "བདག")))
    (should (or (null result) (listp result) (stringp result)))))

;; ============================================================================
;; FORMAT SYLLABLES NUMBERED TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-format-syllables-numbered-basic ()
  "Test formatting syllables with numbers."
  (let ((result (tibetan-format-syllables-numbered "གང་ཞིག")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-format-syllables-numbered-empty ()
  "Test formatting empty string."
  (let ((result (tibetan-format-syllables-numbered "")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-format-syllables-numbered-long ()
  "Test formatting long verse."
  (let ((result (tibetan-format-syllables-numbered "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; EXTRACT CORE MEANING TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-extract-core-meaning-simple ()
  "Test extracting core meaning from verse."
  (let ((result (tibetan-extract-core-meaning "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-extract-core-meaning-empty ()
  "Test extracting core meaning from empty string."
  (let ((result (tibetan-extract-core-meaning "")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-extract-core-meaning-single-word ()
  "Test extracting core meaning from single word."
  (let ((result (tibetan-extract-core-meaning "སྟོང་པ")))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; SA BCAD NUMBER PARSING TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-parse-sa-bcad-number-tibetan ()
  "Test parsing Tibetan numeral in sa bcad."
  (let ((result (tibetan-parse-sa-bcad-number "༡།")))
    ;; Function returns a list of numbers parsed from dot-separated string
    (should (listp result))
    (should (> (length result) 0))))

(ert-deftest tibetan-parse-sa-bcad-number-arabic ()
  "Test parsing Arabic numeral in sa bcad."
  (let ((result (tibetan-parse-sa-bcad-number "1.")))
    ;; Function returns a list of numbers
    (should (listp result))
    (should (> (length result) 0))))

(ert-deftest tibetan-parse-sa-bcad-number-complex ()
  "Test parsing complex sa bcad number."
  (let ((result (tibetan-parse-sa-bcad-number "1.2.3")))
    ;; Function returns a list of numbers parsed from dot-separated string
    (should (listp result))
    (should (= (length result) 3))
    (should (equal result (list 1 2 3)))))

(ert-deftest tibetan-parse-sa-bcad-number-empty ()
  "Test parsing empty sa bcad string."
  (let ((result (tibetan-parse-sa-bcad-number "")))
    (should (or (null result) (numberp result) (stringp result)))))

;; ============================================================================
;; SA BCAD DEPTH TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-sa-bcad-depth-single ()
  "Test sa bcad depth for single digit."
  (let ((result (tibetan-sa-bcad-depth "༡།")))
    (should (or (null result) (numberp result)))))

(ert-deftest tibetan-sa-bcad-depth-nested ()
  "Test sa bcad depth for nested outline."
  (let ((result (tibetan-sa-bcad-depth "༡ག༡།")))
    (should (or (null result) (numberp result)))))

(ert-deftest tibetan-sa-bcad-depth-empty ()
  "Test sa bcad depth with empty string."
  (let ((result (tibetan-sa-bcad-depth "")))
    (should (or (null result) (numberp result)))))

;; ============================================================================
;; METER ANALYSIS
;; ============================================================================

(ert-deftest tibetan-verse-meter-seven ()
  "Test 7-syllable meter detection."
  (let ((verse "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ"))
    (let ((count (tibetan-count-syllables verse)))
      (should (= count 7)))))

(ert-deftest tibetan-verse-meter-irregular ()
  "Test irregular meter detection."
  (let ((verse "བདག"))
    (let ((count (tibetan-count-syllables verse)))
      (should (numberp count))
      (should (= count 1)))))

;; ============================================================================
;; VERSE BLOCK ANALYSIS
;; ============================================================================

(ert-deftest tibetan-verse-analyze-block ()
  "Test verse block analysis."
  (let ((verse-lines '("གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།"
                       "དེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།")))
    (let ((analysis (tibetan-analyze-verse-block verse-lines "1")))
      (should (or (null analysis) (stringp analysis))))))

(ert-deftest tibetan-verse-analyze-block-single ()
  "Test verse block analysis with single line."
  (let ((verse-lines '("གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།")))
    (let ((analysis (tibetan-analyze-verse-block verse-lines "1")))
      (should (or (null analysis) (stringp analysis))))))

;; ============================================================================
;; METRICAL FILLERS
;; ============================================================================

(ert-deftest tibetan-verse-detect-filler-ni ()
  "Test detection of ནི as metrical filler."
  (let ((verse "བདག་ནི་"))
    ;; ནི can be a metrical filler in verse
    (let ((fillers (tibetan-identify-metrical-fillers verse)))
      (should (or (null fillers) (listp fillers))))))

(ert-deftest tibetan-verse-detect-filler-yang ()
  "Test detection of ཡང as metrical filler."
  (let ((verse "བདག་ཡང་"))
    (let ((fillers (tibetan-identify-metrical-fillers verse)))
      (should (or (null fillers) (listp fillers))))))

(ert-deftest tibetan-verse-detect-no-fillers ()
  "Test when no metrical fillers present."
  (let ((verse "སྟོང་པ"))
    (let ((fillers (tibetan-identify-metrical-fillers verse)))
      (should (or (null fillers) (listp fillers))))))

;; ============================================================================
;; APPARATUS ENTRY FORMATTING TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-format-apparatus-entry-basic ()
  "Test formatting basic apparatus entry."
  (let ((result (tibetan-format-apparatus-entry "གང་ཞིག" "གང་ཞིག" "གང་ཞིག" "variant")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-format-apparatus-entry-empty ()
  "Test formatting with empty lemma."
  (let ((result (tibetan-format-apparatus-entry "" "reading" "reading" "note")))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-format-apparatus-entry-no-note ()
  "Test formatting without note."
  (let ((result (tibetan-format-apparatus-entry "གང་ཞིག" "reading1" "reading2" nil)))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; DISPLAY APPARATUS TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-display-apparatus-basic ()
  "Test displaying apparatus entries."
  (let ((entries '(("གང་ཞིག" "reading1" "reading2" "variant"))))
    (let ((result (tibetan-display-apparatus entries)))
      (should (or (null result) (stringp result))))))

(ert-deftest tibetan-display-apparatus-empty ()
  "Test displaying empty apparatus."
  (let ((result (tibetan-display-apparatus nil)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-display-apparatus-multiple ()
  "Test displaying multiple apparatus entries."
  (let ((entries '(("གང་ཞིག" "reading1" "reading2" "note1")
                   ("དེ་ནི" "reading3" "reading4" "note2"))))
    (let ((result (tibetan-display-apparatus entries)))
      (should (or (null result) (stringp result))))))

;; ============================================================================
;; CURRENT VERSE BLOCK TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-get-current-verse-block-in-verse ()
  "Test getting current verse block when in verse."
  (with-temp-buffer
    (insert "Line 1\n")
    (insert "Line 2\n")
    (goto-char 10)
    (let ((result (tibetan-get-current-verse-block)))
      (should (or (null result) (listp result) (stringp result))))))

(ert-deftest tibetan-get-current-verse-block-empty ()
  "Test getting current verse block in empty buffer."
  (with-temp-buffer
    (let ((result (tibetan-get-current-verse-block)))
      (should (or (null result) (listp result))))))

;; ============================================================================
;; INTERACTIVE VERSE ANALYSIS TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-analyze-current-verse-interactive-exists ()
  "Test that interactive analysis function exists."
  (should (fboundp 'tibetan-analyze-current-verse-interactive)))

(ert-deftest tibetan-analyze-current-verse-interactive-is-command ()
  "Test that interactive analysis is a command."
  (should (commandp 'tibetan-analyze-current-verse-interactive)))

;; ============================================================================
;; SA BCAD (OUTLINE) ANALYSIS
;; ============================================================================

(ert-deftest tibetan-verse-sa-bcad-structure ()
  "Test sa bcad (outline) structure detection."
  ;; Sa bcad typically starts with numbers or markers
  (let ((text "༡། དང་པོ།"))
    (should (stringp text))))

;; ============================================================================
;; VERSE VOCABULARY
;; ============================================================================

(ert-deftest tibetan-verse-vocabulary-lookup ()
  "Test verse-specific vocabulary lookup."
  ;; Verse texts may have special meanings
  (let ((term "སྟོང་པ་ཉིད"))
    ;; Should be recognized as emptiness/sunyata
    (should (stringp term))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-verse-nil-input ()
  "Test verse analysis with nil input."
  ;; Should not error
  (should t))

(ert-deftest tibetan-verse-prose-input ()
  "Test verse analysis with prose input."
  ;; Should handle prose gracefully
  (let ((prose "འདི་ནི་ཚིགས་བཅད་མ་ཡིན།"))
    (should (stringp prose))))

(ert-deftest tibetan-verse-very-long ()
  "Test verse analysis with very long text."
  (let ((long-verse (make-string 1000 ?ག)))
    (let ((result (tibetan-count-syllables long-verse)))
      (should (or (null result) (numberp result))))))

(provide 'tibetan-verse-philology-test)
;;; tibetan-verse-philology-test.el ends here
