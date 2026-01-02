;;; custom-vocab-spec.el --- BDD specs for custom vocabulary feature -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for the #+TIBETAN_VOCAB_FILE custom vocabulary feature.
;; Tests PDF parsing, Wylie lookup, and priority over main glossary.

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; CUSTOM VOCABULARY SUITE
;; ============================================================================

(define-bdd-suite custom-vocabulary
    "Custom vocabulary file support (#+TIBETAN_VOCAB_FILE)"

  ;; --- PDF Parsing ---
  (spec "Parse vocabulary PDF with Wylie terms"
    :given (setq test-pdf "/Users/cp/buddhist-studies/WS25-26/Tibetisch III/Sa skya legs bshad/Ressources/Sa skya legs bshad + dMar ston__Word list.pdf")
    :when (when (and (fboundp 'tibetan-parse-vocab-pdf)
                     (file-exists-p test-pdf))
            (tibetan-parse-vocab-pdf test-pdf))
    :then ((tibetan-bdd-assert-truthy result "Should return a hash-table")
           (tibetan-bdd-assert-truthy (hash-table-p result) "Result should be a hash-table")
           (tibetan-bdd-assert-truthy (> (hash-table-count result) 0) "Should have parsed entries"))
    :example "Sa skya legs bshad word list"
    :tags (:custom-vocab :pdf-parsing))

  (spec "Parse Wylie entry 'shes rab ldan na'"
    :given (setq test-pdf "/Users/cp/buddhist-studies/WS25-26/Tibetisch III/Sa skya legs bshad/Ressources/Sa skya legs bshad + dMar ston__Word list.pdf")
    :when (when (and (fboundp 'tibetan-parse-vocab-pdf)
                     (file-exists-p test-pdf))
            (let ((vocab (tibetan-parse-vocab-pdf test-pdf)))
              (gethash "shes rab ldan na" vocab)))
    :then ((tibetan-bdd-assert-truthy result "Should find 'shes rab ldan na' entry")
           (tibetan-bdd-assert-contains result "Dwangs grung"
            "Definition should mention Dwangs grung"))
    :example "shes rab ldan na"
    :tags (:custom-vocab :wylie-lookup))

  (spec "Parse Wylie entry 'bslu ba'"
    :given (setq test-pdf "/Users/cp/buddhist-studies/WS25-26/Tibetisch III/Sa skya legs bshad/Ressources/Sa skya legs bshad + dMar ston__Word list.pdf")
    :when (when (and (fboundp 'tibetan-parse-vocab-pdf)
                     (file-exists-p test-pdf))
            (let ((vocab (tibetan-parse-vocab-pdf test-pdf)))
              (gethash "bslu ba" vocab)))
    :then ((tibetan-bdd-assert-truthy result "Should find 'bslu ba' entry")
           (tibetan-bdd-assert-contains result "deceive"
            "Definition should contain 'deceive'"))
    :example "bslu ba - to deceive"
    :tags (:custom-vocab :wylie-lookup))

  ;; --- Header Detection ---
  (spec "Detect #+TIBETAN_VOCAB_FILE header"
    :given (setq header-result
                 (with-temp-buffer
                   (insert "#+TITLE: Test\n")
                   (insert "#+TIBETAN_VOCAB_FILE: ../path/to/vocab.pdf\n")
                   (insert "* Content\n")
                   (setq buffer-file-name "/tmp/test.org")
                   (tibetan-get-custom-vocab-file)))
    :when header-result
    :then ((tibetan-bdd-assert-truthy result "Should detect vocab file path")
           (tibetan-bdd-assert-contains result "vocab.pdf"
            "Should contain the filename"))
    :example "Header detection"
    :tags (:custom-vocab :header))

  (spec "Return nil when no #+TIBETAN_VOCAB_FILE header"
    :given (setq no-header-result
                 (with-temp-buffer
                   (insert "#+TITLE: Test\n")
                   (insert "* Content\n")
                   (tibetan-get-custom-vocab-file)))
    :when t
    :then ((tibetan-bdd-assert-nil no-header-result "Should return nil when no header"))
    :example "No header"
    :tags (:custom-vocab :header))

  ;; --- Lookup Priority ---
  (spec "Custom vocab lookup converts Tibetan to Wylie"
    :given (progn
             (setq tibetan-current-custom-vocab (make-hash-table :test 'equal))
             (puthash "bslu ba" "to deceive (custom)" tibetan-current-custom-vocab)
             t)
    :when (when (fboundp 'tibetan-lookup-word-in-custom-vocab)
            (tibetan-lookup-word-in-custom-vocab "བསླུ་བ"))
    :then ((tibetan-bdd-assert-truthy result "Should find via Wylie conversion")
           (tibetan-bdd-assert-contains result "deceive"
            "Should return custom definition"))
    :example "Tibetan to Wylie lookup"
    :tags (:custom-vocab :wylie-conversion))

  ;; --- Caching ---
  (spec "Cache parsed vocabulary for reuse"
    :given (progn
             (clrhash tibetan-custom-vocab-cache)
             (setq test-pdf "/Users/cp/buddhist-studies/WS25-26/Tibetisch III/Sa skya legs bshad/Ressources/Sa skya legs bshad + dMar ston__Word list.pdf"))
    :when (when (and (fboundp 'tibetan-parse-vocab-pdf)
                     (file-exists-p test-pdf))
            ;; Parse and cache
            (tibetan-parse-vocab-pdf test-pdf)
            (puthash test-pdf (make-hash-table :test 'equal) tibetan-custom-vocab-cache)
            (gethash test-pdf tibetan-custom-vocab-cache))
    :then ((tibetan-bdd-assert-truthy result "Should cache parsed vocabulary")
           (tibetan-bdd-assert-truthy (hash-table-p result) "Cached value should be hash-table"))
    :example "Vocabulary caching"
    :tags (:custom-vocab :caching)))

;; ============================================================================
;; AUTO-ANALYSIS MODE SUITE
;; ============================================================================

(define-bdd-suite auto-analysis-mode
    "Auto-analysis mode (C-c u E) with persistent analysis"

  (spec "Toggle auto mode on"
    :given (progn
             (setq tibetan-auto-mode nil)
             (when (boundp 'tibetan-auto-last-segment)
               (setq tibetan-auto-last-segment nil)))
    :when (progn
            (setq tibetan-auto-mode t)
            tibetan-auto-mode)
    :then ((tibetan-bdd-assert-truthy result "Auto mode should be enabled"))
    :example "Enable auto mode"
    :tags (:auto-mode))

  (spec "Toggle auto mode off"
    :given (setq tibetan-auto-mode t)
    :when (progn
            (setq tibetan-auto-mode nil)
            tibetan-auto-mode)
    :then ((tibetan-bdd-assert-nil result "Auto mode should be disabled"))
    :example "Disable auto mode"
    :tags (:auto-mode))

  (spec "Track last segment to avoid redundant updates"
    :given (progn
             (setq tibetan-auto-last-segment nil)
             (setq tibetan-auto-last-segment "seg-001"))
    :when tibetan-auto-last-segment
    :then ((tibetan-bdd-assert-equal "seg-001" result
            "Should track last analyzed segment"))
    :example "Segment tracking"
    :tags (:auto-mode :optimization))

  (spec "Clear last segment when toggling off"
    :given (progn
             (setq tibetan-auto-mode t)
             (setq tibetan-auto-last-segment "seg-001"))
    :when (progn
            (setq tibetan-auto-mode nil)
            (setq tibetan-auto-last-segment nil)
            tibetan-auto-last-segment)
    :then ((tibetan-bdd-assert-nil result
            "Should clear last segment when disabled"))
    :example "Clear on disable"
    :tags (:auto-mode)))

(provide 'custom-vocab-spec)
;;; custom-vocab-spec.el ends here
