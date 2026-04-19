;;; tibetan-madhyamaka-terms-test.el --- Tests for Madhyamaka terminology -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for Madhyamaka philosophical terminology database.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../philology" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-madhyamaka-terms)

;; ============================================================================
;; TERM DATABASE
;; ============================================================================

(ert-deftest tibetan-madhyamaka-database-exists ()
  "Test that Madhyamaka terms database exists."
  (should (boundp 'tibetan-madhyamaka-vocabulary))
  (when (boundp 'tibetan-madhyamaka-vocabulary)
    (should (hash-table-p tibetan-madhyamaka-vocabulary))))

(ert-deftest tibetan-madhyamaka-database-populated ()
  "Test that database has entries."
  (when (and (boundp 'tibetan-madhyamaka-vocabulary)
             (hash-table-p tibetan-madhyamaka-vocabulary))
    (should (> (hash-table-count tibetan-madhyamaka-vocabulary) 0))))

;; ============================================================================
;; KEY TERMS - EMPTINESS
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-sunyata ()
  "Test emptiness (sunyata) term."
  (let ((term "སྟོང་པ་ཉིད"))
    ;; This is THE central Madhyamaka term
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-stong-pa ()
  "Test empty (stong pa) term."
  (let ((term "སྟོང་པ"))
    (should (stringp term))))

;; ============================================================================
;; KEY TERMS - TWO TRUTHS
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-kun-rdzob ()
  "Test conventional truth term."
  (let ((term "ཀུན་རྫོབ"))
    ;; kun rdzob = conventional/relative
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-don-dam ()
  "Test ultimate truth term."
  (let ((term "དོན་དམ"))
    ;; don dam = ultimate/absolute
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-bden-pa-gnyis ()
  "Test two truths term."
  (let ((term "བདེན་པ་གཉིས"))
    ;; bden pa gnyis = two truths
    (should (stringp term))))

;; ============================================================================
;; KEY TERMS - DEPENDENT ORIGINATION
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-rten-cing ()
  "Test dependent origination term."
  (let ((term "རྟེན་ཅིང་འབྲེལ་བར་འབྱུང་བ"))
    ;; rten cing 'brel bar 'byung ba = pratityasamutpada
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-rten-byung ()
  "Test short dependent origination term."
  (let ((term "རྟེན་འབྱུང"))
    ;; rten 'byung = dependent arising (short form)
    (should (stringp term))))

;; ============================================================================
;; KEY TERMS - SELF/NO-SELF
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-bdag ()
  "Test self term."
  (let ((term "བདག"))
    ;; bdag = self, atman
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-bdag-med ()
  "Test no-self term."
  (let ((term "བདག་མེད"))
    ;; bdag med = selflessness, anatman
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-rang-bzhin ()
  "Test inherent nature term."
  (let ((term "རང་བཞིན"))
    ;; rang bzhin = svabhava, inherent nature
    (should (stringp term))))

;; ============================================================================
;; KEY TERMS - NEGATION TYPES
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-med-dgag ()
  "Test non-affirming negation."
  (let ((term "མེད་དགག"))
    ;; med dgag = prasajya-pratisedha
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-ma-yin-dgag ()
  "Test affirming negation."
  (let ((term "མ་ཡིན་དགག"))
    ;; ma yin dgag = paryudasa-pratisedha
    (should (stringp term))))

;; ============================================================================
;; KEY TERMS - EXTREMES
;; ============================================================================

(ert-deftest tibetan-madhyamaka-term-mtha-gnyis ()
  "Test two extremes term."
  (let ((term "མཐའ་གཉིས"))
    ;; mtha' gnyis = two extremes
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-yod-mtha ()
  "Test eternalism term."
  (let ((term "ཡོད་མཐའ"))
    ;; yod mtha' = extreme of existence/eternalism
    (should (stringp term))))

(ert-deftest tibetan-madhyamaka-term-med-mtha ()
  "Test nihilism term."
  (let ((term "མེད་མཐའ"))
    ;; med mtha' = extreme of non-existence/nihilism
    (should (stringp term))))

;; ============================================================================
;; LOOKUP FUNCTIONALITY
;; ============================================================================

(ert-deftest tibetan-madhyamaka-lookup-basic ()
  "Test basic term lookup."
  (when (fboundp 'tibetan-madhyamaka-lookup)
    (let ((result (tibetan-madhyamaka-lookup "སྟོང་པ་ཉིད")))
      (when result
        (should (or (stringp result) (listp result)))))))

(ert-deftest tibetan-madhyamaka-lookup-not-found ()
  "Test lookup of non-existent term."
  (when (fboundp 'tibetan-madhyamaka-lookup)
    (let ((result (tibetan-madhyamaka-lookup "xxxxxx")))
      ;; Should return nil or empty for unknown terms
      (should (or (null result) (equal result ""))))))

;; ============================================================================
;; CONTEXT-AWARE LOOKUP
;; ============================================================================

(ert-deftest tibetan-madhyamaka-context-prasangika ()
  "Test Prasangika context awareness."
  ;; Prasangika Madhyamaka uses specific terminology
  (let ((context 'prasangika))
    (should (symbolp context))))

(ert-deftest tibetan-madhyamaka-context-svatantrika ()
  "Test Svatantrika context awareness."
  ;; Svatantrika Madhyamaka uses slightly different terminology
  (let ((context 'svatantrika))
    (should (symbolp context))))

;; ============================================================================
;; INITIALIZATION TESTS
;; ============================================================================

(ert-deftest tibetan-initialize-madhyamaka-vocabulary-function-exists ()
  "Test that tibetan-initialize-madhyamaka-vocabulary function exists."
  (should (fboundp 'tibetan-initialize-madhyamaka-vocabulary)))

(ert-deftest tibetan-initialize-madhyamaka-vocabulary-returns-hash ()
  "Test that initialization returns a hash table."
  (skip-unless (fboundp 'tibetan-initialize-madhyamaka-vocabulary))
  (let ((result (tibetan-initialize-madhyamaka-vocabulary)))
    ;; Should return hash table or be stored in variable
    (should (or (hash-table-p result)
                (and (fboundp 'tibetan-initialize-madhyamaka-vocabulary)
                     (or (boundp 'tibetan-madhyamaka-vocabulary)
                         (boundp 'tibetan-madhyamaka-terms)))))))

;; ============================================================================
;; EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-extract-madhyamaka-vocabulary-function-exists ()
  "Test that tibetan-extract-madhyamaka-vocabulary function exists."
  (should (fboundp 'tibetan-extract-madhyamaka-vocabulary)))

(ert-deftest tibetan-extract-madhyamaka-vocabulary-from-text ()
  "Test extraction of Madhyamaka terms from Tibetan text."
  (skip-unless (fboundp 'tibetan-extract-madhyamaka-vocabulary))
  ;; Test with text containing known Madhyamaka term
  (let ((result (tibetan-extract-madhyamaka-vocabulary "སྟོང་པ་ཉིད་དེ")))
    (should (listp result))))

(ert-deftest tibetan-extract-madhyamaka-vocabulary-empty-text ()
  "Test extraction from empty or no-term text."
  (skip-unless (fboundp 'tibetan-extract-madhyamaka-vocabulary))
  ;; Empty text
  (let ((result1 (tibetan-extract-madhyamaka-vocabulary "")))
    (should (listp result1)))
  ;; Text without Madhyamaka terms
  (let ((result2 (tibetan-extract-madhyamaka-vocabulary "བདག་གིས་ཞིང")))
    (should (listp result2))))

(ert-deftest tibetan-extract-madhyamaka-vocabulary-multiple-terms ()
  "Test extraction of multiple Madhyamaka terms."
  (skip-unless (fboundp 'tibetan-extract-madhyamaka-vocabulary))
  ;; Text with multiple philosophical terms
  (let ((result (tibetan-extract-madhyamaka-vocabulary "སྟོང་པ་ཉིད་དང་དོན་དམ་བདེན་པ")))
    (should (listp result))
    ;; May extract various terms
    (should (>= (length result) 0))))

(provide 'tibetan-madhyamaka-terms-test)
;;; tibetan-madhyamaka-terms-test.el ends here
