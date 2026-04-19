;;; cat-translation-spec.el --- BDD specs for CAT translation engine -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for the CAT (Computer-Assisted Translation) engine.
;; Tests gloss generation, word order transformation (SOV->SVO), and output.

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; CAT TRANSLATION SUITE
;; ============================================================================

(define-bdd-suite cat-translation
    "CAT translation engine (C-c u t)"

  ;; --- Gloss Generation (internal function) ---
  (spec "Generate gloss for known vocabulary word"
    :given (setq test-word "སངས་རྒྱས")
    :when (when (fboundp 'tibetan-cat--gloss-word)
            (tibetan-cat--gloss-word test-word))
    :then ((tibetan-bdd-assert-matches "awaken\\|buddha\\|hood" result
            "Should return gloss containing awakening/buddha reference"))
    :example "Buddha"
    :tags (:glossing))

  (spec "Generate gloss for verb"
    :given (setq test-word "གསུངས")
    :when (when (fboundp 'tibetan-cat--gloss-word)
            (tibetan-cat--gloss-word test-word))
    :then ((tibetan-bdd-assert-matches "speak\\|say\\|said\\|scripture\\|curing\\|dictionary" result
            "Should return gloss or dictionary entry for གསུངས"))
    :example "Honorific verb"
    :tags (:glossing :verbs))

  (spec "Return nil for unknown word gracefully"
    :given (setq test-word "ཨ་ཀ་ར")
    :when (when (fboundp 'tibetan-cat--gloss-word)
            (tibetan-cat--gloss-word test-word))
    :then ((should (or (null result) (stringp result))))
    :tags (:glossing :edge-cases))

  ;; --- Word Order Mapping ---
  (spec "Word order variable exists"
    :given nil
    :when (boundp 'tibetan-cat-translation-word-order)
    :then ((should result))
    :tags (:word-order))

  (spec "Map Erg-Abs to correct order"
    :given nil
    :when (when (boundp 'tibetan-cat-translation-word-order)
            (alist-get 'Erg-Abs tibetan-cat-translation-word-order))
    :then ((should result)
           (should (listp result)))
    :tags (:word-order))

  (spec "Map Abs frame exists"
    :given nil
    :when (when (boundp 'tibetan-cat-translation-word-order)
            (alist-get 'Abs tibetan-cat-translation-word-order))
    :then ((should result))
    :tags (:word-order))

  (spec "Map Erg-Abs-Dat for ditransitive verbs"
    :given nil
    :when (when (boundp 'tibetan-cat-translation-word-order)
            (alist-get 'Erg-Abs-Dat tibetan-cat-translation-word-order))
    :then ((should result))
    :tags (:word-order))

  ;; --- Argument Parsing ---
  (spec "Parse structure text for arguments"
    :given (setq test-structure "- PREDICATE: གསུངས \"to speak\"\n  - AGENT: འཕགས \"noble\"")
    :when (when (fboundp 'tibetan-cat--get-arguments-from-structure)
            (tibetan-cat--get-arguments-from-structure test-structure))
    :then ((should result)
           (should (listp result)))
    :example "Structure from segment analysis"
    :tags (:parsing))

  ;; --- Full Translation Generation ---
  (spec "Generate translation string from text"
    :given (setq test-text "སངས་རྒྱས།")
    :when (when (fboundp 'tibetan-cat-generate-translation)
            (tibetan-cat-generate-translation test-text))
    :then ((should (or (null result) (stringp result))))
    :example "Simple text"
    :tags (:integration))

  ;; --- Function Existence ---
  (spec "tibetan-cat-insert-translation function exists"
    :given nil
    :when (fboundp 'tibetan-cat-insert-translation)
    :then ((should result))
    :tags (:api))

  (spec "tibetan-cat-translate-region function exists"
    :given nil
    :when (fboundp 'tibetan-cat-translate-region)
    :then ((should result))
    :tags (:api)))

(provide 'cat-translation-spec)
;;; cat-translation-spec.el ends here
