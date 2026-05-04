;;; tibetan-analysis-sanskrit-test.el --- Tests for Sanskrit-side Claude pipeline -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for `persist/tibetan-analysis-sanskrit.el' — the Sanskrit
;; Claude analysis pipeline introduced in Phase 2 of two-language-
;; parallel-analysis (2026-04-30).
;;
;; gptel + claude-queue are stubbed; tests run in batch with no
;; network activity.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir))
  (add-to-list 'load-path (expand-file-name "../config" dir)))

(require 'tibetan-analysis-claude)
(require 'tibetan-analysis-sanskrit)

;; ============================================================================
;; FIXTURES + HELPERS
;; ============================================================================

(defmacro tibetan-skt-test--with-source (header-text &rest body)
  "Write a source .org with HEADER-TEXT, bind SOURCE-FILE, eval BODY."
  (declare (indent 1))
  `(let ((source-file (make-temp-file "tibetan-skt-src-" nil ".org")))
     (unwind-protect
         (progn
           (with-temp-file source-file (insert ,header-text))
           ,@body)
       (when (file-exists-p source-file) (delete-file source-file)))))

(defmacro tibetan-skt-test--with-analysis (initial-content &rest body)
  "Write INITIAL-CONTENT to a temp seg-001.org, bind ANALYSIS-FILE, eval BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-skt-ana-" t))
          (analysis-file (expand-file-name "seg-001.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file analysis-file (insert ,initial-content))
           ,@body)
       (delete-directory dir t))))

(defconst tibetan-skt-test--full-response
  "## Translation
Here the bodhisattva is by nature one who delights in giving.

## Sandhi
- bodhisattvasyaivam → bodhisattvasya + evam [savarṇa-dīrgha]
- prakṛtyaiva → prakṛtyā + eva [savarṇa-dīrgha]

## Word List
- iha — adv. — \"here, in this context\"
- bodhisattvaḥ — m. nom. sg. — \"bodhisattva\"
- prakṛtyaiva — instr. sg. f. + emphatic — \"by very nature\"
- dānarucirbhavati — verb (3.sg.pres.) — \"is one who delights in giving\"

## Grammar
A nominal sentence with the copular verb `bhavati' (here in
compound `dānarucirbhavati').  `iha' fronts the topic; the
predicate noun phrase carries the `prakṛtyaiva' adverbial.  No
sandhi joints between independent words besides those listed
above.
"
  "Realistic full Sanskrit-Claude response (no Devanagari section
because the user prompt provided both IAST + Devanagari).")

(defconst tibetan-skt-test--response-with-devanagari
  "## Translation
The bodhisattva by nature delights in giving.

## Devanagari
इह बोधिसत्त्वः प्रकृत्यैव दानरुचिर्भवति

## Sandhi
- prakṛtyaiva → prakṛtyā + eva [savarṇa-dīrgha]

## Word List
- iha — adv.
- bodhisattvaḥ — m. nom. sg.

## Grammar
Brief grammar.
"
  "Sanskrit response that includes a `## Devanagari' section
\(because the user prompt provided IAST only).")

;; ============================================================================
;; build-prompts tests
;; ============================================================================

(ert-deftest tibetan-skt-build-prompts-nil-input ()
  "Nil sanskrit-plist → returns nil."
  (should (null (tibetan-analysis-sanskrit--build-prompts nil nil))))

(ert-deftest tibetan-skt-build-prompts-empty-iast ()
  "Empty `:iast' → returns nil."
  (should (null (tibetan-analysis-sanskrit--build-prompts
                 (list :iast "" :devanagari nil :script-source 'iast-line)
                 nil))))

(ert-deftest tibetan-skt-build-prompts-iast-only ()
  "IAST-only plist → returns (system . user); user has IAST,
no Devanagari line."
  (let* ((prompts (tibetan-analysis-sanskrit--build-prompts
                   (list :iast "iha bodhisattvaḥ"
                         :devanagari nil
                         :script-source 'iast-line)
                   nil))
         (system (car prompts))
         (user   (cdr prompts)))
    (should (stringp system))
    (should (stringp user))
    (should (string-match-p "iha bodhisattvaḥ" user))
    (should (string-match-p "Sanskrit passage (IAST):" user))
    ;; Devanagari-text block must NOT be added when source has no
    ;; Devanagari.  (The instruction line in the user prompt does
    ;; mention `## Devanagari' as part of Claude's output schema,
    ;; which is fine — what we check is that no actual Devanagari-
    ;; passage block was inserted.)
    (should-not (string-match-p "Sanskrit passage (Devanagari):" user))
    ;; System must announce its philologist role.
    (should (string-match-p "Sanskrit philology" system))
    (should (string-match-p "## Translation" system))
    (should (string-match-p "## Sandhi" system))
    (should (string-match-p "## Word List" system))
    (should (string-match-p "## Grammar" system))))

(ert-deftest tibetan-skt-build-prompts-devanagari-included ()
  "When `:devanagari' is non-nil, the user prompt carries both
IAST and Devanagari blocks."
  (let* ((prompts (tibetan-analysis-sanskrit--build-prompts
                   (list :iast "iha bodhisattvaḥ"
                         :devanagari "इह बोधिसत्त्वः"
                         :script-source 'iast-and-devanagari)
                   nil))
         (user (cdr prompts)))
    (should (string-match-p "Sanskrit passage (IAST):" user))
    (should (string-match-p "Sanskrit passage (Devanagari):" user))
    (should (string-match-p "इह बोधिसत्त्वः" user))))

(ert-deftest tibetan-skt-build-prompts-target-lang-german ()
  "Source with `#+TIBETAN_TARGET_LANG: de' → system carries the
German directive."
  (tibetan-skt-test--with-source
      "#+TITLE: T\n#+TIBETAN_TARGET_LANG: de\n"
    (let* ((prompts (tibetan-analysis-sanskrit--build-prompts
                     (list :iast "iha" :devanagari nil
                           :script-source 'iast-line)
                     source-file))
           (system (car prompts)))
      (should (string-match-p "GERMAN" system)))))

(ert-deftest tibetan-skt-build-prompts-handles-multiple-claude-context-headers ()
  "Regression (live test 2026-05-03 on gotrapaṭala.org seg 9):  the
prompt builder must accept a source with MULTIPLE
`#+TIBETAN_CLAUDE_CONTEXT:' header lines.  The metadata reader
returns `:claude-context' as a LIST of strings, one per header
line.  Earlier the builder passed that list directly to `concat',
which interprets each list element as a character — producing
`(error \"Wrong type argument: characterp <STRING>\")' the moment
a real source with more than zero context headers reached the
Sanskrit Claude call.  The Tibetan-side builder iterates with
`dolist'; this test asserts the Sanskrit-side builder is
similarly list-aware."
  (tibetan-skt-test--with-source
      (concat "#+TITLE: Doc\n"
              "#+SOURCE_MODE: parallel-sanskrit\n"
              "#+TIBETAN_CLAUDE_CONTEXT: First line of context.\n"
              "#+TIBETAN_CLAUDE_CONTEXT: Second line of context.\n"
              "#+TIBETAN_CLAUDE_CONTEXT: Third line of context.\n")
    (let ((prompt (tibetan-analysis-sanskrit--build-prompts
                   (list :iast "iha bodhisattvaḥ" :devanagari nil
                         :script-source 'iast-line)
                   source-file)))
      (should prompt)
      (should (consp prompt))
      (should (stringp (car prompt)))
      ;; All three context lines should appear in the system block.
      (should (string-match-p "First line of context\\."
                              (car prompt)))
      (should (string-match-p "Second line of context\\."
                              (car prompt)))
      (should (string-match-p "Third line of context\\."
                              (car prompt))))))

(ert-deftest tibetan-skt-build-prompts-system-block-stable-across-segments ()
  "Cache invariant: two `--build-prompts' calls on the same
source with DIFFERENT IAST produce byte-identical SYSTEM
prompts."
  (tibetan-skt-test--with-source
      "#+TITLE: Doc\n#+SOURCE_MODE: parallel-sanskrit\n"
    (let* ((p1 (tibetan-analysis-sanskrit--build-prompts
                (list :iast "iha" :devanagari nil
                      :script-source 'iast-line)
                source-file))
           (p2 (tibetan-analysis-sanskrit--build-prompts
                (list :iast "tatremāni" :devanagari nil
                      :script-source 'iast-line)
                source-file)))
      (should (equal (car p1) (car p2)))
      (should-not (equal (cdr p1) (cdr p2))))))

;; ============================================================================
;; parse-claude-sections tests
;; ============================================================================

(ert-deftest tibetan-skt-parse-all-five-sections ()
  "Realistic five-section response parses into all five plist keys."
  (let ((p (tibetan-analysis-sanskrit--parse-claude-sections
            tibetan-skt-test--response-with-devanagari)))
    (should (string-match-p "by nature delights"
                            (plist-get p :translation)))
    (should (string-match-p "इह बोधिसत्त्वः"
                            (plist-get p :devanagari)))
    (should (string-match-p "prakṛtyaiva"
                            (plist-get p :sandhi)))
    (should (string-match-p "bodhisattvaḥ"
                            (plist-get p :word-list)))
    (should (string-match-p "Brief grammar"
                            (plist-get p :grammar)))))

(ert-deftest tibetan-skt-parse-no-devanagari-leaves-nil ()
  "Response WITHOUT `## Devanagari' section leaves `:devanagari' nil."
  (let ((p (tibetan-analysis-sanskrit--parse-claude-sections
            tibetan-skt-test--full-response)))
    (should (null (plist-get p :devanagari)))
    (should (plist-get p :translation))))

(ert-deftest tibetan-skt-parse-empty-input ()
  "Nil / empty input returns plist with all-nil slots."
  (dolist (input '(nil ""))
    (let ((p (tibetan-analysis-sanskrit--parse-claude-sections input)))
      (should (null (plist-get p :translation)))
      (should (null (plist-get p :devanagari)))
      (should (null (plist-get p :sandhi)))
      (should (null (plist-get p :word-list)))
      (should (null (plist-get p :grammar))))))

(ert-deftest tibetan-skt-parse-word-list-key-uses-hyphen ()
  "`## Word List' (with the space) routes to `:word-list' (with
the hyphen) — special-case in the heading-key helper."
  (let ((p (tibetan-analysis-sanskrit--parse-claude-sections
            "## Word List\n- iha — adverb\n")))
    (should (string-match-p "iha" (plist-get p :word-list)))))

;; ============================================================================
;; insert-sections tests
;; ============================================================================

(ert-deftest tibetan-skt-insert-creates-parent-and-sections ()
  "Inserting into a file without `* Sanskrit Analysis' creates the
parent + every parsed section.

Phase 1.4 of layout-revision §5.18 (2026-05-04): the level-2
translation heading is `** Translation' (was `** Claude
Translation')."
  (tibetan-skt-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Auto-Analysis\n** Wylie\nbdag /\n\n* Footnotes\n"
    (tibetan-analysis-sanskrit--insert-sections
     tibetan-skt-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\* Sanskrit Analysis$" s))
        (should (string-match-p "^\\*\\* Translation$" s))
        (should-not (string-match-p "^\\*\\* Claude Translation$" s))
        (should (string-match-p "^\\*\\* Sandhi Decomposition$" s))
        (should (string-match-p "^\\*\\* Word List$" s))
        (should (string-match-p "^\\*\\* Grammar$" s))
        ;; Devanagari NOT created — response didn't include it.
        (should-not (string-match-p "^\\*\\* Devanagari$" s))
        ;; Body content present.
        (should (string-match-p "delights in giving" s))
        (should (string-match-p "savarṇa-dīrgha" s))))))

(ert-deftest tibetan-skt-insert-idempotent ()
  "Calling insert-sections twice with the same response yields the
same file content (no duplicate parents / headings / bodies)."
  (tibetan-skt-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-sanskrit--insert-sections
     tibetan-skt-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((after-first
           (with-temp-buffer (insert-file-contents analysis-file)
                             (buffer-string))))
      (tibetan-analysis-sanskrit--insert-sections
       tibetan-skt-test--full-response analysis-file)
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should (string= (buffer-string) after-first))))))

(ert-deftest tibetan-skt-insert-empty-response-no-op ()
  "Empty / nil response leaves the file untouched (no parent
created)."
  (let ((initial "* Tibetan Text\nbdag\n\n* Footnotes\n"))
    (tibetan-skt-test--with-analysis initial
      (dolist (resp '(nil "" "no headings here"))
        (tibetan-analysis-sanskrit--insert-sections resp analysis-file))
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf)))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should-not (string-match-p "^\\* Sanskrit Analysis$"
                                    (buffer-string)))))))

;; ============================================================================
;; read + restore tests
;; ============================================================================

(ert-deftest tibetan-skt-read-round-trip ()
  "insert → read returns the same translation/sandhi/word-list/grammar
bodies."
  (tibetan-skt-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-sanskrit--insert-sections
     tibetan-skt-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((p (tibetan-analysis-sanskrit--read-sections analysis-file)))
      (should (string-match-p "delights in giving"
                              (plist-get p :translation)))
      (should (string-match-p "savarṇa-dīrgha"
                              (plist-get p :sandhi)))
      (should (string-match-p "bodhisattvaḥ"
                              (plist-get p :word-list)))
      (should (string-match-p "nominal sentence"
                              (plist-get p :grammar)))
      (should (null (plist-get p :devanagari))))))

(ert-deftest tibetan-skt-restore-round-trip ()
  "read → restore → re-read preserves all four primary slots."
  (tibetan-skt-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-sanskrit--insert-sections
     tibetan-skt-test--full-response analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (let ((before (tibetan-analysis-sanskrit--read-sections
                   analysis-file)))
      (tibetan-analysis-sanskrit--restore-sections
       analysis-file
       (list :translation (plist-get before :translation)
             :sandhi      "UPDATED sandhi"
             :word-list   (plist-get before :word-list)
             :grammar     (plist-get before :grammar)))
      (let ((buf (find-buffer-visiting analysis-file)))
        (when buf
          (with-current-buffer buf (set-buffer-modified-p nil))
          (kill-buffer buf)))
      (let ((after (tibetan-analysis-sanskrit--read-sections
                    analysis-file)))
        (should (equal (plist-get after :sandhi) "UPDATED sandhi"))
        (should (string-match-p "delights in giving"
                                (plist-get after :translation)))))))

;; ============================================================================
;; Section order assertions
;; ============================================================================

(ert-deftest tibetan-skt-section-order-defconst-shape ()
  "The section-order defconst lists the five Sanskrit-side keys
at level 2."
  (let ((order tibetan-analysis-sanskrit--section-order))
    (dolist (key '(:translation :devanagari :sandhi :word-list :grammar))
      (let ((entry (assq key order)))
        (should entry)
        (should (= (nth 2 entry) 2))))))

;; ============================================================================
;; Phase 1.4 of layout-revision §5.18 (2026-05-04):
;;
;; Sanskrit-side `** Claude Translation' → `** Translation'.  Mirrors the
;; Tibetan-side rename (Phase 1.3): parent context (`* Sanskrit Analysis')
;; makes the language-attribution clear so the redundant `Claude'
;; qualifier on the level-2 heading drops.
;; ============================================================================

(ert-deftest tibetan-skt-insert-emits-translation-not-claude-translation ()
  "Phase 1.4 of layout-revision §5.18 (2026-05-04):  the Sanskrit-side
writer emits the level-2 heading `** Translation' (was `** Claude
Translation').  Section-order defconst's `:translation' slot
remains the same key — only the rendered heading string changes."
  (let* ((dir (make-temp-file "ttest-skt-1.4-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n"))
          (tibetan-analysis-sanskrit--insert-sections
           "## Translation\nSanskrit-translation-body\n\n## Word List\n- iha — adv.\n"
           file)
          (with-temp-buffer
            (insert-file-contents file)
            (let ((content (buffer-string)))
              (should (string-match-p "^\\*\\* Translation$" content))
              (should-not (string-match-p "^\\*\\* Claude Translation$"
                                          content))
              (should (string-match-p "Sanskrit-translation-body"
                                      content)))))
      (delete-directory dir t))))

(ert-deftest tibetan-skt-read-sections-falls-back-to-claude-translation ()
  "Phase 1.4 migration:  a fixture with the LEGACY `** Claude
Translation' (level 2 inside `* Sanskrit Analysis') still resolves
on `--read-sections' — the reader's `:translation' lookup chain
tries the new name first and falls back to the legacy name."
  (let* ((dir (make-temp-file "ttest-skt-1.4b-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Sanskrit Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Claude Translation\n"
                    "LEGACY-SANSKRIT-BODY\n\n"
                    "** Word List\n- iha — adv.\n\n"))
          (let ((p (tibetan-analysis-sanskrit--read-sections file)))
            (should (equal (plist-get p :translation)
                           "LEGACY-SANSKRIT-BODY"))
            (should (string-match-p "iha"
                                    (plist-get p :word-list)))))
      (delete-directory dir t))))

(ert-deftest tibetan-skt-restore-rewrites-claude-translation-as-translation ()
  "Phase 1.4 round-trip:  a fixture with the legacy `** Claude
Translation' heading is rewritten to `** Translation' on the next
`--insert-sections' run, body bytes preserved verbatim."
  (let* ((dir (make-temp-file "ttest-skt-1.4c-" t))
         (file (expand-file-name "seg-001.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Tibetan Text\nbdag\n\n"
                    "* Sanskrit Analysis\n"
                    ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                    "** Claude Translation\n"
                    "LEGACY-PRE-REWRITE\n\n"
                    "** Word List\n- old\n\n"))
          (tibetan-analysis-sanskrit--insert-sections
           "## Translation\nFRESH-TRANS\n\n## Word List\n- new\n"
           file)
          (with-temp-buffer
            (insert-file-contents file)
            (let ((content (buffer-string)))
              (should (string-match-p "^\\*\\* Translation$" content))
              (should-not (string-match-p "^\\*\\* Claude Translation$"
                                          content))
              (should (string-match-p "FRESH-TRANS" content)))))
      (delete-directory dir t))))

;; ============================================================================
;; Queue integration (concurrency optimization, 2026-04-30)
;;
;; Sanskrit + Combined calls used to bypass `tibetan-claude-queue'
;; entirely, which meant a batch of N parallel-mode segments fired
;; N simultaneous Sanskrit requests with no rate-limit safety + no
;; 429 retry.  These tests assert that `--request-translation' now
;; routes through the queue.
;; ============================================================================

(ert-deftest tibetan-skt-request-translation-uses-queue ()
  "`--request-translation' submits via `tibetan-claude-queue-submit'
\(parity with the Tibetan call's queue use)."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--request-translation))
  (let ((submitted nil))
    ;; Stub the queue-submit so we don't hit the network.
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (_thunk &rest args)
                 (setq submitted (list :label (plist-get args :label)
                                       :on-fail (plist-get args :on-fail)))
                 nil))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ;; Make `gptel-request' fboundp so the early guard passes.
              ((symbol-function 'gptel-request)
               (lambda (&rest _) nil)))
      (tibetan-analysis-sanskrit--request-translation
       (list :iast "ahaṃ" :devanagari nil :script-source 'iast-line)
       nil "/tmp/seg-001.org"))
    (should submitted)
    ;; Label carries the analysis-file basename + a `skt:' tag so
    ;; queue diagnostics distinguish Sanskrit jobs from Tibetan.
    (should (string-match-p "\\`skt:" (plist-get submitted :label)))
    (should (string-match-p "seg-001" (plist-get submitted :label)))
    (should (functionp (plist-get submitted :on-fail)))))

(ert-deftest tibetan-skt-request-translation-no-queue-submit-when-args-missing ()
  "`--request-translation' must not submit anything to the queue
when SANSKRIT-PLIST is nil / lacks IAST."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--request-translation))
  (let ((submitted nil))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (&rest _) (setq submitted t) nil))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ((symbol-function 'gptel-request)
               (lambda (&rest _) nil)))
      (tibetan-analysis-sanskrit--request-translation nil nil "/tmp/x.org")
      (tibetan-analysis-sanskrit--request-translation
       (list :iast "" :devanagari nil :script-source 'iast-line)
       nil "/tmp/x.org"))
    (should-not submitted)))

;; ============================================================================
;; Post-fire validation + retry (2026-05-04, Issue 1)
;; ============================================================================
;;
;; Live observation on gotrapaṭala segment 9 after §5.18 layout-
;; revision landed:  Sanskrit Claude returned a partial response
;; missing `## Translation' and `## Grammar' for short segments.
;; Claude collapses brevity-as-quality even after the prompt was
;; tightened to "REQUIRED — emit every time".  Belt-and-braces fix:
;; detect missing required sections in the parsed plist and fire ONE
;; focused retry asking only for the missing pieces.

(ert-deftest tibetan-skt-missing-required-sections-empty-when-all-present ()
  "All three required keys (`:translation' / `:word-list' / `:grammar')
populated → returns nil.  Conditional sections (`:devanagari' /
`:sandhi') don't enter the calculation."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--missing-required-sections))
  (let ((parsed (list :translation "T body"
                      :devanagari nil
                      :sandhi nil
                      :word-list "WL body"
                      :grammar "G body")))
    (should (null
             (tibetan-analysis-sanskrit--missing-required-sections parsed)))))

(ert-deftest tibetan-skt-missing-required-sections-detects-translation ()
  "Missing `:translation' → returned list contains `:translation'."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--missing-required-sections))
  (let ((parsed (list :translation nil
                      :word-list "WL body"
                      :grammar "G body")))
    (should
     (memq :translation
           (tibetan-analysis-sanskrit--missing-required-sections parsed)))))

(ert-deftest tibetan-skt-missing-required-sections-detects-grammar ()
  "Missing `:grammar' → returned list contains `:grammar'."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--missing-required-sections))
  (let ((parsed (list :translation "T body"
                      :word-list "WL body"
                      :grammar nil)))
    (should
     (memq :grammar
           (tibetan-analysis-sanskrit--missing-required-sections parsed)))))

(ert-deftest tibetan-skt-missing-required-sections-detects-empty-string ()
  "Empty / whitespace-only body counts as missing — guards against
Claude emitting `## Translation' followed by an empty body."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--missing-required-sections))
  (let ((parsed (list :translation "   "
                      :word-list "WL body"
                      :grammar "")))
    (let ((missing
           (tibetan-analysis-sanskrit--missing-required-sections parsed)))
      (should (memq :translation missing))
      (should (memq :grammar missing)))))

(ert-deftest tibetan-skt-missing-required-sections-ignores-conditional ()
  "Missing `:devanagari' or `:sandhi' alone → nil (they are
conditional, not required).  This is the live faithful-rendering
case where Claude correctly omits a Devanagari section."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--missing-required-sections))
  (let ((parsed (list :translation "T"
                      :devanagari nil
                      :sandhi nil
                      :word-list "WL"
                      :grammar "G")))
    (should (null
             (tibetan-analysis-sanskrit--missing-required-sections parsed)))))

(ert-deftest tibetan-skt-merge-parsed-fills-missing-from-retry ()
  "`--merge-parsed' fills a nil slot in original from the retry
response.  Retry responsible for the missing pieces; original
keeps everything it has."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--merge-parsed))
  (let* ((original (list :translation nil
                         :devanagari nil
                         :sandhi nil
                         :word-list "WL body"
                         :grammar nil))
         (retry (list :translation "T body"
                      :devanagari nil
                      :sandhi nil
                      :word-list nil
                      :grammar "G body"))
         (merged
          (tibetan-analysis-sanskrit--merge-parsed original retry)))
    (should (string= "T body" (plist-get merged :translation)))
    (should (string= "WL body" (plist-get merged :word-list)))
    (should (string= "G body" (plist-get merged :grammar)))))

(ert-deftest tibetan-skt-merge-parsed-prefers-original-when-both-present ()
  "When both original and retry populate the same slot, original
wins — retry is FILL-MISSING, not OVERWRITE.  Guards against a
verbose retry response clobbering a perfectly-good Word List from
the first try."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--merge-parsed))
  (let* ((original (list :translation "Original T"
                         :word-list "Original WL"
                         :grammar nil))
         (retry (list :translation "Retry T"
                      :word-list "Retry WL"
                      :grammar "Retry G"))
         (merged
          (tibetan-analysis-sanskrit--merge-parsed original retry)))
    (should (string= "Original T" (plist-get merged :translation)))
    (should (string= "Original WL" (plist-get merged :word-list)))
    ;; Only `:grammar' was missing in original; takes from retry.
    (should (string= "Retry G" (plist-get merged :grammar)))))

(ert-deftest tibetan-skt-build-retry-prompts-system-byte-identical ()
  "The retry's SYSTEM block is byte-identical to the first call's
SYSTEM block.  Anthropic prompt cache stays warm for the retry —
only the user-block delta is billed at full rate."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--build-retry-prompts))
  (let* ((skt-plist (list :iast "ahaṃ vadāmi" :devanagari nil
                          :script-source 'iast-line))
         (orig (tibetan-analysis-sanskrit--build-prompts skt-plist nil nil))
         (retry (tibetan-analysis-sanskrit--build-retry-prompts
                 skt-plist nil '(:translation :grammar))))
    (should retry)
    (should (string= (car orig) (car retry)))))

(ert-deftest tibetan-skt-build-retry-prompts-user-mentions-missing ()
  "The retry's USER block names the specific sections that the
first response did not emit, prefixed with `## ' so Claude sees
the heading shape it needs to produce."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--build-retry-prompts))
  (let* ((skt-plist (list :iast "ahaṃ vadāmi" :devanagari nil
                          :script-source 'iast-line))
         (retry (tibetan-analysis-sanskrit--build-retry-prompts
                 skt-plist nil '(:translation :grammar)))
         (user (cdr retry)))
    (should (string-match-p "## Translation" user))
    (should (string-match-p "## Grammar" user))
    (should-not (string-match-p "## Word List" user))))

(ert-deftest tibetan-skt-build-retry-prompts-user-includes-iast ()
  "The retry's USER block re-includes the original IAST passage so
Claude can reference it when building the missing sections."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--build-retry-prompts))
  (let* ((skt-plist (list :iast "ṣaḍ imāni dharmāḥ"
                          :devanagari nil
                          :script-source 'iast-line))
         (retry (tibetan-analysis-sanskrit--build-retry-prompts
                 skt-plist nil '(:translation))))
    (should (string-match-p "ṣaḍ imāni dharmāḥ" (cdr retry)))))

(ert-deftest tibetan-skt-build-retry-prompts-nil-when-no-missing-keys ()
  "Empty / nil missing-keys → returns nil.  No retry to fire."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--build-retry-prompts))
  (let ((skt-plist (list :iast "ahaṃ" :devanagari nil
                         :script-source 'iast-line)))
    (should (null
             (tibetan-analysis-sanskrit--build-retry-prompts
              skt-plist nil nil)))
    (should (null
             (tibetan-analysis-sanskrit--build-retry-prompts
              skt-plist nil '())))))

(ert-deftest tibetan-skt-request-translation-fires-retry-when-translation-missing ()
  "Integration:  when the first Sanskrit response is missing
`## Translation', `--request-translation' fires a SECOND
gptel-request inside the same queue thunk asking for the missing
section.  Locks the production retry path."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--fire-retry-for-missing))
  (let ((requests '())
        (queue-args nil)
        (incomplete-response
         "## Word List\n- iha — adv.\n\n")  ; missing Translation + Grammar
        (retry-response
         "## Translation\nHere…\n\n## Grammar\nNominal sentence.\n"))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (thunk &rest args)
                 (setq queue-args args)
                 ;; Run the thunk synchronously — it fires the
                 ;; gptel-request whose stub captures the call,
                 ;; then drives the retry from inside.
                 (funcall thunk (lambda (&rest _) nil))))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ((symbol-function 'gptel-request)
               (lambda (user-prompt &rest args)
                 (push (list :user user-prompt
                             :system (plist-get args :system))
                       requests)
                 ;; First call returns incomplete; second returns retry.
                 (let ((cb (plist-get args :callback))
                       (resp (if (= 1 (length requests))
                                 incomplete-response
                               retry-response)))
                   (when cb (funcall cb resp '(:status . 200)))))))
      (tibetan-skt-test--with-analysis
          "* Tibetan Text\nbdag\n\n* Footnotes\n"
        (tibetan-analysis-sanskrit--request-translation
         (list :iast "ahaṃ vadāmi" :devanagari nil
               :script-source 'iast-line)
         nil analysis-file)
        ;; Two gptel-request calls fired: original + retry.
        (should (= 2 (length requests)))
        ;; Second call's user prompt names the missing sections.
        (let ((retry-user (plist-get (car requests) :user)))
          (should (string-match-p "## Translation" retry-user))
          (should (string-match-p "## Grammar" retry-user))
          (should-not (string-match-p "## Word List" retry-user)))
        ;; Both calls used the same SYSTEM block (cache stays warm).
        (should (string=
                 (plist-get (car requests) :system)
                 (plist-get (cadr requests) :system)))
        ;; File was written with merged content (Translation + Word
        ;; List + Grammar all present).
        (let ((buf (find-buffer-visiting analysis-file)))
          (when buf
            (with-current-buffer buf (set-buffer-modified-p nil))
            (kill-buffer buf)))
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (let ((s (buffer-string)))
            (should (string-match-p "^\\* Sanskrit Analysis$" s))
            (should (string-match-p "^\\*\\* Translation$" s))
            (should (string-match-p "Here…" s))
            (should (string-match-p "^\\*\\* Word List$" s))
            (should (string-match-p "iha" s))
            (should (string-match-p "^\\*\\* Grammar$" s))
            (should (string-match-p "Nominal sentence" s))))))))

(ert-deftest tibetan-skt-request-translation-no-retry-when-response-complete ()
  "Integration:  when the first Sanskrit response includes all
three required sections, NO retry is fired."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--fire-retry-for-missing))
  (let ((requests '()))
    (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
               (lambda (thunk &rest _args)
                 (funcall thunk (lambda (&rest _) nil))))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () nil))
              ((symbol-function 'gptel-request)
               (lambda (_user-prompt &rest args)
                 (push t requests)
                 (let ((cb (plist-get args :callback)))
                   (when cb
                     (funcall cb tibetan-skt-test--full-response
                              '(:status . 200)))))))
      (tibetan-skt-test--with-analysis
          "* Tibetan Text\nbdag\n\n* Footnotes\n"
        (tibetan-analysis-sanskrit--request-translation
         (list :iast "ahaṃ vadāmi" :devanagari nil
               :script-source 'iast-line)
         nil analysis-file)
        ;; Exactly ONE gptel-request — no retry.
        (should (= 1 (length requests)))))))

(ert-deftest tibetan-skt-write-from-plist-writes-three-required ()
  "`--write-from-plist' accepts a plist directly and writes each
non-nil section.  Used by the retry-merge path after the original
+ retry plists have been merged.  Bypasses the response-string
parser."
  (skip-unless (fboundp 'tibetan-analysis-sanskrit--write-from-plist))
  (tibetan-skt-test--with-analysis
      "* Tibetan Text\nbdag\n\n* Footnotes\n"
    (tibetan-analysis-sanskrit--write-from-plist
     (list :translation "Merged T"
           :devanagari nil
           :sandhi nil
           :word-list "Merged WL"
           :grammar "Merged G")
     analysis-file)
    (let ((buf (find-buffer-visiting analysis-file)))
      (when buf
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf)))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "^\\* Sanskrit Analysis$" s))
        (should (string-match-p "^\\*\\* Translation$" s))
        (should (string-match-p "Merged T" s))
        (should (string-match-p "^\\*\\* Word List$" s))
        (should (string-match-p "Merged WL" s))
        (should (string-match-p "^\\*\\* Grammar$" s))
        (should (string-match-p "Merged G" s))))))

(provide 'tibetan-analysis-sanskrit-test)
;;; tibetan-analysis-sanskrit-test.el ends here
