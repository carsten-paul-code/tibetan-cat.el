;;; tibetan-document-prep-wizard.el --- Unified Tibetan document prep wizard -*- lexical-binding: t -*-

;;; Commentary:
;; §5.27 Phase 6 (2026-05-27):  the top-level wizard that orchestrates
;; source acquisition (Wylie / OCR / paste / existing-file), metadata
;; headers (target language, genre, author, context, class mode,
;; sentence detail), and analysis kickoff into ONE guided flow.
;;
;; Replaces the previous fragmented six-+-step process where Carsten
;; had to bounce between the OCR wizard, the Python Wylie converter
;; (CLI), manual header editing, `tibetan-add-sentence-structure',
;; and `tibetan-auto-analyze-document'.
;;
;; Composition:  this module is PURE ORCHESTRATION.  The heavy
;; lifting lives elsewhere — Wylie ingest (`tibetan-wylie-ingest'),
;; OCR wizard (`tibetan-doc-prep-wizard'), post-ingest relocation
;; (`tibetan-doc-prep-move-to-work-in-progress'), genre selectbox
;; (`tibetan-document-genres-read'), async Claude pre-fill
;; (`tibetan-document-prep--ask-claude'), header upserters
;; (`tibetan-document-prep--upsert-single-line-header'), and the
;; analysis pipeline (`tibetan-auto-analyze-document',
;; `tibetan-sentence-create-all').  The wizard just walks the user
;; through and stitches them together.
;;
;; Sanskrit-included documents are deliberately out of scope per the
;; §5.27 plan — the wizard never offers `#+SOURCE_MODE: parallel-
;; sanskrit'.  Users enable that path via the existing toggle.

;;; Code:

(require 'cl-lib)
(require 'tibetan-document-genres)
(require 'tibetan-document-prep-claude)
(require 'tibetan-wylie-ingest)
(require 'tibetan-doc-prep)

;; Forward declarations — guarded at call sites.
(declare-function tibetan-doc-prep-wizard "tibetan-doc-prep" ())
(declare-function tibetan-add-sentence-structure "tibetan-sentence-structure"
                  (&optional include-weak))
(declare-function tibetan-auto-analyze-document
                  "tibetan-auto-analysis" (&optional force))
(declare-function tibetan-sentence-create-all
                  "tibetan-sentence-persist" ())
(declare-function tibetan-analysis--read-source-metadata
                  "tibetan-analysis-claude" (source-file))

;; ============================================================================
;; STATE
;; ============================================================================

(defvar tibetan-document-prep-wizard--state nil
  "Transient plist of the in-flight wizard run.  Cleared on
completion.  Carries `:source-file', `:input-route', whatever
metadata has been gathered so far.  Internal to the wizard
flow.")

;; ============================================================================
;; INPUT ROUTE
;; ============================================================================

(defconst tibetan-document-prep-wizard--routes
  '(("Wylie file (.org with Wylie body) — converts via pyewts" . wylie)
    ("Tibetan-script file (already Unicode) — skip ingest" . unicode)
    ("Existing file — resume / re-run wizard on a prepared source" . existing)
    ("OCR wizard (delegate to `tibetan-doc-prep-wizard')" . ocr))
  "Display-label → route-key alist for the wizard's first step.")

(defun tibetan-document-prep-wizard--read-route ()
  "Prompt the user for an INPUT ROUTE.  Returns the route key symbol."
  (let* ((labels (mapcar #'car tibetan-document-prep-wizard--routes))
         (choice (completing-read "Input route: " labels nil t nil nil
                                  (caar tibetan-document-prep-wizard--routes))))
    (cdr (assoc choice tibetan-document-prep-wizard--routes))))

(defun tibetan-document-prep-wizard--run-wylie-ingest ()
  "Prompt for a Wylie `.org' source, validate + convert + relocate.
Returns the final source-file path (post-relocation into the
configured `work in progress/' folder).

When the source is bare (no `* Tibetan Text' heading) the wizard
OFFERS to auto-wrap it before validation — bare Wylie files
copy-pasted from a transcription don't carry the org-org wrapper
the converter requires, so this catches the common case without
forcing the user to hand-edit."
  (let* ((path (read-file-name "Wylie source (.org): " nil nil t))
         (report (tibetan-wylie-ingest-validate-input path)))
    ;; Step 0:  if the source has no `* Tibetan Text' heading,
    ;; offer to wrap it in the canonical org structure.
    (unless (plist-get report :has-tibetan-text-section)
      (cond
       ((y-or-n-p
         (format "`%s' has no `* Tibetan Text' heading.  \
Auto-wrap with `#+TITLE: %s' + `* Tibetan Text' header? "
                 (file-name-nondirectory path)
                 (file-name-base path)))
        (tibetan-wylie-ingest-wrap-bare-source path)
        (message "Wrapped %s with org header."
                 (file-name-nondirectory path))
        ;; Re-validate after the wrap so paragraph / segment counts
        ;; reflect the now-wrapped body.
        (setq report (tibetan-wylie-ingest-validate-input path)))
       (t
        (user-error
         "Source has no `* Tibetan Text' heading — cannot convert"))))
    ;; Step 0.5:  shad normalisation.  Real-world Wylie sources
    ;; routinely use `|' / `| |' shads where the Python ingest
    ;; script expects `/' / `//'.  Offer to rewrite the body.
    (when (> (plist-get report :pipe-shad-count) 0)
      (let ((n (plist-get report :pipe-shad-count)))
        (when (y-or-n-p
               (format
                "Body has %d pipe-shad char(s) (`|' / `| |').  \
Normalise to `/' / `//' so the converter segments correctly? "
                n))
          (let ((rewritten (tibetan-wylie-ingest-normalize-shads path)))
            (message "Normalised %d pipe-shad char(s)." rewritten)
            (setq report (tibetan-wylie-ingest-validate-input path))))))
    ;; Step 0.6:  folio-marker normalisation.  `[141a.6]' → `[F:D141a6]'
    ;; so the script's regex extracts them as :FOLIO: org properties
    ;; instead of leaving them inline (where pyewts would garble them).
    (when (> (plist-get report :non-standard-folio-count) 0)
      (let ((n (plist-get report :non-standard-folio-count)))
        (when (y-or-n-p
               (format
                "Body has %d bracket-style folio marker(s) (e.g. `[141a.6]').  \
Reshape to `[F:D...]' so the script extracts them as :FOLIO: properties? "
                n))
          (let ((rewritten
                 (tibetan-wylie-ingest-normalize-folio-markers path)))
            (message "Reshaped %d folio marker(s)." rewritten)
            (setq report (tibetan-wylie-ingest-validate-input path))))))
    (when (or (> (plist-get report :tibetan-unicode-count) 0)
              (> (plist-get report :non-ascii-count) 0))
      (let ((tib-count (plist-get report :tibetan-unicode-count))
            (other-count (plist-get report :non-ascii-count)))
        (unless (y-or-n-p
                 (format "Validation flagged %d Tibetan-Unicode + %d non-ASCII char(s).  Proceed anyway? "
                         tib-count other-count))
          (user-error "Wizard aborted at validation step"))))
    (message "Wylie ingest:  validated %d paragraph(s), ~%d segment(s)."
             (plist-get report :paragraph-count)
             (plist-get report :estimated-segment-count))
    ;; Convert in place;  the wrapper relocates the result into
    ;; `work in progress/' and returns the new path.
    (tibetan-wylie-ingest-file path t)))

(defun tibetan-document-prep-wizard--collect-source-file (route)
  "Acquire a source-file path for the given ROUTE.
Dispatches to the appropriate ingest helper;  returns the final
absolute path."
  (pcase route
    ('wylie    (tibetan-document-prep-wizard--run-wylie-ingest))
    ('unicode  (read-file-name
                "Tibetan-script source (.org): " nil nil t))
    ('existing (read-file-name
                "Existing source (.org): " nil nil t))
    ('ocr      (cond
                ((fboundp 'tibetan-doc-prep-wizard)
                 (call-interactively #'tibetan-doc-prep-wizard)
                 (read-file-name
                  "OCR-prepared source (.org): " nil nil t))
                (t
                 (user-error "OCR wizard (`tibetan-doc-prep-wizard') not loaded"))))
    (_ (user-error "Unknown input route:  %S" route))))

;; ============================================================================
;; METADATA STEPS
;; ============================================================================

(defun tibetan-document-prep-wizard--read-target-lang (source-file)
  "Prompt for `#+TIBETAN_TARGET_LANG:'.  Defaults to existing value
or `de'.  Writes the header on the source file via
`tibetan-document-prep--upsert-single-line-header'."
  (let* ((current (and (fboundp 'tibetan-analysis--read-source-metadata)
                       (plist-get
                        (ignore-errors
                          (tibetan-analysis--read-source-metadata source-file))
                        :target-lang)))
         (default (or current "de"))
         (choice (completing-read
                  "Target language: " '("de" "en") nil t nil nil default)))
    (tibetan-document-prep-wizard--write-header
     source-file "TIBETAN_TARGET_LANG" choice)
    choice))

(defun tibetan-document-prep-wizard--fire-async-claude (source-file)
  "Submit the async Claude metadata-suggestion call.

Caches the response in `tibetan-document-prep--claude-suggestions'
on the source's visiting buffer (creating it on the fly when the
source isn't open).  Returns immediately — the wizard continues
without waiting for Claude's reply."
  (let ((buf (or (get-file-buffer source-file)
                 (find-file-noselect source-file))))
    (condition-case err
        (tibetan-document-prep--ask-claude
         source-file
         (lambda (plist)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (setq tibetan-document-prep--claude-suggestions plist)
               (message
                "Claude metadata returned for %s — \
M-x tibetan-document-prep-apply-claude-suggestions to apply"
                (file-name-nondirectory source-file))))))
      (user-error
       (message "Async Claude pre-fill skipped:  %s"
                (error-message-string err)))
      (error
       (message "Async Claude pre-fill error:  %s"
                (error-message-string err))))))

(defun tibetan-document-prep-wizard--read-genre (source-file)
  "Prompt for `#+TIBETAN_TEXT_TYPE:' using the canonical selectbox.

When Claude's async suggestion has already arrived (cached in
the source buffer's local var) its `:genre' is used as the
completing-read default;  otherwise existing-header value or
`classical' is the fallback."
  (let* ((claude-suggestion
          (let ((buf (get-file-buffer source-file)))
            (and buf
                 (buffer-local-value
                  'tibetan-document-prep--claude-suggestions buf))))
         (claude-genre (plist-get claude-suggestion :genre))
         (current (and (fboundp 'tibetan-analysis--read-source-metadata)
                       (plist-get
                        (ignore-errors
                          (tibetan-analysis--read-source-metadata source-file))
                        :text-type)))
         (current-key (and current (intern current)))
         (default (or claude-genre current-key 'classical))
         (chosen (tibetan-document-genres-read default "Genre: ")))
    (tibetan-document-prep-wizard--write-header
     source-file "TIBETAN_TEXT_TYPE" (symbol-name chosen))
    chosen))

(defun tibetan-document-prep-wizard--read-author (source-file)
  "Prompt for `#+TIBETAN_AUTHOR:'.  Default = Claude suggestion if
present, otherwise existing header value, otherwise empty string."
  (let* ((claude-suggestion
          (let ((buf (get-file-buffer source-file)))
            (and buf
                 (buffer-local-value
                  'tibetan-document-prep--claude-suggestions buf))))
         (claude-author (plist-get claude-suggestion :author))
         (current (and (fboundp 'tibetan-analysis--read-source-metadata)
                       (plist-get
                        (ignore-errors
                          (tibetan-analysis--read-source-metadata source-file))
                        :author)))
         (default (or claude-author current ""))
         (input (read-string
                 (if (string-empty-p default)
                     "Author (leave empty if unknown): "
                   (format "Author [%s]: " default))
                 nil nil default))
         (clean (string-trim input)))
    (unless (string-empty-p clean)
      (tibetan-document-prep-wizard--write-header
       source-file "TIBETAN_AUTHOR" clean))
    clean))

(defun tibetan-document-prep-wizard--read-context-lines (source-file)
  "Prompt for `#+TIBETAN_CLAUDE_CONTEXT:' lines (multi-line).

When Claude's async suggestion has arrived its `:context' list is
offered as the default — user accepts with RET, edits inline, or
clears and types fresh lines.  Empty input ends the loop.

Lines are appended via `tibetan-document-prep--append-context-
lines' so existing context lines are preserved."
  (let* ((claude-suggestion
          (let ((buf (get-file-buffer source-file)))
            (and buf
                 (buffer-local-value
                  'tibetan-document-prep--claude-suggestions buf))))
         (claude-context (plist-get claude-suggestion :context))
         (new-lines '()))
    (when claude-context
      (message "Claude suggested %d context line(s):" (length claude-context))
      (dolist (line claude-context)
        (message "  · %s" line))
      (when (y-or-n-p "Use Claude's context lines as starting point? ")
        (setq new-lines (copy-sequence claude-context))))
    (let ((more t))
      (while more
        (let ((line (read-string "Additional context line (RET to finish): ")))
          (cond
           ((string-empty-p (string-trim line))
            (setq more nil))
           (t
            (setq new-lines (append new-lines (list (string-trim line)))))))))
    (when new-lines
      (with-temp-buffer
        (insert-file-contents source-file)
        (tibetan-document-prep--append-context-lines new-lines)
        (write-region (point-min) (point-max) source-file)))
    new-lines))

(defconst tibetan-document-prep-wizard--class-modes
  '(("grammar  — segment-focused (Tibetisch III/IV)" . grammar)
    ("reading  — sentence-focused (reading classes)" . reading))
  "Class mode choices.")

(defun tibetan-document-prep-wizard--read-class-mode (source-file)
  "Prompt for `#+TIBETAN_CLASS_MODE:'.  Default = existing value
or `grammar'.  Returns the chosen symbol (`grammar' | `reading')."
  (let* ((current (and (fboundp 'tibetan-analysis--read-source-metadata)
                       (plist-get
                        (ignore-errors
                          (tibetan-analysis--read-source-metadata source-file))
                        :class-mode)))
         (current-sym (and current (intern current)))
         (default-label
           (or (car (rassq (or current-sym 'grammar)
                           tibetan-document-prep-wizard--class-modes))
               (caar tibetan-document-prep-wizard--class-modes)))
         (labels (mapcar #'car tibetan-document-prep-wizard--class-modes))
         (choice (completing-read "Class mode: " labels nil t nil nil
                                  default-label))
         (key (cdr (assoc choice tibetan-document-prep-wizard--class-modes))))
    (tibetan-document-prep-wizard--write-header
     source-file "TIBETAN_CLASS_MODE" (symbol-name key))
    key))

(defconst tibetan-document-prep-wizard--sentence-details
  '(("compressed — ~2 A4 per sentence (in-class default)" . compressed)
    ("detailed   — full §5.21 segment layout per sentence" . detailed))
  "Sentence-detail choices, only meaningful in reading class-mode.")

(defun tibetan-document-prep-wizard--read-sentence-detail (source-file)
  "Prompt for `#+TIBETAN_SENTENCE_DETAIL:'.  Returns chosen symbol."
  (let* ((current (and (fboundp 'tibetan-analysis--read-source-metadata)
                       (plist-get
                        (ignore-errors
                          (tibetan-analysis--read-source-metadata source-file))
                        :sentence-detail)))
         (current-sym (and current (intern current)))
         (default-label
           (or (car (rassq (or current-sym 'compressed)
                           tibetan-document-prep-wizard--sentence-details))
               (caar tibetan-document-prep-wizard--sentence-details)))
         (labels (mapcar #'car tibetan-document-prep-wizard--sentence-details))
         (choice (completing-read "Sentence detail: " labels nil t nil nil
                                  default-label))
         (key (cdr (assoc choice tibetan-document-prep-wizard--sentence-details))))
    (tibetan-document-prep-wizard--write-header
     source-file "TIBETAN_SENTENCE_DETAIL" (symbol-name key))
    key))

;; ============================================================================
;; HEADER WRITE HELPER  -------------------------------------------------------
;; ============================================================================

(defun tibetan-document-prep-wizard--write-header (source-file key value)
  "Upsert `#+KEY: VALUE' into SOURCE-FILE.  Re-uses the Phase-4
header writer so the wizard and the Claude-apply command share
one implementation."
  (with-temp-buffer
    (insert-file-contents source-file)
    (tibetan-document-prep--upsert-single-line-header key value)
    (write-region (point-min) (point-max) source-file)))

;; ============================================================================
;; RESOURCES SCAFFOLD
;; ============================================================================

(defconst tibetan-document-prep-wizard--vocabulary-template
  "#+TITLE: Per-document vocabulary
#+OPTIONS: toc:nil num:nil

* Vocabulary

| Term | Definition |
|------+------------|
|      |            |
"
  "Starter content for `Resources/vocabulary.org'.  Org-table
format matches the parser in `tibetan-parse-wordlist-org' —
filled-in rows are auto-loaded by `tibetan-load-resources-vocab'.")

(defun tibetan-document-prep-wizard--scaffold-resources (source-file)
  "Create `Resources/vocabulary.org' next to SOURCE-FILE if absent.
Returns the path of the (created or pre-existing) file."
  (let* ((source-dir (file-name-directory (expand-file-name source-file)))
         (res-dir (expand-file-name "Resources" source-dir))
         (vocab-file (expand-file-name "vocabulary.org" res-dir)))
    (unless (file-directory-p res-dir)
      (make-directory res-dir t))
    (unless (file-exists-p vocab-file)
      (with-temp-file vocab-file
        (insert tibetan-document-prep-wizard--vocabulary-template)))
    vocab-file))

;; ============================================================================
;; ANALYSIS KICKOFF
;; ============================================================================

(defun tibetan-document-prep-wizard--run-sentence-structure (source-file)
  "Open SOURCE-FILE and run `tibetan-add-sentence-structure' on it.
Demotes `*** Segment N' headings under `*** Sentence N' wrappers
ready for analysis."
  (when (fboundp 'tibetan-add-sentence-structure)
    (let ((buf (find-file-noselect source-file)))
      (with-current-buffer buf
        (tibetan-add-sentence-structure)
        (save-buffer)))))

(defun tibetan-document-prep-wizard--maybe-run-auto-analyze (source-file
                                                            class-mode)
  "Offer to run `tibetan-auto-analyze-document' on SOURCE-FILE.
When CLASS-MODE is `reading', additionally offer to run
`tibetan-sentence-create-all' afterwards."
  (when (and (fboundp 'tibetan-auto-analyze-document)
             (y-or-n-p "Run full Claude analysis now (C-c u B)?  This may take several minutes. "))
    (let ((buf (find-file-noselect source-file)))
      (with-current-buffer buf
        (tibetan-auto-analyze-document))))
  (when (and (eq class-mode 'reading)
             (fboundp 'tibetan-sentence-create-all)
             (y-or-n-p "Create per-sentence analysis files (sent-NNN.org) now? "))
    (let ((buf (find-file-noselect source-file)))
      (with-current-buffer buf
        (tibetan-sentence-create-all)))))

;; ============================================================================
;; SUMMARY
;; ============================================================================

(defun tibetan-document-prep-wizard--format-summary (state)
  "Render a human-readable summary of the wizard's STATE."
  (mapconcat
   #'identity
   (list
    "Document Preparation Wizard — Summary"
    (make-string 60 ?─)
    (format "  Source file:       %s"
            (abbreviate-file-name (or (plist-get state :source-file) "?")))
    (format "  Input route:       %s"
            (or (plist-get state :input-route) "?"))
    (format "  Target language:   %s" (or (plist-get state :target-lang) "?"))
    (format "  Genre:             %s"
            (or (and (plist-get state :genre)
                     (symbol-name (plist-get state :genre)))
                "?"))
    (format "  Author:            %s"
            (if (and (plist-get state :author)
                     (not (string-empty-p (plist-get state :author))))
                (plist-get state :author)
              "(none)"))
    (format "  Context lines:     %d"
            (length (plist-get state :context)))
    (format "  Class mode:        %s"
            (or (and (plist-get state :class-mode)
                     (symbol-name (plist-get state :class-mode)))
                "?"))
    (when (eq (plist-get state :class-mode) 'reading)
      (format "  Sentence detail:   %s"
              (or (and (plist-get state :sentence-detail)
                       (symbol-name (plist-get state :sentence-detail)))
                  "?")))
    (format "  Resources/vocab:   %s"
            (or (plist-get state :vocabulary-file) "(skipped)"))
    ""
    "Async Claude metadata pre-fill:"
    (format "  %s"
            (cond
             ((plist-get state :claude-applied-eagerly)
              "applied via wizard defaults")
             ((plist-get state :claude-fired)
              "fired in background — \
M-x tibetan-document-prep-apply-claude-suggestions when ready")
             (t "not fired")))
    ""
    "Next-step commands:"
    "  C-c u B   — re-run full Claude analysis"
    "  M-x tibetan-sentence-create-all"
    "  M-x tibetan-document-prep-apply-claude-suggestions")
   "\n"))

;; ============================================================================
;; TOP-LEVEL
;; ============================================================================

;;;###autoload
(defun tibetan-document-prep-wizard ()
  "Unified document-preparation wizard (§5.27).

Walks through:
  1. Input route (Wylie / Tibetan-script / existing / OCR).
  2. (Wylie route) validate + convert via pyewts, relocate to
     `work in progress/'.
  3. Target language → `#+TIBETAN_TARGET_LANG:'.
  4. Fire async Claude metadata suggestion (does NOT block).
  5. Genre selectbox → `#+TIBETAN_TEXT_TYPE:'.
  6. Author + context lines → `#+TIBETAN_AUTHOR:' + N x
     `#+TIBETAN_CLAUDE_CONTEXT:'.
  7. Class mode → `#+TIBETAN_CLASS_MODE:'.
  8. (Reading class-mode) sentence detail → `#+TIBETAN_SENTENCE_DETAIL:'.
  9. Resources/vocabulary.org scaffold.
  10. Sentence-structure demotion (`*** Segment N' →
      `*** Sentence N' wrappers).
  11. Offer to run `tibetan-auto-analyze-document' +
      (reading mode) `tibetan-sentence-create-all'.
  12. Final summary buffer.

When Claude's async suggestion arrives mid-wizard it's cached on
the source's visiting buffer;  later wizard steps (genre, author,
context) consult it as a default.  Post-wizard the user can run
`M-x tibetan-document-prep-apply-claude-suggestions' to apply any
suggestions not yet incorporated."
  (interactive)
  (setq tibetan-document-prep-wizard--state nil)
  (let* ((route (tibetan-document-prep-wizard--read-route))
         (source-file
          (tibetan-document-prep-wizard--collect-source-file route))
         (state (list :input-route route
                      :source-file source-file)))
    (unless (and source-file (file-exists-p source-file))
      (user-error "Wizard:  no source file acquired — aborting"))
    ;; Step 3 — target language.
    (setq state (plist-put state :target-lang
                           (tibetan-document-prep-wizard--read-target-lang
                            source-file)))
    ;; Step 4 — fire async Claude (best-effort).
    (tibetan-document-prep-wizard--fire-async-claude source-file)
    (setq state (plist-put state :claude-fired t))
    ;; Step 5 — genre.
    (setq state (plist-put state :genre
                           (tibetan-document-prep-wizard--read-genre
                            source-file)))
    ;; Step 6 — author + context.
    (setq state (plist-put state :author
                           (tibetan-document-prep-wizard--read-author
                            source-file)))
    (setq state (plist-put state :context
                           (tibetan-document-prep-wizard--read-context-lines
                            source-file)))
    ;; Step 7 — class mode.
    (let ((mode (tibetan-document-prep-wizard--read-class-mode
                 source-file)))
      (setq state (plist-put state :class-mode mode))
      ;; Step 8 — sentence detail (reading only).
      (when (eq mode 'reading)
        (setq state (plist-put state :sentence-detail
                               (tibetan-document-prep-wizard--read-sentence-detail
                                source-file)))))
    ;; Step 9 — Resources/vocabulary.org scaffold.
    (when (y-or-n-p "Create `Resources/vocabulary.org' starter? ")
      (setq state (plist-put state :vocabulary-file
                             (tibetan-document-prep-wizard--scaffold-resources
                              source-file))))
    ;; Step 10 — sentence-structure demotion.
    (when (y-or-n-p "Run `tibetan-add-sentence-structure' to wrap segments? ")
      (tibetan-document-prep-wizard--run-sentence-structure source-file))
    ;; Step 11 — analysis kickoff (optional).
    (tibetan-document-prep-wizard--maybe-run-auto-analyze
     source-file (plist-get state :class-mode))
    ;; Step 12 — summary.
    (setq tibetan-document-prep-wizard--state state)
    (with-output-to-temp-buffer "*Tibetan Doc Prep Summary*"
      (princ (tibetan-document-prep-wizard--format-summary state)))
    state))

(provide 'tibetan-document-prep-wizard)
;;; tibetan-document-prep-wizard.el ends here
