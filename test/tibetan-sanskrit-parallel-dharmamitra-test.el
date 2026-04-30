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

(provide 'tibetan-sanskrit-parallel-dharmamitra-test)
;;; tibetan-sanskrit-parallel-dharmamitra-test.el ends here
