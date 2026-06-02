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
    (should (string-match-p "to give" (alist-get 'meaning result)))))

(ert-deftest tibetan-verb-lookup-btsong-aliases-consistent ()
  "All forms of `to sell' (བཙོང / ཚོང / བཙོངས / འཚོང) resolve to the
SAME entry.  Regression for a contradictory duplicate: two puthash
calls defined `བཙོང' with different lemmas/imperatives, and the
`ཚོང' alias pointed at the dead (overwritten) entry — so `ཚོང' and
`བཙོང' returned different alists."
  (let ((btsong (tibetan-verb-lookup "བཙོང"))
        (tshong (tibetan-verb-lookup "ཚོང")))
    (should btsong)
    (should tshong)
    (should (string= (alist-get 'lemma btsong)
                     (alist-get 'lemma tshong)))
    (should (string= (alist-get 'imperative_stem btsong)
                     (alist-get 'imperative_stem tshong)))))

(ert-deftest tibetan-verb-lookup-with-punctuation ()
  "Test that verbs with trailing shad are still found."
  (let ((result (tibetan-verb-lookup "བྱིན།")))
    (should result)
    (should (string= "སྦྱིན" (alist-get 'lemma result)))))

(ert-deftest tibetan-verb-lookup-with-trailing-tsheg ()
  "Verbs with a trailing tsheg (་) are still found.
A word arriving as `བྱིན་' (tsheg not yet stripped — e.g. from a
case-stripping pass that left `STEM་') must match the DB key `བྱིན'.
Mirrors CLAUDE.md §7: trailing-tsheg-after-stripping pitfall."
  (let ((bare (tibetan-verb-lookup "བྱིན"))
        (tsheg (tibetan-verb-lookup "བྱིན་")))
    (should bare)
    (should tsheg)
    (should (equal bare tsheg))))

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

(ert-deftest tibetan-verb-stem-normalization-indexes-all-stems ()
  "Every entry's real stems resolve via lookup — including stems that
were previously missing a hand-written alias.  Guards the normalization
pass that auto-indexes present/past/future/imperative as keys."
  ;; སྨྲོས is the imperative of སྨྲ; was missing a key before normalization.
  (let ((r (tibetan-verb-lookup "སྨྲོས")))
    (should r)
    (should (string= "སྨྲ" (alist-get 'present_stem r))))
  ;; ཐོབས (imperative of ཐོབ), མཐོངས (imperative of མཐོང): also resolve.
  (should (tibetan-verb-lookup "ཐོབས"))
  (should (tibetan-verb-lookup "མཐོངས"))
  ;; Spot-check: every entry's non-placeholder stems are keyed.
  (let ((missing 0) (seen (make-hash-table :test 'equal)))
    (maphash
     (lambda (_k v)
       (let ((lemma (alist-get 'lemma v)))
         (unless (gethash lemma seen)
           (puthash lemma t seen)
           (dolist (sk '(present_stem past_stem future_stem imperative_stem))
             (let ((stem (alist-get sk v)))
               (when (and stem (stringp stem) (> (length stem) 0)
                          (not (string= stem "—"))
                          (not (gethash stem tibetan-verb-database)))
                 (cl-incf missing)))))))
     tibetan-verb-database)
    (should (= 0 missing))))

(ert-deftest tibetan-verb-matched-stem-identifies-stem ()
  "`tibetan-verb-matched-stem' reports which stem a surface form is."
  (let ((byed (tibetan-verb-lookup "བྱེད")))
    (should (eq 'present    (tibetan-verb-matched-stem "བྱེད" byed)))
    (should (eq 'past       (tibetan-verb-matched-stem "བྱས" byed)))
    (should (eq 'future     (tibetan-verb-matched-stem "བྱ" byed)))
    (should (eq 'imperative (tibetan-verb-matched-stem "བྱོས" byed)))
    ;; Trailing tsheg / shad tolerated.
    (should (eq 'past       (tibetan-verb-matched-stem "བྱས།" byed)))
    (should (null           (tibetan-verb-matched-stem "ཁྱིམ" byed)))))

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

;; ============================================================================
;; IS-VERB-P CLASSIFICATION TESTS
;; ============================================================================

(ert-deftest tibetan-is-verb-p-known-verb ()
  "Test that known verbs are correctly classified as verbs."
  (skip-unless (fboundp 'tibetan-is-verb-p))
  (should (tibetan-is-verb-p "བྱེད"))  ; "to do" is a verb
  (should (tibetan-is-verb-p "འགྲོ"))  ; "to go" is a verb
  (should (tibetan-is-verb-p "ཡིན")))  ; "to be" is a verb

(ert-deftest tibetan-is-verb-p-non-verb ()
  "Test that non-verbs are correctly classified as non-verbs."
  (skip-unless (fboundp 'tibetan-is-verb-p))
  (should-not (tibetan-is-verb-p "ཨ་མ"))  ; "mother" is not a verb
  (should-not (tibetan-is-verb-p "གྲུབ"))  ; depends on context/form
  (should-not (tibetan-is-verb-p "མི")))   ; "person" is not a verb

(ert-deftest tibetan-is-verb-p-verb-stems ()
  "Test verb classification for different verb stems."
  (skip-unless (fboundp 'tibetan-is-verb-p))
  ;; Past stem
  (should (tibetan-is-verb-p "བྱས"))  ; past of བྱེད
  ;; Future stem
  (should (tibetan-is-verb-p "བྱ"))   ; future of བྱེད
  ;; Imperative stem
  (should (tibetan-is-verb-p "སོང")))  ; imperative of འགྲོ

(ert-deftest tibetan-is-verb-p-empty-input ()
  "Test verb classification with empty input."
  (skip-unless (fboundp 'tibetan-is-verb-p))
  (should-not (tibetan-is-verb-p ""))
  (should-not (tibetan-is-verb-p nil)))

(ert-deftest tibetan-is-verb-p-with-punctuation ()
  "Test verb classification with Tibetan punctuation."
  (skip-unless (fboundp 'tibetan-is-verb-p))
  ;; Verb with trailing shad
  (should (tibetan-is-verb-p "བྱེད།")))

(provide 'tibetan-verb-classifier-test)
;;; tibetan-verb-classifier-test.el ends here
