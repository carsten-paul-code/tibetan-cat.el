;;; particle-analysis-spec.el --- BDD specs for particle detection -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for Tibetan grammatical particle detection.
;; Based on Classical Tibetan grammar (Bialek, Hill, Tournadre).

;;; Code:

(require 'tibetan-bdd)

;; Helper for particle annotation
(defun tibetan-bdd--get-particle-annotation (word)
  "Get particle annotation for WORD using analysis-persist function."
  (when (fboundp 'tibetan-analysis--get-particle-annotation)
    (tibetan-analysis--get-particle-annotation word)))

;; ============================================================================
;; PARTICLE ANALYSIS SUITE
;; ============================================================================

(define-bdd-suite particle-analysis
    "Grammatical particle detection and annotation"

  ;; --- Ergative/Instrumental Particles ---
  (spec "Detect གྱིས as ergative marker"
    :given (setq test-particle "གྱིས")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ERG" result))
    :example "Segment 25: ཁྲུས་གྱིས་ལ"
    :tags (:regression :case-markers))

  (spec "Detect ས as ergative marker"
    :given (setq test-particle "ས")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ERG" result))
    :tags (:case-markers))

  (spec "Detect ཀྱིས as ergative marker"
    :given (setq test-particle "ཀྱིས")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ERG" result))
    :tags (:case-markers))

  ;; --- Dative/Locative Particles ---
  (spec "Detect ལ as dative marker"
    :given (setq test-particle "ལ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "DAT" result))
    :example "Segment 25: གྱིས་ལ"
    :tags (:regression :case-markers))

  (spec "Detect ན as locative/conditional"
    :given (setq test-particle "ན")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "LOC\\|if\\|when" result))
    :example "Segment 25: བཙོང་ན"
    :tags (:regression :case-markers))

  ;; --- Terminative Particles (Bialek: goal/direction/manner) ---
  (spec "Detect ཏུ as terminative marker"
    :given (setq test-particle "ཏུ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ALL.*toward" result))
    :example "Segment 25: འོག་ཏུ"
    :tags (:regression :case-markers))

  (spec "Detect སུ as terminative marker"
    :given (setq test-particle "སུ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ALL.*toward" result))
    :tags (:case-markers))

  (spec "Detect དུ as terminative marker"
    :given (setq test-particle "དུ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ALL.*toward" result))
    :tags (:case-markers))

  (spec "Detect ར as terminative marker"
    :given (setq test-particle "ར")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ALL.*toward" result))
    :tags (:case-markers))

  ;; --- Genitive Particles ---
  (spec "Detect གི as genitive marker"
    :given (setq test-particle "གི")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "GEN" result))
    :tags (:case-markers))

  (spec "Detect ཀྱི as genitive marker"
    :given (setq test-particle "ཀྱི")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "GEN" result))
    :tags (:case-markers))

  (spec "Detect འི as genitive marker"
    :given (setq test-particle "འི")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "GEN" result))
    :tags (:case-markers))

  ;; --- Ablative Particles ---
  (spec "Detect ནས as ablative marker"
    :given (setq test-particle "ནས")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ABL" result))
    :tags (:case-markers))

  (spec "Detect ལས as ablative marker"
    :given (setq test-particle "ལས")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "ABL" result))
    :tags (:case-markers))

  ;; --- Converb Particles ---
  (spec "Detect སྟེ as continuative converb"
    :given (setq test-particle "སྟེ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "CONV" result))
    :example "Segment 25: ཇི་སྟེ"
    :tags (:regression :converbs))

  (spec "Detect ཏེ as continuative converb"
    :given (setq test-particle "ཏེ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "CONV" result))
    :tags (:converbs))

  (spec "Detect ཅིང as simultaneous converb"
    :given (setq test-particle "ཅིང")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "CONV" result))
    :tags (:converbs))

  ;; --- Nominalizers ---
  ;; Note: Standalone པ/བ return nil because they're usually part of verb forms
  ;; (like བཞུགས་པའི) and are handled contextually, not as isolated particles.
  ;; Agent nominalizers པོ/བོ are detected.
  (spec "Detect བོ as agent nominalizer"
    :given (setq test-particle "བོ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "AGT" result))
    :example "Segment: བྱེད་པོ (agent)"
    :tags (:regression :nominalizers))

  (spec "Detect པོ as agent nominalizer"
    :given (setq test-particle "པོ")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "AGT" result))
    :tags (:nominalizers))

  ;; --- Imperative Particles ---
  (spec "Detect ཤིག as imperative marker"
    :given (setq test-particle "ཤིག")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "IMP" result))
    :example "Segment 25: ཐོངས་ཤིག"
    :tags (:regression :imperative))

  (spec "Detect ཅིག as imperative marker"
    :given (setq test-particle "ཅིག")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "IMP" result))
    :tags (:imperative))

  ;; --- Topic Marker ---
  (spec "Detect ནི as topic marker"
    :given (setq test-particle "ནི")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "TOP" result))
    :tags (:discourse-markers))

  ;; --- Comitative ---
  (spec "Detect དང as comitative"
    :given (setq test-particle "དང")
    :when (tibetan-bdd--get-particle-annotation test-particle)
    :then ((tibetan-bdd-assert-matches "COM" result))
    :tags (:case-markers)))

;; ============================================================================
;; ZERO-MARKER RENDERING SUITE
;; ============================================================================
;;
;; The Particle Map flags transitive verbs that lack an explicit
;; ergative-marked agent with `Ø' (zero-marker).  Earlier versions
;; emitted these as trailing notes (`[Ø AGENT expected before V]')
;; appended after the Wylie line; the new convention embeds Ø
;; directly inline in the map at the verb's position so the visual
;; alignment between particle markup and verb-argument structure
;; stays in one line.

(define-bdd-suite zero-marker-rendering
    "Particle Map renders Ø inline, not as trailing notes"

  (spec "Ø appears inline before transitive verb"
    :given (when (fboundp 'tibetan-analysis--generate-particle-map)
             (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
                        (lambda (s)
                          (cond ((equal s "FOO") "alpha smra beta")
                                ((equal s "smra") "smra")
                                (t s)))))
               (setq result
                     (tibetan-analysis--generate-particle-map
                      "FOO"
                      nil
                      '(((lemma . "smra")
                         (transitivity . "Transitive")
                         (case_frame . "Erg-Abs")))))))
    :when result
    :then ((should result)
           (should (string-match-p "Ø smra" result))
           (should-not (string-match-p "\\[Ø AGENT expected" result)))
    :example "Particle Map embeds Ø inline before `smra'"
    :tags (:zero-marker :rendering :critical))

  (spec "Ø NOT inserted before intransitive verbs"
    :given (when (fboundp 'tibetan-analysis--generate-particle-map)
             (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
                        (lambda (s)
                          (cond ((equal s "BAR") "phyin pa")
                                ((equal s "phyin") "phyin")
                                (t s)))))
               (setq result
                     (tibetan-analysis--generate-particle-map
                      "BAR"
                      nil
                      '(((lemma . "phyin")
                         (transitivity . "Intransitive")
                         (case_frame . "Abs")))))))
    :when result
    :then ((should result)
           (should-not (string-match-p "Ø" result)))
    :example "Intransitive `phyin' gets no Ø"
    :tags (:zero-marker :rendering :backwards-compat)))

(provide 'particle-analysis-spec)
;;; particle-analysis-spec.el ends here
