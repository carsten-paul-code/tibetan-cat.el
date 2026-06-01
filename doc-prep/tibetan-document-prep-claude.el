;;; tibetan-document-prep-claude.el --- Async Claude metadata pre-fill -*- lexical-binding: t -*-

;;; Commentary:
;; §5.27 Phase 4 (2026-05-27):  given a freshly-converted Tibetan
;; source file, ask Claude (asynchronously, via the shared throttled
;; queue) to suggest:
;;
;;   · GENRE (one of the 14 keys in `tibetan-document-genre-taxonomy')
;;   · AUTHOR (a likely attribution, or "unknown")
;;   · CONTEXT (1-3 historical / textual / doctrinal lines)
;;
;; The wizard fires this call early and proceeds without blocking;
;; Claude's response is cached as a buffer-local plist
;; (`tibetan-document-prep--claude-suggestions') and announced via
;; `message'.  The user reviews via
;; `tibetan-document-prep-apply-claude-suggestions' which writes the
;; suggestions into the source file's `#+TIBETAN_TEXT_TYPE:' /
;; `#+TIBETAN_AUTHOR:' / `#+TIBETAN_CLAUDE_CONTEXT:' headers.
;;
;; Composition:  uses `tibetan-claude-queue-submit' for throttling
;; (same backoff / retry semantics as the per-segment Claude calls)
;; and `gptel-request' for the actual HTTP call.  No new auth
;; surface.

;;; Code:

(require 'cl-lib)
(require 'tibetan-document-genres)

;; Forward declarations — runtime guarded by `fboundp', so a missing
;; gptel / queue gracefully degrades to "feature disabled".
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(declare-function tibetan-claude-queue-submit "tibetan-claude-queue"
                  (thunk &rest args))

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-document-prep-claude nil
  "Async Claude metadata pre-fill for the document-preparation wizard."
  :group 'tibetan-doc-prep
  :prefix "tibetan-document-prep-claude-")

(defcustom tibetan-document-prep-claude-excerpt-words 200
  "Word count of the Tibetan excerpt sent to Claude for metadata.

200 words is enough for a confident genre signal (verse meter,
honorific register, formulaic openings) without bloating the
context window.  Increase if Claude's suggestions feel under-
informed;  decrease to save tokens."
  :type 'integer
  :group 'tibetan-document-prep-claude)

;; ============================================================================
;; STATE
;; ============================================================================

(defvar-local tibetan-document-prep--claude-suggestions nil
  "Buffer-local plist of the latest Claude metadata suggestions.

Shape:
  (:genre KEY        ; symbol from `tibetan-document-genre-taxonomy'
                     ; or nil when Claude couldn't decide
   :author STR       ; suggested author name, or \"unknown\"
   :context LIST)    ; list of 1-3 context strings

Set by the wizard's async callback when Claude returns;  consumed
by `tibetan-document-prep-apply-claude-suggestions'.")

;; ============================================================================
;; PROMPT BUILDING
;; ============================================================================

(defun tibetan-document-prep--extract-body-excerpt (source-file)
  "Return the first ~N words of SOURCE-FILE's `* Tibetan Text' body.

N is `tibetan-document-prep-claude-excerpt-words'.  Returns nil
when the file is unreadable, the section is absent, or the body
is empty.  Skips org metadata headers and section headings — the
excerpt is pure body text, ready for Claude.

Words are split on whitespace;  Tibetan tshegs (U+0F0B) and
shads (U+0F0D) are preserved within each whitespace-separated
chunk so the excerpt remains parseable as Tibetan."
  (when (and source-file (file-exists-p source-file))
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text[ \t]*$" nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (save-excursion
                      (if (re-search-forward "^\\* " nil t)
                          (line-beginning-position)
                        (point-max))))
               (body (buffer-substring-no-properties start end))
               ;; Drop org sub-headings and PROPERTIES drawers so the
               ;; excerpt is body text only.
               (clean (replace-regexp-in-string
                       "^\\*+ .*$" "" body))
               (clean (replace-regexp-in-string
                       ":PROPERTIES:[\0-\377[:nonascii:]]*?:END:" "" clean))
               (words (split-string clean "[ \t\n]+" t)))
          (when words
            (mapconcat #'identity
                       (cl-subseq words 0
                                  (min (length words)
                                       tibetan-document-prep-claude-excerpt-words))
                       " ")))))))

(defun tibetan-document-prep--build-system-prompt ()
  "Return the system prompt instructing Claude to emit JSON metadata.

Enumerates the 14 canonical genre keys so Claude picks from the
exact set the wizard's selectbox understands;  asks for a tightly
shaped JSON response so the parser stays simple."
  (concat
   "You are an expert in classical and post-classical Tibetan "
   "literature.  Given a short excerpt from a Tibetan-language "
   "source, identify:\n\n"
   "  1. GENRE — pick exactly ONE of these keys (use the bare key, "
   "not the label):\n"
   (mapconcat
    (lambda (entry)
      (let ((key (car entry))
            (plist (cdr entry)))
        (format "       %s — %s"
                (symbol-name key)
                (plist-get plist :description))))
    tibetan-document-genre-taxonomy "\n")
   "\n\n"
   "  2. AUTHOR — a likely attribution as a single short string, "
   "or the literal string \"unknown\" if uncertain.\n\n"
   "  3. CONTEXT — 1 to 3 short lines of historical / textual / "
   "doctrinal background (each line ≤ 100 characters).\n\n"
   "Respond ONLY with a single JSON object, no preamble, no "
   "explanation, no code-fence markers.  Use this exact schema:\n\n"
   "  {\n"
   "    \"genre\": \"<key>\",\n"
   "    \"author\": \"<name or unknown>\",\n"
   "    \"context\": [\"<line 1>\", \"<line 2>\"]\n"
   "  }"))

(defun tibetan-document-prep--build-user-prompt (excerpt)
  "Wrap EXCERPT in the user-prompt frame Claude expects."
  (concat "Tibetan excerpt (first ~"
          (number-to-string tibetan-document-prep-claude-excerpt-words)
          " words):\n\n"
          excerpt))

;; ============================================================================
;; RESPONSE PARSING
;; ============================================================================

(defun tibetan-document-prep--strip-code-fence (response)
  "Return RESPONSE with surrounding ```json … ``` fences removed.

Claude occasionally wraps a JSON response in code fences despite
explicit instructions.  We strip them so the parser sees clean
JSON.  Idempotent — input without fences passes through."
  (when (stringp response)
    (let ((trimmed (string-trim response)))
      (cond
       ((string-match
         "\\`\\(?:```[a-zA-Z]*\n\\)?\\(\\(?:.\\|\n\\)*?\\)\\(?:\n?```\\)?\\'"
         trimmed)
        (string-trim (match-string 1 trimmed)))
       (t trimmed)))))

(defun tibetan-document-prep--parse-claude-response (response)
  "Parse Claude's JSON RESPONSE into a metadata plist.

Returns:
  (:genre KEY-SYMBOL-OR-NIL
   :author STRING-OR-NIL
   :context LIST-OF-STRINGS)

Unknown / malformed JSON → nil (caller falls back to no-suggestion
behaviour).  Unknown genre keys (not in the taxonomy) → :genre nil,
other fields preserved.  Author = \"unknown\" → :author nil so the
wizard knows to fall through to the manual prompt."
  (when (and response (stringp response))
    (condition-case nil
        (let* ((stripped (tibetan-document-prep--strip-code-fence response))
               (parsed (let ((json-object-type 'alist)
                             (json-array-type 'list)
                             (json-key-type 'string)
                             (json-null nil)
                             (json-false nil))
                         (json-read-from-string stripped)))
               (genre-str (cdr (assoc "genre" parsed)))
               (author-str (cdr (assoc "author" parsed)))
               (context (cdr (assoc "context" parsed)))
               (genre-key (and genre-str
                               (stringp genre-str)
                               (let ((sym (intern (downcase
                                                   (string-trim genre-str)))))
                                 (and (memq sym
                                            (tibetan-document-genres-keys))
                                      sym))))
               (author (and author-str
                            (stringp author-str)
                            (let ((s (string-trim author-str)))
                              (and (not (string-empty-p s))
                                   (not (string= "unknown" (downcase s)))
                                   s))))
               (context-clean
                (and (listp context)
                     (cl-remove-if-not
                      #'stringp
                      (mapcar (lambda (s)
                                (and (stringp s) (string-trim s)))
                              context)))))
          (list :genre genre-key
                :author author
                :context context-clean))
      (error nil))))

;; ============================================================================
;; HEADER WRITING  ------------------------------------------------------------
;; ============================================================================

(defun tibetan-document-prep--upsert-single-line-header (key value)
  "In the current buffer, set `#+KEY: VALUE' (single-line header).

Replaces an existing matching line in place;  otherwise inserts
after the last existing `#+TIBETAN_…' / `#+TITLE:' line so the
metadata block stays contiguous."
  (let ((line (format "#+%s: %s" key value))
        (regexp (format "^#\\+%s:[ \t]*.*$" (regexp-quote key))))
    (goto-char (point-min))
    (cond
     ((re-search-forward regexp nil t)
      (replace-match line t t))
     (t
      (goto-char (point-min))
      (let ((insert-after
             (save-excursion
               (or (and (re-search-forward
                         "^#\\+\\(TIBETAN_[A-Z_]+\\|TITLE\\):"
                         nil t)
                        ;; Walk to the LAST contiguous header line.
                        (let ((last (line-beginning-position)))
                          (forward-line 1)
                          (while (looking-at-p "^#\\+")
                            (setq last (line-beginning-position))
                            (forward-line 1))
                          last))
                   (point-min)))))
        (goto-char insert-after)
        (end-of-line)
        (insert "\n" line))))))

(defun tibetan-document-prep--append-context-lines (lines)
  "In the current buffer, append `#+TIBETAN_CLAUDE_CONTEXT: <line>'
for each entry in LINES (a list of strings).  Existing context
lines are preserved — the new ones go AFTER the last one (or
after the final `#+TIBETAN_…' header when none exist yet)."
  (when lines
    (goto-char (point-min))
    (let ((last-context-pos
           (save-excursion
             (let (found)
               (while (re-search-forward
                       "^#\\+TIBETAN_CLAUDE_CONTEXT:.*$" nil t)
                 (setq found (point)))
               found))))
      (cond
       (last-context-pos
        (goto-char last-context-pos)
        (end-of-line))
       (t
        ;; Land after the last existing metadata line.
        (goto-char (point-min))
        (let ((insert-after (point-min)))
          (while (re-search-forward
                  "^#\\+\\(TIBETAN_[A-Z_]+\\|TITLE\\):.*$" nil t)
            (setq insert-after (line-end-position)))
          (goto-char insert-after))))
      ;; Collect the context values already in the buffer so we don't
      ;; append duplicates — re-running the wizard / re-applying Claude
      ;; suggestions must be idempotent rather than accumulating
      ;; identical #+TIBETAN_CLAUDE_CONTEXT: lines.
      (let ((seen (save-excursion
                    (goto-char (point-min))
                    (let (vals)
                      (while (re-search-forward
                              "^#\\+TIBETAN_CLAUDE_CONTEXT: *\\(.*\\)$" nil t)
                        (push (string-trim (match-string 1)) vals))
                      vals))))
        (dolist (line lines)
          (let ((clean (string-trim line)))
            (unless (or (string-empty-p clean) (member clean seen))
              (push clean seen)
              (insert (format "\n#+TIBETAN_CLAUDE_CONTEXT: %s" clean)))))))))

(defun tibetan-document-prep--apply-suggestions (source-file plist)
  "Write the suggestion PLIST's headers into SOURCE-FILE.

Three header kinds are touched (each only when its value is
non-nil):
  · :genre   → `#+TIBETAN_TEXT_TYPE:'      (replaces existing)
  · :author  → `#+TIBETAN_AUTHOR:'         (replaces existing)
  · :context → appends one `#+TIBETAN_CLAUDE_CONTEXT:' per line
               (existing context lines are preserved)

No-op when SOURCE-FILE is unreadable or PLIST is nil.  Returns the
SOURCE-FILE path on success."
  (when (and source-file
             (file-exists-p source-file)
             (file-writable-p source-file)
             plist)
    (let ((genre (plist-get plist :genre))
          (author (plist-get plist :author))
          (context (plist-get plist :context)))
      (with-temp-buffer
        (insert-file-contents source-file)
        (when genre
          (tibetan-document-prep--upsert-single-line-header
           "TIBETAN_TEXT_TYPE" (symbol-name genre)))
        (when (and author (stringp author) (not (string-empty-p author)))
          (tibetan-document-prep--upsert-single-line-header
           "TIBETAN_AUTHOR" author))
        (when context
          (tibetan-document-prep--append-context-lines context))
        (write-region (point-min) (point-max) source-file))
      source-file)))

;; ============================================================================
;; ASYNC SUBMIT
;; ============================================================================

(defun tibetan-document-prep--ask-claude (source-file callback)
  "Submit a Claude metadata-suggestion request for SOURCE-FILE.

Builds the excerpt + prompts, dispatches via
`tibetan-claude-queue-submit' (so throttle / retry / rate-limit
handling is shared with the rest of the Claude pipeline), and on
success invokes CALLBACK with the parsed suggestion plist (or nil
when Claude returned an unparseable / empty body).

Signals a `user-error' when the prerequisites are missing
\(gptel not loaded, queue not loaded, source unreadable, body
section absent) so callers see the actionable hint without a
silent failure."
  (unless (and source-file (file-exists-p source-file))
    (user-error "Source file not found:  %s" source-file))
  (unless (functionp callback)
    (error "tibetan-document-prep--ask-claude:  CALLBACK must be a function"))
  (unless (fboundp 'tibetan-claude-queue-submit)
    (user-error "tibetan-claude-queue not loaded — async pre-fill disabled"))
  (unless (and (featurep 'gptel) (fboundp 'gptel-request))
    (user-error "gptel not loaded — async pre-fill disabled"))
  (let ((excerpt (tibetan-document-prep--extract-body-excerpt source-file)))
    (unless (and excerpt (not (string-empty-p excerpt)))
      (user-error
       "Source has no `* Tibetan Text' body — nothing to send to Claude"))
    (let ((system-prompt (tibetan-document-prep--build-system-prompt))
          (user-prompt (tibetan-document-prep--build-user-prompt excerpt))
          (label (format "doc-prep-claude:%s"
                         (file-name-nondirectory source-file))))
      (tibetan-claude-queue-submit
       (lambda (done)
         (condition-case err
             (gptel-request
              user-prompt
              :system system-prompt
              :callback
              (lambda (response _info)
                (condition-case cb-err
                    (let ((parsed
                           (and (stringp response)
                                (tibetan-document-prep--parse-claude-response
                                 response))))
                      (funcall callback parsed))
                  (error
                   (message "Claude metadata callback error:  %s"
                            (error-message-string cb-err))
                   (funcall callback nil)))
                (funcall done)))
           (error
            (message "Claude metadata request error:  %s"
                     (error-message-string err))
            (funcall callback nil)
            (funcall done))))
       :label label))))

;; ============================================================================
;; INTERACTIVE COMMAND
;; ============================================================================

;;;###autoload
(defun tibetan-document-prep-apply-claude-suggestions ()
  "Apply the cached Claude metadata suggestions to the current buffer.

Reads from `tibetan-document-prep--claude-suggestions' (buffer-
local;  set by the wizard's async callback).  Writes the
suggestion plist's `:genre' / `:author' / `:context' fields into
the buffer's file as `#+TIBETAN_TEXT_TYPE:' / `#+TIBETAN_AUTHOR:' /
`#+TIBETAN_CLAUDE_CONTEXT:' headers, then reverts the buffer to
pick up the new content.

When no cached suggestions exist (Claude hasn't returned yet, or
the wizard wasn't run) the command prints a polite message and
returns nil.  Use \\[tibetan-document-prep-wizard] to kick off a
fresh metadata fetch."
  (interactive)
  (let ((suggestions tibetan-document-prep--claude-suggestions)
        (path (buffer-file-name)))
    (cond
     ((null suggestions)
      (message "No cached Claude metadata suggestions for this buffer — \
re-run the wizard to fetch."))
     ((null path)
      (user-error "Buffer is not visiting a file — can't write headers"))
     (t
      (tibetan-document-prep--apply-suggestions path suggestions)
      (revert-buffer t t t)
      (message "Applied Claude suggestions:  genre=%s  author=%s  context=%d line(s)"
               (or (plist-get suggestions :genre) "-")
               (or (plist-get suggestions :author) "-")
               (length (plist-get suggestions :context)))))))

(provide 'tibetan-document-prep-claude)
;;; tibetan-document-prep-claude.el ends here
