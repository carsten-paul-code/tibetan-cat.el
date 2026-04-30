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

(provide 'tibetan-sanskrit-parallel-dharmamitra-test)
;;; tibetan-sanskrit-parallel-dharmamitra-test.el ends here
