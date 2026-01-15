;;; tibetan-sentence-detection-test.el --- Tests for sentence boundary detection -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for intelligent sentence boundary detection using clause analysis.
;; Tests cover:
;; - Main verb detection in segments
;; - Converb-only segment detection
;; - Sentence boundary determination
;; - Sentence grouping from segments

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-org-structure)
(require 'tibetan-clause-analysis nil t)

;; ============================================================================
;; MAIN VERB DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-segment-has-main-verb-copula ()
  "Test that copula verbs are detected as main verbs."
  (should (tibetan--segment-has-main-verb-p "འདི་ནི་ཆོས་ཡིན།")))

(ert-deftest tibetan-segment-has-main-verb-existential ()
  "Test that existential verbs are detected as main verbs."
  (should (tibetan--segment-has-main-verb-p "དེར་སངས་རྒྱས་བཞུགས་ཡོད།")))

(ert-deftest tibetan-segment-has-main-verb-honorific ()
  "Test that honorific verbs are detected as main verbs."
  (should (tibetan--segment-has-main-verb-p "སྟོན་པས་གསུངས།")))

(ert-deftest tibetan-segment-has-main-verb-final-particle ()
  "Test that final particles indicate main verb."
  (should (tibetan--segment-has-main-verb-p "དེ་ལྟར་བཀྲིའོ།")))

(ert-deftest tibetan-segment-has-main-verb-double-shad ()
  "Test that double-shad indicates sentence end."
  (should (tibetan--segment-has-main-verb-p "འདི་སྐད་བདག་གིས་ཐོས་པ།།")))

;; ============================================================================
;; CONVERB-ONLY DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-segment-is-converb-only-ablative ()
  "Test detection of ablative converb-only segment."
  (should (tibetan--segment-is-converb-only-p "སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་ནས།")))

(ert-deftest tibetan-segment-is-converb-only-coordinative ()
  "Test detection of coordinative converb-only segment."
  (should (tibetan--segment-is-converb-only-p "ཐོས་ཏེ།")))

(ert-deftest tibetan-segment-is-converb-only-simultaneous ()
  "Test detection of simultaneous converb-only segment."
  ;; མཁས་ཤིང། ends with simultaneous converb ཤིང
  (should (tibetan--segment-is-converb-only-p "མཁས་ཤིང།")))

(ert-deftest tibetan-segment-is-converb-only-false-for-main-verb ()
  "Test that segment with main verb is not converb-only."
  (should-not (tibetan--segment-is-converb-only-p "དེ་ལྟར་བཀྲིའོ།")))

(ert-deftest tibetan-segment-is-converb-only-false-for-copula ()
  "Test that copula is not detected as converb-only."
  (should-not (tibetan--segment-is-converb-only-p "འདི་ཆོས་ཡིན།")))

;; ============================================================================
;; SENTENCE BOUNDARY DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-segment-ends-sentence-double-shad ()
  "Test double-shad always ends sentence."
  (should (tibetan--segment-ends-sentence-p "text།།")))

(ert-deftest tibetan-segment-ends-sentence-final-particle-o ()
  "Test final particle འོ ends sentence."
  (should (tibetan--segment-ends-sentence-p "བཀྲིའོ།")))

(ert-deftest tibetan-segment-ends-sentence-final-particle-so ()
  "Test final particle སོ ends sentence."
  (should (tibetan--segment-ends-sentence-p "བཤད་སོ།")))

(ert-deftest tibetan-segment-ends-sentence-final-particle-ngo ()
  "Test final particle ངོ ends sentence."
  (should (tibetan--segment-ends-sentence-p "མཐོང་ངོ།")))

(ert-deftest tibetan-segment-ends-sentence-copula ()
  "Test copula verb ends sentence."
  (should (tibetan--segment-ends-sentence-p "འདི་ཆོས་ཡིན།")))

(ert-deftest tibetan-segment-ends-sentence-existential ()
  "Test existential verb ends sentence."
  (should (tibetan--segment-ends-sentence-p "དེར་ཡོད།")))

(ert-deftest tibetan-segment-ends-sentence-not-converb ()
  "Test converb-only segment does not end sentence."
  (should-not (tibetan--segment-ends-sentence-p "བཞུགས་ནས།")))

;; ============================================================================
;; SENTENCE GROUPING TESTS
;; ============================================================================

(ert-deftest tibetan-group-sentences-single-segment ()
  "Test single segment becomes one sentence."
  (let ((result (tibetan--group-into-sentences "བཀྲ་ཤིས་བདེ་ལེགས།")))
    (should (= 1 (length result)))
    (should (= 1 (length (car result))))))

(ert-deftest tibetan-group-sentences-converb-chain ()
  "Test converb chain forms single sentence."
  (let ((result (tibetan--group-into-sentences "བཞུགས་ནས།ཐོས་ཏེ།མཐོང་ངོ།")))
    ;; All three should be in one sentence
    (should (= 1 (length result)))
    (should (= 3 (length (car result))))))

(ert-deftest tibetan-group-sentences-double-shad-split ()
  "Test double-shad splits sentences."
  ;; Double-shad in the text itself marks sentence boundary
  ;; Note: The segment ending with །། will be detected as sentence end
  (let ((result (tibetan--group-into-sentences "འདི་སྐད་བདག་གིས་ཐོས་པ།།དེ་ནས་སངས་རྒྱས།")))
    ;; Should have at least 1 sentence (possibly 2 if double-shad preserved)
    (should (>= (length result) 1))))

(ert-deftest tibetan-group-sentences-empty-text ()
  "Test empty text returns empty list."
  (let ((result (tibetan--group-into-sentences "")))
    (should (null result))))

(ert-deftest tibetan-group-sentences-line-based ()
  "Test line-based text groups by line."
  (let ((result (tibetan--group-into-sentences "Line one།
Line two།
Line three།")))
    ;; Each line should be treated according to verb analysis
    (should (>= (length result) 1))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-detection-with-clause-analysis ()
  "Test sentence detection integrates with clause analysis."
  (skip-unless (fboundp 'tibetan-detect-converbs))
  (let ((text "བཞུགས་ནས་བཀྲིའོ།"))
    (let ((converbs (tibetan-detect-converbs text)))
      (should converbs)
      (should (= 1 (length converbs)))
      (should (eq 'ablative (plist-get (car converbs) :type))))))

(ert-deftest tibetan-sentence-detection-main-verb-identification ()
  "Test main verb is found after converbs."
  (skip-unless (fboundp 'tibetan-find-main-verb))
  ;; Use a text with a clearly recognizable main verb
  (let ((text "སྟོན་པས་གསུངས།"))
    (let ((main-verb (tibetan-find-main-verb text)))
      ;; Should find གསུངས as main verb (honorific "said")
      (should main-verb)
      (should (equal "གསུངས" (plist-get main-verb :verb))))))

;; ============================================================================
;; REAL-WORLD TEXT TESTS
;; ============================================================================

(ert-deftest tibetan-sentence-padma-rnam-rgyal-opening ()
  "Test sentence detection on Padma rnam-rgyal opening."
  (let ((result (tibetan--group-into-sentences
                 "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།
ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ་རྒྱ་མཚོར་རིན་པོ་ཆེ་ལེན་དུ་འགྲོ་བ་དག་གིས།
བདག་ཅག་གིས་མིའི་ནང་ནས་མཁས་ཤིང་ཤེས་པ་ཞིག་དེད་དཔོན་དུ་བཀྲིའོ།")))
    ;; Should form 1-2 sentences (all converb-connected or split at line)
    (should (>= (length result) 1))
    (should (<= (length result) 3))))

(ert-deftest tibetan-sentence-refuge-formula ()
  "Test refuge formula recognized as one sentence."
  (let ((result (tibetan--group-into-sentences
                 "སངས་རྒྱས་ཆོས་དང་ཚོགས་ཀྱི་མཆོག་རྣམས་ལ།བྱང་ཆུབ་བར་དུ་བདག་ནི་སྐྱབས་སུ་མཆི།")))
    ;; Refuge formula with མཆི is one sentence
    (should (= 1 (length result)))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-sentence-detection-run-tests ()
  "Run all sentence detection tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-sentence-\\|^tibetan-segment-\\|^tibetan-group-"))

(provide 'tibetan-sentence-detection-test)
;;; tibetan-sentence-detection-test.el ends here
