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
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-auto-analysis-run-tests ()
  "Run all auto-analysis tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-auto-"))

(provide 'tibetan-auto-analysis-test)
;;; tibetan-auto-analysis-test.el ends here
