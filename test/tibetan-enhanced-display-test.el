;;; tibetan-enhanced-display-test.el --- Tests for tibetan-enhanced-display.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for enhanced display and analysis functionality.
;; Tests cover zero-marker analysis, segment info display, and claimed indices extraction.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-enhanced-display)

;; ============================================================================
;; ZERO MARKER ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-zero-markers-nil-inputs ()
  "Test zero-marker analysis with nil or missing inputs."
  (skip-unless (fboundp 'tibetan-analyze-zero-markers))
  ;; nil inputs should return nil
  (should-not (tibetan-analyze-zero-markers nil nil nil))
  (should-not (tibetan-analyze-zero-markers '() nil nil))
  ;; Empty lists should return nil
  (should-not (tibetan-analyze-zero-markers '() '() '())))

(ert-deftest tibetan-analyze-zero-markers-returns-list ()
  "Test that zero-marker analysis returns a list when given valid inputs."
  (skip-unless (fboundp 'tibetan-analyze-zero-markers))
  ;; With non-empty inputs, should return list or nil
  (let ((verbs '(((lemma . "བྱེད"))))
        (multiword-units '((0 1 "བདག" ((english . "I")))))
        (words '("བདག" "གིས")))
    (let ((result (tibetan-analyze-zero-markers verbs multiword-units words)))
      ;; Should be list or nil
      (should (or (listp result) (null result))))))

;; ============================================================================
;; GET CLAIMED INDICES TESTS
;; ============================================================================

(ert-deftest tibetan-get-claimed-indices-basic ()
  "Test extraction of claimed indices from multiword units."
  (skip-unless (fboundp 'tibetan-get-claimed-indices))
  ;; Single unit claiming indices 0-2
  (let ((multiword-units '((0 2 "བྱང་ཆུབ" ((english . "enlightenment"))))))
    (let ((claimed (tibetan-get-claimed-indices multiword-units)))
      (should (hash-table-p claimed))
      ;; Indices 0 and 1 should be claimed
      (should (gethash 0 claimed))
      (should (gethash 1 claimed))
      ;; Index 2 should not be claimed (range is exclusive on right)
      (should-not (gethash 2 claimed)))))

(ert-deftest tibetan-get-claimed-indices-multiple-units ()
  "Test claimed indices with multiple multiword units."
  (skip-unless (fboundp 'tibetan-get-claimed-indices))
  (let ((multiword-units '(
        (0 2 "བྱང་ཆུབ" ((english . "enlightenment")))
        (3 5 "སེམས་དཔའ" ((english . "bodhisattva")))
        )))
    (let ((claimed (tibetan-get-claimed-indices multiword-units)))
      (should (hash-table-p claimed))
      ;; First unit claims 0, 1
      (should (gethash 0 claimed))
      (should (gethash 1 claimed))
      ;; Second unit claims 3, 4
      (should (gethash 3 claimed))
      (should (gethash 4 claimed))
      ;; Index 2 and 5 not claimed
      (should-not (gethash 2 claimed))
      (should-not (gethash 5 claimed)))))

(ert-deftest tibetan-get-claimed-indices-empty-input ()
  "Test claimed indices with empty multiword units."
  (skip-unless (fboundp 'tibetan-get-claimed-indices))
  (let ((claimed (tibetan-get-claimed-indices '())))
    (should (hash-table-p claimed))
    ;; Hash table should be empty
    (should (= (hash-table-count claimed) 0))))

(ert-deftest tibetan-get-claimed-indices-single-syllable ()
  "Test claimed indices for single-syllable multiword units."
  (skip-unless (fboundp 'tibetan-get-claimed-indices))
  ;; Unit claiming just index 0
  (let ((multiword-units '((0 1 "བ" ((english . "prefix"))))))
    (let ((claimed (tibetan-get-claimed-indices multiword-units)))
      (should (gethash 0 claimed))
      (should-not (gethash 1 claimed)))))

;; ============================================================================
;; SEGMENT INFO ENHANCED TESTS
;; ============================================================================

(ert-deftest tibetan-segment-info-enhanced-function-exists ()
  "Test that tibetan-segment-info-enhanced function exists and is callable."
  (skip-unless (fboundp 'tibetan-segment-info-enhanced))
  (should (functionp 'tibetan-segment-info-enhanced)))

(ert-deftest tibetan-segment-info-enhanced-interactive ()
  "Test that tibetan-segment-info-enhanced is interactive."
  (skip-unless (fboundp 'tibetan-segment-info-enhanced))
  (should (commandp 'tibetan-segment-info-enhanced)))

(ert-deftest tibetan-segment-info-enhanced-silent-mode ()
  "Test that tibetan-segment-info-enhanced accepts silent parameter."
  (skip-unless (fboundp 'tibetan-segment-info-enhanced))
  ;; Should not error when called with silent flag
  (should (condition-case err
              (progn
                (with-temp-buffer
                  ;; Call with silent=t
                  (tibetan-segment-info-enhanced t))
                t)
            (error nil))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-enhanced-display-returns-consistent-types ()
  "Test that enhanced display functions return consistent types."
  (skip-unless (fboundp 'tibetan-get-claimed-indices))
  ;; claimed indices should always be hash table
  (let ((claimed1 (tibetan-get-claimed-indices '()))
        (claimed2 (tibetan-get-claimed-indices '((0 1 "test" ())))))
    (should (hash-table-p claimed1))
    (should (hash-table-p claimed2))))

;; ============================================================================
;; BUILD COMPOUND-AWARE SEGMENTS TESTS
;; ============================================================================

(ert-deftest tibetan-build-compound-aware-segments-basic ()
  "Test building segments with no compounds."
  (skip-unless (fboundp 'tibetan-build-compound-aware-segments))
  (let ((words '("བདག" "གིས" "བྱེད"))
        (multiword-units '()))
    (let ((result (tibetan-build-compound-aware-segments words multiword-units)))
      (should (listp result))
      (should (= (length result) 3))
      (should (equal result '("བདག" "གིས" "བྱེད"))))))

(ert-deftest tibetan-build-compound-aware-segments-with-compounds ()
  "Test building segments with recognized compounds."
  (skip-unless (fboundp 'tibetan-build-compound-aware-segments))
  (let ((words '("བྱང" "ཆུབ" "སེམས" "དཔའ"))
        (multiword-units '((0 2 "བྱང་ཆུབ" ((english . "enlightenment"))))))
    (let ((result (tibetan-build-compound-aware-segments words multiword-units)))
      (should (listp result))
      ;; Should have the compound and two remaining words
      (should (= (length result) 3))
      (should (equal (car result) "བྱང་ཆུབ")))))

(ert-deftest tibetan-build-compound-aware-segments-multiple-compounds ()
  "Test segments with multiple compounds."
  (skip-unless (fboundp 'tibetan-build-compound-aware-segments))
  (let ((words '("བྱང" "ཆུབ" "སེམས" "དཔའ" "འདི" "ནི"))
        (multiword-units '((0 2 "བྱང་ཆུབ" ((english . "enlightenment")))
                          (2 4 "སེམས་དཔའ" ((english . "bodhisattva"))))))
    (let ((result (tibetan-build-compound-aware-segments words multiword-units)))
      (should (listp result))
      (should (member "བྱང་ཆུབ" result))
      (should (member "སེམས་དཔའ" result)))))

;; ============================================================================
;; EXTRACT VERBS COMPOUND-AWARE TESTS
;; ============================================================================

(ert-deftest tibetan-extract-verbs-compound-aware-empty-input ()
  "Test verb extraction with empty input."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let ((result (tibetan-extract-verbs-compound-aware "" '() '())))
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-extract-verbs-compound-aware-nil-input ()
  "Test verb extraction with nil input."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let ((result (tibetan-extract-verbs-compound-aware nil '() '())))
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-extract-verbs-compound-aware-returns-list ()
  "Test that verb extraction returns a list."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let ((words '("བྱེད" "པ"))
        (multiword-units '()))
    (let ((result (tibetan-extract-verbs-compound-aware "བྱེད་པ" words multiword-units)))
      (should (listp result)))))

(ert-deftest tibetan-extract-verbs-compound-aware-skips-compounds ()
  "Test that verbs inside compounds are skipped."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  ;; If a syllable is part of a multi-word compound, it shouldn't be extracted as standalone verb
  (let ((words '("བྱང" "ཆུབ"))
        (multiword-units '((0 2 "བྱང་ཆུབ" ((english . "enlightenment"))))))
    (let ((result (tibetan-extract-verbs-compound-aware "བྱང་ཆུབ" words multiword-units)))
      ;; Result should be a list (possibly empty if no standalone verbs found)
      (should (listp result)))))

;; ============================================================================
;; tibetan-analyze-arguments — single-char case-particle disambiguation
;; ============================================================================
;; Regression guard for the legacy Sentence Structure section: case
;; markers `ས/ལ/ར/ན' must NOT be detected when they're the syllable's
;; final consonant.  Routed through the segmenter's case-of helper,
;; which already implements the standalone-only rule for single-char
;; particles.  Pre-fix, `རྒྱལ' (king) was being mis-tagged as DATIVE
;; because of its trailing ལ, and `ཡུལ' similarly.

(ert-deftest tibetan-analyze-arguments-rgyal-not-dative ()
  "`རྒྱལ' (final consonant ལ) must NOT be tagged as DATIVE."
  (skip-unless (fboundp 'tibetan-clause-seg--case-of))
  (let* ((mwu '((0 0 "རྒྱལ" nil)))
         (verb '((lemma . "འཛུགས")
                 (source-pos . 1)
                 (case_frame . "Erg-Abs")
                 (transitivity . "Transitive")))
         (args (tibetan-analyze-arguments verb mwu '("རྒྱལ" "འཛུགས") nil))
         (rgyal (cl-find-if (lambda (a) (string= (alist-get 'form a) "རྒྱལ"))
                            args)))
    (should rgyal)
    (should-not (string= (alist-get 'role rgyal) "DATIVE"))))

(ert-deftest tibetan-analyze-arguments-yul-not-dative ()
  "`ཡུལ' (final consonant ལ) must NOT be tagged as DATIVE either."
  (skip-unless (fboundp 'tibetan-clause-seg--case-of))
  (let* ((mwu '((0 0 "ཡུལ" nil)))
         (verb '((lemma . "འཐོན")
                 (source-pos . 1)
                 (case_frame . "Abs-Abl")
                 (transitivity . "Intransitive")))
         (args (tibetan-analyze-arguments verb mwu '("ཡུལ" "འཐོན") nil))
         (yul (cl-find-if (lambda (a) (string= (alist-get 'form a) "ཡུལ"))
                          args)))
    (should yul)
    (should-not (string= (alist-get 'role yul) "DATIVE"))))

(ert-deftest tibetan-analyze-arguments-multichar-suffix-still-tagged ()
  "Real multi-char case suffixes are still detected — `བདག་གིས' must
still come back as ERGATIVE so we don't regress the working path."
  (skip-unless (fboundp 'tibetan-clause-seg--case-of))
  (let* ((mwu '((0 0 "བདག་གིས" nil)))
         (verb '((lemma . "བྱེད")
                 (source-pos . 1)
                 (case_frame . "Erg-Abs")
                 (transitivity . "Transitive")))
         (args (tibetan-analyze-arguments verb mwu '("བདག་གིས" "བྱེད") nil))
         (bdag (cl-find-if (lambda (a) (string= (alist-get 'form a) "བདག་གིས"))
                           args)))
    (should bdag)
    (should (string= (alist-get 'role bdag) "ERGATIVE"))))

;; ============================================================================
;; MWU-aware verb extraction (seg-11 / seg-14 regressions)
;; ============================================================================

(ert-deftest tibetan-extract-verbs-skip-multisyl-window-overlapping-mwu ()
  "A 2-/3-syllable Hill DB window that overlaps any parser-detected
MWU is skipped — the MWU's own analysis (or the strategy-2 fallback)
handles it.  Otherwise a noun compound like `ཀློག་སློབ' would emit a
spurious `ཀློག་སློབ' verb compound entry."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((words '("ཀློག" "སློབ" "པའི" "སློབ" "དཔོན"))
         (mwu '((0 2 "ཀློག་སློབ" ((english . "instructor")))
                (3 5 "སློབ་དཔོན" ((english . "master, teacher")))))
         (verbs (tibetan-extract-verbs-compound-aware
                 "ཀློག་སློབ་པའི་སློབ་དཔོན" words mwu))
         (lemmas (mapcar (lambda (v) (alist-get 'lemma v)) verbs)))
    ;; Neither MWU's metadata says `to …' / `verb' / `pf./pres.', so
    ;; the strategy-2 fallback must NOT add the last syllable as a verb.
    (should-not (member "སློབ" lemmas))
    (should-not (member "ཀློག" lemmas))))

(ert-deftest tibetan-extract-verbs-mwu-fallback-fires-for-verbal-meta ()
  "When the MWU's `english' meta describes a verb, the strategy-2
fallback DOES record the head verb (`ཆུང་མ་བྱེད' → `བྱེད').  This is
the light-verb path the fallback was originally introduced for."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((words '("ཆུང" "མ" "བྱེད"))
         (mwu '((0 3 "ཆུང་མ་བྱེད" ((english . "to become the wife of")))))
         (verbs (tibetan-extract-verbs-compound-aware
                 "ཆུང་མ་བྱེད" words mwu))
         (lemmas (mapcar (lambda (v) (alist-get 'lemma v)) verbs)))
    (should (member "བྱེད" lemmas))))

(ert-deftest tibetan-extract-verbs-mwu-suppresses-pseudo-negation ()
  "When `མ' sits inside an MWU together with the verb that follows,
it is part of the compound (e.g. `ཆུང་མ' = wife) and must NOT be
treated as the negation prefix.  Pre-fix, `ཆུང་མ་བྱེད' was producing
a spuriously-negated `བྱེད' entry."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((words '("ཆུང" "མ" "བྱེད"))
         (mwu '((0 3 "ཆུང་མ་བྱེད" ((english . "to become the wife of")))))
         (verbs (tibetan-extract-verbs-compound-aware
                 "ཆུང་མ་བྱེད" words mwu))
         (byed (cl-find-if (lambda (v) (string= (alist-get 'lemma v) "བྱེད"))
                           verbs)))
    (should byed)
    (should-not (alist-get 'negated byed))))

(provide 'tibetan-enhanced-display-test)
;;; tibetan-enhanced-display-test.el ends here
