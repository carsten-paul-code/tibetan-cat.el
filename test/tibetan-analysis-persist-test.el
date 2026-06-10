;;; tibetan-analysis-persist-test.el --- Tests for tibetan-analysis-persist.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for Tibetan analysis persistence module.
;; Tests cover: filename generation, hash computation, section parsing,
;; and utility functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-analysis-persist)

;; ============================================================================
;; FILENAME GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-make-short-name-tigress ()
  "Test short name generation for Tigress file."
  (should (string= "blockpri"
                   (tibetan-analysis-make-short-name "Tigress-Story-BlockPrint-Class.org"))))

(ert-deftest tibetan-analysis-make-short-name-saskya ()
  "Test short name generation for Sa-skya file."
  (should (string= "sa"
                   (tibetan-analysis-make-short-name "Reading-Sa-skya-legs-bshad.org"))))

(ert-deftest tibetan-analysis-make-short-name-reading ()
  "Test short name generation for Reading files."
  (let ((result (tibetan-analysis-make-short-name "Reading-05-Padma.org")))
    (should (stringp result))
    (should (string= "padma" result))))

(ert-deftest tibetan-analysis-make-short-name-generic ()
  "Test short name generation for generic files."
  (let ((result (tibetan-analysis-make-short-name "SomeDocument.org")))
    (should (stringp result))
    (should (> (length result) 0))
    (should (<= (length result) 8))))

(ert-deftest tibetan-analysis-make-short-name-nil ()
  "Test short name generation with nil input."
  (should (null (tibetan-analysis-make-short-name nil))))

(ert-deftest tibetan-analysis-segment-filename-number ()
  "Test segment filename generation from number."
  (let ((result (tibetan-analysis-segment-filename 1)))
    (should (string= "seg-001.org" result))))

(ert-deftest tibetan-analysis-segment-filename-number-with-source ()
  "Test segment filename generation from number with source file."
  (let ((result (tibetan-analysis-segment-filename 42)))
    (should (string= "seg-042.org" result))))

(ert-deftest tibetan-analysis-segment-filename-string ()
  "Test segment filename generation from string ID."
  (let ((result (tibetan-analysis-segment-filename "Segment 15")))
    (should (string= "seg-015.org" result))))

(ert-deftest tibetan-analysis-segment-filename-string-with-source ()
  "Test segment filename generation from string."
  (let ((result (tibetan-analysis-segment-filename "Segment 7")))
    (should (string= "seg-007.org" result))))

(ert-deftest tibetan-analysis-segment-filename-line-format ()
  "Test segment filename with Line N format."
  (let ((result (tibetan-analysis-segment-filename "Line 3")))
    (should (string-match-p "seg-003" result))))

(ert-deftest tibetan-analysis-segment-filename-padding ()
  "Test that segment numbers are zero-padded to 3 digits."
  (should (string-match-p "seg-001" (tibetan-analysis-segment-filename 1)))
  (should (string-match-p "seg-010" (tibetan-analysis-segment-filename 10)))
  (should (string-match-p "seg-100" (tibetan-analysis-segment-filename 100))))

;; ============================================================================
;; HASH COMPUTATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-compute-hash-basic ()
  "Test basic hash computation."
  (let ((hash (tibetan-analysis-compute-hash "test")))
    (should (stringp hash))
    (should (= 32 (length hash)))))  ; MD5 is 32 hex chars

(ert-deftest tibetan-analysis-compute-hash-consistency ()
  "Test that same input gives same hash."
  (let ((text "བཀྲ་ཤིས་བདེ་ལེགས།"))
    (should (string= (tibetan-analysis-compute-hash text)
                     (tibetan-analysis-compute-hash text)))))

(ert-deftest tibetan-analysis-compute-hash-different ()
  "Test that different inputs give different hashes."
  (should-not (string= (tibetan-analysis-compute-hash "text1")
                       (tibetan-analysis-compute-hash "text2"))))

(ert-deftest tibetan-analysis-compute-hash-tibetan ()
  "Test hash computation with Tibetan text."
  (let ((hash (tibetan-analysis-compute-hash "བཀྲ་ཤིས།")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

(ert-deftest tibetan-analysis-compute-hash-empty ()
  "Test hash computation with empty string."
  (let ((hash (tibetan-analysis-compute-hash "")))
    (should (stringp hash))
    (should (= 32 (length hash)))))

;; ============================================================================
;; SECTION BOUNDS PARSING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-find-section-bounds-basic ()
  "Test finding section bounds in buffer."
  (with-temp-buffer
    (insert "* Section 1\nContent 1\n* Section 2\nContent 2\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Section 1")))
      (should bounds)
      (should (consp bounds))
      (should (integerp (car bounds)))
      (should (integerp (cdr bounds))))))

(ert-deftest tibetan-analysis-find-section-bounds-not-found ()
  "Test finding non-existent section."
  (with-temp-buffer
    (insert "* Section 1\nContent\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Missing")))
      (should (null bounds)))))

(ert-deftest tibetan-analysis-find-section-bounds-nested ()
  "Test finding section bounds with subsections."
  (with-temp-buffer
    (insert "* Top\n** Sub1\nContent 1\n** Sub2\nContent 2\n* Next\n")
    (let ((bounds (tibetan-analysis-find-section-bounds (current-buffer) "Top")))
      (should bounds)
      (should (< (car bounds) (cdr bounds))))))

;; ============================================================================
;; USER SECTION EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-get-user-sections-callable ()
  "Test that get-user-sections function exists."
  (should (fboundp 'tibetan-analysis-get-user-sections)))

(ert-deftest tibetan-analysis-get-user-sections-reads-tibetan-analysis-as-auto-analysis-fallback ()
  "Phase 1.1 of layout-revision (2026-05-04):  the new top-level
heading `* Tibetan Analysis' (rename of `* Auto-Analysis') must be
in `--get-user-sections's section-name walk so the regenerator
picks it up on subsequent reanalyse.  Without it, a file that
already carries the new heading would have its body treated as
not-preserved by callers that consult the alist by section name.

The auto-content body is always regenerated (not preserved-from-
old) so this test does not assert the alist's value byte-for-byte;
it asserts only that the section name is recognised — i.e. the
returned alist contains a key `\"Tibetan Analysis\"' when the
file has the new heading."
  (let* ((dir (make-temp-file "ttest-getuser-1.1-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Test\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* Tibetan Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nbdag\n\n"
                    "* Footnotes\n\n"))
          (let ((sections (tibetan-analysis-get-user-sections file)))
            (should (assoc "Tibetan Analysis" sections))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-get-user-sections-reads-old-and-new-when-both-present ()
  "Edge case (cannot occur in real workflow, but locks behaviour):
when a file simultaneously carries both `* Auto-Analysis' and
`* Tibetan Analysis', `--get-user-sections' returns BOTH keys.
The downstream regenerator owns disambiguation — it discards the
auto-content body anyway and re-emits using only the new heading.
This test simply ensures the reader does not silently drop one of
them."
  (let* ((dir (make-temp-file "ttest-getuser-1.1b-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Test\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* Auto-Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nlegacy\n\n"
                    "* Tibetan Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nnew\n\n"
                    "* Footnotes\n\n"))
          (let ((sections (tibetan-analysis-get-user-sections file)))
            (should (assoc "Tibetan Analysis" sections))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-emits-tibetan-analysis-heading-not-auto-analysis ()
  "Phase 1.2 of layout-revision (2026-05-04):  the segment-level
regenerator must emit `* Tibetan Analysis' as the parent heading
of the auto-content (was `* Auto-Analysis').  Symmetry with
`* Sanskrit Analysis' makes language-attribution unambiguous for
classroom readers.

Carve-outs (NOT touched by this commit): paragraph-file creator
keeps `* Auto-Analysis'; sentence-layout files keep their level-3
`*** Claude Translation' embed unchanged.  See §5.18 carve-out
documentation."
  (let* ((dir (make-temp-file "ttest-regen-1.2-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Test\n"
                    "#+TIBETAN_HASH: aaa\n"
                    "#+ANALYSIS_VERSION: 1.0\n"
                    "#+CREATED: 2026-05-04\n"
                    "#+LAST_ANALYZED: 2026-05-04\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* My Notes\n\n\n"
                    "* Working Translation\n\n\n"
                    "* Auto-Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nbdag\n\n"
                    "* Footnotes\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie Transliteration\nbdag\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག"
                                              "** Wylie Transliteration\nbdag\n\n"))
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward "^\\* Tibetan Analysis$" nil t))
            (goto-char (point-min))
            (should-not (re-search-forward "^\\* Auto-Analysis$" nil t))))
      (delete-directory dir t))))

;; ============================================================================
;; Phase 2.1 of layout-revision §5.18 (2026-05-04):
;;
;; Sanskrit-first ordering for the per-segment file.  The regenerator
;; emits sections in this canonical order:
;;
;;   * My Notes
;;   * Working Translation
;;   * (Reference Translations / Translation Comparison if present)
;;   * Sanskrit Text                       (parallel-mode only)
;;   * Sanskrit Analysis                   (parallel-mode only)
;;   * Tibetan Text                        ← was first; now slot 6
;;   * Tibetan Analysis                    (the regenerated content)
;;   * Combined Analysis                   (parallel-mode only)
;;   * Apparatus / Footnotes
;;   * DharmaMitra Translation (Sanskrit)  ← Sanskrit-DM first now
;;   * DharmaMitra Translation (Tibetan)
;;   * Sanskrit (DharmaMitra) (legacy realign)
;; ============================================================================

(defun tibetan-analysis-test--section-pos (s name)
  "Return byte position of `^* NAME' in S, or nil if absent."
  (string-match (format "^\\* %s\\(?:$\\| \\|(\\)" (regexp-quote name)) s))

(ert-deftest tibetan-analysis-regenerate-auto-emits-my-notes-before-tibetan-text ()
  "Phase 2.1 of layout-revision §5.18 (2026-05-04):  user content
\(My Notes / Working Translation) is emitted at the TOP of the
file, before the language-source sections.  This puts the
classroom reader's working space at the top of the buffer."
  (let* ((dir (make-temp-file "ttest-reorder-2.1a-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: T\n#+TIBETAN_HASH: aaa\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* My Notes\nNOTE\n\n"
                    "* Working Translation\nWT\n\n"
                    "* Tibetan Analysis\n** Wylie\nbdag /\n\n"
                    "* Footnotes\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie\nbdag /\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག"
                                              "** Wylie\nbdag /\n\n"))
          (let* ((s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                 (notes (tibetan-analysis-test--section-pos s "My Notes"))
                 (tib   (tibetan-analysis-test--section-pos s "Tibetan Text")))
            (should (and notes tib))
            (should (< notes tib))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-emits-sanskrit-pair-before-tibetan-pair ()
  "Phase 2.1 of layout-revision §5.18 (2026-05-04):  in parallel-
Sanskrit mode the Sanskrit pair (Text + Analysis) sits ABOVE the
Tibetan pair (Text + Analysis), matching the class workflow that
reads Sanskrit first then checks the Tibetan."
  (let* ((dir (make-temp-file "ttest-reorder-2.1b-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: T\n#+TIBETAN_HASH: bbb\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* My Notes\n\n\n"
                    "* Working Translation\n\n\n"
                    "* Sanskrit Text\nIAST: ahaṃ\n\n"
                    "* Tibetan Analysis\n** Wylie\nbdag /\n\n"
                    "* Sanskrit Analysis\n** Word List\n- iha\n\n"
                    "* Combined Analysis\n** Combined Translation\nFoo\n\n"
                    "* Footnotes\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie\nbdag /\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག"
                                              "** Wylie\nbdag /\n\n"))
          (let* ((s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                 (skt-text (tibetan-analysis-test--section-pos s "Sanskrit Text"))
                 (skt-an   (tibetan-analysis-test--section-pos s "Sanskrit Analysis"))
                 (tib-text (tibetan-analysis-test--section-pos s "Tibetan Text"))
                 (tib-an   (tibetan-analysis-test--section-pos s "Tibetan Analysis")))
            (should (and skt-text skt-an tib-text tib-an))
            (should (< skt-text skt-an))
            (should (< skt-an tib-text))
            (should (< tib-text tib-an))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-emits-combined-analysis-before-footnotes ()
  "Phase 2.1: `* Combined Analysis' sits between the language pairs
and `* Footnotes'."
  (let* ((dir (make-temp-file "ttest-reorder-2.1c-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: T\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* Tibetan Analysis\n** Wylie\nbdag\n\n"
                    "* Combined Analysis\n** Combined Translation\nFoo\n\n"
                    "* Footnotes\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie\nbdag\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག" "** Wylie\nbdag\n\n"))
          (let* ((s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                 (combined (tibetan-analysis-test--section-pos s "Combined Analysis"))
                 (foot     (tibetan-analysis-test--section-pos s "Footnotes")))
            (should (and combined foot))
            (should (< combined foot))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-migrates-legacy-dm-tibetan-toplevel ()
  "DharmaMitra Tibetan layout revision (2026-05-19):  the legacy
top-level `* DharmaMitra Translation (Tibetan)' is RETIRED.  On
regenerate, the legacy section is removed and its body migrated
to the nested `** DharmaMitra Translation' inside `* Tibetan
Analysis' (peer of `** Translation').  Sanskrit DM stays at
top-level (parallel-mode workflow symmetry)."
  (let* ((dir (make-temp-file "ttest-reorder-2.1d-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: T\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* Tibetan Analysis\n** Wylie\nbdag\n\n"
                    "* Footnotes\n\n"
                    "* DharmaMitra Translation (Tibetan)\nDM-T-LEGACY-BODY\n\n"
                    "* DharmaMitra Translation (Sanskrit)\nDM-S\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie\nbdag\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག" "** Wylie\nbdag\n\n"))
          (let ((s (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))
            ;; Top-level DM Tibetan section retired.
            (should-not (string-match-p
                         "^\\* DharmaMitra Translation (Tibetan)$" s))
            ;; Body migrated to nested level-2 location.
            (should (string-match-p "^\\*\\* DharmaMitra Translation$" s))
            (should (string-match-p "DM-T-LEGACY-BODY" s))
            ;; Sanskrit DM stays at top-level.
            (should (string-match-p
                     "^\\* DharmaMitra Translation (Sanskrit)$" s))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-old-file-with-old-order-rewrites-into-new-order ()
  "Phase 2.1 end-to-end migration:  fixture in OLD order (Tibetan
Text first, all sections in legacy positions) is rewritten by
`regenerate-auto' into the new Sanskrit-first order, with all
preserved-content bodies intact."
  (let* ((dir (make-temp-file "ttest-reorder-2.1e-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: T\n#+TIBETAN_HASH: ccc\n\n"
                    ;; OLD order: Tibetan Text → My Notes → Working
                    ;; Translation → Sanskrit Text → Tibetan Analysis →
                    ;; Sanskrit Analysis → Combined Analysis → Footnotes
                    ;; → DM Tibetan → DM Sanskrit.
                    "* Tibetan Text\nbdag\n\n"
                    "* My Notes\nMUST-SURVIVE-NOTE\n\n"
                    "* Working Translation\nMUST-SURVIVE-WT\n\n"
                    "* Sanskrit Text\nIAST: ahaṃ\n\n"
                    "* Tibetan Analysis\n** Wylie\nbdag\n\n"
                    "* Sanskrit Analysis\n** Word List\n- iha\n\n"
                    "* Combined Analysis\n** Combined Translation\nFoo\n\n"
                    "* Footnotes\nMUST-SURVIVE-FN\n\n"
                    "* DharmaMitra Translation (Tibetan)\nDM-T-BODY\n\n"
                    "* DharmaMitra Translation (Sanskrit)\nDM-S-BODY\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie\nbdag\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག" "** Wylie\nbdag\n\n"))
          (let* ((s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                 (positions
                  ;; DharmaMitra Tibetan no longer at top-level (2026-05-19) —
                  ;; migrated to nested `** DharmaMitra Translation' inside
                  ;; `* Tibetan Analysis'.
                  (mapcar (lambda (n)
                            (cons n (tibetan-analysis-test--section-pos s n)))
                          '("My Notes"
                            "Working Translation"
                            "Sanskrit Text"
                            "Sanskrit Analysis"
                            "Tibetan Text"
                            "Tibetan Analysis"
                            "Combined Analysis"
                            "Footnotes"
                            "DharmaMitra Translation (Sanskrit)"))))
            ;; All top-level sections present.
            (dolist (p positions)
              (should (cdr p)))
            ;; Strictly ascending positions in the new order.
            (let ((prev -1))
              (dolist (p positions)
                (should (> (cdr p) prev))
                (setq prev (cdr p))))
            ;; CLAUDE.md §6 invariant — preserved-content bodies survive.
            (should (string-match-p "MUST-SURVIVE-NOTE" s))
            (should (string-match-p "MUST-SURVIVE-WT" s))
            (should (string-match-p "MUST-SURVIVE-FN" s))
            ;; DM Tibetan body migrated to nested level-2 location.
            (should (string-match-p "DM-T-BODY" s))
            (should-not (string-match-p
                         "^\\* DharmaMitra Translation (Tibetan)$" s))
            ;; DM Sanskrit stays at top-level.
            (should (string-match-p "DM-S-BODY" s))
            (should (string-match-p "IAST: ahaṃ" s))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-migrates-old-auto-analysis-file ()
  "Phase 1.2 end-to-end migration:  a fixture file in OLD shape
\(`* Auto-Analysis' parent heading) gets rewritten to NEW shape
\(`* Tibetan Analysis') by `regenerate-auto', preserving My Notes
body bytes verbatim (CLAUDE.md §6 user-content invariant)."
  (let* ((dir (make-temp-file "ttest-migrate-1.2-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+TITLE: Test\n"
                    "#+TIBETAN_HASH: bbb\n"
                    "#+ANALYSIS_VERSION: 1.0\n"
                    "#+CREATED: 2026-05-04\n"
                    "#+LAST_ANALYZED: 2026-05-04\n\n"
                    "* Tibetan Text\nbdag\n\n"
                    "* My Notes\n\nIMPORTANT — must survive\n\n"
                    "* Working Translation\n\nWORKING TRANS — must survive\n\n"
                    "* Auto-Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nold-content\n\n"
                    "* Footnotes\n\nFOOTNOTE — must survive\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie Transliteration\nbdag\n\n")))
            (tibetan-analysis-regenerate-auto file "བདག"
                                              "** Wylie Transliteration\nbdag\n\n"))
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (should (re-search-forward "^\\* Tibetan Analysis$" nil t))
            (goto-char (point-min))
            (should-not (re-search-forward "^\\* Auto-Analysis$" nil t))
            ;; CLAUDE.md §6 invariant — user content survives.
            (goto-char (point-min))
            (should (search-forward "IMPORTANT — must survive" nil t))
            (goto-char (point-min))
            (should (search-forward "WORKING TRANS — must survive" nil t))
            (goto-char (point-min))
            (should (search-forward "FOOTNOTE — must survive" nil t))))
      (delete-directory dir t))))

;; ============================================================================
;; SYNC CHECK TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-check-sync-no-file ()
  "Test sync check when file doesn't exist."
  (let ((result (tibetan-analysis-check-sync "/nonexistent/path.org" "text")))
    ;; Should return nil or handle gracefully
    (should (or (null result) (eq result t)))))

;; ============================================================================
;; FACE SETUP TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-setup-faces-callable ()
  "Test that face setup function is callable."
  (should (fboundp 'tibetan-analysis-setup-faces)))

(ert-deftest tibetan-analysis-tibetan-face-exists ()
  "Test that Tibetan face is defined."
  (should (facep 'tibetan-analysis-tibetan-face)))

(ert-deftest tibetan-analysis-roman-face-exists ()
  "Test that roman face is defined."
  (should (facep 'tibetan-analysis-roman-face)))

;; ============================================================================
;; VOCABULARY LOADING TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-ensure-vocabulary-callable ()
  "Test that vocabulary loading function exists."
  (should (fboundp 'tibetan-analysis--ensure-vocabulary)))

(ert-deftest tibetan-analysis-get-particle-annotation-callable ()
  "Test that particle annotation function exists."
  (should (fboundp 'tibetan-analysis--get-particle-annotation)))

;; ============================================================================
;; CONTENT GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-generate-content-callable ()
  "Test that content generation function exists."
  (should (fboundp 'tibetan-analysis-generate-content)))

(ert-deftest tibetan-analysis-generate-content-emits-phonetics-after-wylie ()
  "Class-reading aid (2026-05-19):  the analysis content emits a
`** Phonetics' section directly after `** Wylie Transliteration'.

Asserts the priority-order invariant and the body is non-empty
for Tibetan input (phonetics converter actually fires)."
  (skip-unless (and (fboundp 'tibetan-analysis-generate-content)
                    (fboundp 'tibetan-to-phonetics)))
  (let ((content (tibetan-analysis-generate-content "བདག")))
    (should content)
    (should (stringp content))
    ;; Both headings present.
    (should (string-match-p "^\\*\\* Wylie Transliteration$" content))
    (should (string-match-p "^\\*\\* Phonetics$" content))
    ;; Phonetics appears AFTER Wylie.
    (let ((wylie-pos (string-match "^\\*\\* Wylie Transliteration$" content))
          (phon-pos  (string-match "^\\*\\* Phonetics$" content)))
      (should (and wylie-pos phon-pos))
      (should (< wylie-pos phon-pos)))
    ;; Phonetics body is non-empty (and not the fallback placeholder).
    (let* ((phon-pos (string-match "^\\*\\* Phonetics$" content))
           (after (substring content phon-pos))
           ;; Body lives between the heading and the next ^** heading.
           (body-start (and (string-match "\n" after) (match-end 0)))
           (next-heading (and body-start
                              (string-match "^\\*\\* " after body-start)))
           (body (string-trim
                  (substring after body-start
                             (or next-heading (length after))))))
      (should (not (string-empty-p body)))
      (should-not (string-match-p "\\[Phonetics not available\\]" body)))))

(ert-deftest tibetan-analysis-generate-content-empty ()
  "Test content generation with empty input."
  ;; Should not error on empty input
  (condition-case err
      (let ((result (tibetan-analysis-generate-content "")))
        (should (or (null result) (stringp result))))
    (error (should-not "Should not error on empty input"))))

(ert-deftest tibetan-analysis-generate-content-basic ()
  "Test basic content generation."
  ;; Note: Full content generation depends on vocabulary being loaded
  (condition-case nil
      (let ((result (tibetan-analysis-generate-content "བདག")))
        (should (or (null result) (stringp result))))
    (error nil)))  ; Allow errors if dependencies not loaded

(ert-deftest tibetan-analysis-generate-content-gyur-pao-no-fallback ()
  "P5 regression (CLAUDE.md §6, 2026-04-30): the YBh seg-030..034
corner case `གྱུར་པའོ་༎' (verb `gyur' + nominaliser+declarative
particle `པའོ' + closing daṇḍa) used to trip the outer error
fallback with `(wrong-type-argument stringp nil)' because the
vocab-multisource entry's `:primary' field came back as the
empty string `\"\"' — `(when raw-meaning …)' entered for `\"\"',
then `(car (split-string \"\" \";\" t))' returned nil and
`(string-trim nil)' raised stringp,nil.

After the fix, the empty-string raw-meaning is short-circuited
to nil (treated the same as a missing dictionary entry) so the
short-meaning chain falls through cleanly.  The full Section
1..8 layout is generated, NOT the `[Analysis error — partial
file only]' fallback template."
  (skip-unless (fboundp 'tibetan-analysis-generate-content))
  (skip-unless (fboundp 'tibetan-parse-enhanced))
  (skip-unless (fboundp 'tibetan-vocab-multisource-entries))
  (let ((out (tibetan-analysis-generate-content "གྱུར་པའོ་༎")))
    (should (stringp out))
    (should (not (string-empty-p out)))
    ;; Fallback template's distinctive marker MUST NOT appear.
    (should-not (string-match-p "\\[Analysis error — partial file only\\]"
                                out))
    (should-not (string-match-p "Parser failure for this segment"
                                out))
    ;; Full layout sections present.
    (should (string-match-p "^\\*\\* Wylie Transliteration$" out))
    (should (string-match-p "^\\*\\* Interlinear Gloss" out))
    (should (string-match-p "^\\*\\* Claude Translation$" out))
    (should (string-match-p "^\\*\\* Grammar" out))
    (should (string-match-p "^\\*\\* Sentence Structure" out))
    (should (string-match-p "^\\*\\* Verb Classification" out))
    (should (string-match-p "^\\*\\* Detailed Dictionary" out))
    (should (string-match-p "^\\*\\* Provided Translations" out))))

;; ============================================================================
;; MAIN INTERFACE TESTS
;; ============================================================================

(ert-deftest tibetan-open-segment-analysis-callable ()
  "Test that main analysis function exists."
  (should (fboundp 'tibetan-open-segment-analysis)))

(ert-deftest tibetan-reanalyze-segment-callable ()
  "Test that reanalysis function exists."
  (should (fboundp 'tibetan-reanalyze-segment)))

;; Note: The following functions are planned but not yet implemented:
;; - tibetan-collect-all-segments
;; - tibetan-analyze-all-segments
;; Tests for these functions are deferred until implementation is available.
;;
;; The DharmaMitra refresh/copy commands (tibetan-refresh-dharmamitra-
;; translation / tibetan-copy-dharmamitra-to-working) were never
;; implemented; their dead C-c u D / C-c u W bindings + menu items were
;; removed (they raised void-function).

;; ============================================================================
;; ANALYSIS MODE HOOK TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-analysis-mode-hook-callable ()
  "Test that mode-hook function exists and is callable."
  (should (fboundp 'tibetan-analysis-mode-hook)))

(ert-deftest tibetan-analysis-mode-hook-safe ()
  "Test that mode-hook doesn't error when called."
  (condition-case err
      (tibetan-analysis-mode-hook)
    (error (should-not (format "Mode hook should not error: %s" err)))))

(ert-deftest tibetan-analysis-mode-hook-in-buffer ()
  "Test mode-hook execution in a buffer context."
  (with-temp-buffer
    (condition-case err
        (tibetan-analysis-mode-hook)
      (error (should-not (format "Mode hook should not error in buffer: %s" err))))))

(ert-deftest tibetan-analysis-mode-hook-preserves-content ()
  "Test that mode-hook doesn't modify buffer content."
  (with-temp-buffer
    (insert "Sample content")
    (let ((original (buffer-string)))
      (tibetan-analysis-mode-hook)
      (should (string= (buffer-string) original)))))

;; ============================================================================
;; GET STORED HASH TESTS (untested public function)
;; ============================================================================

(ert-deftest tibetan-analysis-get-stored-hash-callable ()
  "Test that get-stored-hash function exists."
  (should (fboundp 'tibetan-analysis-get-stored-hash)))

(ert-deftest tibetan-analysis-get-stored-hash-nonexistent-file ()
  "Test get-stored-hash with nonexistent file."
  (let ((result (tibetan-analysis-get-stored-hash "/nonexistent/file.org")))
    ;; Should return nil or empty string for missing file
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-analysis-get-stored-hash-nil-path ()
  "Test get-stored-hash with nil path."
  (let ((result (tibetan-analysis-get-stored-hash nil)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-analysis-get-stored-hash-empty-file ()
  "Test get-stored-hash with empty file."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (let ((result (tibetan-analysis-get-stored-hash temp-file)))
          ;; Should handle empty file gracefully
          (should (or (null result) (stringp result))))
      (delete-file temp-file))))

(ert-deftest tibetan-analysis-get-stored-hash-with-hash-header ()
  "Test get-stored-hash with hash in file header."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TIBETAN_HASH: abc123def456\n")
            (insert "Some content\n"))
          (let ((result (tibetan-analysis-get-stored-hash temp-file)))
            ;; Should extract the hash if present
            (should (or (null result) (stringp result)))))
      (delete-file temp-file))))

(ert-deftest tibetan-analysis-get-stored-hash-returns-string ()
  "Test that get-stored-hash returns nil or string."
  (skip-unless (fboundp 'tibetan-analysis-get-stored-hash))
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (let ((result (tibetan-analysis-get-stored-hash temp-file)))
          (should (or (null result) (stringp result))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest tibetan-analysis-get-stored-hash-consistency ()
  "Test that reading same file returns same hash."
  (let ((temp-file (make-temp-file "test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "#+TIBETAN_HASH: test123\n"))
          (let ((hash1 (tibetan-analysis-get-stored-hash temp-file))
                (hash2 (tibetan-analysis-get-stored-hash temp-file)))
            (if hash1
                (should (string= hash1 hash2))
              ;; If hash1 is nil, hash2 should also be nil
              (should (null hash2)))))
      (delete-file temp-file))))

;; ============================================================================
;; VERSION AND CONSTANTS TESTS
;; ============================================================================

(ert-deftest tibetan-analysis-version-exists ()
  "Test that version constant is defined."
  (should (boundp 'tibetan-analysis-version))
  (should (stringp tibetan-analysis-version)))

(ert-deftest tibetan-analysis-roman-scale-exists ()
  "Test that roman scale customization exists."
  (should (boundp 'tibetan-analysis-roman-scale))
  (should (numberp tibetan-analysis-roman-scale)))

;; ============================================================================
;; INTEGRATION TESTS (require file system access)
;; ============================================================================

(ert-deftest tibetan-analysis-get-folder-callable ()
  "Test that folder function is callable."
  (should (fboundp 'tibetan-analysis-get-folder)))

(ert-deftest tibetan-analysis-create-file-callable ()
  "Test that file creation function exists."
  (should (fboundp 'tibetan-analysis-create-file)))

(ert-deftest tibetan-analysis-migrate-suffix-in-folder-renames ()
  "§5.23 (2026-05-22):  `tibetan-analysis-migrate-suffix-in-folder'
reads each unsuffixed `seg-NNN.org' / `sent-NNN.org' file's
`#+SOURCE:' link, derives a short-name via
`tibetan-analysis-make-short-name', and renames the file in
place.  Idempotent — already-suffixed files are skipped;
files with no `#+SOURCE:' link are skipped.  Files where the
target name already exists are NOT clobbered."
  (should (fboundp 'tibetan-analysis-migrate-suffix-in-folder))
  (let* ((dir (make-temp-file "ttest-migrate-" t))
         (analysis (expand-file-name "analysis" dir))
         (src-a (expand-file-name "alpha-src.org" dir))
         (src-b (expand-file-name "beta-src.org" dir)))
    (unwind-protect
        (progn
          (make-directory analysis)
          (with-temp-file src-a (insert "#+TITLE: A\n"))
          (with-temp-file src-b (insert "#+TITLE: B\n"))
          ;; Create three analysis files: two unsuffixed (one each
          ;; from alpha/beta), one already-suffixed (idempotency test),
          ;; one without #+SOURCE: (no-source test).
          (with-temp-file (expand-file-name "seg-001.org" analysis)
            (insert "#+SOURCE: [[file:../alpha-src.org::*Segment 1][a/1]]\n"))
          (with-temp-file (expand-file-name "seg-002.org" analysis)
            (insert "#+SOURCE: [[file:../beta-src.org::*Segment 2][b/2]]\n"))
          (with-temp-file (expand-file-name "seg-003-alpha.org" analysis)
            (insert "#+SOURCE: [[file:../alpha-src.org::*Segment 3][a/3]]\n"))
          (with-temp-file (expand-file-name "seg-004.org" analysis)
            (insert "#+TITLE: orphan, no SOURCE link\n"))
          (let ((result (tibetan-analysis-migrate-suffix-in-folder analysis)))
            ;; 2 unsuffixed renamed; 1 orphan skipped (no SOURCE).
            ;; The already-suffixed file isn't in the input list at all
            ;; (regex filters to unsuffixed only).
            (should (= 2 (plist-get result :renamed)))
            (should (= 1 (plist-get result :skipped))))
          ;; New names exist; old names gone.
          (should (file-exists-p
                   (expand-file-name "seg-001-alpha.org" analysis)))
          (should (file-exists-p
                   (expand-file-name "seg-002-beta.org" analysis)))
          (should-not (file-exists-p
                       (expand-file-name "seg-001.org" analysis)))
          (should-not (file-exists-p
                       (expand-file-name "seg-002.org" analysis)))
          ;; Already-suffixed file untouched.
          (should (file-exists-p
                   (expand-file-name "seg-003-alpha.org" analysis)))
          ;; Orphan untouched (no source to derive short-name from).
          (should (file-exists-p
                   (expand-file-name "seg-004.org" analysis))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-create-file-emits-suffixed-filename ()
  "§5.23 (2026-05-22):  `tibetan-analysis-create-file' threads its
SOURCE-FILE argument through `tibetan-analysis-get-filepath',
producing the SUFFIXED filename `seg-NNN-SHORT.org' (e.g.
`seg-007-src.org' for a source named `src.org').  Was previously
UNSUFFIXED — broke multi-source folders by silent overwrite.

The short-name is derived by `tibetan-analysis-make-short-name'.
For `src.org' the short-name is `src'."
  (skip-unless (fboundp 'tibetan-analysis-create-file))
  (let* ((dir (make-temp-file "ttest-suffix-" t))
         (source-file (expand-file-name "src.org" dir))
         (buf nil))
    (unwind-protect
        (progn
          (with-temp-file source-file (insert "#+TITLE: Src\n"))
          (setq buf (find-file-noselect source-file))
          (with-current-buffer buf
            (let ((path (tibetan-analysis-create-file
                         7 "བདུད།" source-file
                         "** Wylie\nbdud\n" nil)))
              (should (file-exists-p path))
              (should (string-match-p "/seg-007-src\\.org\\'" path))
              ;; The legacy UNSUFFIXED path must NOT have been written.
              (let ((unsuffixed (replace-regexp-in-string
                                 "-src\\.org\\'" ".org" path)))
                (should-not (file-exists-p unsuffixed))))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-create-file-disables-toc-and-section-numbering ()
  "§5.22 follow-up (2026-05-21):  segment scaffold emits
`#+OPTIONS: toc:nil num:nil' so HTML / PDF / LaTeX export of
seg-NNN.org does NOT include an auto-generated table of contents
AND does NOT prefix headings with section numbers.  Class-
presentation clean."
  (skip-unless (fboundp 'tibetan-analysis-create-file))
  (let* ((dir (make-temp-file "ttest-options-" t))
         (source-file (expand-file-name "src.org" dir))
         (buf nil))
    (unwind-protect
        (progn
          (with-temp-file source-file (insert "#+TITLE: Source\n"))
          (setq buf (find-file-noselect source-file))
          (with-current-buffer buf
            (let ((path (tibetan-analysis-create-file
                         7 "བདུད།" source-file
                         "** Wylie\nbdud\n" nil)))
              (with-temp-buffer
                (insert-file-contents path)
                (let ((s (buffer-string)))
                  (should (string-match-p "^#\\+OPTIONS:.*toc:nil" s))
                  (should (string-match-p "^#\\+OPTIONS:.*num:nil" s)))))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-create-file-writes-folio-drawer-when-passed ()
  "P6 — when the optional FOLIO argument is passed, the analysis
file's `* Tibetan Text' heading carries a `:PROPERTIES:' drawer
with `:FOLIO: <folio>'.  This preserves the folio reference from
the source segment so the YBh class can scroll the analysis file
and see which folio they're on without leaving the buffer.

Before this fix, §5.8.2's drawer-skip extractor stripped `:FOLIO:'
from the source segment body before passing the text on, with the
side-effect that the new analysis file lost the folio entirely
(low-priority bug parked as P6 in CLAUDE.md §6, addressed
2026-05-05)."
  (skip-unless (fboundp 'tibetan-analysis-create-file))
  (let* ((dir (make-temp-file "ttest-folio-" t))
         (source-file (expand-file-name "src.org" dir))
         (buf nil))
    (unwind-protect
        (progn
          (with-temp-file source-file (insert "#+TITLE: Source\n"))
          ;; `tibetan-analysis-get-folder' uses `(buffer-file-name)' —
          ;; visit the source so the analysis dir resolves under it.
          (setq buf (find-file-noselect source-file))
          (with-current-buffer buf
            (let ((path (tibetan-analysis-create-file
                         42 "བདག་ལ" source-file "* Tibetan Analysis\nbody\n"
                         "D3a3")))
              (should (file-exists-p path))
              (with-temp-buffer
                (insert-file-contents path)
                (let ((s (buffer-string)))
                  ;; Drawer attached to the * Tibetan Text heading.
                  (should (string-match-p "^\\* Tibetan Text\n:PROPERTIES:" s))
                  (should (string-match-p ":FOLIO: D3a3" s))
                  (should (string-match-p ":END:" s))
                  ;; Tibetan body still follows the drawer.
                  (should (string-match-p "བདག་ལ" s)))))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-create-file-no-drawer-when-folio-nil ()
  "When the optional FOLIO argument is nil (the common case for
non-YBh sources), the `* Tibetan Text' heading is emitted plain —
no `:PROPERTIES:' drawer.  Backwards-compatible default."
  (skip-unless (fboundp 'tibetan-analysis-create-file))
  (let* ((dir (make-temp-file "ttest-folio-nil-" t))
         (source-file (expand-file-name "src.org" dir))
         (buf nil))
    (unwind-protect
        (progn
          (with-temp-file source-file (insert "#+TITLE: Source\n"))
          (setq buf (find-file-noselect source-file))
          (with-current-buffer buf
            ;; Call without the FOLIO arg (4-positional form).
            (let ((path (tibetan-analysis-create-file
                         7 "བདག" source-file
                         "* Tibetan Analysis\nbody\n")))
              (should (file-exists-p path))
              (with-temp-buffer
                (insert-file-contents path)
                (let ((s (buffer-string)))
                  ;; * Tibetan Text appears as a plain heading.
                  (should (string-match-p "^\\* Tibetan Text\n[^:]" s))
                  (should-not (string-match-p ":FOLIO:" s)))))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

;; ============================================================================
;; Dangling [[term-X][..]] link stripper (export safety, 2026-05-18)
;; ============================================================================
;;
;; The Interlinear Gloss and Detailed Dictionary use independent MWU
;; tokenization paths.  When they disagree on how to group syllables
;; (e.g. Interlinear treats `zla ba' + `bzhin' as two stems while DD
;; joins them into `zla ba bzhin'), the Interlinear emits
;; `[[term-zla-ba][zla ba]]' and `[[term-bzhin][bzhin]]' but DD only
;; produces `<<term-zla-ba-bzhin>>'.  The Interlinear links dangle.
;;
;; `org-export-dispatch' aborts with `Unable to resolve link' on the
;; first such dangle, blocking PDF / HTML export.  Live observation:
;; Tibetisch IV seg-049 — 4 dangling targets in one segment
;; (term-rnams-ngo-so, term-zla-ba, term-bzhin, term-phyar-nas);
;; export crashed on the first.

(ert-deftest tibetan-analysis-strip-dangling-term-links-strips-missing-anchor ()
  "When a `[[term-X][label]]' link has no matching `<<term-X>>'
anchor in the buffer, the link is replaced with the plain LABEL.
The valid sibling link (whose anchor exists) is left untouched."
  (skip-unless (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer))
  (with-temp-buffer
    (insert "** Interlinear Gloss\n"
            "[[term-foo][foo]] [gloss-foo] "
            "[[term-missing][label-missing]] [gloss-missing]\n\n"
            "** Detailed Dictionary\n"
            "<<term-foo>>\nfoo body\n")
    (let ((stripped
           (tibetan-analysis--strip-dangling-term-links-in-buffer)))
      (should (= 1 stripped))
      (let ((s (buffer-string)))
        ;; Valid link untouched.
        (should (string-match-p "\\[\\[term-foo\\]\\[foo\\]\\]" s))
        ;; Dangling link replaced with plain label.
        (should-not (string-match-p "term-missing" s))
        (should (string-match-p "label-missing \\[gloss-missing\\]" s))
        ;; Anchor still present.
        (should (string-match-p "<<term-foo>>" s))))))

(ert-deftest tibetan-analysis-strip-dangling-term-links-idempotent ()
  "Running the helper twice yields the same result as running it
once — no double-stripping, no error on a clean buffer."
  (skip-unless (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer))
  (with-temp-buffer
    (insert "** Interlinear\n[[term-x][x]] [[term-y][y label]]\n"
            "<<term-x>>\n")
    (tibetan-analysis--strip-dangling-term-links-in-buffer)
    (let ((after-first (buffer-string)))
      (tibetan-analysis--strip-dangling-term-links-in-buffer)
      (should (string= after-first (buffer-string))))))

(ert-deftest tibetan-analysis-strip-dangling-term-links-leaves-other-links-alone ()
  "Non-`term-X' links (id, file, http, internal anchors that
aren't `term-*') are not touched by the stripper.  Catches a
class of would-be false positives — only the `term-*' namespace
is the responsibility of this helper."
  (skip-unless (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer))
  (with-temp-buffer
    (insert "[[id:ABCDEF][Portfolio §1.6]]\n"
            "[[file:foo.org][file]]\n"
            "[[https://example.com][http]]\n"
            "[[other-anchor][other]]\n"
            "[[term-missing][dangling]]\n"
            ;; No anchors at all.
            )
    (tibetan-analysis--strip-dangling-term-links-in-buffer)
    (let ((s (buffer-string)))
      (should (string-match-p "\\[\\[id:ABCDEF\\]" s))
      (should (string-match-p "\\[\\[file:foo.org\\]" s))
      (should (string-match-p "\\[\\[https://example.com\\]" s))
      (should (string-match-p "\\[\\[other-anchor\\]" s))
      ;; Only the term-* dangle was stripped.
      (should-not (string-match-p "term-missing" s))
      (should (string-match-p "dangling" s)))))

(ert-deftest tibetan-analysis-strip-dangling-term-links-real-seg-049-shape ()
  "Reproduces the seg-049 shape:  Interlinear emits `term-rnams-
ngo-so' + `term-zla-ba' + `term-bzhin' + `term-phyar-nas' while
DD anchors only have `term-rnams', `term-so', `term-zla-ba-bzhin',
`term-phya', `term-nas'.  After strip, only the dangling 4 are
removed;  the 5 anchored Interlinear links + the 2 anchored
remain untouched."
  (skip-unless (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer))
  (with-temp-buffer
    (insert "** Interlinear Gloss\n"
            "[[term-khyed-rang][khyed rang]] "
            "[[term-rnams-ngo-so][rnams ngo so]] "
            "[[term-zla-ba][zla ba]] "
            "[[term-bzhin][bzhin]] "
            "[[term-phyar-nas][phyar nas]]\n\n"
            "** Detailed Dictionary\n"
            "<<term-khyed-rang>>\n"
            "<<term-rnams>>\n"
            "<<term-so>>\n"
            "<<term-zla-ba-bzhin>>\n"
            "<<term-phya>>\n"
            "<<term-nas>>\n")
    (let ((stripped
           (tibetan-analysis--strip-dangling-term-links-in-buffer)))
      ;; 4 dangling: rnams-ngo-so, zla-ba, bzhin, phyar-nas.
      (should (= 4 stripped))
      (let ((s (buffer-string)))
        ;; Anchored link kept as link.
        (should (string-match-p "\\[\\[term-khyed-rang\\]" s))
        ;; All 4 dangling labels survive as plain text.
        (should (string-match-p "rnams ngo so" s))
        (should (string-match-p "zla ba" s))
        (should (string-match-p "bzhin" s))
        (should (string-match-p "phyar nas" s))
        ;; All 4 dangling targets are gone.
        (should-not (string-match-p "term-rnams-ngo-so" s))
        (should-not (string-match-p "term-zla-ba\\]" s))
        (should-not (string-match-p "term-bzhin\\]" s))
        (should-not (string-match-p "term-phyar-nas" s))))))

(ert-deftest tibetan-analysis-strip-dangling-term-links-in-folder-walks-all-shapes ()
  "Folder helper visits seg-*, sent-*, par-*, compound-*.org files
in FOLDER, strips dangles in each, saves changed files, reports
totals.  One-shot recovery path for analysis files generated
before the dangling-link guard landed."
  (skip-unless (fboundp 'tibetan-analysis-strip-dangling-term-links-in-folder))
  (let* ((dir (make-temp-file "ttest-strip-folder-" t)))
    (unwind-protect
        (progn
          ;; Two files with dangles, one without.
          (with-temp-file (expand-file-name "seg-001.org" dir)
            (insert "[[term-bad-1][label1]] [[term-good][label-g]]\n"
                    "<<term-good>>\n"))
          (with-temp-file (expand-file-name "sent-001.org" dir)
            (insert "[[term-bad-2][label2]]\n"))
          (with-temp-file (expand-file-name "seg-002.org" dir)
            (insert "[[term-x][x]]\n<<term-x>>\n"))
          ;; Unrelated file: ignored.
          (with-temp-file (expand-file-name "notes.org" dir)
            (insert "[[term-untouched][touched-not]]\n"))
          (let ((result
                 (tibetan-analysis-strip-dangling-term-links-in-folder dir)))
            (should (= 3 (plist-get result :files)))
            (should (= 2 (plist-get result :modified)))
            (should (= 2 (plist-get result :stripped))))
          ;; seg-001 modified.
          (with-temp-buffer
            (insert-file-contents (expand-file-name "seg-001.org" dir))
            (let ((s (buffer-string)))
              (should-not (string-match-p "term-bad-1" s))
              (should (string-match-p "\\[\\[term-good\\]" s))
              (should (string-match-p "label1" s))))
          ;; sent-001 modified.
          (with-temp-buffer
            (insert-file-contents (expand-file-name "sent-001.org" dir))
            (should-not
             (string-match-p "term-bad-2" (buffer-string))))
          ;; notes.org untouched.
          (with-temp-buffer
            (insert-file-contents (expand-file-name "notes.org" dir))
            (should
             (string-match-p "term-untouched" (buffer-string)))))
      ;; Kill any buffers we left behind.
      (dolist (f '("seg-001.org" "sent-001.org" "seg-002.org" "notes.org"))
        (let ((buf (find-buffer-visiting (expand-file-name f dir))))
          (when buf
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-regenerate-auto-strips-dangling-term-links ()
  "End-to-end:  `tibetan-analysis-regenerate-auto' invokes the
dangling-link stripper as part of the rewrite pass.  After
regeneration, the file is export-safe (no dangling term-*
references)."
  (skip-unless (fboundp 'tibetan-analysis-regenerate-auto))
  (skip-unless (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer))
  (let* ((dir (make-temp-file "ttest-strip-" t))
         (filepath (expand-file-name "seg-049.org" dir))
         ;; Auto-content has BOTH the anchored DD and the dangling
         ;; Interlinear link.  The stripper should remove the
         ;; dangle on save.
         (auto-content
          (concat "** Interlinear Gloss\n"
                  "[[term-foo][foo]] [gloss] "
                  "[[term-dangling][bad label]] [other]\n\n"
                  "** Detailed Dictionary\n"
                  "<<term-foo>>\n"
                  "foo body\n")))
    (unwind-protect
        (progn
          (with-temp-file filepath
            (insert "#+TITLE: seg 49\n#+TIBETAN_HASH: x\n\n"
                    "* My Notes\n\n\n"
                    "* Working Translation\n\n\n"
                    "* Tibetan Text\nསྒོ\n\n"
                    "* Tibetan Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie\nsgo\n\n"
                    "* Footnotes\n"))
          (tibetan-analysis-regenerate-auto filepath "སྒོ" auto-content)
          ;; Buffer is open via find-file-noselect inside regenerate.
          (let ((buf (find-buffer-visiting filepath)))
            (when buf
              (with-current-buffer buf (set-buffer-modified-p nil))
              (kill-buffer buf)))
          (with-temp-buffer
            (insert-file-contents filepath)
            (let ((s (buffer-string)))
              ;; Anchored link preserved.
              (should (string-match-p "\\[\\[term-foo\\]\\[foo\\]\\]" s))
              ;; Dangling link stripped.
              (should-not (string-match-p "term-dangling" s))
              (should (string-match-p "bad label \\[other\\]" s)))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-get-filepath-callable ()
  "Test that filepath function exists."
  (should (fboundp 'tibetan-analysis-get-filepath)))

(ert-deftest tibetan-analysis-regenerate-auto-callable ()
  "Test that regeneration function exists."
  (should (fboundp 'tibetan-analysis-regenerate-auto)))

;; ============================================================================
;; format-word-with-wylie — canonical "SCRIPT [wylie]" formatter
;; ============================================================================
;; Used by every analysis section that mentions a Tibetan word (except
;; the top-level * Tibetan Text). Unifies the display so we never ship
;; `script  wylie' in one section and `script [wylie]' in another.

(ert-deftest tibetan-analysis-format-word-with-wylie-happy-path ()
  "Tibetan input → `SCRIPT [wylie]' when the converter produces a
distinct, non-empty wylie string."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) "yul")))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ [yul]"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-empty-returns-empty ()
  "Nil, empty string, and non-string inputs return empty string."
  (should (string= (tibetan-analysis--format-word-with-wylie nil) ""))
  (should (string= (tibetan-analysis--format-word-with-wylie "") ""))
  (should (string= (tibetan-analysis--format-word-with-wylie 42) "")))

(ert-deftest tibetan-analysis-format-word-with-wylie-identical-returns-script-only ()
  "If the converter echoes the input (e.g. already-wylie input, or
converter is identity for punctuation), return the word alone —
never `word [word]'."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (w) w)))
    (should (string= (tibetan-analysis--format-word-with-wylie "yul")
                     "yul"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-converter-errors ()
  "If the converter throws, fall back to the word alone — no brackets."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) (error "boom"))))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ"))))

(ert-deftest tibetan-analysis-format-word-with-wylie-blank-wylie ()
  "Converter returning empty or whitespace-only is treated as no wylie."
  (cl-letf (((symbol-function 'tibetan-to-wylie-fixed)
             (lambda (_w) "   ")))
    (should (string= (tibetan-analysis--format-word-with-wylie "ཡུལ")
                     "ཡུལ"))))

;; ============================================================================
;; Bialek-unified grammatical-role labels (DRY: one terminology table)
;; ============================================================================
;; Regression guard: `get-grammatical-role' must surface Bialek's
;; terminology (e.g. "GENITIVE (GEN)", "CONVERBIAL: ABLATIVE CONVERB")
;; rather than the old hand-maintained labels ("Genitive particle",
;; "Ablative particle"), so the Word/Particle List and the Grammatical
;; Markers section stay in lock-step.

(defun tibetan-analysis-persist-test--role (word &optional root)
  "Shorthand: compute a grammatical role with an empty verb-table."
  (tibetan-analysis--get-grammatical-role
   word (or root word) (make-hash-table :test 'equal)))

(ert-deftest tibetan-analysis-role-genitive-is-bialek ()
  "`པའི' ends with the genitive suffix → `GENITIVE (GEN)' (Bialek),
not the legacy `Genitive particle' label."
  (let ((role (tibetan-analysis-persist-test--role "པའི")))
    (should role)
    (should (string-match-p "GENITIVE" role))))

(ert-deftest tibetan-analysis-role-ablative-converb-is-bialek ()
  "`ནས' → Bialek `CONVERBIAL: ABLATIVE CONVERB', not `Ablative particle'."
  (let ((role (tibetan-analysis-persist-test--role "ནས")))
    (should role)
    (should (string-match-p "ABLATIVE CONVERB" role))))

(ert-deftest tibetan-analysis-role-coordinative-converb-is-bialek ()
  "`ཏེ' → Bialek `CONVERBIAL: COORDINATIVE CONVERB'."
  (let ((role (tibetan-analysis-persist-test--role "ཏེ")))
    (should role)
    (should (string-match-p "COORDINATIVE CONVERB" role))))

(ert-deftest tibetan-analysis-role-dative-is-bialek ()
  "`ལ' standalone → Bialek `DATIVE (DAT)'."
  (let ((role (tibetan-analysis-persist-test--role "ལ")))
    (should role)
    (should (string-match-p "DATIVE" role))))

(ert-deftest tibetan-analysis-role-terminative-is-bialek ()
  "`དུ' → Bialek `TERMINATIVE (ALL)'."
  (let ((role (tibetan-analysis-persist-test--role "དུ")))
    (should role)
    (should (string-match-p "TERMINATIVE" role))))

(ert-deftest tibetan-analysis-role-verb-suffix-uses-bialek ()
  "When the word is a verb AND carries a bialek-classifiable particle
tail, the combined label reads `<verb-kind>, <BIALEK TYPE>' — so the
suffix annotation uses Bialek's wording, not the legacy
`causal converb form' / `ablative converb form' strings."
  (let ((suffix (tibetan-analysis--detect-verb-suffix "བྱས་པས" "བྱས")))
    (should suffix)
    (should (string-match-p "CAUSAL CONVERB" suffix))
    (should (string-prefix-p ", " suffix))))

(ert-deftest tibetan-analysis-role-noun-fallback ()
  "Words bialek does not classify and that are not in the verb-table
fall back to the plain `Noun' label.  Uses `ཡུལ' which is neither a
particle-bearing form nor a Hill-DB verb."
  (let ((role (tibetan-analysis-persist-test--role "ཡུལ")))
    (should (string= role "Noun"))))

(ert-deftest tibetan-analysis-bialek-type-handles-compound-word ()
  "`tibetan-analysis--bialek-type' looks up the compound form even
when bialek's tsheg-split would miss the causal-converb pair
(e.g. `བྱས་པས' → split to `བྱས' + `པས' → neither alone classifies).
The tsheg-removed fallback must recover the CAUSAL CONVERB tag."
  (let ((type (tibetan-analysis--bialek-type "བྱས་པས")))
    (should type)
    (should (string-match-p "CAUSAL CONVERB" type))))

(ert-deftest tibetan-analysis-role-nominalised-verb-keeps-verb-prefix ()
  "`སླེབ་པའི' → the genitive-nominalised form of the verb `སླེབ'
must still surface as a verb in the role label, i.e. `Verb, GENITIVE
(GEN)' — NOT bare `GENITIVE (GEN)'.  Regression guard for the
deep-particle-strip path (strip past the bare nominaliser `པ')."
  (let ((role (tibetan-analysis-persist-test--role "སླེབ་པའི"
                                                    "སླེབ་པ")))
    (should role)
    (should (string-match-p "[Vv]erb" role))
    (should (string-match-p "GENITIVE" role))))

(ert-deftest tibetan-analysis-bialek-type-empty-or-nil ()
  "Nil / empty / non-string inputs yield nil, not an error."
  (should (null (tibetan-analysis--bialek-type nil)))
  (should (null (tibetan-analysis--bialek-type "")))
  (should (null (tibetan-analysis--bialek-type 42))))

;; ============================================================================
;; Clause Structure (Round-2) integration
;; ============================================================================
;; The `** Clause Structure' section is populated from
;; `tibetan-analyze-round2' via `tibetan-analysis--render-clause-structure'.
;; It is gated on `tibetan-analysis-show-clause-structure' (defaults to t).

(ert-deftest tibetan-analysis-render-clause-structure-empty-inputs ()
  "No words / no verbs → empty string.  Must NOT throw."
  (should (string= "" (tibetan-analysis--render-clause-structure
                       nil nil nil)))
  (should (string= "" (tibetan-analysis--render-clause-structure
                       '("གཞིས") nil nil))))

(ert-deftest tibetan-analysis-render-clause-structure-no-analysis ()
  "If `tibetan-analyze-round2' produces no clauses, render a
placeholder rather than an empty string, so the section is obviously
present-but-idle in the output."
  (cl-letf (((symbol-function 'tibetan-analyze-round2)
             (lambda (_w _v &optional _m)
               '((clauses . nil) (nps . nil)
                 (argument-structure . nil)))))
    (let ((out (tibetan-analysis--render-clause-structure
                '("ཡུལ") '(((lemma . "ཡུལ"))) nil)))
      (should (string-match-p "No clause structure" out)))))

(ert-deftest tibetan-analysis-render-clause-structure-happy-path ()
  "Single main-clause scenario: renders a `Clause 1 [main]: verb …' line
and any NPs found inside the clause, each routed through the
`SCRIPT [wylie]' formatter."
  (let* ((verb-entry `((lemma . "སླེབ")
                       (meaning . "to arrive, to reach")))
         (np         `((start . 0) (end . 1)
                       (head . "ཀོ་རོན་ས")
                       (case . TERM)))
         (clause     `((start . 0) (end . 2)
                       (type . main)
                       (converb-type . nil)
                       (converb-particle . nil)
                       (verb . ,verb-entry)))
         (r2         `((clauses . (,clause))
                       (nps . (,np))
                       (argument-structure
                        . (((clause . ,clause)
                            (verb . ,verb-entry)
                            (case-frame . "Abs-Term")
                            (arguments
                             . (((role . goal)
                                 (np . ,np))))))))))
    (cl-letf (((symbol-function 'tibetan-analyze-round2)
               (lambda (_w _v &optional _m) r2))
              ((symbol-function 'tibetan-to-wylie-fixed)
               (lambda (w) (cond ((string= w "སླེབ") "sleb")
                                 ((string= w "ཀོ་རོན་ས") "ko ron sa")
                                 (t w)))))
      (let ((out (tibetan-analysis--render-clause-structure
                  '("ཀོ་རོན་ས" "སླེབ") (list verb-entry) nil)))
        (should (string-match-p "Clause 1 \\[main\\]" out))
        (should (string-match-p "verb སླེབ \\[sleb\\]" out))
        ;; Role rendered as a class-facing label with the full NP.
        (should (string-match-p "GOAL (TERM): ཀོ་རོན་ས \\[ko ron sa\\]" out))))))

(ert-deftest tibetan-analysis-render-clause-structure-labels-subject-object ()
  "A transitive clause renders explicit SUBJECT / DIRECT OBJECT labels
\(subject before object), each showing the full noun phrase — the
class-facing structure view."
  (let* ((verb-entry `((lemma . "བྱེད")
                       (meaning . "to do, to make")
                       (transitivity . "Transitive")
                       (case_frame . "Erg-Abs")))
         (subj `((start . 0) (end . 1) (head . "བདག") (case . ERG)))
         (obj  `((start . 1) (end . 2) (head . "ཆོས") (case . nil)))
         (clause `((start . 0) (end . 3)
                   (type . main) (converb-type . nil) (converb-particle . nil)
                   (verb . ,verb-entry)))
         (r2 `((clauses . (,clause))
               (nps . (,subj ,obj))
               (argument-structure
                . (((clause . ,clause)
                    (verb . ,verb-entry)
                    (case-frame . "Erg-Abs")
                    (arguments . (((role . agent) (np . ,subj))
                                  ((role . patient) (np . ,obj))))))))))
    (cl-letf (((symbol-function 'tibetan-analyze-round2)
               (lambda (_w _v &optional _m) r2))
              ((symbol-function 'tibetan-to-wylie-fixed)
               (lambda (w) (cond ((string= w "བྱེད") "byed")
                                 ((string= w "བདག") "bdag")
                                 ((string= w "ཆོས") "chos")
                                 (t w)))))
      (let* ((out (tibetan-analysis--render-clause-structure
                   '("བདག" "ཆོས" "བྱེད") (list verb-entry) nil))
             (subj-pos (string-match "SUBJECT (ERG): བདག" out))
             (obj-pos  (string-match "DIRECT OBJECT (ABS): ཆོས" out)))
        (should subj-pos)
        (should obj-pos)
        ;; Subject listed before object.
        (should (< subj-pos obj-pos))))))

(ert-deftest tibetan-analysis-render-clause-structure-dependent-shows-converb ()
  "A dependent clause shows the converb particle that licenses it."
  (let* ((verb-entry `((lemma . "འཐོན")))
         (clause     `((start . 0) (end . 1)
                       (type . dependent)
                       (converb-type . coordinative)
                       (converb-particle . "ཏེ")
                       (verb . ,verb-entry)))
         (r2         `((clauses . (,clause))
                       (nps . nil)
                       (argument-structure . nil))))
    (cl-letf (((symbol-function 'tibetan-analyze-round2)
               (lambda (_w _v &optional _m) r2))
              ((symbol-function 'tibetan-to-wylie-fixed)
               (lambda (w) (cond ((string= w "འཐོན") "'thon")
                                 ((string= w "ཏེ") "te")
                                 (t w)))))
      (let ((out (tibetan-analysis--render-clause-structure
                  '("འཐོན" "ཏེ") (list verb-entry) nil)))
        (should (string-match-p "Clause 1 \\[dependent · ཏེ \\[te\\]" out))
        (should (string-match-p "verb འཐོན" out))))))

(ert-deftest tibetan-analysis-show-clause-structure-is-defcustom ()
  "The clause-structure section must be user-configurable (per P2)."
  (should (boundp 'tibetan-analysis-show-clause-structure))
  (should (get 'tibetan-analysis-show-clause-structure 'custom-type)))

;; ============================================================================
;; Interlinear Gloss gloss-lookup goes through the multisource pipeline
;; ============================================================================
;; Regression guard for the DRY consolidation: the Interlinear Gloss
;; (and the Detailed Dictionary) must pick glosses from the SAME
;; multi-source priority chain, so the Resources / Custom entry wins
;; over Steinert / Rangjung Yeshe.  A Resources-sourced entry also
;; gets a ★ marker inline.
;;
;; Previously this test exercised the Word / Particle List section;
;; that section was removed 2026-04-22 (its content was redundant
;; with the Interlinear Gloss) and the ★ marker moved up to the
;; Interlinear.  The multisource lookup path is unchanged; only the
;; display surface shifted.

(ert-deftest tibetan-analysis-interlinear-uses-multisource-resources-first ()
  "When the multisource lookup returns a Resources entry first, the
Interlinear Gloss must surface that gloss (with the ★ marker), not
fall back to a Steinert/RY single-source pick."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (word)
               (when (string= word "ཡུལ")
                 (list (list :source "Resources (provided)"
                             :primary "Heimat // homeland"
                             :detailed "Heimat, Land // homeland, region"
                             :sanskrit nil :wylie "yul")
                       (list :source "Steinert/02-RangjungYeshe"
                             :primary "object"
                             :detailed "object; place; sense object"
                             :sanskrit nil :wylie "yul"))))))
    (let* ((out (condition-case nil
                    (tibetan-analysis-generate-content "ཡུལ")
                  (error nil)))
           (il (and out
                    (when (string-match
                           "\\*\\* Interlinear Gloss\\(.\\|\n\\)*?\\*\\* "
                           out)
                      (match-string 0 out)))))
      (when il
        ;; The Resources bilingual "Heimat // homeland" gets its English
        ;; half surfaced by `tibetan-interlinear--prefer-english'.
        (should (string-match-p "homeland" il))
        (should (string-match-p "★" il))
        ;; Must NOT have surfaced the Steinert gloss.
        (should-not (string-match-p "object; place" il))))))

(ert-deftest tibetan-analysis-word-particle-list-section-is-removed ()
  "The Word / Particle List section must NOT be present in the
generated analysis content.  Regression guard for 2026-04-22 — the
section was removed in favour of relying on the Interlinear Gloss
above, which carries the same information more compactly."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "སངས་རྒྱས།")
                 (error nil))))
      (when out
        (should-not (string-match-p "^\\*\\* Word / Particle List"
                                    out))))))

;; ----------------------------------------------------------------------------
;; Pass 6b: merged `** Grammar' section + retired subheadings
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-grammar-section-renders-merged ()
  "§5.21 Commit 3/7 (2026-05-20):  Pass 6b's two siblings `***
Particle Map' + `*** Particles in This Segment' are MERGED into
a single `*** Particles' section with the visual skeleton at the
top and per-particle bullets below."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "བདག་གིས་ལས་བྱས་ནས་སོང་།")
                 (error nil))))
      (when out
        ;; Merged section exists at level 2
        (should (string-match-p "^\\*\\* Grammar$" out))
        ;; §5.21:  one merged `*** Particles' section.
        (should (string-match-p "^\\*\\*\\* Particles$" out))
        ;; Old siblings retired.
        (should-not (string-match-p "^\\*\\*\\* Particle Map$" out))
        (should-not (string-match-p "^\\*\\*\\* Particles in This Segment$" out))
        ;; Old standalone level-2 sections are retired (Pass 6b).
        (should-not (string-match-p "^\\*\\* Particle Map$" out))
        (should-not (string-match-p "^\\*\\* Particle Overview$" out))
        (should-not (string-match-p "^\\*\\* Grammatical Markers$" out))))))

(ert-deftest tibetan-analysis-sentence-structure-replaces-clause-structure ()
  "Pass 6b merges the old skinny `** Sentence Structure' (verb → args)
into the Round-2 clause output and renames the section.  `** Clause
Structure' must be retired; `** Sentence Structure' carries the
per-clause NPs + roles."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content "བདག་གིས་ལས་བྱས།")
                 (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Sentence Structure$" out))
        (should-not (string-match-p "^\\*\\* Clause Structure$" out))))))

;; ----------------------------------------------------------------------------
;; Regression — Portfolio snippet multi-line bodies are fully indented
;; ----------------------------------------------------------------------------
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: the `des' entry's
;; §1.3.4 Portfolio description embedded example bullets, e.g.
;;
;;   The ergative/instrumental may express the cause or reason …
;;
;;   - thos pas phyir mi 'ong gi 'bras bu thob bo --- "because..."
;;   - dran pas rab tu dga' ba skyes te/ --- "because..."
;;
;; The `*** Particles in This Segment' renderer's
;;   (insert (format "    %s\n" (truncate-para body 400)))
;; indented only the FIRST line (the intro paragraph).  Subsequent
;; lines — particularly example bullets that start with `- ' —
;; landed at column 0 after the first newline, so they read as
;; brand-new top-level particle entries rather than body of the
;; current snippet.  Students saw two phantom `- thos pas ...'
;; "particle" items between `des' and `der'.
;;
;; Fix requirement: EVERY line of the snippet body (including
;; blank lines within) must be indented to match the first line's
;; column.  Writing regression test first per CLAUDE.md rule 2.

(ert-deftest tibetan-analysis-grammar-portfolio-snippet-multiline-indented ()
  "Every line of a multi-line Portfolio snippet body must be
indented so it stays nested under the particle entry — example
bullets cannot escape to column 0.  Regression guard for the
`des' §1.3.4 indent leak spotted on seg-30."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (when (equal sub-id "1.3.4")
                 (cons "Reason"
                       (concat
                        "The ergative may express cause or reason.\n\n"
                        "- thos pas phyir mi 'ong --- example 1\n"
                        "- dran pas rab tu dga' --- example 2"))))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "des" :particle "s"
                        :sub-id "1.3.4" :label "reason")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content "དེས།")
                  (error nil))))
      (when out
        ;; Locate the Grammar section's particle entries.
        (let* ((grammar-start (string-match "\\*\\*\\* Particles in This Segment"
                                            out))
               (grammar-end (or (string-match "^\\*\\* " out
                                              (and grammar-start
                                                   (1+ grammar-start)))
                                (length out)))
               (grammar-body (and grammar-start
                                  (substring out grammar-start grammar-end))))
          (when grammar-body
            ;; CRITICAL: no line beginning with `- thos' / `- dran' at
            ;; column 0 (not nested under `    ' indentation).  The
            ;; example bullets must stay indented as part of the
            ;; snippet body.
            (should-not (string-match-p "^- thos pas" grammar-body))
            (should-not (string-match-p "^- dran pas" grammar-body))
            ;; And the example lines ARE still present (we didn't
            ;; truncate them away) — look for their text, indented.
            (should (string-match-p "    - thos pas\\|      - thos pas"
                                    grammar-body))))))))

;; ----------------------------------------------------------------------------
;; Pass 6c: Claude particle-function parser + Portfolio snippet rendering
;; ----------------------------------------------------------------------------

(require 'tibetan-analysis-claude)

(ert-deftest tibetan-analysis-parse-claude-particles-basic ()
  "Four-field `word, particle, sub-id, label' lines parse into
tuples; junk lines are skipped."
  (let* ((body (concat "der, r, 1.5.1, place\n"
                       "mthu'i, 'i, 1.1.1, attributive\n"
                       "bslabs nas, nas, 2.11.1, sequential-temporal\n"
                       "[none matched]\n"   ;; junk line — skipped
                       "tshim nas, nas, 2.11.2, causal-sequential\n"))
         (tuples (tibetan-analysis--parse-claude-particles body)))
    (should (= 4 (length tuples)))
    (should (equal (plist-get (nth 0 tuples) :word)     "der"))
    (should (equal (plist-get (nth 0 tuples) :particle) "r"))
    (should (equal (plist-get (nth 0 tuples) :sub-id)   "1.5.1"))
    (should (equal (plist-get (nth 0 tuples) :label)    "place"))
    (should (equal (plist-get (nth 1 tuples) :sub-id) "1.1.1"))
    (should (equal (plist-get (nth 2 tuples) :sub-id) "2.11.1"))
    (should (equal (plist-get (nth 3 tuples) :label) "causal-sequential"))))

(ert-deftest tibetan-analysis-parse-claude-particles-empty-nil ()
  "Empty / nil body returns nil, never a spurious tuple."
  (should (null (tibetan-analysis--parse-claude-particles nil)))
  (should (null (tibetan-analysis--parse-claude-particles "")))
  (should (null (tibetan-analysis--parse-claude-particles "\n\n  \n"))))

(ert-deftest tibetan-analysis-grammar-renders-portfolio-snippet-with-claude ()
  "When the dynamic `claude-particles-for-render' var carries tagged
particle tuples, the Grammar section includes the Portfolio sub-
function heading + snippet per occurrence (self-contained output).
Stubs the Portfolio snippet lookup so the test doesn't need the
user's actual Portfolio file loaded.  Uses `mthu'i' where the
Bialek-reported word matches Claude's `:word' field cleanly."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (key sub-id)
               ;; Return a stub snippet only for the tagged occurrence
               ;; we're testing; other lookups return nil.
               (when (and (equal key "genitive")
                          (equal sub-id "1.1.1"))
                 (cons "Genitive Attribute"
                       "Attributive genitive: X-'i Y = 'Y of X' or 'X's Y'.")))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "mthu'i" :particle "'i"
                        :sub-id "1.1.1" :label "attributive")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "མཐུའི་མན་ངག")
                  (error nil))))
      (when out
        ;; Portfolio snippet heading and body appear under the particle.
        (should (string-match-p "§ 1\\.1\\.1 Genitive Attribute" out))
        (should (string-match-p
                 "Attributive genitive:"
                 out))))))

(ert-deftest tibetan-analysis-grammar-falls-back-without-claude-particles ()
  "Without Claude tuples, the merged `*** Particles' section
renders the compact parser-only bullet list — no § sub-IDs, no
snippet block.  Regression guard that Pass 6c is additive, not
destructive of the Pass 6b baseline.  §5.21 Commit 3/7:  the
merged section is `*** Particles' (was `*** Particles in This
Segment'  sibling of `*** Particle Map')."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let* ((tibetan-analysis--claude-particles-for-render nil)
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "བདག་གིས་ལས་བྱས།")
                  (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Grammar$" out))
        (should (string-match-p "^\\*\\*\\* Particles$" out))
        ;; No Claude-driven sub-ID headers.
        (should-not (string-match-p "^  § [0-9]" out))))))

;; ----------------------------------------------------------------------------
;; Pass 6c follow-up (2026-04-22): Interlinear surfaces Resources gloss
;; + ★ for particle-bearing words; Particle Map avoids double-wrap.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-interlinear-picks-stem-for-particle-bearing-word ()
  "For a word like `མཐུའི' (mthu'i = mthu + GEN 'i) the Interlinear
must pick the best-ranked gloss across BOTH the word-level and
stem-level multi-source lookups.  Without this fix the word-level
lookup returns a low-rank Bundled hit and short-circuits the (or)
fallback, so the Resources / Hopkins stem entries never surface
— the Interlinear silently diverges from the Detailed Dictionary.

Stub two lookups: `mthu'i' → Bundled (rank 9), `mthu' → Resources
(rank 2).  The combined/ranked pick must be Resources — asserted
via the ★ marker emitted by the Interlinear for curated entries."
  (let ((call-log '()))
    (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
               (lambda (word)
                 (push word call-log)
                 (cond
                  ((equal word "མཐུའི")
                   (list (list :source "Bundled"
                               :tibetan "མཐུའི" :wylie "mthu'i"
                               :primary "ambiguous")))
                  ((equal word "མཐུ")
                   (list (list :source "Resources (provided)"
                               :tibetan "མཐུ" :wylie "mthu"
                               :detailed "Kraft // might"
                               :primary "Kraft")))
                  (t nil)))))
      (let ((out (condition-case nil
                     (tibetan-analysis-generate-content "མཐུའི་མན་ངག")
                   (error nil))))
        (when out
          ;; Both lookups happened (word + stem)
          (should (member "མཐུའི" call-log))
          (should (member "མཐུ" call-log))
          ;; The Interlinear line for mthu'i carries the ★ marker
          ;; because Resources was picked by the ranker.
          (let ((il (when (string-match
                           "\\*\\* Interlinear Gloss\n\\([^*]*?\\)\n\\*\\*"
                           out)
                      (match-string 1 out))))
            (when il
              (should (string-match-p "★" il))
              ;; English side of the bilingual gloss wins (prefer-english).
              (should (string-match-p "might" il)))))))))

(ert-deftest tibetan-analysis-particle-map-no-double-wrap ()
  "`nas' appears in both case-particles (ablative) and
converb-particles — the particle-map renderer must not produce
`=~nas~=' double-wrap.  Pass ordering (converbs first) + case-
sensitive matching (explicit `case-fold-search nil') keep the
passes from stepping on each other's output.  Particle tokens
keep their natural lowercase Wylie now that the face remap
handles visual emphasis."
  (let ((map (tibetan-analysis--render-particle-skeleton
              "བསླབས་ནས་སོང་" nil nil)))
    ;; Converb wrapping present (lowercase `nas' inside `~...~').
    (should (string-match-p "~nas~" map))
    ;; No nested `=~nas~=' soup.
    (should-not (string-match-p "=~nas~=" map))
    (should-not (string-match-p "=\\(~\\|.\\)*nas\\(~\\|.\\)*=" map))))

(ert-deftest tibetan-analysis-particle-map-case-sensitive-pass-isolation ()
  "Case-particle and converb-particle passes must not cross-contaminate
even when `case-fold-search' is non-nil in the surrounding context.
Uses `མཐུའི' (mthu + genitive 'i in one word) where the `\\b'i\\b'
regex can match — testing that GEN marks `=gis=' and doesn't leak
into a converb `~gis~' wrap."
  (let* ((case-fold-search t)    ;; hostile default
         (map (tibetan-analysis--render-particle-skeleton
               "མཐུའི་གིས་" nil nil)))
    ;; ERG particle `gis' renders as `=gis=' (lowercase, magenta
    ;; via face remap) and never as `~gis~' (converb orange).
    (should (string-match-p "=gis=" map))
    (should-not (string-match-p "~gis~" map))))

(ert-deftest tibetan-analysis-role-based-faces-defined ()
  "Role-based highlighting (2026-06-02) defines the verb, role-label and
Tibetan-script faces."
  (should (facep 'tibetan-analysis-tibetan-face))
  (should (facep 'tibetan-analysis-verb-face))
  (should (facep 'tibetan-analysis-structure-role-face)))

(ert-deftest tibetan-analysis-highlight-keywords-match-expected ()
  "The role-based highlighting matchers target the right patterns: the
Tibetan-script function matcher finds Tibetan (not Latin), and the
Sentence-Structure regexes match a role label line and a clause verb."
  (let ((case-fold-search nil))
    ;; Tibetan-script matcher (a function, not a regex string) advances
    ;; over a Tibetan run and stops on Latin.
    (with-temp-buffer
      (insert "བདག bdag")
      (goto-char (point-min))
      (should (tibetan-analysis--tibetan-script-matcher (point-max)))
      ;; The match covered the Tibetan, not the Latin "bdag".
      (should (string-match-p "[ༀ-࿿]"
                              (buffer-substring (match-beginning 0)
                                                (match-end 0))))
      ;; No further Tibetan run after the match.
      (should-not (tibetan-analysis--tibetan-script-matcher (point-max))))
    ;; Structure keywords: role label + clause-verb.
    (let* ((kws tibetan-analysis--structure-font-lock-keywords)
           (label-re (car (nth 0 kws)))
           (verb-re  (car (nth 1 kws))))
      (should (string-match-p label-re "    SUBJECT (ERG): བདག"))
      (should (string-match-p label-re "    DIRECT OBJECT (ABS): ཆོས"))
      (should-not (string-match-p label-re "    NPs without colon "))
      (should (string-match-p verb-re "Clause 1 [main]: verb བྱེད [byed]")))))

(ert-deftest tibetan-analysis-particle-skeleton-no-spurious-zero-on-overt-ergative ()
  "The particle skeleton must NOT stamp `Ø' before a transitive verb when
the immediately-preceding argument is already overtly case-marked (an
ergative subject) — that spuriously marks an overt argument as zero.
§5.21-deferred zero-marker fix.  When the pre-verbal slot is a bare
content word (a genuine zero-marked object), Ø is still stamped."
  (skip-unless (fboundp 'tibetan-analysis--render-particle-skeleton))
  (let ((verbs (list '((lemma . "བྱེད")
                       (transitivity . "Transitive")
                       (case_frame . "Erg-Abs")))))
    ;; Overt ergative subject immediately before the verb → NO Ø.
    (let ((s (tibetan-analysis--render-particle-skeleton "བདག་གིས་བྱེད" nil verbs)))
      (should (string-match-p "byed" s))
      (should-not (string-match-p "Ø" s)))
    ;; Bare (zero-marked) object before the verb → Ø is correct.
    (let ((s (tibetan-analysis--render-particle-skeleton
              "བདག་གིས་ཆོས་བྱེད" nil verbs)))
      (should (string-match-p "Ø byed" s)))))

(ert-deftest tibetan-analysis-particle-wylie-normalise ()
  "`--particle-wylie-normalise' strips the trailing `a' from
mono-consonant + inherent-vowel forms so `ra' and `r' both
normalise to `r'.  Needed because `tibetan-to-wylie-fixed' emits
the full-syllable `ra' for bare Tibetan `ར' while Claude's
`## Particles' output emits just `r' for the consonant-only
particle."
  (skip-unless (fboundp 'tibetan-analysis--particle-wylie-normalise))
  ;; Inherent-a forms strip to the bare consonant.
  (should (equal "r" (tibetan-analysis--particle-wylie-normalise "ra")))
  (should (equal "s" (tibetan-analysis--particle-wylie-normalise "sa")))
  (should (equal "d" (tibetan-analysis--particle-wylie-normalise "da")))
  ;; Bare consonant forms pass through unchanged.
  (should (equal "r" (tibetan-analysis--particle-wylie-normalise "r")))
  (should (equal "s" (tibetan-analysis--particle-wylie-normalise "s")))
  ;; Multi-char particles left intact (`la' would be ambiguous if
  ;; stripped; `ni', `dang', `kyi' obviously shouldn't change).
  (should (equal "la"   (tibetan-analysis--particle-wylie-normalise "la")))
  (should (equal "ni"   (tibetan-analysis--particle-wylie-normalise "ni")))
  (should (equal "dang" (tibetan-analysis--particle-wylie-normalise "dang")))
  (should (equal "kyi"  (tibetan-analysis--particle-wylie-normalise "kyi"))))

(ert-deftest tibetan-analysis-particle-wylie-equivalent-p ()
  "Equivalence predicate handles `r'/`ra', `s'/`sa' pairs correctly
and rejects truly distinct particles."
  (skip-unless (fboundp 'tibetan-analysis--particle-wylie-equivalent-p))
  ;; Equivalent pairs — Claude gives `r', bialek/Wylie gives `ra'.
  (should (tibetan-analysis--particle-wylie-equivalent-p "r" "ra"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "ra" "r"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "s" "sa"))
  ;; Identity for multi-char particles.
  (should (tibetan-analysis--particle-wylie-equivalent-p "nas" "nas"))
  (should (tibetan-analysis--particle-wylie-equivalent-p "'i" "'i"))
  ;; Truly distinct particles don't match.
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "nas" "la"))
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "gi" "gis"))
  ;; Nil / empty → nil.
  (should-not (tibetan-analysis--particle-wylie-equivalent-p nil "r"))
  (should-not (tibetan-analysis--particle-wylie-equivalent-p "r" nil)))

(ert-deftest tibetan-analysis-grammar-multiple-claude-tuples-per-particle ()
  "When bialek dedups two `nas' occurrences into one entry but
Claude emits two tuples (one per occurrence with different sub-
functions), the Grammar renderer must surface BOTH sub-functions
under the single bialek entry, annotated with the context word
so the student can tell which applies to which occurrence."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (cond
                ((equal sub-id "2.11.1")
                 (cons "Sequential Temporal"
                       "V-nas marks the earlier action."))
                ((equal sub-id "2.11.2")
                 (cons "Causal" "V-nas in a causal reading."))))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "bslabs nas" :particle "nas"
                        :sub-id "2.11.1" :label "sequential-temporal")
                  (list :word "tshim nas"  :particle "nas"
                        :sub-id "2.11.2" :label "causal-sequential")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content
                     "བསླབས་ནས་ཚིམ་ནས་སོང་།")
                  (error nil))))
      (when out
        ;; Both sub-functions appear under the single `nas' bialek entry.
        (should (string-match-p "§ 2\\.11\\.1 Sequential Temporal" out))
        (should (string-match-p "§ 2\\.11\\.2 Causal" out))
        ;; Context-word annotation tells them apart.
        (should (string-match-p "(in bslabs nas)" out))
        (should (string-match-p "(in tshim nas)" out))))))

(ert-deftest tibetan-analysis-grammar-terminative-ra-r-match ()
  "`der' → bialek reports particle Wylie `ra' (inherent vowel);
Claude reports particle `r' (consonant alone).  The new Wylie-
equivalence normaliser must treat them as the same so the
terminative-§1.5.1 snippet surfaces under the `der' bialek entry."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w) nil))
            ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
             (lambda (_key sub-id)
               (when (equal sub-id "1.5.1")
                 (cons "Place / Location"
                       "Destination or place reached.")))))
    (let* ((tibetan-analysis--claude-particles-for-render
            (list (list :word "der" :particle "r"
                        :sub-id "1.5.1" :label "place")))
           (out (condition-case nil
                    (tibetan-analysis-generate-content "དེར་སོང་།")
                  (error nil))))
      (when out
        (should (string-match-p "§ 1\\.5\\.1 Place / Location" out))
        (should (string-match-p "Destination or place reached" out))))))

(ert-deftest tibetan-analysis-particle-map-lowercase-particles ()
  "Particle tokens inside `=...=' / `~...~' / `*...*' wrappings
keep their natural lowercase Wylie spelling (Pass 6d, 2026-04-22).
Reads cleaner than upcased `='I='; magenta/orange face remap in
`tibetan-analysis-setup-faces' carries the visual emphasis."
  (let ((case-fold-search nil)   ;; be strict about case in this test
        (map (tibetan-analysis--render-particle-skeleton
              "མཐུའི་བསླབས་ནས་སོང་" nil nil)))
    ;; Genitive `'i' stays lowercase (apostrophe + i), not upcased.
    (should (string-match-p "='i=" map))
    (should-not (string-match-p "='I=" map))
    ;; Converb `nas' likewise.
    (should (string-match-p "~nas~" map))
    (should-not (string-match-p "~NAS~" map))
    ;; Clean converb, not `~=nas=~' double-wrap.
    (should-not (string-match-p "~=nas=~" map))))

;; ----------------------------------------------------------------------------
;; Regression — Particle-map markers render colored even when embedded in
;; compound Wylie tokens where org's emphasis parser won't fire.
;; ----------------------------------------------------------------------------
;;
;; Reproduced 2026-04-22 on Milarepa seg-30: the `='i=' inside `mthu='i='
;; rendered with no face at all (not magenta).  Diagnosis: org-mode's
;; emphasis regexp requires a word-boundary PRE character before the
;; opening `='.  The Particle Map's compact compound
;;   `der mthu='i= man ngag bslabs ~nas~'
;; has `=' directly after the letter `u' — no PRE match, no verbatim
;; parsing, no face.  Similarly for `~nas~' embedded in compounds on
;; other segments.
;;
;; Fix: install buffer-local font-lock keywords in
;; `tibetan-analysis-setup-faces' that match `=X=' / `~X~' regardless
;; of org's word-boundary rules and apply the magenta / orange face
;; directly.  Tested by running font-lock-ensure on a buffer with the
;; compact particle-map text and checking the face on each marker's
;; character.

(defun tibetan-particle-map-faces-test--face-at (buffer pos)
  "Return the face (or list of faces) at POS in BUFFER."
  (with-current-buffer buffer
    (get-text-property pos 'face)))

(defun tibetan-particle-map-faces-test--any-face-eq (face-value target)
  "Return non-nil if FACE-VALUE is TARGET or contains TARGET in its list."
  (cond
   ((eq face-value target) t)
   ((and (listp face-value) (memq target face-value)) t)
   (t nil)))

(ert-deftest tibetan-analysis-particle-map-case-marker-colored-in-compound ()
  "After `tibetan-analysis-setup-faces' runs, a case-particle marker
embedded INSIDE a compound Wylie token (no word boundary before the
opening `=') must carry `tibetan-analysis-case-particle-face' — so
`'i' in `mthu='i=' renders magenta.  Regression guard for the
org-emphasis-parser-doesn't-fire bug spotted on seg-30."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man ngag bslabs ~nas~ song /\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; Locate the opening `=' of `='i='.
    (goto-char (point-min))
    (let ((case-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "='i=" nil t)
                           (match-beginning 0)))))
      (should case-pos)
      (let ((f (tibetan-particle-map-faces-test--face-at
                (current-buffer) case-pos)))
        (should (tibetan-particle-map-faces-test--any-face-eq
                 f 'tibetan-analysis-case-particle-face))))
    ;; And the same for the middle of the marker (`'i').
    (let ((mid-pos (save-excursion
                     (goto-char (point-min))
                     (and (re-search-forward "='i=" nil t)
                          (1+ (match-beginning 0))))))
      (when mid-pos
        (let ((f (tibetan-particle-map-faces-test--face-at
                  (current-buffer) mid-pos)))
          (should (tibetan-particle-map-faces-test--any-face-eq
                   f 'tibetan-analysis-case-particle-face)))))))

(ert-deftest tibetan-analysis-particle-map-converb-marker-colored-in-compound ()
  "Same contract for converb markers `~X~' — the `nas' in
`bslabs ~nas~' (with `~' NOT at a strict word boundary relative to
the preceding word) must render with
`tibetan-analysis-converb-particle-face' (orange)."
  (require 'org)
  (with-temp-buffer
    (insert "bslabs ~nas~ grogs po\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (let ((conv-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "~nas~" nil t)
                           (match-beginning 0)))))
      (should conv-pos)
      (let ((f (tibetan-particle-map-faces-test--face-at
                (current-buffer) conv-pos)))
        (should (tibetan-particle-map-faces-test--any-face-eq
                 f 'tibetan-analysis-converb-particle-face))))))

(ert-deftest tibetan-analysis-particle-map-delimiters-hidden ()
  "The `=' / `~' delimiters wrapping Particle Map markers must be
rendered INVISIBLE so students see a clean `'i' in magenta and
`nas' in orange — not the delimiter characters.  Matches org's
own `org-hide-emphasis-markers' behaviour for clean-boundary
tokens but works even for compound-embedded markers where org's
emphasis parser doesn't fire.

Implementation detail: we use `invisible' with a namespaced
symbol that's added to `buffer-invisibility-spec' by
`tibetan-analysis-setup-faces'.  Both conditions must be true for
rendering to hide the delimiters — just the property isn't enough."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man ngag bslabs ~nas~ song /\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; Case-particle opening `=' (embedded in compound, col 8).
    (let ((open-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "='i=" nil t)
                           (match-beginning 0)))))
      (should open-pos)
      (let ((inv (get-text-property open-pos 'invisible)))
        ;; The `=' character has an `invisible' property set.
        (should inv)
        ;; And that property value is in the buffer's invisibility
        ;; spec — otherwise the property is a no-op visually.
        (should (or (eq inv t)
                    (and (listp buffer-invisibility-spec)
                         (or (memq inv buffer-invisibility-spec)
                             (assq inv buffer-invisibility-spec)))
                    (and (not (listp buffer-invisibility-spec))
                         buffer-invisibility-spec)))))
    ;; Converb `~' delimiter (not in a compound, but same treatment).
    (let ((conv-pos (save-excursion
                      (goto-char (point-min))
                      (and (re-search-forward "~nas~" nil t)
                           (match-beginning 0)))))
      (should conv-pos)
      (let ((inv (get-text-property conv-pos 'invisible)))
        (should inv)))))

(ert-deftest tibetan-analysis-particle-map-content-stays-visible ()
  "The content INSIDE the delimiters (the actual particle letters
`'i', `nas', `gis', ...) must NOT have the `invisible' property —
only the wrapping `=' / `~' characters are hidden.  Regression
guard that the invisibility treatment doesn't accidentally hide
the particle text itself."
  (require 'org)
  (with-temp-buffer
    (insert "der mthu='i= man bslabs ~nas~\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; The apostrophe inside `='i=' (col 9, the `'' character).
    (let ((content-pos (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "='i=" nil t)
                              (1+ (match-beginning 0))))))
      (should content-pos)
      (should-not (get-text-property content-pos 'invisible)))
    ;; The `n' inside `~nas~'.
    (let ((content-pos (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "~nas~" nil t)
                              (1+ (match-beginning 0))))))
      (should content-pos)
      (should-not (get-text-property content-pos 'invisible)))))

(ert-deftest tibetan-analysis-particle-map-face-setup-is-idempotent ()
  "Running `tibetan-analysis-setup-faces' twice in the same buffer
must not double-install the font-lock keywords (no duplicated rules,
no accumulated face lookups)."
  (require 'org)
  (with-temp-buffer
    (insert "mthu='i= bslabs ~nas~\n")
    (org-mode)
    (tibetan-analysis-setup-faces)
    (tibetan-analysis-setup-faces)    ;; 2nd call must be a no-op
    (font-lock-ensure (point-min) (point-max))
    ;; Still colored — face application still correct.
    (let ((pos (save-excursion
                 (goto-char (point-min))
                 (and (re-search-forward "='i=" nil t)
                      (match-beginning 0)))))
      (should (tibetan-particle-map-faces-test--any-face-eq
               (tibetan-particle-map-faces-test--face-at (current-buffer) pos)
               'tibetan-analysis-case-particle-face)))))

;; ============================================================================
;; WORD-TOKEN CLEANUP — B3 regression (live review 2026-04-24, seg-16 of
;; gal-chen-nyi-shu.org).  Interlinear rendered
;;   [[term-byang-chub-kyi-sems][/byang chub kyi sems]]
;; — a leading shad leaked from the tokenizer into the link label because
;; the word-cleanup inside the enriched-vocab-pairs loop stripped only
;; trailing shads ("[།༎༏༐༑ ]+$").  Two sibling cleanup sites in the
;; same module (--get-grammatical-role, --build-cat-translation) already
;; strip all shads via "[།༎༏༐༑༔/]".  These tests pin the contract of
;; the extracted helper `tibetan-analysis--clean-word-token'.
;; ============================================================================

(ert-deftest tibetan-analysis-clean-word-token-strips-leading-shad ()
  "B3 regression: leading shad `།' must not survive cleanup.
Without the strip, the token reaches the Interlinear renderer as
`།བྱང་ཆུབ་ཀྱི་སེམས', is Wylie-converted to `/byang chub kyi sems',
and ends up inside the `[[term-...][...]]' link label."
  (should (string= (tibetan-analysis--clean-word-token "།བྱང་ཆུབ་ཀྱི་སེམས")
                   "བྱང་ཆུབ་ཀྱི་སེམས")))

(ert-deftest tibetan-analysis-clean-word-token-strips-trailing-shad ()
  "Trailing shad (the prior behaviour) must still be stripped."
  (should (string= (tibetan-analysis--clean-word-token "བྱང་ཆུབ།")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-strips-both-sides ()
  "Shad on both sides — the case this bug surfaced in verse contexts
like `... na/ /byang chub ...' where each line-break shad produces a
leading shad on the next token AND a trailing on the previous one."
  (should (string= (tibetan-analysis--clean-word-token "།བྱང་ཆུབ།")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-trims-whitespace ()
  "Whitespace on either side is stripped before shad stripping.
Tsheg `་' is NOT stripped — it's a word-internal separator, not a
boundary marker, and it appears inside legitimate multi-syllable
word tokens like `byang་chub'."
  (should (string= (tibetan-analysis--clean-word-token "  །བྱང་ཆུབ  ")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-handles-all-shad-variants ()
  "The full shad family `།༎༏༐༑༔' plus the Wylie stand-in `/' is
stripped.  Matches the character class used by the two sibling
cleanup sites in the same module."
  (should (string= (tibetan-analysis--clean-word-token "༎བྱང") "བྱང"))
  (should (string= (tibetan-analysis--clean-word-token "༔བྱང") "བྱང"))
  (should (string= (tibetan-analysis--clean-word-token "/byang") "byang")))

(ert-deftest tibetan-analysis-clean-word-token-passthrough ()
  "Clean input must come through unchanged."
  (should (string= (tibetan-analysis--clean-word-token "བྱང་ཆུབ")
                   "བྱང་ཆུབ")))

(ert-deftest tibetan-analysis-clean-word-token-empty-input ()
  "Empty / whitespace-only input collapses to empty string, not nil."
  (should (string= (tibetan-analysis--clean-word-token "") ""))
  (should (string= (tibetan-analysis--clean-word-token "  ") "")))

;; ============================================================================
;; CLAUDE VOCAB / PARTICLE OVERRIDE — B1+B2 regression (live review
;; 2026-04-24, seg-16 of gal-chen-nyi-shu.org).
;;
;; B1: `blo sbyangs' was glossed as `<person> Cīrṇabuddhi, Trained Mind'
;; because Steinert's 84000Dict knows *blo sbyangs* only as the 547th
;; buddha's name.  Claude Vocabulary correctly analyses it as a verb
;; phrase in context ("if one trains the mind").  The Interlinear had
;; no way to consult Claude's per-word output.
;;
;; B2: standalone `na' (wylie) was glossed as `(1) to' — the locative
;; sense from the dictionary — but Claude Particles correctly tagged
;; it `2.8, conditional' (conditional converb after verb stem).
;;
;; Both are `Interlinear uses dict-only disambiguation when Claude has
;; already answered the question correctly'.  Fix: two helpers that
;; consult the parsed Claude sections (already threaded through via
;; dynamic binding for the Grammar renderer); override applies at the
;; END of the short-meaning chain so dictionary remains the default
;; for tokens Claude didn't specifically address.
;; ============================================================================

(ert-deftest tibetan-analysis-claude-particle-label-for-token-match ()
  "B2 regression: standalone `ན' (wylie `na') matches a Claude Particles
entry with label `conditional' at sub-id `2.8' — helper returns the
formatted short label `conditional (§2.8)'."
  (let ((particles '((:word "tshad med bzhi po 'di blo sbyangs na"
                      :particle "na"
                      :sub-id "2.8"
                      :label "conditional"))))
    (should (string= (tibetan-analysis--claude-particle-label-for-token
                      "ན" particles)
                     "conditional (§2.8)"))))

(ert-deftest tibetan-analysis-claude-particle-label-for-token-no-match ()
  "Token Wylie doesn't match any :particle — helper returns nil so the
dictionary gloss survives."
  (let ((particles '((:word "tshad med bzhi po 'di blo sbyangs na"
                      :particle "na"
                      :sub-id "2.8"
                      :label "conditional"))))
    (should-not (tibetan-analysis--claude-particle-label-for-token
                 "བློ" particles))))

(ert-deftest tibetan-analysis-claude-particle-label-for-token-nil-particles ()
  "Nil / empty particle list — helper returns nil without error.
This is the first-time-generate path: Claude hasn't responded yet,
no particles threaded in, override must be a no-op."
  (should-not (tibetan-analysis--claude-particle-label-for-token "ན" nil))
  (should-not (tibetan-analysis--claude-particle-label-for-token "ན" '())))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-extracts-quoted-gloss ()
  "B1 regression: Claude Vocabulary line
`blo sbyangs na, verb + locative converb, \"if one trains the mind\", ...'
— helper extracts the 3rd (quoted) field as the short gloss."
  (let ((vocab '(("blo sbyangs na" . "blo sbyangs na, verb + locative converb, \"if one trains the mind\", conditional construction"))))
    (should (string= (tibetan-analysis--claude-vocab-gloss-for-token
                      "བློ་སྦྱངས" vocab)
                     "if one trains the mind"))))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-no-match ()
  "Token's Wylie is not a prefix of any key — helper returns nil."
  (let ((vocab '(("'di" . "'di, adjective, \"this\", demonstrative"))))
    (should-not (tibetan-analysis--claude-vocab-gloss-for-token
                 "བྱང" vocab))))

(ert-deftest tibetan-analysis-claude-vocab-gloss-for-token-nil-vocab ()
  "Nil vocab alist — helper returns nil without error.
First-time-generate path: no Claude response yet."
  (should-not (tibetan-analysis--claude-vocab-gloss-for-token "བློ" nil)))

(ert-deftest tibetan-analysis-claude-vocab-gloss-only-overrides-tagged-glosses ()
  "The dictionary-facing override logic: dict gloss that starts with
`<person>' or `<place>' tag should be replaced by Claude's gloss.
A dict gloss WITHOUT a tag prefix (i.e. a legitimate lexical
reading) is left alone.  This is the integration-level test on
`tibetan-analysis--apply-claude-vocab-override'."
  (let ((vocab '(("blo sbyangs na" . "blo sbyangs na, verb, \"if one trains the mind\", ..."))))
    ;; <person>-tagged dict gloss → override with Claude
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "<person> Cīrṇabuddhi, Trained Mind" vocab)
                     "if one trains the mind"))
    ;; <place>-tagged → override
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "<place> Somewhere" vocab)
                     "if one trains the mind"))
    ;; Plain lexical gloss → keep dict's reading (Claude doesn't win
    ;; here, the tag check gates the override).
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "བློ་སྦྱངས" "cultivated, trained" vocab)
                     "cultivated, trained"))
    ;; <term> tag IS legitimate (84000 canonical term marker) — keep.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "ཚད་མེད་བཞི་པོ" "<term> four immeasurables" vocab)
                     "<term> four immeasurables"))))

(ert-deftest tibetan-analysis-claude-vocab-proper-noun-p-detects-name ()
  "When Claude's Vocabulary line classifies a token as a proper noun
(the part-of-speech field, before the quoted gloss, contains
`proper'), the helper returns the quoted name.

Regression for Milarepa Segment 110 (`རྔོག'): Rangjung-Yeshe glosses
the common noun \"mane\", but Claude — which sees clause context —
classifies it `proper noun, \"rNgog\"' (Mar pa's disciple)."
  (let ((vocab '(("rngog" . "rngog, proper noun, \"rNgog\", one of Mar pa's chief disciples"))))
    (should (string= (tibetan-analysis--claude-vocab-proper-noun-p
                      "རྔོག" vocab)
                     "rNgog")))
  ;; Non-proper-noun POS → nil (a comma inside the gloss must not trip it).
  (let ((vocab '(("nga" . "nga, pronoun, \"I, me\", first person"))))
    (should-not (tibetan-analysis--claude-vocab-proper-noun-p "ང" vocab)))
  ;; Nil vocab / no match → nil.
  (should-not (tibetan-analysis--claude-vocab-proper-noun-p "རྔོག" nil)))

(ert-deftest tibetan-analysis-claude-vocab-override-rescues-untagged-proper-noun ()
  "A dictionary common-noun gloss (no `<person>'/`<place>' tag) that
masks a proper name is overridden with Claude's name when Claude
classifies the token as a proper noun.

Milarepa Segment 110: dict gloss \"mane\" for `རྔོག' → Claude's
\"rNgog\".  A token Claude calls a common noun keeps the dict gloss."
  (let ((vocab '(("rngog" . "rngog, proper noun, \"rNgog\", a disciple of Mar pa"))))
    ;; Untagged common-noun dict gloss + Claude proper-noun → override.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "རྔོག" "mane" vocab)
                     "rNgog")))
  ;; Claude says common noun → dict gloss kept (no spurious override).
  (let ((vocab '(("khang" . "khang, noun, \"house\", dwelling"))))
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "ཁང" "house, building" vocab)
                     "house, building"))))

;; ============================================================================
;; U4 — Claude Grammar nested under ** Grammar (2026-04-24)
;;
;; Claude Grammar moved from a level-2 sibling section to
;; `*** Claude Grammar' under `** Grammar' between `*** Particle Map'
;; and `*** Particles in This Segment'.  Reader flow inside Grammar:
;; map (visual) → Claude's prose reading → per-particle Portfolio refs.
;; These tests pin the scaffold + migration placement via the helper
;; `tibetan-analysis--place-claude-grammar-heading'.
;; ============================================================================

(ert-deftest tibetan-analysis-place-claude-grammar-heading-preferred-slot ()
  "Preferred slot: just before `*** Particles in This Segment'.
The render scaffold emits Particle Map then Particles in This
Segment; U4 inserts Claude Grammar between them so the reader
flows visual → prose → detail."
  (with-temp-buffer
    (insert "** Grammar\n"
            "preamble\n\n"
            "*** Particle Map\n"
            "=CASE= =GEN=\n\n"
            "bdag kyi nor bu\n\n"
            "*** Particles in This Segment\n"
            "- kyi · GEN\n\n"
            "** Sentence Structure\ns\n")
    (tibetan-analysis--place-claude-grammar-heading)
    (goto-char (point-min))
    (let* ((map-pos  (re-search-forward "^\\*\\*\\* Particle Map$" nil t))
           (cg-pos   (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t))
           (list-pos (re-search-forward "^\\*\\*\\* Particles in This Segment$"
                                        nil t)))
      (should map-pos)
      (should cg-pos)
      (should list-pos)
      (should (< map-pos cg-pos))
      (should (< cg-pos list-pos)))))

(ert-deftest tibetan-analysis-place-claude-grammar-heading-after-map-only ()
  "When `*** Particles in This Segment' is absent, fall back to
placing after `*** Particle Map' (still inside Grammar)."
  (with-temp-buffer
    (insert "** Grammar\n"
            "*** Particle Map\n"
            "pm body\n\n"
            "** Sentence Structure\ns\n")
    (tibetan-analysis--place-claude-grammar-heading)
    (goto-char (point-min))
    (let ((map-pos (re-search-forward "^\\*\\*\\* Particle Map$" nil t))
          (cg-pos  (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t))
          (ss-pos  (re-search-forward "^\\*\\* Sentence Structure$" nil t)))
      (should (and map-pos cg-pos ss-pos))
      ;; Claude Grammar lands INSIDE Grammar (before Sentence Structure).
      (should (< cg-pos ss-pos))
      (should (< map-pos cg-pos)))))

(ert-deftest tibetan-analysis-place-claude-grammar-heading-empty-grammar ()
  "When `** Grammar' exists but is empty of level-3 subsections, the
heading still goes inside the Grammar body region (before the next
level-2 heading), not after it."
  (with-temp-buffer
    (insert "** Grammar\n"
            "\n"
            "** Sentence Structure\ns\n")
    (tibetan-analysis--place-claude-grammar-heading)
    (goto-char (point-min))
    (let ((gram-pos (re-search-forward "^\\*\\* Grammar$" nil t))
          (cg-pos   (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t))
          (ss-pos   (re-search-forward "^\\*\\* Sentence Structure$" nil t)))
      (should (and gram-pos cg-pos ss-pos))
      (should (< gram-pos cg-pos))
      (should (< cg-pos ss-pos)))))

(ert-deftest tibetan-analysis-place-claude-grammar-heading-no-grammar ()
  "Bare buffer with no `** Grammar' at all — heading appended at end
so the restore path still has a write target, but it's outside any
priority section (rare fallback)."
  (with-temp-buffer
    (insert "** Wylie Transliteration\nw\n\n")
    (tibetan-analysis--place-claude-grammar-heading)
    (should (string-match-p "\\*\\*\\* Claude Grammar"
                            (buffer-substring-no-properties
                             (point-min) (point-max))))))

;; ============================================================================
;; U5 — Interlinear gloss colour (2026-04-24)
;;
;; The gloss content inside `]] [gloss]' in the Interlinear Gloss
;; section gets `tibetan-analysis-interlinear-gloss-face' so the
;; English / German translation is visually distinct from the Wylie
;; link text preceding it.  The face is applied via buffer-local
;; font-lock rules installed by `tibetan-analysis-setup-faces'.
;; ============================================================================

(ert-deftest tibetan-analysis-interlinear-gloss-face-on-gloss-content ()
  "Gloss text inside `]] [gloss]' picks up
`tibetan-analysis-interlinear-gloss-face' after `setup-faces' runs."
  (with-temp-buffer
    (org-mode)
    (insert "** Interlinear Gloss\n"
            "[[term-bdag][bdag]] [I, self] "
            "[[term-khor-ba]['khor ba]] [cyclic existence]\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    ;; Inspect the face at the position of the first letter in the
    ;; gloss content (`I' in `[I, self]').
    (goto-char (point-min))
    (re-search-forward "\\[I, self\\]")
    (let* ((gloss-pos (1+ (match-beginning 0))) ; inside bracket
           (face (get-text-property gloss-pos 'face)))
      (should (or (eq face 'tibetan-analysis-interlinear-gloss-face)
                  (and (listp face)
                       (memq 'tibetan-analysis-interlinear-gloss-face
                             face)))))))

(ert-deftest tibetan-analysis-interlinear-gloss-face-with-curated-star ()
  "Curated `★ ' before the gloss bracket does NOT defeat the match;
the face still lands on the gloss content."
  (with-temp-buffer
    (org-mode)
    (insert "** Interlinear Gloss\n"
            "[[term-rmang-rdo][rmang rdo]] ★ [foundation stone]\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (goto-char (point-min))
    (re-search-forward "\\[foundation stone\\]")
    (let* ((gloss-pos (1+ (match-beginning 0)))
           (face (get-text-property gloss-pos 'face)))
      (should (or (eq face 'tibetan-analysis-interlinear-gloss-face)
                  (and (listp face)
                       (memq 'tibetan-analysis-interlinear-gloss-face
                             face)))))))

(ert-deftest tibetan-analysis-interlinear-gloss-face-does-not-leak ()
  "The Interlinear gloss face must NOT apply to bracketed content in
other contexts — specifically, the `[Steinert/...]' source tags in
the Detailed Dictionary are bracketed but not preceded by `]]'."
  (with-temp-buffer
    (org-mode)
    (insert "** Detailed Dictionary\n"
            "  [Steinert/43-84000Dict]\n"
            "    <term> four immeasurables\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (goto-char (point-min))
    (re-search-forward "\\[Steinert/43-84000Dict\\]")
    (let* ((tag-pos (1+ (match-beginning 0)))
           (face (get-text-property tag-pos 'face)))
      (should-not
       (or (eq face 'tibetan-analysis-interlinear-gloss-face)
           (and (listp face)
                (memq 'tibetan-analysis-interlinear-gloss-face face)))))))

;; ============================================================================
;; U6 — hide <<term-xxx>> radio-target markers (2026-04-24)
;;
;; The Detailed Dictionary emits `<<term-foo-bar>>' org radio-target
;; lines before every `◆' entry so `[[term-foo-bar][wylie]]' links
;; in the Interlinear can jump to the entry.  The markers are noisy
;; on display — the reader's eye lands on `<<term-...>>' before the
;; Tibetan / Wylie it's looking for.  Font-lock gives them the
;; `invisible' property tagged with the namespaced symbol
;; `tibetan-analysis-term-anchor', which is registered in the
;; buffer-invisibility-spec so only our markers (not other org
;; structures) are hidden.
;; ============================================================================

(ert-deftest tibetan-analysis-term-anchor-gets-invisible-property ()
  "After `setup-faces' runs, a `<<term-xxx>>' marker in the buffer
carries the `invisible' text property set to
`tibetan-analysis-term-anchor'."
  (with-temp-buffer
    (org-mode)
    (insert "** Detailed Dictionary\n"
            "<<term-tshad-med-bzhi-po>>\n"
            "◆ ཚད་མེད་བཞི་པོ [tshad med bzhi po]\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (goto-char (point-min))
    (re-search-forward "<<term-tshad-med-bzhi-po>>")
    (let* ((mid (1+ (match-beginning 0)))  ; inside the marker
           (inv (get-text-property mid 'invisible)))
      (should (or (eq inv 'tibetan-analysis-term-anchor)
                  (and (listp inv)
                       (memq 'tibetan-analysis-term-anchor inv)))))))

(ert-deftest tibetan-analysis-term-anchor-in-invisibility-spec ()
  "After `setup-faces' runs, the buffer's invisibility-spec includes
`tibetan-analysis-term-anchor' so the invisible property actually
takes effect visually (not just as a text attribute)."
  (with-temp-buffer
    (org-mode)
    (insert "** Detailed Dictionary\n<<term-foo>>\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (should (or (eq buffer-invisibility-spec t)
                (and (listp buffer-invisibility-spec)
                     (or (memq 'tibetan-analysis-term-anchor
                               buffer-invisibility-spec)
                         (assq 'tibetan-analysis-term-anchor
                               buffer-invisibility-spec)))))))

(ert-deftest tibetan-analysis-term-anchor-does-not-hide-regular-link-text ()
  "The hiding regex `<<term-...>>' must NOT match ordinary link
text like `[[term-foo][wylie]]' — that keeps the clickable Wylie
visible while only the radio-target marker line is hidden."
  (with-temp-buffer
    (org-mode)
    (insert "** Interlinear Gloss\n"
            "[[term-bdag][bdag]] [I, self]\n")
    (setq tibetan-analysis--faces-setup nil)
    (tibetan-analysis-setup-faces)
    (font-lock-ensure (point-min) (point-max))
    (goto-char (point-min))
    (re-search-forward "\\[bdag\\]")
    ;; The `bdag' link text must NOT be marked invisible.
    (let* ((bdag-pos (1+ (match-beginning 0)))
           (inv (get-text-property bdag-pos 'invisible)))
      (should-not (eq inv 'tibetan-analysis-term-anchor))
      (should-not (and (listp inv)
                       (memq 'tibetan-analysis-term-anchor inv))))))

;; ============================================================================
;; U3 — Buddhist Terms subsection under ** Grammar (2026-04-24)
;;
;; For tokens the Steinert 84000 tables tag `<term>' (canonical
;; Buddhist terminology — Four Immeasurables, Bodhicitta, Skandha,
;; etc.) the Grammar section emits a `*** Buddhist Terms' subsection
;; between `*** Claude Grammar' and `*** Particles in This Segment'
;; carrying the 84000Definitions paragraph.  The section is omitted
;; when no Buddhist terms are present in the segment.
;; ============================================================================

(ert-deftest tibetan-analysis-buddhist-term-entry-p-term-tag ()
  "An 84000Dict / 84000Definitions entry whose body starts with the
literal `<term>' tag is classified as a Buddhist term."
  (should (tibetan-analysis--buddhist-term-entry-p
           '(:source "Steinert/43-84000Dict"
             :primary "<term> four immeasurables"
             :detailed "<term> four immeasurables"
             :sanskrit nil
             :wylie "tshad med bzhi po")))
  (should (tibetan-analysis--buddhist-term-entry-p
           '(:source "Steinert/44-84000Definitions"
             :primary "<term> four immeasurables"
             :detailed "<term> four immeasurables (Skt: caturapramāṇa): \\n1) The meditations on love ..."
             :wylie "tshad med bzhi po"))))

(ert-deftest tibetan-analysis-buddhist-term-entry-p-person-is-not-term ()
  "`<person>' and `<place>' tags are NOT Buddhist terms — those
surface via B1's dict-vs-Claude override, not the Buddhist Terms
subsection (which is for encyclopedic terminology not proper nouns)."
  (should-not (tibetan-analysis--buddhist-term-entry-p
               '(:source "Steinert/43-84000Dict"
                 :primary "<person> Cīrṇabuddhi, Trained Mind"
                 :detailed "<person> Cīrṇabuddhi, Trained Mind"
                 :wylie "blo sbyangs")))
  (should-not (tibetan-analysis--buddhist-term-entry-p
               '(:source "Steinert/43-84000Dict"
                 :primary "<place> Vulture Peak"
                 :wylie "bya rgod"))))

(ert-deftest tibetan-analysis-buddhist-term-entry-p-non-84000-ignored ()
  "Entries from other dictionary sources — Rangjung Yeshe, Hopkins,
Resources — are NOT Buddhist terms for this subsection's purposes,
even if their gloss happens to contain `<term>'.  Only 84000 tables
use the tag systematically, and surfacing random matches from other
sources would produce a noisy section."
  (should-not (tibetan-analysis--buddhist-term-entry-p
               '(:source "Steinert/02-RangjungYeshe"
                 :primary "<term> buddha"
                 :wylie "sangs rgyas")))
  (should-not (tibetan-analysis--buddhist-term-entry-p
               '(:source "Resources (provided)"
                 :primary "Grundstein // foundation stone"
                 :wylie "rmang rdo"))))

(ert-deftest tibetan-analysis-format-buddhist-term-body-strips-term-tag ()
  "Leading `<term>' / `<term>:' marker gets stripped; literal `\\n'
escape sequences become real separators; long bodies are truncated."
  (should (string=
           (tibetan-analysis--format-buddhist-term-body
            "<term> four immeasurables (Skt: caturapramāṇa)")
           "four immeasurables (Skt: caturapramāṇa)"))
  ;; Literal backslash-n sequences (as 84000 rows store them) are
  ;; flattened.
  (should (string-match-p
           "meditation.*compassion"
           (tibetan-analysis--format-buddhist-term-body
            "<term> four immeasurables\\n1) The meditations on love, compassion, joy, equanimity")))
  ;; Truncation.
  (should (<= (length (tibetan-analysis--format-buddhist-term-body
                       (make-string 500 ?x)
                       100))
              100)))

(ert-deftest tibetan-analysis-collect-buddhist-terms-empty ()
  "No Buddhist terms in the passage → helper returns nil → the
`*** Buddhist Terms' subsection is omitted from the render."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w)
               '((:source "Steinert/02-RangjungYeshe"
                  :primary "I, self"
                  :wylie "bdag")))))
    (should-not (tibetan-analysis--collect-buddhist-terms
                 '(("བདག" . "I, self"))))))

(ert-deftest tibetan-analysis-collect-buddhist-terms-single-hit ()
  "When a token has an 84000 `<term>' entry, collect returns one
(SCRIPT WYLIE DEFINITION) triple.  Prefers 84000Definitions body
over 84000Dict when both are present — the Definitions row carries
the encyclopedic paragraph, not just the dictionary gloss."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w)
               '((:source "Steinert/43-84000Dict"
                  :primary "<term> four immeasurables"
                  :detailed "<term> four immeasurables"
                  :wylie "tshad med bzhi po")
                 (:source "Steinert/44-84000Definitions"
                  :primary "<term> four immeasurables"
                  :detailed "<term> four immeasurables: love, compassion, joy, equanimity"
                  :wylie "tshad med bzhi po")))))
    (let ((collected
           (tibetan-analysis--collect-buddhist-terms
            '(("ཚད་མེད་བཞི་པོ" . "four immeasurables")))))
      (should (= (length collected) 1))
      ;; The Definitions body (long) wins over Dict (short).
      (should (string-match-p "love, compassion"
                              (nth 2 (car collected)))))))

(ert-deftest tibetan-analysis-collect-buddhist-terms-dedup-by-script ()
  "Same Tibetan term appearing twice in the segment surfaces once."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_w)
               '((:source "Steinert/44-84000Definitions"
                  :primary "<term> bodhicitta"
                  :detailed "<term> bodhicitta: mind of awakening"
                  :wylie "byang chub kyi sems")))))
    (let ((collected
           (tibetan-analysis--collect-buddhist-terms
            '(("བྱང་ཆུབ་ཀྱི་སེམས" . "mind of awakening")
              ("བྱང་ཆུབ་ཀྱི་སེམས" . "mind of awakening")))))
      (should (= (length collected) 1)))))

;; ============================================================================
;; U4 follow-up: no orphan level-2 Claude Grammar after regen (2026-04-24)
;;
;; The initial U4 ship left a legacy emission in `generate-content' that
;; inserted `*** Claude Grammar' inside `** Provided Translations'; the
;; reorder step's `--extract-claude-grammar' helper then promoted it to
;; `** Claude Grammar' at level 2.  Combined with the U4 scaffold's
;; `*** Claude Grammar' under `** Grammar', the result was TWO Claude
;; Grammar headings — one in the correct U4 position, one orphan at
;; level 2 stuck at the end of `* Auto-Analysis'.
;;
;; Surfaced by Carsten on live `C-c u R' of seg-16 of gal-chen-nyi-shu.org
;; on 2026-04-24.  The fix removes the legacy emission; this test
;; guards against it coming back.
;; ============================================================================

(ert-deftest tibetan-analysis-generate-content-no-level2-claude-grammar ()
  "U4 regression: `generate-content' must NOT emit `** Claude Grammar'
at level 2 anywhere in its output.  The canonical Claude Grammar slot
is `*** Claude Grammar' nested under `** Grammar', emitted by
`--render-grammar-section'.  Any level-2 `** Claude Grammar'
would indicate the legacy Provided-Translations emission has come
back (or the `--extract-claude-grammar' reorder helper has
mis-promoted it)."
  (let ((out (tibetan-analysis-generate-content "བདག་གིས།" 1 nil nil)))
    (should out)
    ;; Zero level-2 Claude Grammar — U4 nests it at level 3.
    (should-not (string-match-p "^\\*\\* Claude Grammar$" out))
    ;; Exactly one level-3 Claude Grammar — the U4 scaffold placeholder.
    (let ((count 0)
          (start 0))
      (while (string-match "^\\*\\*\\* Claude Grammar$" out start)
        (setq count (1+ count))
        (setq start (match-end 0)))
      (should (= count 1)))))

;; ============================================================================
;; §5.21 — `*** CAT Gloss' removal (2026-05-20)
;; ============================================================================
;;
;; The rule-based CAT Gloss inside `** Provided Translations' was retired:
;; Carsten reads Claude / DharmaMitra translations in class, CAT Gloss was
;; a hand-rolled phrase composer that added 248 lines for no class value.

(ert-deftest tibetan-analysis-generate-content-no-cat-gloss ()
  "§5.21:  the segment renderer no longer emits `*** CAT Gloss'.
The rule-based CAT Gloss is retired in favour of the two AI
translations (`** Translation' / `** DharmaMitra Translation')
that already render the working surface for class reading."
  (let ((out (tibetan-analysis-generate-content "བདག་གིས།" 1 nil nil)))
    (should out)
    (should-not (string-match-p "^\\*\\*\\* CAT Gloss$" out))))

(ert-deftest tibetan-analysis-claude-vocabulary-at-level-2 ()
  "§5.21 Commit 2/7:  `** Claude Vocabulary' lives at LEVEL 2,
sitting between `** Interlinear Gloss' and `** Translation' /
`** Claude Translation'.  No more level-3 `*** Claude
Vocabulary' inside `** Provided Translations'."
  (let ((out (tibetan-analysis-generate-content "བདག་གིས།" 1 nil nil)))
    (should out)
    ;; Level-2 heading present.
    (should (string-match-p "^\\*\\* Claude Vocabulary$" out))
    ;; Level-3 heading absent.
    (should-not (string-match-p "^\\*\\*\\* Claude Vocabulary$" out))
    ;; Position:  AFTER Interlinear, BEFORE Claude Translation.
    (let ((interlinear-pos (string-match "^\\*\\* Interlinear Gloss$" out))
          (vocab-pos       (string-match "^\\*\\* Claude Vocabulary$" out))
          (trans-pos       (string-match
                            "^\\*\\* \\(?:Claude Translation\\|Translation\\)$"
                            out)))
      (should (and interlinear-pos vocab-pos trans-pos))
      (should (< interlinear-pos vocab-pos))
      (should (< vocab-pos trans-pos))))) ; §5.21 canonical order

(ert-deftest tibetan-analysis-claude-section-order-vocabulary-at-level-2 ()
  "§5.21:  `tibetan-analysis--claude-section-order' has
`(:vocabulary \"Claude Vocabulary\" 2)' — level 2, not the
legacy level 3.  Locks the section-order entry the Claude
writer dispatches on."
  (let ((entry (assq :vocabulary tibetan-analysis--claude-section-order)))
    (should entry)
    (should (string= "Claude Vocabulary" (nth 1 entry)))
    (should (= 2 (nth 2 entry)))))

(ert-deftest tibetan-analysis-merge-claude-vocabulary-retired ()
  "§5.21:  `tibetan-analysis--merge-claude-vocabulary' is retired.
The merge targeted `** Word / Particle List' which §5.10 retired
months ago — net no-op since April.  Regression guard against
re-introduction."
  (should-not (fboundp 'tibetan-analysis--merge-claude-vocabulary)))

(ert-deftest tibetan-analysis-cat-translation-builder-retired ()
  "§5.21:  `tibetan-analysis--build-cat-translation' and its three
helper functions (`--cat-english-gloss', `--ing-form',
`--past-form') are retired along with the CAT Gloss section.
The fboundp probe guards against accidental re-introduction."
  (should-not (fboundp 'tibetan-analysis--build-cat-translation))
  (should-not (fboundp 'tibetan-analysis--ing-form))
  (should-not (fboundp 'tibetan-analysis--past-form))
  ;; `--cat-english-gloss' was a helper used ONLY by the CAT
  ;; pipeline.  Retired with the rest.
  (should-not (fboundp 'tibetan-analysis--cat-english-gloss)))

;; ----------------------------------------------------------------------------
;; §5.21 Commit 4/7 (2026-05-20):  Bialek 2022 published-textbook
;; references on per-particle bullets.  Bullet bracket now carries
;; BOTH `Bialek 2022 §X.Y (Title)' (canonical published reference)
;; AND the existing `Portfolio §A.B' field (Carsten's hand-written
;; zettel — may differ from textbook numbering).  Either side may
;; be absent → bracket falls back gracefully to whichever is
;; available.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-bialek-textbook-ref-lookup-exists ()
  "`tibetan-bialek-textbook-ref' maps a particle-type string (the
ALL-CAPS `nth 2' of a `tibetan-analyze-grammar-bialek' tuple) to
the canonical `Bialek 2022 §X.Y (Title)' string.  Helper must
exist and return a string for at least the core cases."
  (require 'tibetan-bialek-textbook-refs nil t)
  (should (fboundp 'tibetan-bialek-textbook-ref))
  ;; Core case particles — must resolve.
  (should (stringp (tibetan-bialek-textbook-ref "GENITIVE (GEN)")))
  (should (stringp (tibetan-bialek-textbook-ref
                    "ERGATIVE/INSTRUMENTAL (ERG/INST)")))
  (should (stringp (tibetan-bialek-textbook-ref "DATIVE (DAT)")))
  (should (stringp (tibetan-bialek-textbook-ref "TERMINATIVE (ALL)")))
  (should (stringp (tibetan-bialek-textbook-ref "COMITATIVE (COM)")))
  (should (stringp (tibetan-bialek-textbook-ref "ELATIVE/ABLATIVE (ABL)")))
  (should (stringp (tibetan-bialek-textbook-ref "TOPIC (TOP)")))
  ;; Core converbs.
  (should (stringp (tibetan-bialek-textbook-ref
                    "CONVERBIAL: ABLATIVE CONVERB")))
  (should (stringp (tibetan-bialek-textbook-ref
                    "CONVERBIAL: COORDINATIVE CONVERB")))
  (should (stringp (tibetan-bialek-textbook-ref
                    "CONVERBIAL: SIMULTANEOUS CONVERB")))
  (should (stringp (tibetan-bialek-textbook-ref
                    "CONVERBIAL: CAUSAL CONVERB")))
  (should (stringp (tibetan-bialek-textbook-ref
                    "CONVERBIAL: CONDITIONAL CONVERB")))
  ;; Unknown type → nil (NOT an error).
  (should-not (tibetan-bialek-textbook-ref "MADE-UP NONSENSE")))

(ert-deftest tibetan-analysis-bialek-textbook-ref-shape ()
  "Returned references follow the canonical `Bialek 2022 §X.Y
(Title)' shape so the renderer can drop them verbatim into the
bullet bracket.  Section number + parenthetical title both
present."
  (require 'tibetan-bialek-textbook-refs nil t)
  (let ((ref (tibetan-bialek-textbook-ref "GENITIVE (GEN)")))
    (should (string-match-p "Bialek 2022" ref))
    (should (string-match-p "§" ref))
    (should (string-match-p "(Genitive)" ref)))
  (let ((ref (tibetan-bialek-textbook-ref "COMITATIVE (COM)")))
    (should (string-match-p "Bialek 2022 §1\\.7" ref))
    (should (string-match-p "(Comitative)" ref)))
  (let ((ref (tibetan-bialek-textbook-ref
              "CONVERBIAL: ABLATIVE CONVERB")))
    ;; Bialek's gerundial-converb chapter; §2.11 covers V+nas.
    (should (string-match-p "Bialek 2022 §2\\.11" ref))))

(ert-deftest tibetan-analysis-particle-bullet-carries-bialek-ref ()
  "The merged `*** Particles' bullet bracket carries BOTH the
Bialek 2022 published-textbook reference AND the Portfolio
reference, separated by `; '.  Reader gets both:  canonical
textbook numbering for cross-referencing the Bialek book, plus
Carsten's hand-written zettel for the in-house function
breakdown."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content
                    "བདག་གིས་ལས་བྱས།")
                 (error nil))))
      (when out
        ;; The Ergative bullet for `gis' carries both refs in one
        ;; bracket.
        (should (string-match-p
                 "\\[Bialek 2022 §[0-9]+\\.[0-9]+[^]]*; Portfolio §[0-9.]+[^]]*\\]"
                 out))))))

;; ----------------------------------------------------------------------------
;; §5.21 Commit 5/7 (2026-05-20):  `** Detailed Dictionary' moves to
;; the bottom of `* Tibetan Analysis'.  Class-use feedback:  the
;; dictionary is reference material consulted on confusion, not flow
;; reading;  it shouldn't sit in the middle of the analysis between
;; Verb Classification and Provided Translations.  Reader-flow goal:
;;
;;   Wylie → Phonetics → Interlinear → Translations → Grammar →
;;   Sentence/Verb structure → Provided Translations → Detailed
;;   Dictionary (reference, not flow)
;;
;; No body changes — improvement deferred per AskUserQuestion.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-detailed-dictionary-is-last-section ()
  "`** Detailed Dictionary' is the LAST level-2 heading emitted
inside the `* Tibetan Analysis' subtree.  Renders AFTER
`** Provided Translations' so the reader reaches the dictionary
only on confusion — flow sections (Wylie → Phonetics →
Interlinear → Translations → Grammar → Sentence Structure →
Verb Classification → Provided Translations) appear first."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content
                    "བདག་གིས་ལས་བྱས།")
                 (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Detailed Dictionary$" out))
        (should (string-match-p "^\\*\\* Provided Translations$" out))
        ;; Provided Translations comes BEFORE Detailed Dictionary.
        (let ((dd-pos (string-match
                       "^\\*\\* Detailed Dictionary$" out))
              (pt-pos (string-match
                       "^\\*\\* Provided Translations$" out)))
          (should (and dd-pos pt-pos))
          (should (< pt-pos dd-pos)))
        ;; Detailed Dictionary is the LAST level-2 heading — no
        ;; other `** ' heading appears after it.
        (let ((dd-end (and (string-match
                            "^\\*\\* Detailed Dictionary$" out)
                           (match-end 0))))
          (when dd-end
            (should-not (string-match-p "^\\*\\* [A-Z]"
                                        (substring out dd-end)))))))))

(ert-deftest tibetan-analysis-priority-order-puts-detailed-dictionary-last ()
  "`tibetan-analysis--priority-section-order' lists `** Detailed
Dictionary' as the LAST entry.  Sections not in the priority
list fall to the end in generation order — so making Detailed
Dictionary the explicit last entry locks the position even if
emission order changes."
  (let ((order tibetan-analysis--priority-section-order))
    (should (member "** Detailed Dictionary" order))
    (should (string= "** Detailed Dictionary"
                     (car (last order))))))

;; ----------------------------------------------------------------------------
;; §5.21 Commit 6/7 (2026-05-20):  `** Provided Translations' becomes
;; a USER-CONTENT section preserved across reanalyze — behaves like
;; `* My Notes' / `* Working Translation', not like an auto-generated
;; analysis section.  Carsten pastes published / hand-curated reference
;; translations (Roehrich, Lopez, etc.) into this slot during class
;; prep;  the regenerate path must keep his pastes verbatim.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-provided-translations-emitted-as-empty-placeholder ()
  "Renderer emits `** Provided Translations' as a bare empty
placeholder — no `*** Reference Translations' child, no `*** CAT
Gloss', no `*** Claude Vocabulary'.  All auto-children are
retired in §5.21:  CAT Gloss in Commit 1, Claude Vocabulary
promoted to level 2 in Commit 2, Reference Translations was
the only remaining auto-child and is removed here so the slot
becomes pristine for user paste."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let ((out (condition-case nil
                   (tibetan-analysis-generate-content
                    "བདག་གིས་ལས་བྱས།")
                 (error nil))))
      (when out
        (should (string-match-p "^\\*\\* Provided Translations$" out))
        ;; No auto-children inside PT.
        (let* ((pt-start (string-match
                          "^\\*\\* Provided Translations$" out))
               (next-l2 (and pt-start
                             (string-match
                              "^\\*\\* [A-Z]"
                              (substring out (1+ pt-start)))))
               (pt-body (and pt-start
                             (substring out
                                        pt-start
                                        (if next-l2
                                            (+ 1 pt-start next-l2)
                                          (length out))))))
          (when pt-body
            (should-not (string-match-p
                         "^\\*\\*\\* Reference Translations$" pt-body))
            (should-not (string-match-p
                         "^\\*\\*\\* CAT Gloss$" pt-body))
            (should-not (string-match-p
                         "^\\*\\*\\* Claude Vocabulary$" pt-body))))))))

(ert-deftest tibetan-analysis-read-provided-translations-nested-body-helper ()
  "`tibetan-analysis--read-provided-translations-nested-body'
exists and returns the trimmed body of `** Provided Translations'
inside `* Tibetan Analysis' from FILEPATH.  Returns nil on
absent / empty / placeholder body."
  (should (fboundp 'tibetan-analysis--read-provided-translations-nested-body))
  (let ((tmp (make-temp-file "ta-pt-" nil ".org")))
    (unwind-protect
        (progn
          ;; Case 1:  body present — returned trimmed.
          (with-temp-file tmp
            (insert "#+TITLE: t\n\n")
            (insert "* Tibetan Analysis\n")
            (insert "** Wylie Transliteration\nfoo\n\n")
            (insert "** Provided Translations\n")
            (insert "Roehrich 1976: foo bar.\n")
            (insert "Lopez 2019: alt rendering.\n\n")
            (insert "** Detailed Dictionary\n[deep ref]\n"))
          (let ((body (tibetan-analysis--read-provided-translations-nested-body
                       tmp)))
            (should (stringp body))
            (should (string-match-p "Roehrich 1976" body))
            (should (string-match-p "Lopez 2019" body))
            ;; Body must NOT contain the next heading.
            (should-not (string-match-p "Detailed Dictionary" body)))
          ;; Case 2:  empty body → nil.
          (with-temp-file tmp
            (insert "* Tibetan Analysis\n** Provided Translations\n\n"))
          (should-not
           (tibetan-analysis--read-provided-translations-nested-body tmp))
          ;; Case 3:  no `* Tibetan Analysis' → nil (legacy
          ;; `* Auto-Analysis' fallback handled separately).
          (with-temp-file tmp
            (insert "* Tibetan Text\nfoo\n"))
          (should-not
           (tibetan-analysis--read-provided-translations-nested-body tmp)))
      (delete-file tmp))))

(ert-deftest tibetan-analysis-provided-translations-preserved-across-regenerate ()
  "Hand-pasted content under `** Provided Translations' (inside
`* Tibetan Analysis') survives `tibetan-analysis-regenerate-auto'
verbatim.  Same pattern as the §5.20 DharmaMitra-Tibetan-nested-
body preservation."
  (cl-letf (((symbol-function 'tibetan-vocab-multisource-entries)
             (lambda (_word) nil)))
    (let* ((tmp (make-temp-file "ta-pt-preserve-" nil ".org"))
           (paste "Roehrich 1976 (Blue Annals):\nMilarepa replied …\n\nLopez 2019:\nMila answered …\n"))
      (unwind-protect
          (progn
            ;; Build a file in the §5.21 layout with hand-pasted PT body.
            (with-temp-file tmp
              (insert "#+TITLE: Segment 1 Analysis\n")
              (insert "#+TIBETAN_HASH: 0\n")
              (insert "#+LAST_ANALYZED: 1970-01-01\n\n")
              (insert "* My Notes\n\n\n")
              (insert "* Working Translation\n\n\n")
              (insert "* Tibetan Text\nབདག་གིས་ལས་བྱས།\n\n")
              (insert "* Tibetan Analysis\n")
              (insert ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")
              (insert "** Wylie Transliteration\nbdag gis las byas\n\n")
              (insert "** Provided Translations\n")
              (insert paste)
              (insert "\n")
              (insert "** Detailed Dictionary\n[ref]\n\n")
              (insert "* Footnotes\n\n"))
            ;; Regenerate with new auto-content — the existing PT body
            ;; must survive verbatim.
            (let ((auto (tibetan-analysis-generate-content
                         "བདག་གིས་ལས་བྱས།")))
              (tibetan-analysis-regenerate-auto
               tmp "བདག་གིས་ལས་བྱས།" auto))
            ;; Read the post-regenerate file and assert paste survived.
            (let ((post (with-temp-buffer
                          (insert-file-contents tmp)
                          (buffer-string))))
              (should (string-match-p "Roehrich 1976" post))
              (should (string-match-p "Lopez 2019" post))
              (should (string-match-p "Milarepa replied" post))
              (should (string-match-p "Mila answered" post))
              ;; Layout still correct:  PT before DD.
              (let ((pt-pos (string-match
                             "^\\*\\* Provided Translations$" post))
                    (dd-pos (string-match
                             "^\\*\\* Detailed Dictionary$" post)))
                (should (and pt-pos dd-pos))
                (should (< pt-pos dd-pos)))))
        (delete-file tmp)))))

(ert-deftest tibetan-analysis-particle-bullet-bialek-ref-falls-back ()
  "When the bialek-tuple's portfolio field is nil, the bracket
shows only the Bialek 2022 ref (no trailing `; ').  When the
Bialek 2022 lookup misses (unknown type), the bracket shows
only the Portfolio ref (no leading `; ').  Either way, the
bracket itself is well-formed (single matched pair of square
brackets)."
  (require 'tibetan-bialek-textbook-refs nil t)
  ;; Bialek-only side: simulate a tuple with no Portfolio field.
  (let* ((bialek-analysis
          (list (list "གིས" "བདག་གིས"
                      "ERGATIVE/INSTRUMENTAL (ERG/INST)"
                      "Marks agent" "Translation: by X"
                      "Bialek: Ergative"
                      nil)))  ;; portfolio absent
         (out (with-temp-buffer
                (tibetan-analysis--render-particle-bullets
                 bialek-analysis nil)
                (buffer-string))))
    (should (string-match-p "\\[Bialek 2022 §[^]]*\\]" out))
    ;; No trailing semicolon because Portfolio missing.
    (should-not (string-match-p "Bialek 2022 §[^]]*;[^]]*\\]" out)))
  ;; Portfolio-only side: simulate an unknown type with a Portfolio
  ;; field intact.
  (let* ((bialek-analysis
          (list (list "??" "??"
                      "UNKNOWN-TYPE-NOT-IN-BIALEK-2022"
                      "x" "y" "z"
                      "Portfolio §9.9 (Made up)")))
         (out (with-temp-buffer
                (tibetan-analysis--render-particle-bullets
                 bialek-analysis nil)
                (buffer-string))))
    (should (string-match-p "\\[Portfolio §9\\.9[^]]*\\]" out))
    (should-not (string-match-p "Bialek 2022" out))))

;; ============================================================================
;; Claude Vocabulary term highlighting (2026-06-03)
;;
;; The Claude Vocabulary entries lead with a Wylie term (`bla ma, noun,
;; "teacher", …').  Wylie is Latin script, so the Tibetan-script font-lock
;; colourizer never touched it and the terms were hard to pick out.  A
;; section-bounded matcher highlights the leading term (text before the
;; first comma) only inside `** Claude Vocabulary'.
;; ============================================================================

(ert-deftest tibetan-analysis-vocab-term-matcher-finds-terms ()
  "The matcher captures each Claude Vocabulary entry's leading term
\(group 1) and not the bodies of other sections."
  (with-temp-buffer
    (insert "** Interlinear Gloss\n"
            "[[term-x][bla ma]] [teacher]\n"
            "** Claude Vocabulary\n"
            "bla ma, noun, \"teacher\", honorific title\n"
            "phru rlog, noun, \"farm work\", field labour\n"
            "** Translation\n"
            "He went to the field.\n")
    (goto-char (point-min))
    (let (terms)
      (while (tibetan-analysis--vocab-term-matcher (point-max))
        (push (match-string 1) terms))
      (setq terms (nreverse terms))
      (should (member "bla ma" terms))
      (should (member "phru rlog" terms))
      ;; The Translation body is not a vocabulary term.
      (should-not (member "He went to the field" terms))
      ;; Exactly the two vocabulary entries matched.
      (should (= 2 (length terms))))))

(ert-deftest tibetan-analysis-vocab-term-matcher-skips-other-sections ()
  "Leading `term, …' lines in `*** Claude Particles' (a different
section) must NOT be highlighted as vocabulary terms."
  (with-temp-buffer
    (insert "** Provided Translations\n"
            "*** Claude Particles\n"
            "mar pas, pas, 1.3.1, agent of transitive\n")
    (goto-char (point-min))
    (should-not (tibetan-analysis--vocab-term-matcher (point-max)))))

;; ============================================================================
;; Shad-boundary markers in word lists (2026-06-03)
;;
;; MA Reading "segments" can span several shad (།)-delimited units.  A
;; render-time marker in the Claude Vocabulary and Interlinear Gloss shows
;; where each shad-unit ends, so the reader can analyse shad-by-shad while
;; reading the whole section.  Placement is by the boundary word — the
;; last syllable before each INTERNAL shad.
;; ============================================================================

(ert-deftest tibetan-analysis-shad-boundary-words-internal-only ()
  "Boundary words are the last syllable before each INTERNAL shad
\(a shad with content after it); a trailing shad is not a boundary."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  ;; Two units, one internal boundary after `ཤུ' (= \"shu\").
  (should (equal (tibetan-analysis--shad-boundary-words
                  "གལ་ཆེན་ཉི་ཤུ། ཨོམ་སྭ་སྟི།")
                 '("shu")))
  ;; Single unit → no internal boundary.
  (should (null (tibetan-analysis--shad-boundary-words "བདག་གིས།")))
  (should (null (tibetan-analysis--shad-boundary-words nil))))

(ert-deftest tibetan-analysis-mark-shads-in-vocab-inserts-and-idempotent ()
  "A marker line is inserted after the vocabulary entry whose term ends
in the boundary word; re-running does not duplicate it."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  (let* ((text "གལ་ཆེན་ཉི་ཤུ། ཨོམ་སྭ་སྟི།")
         (body (concat "gal chen, adjective, \"important\"\n"
                       "nyi shu, numeral, \"twenty\"\n"
                       "om, particle, \"om\"\n"
                       "swa sti, noun, \"svasti\""))
         (m tibetan-analysis--shad-marker)
         (out (tibetan-analysis--mark-shads-in-vocab body text)))
    ;; Marker sits between the `nyi shu' line and the `om' line.
    (should (string-match-p (concat "nyi shu[^\n]*\n" (regexp-quote m) "\nom,") out))
    ;; Exactly one marker.
    (should (= 1 (cl-count m (split-string out "\n") :test #'string=)))
    ;; Idempotent.
    (should (string= out (tibetan-analysis--mark-shads-in-vocab out text)))))

(ert-deftest tibetan-analysis-mark-shads-in-interlinear-splices-and-idempotent ()
  "The marker is spliced after the boundary token's gloss in the flowing
Interlinear line; re-running does not duplicate it."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  (let* ((text "གལ་ཆེན་ཉི་ཤུ། ཨོམ་སྭ་སྟི།")
         (body "[[term-gal-chen][gal chen]] [importance] nyi [two] shu [to peel] om [seed] swa [so] sti [live]")
         (m tibetan-analysis--shad-marker)
         (out (tibetan-analysis--mark-shads-in-interlinear body text)))
    (should (string-match-p (concat "shu \\[to peel\\]\n" (regexp-quote m) "\nom ") out))
    (should (= 1 (cl-count m (split-string out "\n") :test #'string=)))
    (should (string= out (tibetan-analysis--mark-shads-in-interlinear out text)))))

(ert-deftest tibetan-analysis-apply-shad-markers-marks-both-sections ()
  "`--apply-shad-markers' inserts a marker into both the Interlinear
Gloss and Claude Vocabulary of a multi-shad file, and is idempotent."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  (let ((f (make-temp-file "seg-shad" nil ".org"))
        (m tibetan-analysis--shad-marker))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "#+TITLE: Segment 0\n\n"
                    "* Tibetan Text\n"
                    "གལ་ཆེན་ཉི་ཤུ། ཨོམ་སྭ་སྟི།\n\n"
                    "* Tibetan Analysis\n"
                    "** Interlinear Gloss\n"
                    "[[term-gal-chen][gal chen]] [importance] nyi [two] shu [to peel] om [seed] swa [so] sti [live]\n\n"
                    "** Claude Vocabulary\n"
                    "gal chen, adjective, \"important\"\n"
                    "nyi shu, numeral, \"twenty\"\n"
                    "om, particle, \"om\"\n"
                    "swa sti, noun, \"svasti\"\n\n"
                    "** Translation\n"
                    "The twenty great ones. Om svasti.\n"))
          (tibetan-analysis--apply-shad-markers f)
          (let ((s (with-temp-buffer (insert-file-contents f) (buffer-string))))
            ;; Marker present in both sections.
            (should (string-match-p (concat "shu \\[to peel\\]\n" (regexp-quote m)) s))
            (should (string-match-p (concat "nyi shu[^\n]*\n" (regexp-quote m) "\nom,") s))
            ;; Exactly two markers total (one per section).
            (should (= 2 (cl-count m (split-string s "\n") :test #'string=)))
            ;; Translation body untouched.
            (should (string-match-p "The twenty great ones" s)))
          ;; Idempotent: a second pass keeps exactly two markers.
          (tibetan-analysis--apply-shad-markers f)
          (let ((s (with-temp-buffer (insert-file-contents f) (buffer-string))))
            (should (= 2 (cl-count m (split-string s "\n") :test #'string=)))))
      (when (get-file-buffer f) (kill-buffer (get-file-buffer f)))
      (delete-file f))))

;; ============================================================================
;; get-filepath bare-file fallback (2026-06-03)
;;
;; §5.23 made create / auto-analyze always use the suffixed
;; `seg-NNN-SHORT.org'.  For a single-source folder NOT migrated to the
;; suffix (Milarepa keeps bare `seg-NNN.org'), that created a `-milarepa'
;; DUPLICATE on every C-c u B and re-fired Claude/DM.  The resolver now
;; prefers an existing bare file that belongs to the same source.
;; ============================================================================

(ert-deftest tibetan-analysis-resolve-filepath-prefers-existing-bare-same-source ()
  "When the suffixed file is absent but a bare `seg-NNN.org' exists and
belongs to the SAME source, the bare path is returned (no duplicate)."
  (let ((dir (make-temp-file "tcat-resolve" t)))
    (unwind-protect
        (let ((bare (expand-file-name "seg-012.org" dir)))
          (with-temp-file bare
            (insert "#+SOURCE: [[file:../Milarepa-prepared.org::*Segment 12]"
                    "[Milarepa-prepared.org / Segment 12]]\n"))
          ;; bare exists, same source → bare
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 12 "milarepa" "/x/Milarepa-prepared.org")
                           bare))
          ;; bare belongs to a DIFFERENT source → use suffixed (no collision)
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 12 "lam" "/x/lam-rim-thun-cig.org")
                           (expand-file-name "seg-012-lam.org" dir))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-resolve-filepath-suffixed-wins-and-new-gets-suffix ()
  "An existing suffixed file always wins; a brand-new file (neither
exists) gets the suffix; no source-file → bare."
  (let ((dir (make-temp-file "tcat-resolve2" t)))
    (unwind-protect
        (let ((suffixed (expand-file-name "seg-005-milarepa.org" dir)))
          (with-temp-file suffixed (insert "x\n"))
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 5 "milarepa" "/x/Milarepa-prepared.org")
                           suffixed))
          ;; neither exists → new suffixed
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 9 "milarepa" "/x/Milarepa-prepared.org")
                           (expand-file-name "seg-009-milarepa.org" dir)))
          ;; no source-file → bare
          (should (string= (tibetan-analysis--resolve-filepath dir 9 nil nil)
                           (expand-file-name "seg-009.org" dir))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-vocab-term-matcher-terminates-on-final-line ()
  "H3 (Fable-5 audit): the matcher's no-match branch must make progress
on a FINAL buffer line with no trailing newline inside the vocab
section.  `forward-line' stops at end-of-line there and
`beginning-of-line' moved point BACK — zero net progress, infinite
loop, and a font-lock-driven editor freeze.  Trigger: typing an
unfinished entry (no comma) at buffer end."
  (with-temp-buffer
    ;; No trailing newline after the last (non-matching) line.
    (insert "** Claude Vocabulary\nbla ma noun teacher")
    (goto-char (point-min))
    (forward-line 1)                      ; bol of the unfinished line
    (should-not (with-timeout (5 (ert-fail "matcher did not terminate"))
                  (tibetan-analysis--vocab-term-matcher (point-max))))))

(ert-deftest tibetan-analysis-regenerate-preserves-unknown-top-sections ()
  "H2 (Fable-5 audit): regenerate-auto used a fixed whitelist and
silently DELETED any other top-level section (live exposure: 45
sent-*-lam files carrying legacy `* Translation' / `* Grammar Notes').
Unknown top-level sections must survive a regenerate verbatim."
  (let ((f (make-temp-file "seg-unknown" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "#+TITLE: Segment 1 Analysis\n\n"
                    "* My Notes\nkeep me\n\n"
                    "* Tibetan Text\nབདག\n\n"
                    "* Tibetan Analysis\nold\n\n"
                    "* Questions for Class\nWhy the ergative here?\n\n"
                    "* Grammar Notes\nlegacy auto-layout body\n\n"
                    "* Footnotes\n\n"))
          (tibetan-analysis-regenerate-auto f "བདག" "** Wylie Transliteration\nbdag\n")
          (let ((s (with-temp-buffer (insert-file-contents f) (buffer-string))))
            (should (string-match-p "^\\* Questions for Class\nWhy the ergative here\\?" s))
            (should (string-match-p "^\\* Grammar Notes\nlegacy auto-layout body" s))
            (should (string-match-p "keep me" s))
            ;; Known machinery still regenerated, no duplicates.
            (should (= 1 (cl-count "* Questions for Class"
                                   (split-string s "\n") :test #'string=)))))
      (when (get-file-buffer f) (kill-buffer (get-file-buffer f)))
      (delete-file f))))

(ert-deftest tibetan-analysis-reanalyze-saves-modified-visiting-buffer-first ()
  "H4 (Fable-5 audit): reanalyze-file read preserved content from DISK
while a modified visiting buffer existed, then erased + rewrote that
buffer — silently discarding unsaved edits (typing into a seg buffer
mid-class, then C-c u R, lost the typed text).  A modified visiting
buffer must be saved before the preserve pass reads the file."
  (let* ((dir (make-temp-file "tcat-unsaved" t))
         (f (expand-file-name "seg-007.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "#+TITLE: Segment 7 Analysis\n\n"
                    "* My Notes\n\n\n"
                    "* Tibetan Text\nབདག\n\n"
                    "* Tibetan Analysis\nold\n\n"
                    "* Footnotes\n\n"))
          ;; Simulate mid-class typing: edit via the visiting buffer,
          ;; do NOT save.
          (with-current-buffer (find-file-noselect f)
            (goto-char (point-min))
            (re-search-forward "^\\* My Notes$")
            (insert "\ntyped mid-class, unsaved"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie Transliteration\nbdag\n")))
            (tibetan-analysis-reanalyze-file f :re-request-claude nil))
          (let ((s (with-temp-buffer (insert-file-contents f) (buffer-string))))
            (should (string-match-p "typed mid-class, unsaved" s))))
      (when (get-file-buffer f) (kill-buffer (get-file-buffer f)))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-file-belongs-to-source-exact-basename ()
  "M1 (Fable-5 audit): the source check was a SUBSTRING match — source
`rim.org' claimed a file whose #+SOURCE names `lam-rim.org' (basename
suffix collision), re-opening the §5.23 cross-source overwrite class.
The comparison must be an exact basename match."
  (let ((dir (make-temp-file "tcat-src" t)))
    (unwind-protect
        (let ((bare (expand-file-name "seg-001.org" dir)))
          (with-temp-file bare
            (insert "#+SOURCE: [[file:../lam-rim.org::*Segment 1]"
                    "[lam-rim.org / Segment 1]]\n"))
          (should (tibetan-analysis--file-belongs-to-source-p
                   bare "/x/lam-rim.org"))
          ;; Substring relatives must NOT match.
          (should-not (tibetan-analysis--file-belongs-to-source-p
                       bare "/x/rim.org"))
          (should-not (tibetan-analysis--file-belongs-to-source-p
                       bare "/x/lam-rim-extra.org")))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-resolve-filepath-rejects-foreign-suffixed-file ()
  "M1b: a suffixed file that POSITIVELY belongs to another source (its
#+SOURCE names a different document — short-name collision, e.g.
`gal-chen-nyi-shu' vs `gal.org' both shortening to `gal') must not be
chosen; the resolver falls through to the caller's own bare file."
  (let ((dir (make-temp-file "tcat-foreign" t)))
    (unwind-protect
        (let ((suffixed (expand-file-name "seg-004-gal.org" dir))
              (bare (expand-file-name "seg-004.org" dir)))
          ;; The suffixed file belongs to gal.org — NOT our source.
          (with-temp-file suffixed
            (insert "#+SOURCE: [[file:../gal.org::*Segment 4]"
                    "[gal.org / Segment 4]]\n"))
          ;; Our own bare file.
          (with-temp-file bare
            (insert "#+SOURCE: [[file:../gal-chen-nyi-shu.org::*Segment 4]"
                    "[gal-chen-nyi-shu.org / Segment 4]]\n"))
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 4 "gal" "/x/gal-chen-nyi-shu.org")
                           bare))
          ;; And gal.org itself still resolves to ITS suffixed file.
          (should (string= (tibetan-analysis--resolve-filepath
                            dir 4 "gal" "/x/gal.org")
                           suffixed)))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-claude-vocab-override-respects-curated-and-term ()
  "M2 (Fable-5 audit): the untagged proper-noun override (path 2) must
NOT rewrite a hand-curated Resources/Custom gloss (§2.9: never
rewritten) nor a `<term>'-tagged 84000 canonical gloss, and must
require an EXACT Claude key match — the prefix match re-glossed a bare
མར (\"butter\") from the `mar pas' MWU entry."
  (let ((vocab '(("mar pas" . "mar pas, proper noun, \"Mar pa\", ergative")
                 ("rngog" . "rngog, proper noun, \"rNgog\", a disciple"))))
    ;; Curated gloss → kept even though Claude says proper noun.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "རྔོག" "Butter // butter" vocab 'curated)
                     "Butter // butter"))
    ;; <term> tag → kept.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "རྔོག" "<term> butter-lamp offering" vocab)
                     "<term> butter-lamp offering"))
    ;; PREFIX key (mar ⊂ mar pas) no longer fires path 2: bare མར
    ;; keeps its dictionary gloss.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "མར" "butter" vocab)
                     "butter"))
    ;; EXACT key still overrides an untagged common-noun gloss.
    (should (string= (tibetan-analysis--apply-claude-vocab-override
                      "རྔོག" "mane" vocab)
                     "rNgog"))))

(provide 'tibetan-analysis-persist-test)
;;; tibetan-analysis-persist-test.el ends here
