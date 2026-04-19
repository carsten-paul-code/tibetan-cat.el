;;; tigress-story-spec.el --- BDD specs for Tigress Jātaka analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications based on real classroom analysis (Tibetisch III, WS25-26).
;; These specs define EXPECTED behavior that the CAT tool should achieve.
;; Source: mDzangs blun, Tigress Jātaka (སྟག་མོ་ལྟོགས་པའི་སྐྱེས་རབས)
;;
;; Each spec documents:
;; 1. The actual Tibetan text from the story
;; 2. What the correct analysis should be
;; 3. The grammatical framework (Bialek, Hill, Schwieger)

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; TIGRESS STORY ANALYSIS SUITE
;; ============================================================================

(define-bdd-suite tigress-story-analysis
    "Tigress Jātaka segment analysis - golden examples from class"

  ;; ==========================================================================
  ;; SEGMENT 26: དེའི་ཚེ་ཀུན་དགའ་བོ་ངོ་མཚར་དུ་གྱུར་པ་ལ་བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།
  ;; "At that time, to Ānanda who had become astonished, the Bhagavan spoke:"
  ;; ==========================================================================

  (spec "seg-026: Recognize ངོ་མཚར as compound"
    :given (setq test-text "ངོ་མཚར་དུ་གྱུར")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              ;; Return list of compound forms
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "ངོ་མཚར" result
            "ངོ་མཚར must be recognized as compound, not ངོ + མཚར"))
    :example "Tigress seg-026: compound word recognition"
    :tags (:tigress :segmentation :critical))

  (spec "seg-026: Detect གྱུར as verb (འགྱུར)"
    :given (setq test-word "གྱུར")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "འགྱུར" (alist-get 'lemma result)
            "གྱུར is past stem of འགྱུར")
           (tibetan-bdd-assert-matches "become\\|transform" (alist-get 'meaning result)))
    :example "Tigress seg-026"
    :tags (:tigress :verbs))

  (spec "seg-026: Detect བཀའ་སྩལ as honorific verb"
    :given (setq test-word "བཀའ་སྩལ")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-not-nil result
            "བཀའ་སྩལ should be recognized as verb")
           (tibetan-bdd-assert-matches "speak\\|say" (alist-get 'meaning result))
           (tibetan-bdd-assert-equal "Transitive" (alist-get 'transitivity result)))
    :example "Tigress seg-026: honorific speech verb"
    :tags (:tigress :verbs :honorific))

  (spec "seg-026: Classify གྱུར with indigenous class"
    :given (setq test-word "གྱུར")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-equal "tha_mi_dad_pa" (alist-get 'indigenous_class result)
            "འགྱུར is intransitive (tha mi dad pa)")
           (tibetan-bdd-assert-equal "Intransitive" (alist-get 'transitivity result)
            "འགྱུར should be intransitive"))
    :example "Tigress seg-026: Tibetan verb classification"
    :tags (:tigress :verbs :tibetan-grammar :critical))

  (spec "seg-026: Analyze དུ as terminative (manner/result)"
    :given (setq test-text "ངོ་མཚར་དུ་གྱུར")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "དུ" result)
           (tibetan-bdd-assert-matches "terminative\\|ALL"
            (tibetan-bdd-get-particle-type "དུ" result))
           (tibetan-bdd-assert-matches "manner\\|result\\|adverbializer"
            (tibetan-bdd-get-particle-function "དུ" result)))
    :example "Tigress seg-026: དུ as adverbializer"
    :tags (:tigress :particles :bialek))

  (spec "seg-026: Analyze ལ as dative (recipient)"
    :given (setq test-text "གྱུར་པ་ལ་བཅོམ་ལྡན་འདས་ཀྱིས")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ལ" result)
           (tibetan-bdd-assert-matches "dative\\|DAT"
            (tibetan-bdd-get-particle-type "ལ" result)))
    :example "Tigress seg-026: ལ marking indirect object"
    :tags (:tigress :particles :bialek))

  (spec "seg-026: Analyze ཀྱིས as ergative (agent)"
    :given (setq test-text "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ཀྱིས" result)
           (tibetan-bdd-assert-matches "ergative\\|instrumental\\|ERG"
            (tibetan-bdd-get-particle-type "ཀྱིས" result))
           (tibetan-bdd-assert-matches "agent"
            (tibetan-bdd-get-particle-function "ཀྱིས" result)))
    :example "Tigress seg-026: ergative marking agent of transitive"
    :tags (:tigress :particles :bialek :critical))

  ;; ==========================================================================
  ;; SEGMENT 27: མ་སྨད་གསུམ་པོ་འདི་ནི་ངས་ད་ལྟར་འདི་འབའ་ཞིག་ཏུ་མ་ཟད།
  ;; "As for these three (mother and sons), not only this present [occasion]..."
  ;; ==========================================================================

  (spec "seg-027: Recognize མ་སྨད as compound"
    :given (setq test-text "མ་སྨད་གསུམ་པོ")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "མ་སྨད" result
            "མ་སྨད (mother and sons) must be recognized as compound"))
    :example "Tigress seg-027"
    :tags (:tigress :segmentation :critical))

  (spec "seg-027: Recognize ད་ལྟར as compound"
    :given (setq test-text "ད་ལྟར་འདི")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "ད་ལྟར" result
            "ད་ལྟར (now/present) must be recognized as compound, not ད + ལྟར"))
    :example "Tigress seg-027"
    :tags (:tigress :segmentation :critical))

  (spec "seg-027: Recognize འབའ་ཞིག as compound"
    :given (setq test-text "འདི་འབའ་ཞིག་ཏུ")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "འབའ་ཞིག" result
            "འབའ་ཞིག (only/merely) must be recognized as compound"))
    :example "Tigress seg-027"
    :tags (:tigress :segmentation))

  (spec "seg-027: Detect ཟད as verb (negative མ་ཟད)"
    :given (setq test-word "ཟད")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-not-nil result
            "ཟད should be recognized as verb")
           (tibetan-bdd-assert-matches "exhaust\\|finish\\|only" (alist-get 'meaning result)))
    :example "Tigress seg-027: མ་ཟད = not only"
    :tags (:tigress :verbs))

  (spec "seg-027: Analyze ནི as topic marker"
    :given (setq test-text "མ་སྨད་གསུམ་པོ་འདི་ནི")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ནི" result)
           (tibetan-bdd-assert-matches "topic\\|TOP"
            (tibetan-bdd-get-particle-type "ནི" result)))
    :example "Tigress seg-027: topic marker"
    :tags (:tigress :particles))

  ;; ==========================================================================
  ;; SEGMENT 28: སྔོན་གྱི་དུས་ནའང་བཀའ་དྲིན་གྱིས་གསོས་པ་ཡིན་ཏེ།
  ;; "In former times too, [they] were nourished by [my] kindness."
  ;; ==========================================================================

  (spec "seg-028: Detect གསོས as verb (past of གསོ)"
    :given (setq test-word "གསོས")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-not-nil result
            "གསོས should be recognized as past stem of གསོ")
           (tibetan-bdd-assert-equal "གསོ" (alist-get 'lemma result))
           (tibetan-bdd-assert-matches "nourish\\|nurture\\|sustain" (alist-get 'meaning result)))
    :example "Tigress seg-028"
    :tags (:tigress :verbs :critical))

  (spec "seg-028: Analyze ནའང as locative+concessive"
    :given (setq test-text "སྔོན་གྱི་དུས་ནའང")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ནའང" result)
           (tibetan-bdd-assert-matches "locative.*concessive\\|LOC.*also\\|even when"
            (tibetan-bdd-get-particle-function "ནའང" result)))
    :example "Tigress seg-028: ན + འང compound particle"
    :tags (:tigress :particles :bialek))

  (spec "seg-028: Analyze གྱིས as instrumental (means)"
    :given (setq test-text "བཀའ་དྲིན་གྱིས་གསོས")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "གྱིས" result)
           (tibetan-bdd-assert-matches "instrumental\\|ERG"
            (tibetan-bdd-get-particle-type "གྱིས" result))
           (tibetan-bdd-assert-matches "means\\|instrument\\|by"
            (tibetan-bdd-get-particle-function "གྱིས" result)))
    :example "Tigress seg-028: instrumental marking means"
    :tags (:tigress :particles :bialek))

  (spec "seg-028: Analyze ཏེ as continuative converb"
    :given (setq test-text "ཡིན་ཏེ")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ཏེ" result)
           (tibetan-bdd-assert-matches "continuative\\|CONV"
            (tibetan-bdd-get-particle-type "ཏེ" result)))
    :example "Tigress seg-028: continuative"
    :tags (:tigress :particles :converbs))

  ;; ==========================================================================
  ;; SEGMENT 32: སྔོན་འདས་པའི་དུས་བསྐལ་པ་གྲངས་མེད་པའི་ཕ་རོལ་ན།
  ;; "Long ago, in time past, on the other side of innumerable kalpas..."
  ;; ==========================================================================

  (spec "seg-032: Recognize ཕ་རོལ་ན as compound"
    :given (setq test-text "པའི་ཕ་རོལ་ན")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "ཕ་རོལ་ན" result
            "ཕ་རོལ་ན (beyond) is a compound including locative ན"))
    :example "Tigress seg-032"
    :tags (:tigress :segmentation :critical))

  (spec "seg-032: Recognize བསྐལ་པ as compound (kalpa)"
    :given (setq test-text "དུས་བསྐལ་པ་གྲངས")
    :when (when (fboundp 'tibetan-parse-enhanced)
            (let* ((parsed (tibetan-parse-enhanced test-text))
                   (units (alist-get 'multiword-units parsed)))
              (mapcar (lambda (u) (nth 2 u)) units)))
    :then ((tibetan-bdd-assert-member "བསྐལ་པ" result
            "བསྐལ་པ (kalpa/aeon) must be recognized as compound"))
    :example "Tigress seg-032"
    :tags (:tigress :segmentation))

  (spec "seg-032: མེད is adjective here, not main verb"
    :given (setq test-text "གྲངས་མེད་པའི")
    :when (when (fboundp 'tibetan-analysis-generate-content)
            (tibetan-analysis-generate-content test-text))
    :then ((tibetan-bdd-assert-not-matches "PREDICATE.*མེད" result
            "མེད in གྲངས་མེད་པའི is adjectival, not the main predicate"))
    :example "Tigress seg-032: attributive མེད"
    :tags (:tigress :verbs :sentence-structure))

  ;; ==========================================================================
  ;; SEGMENT 37: ཕྱི་མ་ནི་བྱམས་པ་དང་སྙིང་རྗེར་ལྡན་ཏེ་ཐམས་ཅད་ལ་བུ་གཅིག་པ་དང་འདྲའོ།
  ;; "The youngest was endowed with loving-kindness and compassion,
  ;;  being like an only child to all."
  ;; ==========================================================================

  (spec "seg-037: Detect ལྡན as verb"
    :given (setq test-word "ལྡན")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-not-nil result
            "ལྡན should be recognized as verb")
           (tibetan-bdd-assert-matches "endowed\\|possess\\|have" (alist-get 'meaning result)))
    :example "Tigress seg-037"
    :tags (:tigress :verbs :critical))

  (spec "seg-037: Detect འདྲ as verb"
    :given (setq test-word "འདྲ")
    :when (tibetan-verb-lookup test-word)
    :then ((tibetan-bdd-assert-not-nil result
            "འདྲ should be recognized as verb")
           (tibetan-bdd-assert-matches "similar\\|like\\|resemble" (alist-get 'meaning result)))
    :example "Tigress seg-037"
    :tags (:tigress :verbs))

  (spec "seg-037: Analyze ར as terminative on སྙིང་རྗེར"
    :given (setq test-text "སྙིང་རྗེར་ལྡན")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "ར" result)
           (tibetan-bdd-assert-matches "terminative\\|ALL"
            (tibetan-bdd-get-particle-type "ར" result)))
    :example "Tigress seg-037: terminative with ལྡན"
    :tags (:tigress :particles :bialek))

  (spec "seg-037: Analyze དང as comitative (with)"
    :given (setq test-text "བྱམས་པ་དང་སྙིང་རྗེར")
    :when (when (fboundp 'tibetan-analyze-grammar-bialek)
            (tibetan-analyze-grammar-bialek test-text))
    :then ((tibetan-bdd-assert-particle-in-analysis "དང" result)
           (tibetan-bdd-assert-matches "comitative\\|COM\\|and\\|with"
            (tibetan-bdd-get-particle-type "དང" result)))
    :example "Tigress seg-037: conjunction"
    :tags (:tigress :particles))

  ;; ==========================================================================
  ;; FULL ANALYSIS OUTPUT STRUCTURE
  ;; ==========================================================================

  (spec "Full analysis includes grammatical markers section"
    :given (setq test-text "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")
    :when (when (fboundp 'tibetan-analysis-generate-content)
            (tibetan-analysis-generate-content test-text))
    :then ((tibetan-bdd-assert-contains result "** Grammatical Markers"
            "Should have Grammatical Markers section")
           (tibetan-bdd-assert-matches "→\\|ERG\\|case" result
            "Should show particle annotations with types and functions"))
    :example "Tigress: analysis output format"
    :tags (:tigress :output-format :critical))

  (spec "Full analysis includes Tibetan verb classification"
    :given (setq test-text "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")
    :when (when (fboundp 'tibetan-analysis-generate-content)
            (tibetan-analysis-generate-content test-text))
    :then ((tibetan-bdd-assert-contains result "** Verb Classification"
            "Should have Verb Classification section")
           (tibetan-bdd-assert-matches "ཐ་དད་པ\\|ཐ་མི་དད་པ" result
            "Should include Tibetan verb category")
           (tibetan-bdd-assert-contains result "STEMS:"
            "Should show verb stems"))
    :example "Tigress: verb classification format"
    :tags (:tigress :output-format :tibetan-grammar :critical))

  (spec "Full analysis detects both verbs in seg-026"
    :given (setq test-text "དེའི་ཚེ་ཀུན་དགའ་བོ་ངོ་མཚར་དུ་གྱུར་པ་ལ་བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")
    :when (when (fboundp 'tibetan-analysis-generate-content)
            (tibetan-analysis-generate-content test-text))
    :then ((tibetan-bdd-assert-matches "གྱུར\\|འགྱུར" result
            "Should detect གྱུར verb")
           (tibetan-bdd-assert-matches "བཀའ་སྩལ" result
            "Should detect བཀའ་སྩལ verb")
           (tibetan-bdd-assert-not-contains result "[No verbs]"
            "Should NOT say 'No verbs'"))
    :example "Tigress seg-026: detect all verbs"
    :tags (:tigress :verbs :integration :critical)))

;; ============================================================================
;; HELPER FUNCTIONS FOR PARTICLE ANALYSIS ASSERTIONS
;; ============================================================================

(defun tibetan-bdd-assert-particle-in-analysis (particle result)
  "Assert that PARTICLE appears in the grammar analysis RESULT."
  (should (and result (string-match-p (regexp-quote particle)
                                       (if (listp result)
                                           (format "%S" result)
                                         result)))))

(defun tibetan-bdd-get-particle-type (particle result)
  "Extract the TYPE annotation for PARTICLE from RESULT."
  (when (and result (listp result))
    (let ((entry (cl-find-if (lambda (e)
                               (string-match-p (regexp-quote particle)
                                               (format "%S" e)))
                             result)))
      (when entry
        (or (nth 2 entry) "")))))

(defun tibetan-bdd-get-particle-function (particle result)
  "Extract the FUNCTION annotation for PARTICLE from RESULT."
  (when (and result (listp result))
    (let ((entry (cl-find-if (lambda (e)
                               (string-match-p (regexp-quote particle)
                                               (format "%S" e)))
                             result)))
      (when entry
        (or (nth 3 entry) "")))))

(defun tibetan-bdd-assert-member (expected list-result &optional msg)
  "Assert that EXPECTED is a member of LIST-RESULT."
  (should (member expected list-result)))

(defun tibetan-bdd-assert-not-matches (pattern result &optional msg)
  "Assert that PATTERN does NOT match in RESULT."
  (should-not (and result (string-match-p pattern result))))

(provide 'tigress-story-spec)
;;; tigress-story-spec.el ends here
