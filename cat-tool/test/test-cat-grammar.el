;;; test-cat-grammar.el --- Tests for cat-grammar.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for CAT grammar analysis functions.
;; Run with: M-x ert-run-tests-batch-and-exit RET test-cat-grammar RET

;;; Code:

(require 'ert)
(require 'cat-grammar)

;; ============================================================================
;; PARTICLE DETECTION TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-detect-ergative ()
  "Test ergative particle detection."
  (let ((p (cat-grammar-detect-particle "བདག་གིས")))
    (should p)
    (should (eq (cat-particle-type p) 'ergative))
    (should (string= (cat-particle-particle p) "གིས"))
    (should (string= (cat-particle-root p) "བདག་"))))

(ert-deftest test-cat-grammar-detect-ergative-kyis ()
  "Test ergative ཀྱིས detection."
  (let ((p (cat-grammar-detect-particle "མ་སྨད་ཀྱིས")))
    (should p)
    (should (eq (cat-particle-type p) 'ergative))
    (should (string= (cat-particle-particle p) "ཀྱིས"))))

(ert-deftest test-cat-grammar-detect-genitive ()
  "Test genitive particle detection."
  (let ((p (cat-grammar-detect-particle "དེའི")))
    (should p)
    (should (eq (cat-particle-type p) 'genitive))
    (should (string= (cat-particle-particle p) "འི"))
    (should (string= (cat-particle-root p) "དེ"))))

(ert-deftest test-cat-grammar-detect-genitive-kyi ()
  "Test genitive ཀྱི detection."
  (let ((p (cat-grammar-detect-particle "བདག་ཀྱི")))
    (should p)
    (should (eq (cat-particle-type p) 'genitive))
    (should (string= (cat-particle-particle p) "ཀྱི"))))

(ert-deftest test-cat-grammar-detect-dative-la ()
  "Test dative ལ detection."
  (let ((p (cat-grammar-detect-particle "གུམ་ལ")))
    (should p)
    (should (eq (cat-particle-type p) 'dative))
    (should (string= (cat-particle-particle p) "ལ"))))

(ert-deftest test-cat-grammar-detect-terminative-su ()
  "Test terminative སུ detection."
  (let ((p (cat-grammar-detect-particle "ཕྱོགས་སུ")))
    (should p)
    (should (eq (cat-particle-type p) 'terminative))
    (should (string= (cat-particle-particle p) "སུ"))))

(ert-deftest test-cat-grammar-detect-terminative-du ()
  "Test terminative དུ detection."
  (let ((p (cat-grammar-detect-particle "མཛད་དུ")))
    (should p)
    (should (eq (cat-particle-type p) 'terminative))
    (should (string= (cat-particle-particle p) "དུ"))))

(ert-deftest test-cat-grammar-detect-ablative-nas ()
  "Test ablative ནས detection."
  (let ((p (cat-grammar-detect-particle "འཚལ་ནས")))
    (should p)
    (should (eq (cat-particle-type p) 'ablative))
    (should (string= (cat-particle-particle p) "ནས"))))

(ert-deftest test-cat-grammar-detect-converb-ste ()
  "Test converb སྟེ detection."
  (let ((p (cat-grammar-detect-particle "བྱས་སྟེ")))
    (should p)
    (should (eq (cat-particle-type p) 'converb-coordinative))
    (should (string= (cat-particle-particle p) "སྟེ"))))

(ert-deftest test-cat-grammar-detect-converb-zhing ()
  "Test converb ཞིང detection."
  (let ((p (cat-grammar-detect-particle "བྱེད་ཞིང")))
    (should p)
    (should (eq (cat-particle-type p) 'converb-simultaneous))
    (should (string= (cat-particle-particle p) "ཞིང"))))

(ert-deftest test-cat-grammar-detect-causal-pas ()
  "Test causal པས detection."
  (let ((p (cat-grammar-detect-particle "སྨྲས་པས")))
    (should p)
    (should (eq (cat-particle-type p) 'causal))
    (should (string= (cat-particle-particle p) "པས"))))

(ert-deftest test-cat-grammar-detect-nominalizer-pa ()
  "Test nominalizer པ detection."
  (let ((p (cat-grammar-detect-particle "ཐུག་པ")))
    (should p)
    (should (eq (cat-particle-type p) 'nominalizer))
    (should (string= (cat-particle-particle p) "པ"))))

(ert-deftest test-cat-grammar-detect-concessive ()
  "Test concessive ཀྱང detection."
  (let ((p (cat-grammar-detect-particle "བདག་ཀྱང")))
    (should p)
    (should (eq (cat-particle-type p) 'concessive))
    (should (string= (cat-particle-particle p) "ཀྱང"))))

(ert-deftest test-cat-grammar-detect-no-particle ()
  "Test detection returns nil when no particle."
  (should-not (cat-grammar-detect-particle "བདག"))
  (should-not (cat-grammar-detect-particle "ཆོས")))

;; ============================================================================
;; STANDALONE PARTICLE TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-detect-standalone-na ()
  "Test standalone ན detection."
  (let ((p (cat-grammar-detect-standalone-particle "ན")))
    (should p)
    (should (eq (cat-particle-type p) 'locative))))

(ert-deftest test-cat-grammar-detect-standalone-la ()
  "Test standalone ལ detection."
  (let ((p (cat-grammar-detect-standalone-particle "ལ")))
    (should p)
    (should (eq (cat-particle-type p) 'dative))))

(ert-deftest test-cat-grammar-detect-standalone-nas ()
  "Test standalone ནས detection."
  (let ((p (cat-grammar-detect-standalone-particle "ནས")))
    (should p)
    (should (eq (cat-particle-type p) 'ablative))))

(ert-deftest test-cat-grammar-detect-standalone-not-particle ()
  "Test standalone detection returns nil for non-particles."
  (should-not (cat-grammar-detect-standalone-particle "བདག"))
  (should-not (cat-grammar-detect-standalone-particle "ཆོས")))

;; ============================================================================
;; TEXT ANALYSIS TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-analyze-text-simple ()
  "Test analysis of simple text with one particle."
  (let ((particles (cat-grammar-analyze-text "བདག་གིས")))
    (should (= (length particles) 1))
    (should (eq (cat-particle-type (car particles)) 'ergative))))

(ert-deftest test-cat-grammar-analyze-text-multiple ()
  "Test analysis of text with multiple particles."
  (let ((particles (cat-grammar-analyze-text "མ་སྨད་ཀྱིས་དེའི་ཕྱོགས་སུ")))
    (should (>= (length particles) 3))
    ;; Should find ergative, genitive, and terminative (སུ is now terminative, not dative)
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'ergative)) particles))
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'genitive)) particles))
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'terminative)) particles))))

(ert-deftest test-cat-grammar-analyze-text-empty ()
  "Test analysis of empty text."
  (should (null (cat-grammar-analyze-text ""))))

(ert-deftest test-cat-grammar-analyze-text-no-particles ()
  "Test analysis of text without particles."
  (should (null (cat-grammar-analyze-text "བདག་ཆོས"))))

;; ============================================================================
;; CASE/CONVERB FILTER TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-analyze-cases ()
  "Test filtering to case particles only."
  (let ((cases (cat-grammar-analyze-cases "མ་སྨད་ཀྱིས་བྱས་སྟེ")))
    ;; Should have ergative, but not converb
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'ergative)) cases))
    (should-not (cl-some (lambda (p) (eq (cat-particle-type p) 'converb-coordinative)) cases))))

(ert-deftest test-cat-grammar-analyze-converbs ()
  "Test filtering to converb particles only."
  (let ((converbs (cat-grammar-analyze-converbs "བྱས་སྟེ་བྱེད་ཞིང")))
    ;; Should have converbs
    (should (>= (length converbs) 2))))

;; ============================================================================
;; FORMATTING TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-get-type-name ()
  "Test type name retrieval."
  (should (string= (cat-grammar-get-type-name 'ergative) "ERGATIVE (ERG)"))
  (should (string= (cat-grammar-get-type-name 'genitive) "GENITIVE (GEN)"))
  (should (string= (cat-grammar-get-type-name 'dative) "DATIVE (DAT)"))
  (should (string= (cat-grammar-get-type-name 'terminative) "TERMINATIVE (TER)"))
  (should (string= (cat-grammar-get-type-name 'elative) "ELATIVE (ELA)")))

(ert-deftest test-cat-grammar-format-particle ()
  "Test particle formatting."
  (let* ((p (cat-grammar-detect-particle "བདག་གིས"))
         (formatted (cat-grammar-format-particle p)))
    (should (stringp formatted))
    (should (string-match-p "གིས" formatted))
    (should (string-match-p "ERGATIVE" formatted))))

(ert-deftest test-cat-grammar-format-analysis-empty ()
  "Test formatting of empty particle list."
  (let ((formatted (cat-grammar-format-analysis nil)))
    (should (string-match-p "No grammatical markers" formatted))))

;; ============================================================================
;; DETECT-ALL-IN-WORD TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-detect-all-ergative ()
  "Test detect-all finds ergative."
  (let ((results (cat-grammar-detect-all-in-word "བདག་གིས")))
    (should (cl-some (lambda (r) (eq (nth 0 r) 'ergative)) results))))

(ert-deftest test-cat-grammar-detect-all-genitive ()
  "Test detect-all finds genitive."
  (let ((results (cat-grammar-detect-all-in-word "དེའི")))
    (should (cl-some (lambda (r) (eq (nth 0 r) 'genitive)) results))))

(ert-deftest test-cat-grammar-detect-all-empty ()
  "Test detect-all returns nil for words without particles."
  (should (null (cat-grammar-detect-all-in-word "བདག"))))

;; ============================================================================
;; REAL-WORLD TEXT TESTS
;; ============================================================================

(ert-deftest test-cat-grammar-full-sentence ()
  "Test analysis of a full sentence from the text."
  (let* ((text "མ་སྨད་ཀྱིས་དེའི་ཕྱོགས་སུ་ཕྱག་འཚལ་ནས་གུམ་ལ་ཐུག་པ་འདིའི་སྐྱགས་མཛད་དུ་གསོལ་ཞེས་སྨྲས་པས")
         (particles (cat-grammar-analyze-text text)))
    ;; Should find multiple particles
    (should (> (length particles) 5))
    ;; Check for specific types
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'ergative)) particles))     ; ཀྱིས
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'genitive)) particles))     ; འི
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'terminative)) particles))  ; སུ, དུ
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'dative)) particles))       ; ལ
    (should (cl-some (lambda (p) (memq (cat-particle-type p) '(ablative elative ablative-temporal))) particles))  ; ནས
    (should (cl-some (lambda (p) (eq (cat-particle-type p) 'causal)) particles))))     ; པས

;; ============================================================================
;; TERMINATIVE VS DATIVE TESTS (Tibetan III)
;; ============================================================================

(ert-deftest test-cat-grammar-terminative-location ()
  "Test terminative for location: grong khyer der (TER)."
  (let ((p (cat-grammar-detect-particle "གྲོང་ཁྱེར་དེར")))
    (should p)
    (should (eq (cat-particle-type p) 'terminative))
    (should (string= (cat-particle-particle p) "ར"))))

(ert-deftest test-cat-grammar-terminative-adverbial ()
  "Test terminative for adverbial: rtag tu (TER)."
  (let ((p (cat-grammar-detect-particle "རྟག་ཏུ")))
    (should p)
    (should (eq (cat-particle-type p) 'terminative))
    (should (string= (cat-particle-particle p) "ཏུ"))))

(ert-deftest test-cat-grammar-dative-recipient ()
  "Test dative for recipient: kun dga' bo la (DAT)."
  (let ((p (cat-grammar-detect-particle "ཀུན་དགའ་བོ་ལ")))
    (should p)
    (should (eq (cat-particle-type p) 'dative))
    (should (string= (cat-particle-particle p) "ལ"))))

;; ============================================================================
;; ELATIVE VS ABLATIVE-TEMPORAL TESTS (Tibetan III)
;; ============================================================================

(ert-deftest test-cat-grammar-classify-nas-elative ()
  "Test ནས classification as elative for spatial origin."
  ;; Non-verb root → elative (spatial origin)
  (should (eq (cat-grammar-classify-nas-particle "རྒྱང་རིང་མོ་ནས") 'elative)))

(ert-deftest test-cat-grammar-classify-nas-ablative-temporal ()
  "Test ནས classification as ablative-temporal for verb root.
Note: This test requires the verb classifier to be loaded."
  ;; Verb root → ablative-temporal (if verb classifier available)
  ;; Without verb classifier, defaults to elative
  (let ((result (cat-grammar-classify-nas-particle "ཟིན་ནས")))
    ;; Either ablative-temporal (if verb classifier) or elative (fallback)
    (should (memq result '(elative ablative-temporal)))))

;; ============================================================================
;; ABSOLUTIVE DETECTION TESTS (Tibetan III)
;; ============================================================================

(ert-deftest test-cat-grammar-absolutive-struct ()
  "Test cat-absolutive struct creation."
  (let ((abs (make-cat-absolutive
              :word "བུ་གཉིས"
              :role 'existential-subject
              :verb nil
              :verb-info nil
              :confidence 'high)))
    (should (cat-absolutive-p abs))
    (should (string= (cat-absolutive-word abs) "བུ་གཉིས"))
    (should (eq (cat-absolutive-role abs) 'existential-subject))
    (should (eq (cat-absolutive-confidence abs) 'high))))

(ert-deftest test-cat-grammar-has-case-marker-p ()
  "Test case marker detection."
  ;; Word with ergative marker
  (should (cat-grammar-has-case-marker-p "བདག་གིས"))
  ;; Word with genitive marker
  (should (cat-grammar-has-case-marker-p "དེའི"))
  ;; Word without marker
  (should-not (cat-grammar-has-case-marker-p "བདག"))
  (should-not (cat-grammar-has-case-marker-p "ཆོས")))

(ert-deftest test-cat-grammar-absolutive-role-name ()
  "Test absolutive role name formatting."
  (should (string-match-p "intransitive" (cat-grammar-absolutive-role-name 'subject-intransitive)))
  (should (string-match-p "transitive" (cat-grammar-absolutive-role-name 'object-transitive)))
  (should (string-match-p "existential" (cat-grammar-absolutive-role-name 'existential-subject)))
  (should (string-match-p "Focus" (cat-grammar-absolutive-role-name 'focus))))

(ert-deftest test-cat-grammar-detect-absolutives-existential ()
  "Test absolutive detection before existential copula.
Example: bu gnyis shig (ABS) yod de"
  (let ((result (cat-grammar-detect-absolutives
                 '("བུ" "གཉིས" "ཤིག" "ཡོད" "དེ"))))
    ;; Should detect unmarked words before ཡོད as existential subjects
    (should (cl-some (lambda (abs)
                       (eq (cat-absolutive-role abs) 'existential-subject))
                     result))))

(ert-deftest test-cat-grammar-detect-absolutives-focus ()
  "Test absolutive detection for sentence-initial focus."
  (let ((result (cat-grammar-detect-absolutives
                 '("གླེང་གཞི" "སྟོན་པ" "མཉན་ཡོད" "ན"))))
    ;; First word might be detected as focus
    (should (cl-some (lambda (abs)
                       (eq (cat-absolutive-role abs) 'focus))
                     result))))

(ert-deftest test-cat-grammar-format-absolutive ()
  "Test absolutive formatting."
  (let* ((abs (make-cat-absolutive
               :word "བུ་གཉིས"
               :role 'existential-subject
               :verb nil
               :verb-info nil
               :confidence 'high))
         (formatted (cat-grammar-format-absolutive abs)))
    (should (stringp formatted))
    (should (string-match-p "བུ་གཉིས" formatted))
    (should (string-match-p "ABSOLUTIVE" formatted))
    (should (string-match-p "existential" formatted))))

;; ============================================================================
;; DETECT-ALL-IN-WORD WITH TERMINATIVE
;; ============================================================================

(ert-deftest test-cat-grammar-detect-all-terminative ()
  "Test detect-all finds terminative."
  (let ((results (cat-grammar-detect-all-in-word "ཕྱོགས་སུ")))
    (should (cl-some (lambda (r) (eq (nth 0 r) 'terminative)) results))))

(ert-deftest test-cat-grammar-detect-all-dative ()
  "Test detect-all finds dative (ལ only now)."
  (let ((results (cat-grammar-detect-all-in-word "གུམ་ལ")))
    (should (cl-some (lambda (r) (eq (nth 0 r) 'dative)) results))))

(provide 'test-cat-grammar)
;;; test-cat-grammar.el ends here
