;;; sentence-detection-spec.el --- BDD specs for sentence boundary detection -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for intelligent sentence boundary detection using
;; clause analysis (main verb identification).
;;
;; Sentence boundaries are determined by:
;; 1. Double-shad (།།) - always a sentence boundary
;; 2. Main verb detection - segment with main verb (not converb) ends sentence
;; 3. Final particles (སོ། འོ། etc.) - sentence-final markers

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; SENTENCE BOUNDARY DETECTION SUITE
;; ============================================================================

(define-bdd-suite sentence-boundary-detection
    "Intelligent sentence boundary detection"

  ;; --- Main Verb Detection ---
  (spec "Detect main verb marks sentence end"
    :given (setq test-segment "བདག་ཅག་གིས་མིའི་ནང་ནས་མཁས་ཤིང་ཤེས་པ་ཞིག་དེད་དཔོན་དུ་བཀྲིའོ།")
    :when (tibetan--segment-has-main-verb-p test-segment)
    :then ((should result))
    :example "Segment with main verb བཀྲི"
    :tags (:sentence :main-verb))

  (spec "Converb-only segment does not end sentence"
    :given (setq test-segment "སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་ནས།")
    :when (tibetan--segment-is-converb-only-p test-segment)
    :then ((should result))
    :example "Segment ending with ablative converb ནས"
    :tags (:sentence :converb))

  (spec "Coordinative converb does not end sentence"
    :given (setq test-segment "རྒྱ་མཚོར་རིན་པོ་ཆེ་ལེན་དུ་འགྲོ་བ་དག་གིས་སྟེ།")
    :when (tibetan--segment-is-converb-only-p test-segment)
    :then ((should result))
    :example "Segment with coordinative སྟེ"
    :tags (:sentence :converb :coordinative))

  (spec "Double-shad always marks sentence end"
    :given (setq test-segment "འདི་སྐད་བདག་གིས་ཐོས་པ་དུས་གཅིག་ན།།")
    :when (tibetan--segment-ends-sentence-p test-segment)
    :then ((should result))
    :example "Double-shad boundary"
    :tags (:sentence :double-shad :critical))

  (spec "Final particle marks sentence end"
    :given (setq test-segment "དེ་ལྟར་བཀྲིའོ།")
    :when (tibetan--segment-ends-sentence-p test-segment)
    :then ((should result))
    :example "Final particle འོ"
    :tags (:sentence :final-particle))

  ;; --- Sentence Grouping ---
  (spec "Group segments by main verb"
    :given (setq test-text "སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་ནས།ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ་བཀྲིའོ།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (= 1 (length result)))
           (should (= 2 (length (car result)))))
    :example "Two segments forming one sentence"
    :tags (:sentence :grouping))

  (spec "Split on double-shad boundary"
    :given (setq test-text "འདི་སྐད་བདག་གིས་ཐོས་པ།།དེ་ནས་སངས་རྒྱས།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (>= (length result) 1)))
    :example "Double-shad separates sentences"
    :tags (:sentence :grouping :double-shad))

  (spec "Converb segments stay in same sentence"
    :given (setq test-text "བཞུགས་ནས།ཐོས་ཏེ།མཐོང་ངོ།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (= 1 (length result)))
           (should (= 3 (length (car result)))))
    :example "Converbs chain to final main verb"
    :tags (:sentence :grouping :converb-chain))

  ;; --- Real-World Text Tests ---
  (spec "Padma rnam-rgyal opening sentences"
    :given (setq test-text "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།
ཡུལ་དེའི་ཚོང་པ་ལྔ་བརྒྱ་རྒྱ་མཚོར་རིན་པོ་ཆེ་ལེན་དུ་འགྲོ་བ་དག་གིས།
བདག་ཅག་གིས་མིའི་ནང་ནས་མཁས་ཤིང་ཤེས་པ་ཞིག་དེད་དཔོན་དུ་བཀྲིའོ།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (>= (length result) 1))
           ;; All 3 lines should form one or two sentences max
           (should (<= (length result) 2)))
    :example "Ocean Deity story opening"
    :tags (:sentence :real-world :padma-rnam-rgyal))

  (spec "Refuge formula as complete sentence"
    :given (setq test-text "སངས་རྒྱས་ཆོས་དང་ཚོགས་ཀྱི་མཆོག་རྣམས་ལ།བྱང་ཆུབ་བར་དུ་བདག་ནི་སྐྱབས་སུ་མཆི།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (= 1 (length result))))
    :example "Buddhist refuge verse"
    :tags (:sentence :real-world :refuge))

  ;; --- Edge Cases ---
  (spec "Single segment is one sentence"
    :given (setq test-text "བཀྲ་ཤིས་བདེ་ལེགས།")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (= 1 (length result)))
           (should (= 1 (length (car result)))))
    :example "Simple greeting"
    :tags (:sentence :edge-case))

  (spec "Empty text returns empty list"
    :given (setq test-text "")
    :when (tibetan--group-into-sentences test-text)
    :then ((should (null result)))
    :tags (:sentence :edge-case))

  (spec "Copula verb ends sentence"
    :given (setq test-segment "འདི་ནི་ཆོས་ཡིན།")
    :when (tibetan--segment-ends-sentence-p test-segment)
    :then ((should result))
    :example "Copula ཡིན marks sentence end"
    :tags (:sentence :copula))

  (spec "Existential verb ends sentence"
    :given (setq test-segment "དེར་སངས་རྒྱས་བཞུགས་ཡོད།")
    :when (tibetan--segment-ends-sentence-p test-segment)
    :then ((should result))
    :example "Existential ཡོད marks sentence end"
    :tags (:sentence :existential)))

;; ============================================================================
;; SENTENCE ANALYSIS INTEGRATION SUITE
;; ============================================================================

(define-bdd-suite sentence-analysis-integration
    "Integration between sentence detection and clause analysis"

  (spec "Sentence analysis uses clause tree"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Test\n** Sentence 1\n*** Segment 1\nབཞུགས་ནས།\n*** Segment 2\nབཀྲིའོ།\n")
             (goto-char (point-min))
             (search-forward "** Sentence 1")
             (beginning-of-line)
             (setq result (tibetan-org-get-sentence-text)))
    :when result
    :then ((should result)
           (should (string-match-p "བཞུགས" result))
           (should (string-match-p "བཀྲི" result)))
    :example "Combined text for clause analysis"
    :tags (:integration :clause-analysis))

  (spec "Detect converb structure in sentence"
    :given (setq test-text "བཞུགས་ནས་བཀྲིའོ།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (= 1 (length result)))
           (should (eq 'ablative (plist-get (car result) :type))))
    :example "Ablative converb in sentence"
    :tags (:integration :converb)))

(provide 'sentence-detection-spec)
;;; sentence-detection-spec.el ends here
