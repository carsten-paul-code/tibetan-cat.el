;;; tibetan-auto-analysis-test.el --- Tests for auto-analysis feature -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for automatic batch analysis generation.

;;; Code:

(require 'ert)
(require 'org)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-org-structure)
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-auto-analysis nil t)

;; ============================================================================
;; SEGMENT COUNTING TESTS
;; ============================================================================

(ert-deftest tibetan-auto-count-segments-empty ()
  "Test counting segments in empty document."
  (skip-unless (fboundp 'tibetan-auto--count-segments))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n")
    (should (= 0 (tibetan-auto--count-segments)))))

(ert-deftest tibetan-auto-count-segments-single ()
  "Test counting single segment."
  (skip-unless (fboundp 'tibetan-auto--count-segments))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n** Sentence 1\n*** Segment 1\ntext\n")
    (should (= 1 (tibetan-auto--count-segments)))))

(ert-deftest tibetan-auto-count-segments-multiple ()
  "Test counting multiple segments."
  (skip-unless (fboundp 'tibetan-auto--count-segments))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n** Sentence 1\n*** Segment 1\ntext1\n*** Segment 2\ntext2\n*** Segment 3\ntext3\n")
    (should (= 3 (tibetan-auto--count-segments)))))

;; ============================================================================
;; SENTENCE COUNTING TESTS
;; ============================================================================

(ert-deftest tibetan-auto-count-sentences-empty ()
  "Test counting sentences in empty document."
  (skip-unless (fboundp 'tibetan-auto--count-sentences))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n")
    (should (= 0 (tibetan-auto--count-sentences)))))

(ert-deftest tibetan-auto-count-sentences-single ()
  "Test counting single sentence."
  (skip-unless (fboundp 'tibetan-auto--count-sentences))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n** Sentence 1\n*** Segment 1\ntext\n")
    (should (= 1 (tibetan-auto--count-sentences)))))

(ert-deftest tibetan-auto-count-sentences-multiple ()
  "Test counting multiple sentences."
  (skip-unless (fboundp 'tibetan-auto--count-sentences))
  (with-temp-buffer
    (org-mode)
    (insert "* Title\n** Sentence 1\n*** Segment 1\ntext\n** Sentence 2\n*** Segment 2\ntext\n")
    (should (= 2 (tibetan-auto--count-sentences)))))

;; ============================================================================
;; SEGMENT COLLECTION TESTS
;; ============================================================================

(ert-deftest tibetan-auto-collect-segments-basic ()
  "Test collecting segment data."
  (skip-unless (fboundp 'tibetan-auto--collect-segments))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "* Title\n\n** Sentence 1\n\n*** Segment 1\nབཀྲ་ཤིས།\n\n*** Segment 2\nབདེ་ལེགས།\n")
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((segments (tibetan-auto--collect-segments)))
      (should (= 2 (length segments)))
      (should (assoc 1 segments))
      (should (assoc 2 segments))
      (should (string-match-p "བཀྲ་ཤིས" (cdr (assoc 1 segments))))
      (should (string-match-p "བདེ་ལེགས" (cdr (assoc 2 segments)))))))

(ert-deftest tibetan-auto-collect-segments-preserves-tibetan ()
  "Test that Tibetan text is preserved in collection."
  (skip-unless (fboundp 'tibetan-auto--collect-segments))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "* Title\n\n** Sentence 1\n\n*** Segment 1\nསངས་རྒྱས་ཆོས་དང་ཚོགས་ཀྱི་མཆོག་རྣམས་ལ།\n")
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((segments (tibetan-auto--collect-segments)))
      (should (= 1 (length segments)))
      (let ((text (cdr (car segments))))
        (should (string-match-p "སངས་རྒྱས" text))
        (should (string-match-p "ཆོས" text))))))

(ert-deftest tibetan-auto-collect-segments-level-4-after-sentence-wrap ()
  "Segments at `**** Segment N' (after `tibetan-add-sentence-structure')
are picked up alongside the legacy `*** Segment N' layout.

Regression for YBh prep 2026-04-20: the collector's heading regex was
hardcoded to three asterisks, so running `C-c u B' on a source that
had already gone through the sentence-structure pass returned zero
segments.  Fixed to `^\\*+ Segment '."
  (skip-unless (fboundp 'tibetan-auto--collect-segments))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "* Text\n\n"
            "*** Sentence 1\n"
            "**** Segment 1\nབཀྲ་ཤིས།\n"
            "**** Segment 2\nབདེ་ལེགས།\n"
            "*** Sentence 2\n"
            "**** Segment 3\nཔདྨ།\n")
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((segments (tibetan-auto--collect-segments)))
      (should (= 3 (length segments)))
      (should (assoc 1 segments))
      (should (assoc 2 segments))
      (should (assoc 3 segments))
      (should (string-match-p "བཀྲ་ཤིས" (cdr (assoc 1 segments))))
      (should (string-match-p "པདྨ" (cdr (assoc 3 segments)))))))

(ert-deftest tibetan-auto-claude-needs-request-matches-two-star-translation ()
  "`tibetan-auto--claude-needs-request-p' matches `^\\*\\* Claude Translation'
(two stars, with suffix) — the actual placement produced by the current
`tibetan-analysis--generate-claude-section' in the `* Auto-Analysis' block.

Regression for YBh batch Claude fill 2026-04-20: the detector was
anchored on `^\\*\\*\\* Claude\\$' (three stars, no suffix) which matches
neither the two-star Auto-Analysis placement nor the three-star
`*** Claude Translation' Provided-Translations placement."
  (skip-unless (fboundp 'tibetan-auto--claude-needs-request-p))
  (let ((tmp (make-temp-file "claude-needs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Tibetan Text\nསངས་རྒྱས།\n\n"
                    "* Auto-Analysis\n"
                    "** Wylie Transliteration\nsangs rgyas\n\n"
                    "** Claude Translation\n"
                    "[Requesting translation...]\n\n"
                    "** Claude Grammar\n\n"
                    "* My Notes\n\n"))
          (should (tibetan-auto--claude-needs-request-p tmp)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-auto-claude-needs-request-matches-three-star-translation ()
  "Also matches `^\\*\\*\\* Claude Translation' (three stars, suffixed) —
the Provided-Translations placement used by sentence-level sent-*.org."
  (skip-unless (fboundp 'tibetan-auto--claude-needs-request-p))
  (let ((tmp (make-temp-file "claude-needs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Tibetan Text\nསངས་རྒྱས།\n\n"
                    "* Provided Translations\n"
                    "*** Claude Translation\n"
                    "[Requesting translation...]\n\n"))
          (should (tibetan-auto--claude-needs-request-p tmp)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-auto-claude-needs-request-nil-when-filled ()
  "Returns nil when the Translation block holds a real (non-placeholder)
translation body."
  (skip-unless (fboundp 'tibetan-auto--claude-needs-request-p))
  (let ((tmp (make-temp-file "claude-needs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Tibetan Text\nསངས་རྒྱས།\n\n"
                    "* Auto-Analysis\n"
                    "** Claude Translation\n"
                    "I pay homage to the Buddha.\n\n"
                    "** Claude Grammar\nSome grammar notes.\n\n"))
          (should-not (tibetan-auto--claude-needs-request-p tmp)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-auto-claude-needs-request-matches-fail-stub ()
  "Fail stubs (`[Claude request failed: ...]') count as still-needing —
so re-running the fill picks them up again."
  (skip-unless (fboundp 'tibetan-auto--claude-needs-request-p))
  (let ((tmp (make-temp-file "claude-needs-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "* Auto-Analysis\n"
                    "** Claude Translation\n"
                    "[Claude request failed: HTTP 500 — re-run C-c u R later]\n\n"))
          (should (tibetan-auto--claude-needs-request-p tmp)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest tibetan-auto-analyze-skip-check-matches-create-path ()
  "`tibetan-auto-analyze-document' must SKIP an existing `seg-NNN.org'
on a second run — not overwrite it.

Regression for 2026-04-20 YBh disaster: the skip check computed
`filepath' via `(tibetan-analysis-get-filepath seg-num source-file)'
which returns a SUFFIXED path like `seg-NNN-<shortname>.org', while
`tibetan-analysis-create-file' internally re-computes the path WITHOUT
source-file and writes to the UNSUFFIXED `seg-NNN.org'.  The mismatch
meant every existing seg-NNN.org was silently overwritten on every
re-run, wiping Claude translations.  Fix: drop the source-file arg
from the skip-check `get-filepath' call so the two paths match."
  (skip-unless (fboundp 'tibetan-auto-analyze-document))
  (skip-unless (fboundp 'tibetan-analysis-get-filepath))
  (let* ((root (make-temp-file "auto-skip-" t))
         (source-file (expand-file-name "gotrapatala.org" root))
         (folder (file-name-as-directory
                  (expand-file-name "analysis" root))))
    (unwind-protect
        (progn
          (make-directory folder t)
          ;; Minimal source with a single *** Segment 1.
          (with-temp-file source-file
            (insert "#+TITLE: YBh test\n\n"
                    "* Tibetan Text\n\n"
                    "*** Segment 1\n"
                    "བཀྲ་ཤིས།\n"))
          (let ((buf (find-file-noselect source-file)))
            (unwind-protect
                (with-current-buffer buf
                  (org-mode)
                  ;; Under real `tibetan-analysis-get-folder' (pins the
                  ;; folder to source-file's directory) the output ends
                  ;; up in `<root>/analysis/seg-001.org'.
                  (let ((expected (expand-file-name "seg-001.org" folder)))
                    ;; Pre-seed a file with a distinctive marker so we
                    ;; can detect an unwanted overwrite.
                    (with-temp-file expected
                      (insert "MARKER-BEFORE-REANALYZE\n"))
                    ;; Suppress Claude fire so the test doesn't need
                    ;; gptel + network.
                    (let ((tibetan-auto-fire-claude-on-create nil))
                      (tibetan-auto-analyze-document))
                    ;; Marker must still be in the file — meaning the
                    ;; skip-check correctly matched.
                    (with-temp-buffer
                      (insert-file-contents expected)
                      (should (string-match-p "MARKER-BEFORE-REANALYZE"
                                              (buffer-string))))))
              (when (buffer-live-p buf)
                (with-current-buffer buf (set-buffer-modified-p nil))
                (kill-buffer buf)))))
      (delete-directory root t))))

(ert-deftest tibetan-auto-fire-claude-on-create-defcustom-exists ()
  "The gate defcustom exists and defaults to t."
  (should (boundp 'tibetan-auto-fire-claude-on-create))
  (should (eq t (default-value 'tibetan-auto-fire-claude-on-create))))

(ert-deftest tibetan-auto--fire-claude-on-new-files-stubbed ()
  "`tibetan-auto--fire-claude-on-new-files' queues one request per pair.

Stubs `run-at-time' to execute the lambda immediately, and stubs
`tibetan-analysis--request-claude-translation' to record its args;
then asserts the stub was called for every pair with the expected
(tibetan-text, filepath) arguments."
  (skip-unless (fboundp 'tibetan-auto--fire-claude-on-new-files))
  (let ((captured '()))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-analysis--request-claude-translation)
               (lambda (text filepath)
                 (push (cons filepath text) captured))))
      (tibetan-auto--fire-claude-on-new-files
       '(("/tmp/seg-001.org" . "text-one")
         ("/tmp/seg-002.org" . "text-two")
         ("/tmp/seg-003.org" . "text-three"))))
    (setq captured (nreverse captured))
    (should (= 3 (length captured)))
    (should (equal "/tmp/seg-001.org" (car (nth 0 captured))))
    (should (equal "text-one"         (cdr (nth 0 captured))))
    (should (equal "/tmp/seg-003.org" (car (nth 2 captured))))
    (should (equal "text-three"       (cdr (nth 2 captured))))))

(ert-deftest tibetan-auto--fire-claude-skips-empty-text ()
  "Pairs whose Tibetan text is nil or empty are not queued."
  (skip-unless (fboundp 'tibetan-auto--fire-claude-on-new-files))
  (let ((count 0))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-analysis--request-claude-translation)
               (lambda (_text _filepath) (setq count (1+ count)))))
      (tibetan-auto--fire-claude-on-new-files
       '(("/tmp/seg-001.org" . "real text")
         ("/tmp/seg-002.org" . "")
         ("/tmp/seg-003.org" . nil))))
    (should (= 1 count))))

(ert-deftest tibetan-auto-collect-sentences-level-3-after-add-structure ()
  "Sentences at `*** Sentence N' (after `tibetan-add-sentence-structure')
are picked up alongside the legacy `** Sentence N' layout.

Regression for YBh prep 2026-04-20: same hardcoded-depth bug as the
segment collector, at `^\\*\\* Sentence' instead of `^\\*+ Sentence'."
  (skip-unless (fboundp 'tibetan-auto--collect-sentences))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "* Text\n\n"
            "*** Sentence 1\n"
            "**** Segment 1\nབཀྲ་ཤིས།\n"
            "*** Sentence 2\n"
            "**** Segment 2\nབདེ་ལེགས།\n")
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((sentences (tibetan-auto--collect-sentences)))
      (should (= 2 (length sentences)))
      (should (assoc 1 sentences))
      (should (assoc 2 sentences)))))

;; ============================================================================
;; SENTENCE COLLECTION TESTS
;; ============================================================================

(ert-deftest tibetan-auto-collect-sentences-basic ()
  "Test collecting sentence data."
  (skip-unless (fboundp 'tibetan-auto--collect-sentences))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "* Title\n\n** Sentence 1\n\n*** Segment 1\ntext1\n\n*** Segment 2\ntext2\n\n** Sentence 2\n\n*** Segment 3\ntext3\n")
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (goto-char (point-min))
    (let ((sentences (tibetan-auto--collect-sentences)))
      (should (= 2 (length sentences)))
      (should (assoc 1 sentences))
      (should (assoc 2 sentences)))))

;; ============================================================================
;; SKIP LOGIC TESTS
;; ============================================================================

(ert-deftest tibetan-auto-should-skip-existing ()
  "Test skip logic for existing files."
  (skip-unless (fboundp 'tibetan-auto--should-skip-p))
  (let ((tibetan-auto-skip-existing t)
        (temp-file (make-temp-file "tibetan-test")))
    (unwind-protect
        (should (tibetan-auto--should-skip-p temp-file))
      (delete-file temp-file))))

(ert-deftest tibetan-auto-should-not-skip-missing ()
  "Test skip logic for missing files."
  (skip-unless (fboundp 'tibetan-auto--should-skip-p))
  (let ((tibetan-auto-skip-existing t))
    (should-not (tibetan-auto--should-skip-p "/nonexistent/file.org"))))

(ert-deftest tibetan-auto-force-regenerate ()
  "Test force regeneration ignores existing files."
  (skip-unless (fboundp 'tibetan-auto--should-skip-p))
  (let ((tibetan-auto-skip-existing nil)
        (temp-file (make-temp-file "tibetan-test")))
    (unwind-protect
        (should-not (tibetan-auto--should-skip-p temp-file))
      (delete-file temp-file))))

;; ============================================================================
;; FILENAME GENERATION TESTS
;; ============================================================================

(ert-deftest tibetan-auto-sentence-filename ()
  "Test sentence analysis filename generation."
  (skip-unless (fboundp 'tibetan-auto--sentence-filename))
  (let ((filename (tibetan-auto--sentence-filename 1 "/path/to/test.org")))
    (should (stringp filename))
    (should (string-match-p "sent-001" filename))
    (should (string-match-p "\\.org$" filename))))

(ert-deftest tibetan-auto-sentence-filename-with-suffix ()
  "Test sentence filename includes source suffix."
  (skip-unless (fboundp 'tibetan-auto--sentence-filename))
  (let ((filename (tibetan-auto--sentence-filename 2 "/path/to/Tigress-Story.org")))
    (should (string-match-p "tigress" filename))))

;; ============================================================================
;; PHASE A.3 — DharmaMitra batch fire on newly-created segments
;; ============================================================================
;;
;; Mirrors the existing `tibetan-auto--fire-claude-on-new-files'
;; pattern.  After `tibetan-auto-analyze-document' creates the
;; structural analysis files, fire DM translations for each
;; (Tibetan + optional Sanskrit) via the umbrella
;; `tibetan-dharmamitra-translation-fire-for-segment'.
;;
;; Gated by `tibetan-auto-fire-dm-on-create' (defcustom, default t)
;; so users who don't want DM translations can opt out without
;; disabling Claude.

(ert-deftest tibetan-auto-fire-dm-on-create-defcustom-exists ()
  "`tibetan-auto-fire-dm-on-create' exists and defaults to t.
Mirrors `tibetan-auto-fire-claude-on-create'."
  (should (boundp 'tibetan-auto-fire-dm-on-create))
  (should (eq t (default-value 'tibetan-auto-fire-dm-on-create))))

(ert-deftest tibetan-auto--fire-dm-on-new-files-stubbed ()
  "`tibetan-auto--fire-dm-on-new-files' calls `fire-for-segment'
once per pair, with each pair's filepath + text."
  (skip-unless (fboundp 'tibetan-auto--fire-dm-on-new-files))
  (let ((captured '()))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-for-segment)
               (lambda (text filepath &rest _)
                 (push (cons filepath text) captured))))
      (tibetan-auto--fire-dm-on-new-files
       '(("/tmp/seg-001.org" . "tibetan-one")
         ("/tmp/seg-002.org" . "tibetan-two")
         ("/tmp/seg-003.org" . "tibetan-three"))))
    (setq captured (nreverse captured))
    (should (= 3 (length captured)))
    (should (equal "/tmp/seg-001.org" (car (nth 0 captured))))
    (should (equal "tibetan-one"      (cdr (nth 0 captured))))
    (should (equal "/tmp/seg-003.org" (car (nth 2 captured))))
    (should (equal "tibetan-three"    (cdr (nth 2 captured))))))

(ert-deftest tibetan-auto--fire-dm-skips-empty-text ()
  "Pairs whose Tibetan text is nil or empty don't trigger
`fire-for-segment'."
  (skip-unless (fboundp 'tibetan-auto--fire-dm-on-new-files))
  (let ((count 0))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-for-segment)
               (lambda (&rest _) (cl-incf count))))
      (tibetan-auto--fire-dm-on-new-files
       '(("/tmp/seg-001.org" . "real text")
         ("/tmp/seg-002.org" . "")
         ("/tmp/seg-003.org" . nil)
         ("/tmp/seg-004.org" . "more text"))))
    (should (= count 2))))

(ert-deftest tibetan-auto--fire-dm-passes-source-and-seg-id ()
  "When the analysis file has a `#+SOURCE:' header, the umbrella
function gets called with the resolved source-file + seg-id so
parallel-mode Sanskrit firing works."
  (skip-unless (fboundp 'tibetan-auto--fire-dm-on-new-files))
  (let ((captured-source nil)
        (captured-seg-id nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_delay _repeat fn) (funcall fn)))
              ((symbol-function 'tibetan-analysis--source-file-from-analysis)
               (lambda (_file) "/tmp/source.org"))
              ((symbol-function 'tibetan-analysis--seg-id-from-filename)
               (lambda (file)
                 (when (string-match "seg-\\([0-9]+\\)" file)
                   (string-to-number (match-string 1 file)))))
              ((symbol-function 'tibetan-dharmamitra-translation-fire-for-segment)
               (lambda (_text _file source-file seg-id)
                 (setq captured-source source-file
                       captured-seg-id seg-id))))
      (tibetan-auto--fire-dm-on-new-files
       '(("/tmp/seg-005.org" . "text"))))
    (should (equal captured-source "/tmp/source.org"))
    (should (= captured-seg-id 5))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-auto-analysis-run-tests ()
  "Run all auto-analysis tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-auto-"))

(provide 'tibetan-auto-analysis-test)
;;; tibetan-auto-analysis-test.el ends here
