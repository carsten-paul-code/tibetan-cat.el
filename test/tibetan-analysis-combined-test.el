;;; tibetan-analysis-combined-test.el --- Tests for Combined-synthesis Claude pipeline -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for `persist/tibetan-analysis-combined.el' — the
;; Combined-synthesis Claude pipeline introduced in Phase 4 of
;; two-language-parallel-analysis (2026-04-30).

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir))
  (add-to-list 'load-path (expand-file-name "../config" dir)))

(require 'tibetan-analysis-claude)
(require 'tibetan-analysis-combined)

;; ============================================================================
;; FIXTURES + HELPERS
;; ============================================================================

(defmacro tibetan-com-test--with-source (header-text &rest body)
  "Write a source .org with HEADER-TEXT, bind SOURCE-FILE, eval BODY."
  (declare (indent 1))
  `(let ((source-file (make-temp-file "tibetan-com-src-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file source-file (insert ,header-text))
           ,@body)
       (when (file-exists-p source-file) (delete-file source-file)))))

(defmacro tibetan-com-test--with-analysis (initial-content &rest body)
  "Write INITIAL-CONTENT to a temp seg-001.org, bind ANALYSIS-FILE, eval BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-com-ana-" t))
          (analysis-file (expand-file-name "seg-001.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file analysis-file (insert ,initial-content))
           ,@body)
       (delete-directory dir t))))

(defconst tibetan-com-test--full-response
  "## Translation
Synthesis: the bodhisattva is by nature one who delights in giving.

## Divergence
- Skt `prakṛtyaiva' (instr. emphatic) → Tib `rang bzhin gyis'
  (locative): the Tibetan emphasises essence; doctrinal weight
  comparable but framing differs.
"
  "Realistic Combined response WITH a Divergence section.")

(defconst tibetan-com-test--no-divergence-response
  "## Translation
Synthesis: he restrains his speech.
"
  "Combined response WITHOUT a Divergence section (faithful
rendering case — Claude correctly omitted Divergence).")

;; ============================================================================
;; build-prompts tests
;; ============================================================================

(ert-deftest tibetan-com-build-prompts-needs-all-four-inputs ()
  "Returns nil when ANY of the four inputs is missing / empty."
  (should (null (tibetan-analysis-combined--build-prompts
                 nil nil "T-trans" "S-trans" nil)))
  (should (null (tibetan-analysis-combined--build-prompts
                 "བདག" nil "T-trans" "S-trans" nil)))
  (should (null (tibetan-analysis-combined--build-prompts
                 "བདག"
                 (list :iast "ahaṃ" :devanagari nil
                       :script-source 'iast-line)
                 "" "S-trans" nil)))
  (should (null (tibetan-analysis-combined--build-prompts
                 "བདག"
                 (list :iast "ahaṃ" :devanagari nil
                       :script-source 'iast-line)
                 "T-trans" "" nil))))

(ert-deftest tibetan-com-build-prompts-all-inputs-present ()
  "All four inputs present → returns (system . user); user
carries both raw sources AND both upstream translations."
  (let* ((prompts (tibetan-analysis-combined--build-prompts
                   "བདག"
                   (list :iast "ahaṃ" :devanagari nil
                         :script-source 'iast-line)
                   "I."     ; tibetan translation
                   "I am."  ; sanskrit translation
                   nil))
         (system (car prompts))
         (user   (cdr prompts)))
    (should (stringp system))
    (should (stringp user))
    (should (string-match-p "comparative reader" system))
    (should (string-match-p "## Translation" system))
    (should (string-match-p "## Divergence" system))
    ;; User prompt has both raw + both translations.
    (should (string-match-p "ahaṃ" user))
    (should (string-match-p "བདག" user))
    (should (string-match-p "Upstream Sanskrit translation:" user))
    (should (string-match-p "I am." user))
    (should (string-match-p "Upstream Tibetan translation:" user))
    (should (string-match-p "^I\\." user))))

(ert-deftest tibetan-com-build-prompts-handles-multiple-claude-context-headers ()
  "Regression (live test 2026-05-03 on gotrapaṭala.org seg 9):  same
class of bug as the Sanskrit-side builder.  Source files routinely
carry MULTIPLE `#+TIBETAN_CLAUDE_CONTEXT:' header lines (the
gotrapaṭala has four).  The metadata reader returns
`:claude-context' as a list of strings — the builder must iterate,
not pass it to `concat' which crashes with `(wrong-type-argument
characterp <STRING>)'."
  (tibetan-com-test--with-source
      (concat "#+TITLE: Doc\n"
              "#+SOURCE_MODE: parallel-sanskrit\n"
              "#+TIBETAN_CLAUDE_CONTEXT: Genre context one.\n"
              "#+TIBETAN_CLAUDE_CONTEXT: Genre context two.\n")
    (let ((prompt (tibetan-analysis-combined--build-prompts
                   "བདག"
                   (list :iast "ahaṃ" :devanagari nil
                         :script-source 'iast-line)
                   "I." "I am." source-file)))
      (should prompt)
      (should (consp prompt))
      (should (stringp (car prompt)))
      (should (string-match-p "Genre context one\\." (car prompt)))
      (should (string-match-p "Genre context two\\." (car prompt))))))

(ert-deftest tibetan-com-build-prompts-system-block-stable-across-segments ()
  "Cache invariant: two builds on the same source with different
inputs produce byte-identical SYSTEM prompts."
  (tibetan-com-test--with-source
      "#+TITLE: Doc\n#+SOURCE_MODE: parallel-sanskrit\n"
    (let* ((p1 (tibetan-analysis-combined--build-prompts
                "tib1"
                (list :iast "skt1" :devanagari nil
                      :script-source 'iast-line)
                "trans1" "stransA" source-file))
           (p2 (tibetan-analysis-combined--build-prompts
                "tib2"
                (list :iast "skt2" :devanagari nil
                      :script-source 'iast-line)
                "trans2" "stransB" source-file)))
      (should (equal (car p1) (car p2)))
      (should-not (equal (cdr p1) (cdr p2))))))

;; ============================================================================
;; needs-fire-p
;; ============================================================================

(ert-deftest tibetan-com-needs-fire-p-true-when-all-present ()
  (should (tibetan-analysis-combined--needs-fire-p
           "བདག"
           (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
           "Tibetan trans" "Sanskrit trans")))

(ert-deftest tibetan-com-needs-fire-p-false-when-any-missing ()
  (should-not (tibetan-analysis-combined--needs-fire-p
               nil
               (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
               "Tibetan trans" "Sanskrit trans"))
  (should-not (tibetan-analysis-combined--needs-fire-p
               "བདག" nil "Tibetan trans" "Sanskrit trans"))
  (should-not (tibetan-analysis-combined--needs-fire-p
               "བདག"
               (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
               nil "Sanskrit trans"))
  (should-not (tibetan-analysis-combined--needs-fire-p
               "བདག"
               (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
               "Tibetan trans" nil)))

(ert-deftest tibetan-com-needs-fire-p-false-when-iast-empty ()
  "Empty `:iast' should not fire (placeholder Sanskrit yields
walker plist with nil iast in production, but defensive check
here for empty-string too)."
  (should-not (tibetan-analysis-combined--needs-fire-p
               "བདག"
               (list :iast "" :devanagari nil :script-source 'iast-line)
               "T" "S")))

;; ============================================================================
;; parser
;; ============================================================================

(ert-deftest tibetan-com-parse-translation-and-divergence ()
  "Response with both sections parses both keys."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            tibetan-com-test--full-response)))
    (should (string-match-p "Synthesis:" (plist-get p :translation)))
    (should (string-match-p "prakṛtyaiva" (plist-get p :divergence)))))

(ert-deftest tibetan-com-parse-divergence-omitted-when-faithful ()
  "Response with no Divergence section leaves `:divergence' nil."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            tibetan-com-test--no-divergence-response)))
    (should (plist-get p :translation))
    (should (null (plist-get p :divergence)))))

(ert-deftest tibetan-com-parse-empty-input ()
  "Empty / nil input returns plist with both keys nil."
  (dolist (input '(nil ""))
    (let ((p (tibetan-analysis-combined--parse-claude-sections input)))
      (should (null (plist-get p :translation)))
      (should (null (plist-get p :divergence))))))

;; ============================================================================
;; insert + read + restore round-trip
;; ============================================================================

(ert-deftest tibetan-com-insert-creates-parent-and-sections ()
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     tibetan-com-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\* Combined Analysis$" s))
        (should (string-match-p "^\\*\\* Combined Translation$" s))
        (should (string-match-p "^\\*\\* Divergence$" s))
        (should (string-match-p "Synthesis:" s))
        (should (string-match-p "prakṛtyaiva" s))))))

(ert-deftest tibetan-com-insert-skips-divergence-when-faithful ()
  "Faithful-rendering response → Combined Translation section
appears, Divergence does NOT."
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     tibetan-com-test--no-divergence-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\*\\* Combined Translation$" s))
        (should-not (string-match-p "^\\*\\* Divergence$" s))))))

(ert-deftest tibetan-com-insert-empty-response-no-op ()
  "Empty response leaves the file untouched (no parent created)."
  (let ((initial "* Tibetan Text\nbdag\n\n* Footnotes\n"))
    (tibetan-com-test--with-analysis initial
      (dolist (resp '(nil "" "no headings"))
        (tibetan-analysis-combined--insert-sections resp analysis-file))
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should-not (string-match-p "^\\* Combined Analysis$"
                                    (buffer-string)))))))

(ert-deftest tibetan-com-read-round-trip ()
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     tibetan-com-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((p (tibetan-analysis-combined--read-sections analysis-file)))
      (should (string-match-p "Synthesis:" (plist-get p :translation)))
      (should (string-match-p "prakṛtyaiva" (plist-get p :divergence))))))

(ert-deftest tibetan-com-restore-round-trip ()
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     tibetan-com-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (tibetan-analysis-combined--restore-sections
     analysis-file
     (list :translation "UPDATED translation"
           :divergence  "UPDATED divergence"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((p (tibetan-analysis-combined--read-sections analysis-file)))
      (should (equal (plist-get p :translation) "UPDATED translation"))
      (should (equal (plist-get p :divergence)  "UPDATED divergence")))))

;; ============================================================================
;; Queue integration (concurrency optimization, 2026-04-30)
;; ============================================================================

(ert-deftest tibetan-com-request-synthesis-uses-queue ()
  "`--request-synthesis' submits via `tibetan-claude-queue-submit'."
  (skip-unless (fboundp 'tibetan-analysis-combined--request-synthesis))
  (let ((submitted nil))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (_thunk &rest args)
                 (setq submitted (list :label (plist-get args :label)
                                       :on-fail (plist-get args :on-fail)))
                 nil))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ((symbol-function 'gptel-request)
               (lambda (&rest _) nil)))
      (tibetan-analysis-combined--request-synthesis
       "བདག"
       (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
       "Tib trans" "Skt trans"
       nil "/tmp/seg-007.org"))
    (should submitted)
    (should (string-match-p "\\`com:" (plist-get submitted :label)))
    (should (string-match-p "seg-007" (plist-get submitted :label)))
    (should (functionp (plist-get submitted :on-fail)))))

(ert-deftest tibetan-com-request-synthesis-no-submit-when-needs-fire-false ()
  "`--request-synthesis' must not touch the queue when
`--needs-fire-p' returns nil (any required input missing)."
  (skip-unless (fboundp 'tibetan-analysis-combined--request-synthesis))
  (let ((submitted nil))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (&rest _) (setq submitted t) nil))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ((symbol-function 'gptel-request)
               (lambda (&rest _) nil)))
      ;; All four args required.  Try with each missing.
      (tibetan-analysis-combined--request-synthesis
       nil
       (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
       "T" "S" nil "/tmp/x.org")
      (tibetan-analysis-combined--request-synthesis
       "བདག" nil "T" "S" nil "/tmp/x.org")
      (tibetan-analysis-combined--request-synthesis
       "བདག"
       (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
       "" "S" nil "/tmp/x.org"))
    (should-not submitted)))

(provide 'tibetan-analysis-combined-test)
;;; tibetan-analysis-combined-test.el ends here
