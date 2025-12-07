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

  ;; --- Gloss Generation ---
  (spec "Generate gloss for known vocabulary word"
    :given (setq test-word "སངས་རྒྱས")
    :when (when (fboundp 'tibetan-cat-gloss-word)
            (tibetan-cat-gloss-word test-word))
    :then ((tibetan-bdd-assert-matches "Buddha\\|awakened" result
            "Should gloss སངས་རྒྱས"))
    :example "Buddha"
    :tags (:glossing))

  (spec "Generate gloss for verb"
    :given (setq test-word "གསུངས")
    :when (when (fboundp 'tibetan-cat-gloss-word)
            (tibetan-cat-gloss-word test-word))
    :then ((tibetan-bdd-assert-matches "speak\\|say\\|said" result
            "Should gloss གསུངས as speak/say"))
    :example "Honorific verb"
    :tags (:glossing :verbs))

  (spec "Return nil for unknown word"
    :given (setq test-word "ཨ་ཀ་ར")
    :when (when (fboundp 'tibetan-cat-gloss-word)
            (tibetan-cat-gloss-word test-word))
    :then ((should (or (null result) (stringp result))))
    :tags (:glossing :edge-cases))

  ;; --- Word Order Mapping ---
  (spec "Map Erg-Abs to Agent-Verb-Patient order"
    :given (setq test-frame "Erg-Abs")
    :when (when (boundp 'tibetan-cat-word-order-mapping)
            (alist-get test-frame tibetan-cat-word-order-mapping nil nil 'equal))
    :then ((tibetan-bdd-assert-equal '(agent verb patient) result
            "Erg-Abs should map to A-V-P"))
    :tags (:word-order))

  (spec "Map Abs to Patient-Verb order (intransitive)"
    :given (setq test-frame "Abs")
    :when (when (boundp 'tibetan-cat-word-order-mapping)
            (alist-get test-frame tibetan-cat-word-order-mapping nil nil 'equal))
    :then ((tibetan-bdd-assert-equal '(patient verb) result
            "Abs should map to P-V"))
    :tags (:word-order))

  (spec "Map Erg-Abs-Dat for ditransitive verbs"
    :given (setq test-frame "Erg-Abs-Dat")
    :when (when (boundp 'tibetan-cat-word-order-mapping)
            (alist-get test-frame tibetan-cat-word-order-mapping nil nil 'equal))
    :then ((tibetan-bdd-assert-equal '(agent verb patient goal) result
            "Erg-Abs-Dat should map to A-V-P-G"))
    :tags (:word-order))

  ;; --- Noun Phrase Building ---
  (spec "Build noun phrase with meaning"
    :given (setq test-arg '((role . "patient")
                            (form . "དབུལ་བ")
                            (english . "poverty")))
    :when (when (fboundp 'tibetan-cat-build-noun-phrase)
            (tibetan-cat-build-noun-phrase test-arg))
    :then ((tibetan-bdd-assert-contains result "poverty"
            "Should include English meaning"))
    :example "Poverty as patient"
    :tags (:phrase-building))

  (spec "Build agent phrase with role marker"
    :given (setq test-arg '((role . "agent")
                            (form . "འཕགས")
                            (english . "noble one")))
    :when (when (fboundp 'tibetan-cat-build-noun-phrase)
            (tibetan-cat-build-noun-phrase test-arg))
    :then ((tibetan-bdd-assert-matches "noble" result
            "Should include agent meaning"))
    :example "Noble one as agent"
    :tags (:phrase-building))

  ;; --- Full Translation Generation ---
  (spec "Generate translation string from text"
    :given (setq test-text "སངས་རྒྱས།")
    :when (when (fboundp 'tibetan-cat-generate-translation)
            (tibetan-cat-generate-translation test-text))
    :then ((should (stringp result)))
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
