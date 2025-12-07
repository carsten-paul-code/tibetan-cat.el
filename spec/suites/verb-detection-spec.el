;;; verb-detection-spec.el --- BDD specs for verb detection -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for verb detection functionality.
;; Golden examples captured from working analysis.

;;; Code:

(require 'tibetan-bdd)
(require 'tibetan-verb-classifier)

;; ============================================================================
;; VERB DETECTION SUITE
;; ============================================================================

(define-bdd-suite verb-detection
    "Verb detection and classification (Hill 2010)"

  ;; --- Golden Example: Segment 25 (selling poverty) ---
  (spec "Detect གསུངས (hon. to speak) in direct speech"
    :given (setq test-word "གསུངས")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "གསུང" (alist-get 'lemma result))
           (tibetan-bdd-assert-matches "speak\\|say" (alist-get 'meaning result))
           (tibetan-bdd-assert-equal "Transitive" (alist-get 'transitivity result)))
    :example "Segment 25: འཕགས་བས...གསུངས།"
    :tags (:regression :critical))

  (spec "Detect བཙོང (to sell) from future stem"
    :given (setq test-word "བཙོང")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "འཚོང" (alist-get 'lemma result))
           (tibetan-bdd-assert-matches "sell" (alist-get 'meaning result))
           (tibetan-bdd-assert-equal "Erg-Abs" (alist-get 'case_frame result)))
    :example "Segment 25: དབུལ་བ་བཙོང་ན"
    :tags (:regression))

  (spec "Detect ཐོངས (imperative of གཏོང, to release)"
    :given (setq test-word "ཐོངས")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "གཏོང" (alist-get 'lemma result))
           (tibetan-bdd-assert-matches "release\\|let go\\|send" (alist-get 'meaning result)))
    :example "Segment 25: སྦྱིན་པ་ཐོངས་ཤིག"
    :tags (:regression))

  (spec "Detect ཁྲུས (to bathe)"
    :given (setq test-word "ཁྲུས")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "ཁྲུས" (alist-get 'lemma result))
           (tibetan-bdd-assert-matches "wash\\|bathe" (alist-get 'meaning result)))
    :example "Segment 25: ཁྲུས་གྱིས་ལ"
    :tags (:regression))

  ;; --- Verb Stem Recognition ---
  (spec "Recognize past stem བྱིན as སྦྱིན"
    :given (setq test-word "བྱིན")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "སྦྱིན" (alist-get 'lemma result))
           (tibetan-bdd-assert-equal "བྱིན" (alist-get 'past_stem result)))
    :example "Common verb: give"
    :tags (:verb-stems))

  (spec "Recognize past stem སོང as འགྲོ"
    :given (setq test-word "སོང")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "འགྲོ" (alist-get 'lemma result))
           (tibetan-bdd-assert-equal "Intransitive" (alist-get 'transitivity result)))
    :example "Common verb: go"
    :tags (:verb-stems))

  ;; --- Transitivity Classification ---
  (spec "Classify transitive verb with Erg-Abs frame"
    :given (setq test-word "མཐོང")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "Transitive" (alist-get 'transitivity result))
           (tibetan-bdd-assert-equal "Erg-Abs" (alist-get 'case_frame result)))
    :example "Perception verb: to see"
    :tags (:case-frames))

  (spec "Classify intransitive verb with Abs frame"
    :given (setq test-word "འགྲོ")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "Intransitive" (alist-get 'transitivity result))
           (tibetan-bdd-assert-equal "Abs" (alist-get 'case_frame result)))
    :example "Motion verb: to go"
    :tags (:case-frames))

  (spec "Classify ditransitive verb with Erg-Abs-Dat frame"
    :given (setq test-word "སྦྱིན")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "Transitive" (alist-get 'transitivity result))
           (tibetan-bdd-assert-equal "Erg-Abs-Dat" (alist-get 'case_frame result)))
    :example "Ditransitive verb: to give"
    :tags (:case-frames :critical))

  ;; --- Punctuation Handling ---
  (spec "Strip trailing shad before lookup"
    :given (setq test-word "གསུངས།")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "གསུང" (alist-get 'lemma result)))
    :example "Verb at end of sentence"
    :tags (:parsing))

  (spec "Handle verb with double shad"
    :given (setq test-word "གསུངས༎")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "གསུང" (alist-get 'lemma result)))
    :example "Verb at end of verse"
    :tags (:parsing))

  ;; --- Edge Cases ---
  (spec "Return nil for non-verb"
    :given (setq test-word "སངས་རྒྱས")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal nil result))
    :example "Buddha - noun, not verb"
    :tags (:edge-cases))

  (spec "Return nil for empty string"
    :given (setq test-word "")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal nil result))
    :tags (:edge-cases))

  (spec "Return nil for whitespace"
    :given (setq test-word "  ")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal nil result))
    :tags (:edge-cases)))

(provide 'verb-detection-spec)
;;; verb-detection-spec.el ends here
