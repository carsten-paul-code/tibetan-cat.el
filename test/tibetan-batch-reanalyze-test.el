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
  Tibetan Text → My Notes → Working Translation → Auto-Analysis → Footnotes.
Legacy files (where user sections come after Auto-Analysis) get
reshaped on the next re-analysis.  Idempotent: running reanalysis
twice does not change the order."
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
          ;; After reanalysis, order must be canonical.
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((s (buffer-string))
                   (tib (tibetan-batch-test--section-position s "Tibetan Text"))
                   (notes (tibetan-batch-test--section-position s "My Notes"))
                   (wt   (tibetan-batch-test--section-position s "Working Translation"))
                   (auto (tibetan-batch-test--section-position s "Auto-Analysis"))
                   (foot (tibetan-batch-test--section-position s "Footnotes")))
              (should (and tib notes wt auto foot))
              (should (< tib notes))
              (should (< notes wt))
              (should (< wt auto))
              (should (< auto foot))
              ;; User content survived the reshape
              (should (string-match-p "Important class note" s))
              (should (string-match-p "Working drop" s))
              (should (string-match-p "Footnote alpha" s))
              ;; Auto-Analysis content was regenerated
              (should (string-match-p "STUB RESHAPE" s))))
          ;; Idempotency — re-running leaves the same order.
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (tibetan-batch-test--stub-generate "RESHAPE2")))
            (tibetan-analysis-reanalyze-file file))
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((s (buffer-string))
                   (notes (tibetan-batch-test--section-position s "My Notes"))
                   (auto (tibetan-batch-test--section-position s "Auto-Analysis"))
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
canonical order (user sections ABOVE Auto-Analysis, Footnotes last)."
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
                   (auto (tibetan-batch-test--section-position s "Auto-Analysis"))
                   (foot (tibetan-batch-test--section-position s "Footnotes")))
              (should (and notes wt auto foot))
              (should (< notes wt))
              (should (< wt auto))
              (should (< auto foot)))))
      (when (file-exists-p tmp) (delete-directory tmp t)))))

(provide 'tibetan-batch-reanalyze-test)
;;; tibetan-batch-reanalyze-test.el ends here
