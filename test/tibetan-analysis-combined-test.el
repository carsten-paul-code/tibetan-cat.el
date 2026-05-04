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
    ;; Phase 3.3 of layout-revision §5.18 (2026-05-04): the second
    ;; section is `## Sanskrit-Tibetan Comparison' (always emitted),
    ;; replacing the legacy opt-in `## Divergence'.
    (should (string-match-p "## Sanskrit-Tibetan Comparison" system))
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
  "Response with both sections parses both keys.

Phase 3.1 of layout-revision §5.18 (2026-05-04): plist key
renamed `:divergence' → `:comparison'.  The fixture's
`## Divergence' heading still routes to `:comparison' for
backwards compat with archived Claude responses."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            tibetan-com-test--full-response)))
    (should (string-match-p "Synthesis:" (plist-get p :translation)))
    (should (string-match-p "prakṛtyaiva" (plist-get p :comparison)))))

(ert-deftest tibetan-com-parse-divergence-omitted-when-faithful ()
  "Response with no Comparison section leaves `:comparison' nil."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            tibetan-com-test--no-divergence-response)))
    (should (plist-get p :translation))
    (should (null (plist-get p :comparison)))))

(ert-deftest tibetan-com-parse-empty-input ()
  "Empty / nil input returns plist with both keys nil."
  (dolist (input '(nil ""))
    (let ((p (tibetan-analysis-combined--parse-claude-sections input)))
      (should (null (plist-get p :translation)))
      (should (null (plist-get p :comparison))))))

;; ============================================================================
;; insert + read + restore round-trip
;; ============================================================================

(ert-deftest tibetan-com-insert-creates-parent-and-sections ()
  "Phase 3.2 of layout-revision §5.18 (2026-05-04):  the writer
emits `** Sanskrit-Tibetan Comparison' (was `** Divergence').
The fixture's `## Divergence' heading parses into `:comparison'
which the writer renders as the new heading."
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
        (should (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
        (should-not (string-match-p "^\\*\\* Divergence$" s))
        (should (string-match-p "Synthesis:" s))
        (should (string-match-p "prakṛtyaiva" s))))))

(ert-deftest tibetan-com-insert-skips-divergence-when-faithful ()
  "Faithful-rendering response → Combined Translation section
appears, Sanskrit-Tibetan Comparison does NOT (parser found no
matching heading in the fixture).

NOTE: Phase 3.3 of layout-revision §5.18 will change the prompt
so Claude ALWAYS emits the comparison section; this test still
exercises the writer's behaviour when the parser finds no
comparison heading."
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
        (should-not (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
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
  "Phase 3.2 of layout-revision §5.18 (2026-05-04):  `--read-sections'
returns `:comparison' (was `:divergence')."
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
      (should (string-match-p "prakṛtyaiva" (plist-get p :comparison))))))

(ert-deftest tibetan-com-restore-round-trip ()
  "Phase 3.2:  restore uses `:comparison' key; writes the body
under `** Sanskrit-Tibetan Comparison'."
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
           :comparison  "UPDATED comparison"))
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((p (tibetan-analysis-combined--read-sections analysis-file)))
      (should (equal (plist-get p :translation) "UPDATED translation"))
      (should (equal (plist-get p :comparison)  "UPDATED comparison")))))

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

;; ============================================================================
;; Phase 3 of layout-revision §5.18 (2026-05-04):
;;
;; `** Divergence' (opt-in, only when serious differences) →
;; `** Sanskrit-Tibetan Comparison' (always emitted, with explicit
;; `[Faithful — …]' marker for faithful renderings).  Plist key
;; `:divergence' is renamed to `:comparison'.  Parser accepts the
;; legacy `## Divergence' heading + the new `## Sanskrit-Tibetan
;; Comparison' / `## Comparison' headings, all routed to `:comparison'.
;; ============================================================================

(ert-deftest tibetan-com-parse-comparison-key-is-comparison-not-divergence ()
  "Phase 3.1 of layout-revision §5.18 (2026-05-04):  the parser
result plist uses `:comparison' (not `:divergence') for the
second section.  A response with the new `## Sanskrit-Tibetan
Comparison' heading populates `:comparison'."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            "## Translation\nFoo bar.\n\n## Sanskrit-Tibetan Comparison\n[Faithful — close.]\n")))
    (should (equal (plist-get p :translation) "Foo bar."))
    (should (equal (plist-get p :comparison) "[Faithful — close.]"))
    ;; Old key is gone.
    (should (null (plist-get p :divergence)))))

(ert-deftest tibetan-com-parse-divergence-legacy-heading-still-recognised-as-comparison ()
  "Phase 3.1 backwards compat:  a response with the LEGACY
`## Divergence' heading routes to the NEW `:comparison' plist
key.  Lets archived Claude responses round-trip during the
soft-migration window."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            "## Translation\nFoo.\n\n## Divergence\n- legacy bullet\n")))
    (should (equal (plist-get p :translation) "Foo."))
    (should (equal (plist-get p :comparison) "- legacy bullet"))
    (should (null (plist-get p :divergence)))))

(ert-deftest tibetan-com-parse-recognises-bare-comparison-heading ()
  "Phase 3.1:  the parser accepts the bare `## Comparison' heading
\(in addition to `## Sanskrit-Tibetan Comparison').  Defensive
against Claude shortening the heading occasionally."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            "## Translation\nFoo.\n\n## Comparison\nBar.\n")))
    (should (equal (plist-get p :comparison) "Bar."))))

(ert-deftest tibetan-com-parse-faithful-marker-treated-as-content-not-empty ()
  "Phase 3.1:  a `[Faithful — …]' single-line body is treated as
real content, not stripped as empty.  This is the marker the
new prompt asks for when the Tibetan closely renders the
Sanskrit."
  (let ((p (tibetan-analysis-combined--parse-claude-sections
            "## Translation\nFoo.\n\n## Sanskrit-Tibetan Comparison\n[Faithful — Tibetan closely renders the Sanskrit; no significant differences.]\n")))
    (should (plist-get p :comparison))
    (should (string-match-p "\\`\\[Faithful" (plist-get p :comparison)))))

(ert-deftest tibetan-com-build-prompts-system-mentions-comparison-always-emit ()
  "Phase 3.3 of layout-revision §5.18 (2026-05-04):  the Combined
system prompt explicitly directs Claude to ALWAYS emit the
Comparison section.  This is the prompt-side change that pairs
with the parser/writer rename in Phase 3.1+3.2.

The new directive includes the literal phrase `Always emit'
near the `Sanskrit-Tibetan Comparison' heading."
  (skip-unless (fboundp 'tibetan-analysis-combined--build-prompts))
  (tibetan-com-test--with-source
      "#+TITLE: Doc\n#+SOURCE_MODE: parallel-sanskrit\n"
    (let ((prompt (tibetan-analysis-combined--build-prompts
                   "བདག"
                   '(:iast "ahaṃ" :devanagari nil :script-source iast-line)
                   "I (Tib)" "I (Skt)" source-file)))
      (should prompt)
      (let ((system (car prompt)))
        (should (string-match-p "Always emit" system))
        (should (string-match-p "Sanskrit-Tibetan Comparison" system))))))

(ert-deftest tibetan-com-build-prompts-system-no-longer-says-only-when-serious ()
  "Phase 3.3:  the Combined system prompt no longer carries the
opt-in phrase `ONLY when there is a SERIOUS' that gated emission
on serious differences."
  (skip-unless (fboundp 'tibetan-analysis-combined--build-prompts))
  (tibetan-com-test--with-source
      "#+TITLE: Doc\n#+SOURCE_MODE: parallel-sanskrit\n"
    (let ((prompt (tibetan-analysis-combined--build-prompts
                   "བདག"
                   '(:iast "ahaṃ" :devanagari nil :script-source iast-line)
                   "T" "S" source-file)))
      (should prompt)
      (let ((system (car prompt)))
        (should-not (string-match-p "ONLY when there is a SERIOUS" system))))))

(ert-deftest tibetan-com-build-prompts-system-mentions-faithful-marker ()
  "Phase 3.3:  the system prompt names the canonical faithful-case
marker text `[Faithful' so Claude emits a stable phrase the
reader can scan for at a glance."
  (skip-unless (fboundp 'tibetan-analysis-combined--build-prompts))
  (tibetan-com-test--with-source
      "#+TITLE: Doc\n#+SOURCE_MODE: parallel-sanskrit\n"
    (let ((prompt (tibetan-analysis-combined--build-prompts
                   "བདག"
                   '(:iast "ahaṃ" :devanagari nil :script-source iast-line)
                   "T" "S" source-file)))
      (should prompt)
      (let ((system (car prompt)))
        (should (string-match-p "\\[Faithful" system))))))

(ert-deftest tibetan-com-section-order-uses-comparison-heading ()
  "Phase 3.2 of layout-revision §5.18 (2026-05-04):  the
section-order defconst maps `:comparison' to the heading
`Sanskrit-Tibetan Comparison' at level 2.  The legacy
`:divergence' / `Divergence' entry is gone."
  (let ((order tibetan-analysis-combined--section-order))
    (should (equal (assq :comparison order)
                   '(:comparison "Sanskrit-Tibetan Comparison" 2)))
    (should (null (assq :divergence order)))
    (should (equal (assq :translation order)
                   '(:translation "Combined Translation" 2)))))

(ert-deftest tibetan-com-insert-emits-comparison-heading-not-divergence ()
  "Phase 3.2:  on a fresh fixture, the writer emits the new
`** Sanskrit-Tibetan Comparison' heading (not legacy
`** Divergence')."
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     "## Translation\nFoo.\n\n## Sanskrit-Tibetan Comparison\nBar.\n"
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
        (should-not (string-match-p "^\\*\\* Divergence$" s))))))

(ert-deftest tibetan-com-restore-migrates-old-divergence-heading ()
  "Phase 3.2 on-disk migration:  a fixture with the LEGACY
`** Divergence' heading inside `* Combined Analysis' is
rewritten to `** Sanskrit-Tibetan Comparison' on the next
`--insert-sections' run, body bytes preserved."
  (tibetan-com-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Combined Analysis\n"
              ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
              "** Combined Translation\nold trans\n\n"
              "** Divergence\n- LEGACY-DIV-BODY\n\n"
              "* Footnotes\n")
    (tibetan-analysis-combined--insert-sections
     "## Translation\nNEW-TRANS\n\n## Sanskrit-Tibetan Comparison\nNEW-COMP\n"
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
        (should-not (string-match-p "^\\*\\* Divergence$" s))
        (should (string-match-p "NEW-COMP" s))
        (should (string-match-p "NEW-TRANS" s))))))

(ert-deftest tibetan-com-read-sections-fallback-reads-divergence-as-comparison ()
  "Phase 3.2 backwards-compat read:  a fixture with the legacy
`** Divergence' (and no new heading) is resolved by
`--read-sections' as `:comparison'.  Lets pre-rename files
round-trip."
  (tibetan-com-test--with-analysis
      (concat "* Tibetan Text\nbdag\n\n"
              "* Combined Analysis\n"
              ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
              "** Combined Translation\ntranslation body\n\n"
              "** Divergence\nLEGACY-DIV\n\n"
              "* Footnotes\n")
    (let ((p (tibetan-analysis-combined--read-sections analysis-file)))
      (should (equal (plist-get p :translation) "translation body"))
      (should (equal (plist-get p :comparison) "LEGACY-DIV")))))

(ert-deftest tibetan-com-end-to-end-faithful-response-writes-comparison-section ()
  "Phase 3.4 of layout-revision §5.18 (2026-05-04):  end-to-end
exercise of the wired-up surface — a faithful Claude response
including the new `## Sanskrit-Tibetan Comparison' heading with
a `[Faithful — …]' marker round-trips through `--insert-sections'
and lands in the analysis file under
`** Sanskrit-Tibetan Comparison'."
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     (concat "## Translation\n"
             "What is the support?  Here, a bodhisattva's own lineage.\n\n"
             "## Sanskrit-Tibetan Comparison\n"
             "[Faithful — Tibetan closely renders the Sanskrit; "
             "no significant differences.]\n")
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
        (should (string-match-p "\\[Faithful" s))
        (should (string-match-p "no significant differences" s))))))

(ert-deftest tibetan-com-end-to-end-divergent-response-writes-bullets ()
  "Phase 3.4:  a divergent response with bulleted divergences
under `## Sanskrit-Tibetan Comparison' round-trips intact (the
writer doesn't strip the bullet structure)."
  (tibetan-com-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-combined--insert-sections
     (concat "## Translation\n"
             "Combined synthesis.\n\n"
             "## Sanskrit-Tibetan Comparison\n"
             "- Sanskrit *gotra*: rendered as Tibetan rigs (lineage).\n"
             "- Sanskrit *cittotpāda*: Tibetan expands to "
             "sems bskyed pa (bodhicitta-arousal).\n")
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\*\\* Sanskrit-Tibetan Comparison$" s))
        (should (string-match-p "Sanskrit \\*gotra\\*" s))
        (should (string-match-p "bodhicitta-arousal" s))
        ;; No `[Faithful' marker — divergent case.
        (should-not (string-match-p "\\[Faithful" s))))))

(provide 'tibetan-analysis-combined-test)
;;; tibetan-analysis-combined-test.el ends here
