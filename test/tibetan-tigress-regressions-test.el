;;; tibetan-tigress-regressions-test.el --- Regression tests for Tigress-story segments -*- lexical-binding: t -*-

;;; Commentary:
;; ERT regressions for the 5 BDD spec failures observed in
;; `spec/suites/tigress-story-spec.el' on 2026-04-19.
;;
;; Each test pins a concrete symptom independent of the BDD framework so
;; the fix stays covered by the primary ERT suite.  They all exercise
;; public entry points only.
;;
;; Root causes (see commit message for the fix):
;;
;;   (1) MWU over-match.  The greedy longest-match loop in
;;       `tibetan-find-multiword-units' accepted Steinert entries up to
;;       eight syllables long.  RangjungYeshe / IvesWaldo keep many
;;       idiomatic phrasal entries that swallow content words —
;;       `ངོ་མཚར་དུ་གྱུར' ("marveled") is a 4-syllable entry that
;;       consumes the verb; `བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ' is a
;;       7-syllable entry that consumes the entire input.
;;
;;   (2) Shadow match.  Even capped to 2 syllables, `དུས་བསྐལ'
;;       (IvesWaldo, "kalpa of destruction") matches at position 0 in
;;       `དུས་བསྐལ་པ་གྲངས' and hides the canonical `བསྐལ་པ' compound at
;;       position 1.
;;
;;   (3) Terminative ར only detected on last piece.  The
;;       `TERMINATIVE -ར ON FINAL PIECE OF A COMPOUND' rule in
;;       `tibetan-particles-bialek.el' required the ר to appear on the
;;       last piece and in a 2-character form.  `སྙིང་རྗེར་ལྡན' has
;;       ר on the NON-final 4-codepoint piece `རྗེར'.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar tibetan-skip-external-glossaries t)

(require 'tibetan-enhanced-parser)
(require 'tibetan-particles-bialek)
(require 'tibetan-analysis-persist nil t)

;; ============================================================================
;; MWU regressions
;; ============================================================================

(defun tibetan-tigress-test--mwu-forms (text)
  "Return the list of MWU joined-forms produced by parsing TEXT."
  (let* ((parsed (tibetan-parse-enhanced text))
         (units (alist-get 'multiword-units parsed)))
    (mapcar (lambda (u) (nth 2 u)) units)))

(ert-deftest tibetan-tigress-mwu-ngo-mtshar-not-swallowed ()
  "`ངོ་མཚར' must be an MWU in `ངོ་མཚར་དུ་གྱུར' — Steinert's 4-syll
`ངོ་མཚར་དུ་གྱུར' phrasal entry must NOT swallow the whole span."
  (let ((forms (tibetan-tigress-test--mwu-forms "ངོ་མཚར་དུ་གྱུར")))
    (should (member "ངོ་མཚར" forms))
    (should-not (member "ངོ་མཚར་དུ་གྱུར" forms))))

(ert-deftest tibetan-tigress-mwu-ba-zhig-not-swallowed ()
  "`འབའ་ཞིག' must be an MWU in `འདི་འབའ་ཞིག་ཏུ' — `འདི་འབའ་ཞིག' from
IvesWaldo must NOT swallow the demonstrative."
  (let ((forms (tibetan-tigress-test--mwu-forms "འདི་འབའ་ཞིག་ཏུ")))
    (should (member "འབའ་ཞིག" forms))
    (should-not (member "འདི་འབའ་ཞིག" forms))))

(ert-deftest tibetan-tigress-mwu-bskal-pa-beats-dus-bskal ()
  "`བསྐལ་པ' (kalpa) must be an MWU in `དུས་བསྐལ་པ་གྲངས'.
The IvesWaldo `དུས་བསྐལ' (\"kalpa of destruction\") entry must not
shadow the canonical `བསྐལ་པ' compound at position 1."
  (let ((forms (tibetan-tigress-test--mwu-forms "དུས་བསྐལ་པ་གྲངས")))
    (should (member "བསྐལ་པ" forms))
    (should-not (member "དུས་བསྐལ" forms))))

(ert-deftest tibetan-tigress-mwu-bka-stsal-honorific-verb-detected ()
  "In `བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།' the honorific verb `བཀའ་སྩལ'
must surface in the verb extractor.  Previously the 7-syllable
RangjungYeshe Steinert entry \"the Bhagavan replied\" consumed the
entire input as ONE MWU, starving the verb extractor."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")
         (parsed (tibetan-parse-enhanced text))
         (words (alist-get 'words parsed))
         (mwus (alist-get 'multiword-units parsed))
         (verbs (tibetan-extract-verbs-compound-aware text words mwus)))
    ;; No MWU may cover more than 2 syllables when sourced from Steinert.
    (dolist (m mwus)
      (let ((span (- (nth 1 m) (nth 0 m)))
            (category (alist-get 'category (nth 3 m))))
        (when (string= category "steinert")
          (should (<= span 2)))))
    ;; The extractor must find the honorific verb.
    (should (cl-some (lambda (v)
                       (and (listp v) (consp (car v))
                            (string= "བཀའ་སྩལ" (alist-get 'lemma v))))
                     verbs))))

;; ============================================================================
;; Bialek case particle regression
;; ============================================================================

(ert-deftest tibetan-tigress-bialek-terminative-r-on-non-final-piece ()
  "In `སྙིང་རྗེར་ལྡན' the ר on the NON-final piece `རྗེར' must be
detected as terminative.  Stripping ר leaves `རྗེ' (lord/noble), a
known lemma, and `རྗེར' itself is not a verb — so the rule that
previously fired only for the final piece must extend here."
  (let ((result (tibetan-analyze-grammar-bialek "སྙིང་རྗེར་ལྡན")))
    (should result)
    (should (cl-some (lambda (entry)
                       (let ((particle (nth 0 entry))
                             (type (nth 2 entry)))
                         (and (string= particle "ར")
                              type
                              (string-match-p "TERMINATIVE\\|ALL" type))))
                     result))))

;; ============================================================================
;; Full analysis content regression (verb classification output)
;; ============================================================================

(ert-deftest tibetan-tigress-analysis-content-includes-tibetan-verb-class ()
  "The Verb Classification section of `tibetan-analysis-generate-content'
must include the Tibetan indigenous class (ཐ་དད་པ or ཐ་མི་དད་པ) for
honorific verbs like `བཀའ་སྩལ' — this was silently absent because the
verb itself was swallowed into a single-MWU parse (see
`tibetan-tigress-mwu-bka-stsal-honorific-verb-detected')."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (let ((result (tibetan-analysis-generate-content
                 "བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")))
    (should (string-match-p "\\*\\* Verb Classification" result))
    (should (string-match-p "ཐ་དད་པ\\|ཐ་མི་དད་པ" result))
    (should (string-match-p "STEMS:" result))))

(provide 'tibetan-tigress-regressions-test)
;;; tibetan-tigress-regressions-test.el ends here
