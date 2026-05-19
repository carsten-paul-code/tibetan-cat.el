;;; tibetan-batch-reanalyze-test.el --- Batch reanalysis tests -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for `tibetan-analysis-reanalyze-file' /
;; `tibetan-analysis-batch-reanalyze' in
;; `persist/tibetan-analysis-persist.el'.
;;
;; Focus: user sections (My Notes, Working Translation, Footnotes) and
;; an existing `*** Claude' translation survive a reanalysis round-trip.
;; We stub `tibetan-analysis-generate-content' so tests do not require
;; the full vocabulary / glossary stack.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir)))

(require 'tibetan-analysis-persist)

;; ----------------------------------------------------------------------------
;; Fixture helpers
;; ----------------------------------------------------------------------------

(defun tibetan-batch-test--write-file (path body)
  (with-temp-file path
    (insert body)))

(defun tibetan-batch-test--stub-generate (body-tag)
  "Return a lambda usable as `tibetan-analysis-generate-content' stub.
BODY-TAG is embedded so tests can assert regeneration happened."
  (lambda (_tibetan-text &optional _seg-id _source-text)
    (format ":PROPERTIES:\n:GENERATED: t\n:END:\n\n** Word List\n- STUB %s\n\n** Provided Translations\n*** DharmaMitra\n[stub]\n\n*** CAT Gloss\n[stub]\n\n*** Claude\n[Requesting translation...]\n\n*** Reference Translations\n[none]\n"
            body-tag)))

(cl-defun tibetan-batch-test--sample-file (path &key claude notes translation footnotes)
  "Write a realistic analysis file at PATH with optional user content."
  (tibetan-batch-test--write-file
   path
   (concat
    "#+TITLE: Segment 7 Analysis\n"
    "#+STARTUP: showall\n"
    "#+TIBETAN_HASH: deadbeef\n"
    "#+ANALYSIS_VERSION: 1.0\n"
    "#+CREATED: 2026-01-01\n"
    "#+LAST_ANALYZED: 2026-01-01\n\n"
    "* Tibetan Text\n"
    "བདག་གིས་ལས་བྱས།\n\n"
    "* Auto-Analysis\n"
    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
    "** Word List\n- OLD entries\n\n"
    "** Provided Translations\n"
    "*** DharmaMitra\n[old]\n\n"
    "*** CAT Gloss\n[old]\n\n"
    "*** Claude\n"
    (or claude "[Requesting translation...]")
    "\n\n"
    "*** Reference Translations\n[none]\n\n"
    "* My Notes\n"
    (or notes "")
    "\n\n"
    "* Working Translation\n"
    (or translation "")
    "\n\n"
    "* Footnotes\n"
    (or footnotes "")
    "\n")))

;; ----------------------------------------------------------------------------
;; Single-file reanalysis
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-batch-reanalyze-preserves-notes-and-translation ()
  "User's notes and working translation survive a reanalysis round-trip."
  (let* ((tmp (make-temp-file "tibetan-reanal-" t))
         (file (expand-file-name "seg-007.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--sample-file
           file
           :notes "This is a crucial context note."
           :translation "By me the work was done.")
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "REGEN-A")))
            (let ((r (tibetan-analysis-reanalyze-file file)))
              (should (plist-get r :ok))
              (should (equal (plist-get r :seg-id) 7))))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((content (buffer-string)))
              ;; New auto-analysis markers present
              (should (string-match-p "STUB REGEN-A" content))
              ;; User sections preserved
              (should (string-match-p
                       "crucial context note" content))
              (should (string-match-p
                       "By me the work was done" content)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-batch-reanalyze-preserves-claude-translation ()
  "An existing `*** Claude' translation is restored after regeneration."
  (let* ((tmp (make-temp-file "tibetan-reanal-" t))
         (file (expand-file-name "seg-007.org" tmp))
         (claude-body "By me, the task was accomplished — Claude renders."))
    (unwind-protect
        (progn
          (tibetan-batch-test--sample-file file :claude claude-body)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "REGEN-B")))
            (let ((r (tibetan-analysis-reanalyze-file file)))
              (should (plist-get r :ok))
              (should (plist-get r :claude-preserved))))
          (with-temp-buffer
            (insert-file-contents file)
            (let ((content (buffer-string)))
              (should (string-match-p "STUB REGEN-B" content))
              (should (string-match-p (regexp-quote claude-body) content))
              ;; The placeholder must be gone
              (should-not
               (string-match-p "\\[Requesting translation\\.\\.\\.\\].*\\[Requesting"
                               content)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-batch-reanalyze-placeholder-not-persisted ()
  "If the existing Claude body is just the placeholder, it is NOT
preserved as a real translation — the regenerated placeholder stays."
  (let* ((tmp (make-temp-file "tibetan-reanal-" t))
         (file (expand-file-name "seg-007.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--sample-file
           file :claude "[Requesting translation...]")
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "REGEN-C")))
            (let ((r (tibetan-analysis-reanalyze-file file)))
              (should (plist-get r :ok))
              (should-not (plist-get r :claude-preserved)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-batch-reanalyze-dry-run-does-not-touch-file ()
  "Dry run reports what would happen without modifying the file."
  (let* ((tmp (make-temp-file "tibetan-reanal-" t))
         (file (expand-file-name "seg-007.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--sample-file file)
          (let* ((mtime-before (file-attribute-modification-time
                                (file-attributes file)))
                 (r (tibetan-analysis-reanalyze-file file :dry-run t))
                 (mtime-after  (file-attribute-modification-time
                                (file-attributes file))))
            (should (plist-get r :ok))
            (should (plist-get r :dry-run))
            (should (equal mtime-before mtime-after))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-batch-reanalyze-missing-seg-id-reports-error ()
  "Files whose name does not carry a seg id return ok=nil with an error."
  (let* ((tmp (make-temp-file "tibetan-reanal-" t))
         (file (expand-file-name "notes.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--write-file
           file "* Tibetan Text\nfoo\n* Auto-Analysis\nbar\n")
          (let ((r (tibetan-analysis-reanalyze-file file)))
            (should-not (plist-get r :ok))
            (should (plist-get r :error))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

;; ----------------------------------------------------------------------------
;; Folder-level batch driver
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-batch-reanalyze-folder-iterates-all ()
  "`tibetan-analysis-batch-reanalyze' processes every seg-NNN*.org file
and returns a summary plist."
  (let* ((tmp (make-temp-file "tibetan-batch-" t))
         (files (list
                 (expand-file-name "seg-001.org" tmp)
                 (expand-file-name "seg-002-padma.org" tmp)
                 (expand-file-name "seg-003.org" tmp)
                 (expand-file-name "unrelated.org" tmp))))
    (unwind-protect
        (progn
          (dolist (f (butlast files))
            (tibetan-batch-test--sample-file f))
          ;; An unrelated file should be ignored by the folder scanner.
          (tibetan-batch-test--write-file (car (last files))
                                          "* Not an analysis file\n")
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "BATCH")))
            (let ((summary (tibetan-analysis-batch-reanalyze
                            :folder tmp :source-file nil)))
              (should (equal (plist-get summary :total) 3))
              (should (equal (plist-get summary :ok) 3))
              (should (equal (plist-get summary :failed) 0))
              ;; Results in seg-id order (1, 2, 3)
              (should (equal (mapcar (lambda (r) (plist-get r :seg-id))
                                     (plist-get summary :results))
                             '(1 2 3))))))
      (dolist (f files) (when (file-exists-p f) (delete-file f)))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

;; ----------------------------------------------------------------------------
;; Pass 6a: canonical layout — My Notes + Working Translation ABOVE
;; Auto-Analysis; Footnotes stays at the bottom.  Legacy files with the
;; reverse ordering are reshaped on re-analysis.
;; ----------------------------------------------------------------------------

(defun tibetan-batch-test--section-position (content section-name)
  "Return character position of `* SECTION-NAME' in CONTENT, or nil."
  (let ((pattern (format "^\\* %s$" (regexp-quote section-name))))
    (when (string-match pattern content)
      (match-beginning 0))))

(ert-deftest tibetan-reanalyze-reshapes-into-canonical-layout ()
  "After reanalysis, section order is:
  Tibetan Text → My Notes → Working Translation → Tibetan Analysis → Footnotes.
Legacy files (where user sections come after the Tibetan Analysis
parent — old name `* Auto-Analysis') get reshaped on the next
re-analysis.  Idempotent: running reanalysis twice does not change
the order.

Phase 1.2 of layout-revision §5.18 (2026-05-04): the parent name
is now `Tibetan Analysis'; the fixture sample-file generator still
emits the legacy `* Auto-Analysis' so the migration path is
exercised end-to-end (legacy → canonical)."
  (let* ((tmp (make-temp-file "tibetan-layout-" t))
         (file (expand-file-name "seg-012.org" tmp)))
    (unwind-protect
        (progn
          ;; Legacy-shaped sample — My Notes / Working Translation /
          ;; Footnotes sit BELOW Auto-Analysis (the old default).
          (tibetan-batch-test--sample-file
           file
           :notes "Important class note"
           :translation "Working drop"
           :footnotes "Footnote alpha")
          ;; Sanity: legacy shape has Auto-Analysis BEFORE My Notes.
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((s (buffer-string))
                   (auto (tibetan-batch-test--section-position s "Auto-Analysis"))
                   (notes (tibetan-batch-test--section-position s "My Notes")))
              (should (and auto notes))
              (should (< auto notes))))
          ;; Run the reanalysis (stub generate-content)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "RESHAPE")))
            (let ((r (tibetan-analysis-reanalyze-file file)))
              (should (plist-get r :ok))))
          ;; After reanalysis, order must be canonical.  Phase 2.1
          ;; of layout-revision §5.18 (2026-05-04): user-content
          ;; sections are emitted ABOVE `* Tibetan Text' (Sanskrit-
          ;; first reading order), not below it.
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((s (buffer-string))
                   (notes (tibetan-batch-test--section-position s "My Notes"))
                   (wt   (tibetan-batch-test--section-position s "Working Translation"))
                   (tib (tibetan-batch-test--section-position s "Tibetan Text"))
                   (auto (tibetan-batch-test--section-position s "Tibetan Analysis"))
                   (foot (tibetan-batch-test--section-position s "Footnotes")))
              (should (and tib notes wt auto foot))
              (should (< notes wt))
              (should (< wt tib))
              (should (< tib auto))
              (should (< auto foot))
              ;; User content survived the reshape
              (should (string-match-p "Important class note" s))
              (should (string-match-p "Working drop" s))
              (should (string-match-p "Footnote alpha" s))
              ;; Tibetan Analysis content was regenerated
              (should (string-match-p "STUB RESHAPE" s))
              ;; Migration path: old `* Auto-Analysis' heading is gone.
              (should-not (string-match-p "^\\* Auto-Analysis$" s))))
          ;; Idempotency — re-running leaves the same order.
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "RESHAPE2")))
            (tibetan-analysis-reanalyze-file file))
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((s (buffer-string))
                   (notes (tibetan-batch-test--section-position s "My Notes"))
                   (auto (tibetan-batch-test--section-position s "Tibetan Analysis"))
                   (foot (tibetan-batch-test--section-position s "Footnotes")))
              (should (< notes auto))
              (should (< auto foot))
              ;; Still preserves user content through the second round
              (should (string-match-p "Important class note" s))
              (should (string-match-p "Footnote alpha" s)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-reanalyze-grammar-picks-up-claude-particles ()
  "Pass 6c round-trip: a fixture file carrying a populated
`*** Claude Particles' body + `** Claude Grammar' prose must
produce, after `reanalyze-file', a `** Grammar' section that
includes the per-occurrence Portfolio sub-function headings
(`§ 1.1.1 Genitive Attribute — attributive') and the Portfolio
description snippet.

Stubs both `tibetan-analysis-generate-content' (to emit the
expected merged-Grammar scaffold so the reanalyse path exercises
the Claude-Particles threading without needing the full
vocabulary/glossary stack) and the Portfolio snippet lookup
helper so the test doesn't depend on the user's Portfolio file."
  (let* ((tmp (make-temp-file "tibetan-pass6c-" t))
         (file (expand-file-name "seg-042.org" tmp)))
    (unwind-protect
        (progn
          ;; Fixture: analysis file with populated Claude Particles.
          (tibetan-batch-test--write-file
           file
           (concat
            "#+TITLE: Segment 42 Analysis\n"
            "#+TIBETAN_HASH: cafe\n"
            "#+ANALYSIS_VERSION: 1.0\n\n"
            "* Tibetan Text\n"
            "མཐུའི་མན་ངག\n\n"
            "* My Notes\nCarsten's note.\n\n"
            "* Working Translation\n\n"
            "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
            "** Wylie Transliteration\nmthu'i man ngag\n\n"
            "** Claude Translation\nInstructions of/on magical power.\n\n"
            "** Claude Grammar\nA bare genitive compound.\n\n"
            "** Provided Translations\n"
            "*** DharmaMitra\n[stub]\n\n"
            "*** Claude Vocabulary\n(empty)\n\n"
            "*** Claude Particles\n"
            "mthu'i, 'i, 1.1.1, attributive\n\n"
            "* Footnotes\n"))
          ;; Stubs.
          (cl-letf*
              (((symbol-function 'tibetan-analysis-generate-content)
                (lambda (&rest _args)
                  ;; Emit a mini Grammar section using the threaded
                  ;; dynamic var — this is what the real renderer
                  ;; does via `--render-grammar-section'.
                  (let* ((particles tibetan-analysis--claude-particles-for-render)
                         (tuple (car particles))
                         (sub-id (and tuple (plist-get tuple :sub-id)))
                         (label  (and tuple (plist-get tuple :label))))
                    (concat
                     "** Grammar\n*** Particles in This Segment\n"
                     (if (and sub-id label)
                         (format "- མཐུའི [mthu'i] · འི ['i] · GEN\n  § %s Genitive Attribute — %s\n    Attributive genitive: X-'i Y = 'Y of X'.\n"
                                 sub-id label)
                       "- མཐུའི [mthu'i] · GEN\n")
                     "\n"))))
               ;; Portfolio lookup returns a deterministic snippet.
               ((symbol-function 'tibetan-interlinear-portfolio-function-snippet)
                (lambda (_key _sub-id)
                  (cons "Genitive Attribute"
                        "Attributive genitive: X-'i Y = 'Y of X'."))))
            (let ((r (tibetan-analysis-reanalyze-file file)))
              (should (plist-get r :ok))
              (should (plist-get r :claude-preserved))))
          ;; Inspect the regenerated file.
          (with-temp-buffer
            (insert-file-contents file)
            (let ((s (buffer-string)))
              ;; Portfolio snippet rendered inline under the Grammar particle.
              (should (string-match-p "§ 1\\.1\\.1 Genitive Attribute" s))
              (should (string-match-p "attributive" s))
              ;; User content preserved through the round-trip.
              (should (string-match-p "Carsten's note" s))
              ;; Claude sections preserved (not regenerated to placeholder).
              (should (string-match-p "Instructions of/on magical power" s))
              (should (string-match-p "A bare genitive compound" s))
              ;; Claude Particles still present after round-trip.
              (should (string-match-p "mthu'i, 'i, 1\\.1\\.1, attributive" s)))))
      (when (file-exists-p file) (delete-file file))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-create-file-uses-canonical-layout ()
  "Fresh `tibetan-analysis-create-file' emits sections in the
canonical order (user sections ABOVE Tibetan Analysis, Footnotes
last).

Phase 1.2 of layout-revision §5.18 (2026-05-04): the auto-content
parent heading is `* Tibetan Analysis' (was `* Auto-Analysis')."
  (let* ((tmp (make-temp-file "tibetan-newfile-" t))
         (source-file (expand-file-name "source.org" tmp)))
    (unwind-protect
        (let ((default-directory tmp))
          ;; Minimal source file for `get-filepath' to resolve against.
          (with-temp-file source-file (insert "#+TITLE: T\n* Segment 1\nfoo\n"))
          ;; Patch get-filepath so the analysis path is inside our tmpdir.
          (cl-letf (((symbol-function 'tibetan-analysis-get-filepath)
                     (lambda (_seg-id &optional _source)
                       (expand-file-name "seg-001.org" tmp))))
            (tibetan-analysis-create-file
             1 "བདག་" source-file "** Wylie\nbdag /\n"))
          (with-temp-buffer
            (insert-file-contents (expand-file-name "seg-001.org" tmp))
            (let* ((s (buffer-string))
                   (notes (tibetan-batch-test--section-position s "My Notes"))
                   (wt   (tibetan-batch-test--section-position s "Working Translation"))
                   (auto (tibetan-batch-test--section-position s "Tibetan Analysis"))
                   (foot (tibetan-batch-test--section-position s "Footnotes")))
              (should (and notes wt auto foot))
              (should (< notes wt))
              (should (< wt auto))
              (should (< auto foot)))))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

;; ============================================================================
;; Phase 5 of two-language-parallel-analysis (2026-04-30):
;; reanalyse preserves all six new top-level sections without
;; re-firing Claude / DM:
;;   * Sanskrit Text
;;   * Sanskrit Analysis
;;   * Combined Analysis
;;   * DharmaMitra Translation (Tibetan)
;;   * DharmaMitra Translation (Sanskrit)
;;   * Sanskrit (DharmaMitra)
;; ============================================================================

(defun tibetan-batch-test--write-with-top-level-sections (path)
  "Write a sample analysis file containing every top-level section
that Phase 5 must preserve across reanalyse-without-refire."
  (tibetan-batch-test--write-file
   path
   (concat
    "#+TITLE: Segment 9 Analysis\n"
    "#+TIBETAN_HASH: cafebabe\n"
    "#+ANALYSIS_VERSION: 1.0\n"
    "#+CREATED: 2026-04-30\n"
    "#+LAST_ANALYZED: 2026-04-30\n\n"
    "* Tibetan Text\nbdag\n\n"
    "* My Notes\nUSER NOTE\n\n"
    "* Working Translation\nWT BODY\n\n"
    "* Sanskrit Text\n\nIAST: ahaṃ\nDevanagari: अहम्\n\n"
    "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
    "** Word List\n- old entry\n\n"
    "** Provided Translations\n*** Claude\n[old]\n\n*** Reference Translations\n[none]\n\n"
    "* Sanskrit Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
    "** Claude Translation\nSANSKRIT-TRANS-BODY\n\n"
    "** Sandhi Decomposition\nSANDHI-BODY\n\n"
    "* Combined Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
    "** Combined Translation\nCOMBINED-BODY\n\n"
    "** Divergence\nDIVERGENCE-BODY\n\n"
    "* Footnotes\nFOOTNOTE BODY\n\n"
    "* DharmaMitra Translation (Tibetan)\n:PROPERTIES:\n:LAST_TRANSLATED: 2026-04-30\n:END:\n\n"
    "DM-TIB-BODY\n\n"
    "* DharmaMitra Translation (Sanskrit)\n:PROPERTIES:\n:LAST_TRANSLATED: 2026-04-30\n:END:\n\n"
    "DM-SKT-BODY\n\n"
    "* Sanskrit (DharmaMitra)\n:PROPERTIES:\n:DM_RANK: 1\n:END:\n\n"
    "REALIGN-BODY\n")))

(ert-deftest tibetan-reanalyze-preserves-top-level-sections-without-refire ()
  "Phase 5 of two-language-parallel-analysis (2026-04-30) +
DharmaMitra Tibetan layout revision (2026-05-19):
reanalyse-without-refire (`:re-request-claude nil', the
default) preserves the five remaining top-level analysis
sections verbatim.  DharmaMitra Tibetan (formerly the sixth
top-level section) is now nested inside `* Tibetan Analysis'
as `** DharmaMitra Translation' — its body is preserved by the
migration helper."
  (let* ((tmp (make-temp-file "tibetan-toplevel-" t))
         (file (expand-file-name "seg-009.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--write-with-top-level-sections file)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "regen-stub")))
            (let ((result (tibetan-analysis-reanalyze-file file)))
              (should (plist-get result :ok))))
          (let ((s (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))
            ;; Remaining top-level sections still present.
            (should (string-match-p "^\\* Sanskrit Text$" s))
            (should (string-match-p "^\\* Sanskrit Analysis$" s))
            (should (string-match-p "^\\* Combined Analysis$" s))
            (should (string-match-p
                     "^\\* DharmaMitra Translation (Sanskrit)$" s))
            (should (string-match-p "^\\* Sanskrit (DharmaMitra)$" s))
            ;; DharmaMitra Tibetan retired from top-level (2026-05-19).
            (should-not (string-match-p
                         "^\\* DharmaMitra Translation (Tibetan)$" s))
            ;; Bodies preserved verbatim.
            (should (string-match-p "IAST: ahaṃ" s))
            (should (string-match-p "Devanagari: अहम्" s))
            (should (string-match-p "SANSKRIT-TRANS-BODY" s))
            (should (string-match-p "SANDHI-BODY" s))
            (should (string-match-p "COMBINED-BODY" s))
            (should (string-match-p "DIVERGENCE-BODY" s))
            ;; DM Tibetan body migrated to nested location.
            (should (string-match-p "DM-TIB-BODY" s))
            (should (string-match-p "DM-SKT-BODY" s))
            (should (string-match-p "REALIGN-BODY" s))
            ;; And the stub regen ran on Auto-Analysis.
            (should (string-match-p "STUB regen-stub" s))))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-reanalyze-canonical-section-order ()
  "Reanalyse rebuild emits TOP-LEVEL sections in canonical order:
  My Notes → Working Translation → Sanskrit Text → Sanskrit
  Analysis → Tibetan Text → Tibetan Analysis → Combined Analysis
  → Footnotes → DharmaMitra Translation (Sanskrit) →
  Sanskrit (DharmaMitra).

Phase 1.2 of layout-revision §5.18 (2026-05-04): `Auto-Analysis'
parent heading renamed to `Tibetan Analysis'.  Phase 2.1
reordered to Sanskrit-first.

DharmaMitra Tibetan layout revision (2026-05-19):  the legacy
top-level `* DharmaMitra Translation (Tibetan)' section is
RETIRED.  The body now lives at level-2 `** DharmaMitra
Translation' inside `* Tibetan Analysis' (peer of `**
Translation'), so the AI translations sit side by side for
class comparison.  This test no longer asserts the top-level
heading exists."
  (let* ((tmp (make-temp-file "tibetan-toplevel-order-" t))
         (file (expand-file-name "seg-009.org" tmp)))
    (unwind-protect
        (progn
          (tibetan-batch-test--write-with-top-level-sections file)
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "order")))
            (tibetan-analysis-reanalyze-file file))
          (let* ((s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                 (positions
                  (mapcar (lambda (n)
                            (cons n (tibetan-batch-test--section-position s n)))
                          '("My Notes"
                            "Working Translation"
                            "Sanskrit Text"
                            "Sanskrit Analysis"
                            "Tibetan Text"
                            "Tibetan Analysis"
                            "Combined Analysis"
                            "Footnotes"
                            "DharmaMitra Translation (Sanskrit)"
                            "Sanskrit (DharmaMitra)"))))
            ;; Each section is present.
            (dolist (p positions)
              (should (cdr p)))
            ;; Strictly ascending positions.
            (let ((prev -1))
              (dolist (p positions)
                (should (> (cdr p) prev))
                (setq prev (cdr p))))
            ;; The retired top-level DM Tibetan section must NOT be
            ;; re-emitted by regenerate.
            (should-not (string-match-p
                         "^\\* DharmaMitra Translation (Tibetan)$" s))))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

;; ============================================================================
;; Phase 5 dispatcher: --fire-parallel-mode-claude-calls
;; ============================================================================

(ert-deftest tibetan-fire-parallel-mode-claude-calls-no-op-when-non-parallel ()
  "When the source file is non-parallel-mode (no
`#+SOURCE_MODE: parallel-sanskrit'), the dispatcher returns
nil — no Sanskrit / Combined call fired."
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls))
  (let* ((tmp (make-temp-file "tibetan-fire-" t))
         (src (expand-file-name "doc.org" tmp))
         (ana (expand-file-name "seg-001.org" tmp)))
    (unwind-protect
        (progn
          (with-temp-file src (insert "#+TITLE: T\n"))
          (with-temp-file ana (insert "* Tibetan Text\nbdag\n"))
          ;; Walker returns nil for non-parallel source → dispatcher
          ;; returns nil without firing.
          (should-not
           (tibetan-analysis--fire-parallel-mode-claude-calls
            "བདག" src ana)))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-fire-parallel-mode-claude-calls-no-op-when-args-missing ()
  "When any required arg is nil, the dispatcher returns nil cleanly
— no error and no Claude call attempt."
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls))
  (should-not
   (tibetan-analysis--fire-parallel-mode-claude-calls nil nil nil))
  (should-not
   (tibetan-analysis--fire-parallel-mode-claude-calls "བདག" nil nil))
  (should-not
   (tibetan-analysis--fire-parallel-mode-claude-calls
    "བདག" "/some/source.org" nil)))

(ert-deftest tibetan-analysis-fire-parallel-uses-translation-heading-for-tibetan-readback ()
  "Phase 1.5 of layout-revision §5.18 (2026-05-04):  the dispatcher
reads the previously-stored Tibetan-side translation body via the
new `** Translation' heading (Phase 1.3 rename) when chaining off
the Sanskrit response into the Combined call.

Fixture: an analysis file where `** Translation' (NEW heading)
carries the Tibetan-side translation.  Stub Sanskrit's
`--request-translation' to invoke its callback with a known plist
\(`(:translation \"S-trans\")').  Stub Combined's
`--request-synthesis' to capture its arguments.  Assert the
captured `tib-trans' arg is the body that lived under
`** Translation'."
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
  (let* ((tmp (make-temp-file "tibetan-fire-trans-" t))
         (ana (expand-file-name "seg-001.org" tmp))
         captured)
    (unwind-protect
        (progn
          (with-temp-file ana
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Tibetan Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Translation\n"
                    "TIB-TRANS-NEW-HEADING\n\n"
                    "** Wylie Transliteration\nbdag /\n\n"))
          (cl-letf
              (((symbol-function 'tibetan-analysis-sanskrit--request-translation)
                (lambda (_skt _src _ana on-done)
                  (funcall on-done '(:translation "S-trans"))))
               ((symbol-function 'tibetan-analysis-combined--request-synthesis)
                (lambda (tib _skt tib-trans skt-trans &rest _)
                  (setq captured (list :tib tib :tib-trans tib-trans
                                       :skt-trans skt-trans))
                  t)))
            (tibetan-analysis--fire-parallel-claude-with-plist
             "བདག"
             '(:iast "ahaṃ" :devanagari nil :script-source iast-line)
             "/dev/null/source.org" ana))
          (should captured)
          (should (equal (plist-get captured :tib-trans)
                         "TIB-TRANS-NEW-HEADING"))
          (should (equal (plist-get captured :skt-trans) "S-trans")))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(ert-deftest tibetan-analysis-fire-parallel-falls-back-to-claude-translation-on-legacy-files ()
  "Phase 1.5 migration:  if the analysis file still carries the
LEGACY `** Claude Translation' heading (level 2, pre-rename),
the dispatcher falls back to it for the Tibetan-side readback."
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
  (let* ((tmp (make-temp-file "tibetan-fire-fallback-" t))
         (ana (expand-file-name "seg-001.org" tmp))
         captured)
    (unwind-protect
        (progn
          (with-temp-file ana
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Auto-Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Claude Translation\n"
                    "TIB-TRANS-LEGACY\n\n"
                    "** Wylie Transliteration\nbdag /\n\n"))
          (cl-letf
              (((symbol-function 'tibetan-analysis-sanskrit--request-translation)
                (lambda (_skt _src _ana on-done)
                  (funcall on-done '(:translation "S-trans"))))
               ((symbol-function 'tibetan-analysis-combined--request-synthesis)
                (lambda (_tib _skt tib-trans _skt-trans &rest _)
                  (setq captured tib-trans)
                  t)))
            (tibetan-analysis--fire-parallel-claude-with-plist
             "བདག"
             '(:iast "ahaṃ" :devanagari nil :script-source iast-line)
             "/dev/null/source.org" ana))
          (should (equal captured "TIB-TRANS-LEGACY")))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

;; ============================================================================
;; Phase 5 dispatcher: wired into the INTERACTIVE entry points
;; ============================================================================
;;
;; §5.17 Phase 5 wires the Sanskrit + Combined dispatcher into the headless
;; reanalyse-file + auto-analyze-document + sentence batch paths.  But the
;; two interactive entry points — `tibetan--reanalyze-segment-impl' (bound
;; to `C-c u R') and `tibetan--open-segment-analysis-impl' (bound to
;; `C-c u A') — were missed.  Symptom (live test 2026-05-02 on
;; gotrapatala.org seg 9): hitting `C-c u R' with re-aligned Sanskrit in
;; the source produced a refreshed Tibetan analysis + DM Tibetan section,
;; but no `* Sanskrit Text', `* Sanskrit Analysis', or
;; `* Combined Analysis'.  Walker, dispatcher, and Claude pipeline all
;; functioning — the call site simply wasn't wired.
;;
;; Regression-test approach:  walk the symbol-function form of each impl
;; defun looking for the dispatcher symbol.  An interpreted function (as
;; loaded from .el during test runs) preserves the body as a walkable
;; cons-tree; a missing call site would not contain the symbol, and the
;; test would fail.

(defun tibetan-batch-reanalyze-test--fn-references-symbol-p (fn-symbol target-symbol)
  "Return non-nil iff FN-SYMBOL's source body references TARGET-SYMBOL.
Uses the printed form of the function value as the search target —
works for both `interpreted-function' record bodies (the format
emacs 30+ uses for lexical-binding defuns) and the plain cons-tree
`lambda' bodies older emacs versions produce.  Surrounds
TARGET-SYMBOL with non-symbol-character delimiters so a substring
match (e.g. `foo' inside `foo-bar') doesn't false-positive."
  (let ((printed (format "%S" (symbol-function fn-symbol)))
        (target (symbol-name target-symbol)))
    (string-match-p
     (concat "[^[:alnum:]_-]"
             (regexp-quote target)
             "[^[:alnum:]_-]")
     printed)))

(ert-deftest tibetan-reanalyze-segment-impl-wires-parallel-dispatcher ()
  "`tibetan--reanalyze-segment-impl' (the `C-c u R' handler) must
invoke `tibetan-analysis--fire-parallel-mode-claude-calls' so the
Sanskrit and Combined analyses fire when in parallel-mode.  Without
this wire, the §5.17 dispatcher fires only via headless batch +
auto-analyze + sentence paths, never via interactive segment
reanalyse — the most common everyday entry point."
  (skip-unless (fboundp 'tibetan--reanalyze-segment-impl))
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls))
  (should (tibetan-batch-reanalyze-test--fn-references-symbol-p
           'tibetan--reanalyze-segment-impl
           'tibetan-analysis--fire-parallel-mode-claude-calls)))

(ert-deftest tibetan-open-segment-analysis-impl-wires-parallel-dispatcher ()
  "`tibetan--open-segment-analysis-impl' (the `C-c u A' handler) must
also invoke `tibetan-analysis--fire-parallel-mode-claude-calls' so a
fresh seg-NNN.org file gets its Sanskrit + Combined analyses on
first creation.  Without this wire, new parallel-mode files start
with only the Tibetan side filled in even when source has aligned
Sanskrit."
  (skip-unless (fboundp 'tibetan--open-segment-analysis-impl))
  (skip-unless (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls))
  (should (tibetan-batch-reanalyze-test--fn-references-symbol-p
           'tibetan--open-segment-analysis-impl
           'tibetan-analysis--fire-parallel-mode-claude-calls)))

(ert-deftest tibetan-dharmamitra-needs-fire-on-open-p-true-when-only-tibetan-populated ()
  "Bug fix 2026-05-04: the existing-file open path's DM auto-fire
gate (`tibetan--open-segment-analysis-impl' lines 3857–3866)
checked ONLY the Tibetan-side DM section.  When a file has the
Tibetan DM populated (from yesterday's run) but lacks the
Sanskrit DM section (DM Sanskrit fire missed for any reason),
the gate returned nil and `fire-for-segment' never ran — leaving
`* DharmaMitra Translation (Sanskrit)' permanently absent until
the user ran an explicit `C-c u R'.

Live observation: gotrapaṭala seg 9 after the layout-revision
work — `* Sanskrit Text' present, Sanskrit Analysis present,
Combined Analysis present, but `* DharmaMitra Translation
\(Sanskrit)' absent because of this gating bug.

The fix:  introduce a predicate `--needs-fire-on-open-p' that
returns t when EITHER Tibetan OR Sanskrit DM section is missing.
The umbrella `fire-for-segment' does internal per-language
gating, so it correctly skips the populated side and fires only
the missing one when called."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-fire-on-open-p))
  (let* ((dir (make-temp-file "ttest-dm-gate-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          ;; Fixture: Tibetan DM populated, Sanskrit DM absent.
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Footnotes\n\n"
                    "* DharmaMitra Translation (Tibetan)\n"
                    "Real Tibetan translation.\n\n"))
          ;; Sanity:  Tibetan-only check returns nil (already populated).
          (should-not (tibetan-dharmamitra-translation-needs-request-p
                       file "Tibetan"))
          ;; And Sanskrit-only check returns t (missing).
          (should (tibetan-dharmamitra-translation-needs-request-p
                   file "Sanskrit"))
          ;; The new on-open predicate triggers when EITHER is missing.
          (should (tibetan-dharmamitra-translation-needs-fire-on-open-p file)))
      (delete-directory dir t))))

(ert-deftest tibetan-dharmamitra-needs-fire-on-open-p-false-when-both-populated ()
  "When BOTH Tibetan and Sanskrit DM sections are populated, the
on-open predicate returns nil — re-running `C-c u A' on a
fully-DM'd file does not re-fire the API."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-fire-on-open-p))
  (let* ((dir (make-temp-file "ttest-dm-gate-2-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Footnotes\n\n"
                    "* DharmaMitra Translation (Tibetan)\n"
                    "Tib body.\n\n"
                    "* DharmaMitra Translation (Sanskrit)\n"
                    "Skt body.\n\n"))
          (should-not
           (tibetan-dharmamitra-translation-needs-fire-on-open-p file)))
      (delete-directory dir t))))

(ert-deftest tibetan-dharmamitra-needs-fire-on-open-p-true-when-both-missing ()
  "Both sections missing → predicate returns t."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-needs-fire-on-open-p))
  (let* ((dir (make-temp-file "ttest-dm-gate-3-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n* Footnotes\n\n"))
          (should
           (tibetan-dharmamitra-translation-needs-fire-on-open-p file)))
      (delete-directory dir t))))

;; ============================================================================
;; Regression: reanalyze-file falls back to #+SOURCE: header when
;; :source-file isn't passed
;; ============================================================================
;;
;; Live test 2026-05-03 on gotrapaṭala.org seg 9 surfaced an
;; auto-regen interaction:  when Claude's response contains
;; `## Particles', `--insert-claude-sections' fires
;; `(tibetan-analysis-reanalyze-file analysis-file
;;     :re-request-claude nil)' to refresh the Grammar section with
;; the new Bialek Portfolio snippets.  This async callback runs
;; AFTER the initial regenerate-auto from `C-c u R' has already
;; emitted `* Sanskrit Text' correctly.  But the auto-regen call
;; passes no `:source-file', so reanalyze-file's binding of
;; `tibetan-analysis--sanskrit-text-for-render' calls
;; `plist-for-segment-id' with `source-file=nil' → returns nil →
;; the regenerate erases the `* Sanskrit Text' section that was
;; correctly emitted minutes earlier.
;;
;; The sentence-level analogue, `tibetan-sentence-reanalyze-file',
;; already falls back to `tibetan-sentence--source-file-from-analysis'
;; when `source-file' isn't given.  This test asserts the segment-
;; level path does the same:  reanalysing a parallel-mode file
;; without `:source-file' should still preserve `* Sanskrit Text'
;; (the function should resolve the source from the analysis
;; file's own `#+SOURCE:' header).

(ert-deftest tibetan-reanalyze-file-resolves-source-from-header-when-not-given ()
  "When `tibetan-analysis-reanalyze-file' is called without
`:source-file', it must fall back to resolving the source path
from the analysis file's own `#+SOURCE:' header so parallel-mode
features (the `* Sanskrit Text' renderer in particular) still
fire on the auto-regen path used by Claude `## Particles' arrival."
  (skip-unless (fboundp 'tibetan-analysis-reanalyze-file))
  (skip-unless (fboundp 'tibetan-analysis--source-file-from-analysis))
  (let* ((tmp (make-temp-file "tibetan-reanalyze-resolve-" t))
         (src (expand-file-name "doc.org" tmp))
         (analysis (expand-file-name "seg-001.org" tmp)))
    (unwind-protect
        (progn
          ;; Source: parallel-mode + a `**** Segment 1' with non-
          ;; placeholder Sanskrit sibling.
          (with-temp-file src
            (insert "#+TITLE: Doc\n"
                    "#+SOURCE_MODE: parallel-sanskrit\n\n"
                    "* Tibetan Text\n\n"
                    "*** Sentence 1\n"
                    "**** Segment 1\n"
                    "བདག\n\n"
                    "**** Sanskrit\n"
                    "ahaṃ\n\n"))
          ;; Analysis file with `#+SOURCE:' link pointing back.
          (with-temp-file analysis
            (insert "#+TITLE: Segment 1 Analysis\n"
                    "#+SOURCE: [[file:doc.org::*Segment 1][doc.org / Segment 1]]\n"
                    "#+TIBETAN_HASH: aaa\n"
                    "#+ANALYSIS_VERSION: 1.0\n"
                    "#+CREATED: 2026-05-03\n"
                    "#+LAST_ANALYZED: 2026-05-03\n\n"
                    "* Tibetan Text\nབདག\n\n"
                    "* My Notes\n\n\n"
                    "* Working Translation\n\n\n"
                    "* Auto-Analysis\n:PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Wylie Transliteration\nbdag\n\n"
                    "* Footnotes\n\n"))
          ;; Stub `generate-content' to avoid pulling the full vocab
          ;; stack — we only care about whether `* Sanskrit Text'
          ;; lands.
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie Transliteration\nbdag\n\n")))
            (tibetan-analysis-reanalyze-file analysis
                                              :re-request-claude nil))
          ;; The fix:  with no `:source-file' passed, reanalyze-file
          ;; should resolve it from the `#+SOURCE:' header and fire
          ;; the Sanskrit Text renderer.
          (with-temp-buffer
            (insert-file-contents analysis)
            (goto-char (point-min))
            (should (re-search-forward "^\\* Sanskrit Text$" nil t))
            (goto-char (point-min))
            (should (re-search-forward "^IAST: ahaṃ" nil t))))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(provide 'tibetan-batch-reanalyze-test)
;;; tibetan-batch-reanalyze-test.el ends here
