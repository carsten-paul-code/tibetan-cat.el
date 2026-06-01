;;; tibetan-dharmamitra-api-test.el --- Tests for DharmaMitra HTTP client -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for `core/tibetan-dharmamitra-api.el' — the HTTP client
;; for DharmaMitra's chat-translate (SSE-streaming OpenAI-compatible)
;; and primary-search endpoints.
;;
;; Test strategy: stub `tibetan-dharmamitra-api--http-post' so no
;; network calls are made.  Pure functions (SSE parser, request body
;; builders, cache key) are exercised directly.  This is Phase 1 of
;; the dharmamitra-realign feature (2026-04-27).

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-dharmamitra-api)

;; ============================================================================
;; SSE STREAM PARSER (pure function, no HTTP)
;; ============================================================================

(ert-deftest tibetan-dharmamitra-api-parse-sse-extracts-content ()
  "Parser concatenates delta.content fields from a multi-chunk SSE
stream and returns the full translation string."
  (let* ((stream (concat
                  "data: {\"id\":\"x\",\"choices\":[{\"delta\":{\"content\":\"\"},\"index\":0}]}\n\n"
                  "data: {\"id\":\"x\",\"choices\":[{\"delta\":{\"content\":\"In this\"},\"index\":0}]}\n\n"
                  "data: {\"id\":\"x\",\"choices\":[{\"delta\":{\"content\":\" context, a Bodhisattva\"},\"index\":0}]}\n\n"
                  "data: {\"id\":\"x\",\"choices\":[{\"delta\":{\"content\":\" gives generously.\"},\"index\":0}]}\n\n"
                  "data: {\"id\":\"x\",\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}]}\n\n"
                  "data: [DONE]\n\n"))
         (out (tibetan-dharmamitra-api--parse-sse-stream stream)))
    (should (string= out "In this context, a Bodhisattva gives generously."))))

(ert-deftest tibetan-dharmamitra-api-parse-sse-handles-no-space-after-colon ()
  "Parser tolerates the `data:{…}' framing (no space after the colon),
which some SSE servers / proxies emit.  Hard-coding `data: ' (one
space) silently dropped the whole stream, surfacing as a misleading
`no content' / rate-limit diagnostic."
  (let ((stream (concat
                 "data:{\"choices\":[{\"delta\":{\"content\":\"abc\"}}]}\n\n"
                 "data:{\"choices\":[{\"delta\":{\"content\":\"def\"}}]}\n\n"
                 "data:[DONE]\n")))
    (should (string= (tibetan-dharmamitra-api--parse-sse-stream stream)
                     "abcdef"))))

(ert-deftest tibetan-dharmamitra-api-parse-sse-handles-done-marker ()
  "Parser stops gracefully at `data: [DONE]' and returns content
gathered up to that point."
  (let ((stream "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\ndata: [DONE]\n"))
    (should (string= (tibetan-dharmamitra-api--parse-sse-stream stream)
                     "hello"))))

(ert-deftest tibetan-dharmamitra-api-parse-sse-empty-stream-returns-empty-string ()
  "Parser returns empty string (not nil, not error) for empty input."
  (should (string= (tibetan-dharmamitra-api--parse-sse-stream "") ""))
  (should (string= (tibetan-dharmamitra-api--parse-sse-stream "\n\n\n") "")))

(ert-deftest tibetan-dharmamitra-api-parse-sse-skips-malformed-lines ()
  "Parser ignores malformed JSON lines instead of crashing.
Subsequent valid lines are still extracted."
  (let ((stream (concat
                 "data: {malformed json\n\n"
                 "data: {\"choices\":[{\"delta\":{\"content\":\"valid\"}}]}\n\n"
                 "data: also bad\n\n"
                 "data: [DONE]\n")))
    (should (string= (tibetan-dharmamitra-api--parse-sse-stream stream)
                     "valid"))))

(ert-deftest tibetan-dharmamitra-api-parse-sse-handles-non-data-lines ()
  "Lines that don't start with `data: ' are ignored (event:, id:,
blank lines, etc.)."
  (let ((stream (concat
                 "event: message\n"
                 "id: 12345\n"
                 "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\n\n"
                 ":heartbeat\n"
                 "data: [DONE]\n")))
    (should (string= (tibetan-dharmamitra-api--parse-sse-stream stream)
                     "x"))))

(ert-deftest tibetan-dharmamitra-api-parse-sse-handles-empty-content-deltas ()
  "Empty `content' fields contribute the empty string and don't
break concatenation."
  (let ((stream (concat
                 "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\n"
                 "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\n\n"
                 "data: {\"choices\":[{\"delta\":{}}]}\n\n"
                 "data: [DONE]\n")))
    (should (string= (tibetan-dharmamitra-api--parse-sse-stream stream)
                     "x"))))

;; ============================================================================
;; REQUEST BODY BUILDERS (pure functions)
;; ============================================================================

(ert-deftest tibetan-dharmamitra-api-build-chat-translate-body-shape ()
  "Chat-translate body has the required keys and values."
  (let* ((body (tibetan-dharmamitra-api--build-chat-translate-body
                "iha bodhisattvaḥ"))
         (parsed (json-parse-string body :object-type 'alist
                                    :array-type 'list)))
    (should (equal (alist-get 'model parsed) "gpt-3.5-turbo"))
    (should (eq (alist-get 'stream parsed) t))
    (should (equal (alist-get 'target_lang parsed) "english"))
    (should (equal (alist-get 'input_encoding parsed) "auto"))
    ;; messages is a list/array with one user message.
    (let* ((messages (alist-get 'messages parsed))
           (first-msg (car messages)))
      (should first-msg)
      (should (equal (alist-get 'role first-msg) "user"))
      (should (equal (alist-get 'content first-msg) "iha bodhisattvaḥ")))))

(ert-deftest tibetan-dharmamitra-api-build-chat-translate-body-respects-target-lang ()
  "`:target-lang' arg overrides the default `english'."
  (let* ((body (tibetan-dharmamitra-api--build-chat-translate-body
                "x" :target-lang "german"))
         (parsed (json-parse-string body :object-type 'alist
                                    :array-type 'list)))
    (should (equal (alist-get 'target_lang parsed) "german"))))

(ert-deftest tibetan-dharmamitra-api-build-search-body-shape ()
  "Search body carries the required keys and default values."
  (let* ((body (tibetan-dharmamitra-api--build-search-body
                "iha bodhisattvaḥ"))
         (parsed (json-parse-string body :object-type 'alist
                                    :array-type 'list)))
    (should (equal (alist-get 'search_input parsed) "iha bodhisattvaḥ"))
    (should (equal (alist-get 'input_encoding parsed) "auto"))
    (should (equal (alist-get 'search_type parsed) "semantic"))
    (should (equal (alist-get 'filter_source_language parsed) "auto"))
    (should (equal (alist-get 'filter_target_language parsed) "all"))
    (should (eq (alist-get 'do_ranking parsed) t))))

(ert-deftest tibetan-dharmamitra-api-build-search-body-respects-include-files ()
  "`:include-files' arg lands in the source_filters block."
  (let* ((body (tibetan-dharmamitra-api--build-search-body
                "x" :include-files '("SA_T06_bsa034")))
         (parsed (json-parse-string body :object-type 'alist
                                    :array-type 'list))
         (filters (alist-get 'source_filters parsed))
         (files (alist-get 'include_files filters)))
    (should (member "SA_T06_bsa034" files))))

(ert-deftest tibetan-dharmamitra-api-build-search-body-respects-source-lang ()
  "`:source-lang' overrides default `auto'."
  (let* ((body (tibetan-dharmamitra-api--build-search-body
                "x" :source-lang "sa"))
         (parsed (json-parse-string body :object-type 'alist
                                    :array-type 'list)))
    (should (equal (alist-get 'filter_source_language parsed) "sa"))))

;; ============================================================================
;; END-TO-END WITH STUBBED HTTP (no network)
;; ============================================================================

(defvar tibetan-dharmamitra-api-test--http-call-count 0
  "Side-channel: counts calls to the stubbed `--http-post'.")

(defun tibetan-dharmamitra-api-test--stub-sse-response ()
  "Return a fake SSE response string the chat-translate stub can return."
  (concat
   "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\n"
   "data: {\"choices\":[{\"delta\":{\"content\":\"In this\"}}]}\n\n"
   "data: {\"choices\":[{\"delta\":{\"content\":\" context.\"}}]}\n\n"
   "data: [DONE]\n"))

(defun tibetan-dharmamitra-api-test--stub-search-response ()
  "Return a fake JSON response string the search stub can return."
  "{\"results\":[{\"id\":\"SA_T06_bsa034:64\",\"lang\":\"sa\",\"source\":\"SA_T06_bsa034\",\"text\":\"iha bodhisattvaḥ prakṛtyaiva\",\"segmentnr\":\"SA_T06_bsa034:64\",\"title\":\"Asaṅga: Bodhisattvabhūmi\",\"summary\":\"\",\"text_new\":{\"text_before\":\"\",\"text_main\":\"iha bodhisattvaḥ\",\"text_after\":\"\"},\"src_link\":\"\",\"query\":\"\"}]}")

(ert-deftest tibetan-dharmamitra-api-chat-translate-end-to-end-with-stub ()
  "Full chat-translate path with stubbed HTTP returns the parsed
translation string."
  (tibetan-dharmamitra-api-clear-cache)
  (setq tibetan-dharmamitra-api-test--http-call-count 0)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (cl-incf tibetan-dharmamitra-api-test--http-call-count)
               (tibetan-dharmamitra-api-test--stub-sse-response))))
    (let ((result (tibetan-dharmamitra-api-chat-translate "iha bodhisattvaḥ")))
      (should (string= result "In this context."))
      (should (= tibetan-dharmamitra-api-test--http-call-count 1)))))

(ert-deftest tibetan-dharmamitra-api-chat-translate-cache-hit-second-call ()
  "Same input twice → only one HTTP call (second is cache hit)."
  (tibetan-dharmamitra-api-clear-cache)
  (setq tibetan-dharmamitra-api-test--http-call-count 0)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (cl-incf tibetan-dharmamitra-api-test--http-call-count)
               (tibetan-dharmamitra-api-test--stub-sse-response))))
    (tibetan-dharmamitra-api-chat-translate "iha bodhisattvaḥ")
    (tibetan-dharmamitra-api-chat-translate "iha bodhisattvaḥ")
    (should (= tibetan-dharmamitra-api-test--http-call-count 1))))

(ert-deftest tibetan-dharmamitra-api-chat-translate-cache-different-inputs-no-collision ()
  "Different inputs do NOT collide in the cache — each gets its own
HTTP call."
  (tibetan-dharmamitra-api-clear-cache)
  (setq tibetan-dharmamitra-api-test--http-call-count 0)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (cl-incf tibetan-dharmamitra-api-test--http-call-count)
               (tibetan-dharmamitra-api-test--stub-sse-response))))
    (tibetan-dharmamitra-api-chat-translate "input A")
    (tibetan-dharmamitra-api-chat-translate "input B")
    (should (= tibetan-dharmamitra-api-test--http-call-count 2))))

(ert-deftest tibetan-dharmamitra-api-search-end-to-end-with-stub ()
  "Full search path with stubbed HTTP returns the parsed results
list (alists)."
  (tibetan-dharmamitra-api-clear-cache)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (tibetan-dharmamitra-api-test--stub-search-response))))
    (let ((results (tibetan-dharmamitra-api-search
                    "iha bodhisattvaḥ"
                    :source-lang "sa"
                    :include-files '("SA_T06_bsa034"))))
      (should (listp results))
      (should (= (length results) 1))
      (should (equal (alist-get 'id (car results)) "SA_T06_bsa034:64"))
      (should (equal (alist-get 'lang (car results)) "sa")))))

(ert-deftest tibetan-dharmamitra-api-search-cache-hit-second-call ()
  "Search cache also dedupes identical queries."
  (tibetan-dharmamitra-api-clear-cache)
  (setq tibetan-dharmamitra-api-test--http-call-count 0)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (cl-incf tibetan-dharmamitra-api-test--http-call-count)
               (tibetan-dharmamitra-api-test--stub-search-response))))
    (tibetan-dharmamitra-api-search "x")
    (tibetan-dharmamitra-api-search "x")
    (should (= tibetan-dharmamitra-api-test--http-call-count 1))))

(ert-deftest tibetan-dharmamitra-api-error-returns-nil-not-crash ()
  "When `--http-post' signals an error, the public API returns nil
gracefully rather than letting the error escape."
  (tibetan-dharmamitra-api-clear-cache)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (error "Simulated HTTP failure"))))
    (let ((result (tibetan-dharmamitra-api-chat-translate "x")))
      (should (null result)))
    (let ((result (tibetan-dharmamitra-api-search "x")))
      (should (null result)))))

(ert-deftest tibetan-dharmamitra-api-clear-cache-actually-clears ()
  "After `clear-cache', a previously-cached query forces a new
HTTP call."
  (tibetan-dharmamitra-api-clear-cache)
  (setq tibetan-dharmamitra-api-test--http-call-count 0)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body)
               (cl-incf tibetan-dharmamitra-api-test--http-call-count)
               (tibetan-dharmamitra-api-test--stub-sse-response))))
    (tibetan-dharmamitra-api-chat-translate "x")
    (tibetan-dharmamitra-api-clear-cache)
    (tibetan-dharmamitra-api-chat-translate "x")
    (should (= tibetan-dharmamitra-api-test--http-call-count 2))))

(ert-deftest tibetan-dharmamitra-api-chat-translate-empty-response-returns-nil ()
  "When the SSE stream is empty / yields no content, return nil
rather than an empty string masquerading as a translation.
Callers can `or' against this."
  (tibetan-dharmamitra-api-clear-cache)
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api--http-post)
             (lambda (_endpoint _body) "")))
    (should (null (tibetan-dharmamitra-api-chat-translate "x")))))

(ert-deftest tibetan-dharmamitra-api-http-post-enforces-tls-verification ()
  "`--http-post' must bind `gnutls-verify-error' to t around the
`url-retrieve-synchronously' call.

Emacs' default `gnutls-verify-error' is nil, meaning certificate
failures do NOT abort the connection — the bearer token would be sent
and the response trusted over an unverified (MITM-able) channel.  This
test sets the global default to nil and captures the dynamic value of
`gnutls-verify-error' at the moment `--http-post' contacts the server;
it must be t."
  (let ((captured 'unset)
        (gnutls-verify-error nil))        ; hostile default
    (cl-letf (((symbol-function 'url-retrieve-synchronously)
               (lambda (&rest _)
                 (setq captured gnutls-verify-error)
                 ;; Return a minimal HTTP buffer so --http-post can parse.
                 (let ((buf (generate-new-buffer " *tls-test*")))
                   (with-current-buffer buf
                     (insert "HTTP/1.1 200 OK\n\nok"))
                   buf))))
      (tibetan-dharmamitra-api--http-post "/x" "{}")
      (should (eq captured t)))))

(provide 'tibetan-dharmamitra-api-test)
;;; tibetan-dharmamitra-api-test.el ends here
