;;; tibetan-sanskrit-parallel-dharmamitra-test.el --- Tests for DharmaMitra alignment orchestration -*- lexical-binding: t -*-

;;; Commentary:
;;
;; ERT tests for `core/tibetan-sanskrit-parallel-dharmamitra.el' —
;; the per-segment alignment orchestrator that drives the
;; dharmamitra-realign workflow.  Phase 2 of the workflow
;; (2026-04-27).
;;
;; Test strategy: stub `tibetan-dharmamitra-api-chat-translate' and
;; `tibetan-dharmamitra-api-search' so no network calls happen;
;; verify the orchestrator threads inputs correctly, calls each
;; primitive once, shapes results, and returns nil on failures.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-dharmamitra-api)
(require 'tibetan-sanskrit-parallel-dharmamitra)

;; ============================================================================
;; FIXTURE HELPERS
;; ============================================================================

(defmacro tibetan-skt-dm-test--with-source-file (contents &rest body)
  "Write CONTENTS to a temp source.org and bind SOURCE-FILE for BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-skt-dm-" t))
          (source-file (expand-file-name "source.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file source-file (insert ,contents))
           ,@body)
       (delete-directory dir t))))

(defun tibetan-skt-dm-test--canonical-search-results ()
  "Return a small list of fake search-result alists for stubs."
  (list
   '((id . "SA_T06_bsa034:64")
     (lang . "sa")
     (source . "SA_T06_bsa034")
     (text . "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati")
     (segmentnr . "SA_T06_bsa034:64")
     (title . "Asaṅga: Bodhisattvabhūmi"))
   '((id . "SA_T06_bsa034:221")
     (lang . "sa")
     (source . "SA_T06_bsa034")
     (text . "evamayaṃ prathamaścittotpādaḥ")
     (segmentnr . "SA_T06_bsa034:221")
     (title . "Asaṅga: Bodhisattvabhūmi"))
   '((id . "SA_T06_bsa034:189")
     (lang . "sa")
     (source . "SA_T06_bsa034")
     (text . "third candidate text")
     (segmentnr . "SA_T06_bsa034:189")
     (title . "Asaṅga: Bodhisattvabhūmi"))))

;; ============================================================================
;; ORCHESTRATION — happy path
;; ============================================================================

(ert-deftest tibetan-skt-dm-candidates-translates-then-searches ()
  "Calls `chat-translate' once with the Tibetan, then `search' once
with the translation as input.  Returns a non-nil candidate
list."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let ((tx-calls 0) (sr-calls 0))
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _)
             (cl-incf tx-calls)
             "In this way, a Bodhisattva inclines toward giving."))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (&rest _)
             (cl-incf sr-calls)
             (tibetan-skt-dm-test--canonical-search-results))))
       (let ((cands (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                     "བདག་" source-file)))
         (should (= tx-calls 1))
         (should (= sr-calls 1))
         (should (listp cands))
         (should (> (length cands) 0)))))))

(ert-deftest tibetan-skt-dm-candidates-passes-tibetan-to-translate ()
  "The Tibetan input flows through to the chat-translate call."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let (captured-text)
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (text &rest _)
             (setq captured-text text)
             "English translation"))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (&rest _)
             (tibetan-skt-dm-test--canonical-search-results))))
       (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
        "བདག་གིས་ལས་བྱས།" source-file)
       (should (equal captured-text "བདག་གིས་ལས་བྱས།"))))))

(ert-deftest tibetan-skt-dm-candidates-passes-translation-to-search ()
  "The English translation from chat-translate becomes the search
input — that's how the cross-language alignment works."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let (captured-search-input)
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _)
             "Translated English query"))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (input &rest _)
             (setq captured-search-input input)
             (tibetan-skt-dm-test--canonical-search-results))))
       (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
        "བདག་" source-file)
       (should (equal captured-search-input "Translated English query"))))))

(ert-deftest tibetan-skt-dm-candidates-uses-dm-sanskrit-source-from-headers ()
  "The `:include-files' arg to `search' is taken from
`#+DM_SANSKRIT_SOURCE:'.  Crucial: the realign command must
NEVER search the whole DM corpus — only the configured target
work.  Otherwise we'd get high-rank hits from prajñāpāramitā
literature instead of the Bodhisattvabhūmi parallel."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let (captured-include-files captured-source-lang)
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _) "x"))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (_input &rest args)
             (setq captured-include-files (plist-get args :include-files))
             (setq captured-source-lang (plist-get args :source-lang))
             (tibetan-skt-dm-test--canonical-search-results))))
       (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
        "བདག་" source-file)
       (should (member "SA_T06_bsa034" captured-include-files))
       (should (equal captured-source-lang "sa"))))))

;; ============================================================================
;; ORCHESTRATION — result shape
;; ============================================================================

(ert-deftest tibetan-skt-dm-candidates-shapes-results-as-plists ()
  "Each candidate is a plist with `:id', `:text', `:segmentnr',
`:title', `:rank' keys.  The original alist form from the search
API is opaque to downstream callers — they consume the shaped
plist."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (cl-letf
       (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
         (lambda (&rest _) "x"))
        ((symbol-function 'tibetan-dharmamitra-api-search)
         (lambda (&rest _)
           (tibetan-skt-dm-test--canonical-search-results))))
     (let* ((cands (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                    "བདག་" source-file))
            (first (car cands)))
       (should first)
       (should (equal (plist-get first :id) "SA_T06_bsa034:64"))
       (should (equal (plist-get first :text)
                      "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati"))
       (should (equal (plist-get first :segmentnr) "SA_T06_bsa034:64"))
       (should (equal (plist-get first :title) "Asaṅga: Bodhisattvabhūmi"))
       (should (= (plist-get first :rank) 1))))))

(ert-deftest tibetan-skt-dm-candidates-rank-is-1-based-and-monotonic ()
  "Rank 1 is the top hit; rank N for the Nth element in the
ordered search response."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (cl-letf
       (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
         (lambda (&rest _) "x"))
        ((symbol-function 'tibetan-dharmamitra-api-search)
         (lambda (&rest _)
           (tibetan-skt-dm-test--canonical-search-results))))
     (let ((cands (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                   "བདག་" source-file)))
       (should (= (plist-get (nth 0 cands) :rank) 1))
       (should (= (plist-get (nth 1 cands) :rank) 2))
       (should (= (plist-get (nth 2 cands) :rank) 3))))))

(ert-deftest tibetan-skt-dm-candidates-respects-max-candidates ()
  "`:max-candidates' caps the result list length even when search
returns more hits.  Default is 5; explicit smaller value
truncates."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (cl-letf
       (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
         (lambda (&rest _) "x"))
        ((symbol-function 'tibetan-dharmamitra-api-search)
         (lambda (&rest _)
           (tibetan-skt-dm-test--canonical-search-results))))  ; 3 hits
     (let ((cands (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                   "བདག་" source-file :max-candidates 2)))
       (should (= (length cands) 2))))))

;; ============================================================================
;; ORCHESTRATION — failure modes
;; ============================================================================

(ert-deftest tibetan-skt-dm-candidates-nil-when-no-dm-source-header ()
  "Without `#+DM_SANSKRIT_SOURCE:' the orchestrator returns nil
WITHOUT calling either API.  We can't proceed without a target
work — searching the whole corpus is wasteful and meaningless
for alignment."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n"  ;; no DM_SANSKRIT_SOURCE
   (let ((tx-calls 0) (sr-calls 0))
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _) (cl-incf tx-calls) "x"))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (&rest _) (cl-incf sr-calls) nil)))
       (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                      "བདག་" source-file)))
       (should (= tx-calls 0))
       (should (= sr-calls 0))))))

(ert-deftest tibetan-skt-dm-candidates-nil-when-translate-fails ()
  "When chat-translate returns nil (HTTP error / empty response),
the orchestrator returns nil WITHOUT calling search.  No point
searching with a missing query."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let ((sr-calls 0))
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _) nil))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (&rest _) (cl-incf sr-calls)
             (tibetan-skt-dm-test--canonical-search-results))))
       (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                      "བདག་" source-file)))
       (should (= sr-calls 0))))))

(ert-deftest tibetan-skt-dm-candidates-nil-when-search-fails ()
  "When search returns nil, orchestrator returns nil."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (cl-letf
       (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
         (lambda (&rest _) "x"))
        ((symbol-function 'tibetan-dharmamitra-api-search)
         (lambda (&rest _) nil)))
     (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                    "བདག་" source-file))))))

(ert-deftest tibetan-skt-dm-candidates-nil-when-source-file-missing ()
  "Nil / nonexistent SOURCE-FILE returns nil without crashing."
  (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                 "བདག་" nil)))
  (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                 "བདག་" "/nonexistent/path.org"))))

(ert-deftest tibetan-skt-dm-candidates-nil-when-tibetan-empty ()
  "Empty Tibetan input returns nil — no point translating an
empty string."
  (tibetan-skt-dm-test--with-source-file
   "#+TITLE: T\n#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n"
   (let ((tx-calls 0))
     (cl-letf
         (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
           (lambda (&rest _) (cl-incf tx-calls) "x"))
          ((symbol-function 'tibetan-dharmamitra-api-search)
           (lambda (&rest _)
             (tibetan-skt-dm-test--canonical-search-results))))
       (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                      "" source-file)))
       (should (null (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                      nil source-file)))
       (should (= tx-calls 0))))))

;; ============================================================================
;; PHASE 3 — Claude disambiguation among DM candidates
;; ============================================================================
;;
;; When DharmaMitra returns 3+ candidates for a Tibetan segment,
;; semantic-search rank does not always pick the right parallel
;; (probed: rank 2 was the correct match for our test query, rank 1
;; was thematically related but topically wrong).  Phase 3 layers
;; Claude on top: given Tibetan + N candidate plists, ask Claude to
;; identify the actual parallel.  Falls back to top candidate when
;; Claude is unavailable.
;;
;; Tests stub `tibetan-sanskrit-parallel-dm--ask-claude-sync' so no
;; gptel / network is touched.  The prompt builder and response
;; parser are pure functions, separately exercised.

(defun tibetan-skt-dm-test--three-candidates ()
  "Return three pre-shaped candidate plists for Phase 3 stubs."
  (list
   (list :id "SA_T06_bsa034:64"
         :text "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati"
         :segmentnr "SA_T06_bsa034:64"
         :title "Asaṅga: Bodhisattvabhūmi"
         :rank 1)
   (list :id "SA_T06_bsa034:221"
         :text "evamayaṃ prathamaścittotpādaḥ"
         :segmentnr "SA_T06_bsa034:221"
         :title "Asaṅga: Bodhisattvabhūmi"
         :rank 2)
   (list :id "SA_T06_bsa034:189"
         :text "third unrelated"
         :segmentnr "SA_T06_bsa034:189"
         :title "Asaṅga: Bodhisattvabhūmi"
         :rank 3)))

;; ----------------------------------------------------------------------------
;; Prompt builder (pure function)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-build-claude-pick-prompt-includes-tibetan ()
  "Prompt carries the Tibetan passage verbatim."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-claude-pick-prompt))
  (let* ((tib "བདག་གིས་ལས་བྱས།")
         (cands (tibetan-skt-dm-test--three-candidates))
         (prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                  tib cands)))
    (should (string-match-p (regexp-quote tib) prompt))))

(ert-deftest tibetan-skt-dm-build-claude-pick-prompt-includes-all-candidates ()
  "Prompt enumerates every candidate (text and rank)."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-claude-pick-prompt))
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                  "བདག་" cands)))
    (should (string-match-p "iha bodhisattvaḥ prakṛtyaiva" prompt))
    (should (string-match-p "evamayaṃ prathamaścittotpādaḥ" prompt))
    (should (string-match-p "third unrelated" prompt))
    (should (string-match-p "Rank 1" prompt))
    (should (string-match-p "Rank 2" prompt))
    (should (string-match-p "Rank 3" prompt))))

(ert-deftest tibetan-skt-dm-build-claude-pick-prompt-asks-for-structured-response ()
  "Prompt instructs Claude to use the `## Choice' / `## Reason'
schema so the parser can extract a deterministic answer."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-claude-pick-prompt))
  (let ((prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                 "བདག་" (tibetan-skt-dm-test--three-candidates))))
    (should (string-match-p "## Choice" prompt))
    (should (string-match-p "## Reason" prompt))))

;; ----------------------------------------------------------------------------
;; Response parser (pure function)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-parse-claude-pick-response-extracts-rank ()
  "Parser extracts a rank integer from `## Choice\\nN'."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--parse-claude-pick-response))
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (response "## Choice\n2\n\n## Reason\nMatches the verb prakṛtyaiva.")
         (parsed (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                  response cands)))
    (should parsed)
    (should (= (plist-get parsed :chosen-rank) 2))
    (should (string-match-p "prakṛtyaiva" (plist-get parsed :reason)))))

(ert-deftest tibetan-skt-dm-parse-claude-pick-response-tolerates-leading-whitespace ()
  "Parser handles whitespace around the rank number."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--parse-claude-pick-response))
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (parsed (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                  "## Choice\n  3  \n\n## Reason\nfoo" cands)))
    (should (= (plist-get parsed :chosen-rank) 3))))

(ert-deftest tibetan-skt-dm-parse-claude-pick-response-rejects-out-of-range-rank ()
  "Parser returns nil when the rank exceeds the candidate count.
Caller will fall back to top candidate."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--parse-claude-pick-response))
  (let ((cands (tibetan-skt-dm-test--three-candidates)))  ;; 3 cands
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 "## Choice\n99\n\n## Reason\nfoo" cands))
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 "## Choice\n0\n\n## Reason\nfoo" cands))))

(ert-deftest tibetan-skt-dm-parse-claude-pick-response-malformed-returns-nil ()
  "Garbage / missing `## Choice' → nil."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--parse-claude-pick-response))
  (let ((cands (tibetan-skt-dm-test--three-candidates)))
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 "no headings here just prose" cands))
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 "## Choice\nnot-a-number" cands))
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 nil cands))
    (should-not (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                 "" cands))))

;; ----------------------------------------------------------------------------
;; Public claude-pick — happy path
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-claude-pick-returns-shaped-plist ()
  "Given Tibetan + candidates + stubbed Claude returning rank 2,
returns a plist `(:chosen-id :chosen-text :chosen-rank :reason)'
sourced from the matching candidate."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_prompt)
               "## Choice\n2\n\n## Reason\nVerb matches.")))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should out)
      (should (equal (plist-get out :chosen-id) "SA_T06_bsa034:221"))
      (should (equal (plist-get out :chosen-text)
                     "evamayaṃ prathamaścittotpādaḥ"))
      (should (= (plist-get out :chosen-rank) 2))
      (should (string-match-p "Verb matches" (plist-get out :reason))))))

(ert-deftest tibetan-skt-dm-claude-pick-single-candidate-skips-claude ()
  "A single candidate needs no disambiguation — return it directly
without calling Claude."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (let ((claude-calls 0))
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
               (lambda (_prompt)
                 (cl-incf claude-calls)
                 "should not be called")))
      (let* ((single (list (car (tibetan-skt-dm-test--three-candidates))))
             (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" single)))
        (should out)
        (should (equal (plist-get out :chosen-id) "SA_T06_bsa034:64"))
        (should (= (plist-get out :chosen-rank) 1))
        (should (string-match-p "single" (plist-get out :reason)))
        (should (= claude-calls 0))))))

;; ----------------------------------------------------------------------------
;; Public claude-pick — fallbacks
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-claude-pick-nil-when-no-candidates ()
  "Empty candidates list returns nil (caller treated as failure)."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (should (null (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" nil)))
  (should (null (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" '()))))

(ert-deftest tibetan-skt-dm-claude-pick-falls-back-to-top-when-claude-unavailable ()
  "When Claude returns nil (gptel missing, HTTP failure), fall back
to the top candidate (rank 1).  The `:reason' field stamps the
fallback path so the dry-run preview can display it."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_prompt) nil)))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should out)
      (should (= (plist-get out :chosen-rank) 1))
      (should (equal (plist-get out :chosen-id) "SA_T06_bsa034:64"))
      ;; Reason flags the fallback path explicitly.
      (should (string-match-p "claude-unavailable" (plist-get out :reason))))))

(ert-deftest tibetan-skt-dm-claude-pick-falls-back-when-response-unparseable ()
  "When Claude returns a non-empty string the parser can't extract
a rank from, fall back to top with a different stamp."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_prompt) "I am unable to choose. Sorry.")))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should out)
      (should (= (plist-get out :chosen-rank) 1))
      (should (string-match-p "unparseable" (plist-get out :reason))))))

(ert-deftest tibetan-skt-dm-claude-pick-falls-back-when-rank-out-of-range ()
  "Claude says `## Choice\\n99' but only 3 candidates exist → top
candidate fallback."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_prompt) "## Choice\n99\n\n## Reason\nout-of-range")))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should out)
      (should (= (plist-get out :chosen-rank) 1))
      (should (string-match-p "unparseable" (plist-get out :reason))))))

(ert-deftest tibetan-skt-dm-claude-pick-prompt-flows-through-to-claude ()
  "The Tibetan + candidates reach the Claude wrapper — verifies the
prompt is built and passed, not silently dropped."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-claude-pick))
  (let (captured-prompt)
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
               (lambda (prompt)
                 (setq captured-prompt prompt)
                 "## Choice\n1\n\n## Reason\ndefault")))
      (tibetan-sanskrit-parallel-dm-claude-pick
       "བདག་གིས་ལས་བྱས།" (tibetan-skt-dm-test--three-candidates))
      (should captured-prompt)
      (should (string-match-p (regexp-quote "བདག་གིས་ལས་བྱས།") captured-prompt))
      (should (string-match-p "iha bodhisattvaḥ prakṛtyaiva" captured-prompt)))))

;; ============================================================================
;; PHASE 4 — Proposal builder + document walker + preview renderer (read-only)
;; ============================================================================
;;
;; Per-segment proposal pipeline:
;;   1. Read (Tibetan, current Sanskrit) for segment-id N.
;;   2. Run Phase 2 (candidates) → Phase 3 (claude-pick).
;;   3. Build a proposal plist comparing current vs proposed.
;; Document walker iterates segments, collects proposals.
;; Preview renderer formats the proposals into a `*Sanskrit
;; Realign Preview*' buffer the user reviews before applying.
;;
;; Phase 4 is read-only — proposals are computed and rendered, no
;; writes happen.  Phase 5 ships the apply mode + interactive
;; commands + keybindings.

(defmacro tibetan-skt-dm-test--with-source-file-multi-segment (&rest body)
  "Write a multi-segment temp source file and bind SOURCE-FILE.
The source has two segments with `**** Sanskrit' siblings, used
by document-walker / segment-data tests."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "tibetan-skt-dm-multi-" t))
          (source-file (expand-file-name "source.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file source-file
             (insert "#+TITLE: Test\n"
                     "#+SOURCE_MODE: parallel-sanskrit\n"
                     "#+DM_SANSKRIT_SOURCE: SA_T06_bsa034\n\n"
                     "* Tibetan Text\n"
                     "** Section 1\n"
                     "*** Sentence 1\n"
                     "**** Segment 1\n"
                     "བདག་གིས་ལས་བྱས།\n\n"
                     "**** Sanskrit\n"
                     "current sanskrit one\n\n"
                     "*** Sentence 2\n"
                     "**** Segment 2\n"
                     "ཁྱོད་ཀྱིས་ཤེས་ཀྱི།\n\n"
                     "**** Sanskrit\n"
                     "current sanskrit two\n\n"))
           ,@body)
       (delete-directory dir t))))

;; ----------------------------------------------------------------------------
;; segment-data-for-id (in core/tibetan-sanskrit-parallel.el)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-segment-data-for-id-returns-tibetan-and-sanskrit ()
  "Given SOURCE-FILE + SEG-ID, return a plist with the segment's
Tibetan body and Sanskrit sibling text."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-segment-data-for-id))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (let ((data (tibetan-sanskrit-parallel-segment-data-for-id source-file 1)))
     (should data)
     (should (string-match-p "བདག་གིས་ལས་བྱས" (plist-get data :tibetan)))
     (should (string-match-p "current sanskrit one"
                             (plist-get data :current-sanskrit))))))

(ert-deftest tibetan-skt-segment-data-for-id-second-segment ()
  "Walker resolves segment 2 too — not just the first."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-segment-data-for-id))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (let ((data (tibetan-sanskrit-parallel-segment-data-for-id source-file 2)))
     (should data)
     (should (string-match-p "ཁྱོད་ཀྱིས་ཤེས" (plist-get data :tibetan)))
     (should (string-match-p "current sanskrit two"
                             (plist-get data :current-sanskrit))))))

(ert-deftest tibetan-skt-segment-data-for-id-nil-when-segment-missing ()
  "Return nil for an out-of-range segment ID without crashing."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-segment-data-for-id))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (should (null (tibetan-sanskrit-parallel-segment-data-for-id
                  source-file 99)))))

;; ----------------------------------------------------------------------------
;; build-proposal (pure function)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-build-proposal-status-change-when-different ()
  "Current vs proposed differ → :status 'change, plist carries
both old and new."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-proposal))
  (let* ((pick (list :chosen-id "SA_T06_bsa034:64"
                     :chosen-text "iha bodhisattvaḥ"
                     :chosen-rank 1
                     :reason "verb match"))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་" "old wrong sanskrit" pick)))
    (should p)
    (should (eq (plist-get p :status) 'change))
    (should (= (plist-get p :seg-id) 5))
    (should (equal (plist-get p :tibetan-text) "བདག་"))
    (should (equal (plist-get p :current-sanskrit) "old wrong sanskrit"))
    (should (equal (plist-get p :proposed-sanskrit) "iha bodhisattvaḥ"))
    (should (= (plist-get p :proposed-rank) 1))
    (should (equal (plist-get p :proposed-segmentnr) "SA_T06_bsa034:64"))
    (should (string-match-p "verb match" (plist-get p :reason)))))

(ert-deftest tibetan-skt-dm-build-proposal-status-unchanged-when-equal ()
  "Current matches proposed (after whitespace normalisation) →
:status 'unchanged."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-proposal))
  (let* ((pick (list :chosen-id "X" :chosen-text "iha bodhisattvaḥ"
                     :chosen-rank 1 :reason ""))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་" "iha bodhisattvaḥ" pick)))
    (should (eq (plist-get p :status) 'unchanged))))

(ert-deftest tibetan-skt-dm-build-proposal-status-unchanged-tolerates-whitespace ()
  "Current vs proposed differ only in trailing whitespace /
internal spacing → still 'unchanged.  Avoids spurious change
proposals from formatting noise."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-proposal))
  (let* ((pick (list :chosen-id "X"
                     :chosen-text "iha bodhisattvaḥ prakṛtyaiva"
                     :chosen-rank 1 :reason ""))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་"
             "  iha bodhisattvaḥ   prakṛtyaiva\n  "
             pick)))
    (should (eq (plist-get p :status) 'unchanged))))

(ert-deftest tibetan-skt-dm-build-proposal-status-no-candidates-when-pick-nil ()
  "Pick is nil (no DM candidates returned) → :status 'no-candidates,
proposed-sanskrit nil."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--build-proposal))
  (let ((p (tibetan-sanskrit-parallel-dm--build-proposal
            5 "བདག་" "current" nil)))
    (should p)
    (should (eq (plist-get p :status) 'no-candidates))
    (should (null (plist-get p :proposed-sanskrit)))))

;; ----------------------------------------------------------------------------
;; realign-document-proposals (orchestration)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-realign-document-walks-all-segments ()
  "Document walker yields one proposal per segment.  The two-
segment fixture should yield exactly two proposals."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-realign-document-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (cl-letf
       (((symbol-function 'tibetan-sanskrit-parallel-dm-candidates-for-tibetan)
         (lambda (tibetan _src &rest _)
           (list (list :id (concat "SA:" tibetan)
                       :text (concat "proposed for " tibetan)
                       :segmentnr "SA:N"
                       :title "BSA"
                       :rank 1))))
        ((symbol-function 'tibetan-sanskrit-parallel-dm-claude-pick)
         (lambda (_tib cands)
           (let ((c (car cands)))
             (list :chosen-id (plist-get c :id)
                   :chosen-text (plist-get c :text)
                   :chosen-rank (plist-get c :rank)
                   :reason "test")))))
     (let ((props (tibetan-sanskrit-parallel-dm-realign-document-proposals
                   source-file)))
       (should (listp props))
       (should (= (length props) 2))
       (should (= (plist-get (nth 0 props) :seg-id) 1))
       (should (= (plist-get (nth 1 props) :seg-id) 2))))))

(ert-deftest tibetan-skt-dm-realign-document-marks-status-correctly ()
  "Walker tags each proposal's status based on current vs
proposed comparison.  Segment 1's current Sanskrit
\"current sanskrit one\" doesn't match the stub's
\"proposed for ...\" → 'change."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-realign-document-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (cl-letf
       (((symbol-function 'tibetan-sanskrit-parallel-dm-candidates-for-tibetan)
         (lambda (_tib _src &rest _)
           (list (list :id "X" :text "different" :segmentnr "Y"
                       :title "BSA" :rank 1))))
        ((symbol-function 'tibetan-sanskrit-parallel-dm-claude-pick)
         (lambda (_tib cands)
           (let ((c (car cands)))
             (list :chosen-id (plist-get c :id)
                   :chosen-text (plist-get c :text)
                   :chosen-rank (plist-get c :rank)
                   :reason "")))))
     (let ((props (tibetan-sanskrit-parallel-dm-realign-document-proposals
                   source-file)))
       (should (eq (plist-get (nth 0 props) :status) 'change))
       (should (eq (plist-get (nth 1 props) :status) 'change))))))

(ert-deftest tibetan-skt-dm-realign-document-handles-pipeline-failure ()
  "If candidates-for-tibetan returns nil (translate failure / no
DM source / etc.), the proposal carries status 'no-candidates
and the walker continues to the next segment."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm-realign-document-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (cl-letf
       (((symbol-function 'tibetan-sanskrit-parallel-dm-candidates-for-tibetan)
         (lambda (&rest _) nil))
        ((symbol-function 'tibetan-sanskrit-parallel-dm-claude-pick)
         (lambda (&rest _) nil)))
     (let ((props (tibetan-sanskrit-parallel-dm-realign-document-proposals
                   source-file)))
       (should (= (length props) 2))
       (dolist (p props)
         (should (eq (plist-get p :status) 'no-candidates)))))))

;; ----------------------------------------------------------------------------
;; render-preview-buffer
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-render-preview-buffer-returns-buffer ()
  "Renderer returns a live buffer with a recognisable name."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--render-preview-buffer))
  (let* ((proposals
          (list (list :seg-id 1
                      :tibetan-text "བདག་"
                      :current-sanskrit "old"
                      :proposed-sanskrit "new"
                      :proposed-rank 1
                      :proposed-segmentnr "SA:1"
                      :reason "test reason"
                      :status 'change)))
         (buf (tibetan-sanskrit-parallel-dm--render-preview-buffer
               "/path/to/source.org" proposals)))
    (should (bufferp buf))
    (should (string-match-p "Sanskrit Realign" (buffer-name buf)))
    (with-current-buffer buf (kill-buffer))))

(ert-deftest tibetan-skt-dm-render-preview-buffer-summarises-counts ()
  "Header line summarises count of changes vs unchanged vs
no-candidates."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--render-preview-buffer))
  (let* ((proposals
          (list (list :seg-id 1 :status 'change
                      :tibetan-text "" :current-sanskrit ""
                      :proposed-sanskrit "" :reason "")
                (list :seg-id 2 :status 'unchanged
                      :tibetan-text "" :current-sanskrit ""
                      :proposed-sanskrit "" :reason "")
                (list :seg-id 3 :status 'no-candidates
                      :tibetan-text "" :current-sanskrit ""
                      :proposed-sanskrit "" :reason "")))
         (buf (tibetan-sanskrit-parallel-dm--render-preview-buffer
               "/path/to/source.org" proposals)))
    (with-current-buffer buf
      (let ((s (buffer-string)))
        ;; Counts visible somewhere in the buffer.
        (should (string-match-p "1.*change\\|change.*1" s))
        (should (string-match-p "1.*unchanged\\|unchanged.*1" s))
        (should (string-match-p "1.*no-candidates\\|no-candidates.*1" s))
        (should (string-match-p (regexp-quote "/path/to/source.org") s))))
    (with-current-buffer buf (kill-buffer))))

(ert-deftest tibetan-skt-dm-render-preview-buffer-shows-each-proposal ()
  "Each proposal's seg-id, current Sanskrit, proposed Sanskrit,
and reason are visible in the buffer."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--render-preview-buffer))
  (let* ((proposals
          (list (list :seg-id 7
                      :tibetan-text "བདག་གིས་ལས་བྱས།"
                      :current-sanskrit "rough draft sanskrit"
                      :proposed-sanskrit "iha bodhisattvaḥ prakṛtyaiva"
                      :proposed-rank 2
                      :proposed-segmentnr "SA_T06_bsa034:64"
                      :reason "verb prakṛtyaiva matches rang bzhin gyis"
                      :status 'change)))
         (buf (tibetan-sanskrit-parallel-dm--render-preview-buffer
               "/x.org" proposals)))
    (with-current-buffer buf
      (let ((s (buffer-string)))
        (should (string-match-p "Segment 7\\|seg-7\\|seg 7" s))
        (should (string-match-p "བདག་གིས་ལས་བྱས" s))
        (should (string-match-p "rough draft sanskrit" s))
        (should (string-match-p "iha bodhisattvaḥ prakṛtyaiva" s))
        (should (string-match-p "prakṛtyaiva matches rang bzhin" s))
        (should (string-match-p "SA_T06_bsa034:64" s))))
    (with-current-buffer buf (kill-buffer))))

;; ============================================================================
;; PHASE 7 — Apply writes to ANALYSIS files, never the source
;; ============================================================================
;;
;; Architectural correction (2026-04-30):  Phase 5's apply mode
;; wrote the realign output back to the source file's
;; `**** Sanskrit' siblings.  That violated the principle that the
;; analysis pipeline must never modify the user's source file
;; (CLAUDE.md §6 — preserve user content; the source is the user's
;; curated input).
;;
;; Phase 7 refactors the apply path:
;;   - DELETED: `tibetan-sanskrit-parallel-write-sanskrit-for-segment-id'
;;     (the source writer) and its 4 tests.
;;   - NEW: `--write-dharmamitra-sanskrit-to-analysis ANALYSIS-FILE
;;     PROPOSAL' writes a top-level `* Sanskrit (DharmaMitra)'
;;     section into the per-segment analysis file (seg-NNN.org).
;;     Top-level placement (outside `* Auto-Analysis') means it
;;     survives reanalysis naturally — no preserve-list change
;;     needed.
;;   - `--apply-proposal' now takes (ANALYSIS-FILE PROPOSAL) and
;;     calls the analysis-file writer.
;;   - `--apply-proposals' takes (SOURCE-FILE PROPOSALS), resolves
;;     analysis paths via `tibetan-analysis-get-filepath' (visiting
;;     the source buffer), and dispatches.
;;
;; The source file remains untouched on every apply — verified by
;; an explicit regression test below.

;; ----------------------------------------------------------------------------
;; Analysis-file writer (in core/tibetan-sanskrit-parallel-dharmamitra.el)
;; ----------------------------------------------------------------------------

(defmacro tibetan-skt-dm-test--with-analysis-file (initial-content &rest body)
  "Write INITIAL-CONTENT to a temp seg-005.org and bind ANALYSIS-FILE."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-skt-dm-write-analysis-" t))
          (analysis-file (expand-file-name "seg-005.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file analysis-file (insert ,initial-content))
           ,@body)
       (delete-directory dir t))))

(defun tibetan-skt-dm-test--proposal-fixture ()
  "Standard proposal plist for Phase 7 writer tests."
  (list :seg-id 5
        :tibetan-text "བདག་"
        :current-sanskrit "old"
        :proposed-sanskrit "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati"
        :proposed-rank 2
        :proposed-segmentnr "SA_T06_bsa034:64"
        :reason "verb prakṛtyaiva matches"
        :status 'change))

(ert-deftest tibetan-skt-dm-write-analysis-creates-section-when-absent ()
  "Writer adds a top-level `* Sanskrit (DharmaMitra)' section to
the analysis file when none exists yet."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis))
  (tibetan-skt-dm-test--with-analysis-file
   (concat "#+TITLE: Segment 5 Analysis\n\n"
           "* Tibetan Text\nསྡོམ་ལ་\n\n"
           "* Auto-Analysis\n** Wylie\n[stub]\n\n"
           "* My Notes\n\n* Working Translation\n\n* Footnotes\n")
   (let ((ok (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
              analysis-file (tibetan-skt-dm-test--proposal-fixture))))
     (should ok)
     (with-temp-buffer
       (insert-file-contents analysis-file)
       (let ((s (buffer-string)))
         (should (string-match-p "^\\* Sanskrit (DharmaMitra)$" s))
         (should (string-match-p "iha bodhisattvaḥ prakṛtyaiva" s)))))))

(ert-deftest tibetan-skt-dm-write-analysis-replaces-existing-section ()
  "When `* Sanskrit (DharmaMitra)' already exists, writer replaces
its body and property drawer."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis))
  (tibetan-skt-dm-test--with-analysis-file
   (concat "#+TITLE: Segment 5 Analysis\n\n"
           "* Tibetan Text\nསྡོམ་ལ་\n\n"
           "* Sanskrit (DharmaMitra)\n"
           ":PROPERTIES:\n:DM_SEGMENTNR: OLD-ID:99\n:END:\n"
           "OLD STALE TEXT\n\n"
           "* My Notes\nuser-content-keep\n")
   (let ((ok (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
              analysis-file (tibetan-skt-dm-test--proposal-fixture))))
     (should ok)
     (with-temp-buffer
       (insert-file-contents analysis-file)
       (let ((s (buffer-string)))
         (should (string-match-p "iha bodhisattvaḥ prakṛtyaiva" s))
         (should-not (string-match-p "OLD STALE TEXT" s))
         (should-not (string-match-p "OLD-ID:99" s))
         ;; My Notes preserved.
         (should (string-match-p "user-content-keep" s)))))))

(ert-deftest tibetan-skt-dm-write-analysis-property-drawer-carries-metadata ()
  "Section's property drawer includes DM_SEGMENTNR / DM_RANK /
CLAUDE_REASON / LAST_REALIGN — all useful for the user
auditing how the alignment was reached."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis))
  (tibetan-skt-dm-test--with-analysis-file
   "#+TITLE: T\n\n* Tibetan Text\n\n"
   (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
    analysis-file (tibetan-skt-dm-test--proposal-fixture))
   (with-temp-buffer
     (insert-file-contents analysis-file)
     (let ((s (buffer-string)))
       (should (string-match-p ":DM_SEGMENTNR: SA_T06_bsa034:64" s))
       (should (string-match-p ":DM_RANK: 2" s))
       (should (string-match-p ":CLAUDE_REASON: verb prakṛtyaiva matches" s))
       ;; LAST_REALIGN is a date stamp — just verify the key is there.
       (should (string-match-p ":LAST_REALIGN:" s))))))

(ert-deftest tibetan-skt-dm-write-analysis-preserves-other-sections ()
  "Tibetan Text, Auto-Analysis, My Notes, Working Translation,
Footnotes — none touched by the writer."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis))
  (tibetan-skt-dm-test--with-analysis-file
   (concat "#+TITLE: T\n\n"
           "* Tibetan Text\nTIBETAN_BODY\n\n"
           "* Auto-Analysis\nAUTO_BODY\n** Wylie\nWYLIE_BODY\n\n"
           "* My Notes\nNOTES_BODY\n\n"
           "* Working Translation\nWT_BODY\n\n"
           "* Footnotes\nFOOTNOTES_BODY\n")
   (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
    analysis-file (tibetan-skt-dm-test--proposal-fixture))
   (with-temp-buffer
     (insert-file-contents analysis-file)
     (let ((s (buffer-string)))
       (should (string-match-p "TIBETAN_BODY" s))
       (should (string-match-p "AUTO_BODY" s))
       (should (string-match-p "WYLIE_BODY" s))
       (should (string-match-p "NOTES_BODY" s))
       (should (string-match-p "WT_BODY" s))
       (should (string-match-p "FOOTNOTES_BODY" s))))))

(ert-deftest tibetan-skt-dm-write-analysis-nil-when-file-missing ()
  "Non-existent ANALYSIS-FILE returns nil without crashing."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis))
  (should-not (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
               "/nonexistent/path/seg-005.org"
               (tibetan-skt-dm-test--proposal-fixture))))

;; ----------------------------------------------------------------------------
;; DM apply-proposal (status-aware) — refactored to call analysis writer
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-apply-proposal-applies-change-status ()
  "Proposal with `:status' `change' calls the analysis-file writer
(NOT a source writer).  Phase 7 architecture: source is never
touched."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposal))
  (let (analysis-write-calls)
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis)
               (lambda (file proposal)
                 (push (list file proposal) analysis-write-calls)
                 t)))
      (let ((p (tibetan-skt-dm-test--proposal-fixture)))
        (tibetan-sanskrit-parallel-dm--apply-proposal "/tmp/seg-005.org" p)
        (should (= (length analysis-write-calls) 1))
        (let ((call (car analysis-write-calls)))
          (should (equal (nth 0 call) "/tmp/seg-005.org"))
          (should (equal (plist-get (nth 1 call) :proposed-sanskrit)
                         "iha bodhisattvaḥ prakṛtyaiva dānarucirbhavati")))))))

(ert-deftest tibetan-skt-dm-apply-proposal-skips-unchanged-status ()
  "Proposal with `:status' `unchanged' is a no-op."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposal))
  (let (write-calls)
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis)
               (lambda (&rest args) (push args write-calls) t)))
      (let ((p (list :seg-id 5 :status 'unchanged
                     :proposed-sanskrit "x")))
        (tibetan-sanskrit-parallel-dm--apply-proposal "/tmp/x.org" p)
        (should (= (length write-calls) 0))))))

(ert-deftest tibetan-skt-dm-apply-proposal-skips-no-candidates-status ()
  "Proposal with `:status' `no-candidates' is a no-op."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposal))
  (let (write-calls)
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis)
               (lambda (&rest args) (push args write-calls) t)))
      (let ((p (list :seg-id 5 :status 'no-candidates
                     :proposed-sanskrit nil)))
        (tibetan-sanskrit-parallel-dm--apply-proposal "/tmp/x.org" p)
        (should (= (length write-calls) 0))))))

;; ----------------------------------------------------------------------------
;; DM apply-proposals (batch, returns count)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-apply-proposals-touches-only-change-status ()
  "Apply-all writes ONLY proposals with `change' status; returns
the count of successful writes.  Each write goes to the
proposal's resolved analysis file (seg-NNN.org), NOT to the
source."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (let (write-calls)
     (cl-letf (((symbol-function 'tibetan-analysis-get-filepath)
                (lambda (seg-id &optional _src)
                  (format "/tmp/seg-%03d.org" seg-id)))
               ((symbol-function 'tibetan-sanskrit-parallel-dm--apply-proposal)
                (lambda (file p)
                  ;; Mimic real apply-proposal's status gate.
                  (when (eq (plist-get p :status) 'change)
                    (push (cons (plist-get p :seg-id) file) write-calls)
                    t))))
       (let* ((proposals
               (list (list :seg-id 1 :status 'change :proposed-sanskrit "a")
                     (list :seg-id 2 :status 'unchanged :proposed-sanskrit "b")
                     (list :seg-id 3 :status 'no-candidates
                           :proposed-sanskrit nil)
                     (list :seg-id 4 :status 'change :proposed-sanskrit "d")))
              (n (tibetan-sanskrit-parallel-dm--apply-proposals
                  source-file proposals)))
         (should (= n 2))
         (should (= (length write-calls) 2))
         ;; Each call resolved to the right analysis file.
         (should (member (cons 1 "/tmp/seg-001.org") write-calls))
         (should (member (cons 4 "/tmp/seg-004.org") write-calls)))))))

(ert-deftest tibetan-skt-dm-apply-proposals-empty-returns-zero ()
  "Empty proposal list returns 0; no writers called."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposals))
  (let ((calls 0))
    (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--apply-proposal)
               (lambda (&rest _) (cl-incf calls) t)))
      (should (= 0 (tibetan-sanskrit-parallel-dm--apply-proposals
                    "/tmp/x.org" nil)))
      (should (= 0 (tibetan-sanskrit-parallel-dm--apply-proposals
                    "/tmp/x.org" '())))
      (should (= calls 0)))))

(ert-deftest tibetan-skt-dm-apply-proposals-threads-source-file-for-suffix ()
  "Apply-all must thread SOURCE-FILE into tibetan-analysis-get-filepath
so the §5.23 per-source suffix resolves the correct seg-NNN-SHORT.org.

Without it, get-filepath returns the bare seg-NNN.org and, in a
multi-source analysis folder, the realign section is written to the
wrong source's file (or a nonexistent path) — the §5.23 silent-
overwrite class on the realign path."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (let (captured-srcs)
     (cl-letf (((symbol-function 'tibetan-analysis-get-filepath)
                (lambda (seg-id &optional src)
                  (push src captured-srcs)
                  (format "/tmp/seg-%03d.org" seg-id)))
               ((symbol-function 'tibetan-sanskrit-parallel-dm--apply-proposal)
                (lambda (_file _p) t)))
       (tibetan-sanskrit-parallel-dm--apply-proposals
        source-file
        (list (list :seg-id 1 :status 'change :proposed-sanskrit "a")))
       ;; The suffix-aware call passed the real source file, not nil.
       (should (member source-file captured-srcs))))))

;; ----------------------------------------------------------------------------
;; REGRESSION: source file is NEVER modified by apply (Phase 7 invariant)
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-apply-proposals-leaves-source-byte-identical ()
  "The Phase 7 architectural invariant: `--apply-proposals' MUST NOT
modify the source file under any circumstances.  Verified by
running the function on a real source file with multiple
`change'-status proposals and asserting the source's bytes are
unchanged before vs after."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--apply-proposals))
  (tibetan-skt-dm-test--with-source-file-multi-segment
   (let* ((src-before
           (with-temp-buffer (insert-file-contents source-file) (buffer-string)))
          (proposals
           (list (list :seg-id 1 :status 'change
                       :proposed-sanskrit "would-be-change-1"
                       :proposed-rank 1 :proposed-segmentnr "X:1"
                       :reason "test")
                 (list :seg-id 2 :status 'change
                       :proposed-sanskrit "would-be-change-2"
                       :proposed-rank 1 :proposed-segmentnr "X:2"
                       :reason "test"))))
     (cl-letf (((symbol-function 'tibetan-analysis-get-filepath)
                (lambda (seg-id &optional _src)
                  (format "/tmp/no-such-analysis-%d.org" seg-id))))
       (tibetan-sanskrit-parallel-dm--apply-proposals
        source-file proposals))
     (let ((src-after
            (with-temp-buffer (insert-file-contents source-file) (buffer-string))))
       (should (equal src-before src-after))))))

;; ----------------------------------------------------------------------------
;; Interactive commands
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-realign-document-fbound-and-commandp ()
  "The document realign command is interactive."
  (should (fboundp 'tibetan-sanskrit-parallel-dm-realign-document))
  (should (commandp 'tibetan-sanskrit-parallel-dm-realign-document)))

(ert-deftest tibetan-skt-dm-realign-segment-fbound-and-commandp ()
  "The segment realign command is interactive."
  (should (fboundp 'tibetan-sanskrit-parallel-dm-realign-segment))
  (should (commandp 'tibetan-sanskrit-parallel-dm-realign-segment)))

;; ============================================================================
;; PHASE 8 — Claude extracts matching clause from chosen DM candidate
;; ============================================================================
;;
;; Phase 7 fixed WHERE the realign output lands.  Phase 8 fixes
;; WHAT lands.
;;
;; DM corpus segments are coarser than Tibetan segments.  A
;; 1-line uddāna verse line on the Tibetan side may semantically
;; match a multi-line corpus segment containing title + ToC +
;; verse.  Phase 7's apply mode wrote that whole multi-line chunk;
;; Phase 8 asks Claude not just "which candidate?" but also
;; "which exact clause within that candidate parallels the
;; Tibetan?".  Claude's verbatim clause becomes the
;; `:proposed-sanskrit'; the full candidate text remains in
;; `:chosen-text' for provenance.
;;
;; The pick prompt schema gains a `## Clause' section.  The
;; parser captures it as `:chosen-clause' on the pick plist.
;; `--build-proposal' uses `:chosen-clause' if present, else
;; falls back to the full `:chosen-text' (preserves backward
;; compatibility with the single-candidate fast path which
;; doesn't call Claude).

;; ----------------------------------------------------------------------------
;; Prompt schema
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-build-pick-prompt-asks-for-clause ()
  "Prompt instructs Claude to emit a `## Clause' section with the
verbatim matching clause from the chosen candidate."
  (let ((prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                 "བདག་" (tibetan-skt-dm-test--three-candidates))))
    (should (string-match-p "## Clause" prompt))
    ;; Existing schema sections still present.
    (should (string-match-p "## Choice" prompt))
    (should (string-match-p "## Reason" prompt))))

(ert-deftest tibetan-skt-dm-build-pick-prompt-instructs-verbatim ()
  "Prompt makes clear the clause must be VERBATIM (not paraphrased)
so the writer can reliably write it back."
  (let ((prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                 "བདག་" (tibetan-skt-dm-test--three-candidates))))
    (should (string-match-p "verbatim\\|exact\\|EXACT" prompt))))

;; ----------------------------------------------------------------------------
;; Parser updates
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-parse-pick-response-extracts-chosen-clause ()
  "Parser returns `:chosen-clause' alongside `:chosen-rank' / `:reason'."
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (response (concat
                    "## Choice\n2\n\n"
                    "## Clause\n"
                    "evamayaṃ prathamaścittotpādaḥ\n\n"
                    "## Reason\n"
                    "Matches the Tibetan focus on cittotpāda.\n"))
         (parsed (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                  response cands)))
    (should parsed)
    (should (= (plist-get parsed :chosen-rank) 2))
    (should (equal (plist-get parsed :chosen-clause)
                   "evamayaṃ prathamaścittotpādaḥ"))
    (should (string-match-p "cittotpāda" (plist-get parsed :reason)))))

(ert-deftest tibetan-skt-dm-parse-pick-response-clause-multi-line ()
  "Multi-line `## Clause' body is captured intact (verse-form
Sanskrit may legitimately span multiple lines)."
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (response (concat
                    "## Choice\n1\n\n"
                    "## Clause\n"
                    "line one\nline two\n\n"
                    "## Reason\nfoo\n"))
         (parsed (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                  response cands)))
    (should (equal (plist-get parsed :chosen-clause)
                   "line one\nline two"))))

(ert-deftest tibetan-skt-dm-parse-pick-response-handles-missing-clause ()
  "Backward compatibility:  responses without `## Clause' still
parse, with `:chosen-clause' as nil so callers can fall back to
full candidate text."
  (let* ((cands (tibetan-skt-dm-test--three-candidates))
         (response "## Choice\n2\n\n## Reason\nVerb match.\n")
         (parsed (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                  response cands)))
    (should parsed)
    (should (= (plist-get parsed :chosen-rank) 2))
    (should (null (plist-get parsed :chosen-clause)))))

;; ----------------------------------------------------------------------------
;; claude-pick output plist
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-claude-pick-includes-chosen-clause-when-extracted ()
  "When Claude returns a `## Clause' section, the pick output's
`:chosen-clause' is the extracted text."
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_p)
               (concat "## Choice\n2\n\n"
                       "## Clause\nevamayaṃ prathamaścittotpādaḥ\n\n"
                       "## Reason\nx\n"))))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should (equal (plist-get out :chosen-clause)
                     "evamayaṃ prathamaścittotpādaḥ"))
      ;; Full :chosen-text still carried for provenance.
      (should (equal (plist-get out :chosen-text)
                     "evamayaṃ prathamaścittotpādaḥ"))
      (should (= (plist-get out :chosen-rank) 2)))))

(ert-deftest tibetan-skt-dm-claude-pick-clause-nil-when-claude-omits-it ()
  "When Claude returns no `## Clause' (legacy / quirky responses),
pick output's `:chosen-clause' is nil; callers fall back to
full text."
  (cl-letf (((symbol-function 'tibetan-sanskrit-parallel-dm--ask-claude-sync)
             (lambda (_p) "## Choice\n2\n\n## Reason\nx\n")))
    (let* ((cands (tibetan-skt-dm-test--three-candidates))
           (out (tibetan-sanskrit-parallel-dm-claude-pick "བདག་" cands)))
      (should (null (plist-get out :chosen-clause)))
      ;; Full text still present.
      (should (equal (plist-get out :chosen-text)
                     "evamayaṃ prathamaścittotpādaḥ")))))

;; ----------------------------------------------------------------------------
;; build-proposal uses :chosen-clause when present
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-skt-dm-build-proposal-uses-chosen-clause-when-present ()
  "Phase 8: when pick plist carries `:chosen-clause', the
proposal's `:proposed-sanskrit' is that clause — NOT the full
multi-line `:chosen-text'.  This is how the granularity issue
is fixed:  big DM chunk in `:chosen-text' for provenance,
extracted clause in `:proposed-sanskrit' for the analysis-file
write."
  (let* ((pick (list :chosen-id "SA:64"
                     :chosen-text "FULL multi-line\nchunk text"
                     :chosen-clause "extracted matching clause"
                     :chosen-rank 1
                     :reason "x"))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་" "old" pick)))
    (should (equal (plist-get p :proposed-sanskrit)
                   "extracted matching clause"))))

(ert-deftest tibetan-skt-dm-build-proposal-falls-back-to-text-when-clause-missing ()
  "Backward compat:  when `:chosen-clause' is nil (legacy
single-candidate path, parser miss), use the full
`:chosen-text'."
  (let* ((pick (list :chosen-id "SA:64"
                     :chosen-text "fallback full text"
                     :chosen-clause nil
                     :chosen-rank 1
                     :reason "single-candidate"))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་" "old" pick)))
    (should (equal (plist-get p :proposed-sanskrit)
                   "fallback full text"))))

(ert-deftest tibetan-skt-dm-build-proposal-falls-back-when-clause-empty ()
  "Empty-string `:chosen-clause' (Claude returned `## Clause'
with no body) also falls back to full text."
  (let* ((pick (list :chosen-id "SA:64"
                     :chosen-text "fallback full text"
                     :chosen-clause ""
                     :chosen-rank 1
                     :reason "x"))
         (p (tibetan-sanskrit-parallel-dm--build-proposal
             5 "བདག་" "old" pick)))
    (should (equal (plist-get p :proposed-sanskrit)
                   "fallback full text"))))

;; ============================================================================
;; PHASE 9 — Bug fix: --ask-claude-sync must load gptel auth first
;; ============================================================================
;;
;; Live test 2026-04-30:  every multi-candidate segment fell back
;; to the top hit with `claude-unavailable-fallback-to-top'
;; reason, even though gptel was loaded in the user's Emacs.
;; *Messages* showed `No `gptel-api-key' found in the auth source'
;; for every Claude call.
;;
;; Root cause:  `--ask-claude-sync' (Phase 3) calls `gptel-request'
;; without first running `tibetan-analysis--ensure-gptel-ready' —
;; the helper that pulls the Anthropic API key from `~/.authinfo'
;; and stuffs it into `gptel-api-key'.  The async claude-translation
;; flow calls it; we forgot.
;;
;; Regression test:  verifies `--ensure-gptel-ready' is called
;; BEFORE `gptel-request'.  Order matters — calling after would
;; race with the request firing.

(ert-deftest tibetan-skt-dm-ask-claude-sync-loads-auth-before-request ()
  "Phase 9 regression:  `--ask-claude-sync' must call
`tibetan-analysis--ensure-gptel-ready' BEFORE `gptel-request'.
Without this, gptel-request fails with
\"No `gptel-api-key' found in the auth source\" on every Claude
call, leaving the realign command stuck in top-hit fallback."
  (skip-unless (fboundp 'tibetan-sanskrit-parallel-dm--ask-claude-sync))
  (let ((order '()))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (eq sym 'gptel)))
              ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
               (lambda () (push 'ensure order)))
              ((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (push 'request order)
                 ;; Fire the callback synchronously so the
                 ;; with-timeout loop exits immediately.
                 (let ((cb (plist-get args :callback)))
                   (when cb (funcall cb "## Choice\n1\n\n## Reason\nx\n" nil))))))
      (tibetan-sanskrit-parallel-dm--ask-claude-sync "test prompt")
      (let ((seq (nreverse order)))
        ;; Both functions called.
        (should (memq 'ensure seq))
        (should (memq 'request seq))
        ;; Order:  ensure before request.
        (should (< (cl-position 'ensure seq)
                   (cl-position 'request seq)))))))

(provide 'tibetan-sanskrit-parallel-dharmamitra-test)
;;; tibetan-sanskrit-parallel-dharmamitra-test.el ends here
