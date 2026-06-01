;;; tibetan-document-prep-claude-test.el --- §5.27 Phase 4 — Async Claude pre-fill -*- lexical-binding: t -*-

;;; Commentary:
;; ERT specs for `doc-prep/tibetan-document-prep-claude.el'.
;;
;; The Claude HTTP call is stubbed throughout — these tests cover
;; the LOGIC (excerpt extraction, prompt building, JSON parsing,
;; header writing, async-submit wiring) without depending on a live
;; gptel or network.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../doc-prep" dir)))

(require 'tibetan-document-genres)
(require 'tibetan-document-prep-claude)

;; ============================================================================
;; EXCERPT EXTRACTION
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-extract-excerpt-clean-source ()
  "First N words under `* Tibetan Text' are returned as a single
whitespace-joined string;  org sub-headings and PROPERTIES drawers
are stripped."
  (let ((dir (make-temp-file "claude-excerpt-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir))
              (tibetan-document-prep-claude-excerpt-words 5))
          (with-temp-file src
            (insert "#+TITLE: T\n* Tibetan Text\n"
                    "*** Segment 1\n:PROPERTIES:\n:FOLIO: D1a1\n:END:\n"
                    "alpha beta gamma delta epsilon zeta\n"))
          (let ((excerpt
                 (tibetan-document-prep--extract-body-excerpt src)))
            (should (stringp excerpt))
            ;; Five words — matches the configured limit.
            (should (= 5 (length (split-string excerpt))))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-extract-excerpt-no-section ()
  "No `* Tibetan Text' section → nil (caller raises user-error)."
  (let ((dir (make-temp-file "claude-noexcerpt-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n* Notes\nx\n"))
          (should-not
           (tibetan-document-prep--extract-body-excerpt src)))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-extract-excerpt-respects-word-cap ()
  "When the body has FEWER than N words the excerpt is the full
body — no padding, no error."
  (let ((dir (make-temp-file "claude-cap-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir))
              (tibetan-document-prep-claude-excerpt-words 200))
          (with-temp-file src
            (insert "* Tibetan Text\nalpha beta gamma\n"))
          (let ((excerpt
                 (tibetan-document-prep--extract-body-excerpt src)))
            (should (= 3 (length (split-string excerpt))))))
      (delete-directory dir t))))

;; ============================================================================
;; PROMPT BUILDING
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-system-prompt-lists-all-genres ()
  "System prompt enumerates every key in
`tibetan-document-genre-taxonomy' so Claude can only pick from the
exact set the wizard's selectbox accepts."
  (let ((prompt (tibetan-document-prep--build-system-prompt)))
    (should (stringp prompt))
    (dolist (key (tibetan-document-genres-keys))
      (should (string-match-p (regexp-quote (symbol-name key)) prompt)))))

(ert-deftest tibetan-document-prep-claude-system-prompt-specifies-json-shape ()
  "Prompt names the three required fields and the bare-JSON
\(no-code-fence) convention.  The parser depends on Claude
honouring this."
  (let ((prompt (tibetan-document-prep--build-system-prompt)))
    (should (string-match-p "\"genre\"" prompt))
    (should (string-match-p "\"author\"" prompt))
    (should (string-match-p "\"context\"" prompt))
    (should (string-match-p "no code-fence\\|no preamble\\|ONLY"
                            prompt))))

(ert-deftest tibetan-document-prep-claude-user-prompt-wraps-excerpt ()
  "User prompt mentions the excerpt with a recognisable preamble."
  (let ((prompt (tibetan-document-prep--build-user-prompt
                 "alpha beta gamma")))
    (should (string-match-p "Tibetan excerpt" prompt))
    (should (string-match-p "alpha beta gamma" prompt))))

;; ============================================================================
;; CODE-FENCE STRIPPING
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-strip-fence-plain-passthrough ()
  "Response without code-fences passes through unchanged
\(modulo trim)."
  (should (equal "{\"genre\": \"mgur\"}"
                 (tibetan-document-prep--strip-code-fence
                  "{\"genre\": \"mgur\"}"))))

(ert-deftest tibetan-document-prep-claude-strip-fence-json-block ()
  "Triple-backtick + `json' language tag is stripped."
  (should (equal "{\"genre\": \"mgur\"}"
                 (tibetan-document-prep--strip-code-fence
                  "```json\n{\"genre\": \"mgur\"}\n```"))))

(ert-deftest tibetan-document-prep-claude-strip-fence-bare-block ()
  "Triple-backtick without language tag is also stripped."
  (should (equal "{\"genre\": \"mgur\"}"
                 (tibetan-document-prep--strip-code-fence
                  "```\n{\"genre\": \"mgur\"}\n```"))))

;; ============================================================================
;; RESPONSE PARSING
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-parse-clean-response ()
  "Well-formed JSON with all three fields → plist with KEY symbol,
author string, context list of strings."
  (let* ((resp "{\"genre\": \"mgur\", \"author\": \"Milarepa\", \
\"context\": [\"11th-century Kagyü yogin\", \"Vajra-songs\"]}")
         (parsed (tibetan-document-prep--parse-claude-response resp)))
    (should (eq 'mgur (plist-get parsed :genre)))
    (should (equal "Milarepa" (plist-get parsed :author)))
    (should (equal '("11th-century Kagyü yogin" "Vajra-songs")
                   (plist-get parsed :context)))))

(ert-deftest tibetan-document-prep-claude-parse-response-with-code-fence ()
  "JSON wrapped in ```json fences is unwrapped before parsing."
  (let* ((resp "```json\n{\"genre\": \"rnam-thar\", \"author\": \
\"Tsang Nyon Heruka\", \"context\": [\"Hagiographer\"]}\n```")
         (parsed (tibetan-document-prep--parse-claude-response resp)))
    (should (eq 'rnam-thar (plist-get parsed :genre)))
    (should (equal "Tsang Nyon Heruka" (plist-get parsed :author)))))

(ert-deftest tibetan-document-prep-claude-parse-unknown-genre-key-is-nil ()
  "Genre key NOT in the taxonomy (`foo-bar') → :genre nil;  other
fields still populate (caller falls back to manual genre prompt)."
  (let* ((resp "{\"genre\": \"foo-bar\", \"author\": \"X\", \
\"context\": []}")
         (parsed (tibetan-document-prep--parse-claude-response resp)))
    (should-not (plist-get parsed :genre))
    (should (equal "X" (plist-get parsed :author)))))

(ert-deftest tibetan-document-prep-claude-parse-author-unknown-becomes-nil ()
  "Author = \"unknown\" (case-insensitive) → :author nil so wizard
prompts the user.  Distinguishes \"Claude doesn't know\" from
\"Claude has a name\"."
  (dolist (val '("unknown" "Unknown" "UNKNOWN"))
    (let* ((resp (format "{\"genre\": \"mgur\", \"author\": \"%s\", \
\"context\": []}" val))
           (parsed (tibetan-document-prep--parse-claude-response resp)))
      (should-not (plist-get parsed :author))
      (should (eq 'mgur (plist-get parsed :genre))))))

(ert-deftest tibetan-document-prep-claude-parse-malformed-json-is-nil ()
  "Unparseable response → nil plist (caller skips the apply step)."
  (should-not (tibetan-document-prep--parse-claude-response
               "not json at all"))
  (should-not (tibetan-document-prep--parse-claude-response
               "{\"genre\": \"mgur\""))) ; truncated

(ert-deftest tibetan-document-prep-claude-parse-nil-input-is-nil ()
  "Nil / empty input → nil (defensive — callback may receive nil
when gptel times out)."
  (should-not (tibetan-document-prep--parse-claude-response nil))
  (should-not (tibetan-document-prep--parse-claude-response "")))

(ert-deftest tibetan-document-prep-claude-parse-context-non-strings-filtered ()
  "Context entries that are NOT strings get filtered out;  remaining
string entries are trimmed."
  (let* ((resp "{\"genre\": \"mgur\", \"author\": \"X\", \
\"context\": [\"  line 1  \", 42, null, \"line 2\"]}")
         (parsed (tibetan-document-prep--parse-claude-response resp)))
    (should (equal '("line 1" "line 2") (plist-get parsed :context)))))

;; ============================================================================
;; HEADER WRITING — single-line upsert
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-upsert-replaces-existing ()
  "Existing `#+TIBETAN_TEXT_TYPE:' line is replaced in place — no
duplicate header is left behind."
  (with-temp-buffer
    (insert "#+TITLE: T\n#+TIBETAN_TEXT_TYPE: classical\n")
    (tibetan-document-prep--upsert-single-line-header
     "TIBETAN_TEXT_TYPE" "mgur")
    (let ((out (buffer-string)))
      (should (string-match-p "#\\+TIBETAN_TEXT_TYPE: mgur" out))
      (should-not (string-match-p
                   "#\\+TIBETAN_TEXT_TYPE: classical" out))
      ;; Exactly one occurrence.
      (should (= 1 (cl-count "TIBETAN_TEXT_TYPE"
                             (split-string out "\n")
                             :test
                             (lambda (needle line)
                               (string-match-p needle line))))))))

(ert-deftest tibetan-document-prep-claude-upsert-inserts-after-title ()
  "No existing header → new line is inserted after the LAST `#+'
metadata line, keeping the metadata block contiguous."
  (with-temp-buffer
    (insert "#+TITLE: T\n#+OPTIONS: toc:nil\n\n* Tibetan Text\nx\n")
    (tibetan-document-prep--upsert-single-line-header
     "TIBETAN_AUTHOR" "Milarepa")
    (let* ((out (buffer-string))
           (lines (split-string out "\n")))
      (should (string-match-p "#\\+TIBETAN_AUTHOR: Milarepa" out))
      ;; Header lands AFTER the last #+ line and BEFORE the body.
      (should (string-match-p "#\\+TIBETAN_AUTHOR" (nth 2 lines))))))

;; ============================================================================
;; HEADER WRITING — context append
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-append-context-no-existing ()
  "First context-line write inserts after the metadata block."
  (with-temp-buffer
    (insert "#+TITLE: T\n\n* Tibetan Text\nx\n")
    (tibetan-document-prep--append-context-lines
     '("11th-century Kagyü yogin" "Vajra-songs"))
    (let ((out (buffer-string)))
      (should (string-match-p
               "#\\+TIBETAN_CLAUDE_CONTEXT: 11th-century" out))
      (should (string-match-p
               "#\\+TIBETAN_CLAUDE_CONTEXT: Vajra-songs" out)))))

(ert-deftest tibetan-document-prep-claude-append-context-preserves-existing ()
  "Existing context lines are kept;  new lines land AFTER the
last existing one — never re-ordering or removing."
  (with-temp-buffer
    (insert "#+TITLE: T\n"
            "#+TIBETAN_CLAUDE_CONTEXT: Pre-existing line\n"
            "\n* Tibetan Text\nx\n")
    (tibetan-document-prep--append-context-lines
     '("New line"))
    (let ((out (buffer-string)))
      (should (string-match-p
               "#\\+TIBETAN_CLAUDE_CONTEXT: Pre-existing line" out))
      (should (string-match-p
               "#\\+TIBETAN_CLAUDE_CONTEXT: New line" out))
      ;; Order:  pre-existing must come BEFORE new.
      (should (< (string-match
                  "#\\+TIBETAN_CLAUDE_CONTEXT: Pre-existing" out)
                 (string-match
                  "#\\+TIBETAN_CLAUDE_CONTEXT: New line" out))))))

(ert-deftest tibetan-document-prep-claude-append-context-dedups ()
  "A context line that already exists is NOT appended again — so
re-running the wizard / re-applying Claude suggestions is idempotent
rather than accumulating duplicate `#+TIBETAN_CLAUDE_CONTEXT:' lines.
Also dedups within the LINES argument itself."
  (with-temp-buffer
    (insert "#+TITLE: T\n"
            "#+TIBETAN_CLAUDE_CONTEXT: Existing context\n"
            "\n* Tibetan Text\nx\n")
    ;; Re-append the existing line plus a duplicate-in-list new line.
    (tibetan-document-prep--append-context-lines
     '("Existing context" "Fresh line" "Fresh line"))
    (let* ((out (buffer-string))
           (count (lambda (s)
                    (cl-count-if
                     (lambda (l)
                       (string= l (format "#+TIBETAN_CLAUDE_CONTEXT: %s" s)))
                     (split-string out "\n")))))
      (should (= 1 (funcall count "Existing context")))
      (should (= 1 (funcall count "Fresh line"))))))

(ert-deftest tibetan-document-prep-claude-append-context-skips-empty-entries ()
  "Empty / whitespace-only entries in LINES are silently dropped —
no `#+TIBETAN_CLAUDE_CONTEXT:  ' line appears in the output."
  (with-temp-buffer
    (insert "#+TITLE: T\n\n* Tibetan Text\nx\n")
    (tibetan-document-prep--append-context-lines
     '("" "  " "Real line" ""))
    (let ((out (buffer-string)))
      (should (string-match-p
               "#\\+TIBETAN_CLAUDE_CONTEXT: Real line" out))
      ;; One context line total — not three.
      (should (= 1 (cl-count
                    "TIBETAN_CLAUDE_CONTEXT"
                    (split-string out "\n")
                    :test (lambda (n l) (string-match-p n l))))))))

;; ============================================================================
;; APPLY-SUGGESTIONS — end-to-end
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-apply-writes-all-three-headers ()
  "End-to-end:  apply-suggestions writes
`#+TIBETAN_TEXT_TYPE' / `#+TIBETAN_AUTHOR' / N x
`#+TIBETAN_CLAUDE_CONTEXT' into the source file."
  (let ((dir (make-temp-file "claude-apply-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\nfoo //\n"))
          (tibetan-document-prep--apply-suggestions
           src
           '(:genre mgur
             :author "Milarepa"
             :context ("11th-century Kagyü" "Vajra-songs")))
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "#\\+TIBETAN_TEXT_TYPE: mgur" out))
            (should (string-match-p "#\\+TIBETAN_AUTHOR: Milarepa" out))
            (should (string-match-p
                     "#\\+TIBETAN_CLAUDE_CONTEXT: 11th-century" out))
            (should (string-match-p
                     "#\\+TIBETAN_CLAUDE_CONTEXT: Vajra-songs" out))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-apply-nil-plist-is-noop ()
  "Nil PLIST = nothing to apply → no file mutation."
  (let ((dir (make-temp-file "claude-noop-" t)))
    (unwind-protect
        (let* ((src (expand-file-name "source.org" dir))
               (before nil))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (setq before (with-temp-buffer (insert-file-contents src)
                                         (buffer-string)))
          (tibetan-document-prep--apply-suggestions src nil)
          (should (equal before
                         (with-temp-buffer (insert-file-contents src)
                                           (buffer-string)))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-apply-partial-plist ()
  "PLIST with only `:genre' present → only the text-type header is
touched;  author + context are untouched."
  (let ((dir (make-temp-file "claude-partial-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (tibetan-document-prep--apply-suggestions
           src '(:genre mdo :author nil :context nil))
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "#\\+TIBETAN_TEXT_TYPE: mdo" out))
            (should-not (string-match-p "#\\+TIBETAN_AUTHOR" out))
            (should-not
             (string-match-p "#\\+TIBETAN_CLAUDE_CONTEXT" out))))
      (delete-directory dir t))))

;; ============================================================================
;; ASK-CLAUDE — queue wiring (stubbed)
;; ============================================================================

(ert-deftest tibetan-document-prep-claude-ask-errors-without-gptel ()
  "Pre-flight gate:  gptel not loaded → `user-error'.  Guards
against firing a request that would silently no-op."
  (let ((dir (make-temp-file "claude-ask-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src
            (insert "* Tibetan Text\nfoo bar baz //\n"))
          (cl-letf
              (((symbol-function 'tibetan-claude-queue-submit)
                (lambda (&rest _) nil))
               ((symbol-function 'featurep)
                (lambda (sym) (not (eq sym 'gptel)))))
            (should-error
             (tibetan-document-prep--ask-claude src #'ignore)
             :type 'user-error)))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-ask-errors-on-missing-body ()
  "Source without `* Tibetan Text' → `user-error' before submit
\(no point spending a Claude call on an empty body)."
  (let ((dir (make-temp-file "claude-empty-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n* Notes\nx\n"))
          (cl-letf
              (((symbol-function 'tibetan-claude-queue-submit)
                (lambda (&rest _) nil))
               ((symbol-function 'featurep) (lambda (_) t))
               ((symbol-function 'gptel-request)
                (lambda (&rest _) nil)))
            (should-error
             (tibetan-document-prep--ask-claude src #'ignore)
             :type 'user-error)))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-claude-ask-submits-to-queue ()
  "Happy path:  `--ask-claude' calls `tibetan-claude-queue-submit'
with a thunk and a meaningful `:label'.  We don't run the thunk —
just verify the queue was invoked."
  (let ((dir (make-temp-file "claude-submit-" t)))
    (unwind-protect
        (let* ((src (expand-file-name "source.org" dir))
               (captured-label nil)
               (captured-thunk nil))
          (with-temp-file src
            (insert "* Tibetan Text\nfoo bar baz //\n"))
          (cl-letf
              (((symbol-function 'tibetan-claude-queue-submit)
                (lambda (thunk &rest plist)
                  (setq captured-thunk thunk)
                  (setq captured-label (plist-get plist :label))))
               ((symbol-function 'featurep) (lambda (_) t))
               ((symbol-function 'gptel-request) (lambda (&rest _) nil)))
            (tibetan-document-prep--ask-claude src #'ignore))
          (should (functionp captured-thunk))
          (should (stringp captured-label))
          (should (string-match-p "source\\.org" captured-label)))
      (delete-directory dir t))))

(provide 'tibetan-document-prep-claude-test)
;;; tibetan-document-prep-claude-test.el ends here
