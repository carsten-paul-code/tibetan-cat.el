;;; tibetan-verb-classifier-test.el --- Tests for tibetan-verb-classifier.el -*- lexical-binding: t -*-

(require 'ert)
(require 'tibetan-verb-classifier)

;; ============================================================================
;; VERB LOOKUP TESTS
;; ============================================================================

(ert-deftest tibetan-verb-lookup-known-verb ()
  "Test that known verbs are found in the database."
  (let ((result (tibetan-verb-lookup "བྱིན")))
    (should result)
    (should (alist-get 'lemma result))
    (should (string= "སྦྱིན" (alist-get 'lemma result)))
    (should (string= "to give" (alist-get 'meaning result)))))

(ert-deftest tibetan-verb-lookup-with-punctuation ()
  "Test that verbs with trailing shad are still found."
  (let ((result (tibetan-verb-lookup "བྱིན།")))
    (should result)
    (should (string= "སྦྱིན" (alist-get 'lemma result)))))

(ert-deftest tibetan-verb-lookup-unknown-verb ()
  "Test that unknown words return nil."
  (should-not (tibetan-verb-lookup "ཨ་མ")))  ; "mother" - not a verb

(ert-deftest tibetan-verb-lookup-empty-string ()
  "Test that empty string returns nil."
  (should-not (tibetan-verb-lookup ""))
  (should-not (tibetan-verb-lookup nil)))

(ert-deftest tibetan-verb-lookup-whitespace ()
  "Test that whitespace-only input returns nil."
  (should-not (tibetan-verb-lookup "   "))
  (should-not (tibetan-verb-lookup "\t\n")))

;; ============================================================================
;; VERB STEMS TESTS
;; ============================================================================

(ert-deftest tibetan-verb-stems-present ()
  "Test that present stem is correctly returned."
  (let ((result (tibetan-verb-lookup "བྱས")))  ; past of བྱེད "to do"
    (should result)
    (should (string= "བྱེད" (alist-get 'present_stem result)))))

(ert-deftest tibetan-verb-stems-past ()
  "Test that past stem is correctly returned."
  (let ((result (tibetan-verb-lookup "བྱེད")))
    (should result)
    (should (string= "བྱས" (alist-get 'past_stem result)))))

(ert-deftest tibetan-verb-stems-future ()
  "Test that future stem is correctly returned."
  (let ((result (tibetan-verb-lookup "བྱེད")))
    (should result)
    (should (string= "བྱ" (alist-get 'future_stem result)))))

(ert-deftest tibetan-verb-stems-imperative ()
  "Test that imperative stem is correctly returned."
  (let ((result (tibetan-verb-lookup "བྱེད")))
    (should result)
    (should (string= "བྱོས" (alist-get 'imperative_stem result)))))

;; ============================================================================
;; TRANSITIVITY TESTS
;; ============================================================================

(ert-deftest tibetan-verb-transitive ()
  "Test that transitive verbs are marked correctly."
  (let ((result (tibetan-verb-lookup "བྱེད")))  ; "to do" - transitive
    (should result)
    (should (string-match-p "Transitive" (alist-get 'transitivity result)))))

(ert-deftest tibetan-verb-intransitive ()
  "Test that intransitive verbs are marked correctly."
  (let ((result (tibetan-verb-lookup "འགྲོ")))  ; "to go" - intransitive
    (should result)
    (should (string-match-p "Intransitive" (alist-get 'transitivity result)))))

(ert-deftest tibetan-verb-copula ()
  "Test that copulas are marked correctly."
  (let ((result (tibetan-verb-lookup "ཡིན")))  ; "to be" - copula
    (should result)
    (should (string-match-p "Copula" (alist-get 'transitivity result)))))

;; ============================================================================
;; CASE FRAME TESTS
;; ============================================================================

(ert-deftest tibetan-verb-case-frame-erg-abs ()
  "Test Ergative-Absolutive case frame."
  (let ((result (tibetan-verb-lookup "བྱེད")))
    (should result)
    (should (string= "Erg-Abs" (alist-get 'case_frame result)))))

(ert-deftest tibetan-verb-case-frame-abs ()
  "Test Absolutive-only case frame (intransitive)."
  (let ((result (tibetan-verb-lookup "འགྲོ")))
    (should result)
    (should (string= "Abs" (alist-get 'case_frame result)))))

(ert-deftest tibetan-verb-case-frame-erg-abs-dat ()
  "Test Ergative-Absolutive-Dative case frame (ditransitive)."
  (let ((result (tibetan-verb-lookup "བྱིན")))  ; "to give"
    (should result)
    (should (string= "Erg-Abs-Dat" (alist-get 'case_frame result)))))

;; ============================================================================
;; INDIGENOUS CLASS TESTS
;; ============================================================================

(ert-deftest tibetan-verb-indigenous-transitive ()
  "Test tha dad pa (transitive) indigenous class."
  (let ((result (tibetan-verb-lookup "བྱེད")))
    (should result)
    (should (string= "tha_dad_pa" (alist-get 'indigenous_class result)))))

(ert-deftest tibetan-verb-indigenous-intransitive ()
  "Test tha mi dad pa (intransitive) indigenous class."
  (let ((result (tibetan-verb-lookup "འགྲོ")))
    (should result)
    (should (string= "tha_mi_dad_pa" (alist-get 'indigenous_class result)))))

;; ============================================================================
;; MULTIPLE STEMS LOOKUP TESTS
;; ============================================================================

(ert-deftest tibetan-verb-lookup-by-past-stem ()
  "Test that looking up past stem finds the verb."
  (let ((result (tibetan-verb-lookup "བྱས")))  ; past of བྱེད
    (should result)
    (should (string= "བྱེད" (alist-get 'lemma result)))))

(ert-deftest tibetan-verb-lookup-by-future-stem ()
  "Test that looking up future stem finds the verb."
  (let ((result (tibetan-verb-lookup "བྱ")))  ; future of བྱེད
    (should result)
    (should (string= "བྱེད" (alist-get 'lemma result)))))

(ert-deftest tibetan-verb-lookup-by-imperative-stem ()
  "Test that looking up imperative stem finds the verb."
  (let ((result (tibetan-verb-lookup "སོང")))  ; imperative of འགྲོ
    (should result)
    (should (string= "འགྲོ" (alist-get 'lemma result)))))

;; ============================================================================
;; COMMON VERBS COVERAGE TESTS
;; ============================================================================

(ert-deftest tibetan-verb-database-has-common-verbs ()
  "Test that common classical Tibetan verbs are in the database."
  (let ((common-verbs '("བྱེད" "འགྲོ" "ཡིན" "ཡོད" "མཐོང" "ཐོས"
                        "གསུང" "མཁྱེན" "བཞུགས" "གཟིགས")))
    (dolist (verb common-verbs)
      (should (tibetan-verb-lookup verb)))))

(ert-deftest tibetan-verb-database-minimum-size ()
  "Test that database has at least 20 verbs."
  (should (>= (hash-table-count tibetan-verb-database) 20)))

(provide 'tibetan-verb-classifier-test)
;;; tibetan-verb-classifier-test.el ends here
