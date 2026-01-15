;;; clause-analysis-spec.el --- BDD specs for clause analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for Tibetan clause analysis features:
;; - Main verb identification
;; - Converb scoping (which converbs depend on which main verbs)
;; - Clause tree structure
;;
;; Based on Bialek's converbial construction theory:
;; - Ablative converb (ནས) - sequential action
;; - Coordinative converb (ཏེ/སྟེ) - coordination
;; - Simultaneous converb (ཞིང/ཅིང) - accompanying action
;; - Causal converb (པས/བས) - reason/cause
;; - Concessive (ཀྱང/ཡང) - "even though"

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; MAIN VERB IDENTIFICATION SUITE
;; ============================================================================

(define-bdd-suite main-verb-identification
    "Identifying main verbs in Tibetan clauses"

  ;; --- Basic Main Verb Detection ---
  (spec "Identify single main verb at end of clause"
    :given (setq test-text "སངས་རྒྱས་ཆོས་གསུངས།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "གསུངས" (plist-get result :verb)))
           (should (eq 'main (plist-get result :type))))
    :example "Buddha taught dharma"
    :tags (:main-verb :basic))

  (spec "Identify main verb with converb preceding"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "གསུངས" (plist-get result :verb)))
           (should (eq 'main (plist-get result :type))))
    :example "Having sat, taught dharma"
    :tags (:main-verb :converb))

  (spec "Identify main verb in sentence with multiple converbs"
    :given (setq test-text "མཉན་ཡོད་དུ་བཞུགས་ནས་དགེ་སློང་རྣམས་ལ་ཆོས་བསྟན།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "བསྟན" (plist-get result :verb))))
    :example "Having resided in Śrāvastī, taught dharma to monks"
    :tags (:main-verb :complex :critical))

  (spec "Handle sentence with copula as main verb"
    :given (setq test-text "འདི་ནི་ཆོས་ཡིན།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "ཡིན" (plist-get result :verb))))
    :example "This is dharma"
    :tags (:main-verb :copula))

  (spec "Handle existential verb as main verb"
    :given (setq test-text "སངས་རྒྱས་མཉན་ཡོད་ན་བཞུགས།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "བཞུགས" (plist-get result :verb))))
    :example "Buddha resided in Śrāvastī"
    :tags (:main-verb :existential))

  ;; --- Edge Cases ---
  (spec "Return nil for text without verb"
    :given (setq test-text "སངས་རྒྱས་ཀྱི་ཆོས།")
    :when (tibetan-find-main-verb test-text)
    :then ((should-not result))
    :example "Buddha's dharma (noun phrase only)"
    :tags (:main-verb :edge-case))

  (spec "Handle empty string"
    :given (setq test-text "")
    :when (tibetan-find-main-verb test-text)
    :then ((should-not result))
    :tags (:main-verb :edge-case))

  ;; --- Verb Position Variants ---
  (spec "Main verb with final particle"
    :given (setq test-text "ཆོས་གསུངས་སོ།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "གསུངས" (plist-get result :verb))))
    :example "Taught dharma (with final particle སོ)"
    :tags (:main-verb :final-particle)))

;; ============================================================================
;; CONVERB DETECTION SUITE
;; ============================================================================

(define-bdd-suite converb-detection
    "Detecting and classifying converbs"

  ;; --- Ablative Converb (ནས) ---
  (spec "Detect ablative converb with ནས"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (cl-find-if (lambda (c)
                                (and (string-match-p "ནས" (plist-get c :particle))
                                     (eq 'ablative (plist-get c :type))))
                              result)))
    :example "Having sat (ablative converb)"
    :tags (:converb :ablative))

  ;; --- Coordinative Converb (ཏེ/སྟེ) ---
  (spec "Detect coordinative converb with སྟེ"
    :given (setq test-text "ཐོས་སྟེ་དད་པ་སྐྱེས།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (cl-find-if (lambda (c)
                                (eq 'coordinative (plist-get c :type)))
                              result)))
    :example "Having heard, faith arose"
    :tags (:converb :coordinative))

  ;; --- Simultaneous Converb (ཞིང/ཅིང) ---
  (spec "Detect simultaneous converb with ཞིང"
    :given (setq test-text "བཞུགས་ཞིང་ཆོས་གསུངས།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (cl-find-if (lambda (c)
                                (eq 'simultaneous (plist-get c :type)))
                              result)))
    :example "While sitting, taught dharma"
    :tags (:converb :simultaneous))

  ;; --- Causal Converb (པས/བས) ---
  (spec "Detect causal converb with པས"
    :given (setq test-text "ཆོས་ཐོས་པས་དད་པ་སྐྱེས།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (cl-find-if (lambda (c)
                                (eq 'causal (plist-get c :type)))
                              result)))
    :example "Because [one] heard dharma, faith arose"
    :tags (:converb :causal))

  ;; --- Multiple Converbs ---
  (spec "Detect multiple converbs in sentence"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས་སྟེ་དགེ་སློང་རྣམས་དགའ།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (>= (length result) 2)))
    :example "Having sat, taught dharma, and monks rejoiced"
    :tags (:converb :multiple :critical))

  ;; --- Concessive Particle (ཀྱང) ---
  (spec "Detect concessive with ཀྱང"
    :given (setq test-text "སྡུག་བསྔལ་ཡོད་ཀྱང་བཟོད།")
    :when (tibetan-detect-converbs test-text)
    :then ((should result)
           (should (cl-find-if (lambda (c)
                                (eq 'concessive (plist-get c :type)))
                              result)))
    :example "Even though suffering exists, [one] endures"
    :tags (:converb :concessive)))

;; ============================================================================
;; CONVERB SCOPING SUITE
;; ============================================================================

(define-bdd-suite converb-scoping
    "Determining which verbs converbs depend on"

  (spec "Scope single converb to main verb"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས།")
    :when (tibetan-scope-converbs test-text)
    :then ((should result)
           (let ((scope (car result)))
             (should (plist-get scope :converb))
             (should (plist-get scope :main-verb))
             (should (string-match-p "བཞུགས" (plist-get (plist-get scope :converb) :stem)))
             (should (string-match-p "གསུངས" (plist-get (plist-get scope :main-verb) :verb)))))
    :example "Converb 'having sat' scopes to 'taught'"
    :tags (:scoping :basic :critical))

  (spec "Scope multiple converbs to same main verb"
    :given (setq test-text "བལྟས་ནས་ཐོས་ཏེ་རྟོགས།")
    :when (tibetan-scope-converbs test-text)
    :then ((should result)
           (should (= (length result) 2))
           (let ((main-verb1 (plist-get (nth 0 result) :main-verb))
                 (main-verb2 (plist-get (nth 1 result) :main-verb)))
             (should (string= (plist-get main-verb1 :verb)
                             (plist-get main-verb2 :verb)))))
    :example "Both converbs scope to final main verb"
    :tags (:scoping :multiple))

  (spec "Scope nested converbs correctly"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས་སྟེ་དགེ་སློང་རྣམས་དགའ།")
    :when (tibetan-scope-converbs test-text)
    :then ((should result)
           ;; First converb (བཞུགས་ནས) scopes to གསུངས
           ;; Second converb (གསུངས་སྟེ) scopes to དགའ
           (should (>= (length result) 2)))
    :example "Nested converbial constructions"
    :tags (:scoping :nested :critical))

  (spec "Handle sentence with no converbs"
    :given (setq test-text "སངས་རྒྱས་ཆོས་གསུངས།")
    :when (tibetan-scope-converbs test-text)
    :then ((should-not result))
    :example "Simple sentence without converbs"
    :tags (:scoping :edge-case)))

;; ============================================================================
;; CLAUSE TREE SUITE
;; ============================================================================

(define-bdd-suite clause-tree
    "Building hierarchical clause structures"

  (spec "Build simple clause tree"
    :given (setq test-text "སངས་རྒྱས་ཆོས་གསུངས།")
    :when (tibetan-build-clause-tree test-text)
    :then ((should result)
           (should (eq 'clause (plist-get result :type)))
           (should (plist-get result :main-verb)))
    :example "Simple main clause"
    :tags (:clause-tree :basic))

  (spec "Build clause tree with dependent clause"
    :given (setq test-text "བཞུགས་ནས་ཆོས་གསུངས།")
    :when (tibetan-build-clause-tree test-text)
    :then ((should result)
           (should (plist-get result :dependent-clauses))
           (should (= 1 (length (plist-get result :dependent-clauses)))))
    :example "Main clause with one dependent"
    :tags (:clause-tree :dependent))

  (spec "Build tree with multiple dependent clauses"
    :given (setq test-text "བལྟས་ནས་ཐོས་ཏེ་རྟོགས།")
    :when (tibetan-build-clause-tree test-text)
    :then ((should result)
           (should (plist-get result :dependent-clauses))
           (should (>= (length (plist-get result :dependent-clauses)) 2)))
    :example "Main clause with two dependent clauses"
    :tags (:clause-tree :multiple))

  (spec "Preserve converb type in tree"
    :given (setq test-text "བཞུགས་ཞིང་ཆོས་གསུངས།")
    :when (tibetan-build-clause-tree test-text)
    :then ((should result)
           (let ((dep (car (plist-get result :dependent-clauses))))
             (should (eq 'simultaneous (plist-get dep :converb-type)))))
    :example "Simultaneous converb type preserved"
    :tags (:clause-tree :converb-type)))

;; ============================================================================
;; REAL-WORLD EXAMPLES SUITE
;; ============================================================================

(define-bdd-suite clause-analysis-real-world
    "Real-world clause analysis examples from Buddhist texts"

  (spec "Analyze Padma rnam-rgyal opening clause"
    :given (setq test-text "ཡང་སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།")
    :when (tibetan-build-clause-tree test-text)
    :then ((should result)
           ;; This is a temporal clause ("when the Teacher was residing...")
           (should (plist-get result :main-verb)))
    :example "Ocean Deity story opening"
    :tags (:real-world :padma-rnam-rgyal))

  (spec "Analyze merchants' voyage clause"
    :given (setq test-text "ཚོང་པ་ལྔ་བརྒྱ་རྒྱ་མཚོར་རིན་པོ་ཆེ་ལེན་དུ་འགྲོ།")
    :when (tibetan-find-main-verb test-text)
    :then ((should result)
           (should (string-match-p "འགྲོ" (plist-get result :verb))))
    :example "500 merchants go to ocean for jewels"
    :tags (:real-world :padma-rnam-rgyal))

  (spec "Analyze Sa skya legs bshad clause with converb"
    :given (setq test-text "བསམས་ནས་བཤད་པ།")
    :when (tibetan-scope-converbs test-text)
    :then ((should result)
           (should (= 1 (length result))))
    :example "Having thought, [one] explained"
    :tags (:real-world :sa-skya-legs-bshad)))

(provide 'clause-analysis-spec)
;;; clause-analysis-spec.el ends here
