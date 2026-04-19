;;; tibetan-translation-suggest-test.el --- Tests for tibetan-translation-suggest.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for translation suggestion functionality.
;; Tests cover translation generation and converb translation guidance.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-translation-suggest)

;; ============================================================================
;; TRANSLATION SUGGESTION TESTS
;; ============================================================================

(ert-deftest tibetan-suggest-translation-function-exists ()
  "Test that tibetan-suggest-translation function exists."
  (should (fboundp 'tibetan-suggest-translation)))

(ert-deftest tibetan-suggest-translation-empty-inputs ()
  "Test translation suggestion with empty inputs."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  ;; Empty vocab and grammar lists
  (let ((result (tibetan-suggest-translation "བདག" '() '())))
    (should (stringp result))))

(ert-deftest tibetan-suggest-translation-with-vocab ()
  "Test translation suggestion with vocabulary list."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  ;; Test with sample vocabulary
  (let ((vocab '(("བདག" . "I") ("བྱེད" . "do")))
        (grammar '()))
    (let ((result (tibetan-suggest-translation "བདག་བྱེད" vocab grammar)))
      (should (stringp result))
      ;; Should contain vocabulary meanings
      (should (string-match-p "I" result)))))

(ert-deftest tibetan-suggest-translation-with-grammar ()
  "Test translation suggestion with grammatical analysis."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  ;; Test with sample grammar analysis
  (let ((vocab '(("པ" . "do")))
        (grammar '(("པས" "པས" "ERGATIVE (ERG)" "marks agent" "by agent" "Bialek"))))
    (let ((result (tibetan-suggest-translation "པས" vocab grammar)))
      (should (stringp result)))))

(ert-deftest tibetan-suggest-translation-returns-string ()
  "Test that translation suggestion always returns a string."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  ;; Various inputs
  (let ((result1 (tibetan-suggest-translation "བདག" '() '()))
        (result2 (tibetan-suggest-translation "" '() '()))
        (result3 (tibetan-suggest-translation "བདག" '(("བདག" . "I")) '())))
    (should (stringp result1))
    (should (stringp result2))
    (should (stringp result3))))

;; ============================================================================
;; CONVERB TRANSLATION GUIDE TESTS
;; ============================================================================

(ert-deftest tibetan-explain-converb-translation-function-exists ()
  "Test that tibetan-explain-converb-translation function exists."
  (should (fboundp 'tibetan-explain-converb-translation)))

(ert-deftest tibetan-explain-converb-translation-empty-grammar ()
  "Test converb translation guide with empty grammar list."
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  (let ((result (tibetan-explain-converb-translation '())))
    (should (stringp result))))

(ert-deftest tibetan-explain-converb-translation-no-converbs ()
  "Test converb guide when no converbs in grammar."
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  ;; Grammar with only case particles, no converbs
  (let ((grammar '(("གིས" "མི་གིས" "ERGATIVE (ERG)" "marks agent" "by agent" "Bialek"))))
    (let ((result (tibetan-explain-converb-translation grammar)))
      (should (stringp result))
      ;; Should be empty string or indicate no converbs
      (should (or (equal result "")
                  (string-match-p "converbial" result))))))

(ert-deftest tibetan-explain-converb-translation-with-converbs ()
  "Test converb guide with actual converbial constructions."
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  ;; Grammar including converbs
  (let ((grammar '(("ནས" "གསེགས་ནས" "CONVERBIAL: ABLATIVE CONVERB" "sequential" "having done" "Bialek"))))
    (let ((result (tibetan-explain-converb-translation grammar)))
      (should (stringp result)))))

(ert-deftest tibetan-explain-converb-translation-returns-string ()
  "Test that converb translation guide always returns a string."
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  ;; Various inputs
  (let ((result1 (tibetan-explain-converb-translation '()))
        (result2 (tibetan-explain-converb-translation '(("ས" "word" "OTHER" "func" "trans" "ref"))))
        (result3 (tibetan-explain-converb-translation '(("ནས" "word" "CONVERBIAL: ABLATIVE" "seq" "having" "Bialek")))))
    (should (stringp result1))
    (should (stringp result2))
    (should (stringp result3))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-translation-workflow ()
  "Test complete translation suggestion workflow."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  ;; Create a sample segment with vocabulary and grammar
  (let ((vocab '(("དེ" . "this") ("ས" . "[ergative]")))
        (grammar '(("གིས" "དེ་གིས" "ERGATIVE (ERG)" "agent" "by" "Bialek"))))
    ;; Generate translation
    (let ((translation (tibetan-suggest-translation "དེ་གིས" vocab grammar)))
      (should (stringp translation))
      ;; Generate converb guide if applicable
      (let ((converb-guide (tibetan-explain-converb-translation grammar)))
        (should (stringp converb-guide))))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-suggest-translation-nil-text ()
  "Test translation suggestion with nil text."
  (skip-unless (fboundp 'tibetan-suggest-translation))
  ;; Should handle gracefully or error clearly
  (let ((result (condition-case err
                    (tibetan-suggest-translation nil '() '())
                  (error "handled"))))
    (should result)))

(ert-deftest tibetan-explain-converb-translation-malformed-grammar ()
  "Test converb guide with malformed grammar entries."
  (skip-unless (fboundp 'tibetan-explain-converb-translation))
  ;; Incomplete grammar entries
  (let ((grammar '((nil "word" "CONVERBIAL" "func"))))
    (let ((result (condition-case err
                      (tibetan-explain-converb-translation grammar)
                    (error "handled"))))
      (should (or (stringp result) (equal result "handled"))))))

(provide 'tibetan-translation-suggest-test)
;;; tibetan-translation-suggest-test.el ends here
