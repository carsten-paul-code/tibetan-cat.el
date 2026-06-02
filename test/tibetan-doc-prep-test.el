;;; tibetan-doc-prep-test.el --- Tests for Tibetan doc-prep pipeline -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for the Tibetan document preparation pipeline.
;; Run with: M-x ert-run-tests-batch-and-exit
;; Or interactively: M-x ert RET t RET

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

;; Load modules to test
(require 'tibetan-doc-format)
(require 'tibetan-ocr-validate)
(require 'tibetan-doc-prep)
(require 'tibetan-doc-prep-init)
(require 'tibetan-ocr-runner)

;; ============================================================================
;; TEST DATA
;; ============================================================================

(defconst tibetan-test--sample-text-clean
  "བདག་གི་སེམས་ཀྱི་རང་བཞིན་ནི།"
  "Clean Tibetan text for testing.")

(defconst tibetan-test--sample-text-with-shad
  "བདག་གི་སེམས།སེམས་ཅན་ཐམས་ཅད།ཆོས་ཀྱི་དབྱིངས།"
  "Tibetan text with multiple shads for line-break testing.")

(defconst tibetan-test--sample-text-with-errors
  "བདག་གི་སེམས་ཀྱི་རངབཞིན།"
  "Tibetan text with potential OCR error (missing tsheg).")

(defconst tibetan-test--known-words
  '("བདག" "སེམས" "ཆོས" "རང་བཞིན")
  "Words that should be in the vocabulary.")

(defconst tibetan-test--known-particles
  '("གི" "ཀྱི" "ནི" "ལ" "ནས")
  "Particles that should be recognized.")

;; ============================================================================
;; FORMATTING TESTS
;; ============================================================================

(ert-deftest tibetan-doc-format-split-at-shad ()
  "Test splitting text at single shad."
  (let ((segments (tibetan-doc-format--split-at-shad
                   tibetan-test--sample-text-with-shad)))
    (should (listp segments))
    (should (= (length segments) 3))
    ;; Each segment should end with shad
    (dolist (seg segments)
      (should (string-suffix-p "།" seg)))))

(ert-deftest tibetan-doc-format-add-segment-markers ()
  "Test adding segment markers to lines."
  (let* ((lines '("བདག་གི་སེམས།" "སེམས་ཅན།"))
         (marked (tibetan-doc-format--add-segment-markers lines)))
    (should (= (length marked) 2))
    (should (string-match-p "〔seg:1〕" (nth 0 marked)))
    (should (string-match-p "〔seg:2〕" (nth 1 marked)))
    (should (string-match-p "〔/seg〕" (nth 0 marked)))))

(ert-deftest tibetan-doc-format-add-segment-markers-with-offset ()
  "Test segment markers with custom starting number."
  (let* ((lines '("line1" "line2"))
         (marked (tibetan-doc-format--add-segment-markers lines 10)))
    (should (string-match-p "〔seg:10〕" (nth 0 marked)))
    (should (string-match-p "〔seg:11〕" (nth 1 marked)))))

(ert-deftest tibetan-doc-format-clean-ocr-artifacts ()
  "Test OCR artifact cleaning."
  (let ((dirty "བདག  གི་སེམས ། ཆོས "))
        (should (not (string-match-p "  "
                                    (tibetan-doc-format-clean-ocr-artifacts dirty))))))

(ert-deftest tibetan-doc-format-extract-folio-markers ()
  "Test folio marker extraction from text."
  (let* ((text "Some text [1a] more text [1b] end")
         (markers (tibetan-doc-format--extract-folio-markers text)))
    (should (listp markers))
    (should (>= (length markers) 2))
    ;; Check that folio numbers were extracted
    (should (member "1a" (mapcar #'cdr markers)))))

(ert-deftest tibetan-doc-format-generate-header ()
  "Test org header generation."
  (let* ((source-info '(:title "Test Doc" :source-file "/path/test.pdf"))
         (options '(:text-type classical))
         (header (tibetan-doc-format--generate-header source-info options)))
    (should (string-match-p "#\\+TITLE:" header))
    (should (string-match-p "Test Doc" header))
    (should (string-match-p "#\\+TIBETAN_TEXT_TYPE:" header))
    (should (string-match-p "classical" header))))

;; ============================================================================
;; VALIDATION TESTS
;; ============================================================================

(ert-deftest tibetan-ocr-validate-particle-recognition ()
  "Test that common particles are recognized."
  (dolist (particle tibetan-test--known-particles)
    (should (member particle tibetan-ocr-validate--particles))))

(ert-deftest tibetan-ocr-validate-strip-particle ()
  "Test particle stripping from words."
  ;; Word with genitive particle
  (let ((result (tibetan-ocr-validate--strip-particle "བདག་གི")))
    (should (consp result))
    ;; Should have root and particle
    (should (stringp (car result))))

  ;; Word without particle
  (let ((result (tibetan-ocr-validate--strip-particle "བདག")))
    (should (consp result))
    (should (null (cdr result)))))

(ert-deftest tibetan-ocr-validate-is-particle ()
  "Test standalone particle detection."
  (should (tibetan-ocr-validate--is-particle "གི"))
  (should (tibetan-ocr-validate--is-particle "ནས"))
  (should (tibetan-ocr-validate--is-particle "ལ"))
  (should-not (tibetan-ocr-validate--is-particle "བདག")))

(ert-deftest tibetan-ocr-validate-valid-structure ()
  "Test syllable structure validation."
  ;; Valid Tibetan syllables
  (should (tibetan-ocr-validate--valid-syllable-structure-p "བདག"))
  (should (tibetan-ocr-validate--valid-syllable-structure-p "སེམས"))
  (should (tibetan-ocr-validate--valid-syllable-structure-p "ཆོས"))

  ;; Empty should be invalid
  (should-not (tibetan-ocr-validate--valid-syllable-structure-p ""))

  ;; Non-Tibetan should be invalid
  (should-not (tibetan-ocr-validate--valid-syllable-structure-p "abc")))

(ert-deftest tibetan-ocr-validate-syllable-returns-plist ()
  "Test that syllable validation returns proper plist."
  (let ((result (tibetan-ocr-validate-syllable "གི")))
    (should (plistp result))
    (should (plist-member result :status))
    (should (plist-member result :syllable))))

(ert-deftest tibetan-ocr-validate-punctuation ()
  "Test that punctuation is handled correctly."
  (let ((result (tibetan-ocr-validate-syllable "།")))
    (should (eq (plist-get result :status) 'valid))
    (should (equal (plist-get result :source) "punctuation"))))

(ert-deftest tibetan-ocr-validate-text-returns-structure ()
  "Test that full text validation returns expected structure."
  (let ((result (tibetan-ocr-validate-text tibetan-test--sample-text-clean)))
    (should (plistp result))
    (should (plist-member result :total))
    (should (plist-member result :valid))
    (should (plist-member result :unknown))
    (should (plist-member result :suspicious))
    (should (> (plist-get result :total) 0))))

(ert-deftest tibetan-ocr-validate-edit-distance ()
  "Test edit distance calculation."
  (should (= (tibetan-ocr-validate--edit-distance "abc" "abc") 0))
  (should (= (tibetan-ocr-validate--edit-distance "abc" "abd") 1))
  (should (= (tibetan-ocr-validate--edit-distance "abc" "abcd") 1))
  (should (= (tibetan-ocr-validate--edit-distance "" "abc") 3)))

(ert-deftest tibetan-ocr-validate-confusion-pairs-exist ()
  "Test that confusion pairs are defined."
  (should (listp tibetan-ocr-validate--confusion-pairs))
  (should (> (length tibetan-ocr-validate--confusion-pairs) 0))
  ;; Check for common confusions
  (should (assoc "ག" tibetan-ocr-validate--confusion-pairs))
  (should (assoc "བ" tibetan-ocr-validate--confusion-pairs)))

(ert-deftest tibetan-ocr-validate-apply-confusion ()
  "Test confusion pair application."
  ;; བདག with བ→པ confusion should produce པདག
  (let ((variants (tibetan-ocr-validate--apply-confusion "བདག")))
    (should (listp variants))
    (should (member "པདག" variants))))

(ert-deftest tibetan-ocr-validate-structure-rejects-subscript-start ()
  "A syllable beginning with a subscript (ྐ) is structurally invalid."
  (should-not (tibetan-ocr-validate--valid-syllable-structure-p "ྐབ")))

(ert-deftest tibetan-ocr-validate-syllable-suspicious-status ()
  "A non-Tibetan, non-punctuation, non-particle token validates as
`suspicious' (exercises the final dispatch branch)."
  (let ((result (tibetan-ocr-validate-syllable "xq")))
    (should (eq (plist-get result :status) 'suspicious))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-doc-prep-validate-then-format ()
  "Test validation followed by formatting workflow."
  (let* ((text tibetan-test--sample-text-with-shad)
         (validation (tibetan-ocr-validate-text text))
         (segments (tibetan-doc-format--split-at-shad text))
         (marked (tibetan-doc-format--add-segment-markers segments)))
    ;; Validation should complete
    (should validation)
    ;; Segments should be created
    (should (= (length marked) 3))
    ;; Each should have markers
    (dolist (seg marked)
      (should (string-match-p "〔seg:" seg)))))

(ert-deftest tibetan-doc-prep-report-generation ()
  "Test validation report generation."
  (let* ((validation (tibetan-ocr-validate-text tibetan-test--sample-text-clean))
         (report (tibetan-ocr-validation-report validation)))
    (should (stringp report))
    (should (string-match-p "Total syllables:" report))
    (should (string-match-p "Valid:" report))))

;; ============================================================================
;; OCR RUNNER TESTS (when available)
;; ============================================================================

(ert-deftest tibetan-ocr-app-detection ()
  "Test BDRC OCR app detection."
  (require 'tibetan-ocr-runner)
  ;; Should return path or nil, never error
  (let ((app (tibetan-ocr--find-app)))
    (should (or (null app) (stringp app)))))

(ert-deftest tibetan-ocr-model-mapping ()
  "Test OCR model name mapping."
  (require 'tibetan-ocr-runner)
  (should (equal (tibetan-ocr--model-name 'woodblock) "Woodblock"))
  (should (equal (tibetan-ocr--model-name 'modern) "Modern"))
  (should (equal (tibetan-ocr--model-name 'pecha) "Woodblock"))  ; alias
  (should (equal (tibetan-ocr--model-name 'unknown) "Woodblock")))  ; default

;; ============================================================================
;; DOC-PREP WIZARD AND INTERACTIVE COMMANDS
;; ============================================================================

(ert-deftest tibetan-doc-prep-wizard-is-command ()
  "Test that tibetan-doc-prep-wizard is an interactive command."
  (should (fboundp 'tibetan-doc-prep-wizard))
  (should (commandp 'tibetan-doc-prep-wizard)))

(ert-deftest tibetan-doc-prep-ocr-is-command ()
  "Test that tibetan-doc-prep-ocr is callable."
  (should (fboundp 'tibetan-doc-prep-ocr))
  (should (commandp 'tibetan-doc-prep-ocr)))

(ert-deftest tibetan-doc-prep-correct-is-command ()
  "Test that tibetan-doc-prep-correct is callable."
  (should (fboundp 'tibetan-doc-prep-correct))
  (should (commandp 'tibetan-doc-prep-correct)))

(ert-deftest tibetan-doc-prep-format-is-command ()
  "Test that tibetan-doc-prep-format is callable."
  (should (fboundp 'tibetan-doc-prep-format))
  (should (commandp 'tibetan-doc-prep-format)))

(ert-deftest tibetan-doc-prep-quick-pecha-is-command ()
  "Test that tibetan-doc-prep-quick-pecha is callable."
  (should (fboundp 'tibetan-doc-prep-quick-pecha))
  (should (commandp 'tibetan-doc-prep-quick-pecha)))

(ert-deftest tibetan-doc-prep-quick-verse-is-command ()
  "Test that tibetan-doc-prep-quick-verse is callable."
  (should (fboundp 'tibetan-doc-prep-quick-verse))
  (should (commandp 'tibetan-doc-prep-quick-verse)))

;; ============================================================================
;; DOC-PREP INIT STATUS
;; ============================================================================

(ert-deftest tibetan-doc-prep-init-status-is-command ()
  "Test that tibetan-doc-prep-init-status is callable."
  (should (fboundp 'tibetan-doc-prep-init-status))
  (should (commandp 'tibetan-doc-prep-init-status)))

;; ----------------------------------------------------------------------------
;; §5.27 Phase 2 follow-up (2026-05-27):  post-ingest relocation into
;; the configured `work in progress' sibling folder.  Mirrors the
;; Milarepa-folder convention from the buddhist-studies repo.
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-doc-prep-resolve-wip-target-relative-default ()
  "Default `work in progress' folder name is resolved as a SIBLING
of the source's parent directory (one level up from the source
itself).  Returns the destination's absolute path."
  (let* ((tibetan-doc-prep-work-in-progress-folder "work in progress")
         (target (tibetan-doc-prep--resolve-work-in-progress-target
                  "/tmp/parent/raw/foo.org")))
    (should (equal "/tmp/parent/work in progress/foo.org" target))))

(ert-deftest tibetan-doc-prep-resolve-wip-target-absolute-folder ()
  "When `--work-in-progress-folder' is an absolute path, the
basename is appended directly — no sibling-of-parent computation."
  (let* ((tibetan-doc-prep-work-in-progress-folder "/abs/wip")
         (target (tibetan-doc-prep--resolve-work-in-progress-target
                  "/tmp/parent/raw/foo.org")))
    (should (equal "/abs/wip/foo.org" target))))

(ert-deftest tibetan-doc-prep-resolve-wip-target-nil-disables ()
  "Nil folder = feature off → resolver returns SOURCE-PATH
unchanged (caller short-circuits the move)."
  (let* ((tibetan-doc-prep-work-in-progress-folder nil)
         (target (tibetan-doc-prep--resolve-work-in-progress-target
                  "/tmp/foo.org")))
    (should (equal "/tmp/foo.org" target))))

(ert-deftest tibetan-doc-prep-move-to-wip-relocates-into-sibling ()
  "End-to-end:  `--move-to-work-in-progress' creates the sibling
`work in progress/' folder and renames the source file across.
Returns the destination's absolute path;  source no longer exists
at the original location."
  (let ((dir (make-temp-file "wip-move-" t)))
    (unwind-protect
        (let* ((tibetan-doc-prep-work-in-progress-folder "work in progress")
               (raw-dir (expand-file-name "raw" dir))
               (source (expand-file-name "foo.org" raw-dir)))
          (make-directory raw-dir t)
          (with-temp-file source (insert "* Tibetan Text\nfoo //\n"))
          (let ((moved (tibetan-doc-prep-move-to-work-in-progress source)))
            (should (file-exists-p moved))
            (should-not (file-exists-p source))
            (should (string-match-p "work in progress/foo\\.org\\'" moved))
            (should (string-match-p "Tibetan Text"
                                    (with-temp-buffer
                                      (insert-file-contents moved)
                                      (buffer-string))))))
      (delete-directory dir t))))

(ert-deftest tibetan-doc-prep-move-to-wip-creates-target-folder ()
  "Missing target folder → helper `make-directory's it with the
parents flag.  Wizard relies on this — the user never has to
pre-create `work in progress/' by hand."
  (let ((dir (make-temp-file "wip-mkdir-" t)))
    (unwind-protect
        (let* ((tibetan-doc-prep-work-in-progress-folder "work in progress")
               (raw-dir (expand-file-name "raw" dir))
               (source (expand-file-name "foo.org" raw-dir)))
          (make-directory raw-dir t)
          (with-temp-file source (insert "x"))
          (should-not (file-directory-p
                       (expand-file-name "work in progress" dir)))
          (tibetan-doc-prep-move-to-work-in-progress source)
          (should (file-directory-p
                   (expand-file-name "work in progress" dir))))
      (delete-directory dir t))))

(ert-deftest tibetan-doc-prep-move-to-wip-nil-folder-is-noop ()
  "Feature disabled (folder = nil) → helper is a no-op:  source
file stays in place, return value = original absolute path."
  (let ((dir (make-temp-file "wip-noop-" t)))
    (unwind-protect
        (let* ((tibetan-doc-prep-work-in-progress-folder nil)
               (source (expand-file-name "foo.org" dir)))
          (with-temp-file source (insert "x"))
          (let ((ret (tibetan-doc-prep-move-to-work-in-progress source)))
            (should (file-exists-p source))
            (should (equal (expand-file-name source) ret))))
      (delete-directory dir t))))

(ert-deftest tibetan-doc-prep-move-to-wip-idempotent ()
  "Calling twice in a row on a source already at the destination
is a no-op the second time (the resolver returns the same path
as the source, and the equal-check short-circuits the rename)."
  (let ((dir (make-temp-file "wip-idem-" t)))
    (unwind-protect
        (let* ((tibetan-doc-prep-work-in-progress-folder "work in progress")
               (raw-dir (expand-file-name "raw" dir))
               (source (expand-file-name "foo.org" raw-dir)))
          (make-directory raw-dir t)
          (with-temp-file source (insert "x"))
          (let ((moved (tibetan-doc-prep-move-to-work-in-progress source))
                (twice nil))
            ;; Second invocation:  pass the already-relocated path.
            (setq twice (tibetan-doc-prep-move-to-work-in-progress moved))
            (should (equal moved twice))
            (should (file-exists-p moved))))
      (delete-directory dir t))))

(ert-deftest tibetan-doc-prep-move-to-wip-missing-source-errors ()
  "Defensive:  nonexistent source → `user-error' (no silent
nothing-happens)."
  (should-error
   (tibetan-doc-prep-move-to-work-in-progress "/nonexistent/foo.org")
   :type 'user-error))

;; ============================================================================
;; HELPER FUNCTION FOR RUNNING TESTS
;; ============================================================================

(defun tibetan-doc-prep-run-tests ()
  "Run all tibetan-doc-prep tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-"))

(defun tibetan-doc-prep-run-tests-batch ()
  "Run all tests in batch mode."
  (ert-run-tests-batch-and-exit "^tibetan-"))

(provide 'tibetan-doc-prep-test)
;;; tibetan-doc-prep-test.el ends here
