;;; tibetan-dharmamitra-api.el --- HTTP client for DharmaMitra search/translate APIs -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; HTTP client for the public DharmaMitra search backend
;; (https://dharmamitra.org/api-search/).  Provides two top-level
;; functions:
;;
;;   `tibetan-dharmamitra-api-chat-translate' — translate any text
;;   (IAST / Devanagari / Tibetan / Wylie / English) to a target
;;   language via DharmaMitra's OpenAI-compatible streaming chat-
;;   translate endpoint.  Returns the concatenated translation
;;   string or nil on error.
;;
;;   `tibetan-dharmamitra-api-search' — semantic search across the
;;   DharmaMitra primary corpus (Tibetan canon, Sanskrit śāstra
;;   editions, Pāli, Chinese).  Returns a list of result alists or
;;   nil.  Supports filtering by source files (e.g. limit hits to
;;   one work) and by query / target language.
;;
;; Both functions are cached in-memory by request body hash, so
;; re-running the same query is free.  Use
;; `tibetan-dharmamitra-api-clear-cache' to drop the cache when DM
;; updates or you want a fresh round.
;;
;; The HTTP layer is isolated in `tibetan-dharmamitra-api--http-post'
;; so tests can `cl-letf' it without making network calls.  The SSE
;; stream parser, request body builders, and cache key derivation
;; are pure functions, separately testable.
;;
;; Phase 1 of the dharmamitra-realign workflow (2026-04-27).

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'url)
;; gnutls / nsm own `gnutls-verify-error' / `network-security-level'.
;; Require them so those variables are genuinely SPECIAL at both compile
;; and run time — otherwise our `let' bindings around
;; `url-retrieve-synchronously' (in --http-post) would be LEXICAL and
;; url.el would never read them, silently defeating TLS verification.
(require 'gnutls)
(require 'nsm)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-dharmamitra-api nil
  "DharmaMitra HTTP client configuration."
  :group 'tibetan-cat
  :prefix "tibetan-dharmamitra-api-")

(defcustom tibetan-dharmamitra-api-base-url
  "https://dharmamitra.org/api-search"
  "Base URL for the DharmaMitra search backend.
The relative paths `/chat-translate/v1/chat/completions' and
`/primary/' are appended to this for the two endpoints."
  :type 'string
  :group 'tibetan-dharmamitra-api)

(defcustom tibetan-dharmamitra-api-token "sthiramati"
  "Bearer token for DharmaMitra API.  The default `sthiramati' is
the publicly-documented token; override only if DharmaMitra
issues a new one or you have a private deployment."
  :type 'string
  :group 'tibetan-dharmamitra-api)

(defcustom tibetan-dharmamitra-api-timeout 30
  "Timeout in seconds for individual DharmaMitra HTTP requests.
chat-translate streams typically complete in 1-2 seconds; search
takes 2-7 seconds.  The default 30 leaves headroom for slow links."
  :type 'integer
  :group 'tibetan-dharmamitra-api)

;; ============================================================================
;; CACHE
;; ============================================================================

(defvar tibetan-dharmamitra-api--cache
  (make-hash-table :test 'equal)
  "In-memory cache for DharmaMitra API responses.
Keyed on a `(endpoint . sha256-of-body)' cons cell so identical
requests dedupe across the public API; cleared by
`tibetan-dharmamitra-api-clear-cache'.")

(defun tibetan-dharmamitra-api--cache-key (endpoint body)
  "Return cache key for ENDPOINT (string) + BODY (JSON string).
Body hash decouples key length from input length and folds
semantically-equivalent requests together."
  (cons endpoint (secure-hash 'sha256 body)))

;;;###autoload
(defun tibetan-dharmamitra-api-clear-cache ()
  "Clear the DharmaMitra API in-memory cache."
  (interactive)
  (clrhash tibetan-dharmamitra-api--cache)
  (when (called-interactively-p 'any)
    (message "DharmaMitra API cache cleared")))

;; ============================================================================
;; SSE STREAM PARSER (pure function — testable without network)
;; ============================================================================

(defun tibetan-dharmamitra-api--parse-sse-stream (stream)
  "Parse an OpenAI-style Server-Sent-Events STREAM string.

Walks lines starting with `data: ', extracts JSON payloads, and
concatenates the `choices[0].delta.content' field of each chunk.
Stops at `data: [DONE]'.  Malformed JSON and non-data lines
(`event:', `id:', heartbeat comments) are silently skipped.

Returns the accumulated content as a string (possibly empty if
the stream contained no content chunks).  Never signals.

This is the pure parsing kernel behind
`tibetan-dharmamitra-api-chat-translate'; the public function
adds caching and HTTP I/O around it."
  (let ((result ""))
    (when (stringp stream)
      (dolist (line (split-string stream "\n" t))
        (when (string-prefix-p "data:" line)
          ;; Tolerate both `data: {…}' and `data:{…}' framings — the
          ;; space after the colon is optional in SSE and some servers/
          ;; proxies omit it.  Strip the leading whitespace (if any)
          ;; from the payload.
          (let ((payload (string-trim-left (substring line 5))))
            (unless (string= payload "[DONE]")
              (condition-case nil
                  (let* ((obj (json-parse-string payload
                                                 :object-type 'alist
                                                 :array-type 'list))
                         (choices (alist-get 'choices obj))
                         (first (car-safe choices))
                         (delta (and first (alist-get 'delta first)))
                         (content (and delta (alist-get 'content delta))))
                    (when (and content (stringp content))
                      (setq result (concat result content))))
                (error nil)))))))
    result))

;; ============================================================================
;; REQUEST BODY BUILDERS (pure functions)
;; ============================================================================

(defun tibetan-dharmamitra-api--build-chat-translate-body
    (text &rest args)
  "Build JSON request body for the chat-translate endpoint.

TEXT is the source content.  ARGS is a plist supporting:
  :target-lang     Default `english' — passed verbatim to DM.
  :input-encoding  Default `auto' — auto / tibetan / wylie / iast / dev / hk.

Returns a JSON-encoded string ready for the request body."
  (let ((target-lang (or (plist-get args :target-lang) "english"))
        (input-encoding (or (plist-get args :input-encoding) "auto")))
    (json-encode
     `((model . "gpt-3.5-turbo")
       (messages . [((role . "user") (content . ,text))])
       (stream . t)
       (temperature . 0.1)
       (do_grammar . :json-false)
       (input_encoding . ,input-encoding)
       (target_lang . ,target-lang)))))

(defun tibetan-dharmamitra-api--build-search-body (input &rest args)
  "Build JSON request body for the primary search endpoint.

INPUT is the search query (text in any supported language).
ARGS is a plist supporting:
  :source-lang    Default `auto' — auto / bo / sa / zh / pa / all.
                  Sets `filter_source_language' on the request.
  :target-lang    Default `all' — same enum.  Sets
                  `filter_target_language'.
  :include-files  Optional list of source IDs to constrain the
                  corpus to specific works (e.g.
                  `(\"SA_T06_bsa034\" \"BO_T06_D4037\")').
  :max-depth      Default 50 — caps the number of returned hits.

Returns a JSON-encoded string."
  (let ((source-lang (or (plist-get args :source-lang) "auto"))
        (target-lang (or (plist-get args :target-lang) "all"))
        (include-files (plist-get args :include-files))
        (max-depth (or (plist-get args :max-depth) 50)))
    (json-encode
     `((search_input . ,input)
       (input_encoding . "auto")
       (search_type . "semantic")
       (semantic_type . "both")
       (filter_source_language . ,source-lang)
       (filter_target_language . ,target-lang)
       (source_filters . ((include_files . ,(vconcat include-files))
                          (include_categories . [])
                          (include_collections . [])))
       (do_ranking . t)
       (max_depth . ,max-depth)))))

;; ============================================================================
;; HTTP WRAPPER (isolated for stub-friendliness)
;; ============================================================================

(defun tibetan-dharmamitra-api--http-post (endpoint body)
  "POST BODY (string) to ENDPOINT (relative path under base URL).

Returns response body as a UTF-8 decoded string, or signals an
error.  Synchronous; respects
`tibetan-dharmamitra-api-timeout'.

Tests stub this function via `cl-letf' so callers exercise the
rest of the pipeline without touching the network."
  (let* ((url (concat tibetan-dharmamitra-api-base-url endpoint))
         (url-request-method "POST")
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("Authorization" . ,(format "Bearer %s"
                                        tibetan-dharmamitra-api-token))
            ("Accept" . "application/json")))
         (url-request-data (encode-coding-string body 'utf-8))
         ;; Enforce TLS certificate verification.  Emacs' default
         ;; `gnutls-verify-error' is nil — cert failures would NOT abort
         ;; the connection, so the bearer token would be sent and the
         ;; response trusted over an unverified (MITM-able) channel.
         (gnutls-verify-error t)
         (network-security-level 'high))
    (with-current-buffer
        (url-retrieve-synchronously url nil nil
                                    tibetan-dharmamitra-api-timeout)
      (unwind-protect
          (progn
            (goto-char (point-min))
            ;; Skip past HTTP headers (terminated by an empty line).
            (when (re-search-forward "^$" nil t)
              (forward-char 1))
            (decode-coding-string
             (buffer-substring-no-properties (point) (point-max))
             'utf-8))
        (kill-buffer (current-buffer))))))

;; ============================================================================
;; PUBLIC API — chat-translate
;; ============================================================================

;;;###autoload
(cl-defun tibetan-dharmamitra-api-chat-translate
    (text &key (target-lang "english") (input-encoding "auto"))
  "Translate TEXT via DharmaMitra's chat-translate endpoint.

TARGET-LANG defaults to `english'.  INPUT-ENCODING defaults to
`auto' — DM auto-detects IAST / Devanagari / Tibetan Unicode /
Wylie.  Override only when auto-detection misbehaves on edge
cases (mixed-script input).

Returns the translation as a string, or nil on:
  - HTTP failure (network, 4xx/5xx, timeout)
  - empty SSE stream (no content chunks)
  - JSON parse failure on every chunk

Cached by request body hash; identical re-invocations return
without an HTTP call.  Use
`tibetan-dharmamitra-api-clear-cache' to invalidate."
  (let* ((body (tibetan-dharmamitra-api--build-chat-translate-body
                text :target-lang target-lang
                :input-encoding input-encoding))
         (key (tibetan-dharmamitra-api--cache-key
               "/chat-translate/v1/chat/completions" body))
         (cached (gethash key tibetan-dharmamitra-api--cache)))
    (or cached
        (condition-case err
            (let* ((sse-response
                    (tibetan-dharmamitra-api--http-post
                     "/chat-translate/v1/chat/completions" body))
                   (translation
                    (and sse-response
                         (tibetan-dharmamitra-api--parse-sse-stream
                          sse-response))))
              (cond
               ;; Happy path: non-empty translation.
               ((and translation (not (string-empty-p translation)))
                (puthash key translation tibetan-dharmamitra-api--cache)
                translation)
               ;; HTTP returned nothing — likely rate-limit or server
               ;; error without a parseable body.  Phase 9 (2026-04-30):
               ;; log explicitly so silent failures are visible in
               ;; *Messages* during diagnosis.
               ((or (null sse-response) (string-empty-p sse-response))
                (message
                 "DharmaMitra chat-translate: empty response (input %d chars) — likely rate-limit or server error"
                 (length (or text "")))
                nil)
               ;; SSE stream had no content chunks.  Either format
               ;; change or an error response masquerading as success.
               (t
                (message
                 "DharmaMitra chat-translate: SSE stream yielded no content (response %d bytes; first 100 chars: %s)"
                 (length sse-response)
                 (substring sse-response 0
                            (min 100 (length sse-response))))
                nil)))
          (error
           (message "DharmaMitra chat-translate failed: %s"
                    (error-message-string err))
           nil)))))

;; ============================================================================
;; PUBLIC API — primary search
;; ============================================================================

;;;###autoload
(cl-defun tibetan-dharmamitra-api-search
    (input &key (source-lang "auto") (target-lang "all")
           include-files (max-depth 50))
  "Search the DharmaMitra primary corpus for INPUT.

INPUT is a query in any supported language; encoding is
auto-detected.  See
`tibetan-dharmamitra-api--build-search-body' for the keyword
arguments — :source-lang, :target-lang, :include-files,
:max-depth.

Returns a list of result alists, each with keys `id', `lang',
`source', `segmentnr', `text', `text_new', `title', `summary',
`src_link', `query'.  Returns nil on:
  - HTTP failure
  - empty results array
  - JSON parse failure

Cached by request body hash; clear with
`tibetan-dharmamitra-api-clear-cache'."
  (let* ((body (tibetan-dharmamitra-api--build-search-body
                input :source-lang source-lang
                :target-lang target-lang
                :include-files include-files
                :max-depth max-depth))
         (key (tibetan-dharmamitra-api--cache-key "/primary/" body))
         (cached (gethash key tibetan-dharmamitra-api--cache)))
    (or cached
        (condition-case err
            (let* ((response-str (tibetan-dharmamitra-api--http-post
                                  "/primary/" body))
                   (response (when (and response-str
                                        (not (string-empty-p response-str)))
                               (json-parse-string response-str
                                                  :object-type 'alist
                                                  :array-type 'list)))
                   (results (and response (alist-get 'results response))))
              (cond
               (results
                (puthash key results tibetan-dharmamitra-api--cache)
                results)
               ;; Phase 9 (2026-04-30): explicit logging when search
               ;; returns empty / no results, instead of silent nil.
               ((or (null response-str) (string-empty-p response-str))
                (message
                 "DharmaMitra search: empty response (query %d chars, sources %s) — likely rate-limit"
                 (length (or input ""))
                 (or include-files "all"))
                nil)
               ((null response)
                (message
                 "DharmaMitra search: response unparseable as JSON (%d bytes); first 100 chars: %s"
                 (length response-str)
                 (substring response-str 0
                            (min 100 (length response-str))))
                nil)
               (t
                (message
                 "DharmaMitra search: zero results (query %d chars, sources %s)"
                 (length (or input ""))
                 (or include-files "all"))
                nil)))
          (error
           (message "DharmaMitra search failed: %s"
                    (error-message-string err))
           nil)))))

(provide 'tibetan-dharmamitra-api)
;;; tibetan-dharmamitra-api.el ends here
