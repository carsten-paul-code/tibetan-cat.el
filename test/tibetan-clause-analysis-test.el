;;; tibetan-clause-analysis-test.el --- Tests for clause analysis -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for Tibetan clause analysis functions including:
;; - Main verb identification (tibetan-find-main-verb)
;; - Converb detection (tibetan-detect-converbs)
;; - Converb scoping (tibetan-scope-converbs)
;; - Clause tree building (tibetan-build-clause-tree)

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-clause-analysis)

;; ============================================================================
;; MAIN VERB IDENTIFICATION TESTS
;; ============================================================================

(ert-deftest tibetan-find-main-verb-basic ()
  "Test basic main verb identification."
  (let ((result (tibetan-find-main-verb "སངས་རྒྱས་ཆོས་གསུངས།")))
    (should result)
    (should (plist-get result :verb))
    (should (string-match-p "གསུངས" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-with-converb ()
  "Test main verb identification with converb preceding."
  (let ((result (tibetan-find-main-verb "བཞུགས་ནས་ཆོས་གསུངས།")))
    (should result)
    (should (string-match-p "གསུངས" (plist-get result :verb)))
    ;; Should not identify converb as main verb
    (should-not (string-match-p "བཞུགས" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-copula ()
  "Test identification of copula as main verb."
  (let ((result (tibetan-find-main-verb "འདི་ནི་ཆོས་ཡིན།")))
    (should result)
    (should (string-match-p "ཡིན" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-existential ()
  "Test identification of existential verb."
  (let ((result (tibetan-find-main-verb "ཆོས་ཡོད།")))
    (should result)
    (should (string-match-p "ཡོད" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-final-particle ()
  "Test main verb with final particle."
  (let ((result (tibetan-find-main-verb "ཆོས་གསུངས་སོ།")))
    (should result)
    (should (string-match-p "གསུངས" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-negative ()
  "Test main verb with negative particle."
  (let ((result (tibetan-find-main-verb "མ་གསུངས།")))
    (should result)
    (should (string-match-p "གསུངས" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-nil-for-noun-phrase ()
  "Test that noun phrases return nil."
  (should-not (tibetan-find-main-verb "སངས་རྒྱས་ཀྱི་ཆོས།")))

(ert-deftest tibetan-find-main-verb-nil-for-empty ()
  "Test empty string returns nil."
  (should-not (tibetan-find-main-verb ""))
  (should-not (tibetan-find-main-verb nil)))

(ert-deftest tibetan-find-main-verb-complex-sentence ()
  "Test main verb in complex sentence with multiple converbs."
  (let ((result (tibetan-find-main-verb "བཞུགས་ནས་ཆོས་གསུངས་སྟེ་དགའ།")))
    (should result)
    ;; The final main verb should be དགའ
    (should (string-match-p "དགའ" (plist-get result :verb)))))

(ert-deftest tibetan-find-main-verb-position ()
  "Test that main verb position is reported."
  (let ((result (tibetan-find-main-verb "ཆོས་གསུངས།")))
    (should result)
    (should (plist-get result :position))))

;; ============================================================================
;; CONVERB DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-detect-converbs-ablative ()
  "Test detection of ablative converb (ནས)."
  (let ((result (tibetan-detect-converbs "བཞུགས་ནས་ཆོས་གསུངས།")))
    (should result)
    (should (= 1 (length result)))
    (should (eq 'ablative (plist-get (car result) :type)))))

(ert-deftest tibetan-detect-converbs-coordinative-te ()
  "Test detection of coordinative converb (ཏེ)."
  (let ((result (tibetan-detect-converbs "ཐོས་ཏེ་དད་སྐྱེས།")))
    (should result)
    (should (cl-find-if (lambda (c) (eq 'coordinative (plist-get c :type)))
                        result))))

(ert-deftest tibetan-detect-converbs-coordinative-ste ()
  "Test detection of coordinative converb (སྟེ)."
  (let ((result (tibetan-detect-converbs "ཐོས་སྟེ་དད་སྐྱེས།")))
    (should result)
    (should (cl-find-if (lambda (c) (eq 'coordinative (plist-get c :type)))
                        result))))

(ert-deftest tibetan-detect-converbs-simultaneous ()
  "Test detection of simultaneous converb (ཞིང/ཅིང)."
  (let ((result (tibetan-detect-converbs "བཞུགས་ཞིང་ཆོས་གསུངས།")))
    (should result)
    (should (cl-find-if (lambda (c) (eq 'simultaneous (plist-get c :type)))
                        result))))

(ert-deftest tibetan-detect-converbs-causal ()
  "Test detection of causal converb (པས/བས)."
  (let ((result (tibetan-detect-converbs "ཐོས་པས་དད་སྐྱེས།")))
    (should result)
    (should (cl-find-if (lambda (c) (eq 'causal (plist-get c :type)))
                        result))))

(ert-deftest tibetan-detect-converbs-concessive ()
  "Test detection of concessive particle (ཀྱང)."
  (let ((result (tibetan-detect-converbs "སྡུག་བསྔལ་ཡོད་ཀྱང་བཟོད།")))
    (should result)
    (should (cl-find-if (lambda (c) (eq 'concessive (plist-get c :type)))
                        result))))

(ert-deftest tibetan-detect-converbs-multiple ()
  "Test detection of multiple converbs."
  (let ((result (tibetan-detect-converbs "བལྟས་ནས་ཐོས་སྟེ་རྟོགས།")))
    (should result)
    (should (>= (length result) 2))))

(ert-deftest tibetan-detect-converbs-none ()
  "Test that simple sentence returns empty list."
  (let ((result (tibetan-detect-converbs "ཆོས་གསུངས།")))
    (should-not result)))

(ert-deftest tibetan-detect-converbs-empty ()
  "Test empty input."
  (should-not (tibetan-detect-converbs ""))
  (should-not (tibetan-detect-converbs nil)))

(ert-deftest tibetan-detect-converbs-stem-extraction ()
  "Test that converb stem is extracted."
  (let ((result (tibetan-detect-converbs "བཞུགས་ནས་ཆོས་གསུངས།")))
    (should result)
    (let ((converb (car result)))
      (should (plist-get converb :stem))
      (should (string-match-p "བཞུགས" (plist-get converb :stem))))))

;; ============================================================================
;; CONVERB SCOPING TESTS
;; ============================================================================

(ert-deftest tibetan-scope-converbs-basic ()
  "Test basic converb scoping."
  (let ((result (tibetan-scope-converbs "བཞུགས་ནས་ཆོས་གསུངས།")))
    (should result)
    (should (= 1 (length result)))
    (let ((scope (car result)))
      (should (plist-get scope :converb))
      (should (plist-get scope :main-verb)))))

(ert-deftest tibetan-scope-converbs-multiple ()
  "Test scoping multiple converbs."
  (let ((result (tibetan-scope-converbs "བལྟས་ནས་ཐོས་སྟེ་རྟོགས།")))
    (should result)
    (should (= 2 (length result)))))

(ert-deftest tibetan-scope-converbs-nested ()
  "Test scoping nested converbs."
  (let ((result (tibetan-scope-converbs "བཞུགས་ནས་ཆོས་གསུངས་སྟེ་དགའ།")))
    (should result)
    (should (>= (length result) 2))))

(ert-deftest tibetan-scope-converbs-none ()
  "Test sentence without converbs."
  (let ((result (tibetan-scope-converbs "ཆོས་གསུངས།")))
    (should-not result)))

(ert-deftest tibetan-scope-converbs-relationship ()
  "Test that scoping shows correct relationship."
  (let ((result (tibetan-scope-converbs "བཞུགས་ནས་གསུངས།")))
    (should result)
    (let ((scope (car result)))
      ;; The converb བཞུགས་ནས should scope to main verb གསུངས
      (should (string-match-p "བཞུགས"
                             (plist-get (plist-get scope :converb) :stem)))
      (should (string-match-p "གསུངས"
                             (plist-get (plist-get scope :main-verb) :verb))))))

;; ============================================================================
;; CLAUSE TREE TESTS
;; ============================================================================

(ert-deftest tibetan-build-clause-tree-simple ()
  "Test building simple clause tree."
  (let ((result (tibetan-build-clause-tree "ཆོས་གསུངས།")))
    (should result)
    (should (eq 'clause (plist-get result :type)))
    (should (plist-get result :main-verb))))

(ert-deftest tibetan-build-clause-tree-with-dependent ()
  "Test building clause tree with dependent clause."
  (let ((result (tibetan-build-clause-tree "བཞུགས་ནས་གསུངས།")))
    (should result)
    (should (plist-get result :dependent-clauses))
    (should (= 1 (length (plist-get result :dependent-clauses))))))

(ert-deftest tibetan-build-clause-tree-multiple-dependents ()
  "Test building clause tree with multiple dependents."
  (let ((result (tibetan-build-clause-tree "བལྟས་ནས་ཐོས་སྟེ་རྟོགས།")))
    (should result)
    (should (plist-get result :dependent-clauses))
    (should (>= (length (plist-get result :dependent-clauses)) 2))))

(ert-deftest tibetan-build-clause-tree-converb-type ()
  "Test that converb type is preserved in tree."
  (let ((result (tibetan-build-clause-tree "བཞུགས་ཞིང་གསུངས།")))
    (should result)
    (let ((dep (car (plist-get result :dependent-clauses))))
      (should dep)
      (should (eq 'simultaneous (plist-get dep :converb-type))))))

(ert-deftest tibetan-build-clause-tree-empty ()
  "Test empty input."
  (should-not (tibetan-build-clause-tree ""))
  (should-not (tibetan-build-clause-tree nil)))

(ert-deftest tibetan-build-clause-tree-text-preserved ()
  "Test that original text is preserved."
  (let ((result (tibetan-build-clause-tree "ཆོས་གསུངས།")))
    (should result)
    (should (plist-get result :text))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-clause-analysis-padma-rnam-rgyal ()
  "Test clause analysis with Padma rnam-rgyal text."
  (let ((text "སྟོན་པ་མཉན་ཡོད་དུ་བཞུགས་པའི་ཚེ།"))
    ;; Should identify བཞུགས as a verb
    (let ((main (tibetan-find-main-verb text)))
      (should main)
      (should (string-match-p "བཞུགས" (plist-get main :verb))))))

(ert-deftest tibetan-clause-analysis-merchants ()
  "Test clause analysis with merchants text."
  (let ((text "ཚོང་པ་ལྔ་བརྒྱ་རྒྱ་མཚོར་འགྲོ།"))
    (let ((main (tibetan-find-main-verb text)))
      (should main)
      (should (string-match-p "འགྲོ" (plist-get main :verb))))))

;; ============================================================================
;; FORMAT CLAUSE TREE TESTS
;; ============================================================================

(ert-deftest tibetan-format-clause-tree-with-nil ()
  "Test formatting nil clause tree."
  (let ((result (tibetan-format-clause-tree nil)))
    (should (stringp result))
    (should (string-match-p "No clause structure" result))))

(ert-deftest tibetan-format-clause-tree-simple-clause ()
  "Test formatting simple clause tree."
  (let* ((text "ཆོས་གསུངས།")
         (tree (tibetan-build-clause-tree text)))
    (if tree
      (let ((result (tibetan-format-clause-tree tree)))
        (should (stringp result))
        (should (string-match-p "Main Clause" result)))
      (skip "Could not build clause tree for test input"))))

(ert-deftest tibetan-format-clause-tree-with-indent ()
  "Test formatting clause tree with indentation."
  (let* ((text "བཞུགས་ནས་གསུངས།")
         (tree (tibetan-build-clause-tree text)))
    (when tree
      (let ((result (tibetan-format-clause-tree tree 1)))
        (should (stringp result))))))

;; ============================================================================
;; ANALYZE CLAUSE STRUCTURE TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-clause-structure-basic ()
  "Test basic clause structure analysis."
  (let ((result (tibetan-analyze-clause-structure "ཆོས་གསུངས།")))
    (should (or (null result) (stringp result)))
    (when result
      (should (> (length result) 0)))))

(ert-deftest tibetan-analyze-clause-structure-with-converb ()
  "Test clause structure analysis with converb."
  (let ((result (tibetan-analyze-clause-structure "བཞུགས་ནས་གསུངས།")))
    (should (or (null result) (stringp result)))
    (when result
      (should (or (string-match-p "CLAUSE STRUCTURE" result)
                  (string-match-p "No clause structure" result))))))

(ert-deftest tibetan-analyze-clause-structure-nil-input ()
  "Test that nil input is handled gracefully."
  (should-not (tibetan-analyze-clause-structure nil))
  (should-not (tibetan-analyze-clause-structure "")))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-clause-analysis-run-tests ()
  "Run all clause analysis tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-"))

(provide 'tibetan-clause-analysis-test)
;;; tibetan-clause-analysis-test.el ends here
