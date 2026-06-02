;;; tibetan-madhyamaka-terms.el --- Madhyamaka philosophical terminology -*- lexical-binding: t -*-

;;; Commentary:
;; Specialized vocabulary for Madhyamaka texts
;; Based on Gelugpa (dGe-lugs) tradition
;; Particularly for dBu ma'i bsdus don lta ba'i me long
;;
;; Covers:
;; - Two Truths (bden gnyis) terminology
;; - Emptiness (stong pa nyid) concepts
;; - Dependent arising (rten 'byung) terms
;; - Valid cognition (tshad ma) concepts
;; - Gelugpa-specific usage

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CORE MADHYAMAKA CONCEPTS
;; ============================================================================

(defvar tibetan-madhyamaka-core-terms
  '(;; Two Truths Framework
    ("བདེན་པ་གཉིས" . "Two Truths/Realities (satyadvaya)")
    ("བདེན་གཉིས" . "Two Truths (satyadvaya)")
    ("ཀུན་རྫོབ་བདེན་པ" . "Conventional truth (saṃvṛtisatya)")
    ("ཀུན་རྫོབ" . "Conventional (saṃvṛti)")
    ("དོན་དམ་བདེན་པ" . "Ultimate truth (paramārthasatya)")
    ("དོན་དམ" . "Ultimate (paramārtha)")
    ("དོན་དམ་པ" . "Ultimate (paramārtha)")

    ;; Madhyamaka School
    ("དབུ་མ" . "Madhyamaka (Middle Way)")
    ("དབུ་མ་པ" . "Mādhyamika (Madhyamaka proponent)")
    ("དབུ་མའི་ལྟ་བ" . "Madhyamaka view")
    ("ཐེག་མཆོག" . "Supreme vehicle (Mahāyāna)")

    ;; Emptiness
    ("སྟོང་པ་ཉིད" . "Emptiness (śūnyatā)")
    ("སྟོང་པ" . "Empty (śūnya)")
    ("སྟོང་ཉིད" . "Emptiness (śūnyatā)")
    ("སྣང་སྟོང" . "Appearance-emptiness")
    ("སྟོང་ཆ" . "Aspect of emptiness")

    ;; Dependent Arising
    ("རྟེན་ཅིང་འབྲེལ་བར་འབྱུང་བ" . "Dependent arising (pratītyasamutpāda)")
    ("རྟེན་འབྱུང" . "Dependent arising (pratītyasamutpāda)")
    ("རྟེན་འབྲེལ" . "Dependent relationship")

    ;; Nature & Characteristics
    ("ངོ་བོ" . "Nature/essence (svabhāva)")
    ("ངོ་བོ་ཉིད" . "Essential nature")
    ("མཚན་ཉིད" . "Definition/characteristic (lakṣaṇa)")
    ("རང་བཞིན" . "Own-nature (svabhāva)")
    ("གནས་ལུགས" . "Mode of abiding/reality")
    ("གནས་ཚུལ" . "Mode of existence")

    ;; Union & Non-duality
    ("ཟུང་འཇུག" . "Union/conjunction (yuganaddha)")
    ("དབྱེར་མེད" . "Inseparable/non-dual")
    ("གཉིས་མེད" . "Non-dual")
    ("གཉིས་སུ་མེད་པ" . "Not two/non-dual")

    ;; Ground, Path, Result
    ("གཞི" . "Ground/basis")
    ("ལམ" . "Path")
    ("འབྲས་བུ" . "Result/fruit")
    ("འབྲས" . "Result")

    ;; Appearance & Reality
    ("སྣང་བ" . "Appearance")
    ("སྣང་ཚུལ" . "Mode of appearance")
    ("གནས་སྣང" . "Reality-appearance")
    ("སྣང་བའི་ཆ" . "Aspect of appearance")

    ;; Valid Cognition
    ("ཚད་མ" . "Valid cognition (pramāṇa)")
    ("རྣམ་དག་ཚད་མ" . "Pure valid cognition")
    ("དོན་དཔྱོད་ཚད་མ" . "Valid cognition analyzing meaning")

    ;; Conceptual/Non-conceptual
    ("རྣམ་གྲངས་པ" . "Conceptual/with enumeration")
    ("རྣམ་གྲངས་མིན་པ" . "Non-conceptual/without enumeration")

    ;; Confusion & Clarity
    ("འཁྲུལ་སྣང" . "Confused appearance")
    ("འཁྲུལ་པ" . "Confusion/error")
    ("གསལ་བ" . "Clear/clarity")

    ;; Correct & Incorrect
    ("ཡང་དག" . "Correct/authentic")
    ("ལོག་པ" . "Incorrect/false")
    ("ལོག་ཤེས" . "Wrong consciousness")

    ;; Establishment & Refutation
    ("སྒྲུབ་པ" . "Establish/prove")
    ("དགག་པ" . "Refute/negate")
    ("བཀག་པ" . "Negated")

    ;; Extremes
    ("མཐའ" . "Extreme")
    ("སྤྲོས་པ" . "Elaboration (prapañca)")
    ("སྤྲོས་བྲལ" . "Free from elaboration")

    ;; Understanding
    ("ཤེས་པ" . "Know/cognize")
    ("རྟོགས་པ" . "Realize/comprehend")
    ("བློ" . "Mind/consciousness")
    ("ཤེས་བྱ" . "Object of knowledge")

    ;; Investigation
    ("དཔྱད་པ" . "Analyze/investigate")
    ("འཇལ་བྱེད" . "Measuring/investigating")
    ("གཞལ་བྱ" . "Object of measurement")

    ;; Purpose & Function
    ("དགོས་པ" . "Purpose/function")
    ("ཕྱིར" . "For the sake of/because")

    ;; Sutras & Sources
    ("ངེས་དོན" . "Definitive meaning (nītārtha)")
    ("མདོ་སྡེ" . "Sūtra")
    ("གསུང" . "Speech/teaching (of Buddha)")

    ;; Luminosity
    ("འོད་གསལ" . "Clear light/luminosity")

    ;; Depth & Peace
    ("ཟབ་པ" . "Profound/deep")
    ("ཞི་བ" . "Peace/tranquil")

    ;; Grasping
    ("དངོས་པོར་འཛིན་པ" . "Grasping at true existence")
    ("དངོས་འཛིན" . "Grasping at entities")
    ("འཛིན་པ" . "Grasp/apprehend")

    ;; Mind/Consciousness
    ("སེམས" . "Mind/consciousness (citta)")
    ("རང་བཞིན" . "Nature (svabhāva)")

    ;; Presentation
    ("རྣམ་གཞག" . "Presentation/exposition")
    ("བསྟན་པ" . "Teaching/exposition")
    ("བཤད་པ" . "Explanation")

    ;; Summary
    ("བསྡུས་དོན" . "Summary/abridged meaning")
    ("མདོར་བསྟན" . "Brief presentation")
    ("རྒྱས་པར་བཤད" . "Extensive explanation")

    ;; Classification
    ("དབྱེ་བ" . "Division/classification")
    ("ཕྱེ་བ" . "Distinguish/divide")
    ("རྣམ་པ" . "Type/aspect")

    ;; Etymology
    ("ངེས་ཚིག" . "Etymology/term analysis")

    ;; Practice
    ("ཉམས་ལེན" . "Practice/cultivation")
    ("ཐབས" . "Method/means (upāya)")

    ;; Determination
    ("ཐག་བཅད" . "Decide/determine")
    ("གཏན་ལ་འབེབས་པ" . "Establish definitively")

    ;; Ordinary & Noble
    ("སོ་སྐྱེ" . "Ordinary being (pṛthagjana)")
    ("འཕགས་པ" . "Noble/ārya")

    ;; Designation
    ("ཐ་སྙད" . "Designation/convention")
    ("མིང" . "Name/designation")
    ))

;; ============================================================================
;; GELUGPA-SPECIFIC USAGE
;; ============================================================================

(defvar tibetan-gelugpa-specific-usage
  '(("རྣམ་གྲངས་པའི་དོན་དམ" . "Quasi-ultimate (conceptual ultimate) - Gelugpa: ultimate found through reasoning")
    ("རྣམ་གྲངས་མིན་པའི་དོན་དམ" . "True ultimate (non-conceptual) - Gelugpa: emptiness itself")
    ("དོན་དམ་དངོས" . "Actual ultimate")
    ("ཀུན་རྫོབ་ཡང་དག" . "Correct conventional (authentic conventional truth)")
    ("ཀུན་རྫོབ་ལོག་པ" . "Incorrect conventional (false conventional)")
    ("གནས་ལུགས་ལ་དགག་སྒྲུབ་མེད" . "No negation or affirmation in reality-as-it-is")
    ("བློའི་ཡུལ་ལ་དགག་སྒྲུབ་ཡོད" . "Negation and affirmation exist for consciousness")
    ))

;; ============================================================================
;; VOCABULARY HASH TABLE
;; ============================================================================

(defvar tibetan-madhyamaka-vocabulary nil
  "Hash table for Madhyamaka philosophical terminology.
Populated from tibetan-madhyamaka-core-terms and tibetan-gelugpa-specific-usage.")

(defun tibetan-initialize-madhyamaka-vocabulary ()
  "Initialize the Madhyamaka vocabulary hash table from the term lists."
  (unless tibetan-madhyamaka-vocabulary
    (setq tibetan-madhyamaka-vocabulary (make-hash-table :test 'equal))
    (dolist (term-pair tibetan-madhyamaka-core-terms)
      (puthash (car term-pair) (cdr term-pair) tibetan-madhyamaka-vocabulary))
    (dolist (term-pair tibetan-gelugpa-specific-usage)
      (puthash (car term-pair) (cdr term-pair) tibetan-madhyamaka-vocabulary))))

;; Initialize on load
(tibetan-initialize-madhyamaka-vocabulary)

;; ============================================================================
;; VOCABULARY LOOKUP
;; ============================================================================

(defun tibetan-madhyamaka--term-present-p (term text)
  "Non-nil when TERM occurs in TEXT as a whole, tsheg/shad/space-
delimited unit (not as a substring inside a larger syllable).

TERM is matched literally (regexp-quoted), bounded on each side by
string start/end or a Tibetan delimiter (tsheg ་, shad །༎༔, space,
tab, newline).  This prevents e.g. the core term `ལམ' matching inside
the unrelated syllable `ལམས'.

Note:  it does NOT resolve compound-internal matches — `ལམ' is a
genuine tsheg-delimited syllable inside `ལམ་རིམ', so it still matches
there.  Distinguishing word- from syllable-boundaries needs real
Tibetan word segmentation, out of scope here."
  (let ((case-fold-search nil))
    (string-match-p
     (concat "\\(?:^\\|[་།༎༔ \t\n]\\)"
             (regexp-quote term)
             "\\(?:$\\|[་།༎༔ \t\n]\\)")
     text)))

(defun tibetan-extract-madhyamaka-vocabulary (tibetan-text)
  "Extract Madhyamaka technical terms from TIBETAN-TEXT.
Returns list of (tibetan-term . english-explanation).  Terms match as
whole tsheg/shad/space-delimited units (see
`tibetan-madhyamaka--term-present-p')."
  (let ((found-terms '()))
    (dolist (term-pair tibetan-madhyamaka-core-terms)
      (when (tibetan-madhyamaka--term-present-p (car term-pair) tibetan-text)
        (push term-pair found-terms)))
    (dolist (term-pair tibetan-gelugpa-specific-usage)
      (when (tibetan-madhyamaka--term-present-p (car term-pair) tibetan-text)
        (push term-pair found-terms)))
    (nreverse found-terms)))

(provide 'tibetan-madhyamaka-terms)
;;; tibetan-madhyamaka-terms.el ends here
