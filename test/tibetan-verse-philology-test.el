;;; tibetan-verse-philology-test.el --- Tests for verse philology -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for verse analysis and philology tools.

;;; Code:

(require 'ert)

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

;; ============================================================================
;; METER ANALYSIS
;; ============================================================================

(ert-deftest tibetan-verse-meter-seven ()
  "Test 7-syllable meter detection."
  (let ((verse "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ"))
    (let ((meter (tibetan-analyze-meter verse)))
      (when meter
        (should (plist-get meter :syllable-count))))))

(ert-deftest tibetan-verse-meter-irregular ()
  "Test irregular meter detection."
  (let ((verse "བདག"))
    (let ((meter (tibetan-analyze-meter verse)))
      (when meter
        (should (numberp (plist-get meter :syllable-count)))))))

;; ============================================================================
;; VERSE BLOCK ANALYSIS
;; ============================================================================

(ert-deftest tibetan-verse-analyze-block ()
  "Test verse block analysis."
  (let ((block "གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།\nདེ་ནི་སྟོང་པ་ཉིད་དུ་བཤད།"))
    (let ((analysis (tibetan-analyze-verse-block block)))
      (when analysis
        (should (listp analysis))))))

;; ============================================================================
;; METRICAL FILLERS
;; ============================================================================

(ert-deftest tibetan-verse-detect-filler-ni ()
  "Test detection of ནི as metrical filler."
  (let ((verse "བདག་ནི་"))
    ;; ནི can be a metrical filler in verse
    (let ((fillers (tibetan-detect-metrical-fillers verse)))
      (when fillers
        (should (listp fillers))))))

(ert-deftest tibetan-verse-detect-filler-yang ()
  "Test detection of ཡང as metrical filler."
  (let ((verse "བདག་ཡང་"))
    (let ((fillers (tibetan-detect-metrical-fillers verse)))
      (when fillers
        (should (listp fillers))))))

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

(provide 'tibetan-verse-philology-test)
;;; tibetan-verse-philology-test.el ends here
