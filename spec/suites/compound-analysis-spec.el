;;; compound-analysis-spec.el --- BDD specs for compound/verse analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for compound (multi-line) analysis feature.
;; Tests verse detection, block markers, and aggregated analysis.

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; COMPOUND ANALYSIS SUITE
;; ============================================================================

(define-bdd-suite compound-analysis
    "Compound/verse analysis (C-c v A)"

  ;; --- Block Marker Detection ---
  (spec "Detect 〔sent〕...〔/sent〕 block"
    :given (setq test-buffer-content "〔sent〕\n〔seg〕Test〔/seg〕\n〔/sent〕")
    :when (with-temp-buffer
            (insert test-buffer-content)
            (goto-char 20)
            (when (fboundp 'tibetan-compound--detect-block-markers)
              (tibetan-compound--detect-block-markers "sent")))
    :then ((should result)
           (should (consp result)))
    :example "Sentence block"
    :tags (:block-detection))

  (spec "Detect 〔verse :num N〕...〔/verse〕 block"
    :given (setq test-buffer-content "〔verse :num 1〕\nརིགས་ཅན་གསུམ།\n〔/verse〕")
    :when (with-temp-buffer
            (insert test-buffer-content)
            (goto-char 20)
            (when (fboundp 'tibetan-compound--detect-block-markers)
              (tibetan-compound--detect-block-markers "verse")))
    :then ((should result))
    :example "Verse block"
    :tags (:block-detection))

  (spec "Detect 〔prose :comment-on N〕 block"
    :given (setq test-buffer-content "〔prose :comment-on 1〕\nCommentary\n〔/prose〕")
    :when (with-temp-buffer
            (insert test-buffer-content)
            (goto-char 25)
            (when (fboundp 'tibetan-compound--detect-block-markers)
              (tibetan-compound--detect-block-markers "prose")))
    :then ((should result))
    :example "Prose commentary block"
    :tags (:block-detection))

  (spec "Return nil when outside any block"
    :given (setq test-buffer-content "Before\n〔sent〕Inside〔/sent〕\nAfter")
    :when (with-temp-buffer
            (insert test-buffer-content)
            (goto-char 3)
            (when (fboundp 'tibetan-compound--detect-block-markers)
              (tibetan-compound--detect-block-markers "sent")))
    :then ((should (null result)))
    :example "Position before block"
    :tags (:block-detection :edge-cases))

  ;; --- Multi-line Aggregation ---
  (spec "Aggregate vocabulary across verse lines"
    :given (setq test-verse "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ།")
    :when (when (and (fboundp 'tibetan-parse-enhanced)
                     (fboundp 'tibetan-build-compound-aware-segments))
            (let* ((parsed (tibetan-parse-enhanced test-verse))
                   (words (alist-get 'words parsed))
                   (multiword (alist-get 'multiword-units parsed)))
              (tibetan-build-compound-aware-segments words multiword)))
    :then ((should (listp result))
           (tibetan-bdd-assert-count-gte result 3 "Should have multiple segments"))
    :example "Verse line with compounds"
    :tags (:aggregation))

  ;; --- Verse Meter Detection ---
  (spec "Count syllables for meter validation"
    :given (setq test-line "རིགས་ཅན་གསུམ་གྱི་གདུལ་བྱ་ལ།")
    :when (when (fboundp 'tibetan-count-syllables)
            (tibetan-count-syllables test-line))
    :then ((should (numberp result)))
    :example "7-syllable verse line"
    :tags (:meter))

  ;; --- Function Existence ---
  (spec "tibetan-open-compound-analysis exists"
    :given nil
    :when (fboundp 'tibetan-open-compound-analysis)
    :then ((should result))
    :tags (:api))

  (spec "tibetan-reanalyze-compound exists"
    :given nil
    :when (fboundp 'tibetan-reanalyze-compound)
    :then ((should result))
    :tags (:api)))

(provide 'compound-analysis-spec)
;;; compound-analysis-spec.el ends here
