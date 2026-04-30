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
parent + every parsed section."
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
        (should (string-match-p "^\\*\\* Claude Translation$" s))
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

(provide 'tibetan-analysis-sanskrit-test)
;;; tibetan-analysis-sanskrit-test.el ends here
