;;; tibetan-round1-verb-extraction-test.el --- Round-1 regression tests -*- lexical-binding: t -*-

;;; Commentary:
;; Regression tests for the Round-1 verb-extraction overhaul in
;; `analysis/tibetan-enhanced-display.el'.
;;
;; The three segments below are real Milarepa sentences whose grammar
;; analysis failed in class on 2026-04-14.  Round 1 targets:
;;   * closed-set detection of minor / modal / reporting verbs
;;     (ཁྲོས, བྱུང, ཕྲོགས, དགོས, ཟེར, …)
;;   * progressive strip-particles so verbs wearing པར/ཏེ/པས are seen
;;   * per-constituent fallback inside multiword units (light verbs)
;;   * safe negation stripping (ma-/mi- with tsheg boundary)
;;   * modal- and reporting-chain annotations
;;
;; These tests exercise the extractor directly — they intentionally
;; bypass parse-enhanced to keep the surface small and reproducible.

;;; Code:

(require 'ert)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir)))

(require 'tibetan-enhanced-display)
(require 'tibetan-verb-classifier nil t)

;; ============================================================================
;; Helpers
;; ============================================================================

(defun tibetan-round1-test--lemmas (verbs)
  "Return list of lemmas from VERBS entries."
  (mapcar (lambda (v) (alist-get 'lemma v)) verbs))

(defun tibetan-round1-test--find (verbs lemma)
  "Return the first entry in VERBS whose lemma matches LEMMA."
  (cl-find-if (lambda (v) (equal (alist-get 'lemma v) lemma)) verbs))

;; ============================================================================
;; Progressive-detection primitives
;; ============================================================================

(ert-deftest tibetan-round1-progressive-finds-byung ()
  "བྱུང་བ་ལ → should find བྱུང after strip-particles."
  (skip-unless (fboundp 'tibetan-verb-detect--progressive))
  (let ((hit (tibetan-verb-detect--progressive "བྱུང་བ་ལ")))
    (should hit)
    (should (string-match-p "བྱུང" (alist-get 'lemma (plist-get hit :entry))))))

(ert-deftest tibetan-round1-progressive-finds-khros ()
  "ཁྲོས་ཏེ → should find ཁྲོས via strip-particles or head."
  (skip-unless (fboundp 'tibetan-verb-detect--progressive))
  (let ((hit (tibetan-verb-detect--progressive "ཁྲོས་ཏེ")))
    (should hit)
    (should (member (alist-get 'lemma (plist-get hit :entry))
                    '("ཁྲོ" "ཁྲོས")))))

(ert-deftest tibetan-round1-progressive-finds-negation ()
  "མ་ཉན་པས → stripping ma- + pas yields ཉན and negated=t."
  (skip-unless (fboundp 'tibetan-verb-detect--progressive))
  (let ((hit (tibetan-verb-detect--progressive "མ་ཉན་པས")))
    (should hit)
    (should (plist-get hit :negated))
    (should (string-match-p "ཉན" (alist-get 'lemma (plist-get hit :entry))))))

(ert-deftest tibetan-round1-progressive-does-not-split-mthong ()
  "མཐོང (to see) must NOT be treated as ma- + ཐོང."
  (skip-unless (fboundp 'tibetan-verb-detect--strip-negation))
  (let ((res (tibetan-verb-detect--strip-negation "མཐོང")))
    ;; Should return (word . nil) — no tsheg after ma-, nothing stripped.
    (should (equal (car res) "མཐོང"))
    (should-not (cdr res))))

(ert-deftest tibetan-round1-progressive-finds-dgos ()
  "Modal དགོས should be found via the closed minor-verb set."
  (skip-unless (fboundp 'tibetan-verb-detect--progressive))
  (let ((hit (tibetan-verb-detect--progressive "དགོས")))
    (should hit)
    (should (equal (alist-get 'lemma (plist-get hit :entry)) "དགོས"))))

(ert-deftest tibetan-round1-progressive-finds-zer ()
  "Reporting ཟེར should be found via the closed reporting set."
  (skip-unless (fboundp 'tibetan-verb-detect--progressive))
  (let ((hit (tibetan-verb-detect--progressive "ཟེར")))
    (should hit)
    (should (equal (alist-get 'lemma (plist-get hit :entry)) "ཟེར"))))

;; ============================================================================
;; End-to-end extraction on failing segments
;; ============================================================================

(ert-deftest tibetan-round1-seg011-byed-dgos-zer ()
  "Seg-011: ཨ་ཁུའི་བུའི་ཆུང་མ་བྱེད་དགོས་ཟེར / byed+MODAL:dgos+SAYS:zer."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "ཨ་ཁུའི་བུའི་ཆུང་མ་བྱེད་དགོས་ཟེར")
         (words '("ཨ་ཁུའི" "བུའི" "ཆུང" "མ" "བྱེད" "དགོས" "ཟེར"))
         ;; Light-verb multiword unit: (start end form meta)
         (mwu  '((2 4 "ཆུང་མ་བྱེད" nil)))
         (verbs (tibetan-extract-verbs-compound-aware text words mwu))
         (lemmas (tibetan-round1-test--lemmas verbs)))
    ;; Should see three distinct verbs.
    (should (member "བྱེད" lemmas))
    (should (member "དགོས" lemmas))
    (should (member "ཟེར" lemmas))
    ;; The main verb should carry a modal chain annotation.
    (let ((byed (tibetan-round1-test--find verbs "བྱེད")))
      (should byed)
      (should (equal (alist-get 'modal-of byed) "དགོས"))
      (should (equal (alist-get 'reports-p byed) "ཟེར")))))

(ert-deftest tibetan-round1-seg012-phrogs-is-found ()
  "Seg-012: …ཕྲོགས / main verb ཕྲོགས must no longer be missed."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "དེ་ལ་མ་ཉན་པས་ཁྲོས་ཏེ་ནོར་རྫས་ཐམས་ཅད་ཕྲོགས")
         (words '("དེ" "ལ" "མ" "ཉན" "པས" "ཁྲོས" "ཏེ"
                  "ནོར" "རྫས" "ཐམས" "ཅད" "ཕྲོགས"))
         (mwu '((7 8 "ནོར་རྫས" nil)
                (9 10 "ཐམས་ཅད" nil)))
         (verbs (tibetan-extract-verbs-compound-aware text words mwu))
         (lemmas (tibetan-round1-test--lemmas verbs)))
    ;; ཕྲོགས was missing before; must be present now.
    (should (or (member "ཕྲོགས" lemmas) (member "འཕྲོག" lemmas)))
    ;; ཉན stays.
    (should (member "ཉན" lemmas))
    ;; ཁྲོས shows up too.
    (should (or (member "ཁྲོ" lemmas) (member "ཁྲོས" lemmas)))))

(ert-deftest tibetan-round1-seg012-nyan-is-negated ()
  "Seg-012: མ་ཉན → ཉན entry must carry negated=t."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "དེ་ལ་མ་ཉན་པས་ཁྲོས་ཏེ་ནོར་རྫས་ཐམས་ཅད་ཕྲོགས")
         (words '("དེ" "ལ" "མ" "ཉན" "པས" "ཁྲོས" "ཏེ"
                  "ནོར" "རྫས" "ཐམས" "ཅད" "ཕྲོགས"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (nyan (tibetan-round1-test--find verbs "ཉན")))
    (should nyan)
    (should (alist-get 'negated nyan))))

(ert-deftest tibetan-round1-seg007-bltams-is-found ()
  "Seg-007: …བལྟམས / past-stem བལྟམས 'be born' must be detected."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "རྗེ་བཙུན་ལྕགས་ཕོ་འབྲུག་གི་ལོ་ལ་བལྟམས")
         (words '("རྗེ" "བཙུན" "ལྕགས" "ཕོ" "འབྲུག" "གི"
                  "ལོ" "ལ" "བལྟམས"))
         (mwu '((0 1 "རྗེ་བཙུན" nil)
                (2 3 "ལྕགས་ཕོ" nil)
                (4 6 "འབྲུག་གི་ལོ" nil)))
         (verbs (tibetan-extract-verbs-compound-aware text words mwu))
         (lemmas (tibetan-round1-test--lemmas verbs)))
    ;; Before fix: "[No verbs detected]".  Now: at least bltams.
    (should (member "བལྟམས" lemmas))))

(ert-deftest tibetan-round1-seg013-byung-is-found ()
  "Seg-013: ཤིན་དུ་ཁས་ཉེན་པར་བྱུང་བ་ལ → byung must now be detected."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "ཤིན་དུ་ཁས་ཉེན་པར་བྱུང་བ་ལ")
         (words '("ཤིན" "དུ" "ཁས" "ཉེན" "པར" "བྱུང" "བ" "ལ"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (lemmas (tibetan-round1-test--lemmas verbs)))
    ;; Previously: "[No verbs detected]" — now we want at least བྱུང.
    (should (or (member "བྱུང" lemmas) (member "འབྱུང" lemmas)))))

;; ============================================================================
;; Round-3 regression tests (smarter negation / conditional detection)
;; ============================================================================

(ert-deftest tibetan-round3-med-is-intrinsically-negated ()
  "`མེད' is the inherent negation of `ཡོད' — must be tagged negated=t
even when nothing precedes it."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "མི་དེ་ལ་ནོར་རྫས་མེད")
         (words '("མི" "དེ" "ལ" "ནོར" "རྫས" "མེད"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (med (tibetan-round1-test--find verbs "མེད")))
    (should med)
    (should (alist-get 'negated med))))

(ert-deftest tibetan-round3-min-is-intrinsically-negated ()
  "`མིན' is the equative negation of `ཡིན' — must be tagged negated=t."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "དེ་བདག་མིན")
         (words '("དེ" "བདག" "མིན"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (min (tibetan-round1-test--find verbs "མིན")))
    (should min)
    (should (alist-get 'negated min))))

(ert-deftest tibetan-round3-conditional-negation ()
  "`མ་X་ན' pattern: negated verb followed by conditional `ན' gets
(conditional . t)."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "དེ་མ་བྱས་ན")
         (words '("དེ" "མ" "བྱས" "ན"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (byas (or (tibetan-round1-test--find verbs "བྱས")
                   (tibetan-round1-test--find verbs "བྱེད"))))
    (should byas)
    (should (alist-get 'negated byas))
    (should (alist-get 'conditional byas))))

(ert-deftest tibetan-round3-non-conditional-negation-not-tagged ()
  "A negated verb NOT followed by `ན' must not get conditional=t."
  (skip-unless (fboundp 'tibetan-extract-verbs-compound-aware))
  (let* ((text "དེ་ལ་མ་ཉན་པས")
         (words '("དེ" "ལ" "མ" "ཉན" "པས"))
         (verbs (tibetan-extract-verbs-compound-aware text words nil))
         (nyan (tibetan-round1-test--find verbs "ཉན")))
    (should nyan)
    (should (alist-get 'negated nyan))
    (should-not (alist-get 'conditional nyan))))

;; ============================================================================
;; Nominaliser / particle exclusion (P1 — seg-4 regression)
;; ============================================================================
;;
;; Observed in the seg-4 paste of a Milarepa analysis file: the Word /
;; Particle List occasionally classified the nominaliser `པ' or the
;; genitive-marked `པའི' as verbs in the Sentence Structure section.
;; Root cause: when the Hill DB and closed-set checks miss, the lookup
;; falls through to `tibetan-verb-detect--vocab-says-verb-p', which
;; accepts any gloss starting with "to ", "pf.", "verb:", etc.  Some
;; dictionary entries for `པ' / `བ' carry such verbal glosses, so the
;; enclitic slipped in.  These tests lock that down.

(ert-deftest tibetan-round1-nominalizer-pa-not-a-verb ()
  "`པ' is never a verb, even if its vocab gloss looks verbal."
  (skip-unless (fboundp 'tibetan-verb-detect--lookup))
  (cl-letf (((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (_w) (list :primary "to be" :detailed nil))))
    (should-not (tibetan-verb-detect--lookup "པ"))))

(ert-deftest tibetan-round1-nominalizer-pai-not-a-verb ()
  "`པའི' (genitive-marked nominaliser) is never a verb."
  (skip-unless (fboundp 'tibetan-verb-detect--lookup))
  (cl-letf (((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (_w) (list :primary "to be" :detailed nil))))
    (should-not (tibetan-verb-detect--lookup "པའི"))))

(ert-deftest tibetan-round1-nominalizer-ba-not-a-verb ()
  "`བ' (post-vowel/open-syllable nominaliser variant) is never a verb."
  (skip-unless (fboundp 'tibetan-verb-detect--lookup))
  (cl-letf (((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (_w) (list :primary "verb: to do" :detailed nil))))
    (should-not (tibetan-verb-detect--lookup "བ"))))

(ert-deftest tibetan-round1-nominalizer-bai-not-a-verb ()
  "`བའི' (genitive-marked `བ' nominaliser) is never a verb."
  (skip-unless (fboundp 'tibetan-verb-detect--lookup))
  (cl-letf (((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (_w) (list :primary "to do" :detailed nil))))
    (should-not (tibetan-verb-detect--lookup "བའི"))))

(ert-deftest tibetan-round1-real-verb-still-detected ()
  "Regression guard: the nominaliser-exclusion must not accidentally
swallow real verbs that happen to end in `པ' (none of the bare set).
`བྱེད' resolves via the Hill DB regardless of the stub."
  (skip-unless (fboundp 'tibetan-verb-detect--lookup))
  (cl-letf (((symbol-function 'tibetan-vocab-lookup-detailed)
             (lambda (_w) nil)))
    (should (tibetan-verb-detect--lookup "བྱེད"))))

(provide 'tibetan-round1-verb-extraction-test)
;;; tibetan-round1-verb-extraction-test.el ends here
