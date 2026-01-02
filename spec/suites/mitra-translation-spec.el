;;; mitra-translation-spec.el --- BDD specs for Mitra AI translation -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for Gemma-2-Mitra-E integration

;;; Code:

(require 'tibetan-bdd)
(require 'tibetan-mitra-translation nil t)

;; ============================================================================
;; MITRA CONFIGURATION SUITE
;; ============================================================================

(define-bdd-suite mitra-configuration
    "Gemma-2-Mitra-E configuration and setup"

  (spec "Default backend is Ollama"
    :given (boundp 'tibetan-mitra-backend)
    :when (setq result tibetan-mitra-backend)
    :then ((tibetan-bdd-assert-equal result 'ollama "Default backend should be ollama")))

  (spec "Default Ollama URL is localhost"
    :given (boundp 'tibetan-mitra-ollama-url)
    :when (setq result tibetan-mitra-ollama-url)
    :then ((tibetan-bdd-assert-equal result "http://localhost:11434" "Default Ollama URL")))

  (spec "HuggingFace model is billingsmoore/gemma-2-2b-mitra-e"
    :given (boundp 'tibetan-mitra-huggingface-model)
    :when (setq result tibetan-mitra-huggingface-model)
    :then ((tibetan-bdd-assert-equal result "billingsmoore/gemma-2-2b-mitra-e" "HF model ID")))

  (spec "Cache is enabled by default"
    :given (boundp 'tibetan-mitra-cache-enabled)
    :when (setq result tibetan-mitra-cache-enabled)
    :then ((tibetan-bdd-assert-truthy result "Cache should be enabled")))

  (spec "Timeout is reasonable"
    :given (boundp 'tibetan-mitra-timeout)
    :when (setq result tibetan-mitra-timeout)
    :then ((tibetan-bdd-assert-truthy (>= result 10) "Timeout should be >= 10 seconds"))))

;; ============================================================================
;; MITRA CACHE SUITE
;; ============================================================================

(define-bdd-suite mitra-cache
    "Mitra translation cache functionality"

  (spec "Cache is a hash table"
    :given (boundp 'tibetan-mitra--cache)
    :when (setq result tibetan-mitra--cache)
    :then ((tibetan-bdd-assert-truthy (hash-table-p result) "Cache should be hash table")))

  (spec "Clear cache empties the cache"
    :given (progn
             (setq tibetan-mitra--cache (make-hash-table :test 'equal))
             (puthash "test" "value" tibetan-mitra--cache))
    :when (tibetan-mitra-clear-cache)
    :then ((tibetan-bdd-assert-equal (hash-table-count tibetan-mitra--cache) 0 "Cache should be empty"))))

;; ============================================================================
;; MITRA FUNCTION AVAILABILITY SUITE
;; ============================================================================

(define-bdd-suite mitra-functions
    "Mitra translation functions availability"

  (spec "tibetan-mitra-translate is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-translate))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "tibetan-mitra-translate-async is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-translate-async))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "tibetan-mitra-translate-region is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-translate-region))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "tibetan-mitra-translate-dwim is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-translate-dwim))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "tibetan-mitra-check-status is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-check-status))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "tibetan-mitra-setup-ollama is defined"
    :given t
    :when (setq result (fboundp 'tibetan-mitra-setup-ollama))
    :then ((tibetan-bdd-assert-truthy result "Function should be defined")))

  (spec "Ollama backend function exists"
    :given t
    :when (setq result (fboundp 'tibetan-mitra--ollama-translate))
    :then ((tibetan-bdd-assert-truthy result "Ollama translate should exist")))

  (spec "HuggingFace backend function exists"
    :given t
    :when (setq result (fboundp 'tibetan-mitra--huggingface-translate))
    :then ((tibetan-bdd-assert-truthy result "HF translate should exist")))

  (spec "Local server backend function exists"
    :given t
    :when (setq result (fboundp 'tibetan-mitra--local-server-translate))
    :then ((tibetan-bdd-assert-truthy result "Local translate should exist"))))

;; ============================================================================
;; MITRA INPUT VALIDATION SUITE
;; ============================================================================

(define-bdd-suite mitra-validation
    "Mitra input validation"

  (spec "Rejects nil input"
    :given t
    :when (setq result (condition-case nil
                           (progn (tibetan-mitra-translate nil) nil)
                         (error t)))
    :then ((tibetan-bdd-assert-truthy result "Should throw error for nil")))

  (spec "Rejects empty string"
    :given t
    :when (setq result (condition-case nil
                           (progn (tibetan-mitra-translate "") nil)
                         (error t)))
    :then ((tibetan-bdd-assert-truthy result "Should throw error for empty string")))

  (spec "Rejects whitespace-only input"
    :given t
    :when (setq result (condition-case nil
                           (progn (tibetan-mitra-translate "   ") nil)
                         (error t)))
    :then ((tibetan-bdd-assert-truthy result "Should throw error for whitespace"))))

;; ============================================================================
;; MITRA DISPLAY FORMATTING SUITE
;; ============================================================================

(define-bdd-suite mitra-display
    "Mitra display formatting"

  (spec "format-for-display handles nil"
    :given t
    :when (setq result (tibetan-mitra-format-for-display nil))
    :then ((tibetan-bdd-assert-truthy (stringp result) "Should return string for nil")))

  (spec "format-for-display includes emoji marker"
    :given t
    :when (setq result (tibetan-mitra-format-for-display "test translation"))
    :then ((tibetan-bdd-assert-truthy (string-match-p "🤖" result) "Should include robot emoji")))

  (spec "format-for-display includes translation text"
    :given t
    :when (setq result (tibetan-mitra-format-for-display "bodhisattva"))
    :then ((tibetan-bdd-assert-truthy (string-match-p "bodhisattva" result) "Should include translation"))))

(provide 'mitra-translation-spec)
;;; mitra-translation-spec.el ends here
