;;; auto-analysis-spec.el --- BDD specs for auto-analysis feature -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for automatic batch analysis generation.
;; After tibetan-prepare-document, users can run auto-analysis to
;; pre-generate all segment and sentence analysis files.

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; AUTO-ANALYSIS SUITE
;; ============================================================================

(define-bdd-suite auto-analysis
    "Automatic analysis generation"

  ;; --- Segment Analysis Generation ---
  (spec "Generate analysis for single segment"
    :given (setq test-text "བཀྲ་ཤིས་བདེ་ལེགས།")
    :when (tibetan-analysis-generate-content test-text)
    :then ((should result)
           (should (stringp result))
           (tibetan-bdd-assert-contains result "** Wylie Transliteration"
            "Should have Wylie Transliteration section"))
    :example "Simple greeting analysis"
    :tags (:auto-analysis :segment))

  (spec "Count segments in document"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Sentence 1\n*** Segment 1\ntext1\n*** Segment 2\ntext2\n")
             (setq result (tibetan-auto--count-segments)))
    :when result
    :then ((should (= 2 result)))
    :example "Document with 2 segments"
    :tags (:auto-analysis :count))

  (spec "Collect segments for batch processing"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Sentence 1\n*** Segment 1\nབཀྲ་ཤིས།\n*** Segment 2\nབདེ་ལེགས།\n")
             (goto-char (point-min))
             (setq result (tibetan-auto--collect-segments)))
    :when result
    :then ((should (= 2 (length result)))
           (should (assoc 1 result))
           (should (assoc 2 result)))
    :example "Collecting segment data"
    :tags (:auto-analysis :collect))

  ;; --- Sentence Analysis Generation ---
  (spec "Generate sentence analysis file"
    :given (setq test-text "བཞུགས་ནས་བཀྲིའོ།")
    :when (tibetan-auto--generate-sentence-analysis 1 test-text)
    :then ((should result)
           (should (stringp result))
           (tibetan-bdd-assert-contains result "Clause Structure"
            "Should have clause structure"))
    :example "Sentence clause analysis"
    :tags (:auto-analysis :sentence))

  (spec "Count sentences in document"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Title\n** Sentence 1\n*** Segment 1\ntext\n** Sentence 2\n*** Segment 2\ntext\n")
             (setq result (tibetan-auto--count-sentences)))
    :when result
    :then ((should (= 2 result)))
    :example "Document with 2 sentences"
    :tags (:auto-analysis :count :sentence))

  ;; --- Batch Processing ---
  (spec "Auto-analyze skips existing files"
    :given (progn
             (setq tibetan-auto-skip-existing t)
             ;; Create a temp file that exists
             (setq test-file (make-temp-file "tibetan-test-skip"))
             (setq result (tibetan-auto--should-skip-p test-file))
             (delete-file test-file))
    :when result
    :then ((should result))
    :example "Skip existing when configured"
    :tags (:auto-analysis :skip))

  (spec "Auto-analyze respects force flag"
    :given (progn
             ;; When skip-existing is nil, we don't skip
             (setq tibetan-auto-skip-existing nil)
             (setq test-file (make-temp-file "tibetan-test-force"))
             (setq result (tibetan-auto--should-skip-p test-file))
             (delete-file test-file))
    :when result
    :then ((should-not result))
    :example "Force regeneration overrides skip"
    :tags (:auto-analysis :force))

  ;; --- Integration ---
  (spec "Analysis folder is created"
    :given (let ((temp-dir (make-temp-file "tibetan-test" t)))
             (with-temp-buffer
               (setq buffer-file-name (expand-file-name "test.org" temp-dir))
               (setq result (tibetan-analysis-get-folder))))
    :when result
    :then ((should result)
           (should (file-directory-p result)))
    :example "Analysis directory creation"
    :tags (:auto-analysis :folder)))

;; ============================================================================
;; PROGRESS REPORTING SUITE
;; ============================================================================

(define-bdd-suite auto-analysis-progress
    "Progress reporting for batch analysis"

  (spec "Progress callback is invoked"
    :given (let ((progress-calls 0))
             (tibetan-auto--with-progress
                 (lambda (current total msg)
                   (setq progress-calls (1+ progress-calls)))
                 3
               ;; Body of macro - directly call report-progress
               (dotimes (i 3)
                 (tibetan-auto--report-progress (1+ i) 3 "Processing")))
             (setq result progress-calls))
    :when result
    :then ((should (= 3 result)))
    :example "Progress callback invoked for each item"
    :tags (:progress :callback)))

(provide 'auto-analysis-spec)
;;; auto-analysis-spec.el ends here
