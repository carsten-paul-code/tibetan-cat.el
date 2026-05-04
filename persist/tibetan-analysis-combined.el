;;; tibetan-analysis-combined.el --- Combined-synthesis Claude pipeline -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase 4 of two-language-parallel-analysis (2026-04-30).
;;
;; The Combined-synthesis Claude call sits ABOVE the two
;; independent translations (Tibetan from
;; `persist/tibetan-analysis-claude.el', Sanskrit from
;; `persist/tibetan-analysis-sanskrit.el') and produces a single
;; justified translation drawing on BOTH sources, plus an
;; optional `## Divergence' note when there is a serious
;; Sanskrit-Tibetan difference.
;;
;; Smaller surface than the two raw-side modules:
;;
;;   tibetan-analysis-combined--build-prompts
;;       (SYSTEM . USER) for the combined call.  System block
;;       defines the comparative-reader role + target-lang;
;;       constant per document → caches.  User block carries
;;       both raw sources (Tib + Skt) AND both translations
;;       produced upstream by the two raw-side calls.
;;
;;   tibetan-analysis-combined--parse-claude-sections
;;       Splits a combined response on `## Translation' /
;;       `## Divergence'.  Both keys nullable; Divergence is
;;       opt-in (Claude emits it only when there is a serious
;;       difference).
;;
;;   tibetan-analysis-combined--insert-sections
;;       Writes parsed sections under `* Combined Analysis'
;;       (top-level).  Idempotent.
;;
;;   tibetan-analysis-combined--read-sections
;;   tibetan-analysis-combined--restore-sections
;;       Round-trip helpers for the reanalyse path.
;;
;;   tibetan-analysis-combined--needs-fire-p
;;       Predicate: both Tibetan and Sanskrit translations are
;;       present and non-empty.  Phase 5 dispatcher checks this
;;       before firing the Combined call.
;;
;;   tibetan-analysis-combined--request-synthesis
;;       Async fire.  Wired by Phase 5.
;;
;; Output goes under a TOP-LEVEL `* Combined Analysis' section
;; (peer of `* Auto-Analysis' / `* Sanskrit Analysis').  Same
;; independence pattern as the other two analyses.

;;; Code:

(require 'cl-lib)
(require 'tibetan-claude-queue nil t)
(require 'gptel nil t)

(defvar gptel-cache)
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(declare-function tibetan-analysis--ensure-gptel-ready
                  "tibetan-analysis-claude" ())
(declare-function tibetan-analysis--read-source-metadata
                  "tibetan-analysis-claude" (source-file))
(declare-function tibetan-analysis--claude-status-rate-limited-p
                  "tibetan-analysis-claude" (info))
(declare-function tibetan-claude-queue-submit
                  "tibetan-claude-queue" (&rest args))

;; ============================================================================
;; PROMPT
;; ============================================================================

(defconst tibetan-analysis-combined--system-prompt-base
  "You are a comparative reader of parallel Sanskrit-Tibetan \
philological corpora, working with a graduate Yogācārabhūmi \
reading class.  You will receive both the Sanskrit (the canonical \
primary) and the Tibetan (the canonical translation) for one \
segment, plus the independent translations of each that another \
model produced.  Your job is to synthesise — produce a single \
best translation that honours both sources, and flag serious \
divergences.

Produce TWO sections (the second is conditional):

`## Translation'
  Your synthetic best reading.  When the two sources agree, \
  follow the agreed reading.  When they diverge, pick whichever \
  reading is better supported by the philological evidence and \
  the doctrinal context;  default to the Sanskrit when there is \
  no compelling reason otherwise.  This is the translation a \
  careful classroom reader would settle on after weighing both \
  sources — not a paraphrase, not a fusion, but a justified \
  single rendering.

`## Divergence'
  Emit ONLY when there is a SERIOUS Sanskrit-Tibetan difference \
  (the Tibetan translators glossed, collapsed, expanded, \
  reordered, or substituted in a way that matters for the \
  philosophical reading).  1–3 short bullets naming the \
  specific divergence(s); each names the Sanskrit term / \
  phrase, the Tibetan rendering, and the philological or \
  doctrinal consequence.  Omit the section entirely for \
  faithful renderings.  Do not invent divergences for trivial \
  word-order or particle-level differences.

Style notes:
  - Keep both sections terse;  this is a reference for a reader \
    who has the two raw translations already in front of them.
  - The user prompt below carries the two raw sources + the two \
    upstream translations.  Use them as the authoritative inputs.
"
  "Constant base for the Combined Claude system prompt.  Per-
document additions (target-lang directive, source genre) appended
at build time.  Constant per document → Anthropic-cache friendly.")

(defun tibetan-analysis-combined--build-prompts
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation
                  source-file &optional _analysis-file)
  "Build (SYSTEM . USER) Claude prompts for the Combined call.

TIBETAN-TEXT, SANSKRIT-PLIST: the two raw sources for the segment.
TIBETAN-TRANSLATION, SANSKRIT-TRANSLATION: the bodies of the two
upstream Claude translations (strings).
SOURCE-FILE: source document (for metadata lookups).
ANALYSIS-FILE: reserved for future ±2 neighbour context.

Returns nil when any of:  tibetan-text empty, sanskrit-plist
nil / lacks IAST, either translation empty.  The Combined call
is meaningful only when all four inputs are present."
  (let* ((iast (and sanskrit-plist (plist-get sanskrit-plist :iast)))
         (devanagari (and sanskrit-plist
                          (plist-get sanskrit-plist :devanagari))))
    (when (and tibetan-text
               (stringp tibetan-text)
               (not (string-empty-p (string-trim tibetan-text)))
               iast (stringp iast) (not (string-empty-p (string-trim iast)))
               tibetan-translation
               (stringp tibetan-translation)
               (not (string-empty-p (string-trim tibetan-translation)))
               sanskrit-translation
               (stringp sanskrit-translation)
               (not (string-empty-p (string-trim sanskrit-translation))))
      (let* ((meta (and source-file
                        (fboundp 'tibetan-analysis--read-source-metadata)
                        (condition-case nil
                            (tibetan-analysis--read-source-metadata
                             source-file)
                          (error nil))))
             (target-lang-val (plist-get meta :target-lang))
             (target-lang-block
              (cond
               ((and target-lang-val (stringp target-lang-val)
                     (equal (downcase target-lang-val) "de"))
                (concat "\nTarget language for `## Translation': "
                        "GERMAN.  Divergence-note metalanguage stays "
                        "in English.\n"))
               (t "\nTarget language for `## Translation': English.\n")))
             (genre-blocks
              (and meta
                   (let ((claude-context
                          (plist-get meta :claude-context)))
                     ;; `:claude-context' is a LIST of strings (one
                     ;; per `#+TIBETAN_CLAUDE_CONTEXT:' header).
                     ;; Bug fix 2026-05-03:  the previous `concat'
                     ;; treated list elements as characters and
                     ;; crashed with `(wrong-type-argument characterp
                     ;; <STRING>)' on any source with at least one
                     ;; context header.  Mirror the Tibetan-side
                     ;; per-line iteration.
                     (when (and claude-context (listp claude-context))
                       (concat
                        "\nDocument context (genre / register / "
                        "vocabulary):\n"
                        (mapconcat (lambda (line) (format "  - %s" line))
                                   claude-context "\n")
                        "\n")))))
             (system (concat tibetan-analysis-combined--system-prompt-base
                             (or target-lang-block "")
                             (or genre-blocks "")))
             (user (concat
                    "Sanskrit (primary) — IAST:\n"
                    iast
                    "\n"
                    (when (and devanagari
                               (stringp devanagari)
                               (not (string-empty-p
                                     (string-trim devanagari))))
                      (format "Sanskrit (primary) — Devanagari:\n%s\n\n"
                              devanagari))
                    "\nTibetan (canonical translation):\n"
                    tibetan-text
                    "\n\n--- Upstream Sanskrit translation:\n"
                    sanskrit-translation
                    "\n\n--- Upstream Tibetan translation:\n"
                    tibetan-translation
                    "\n\nProduce the Combined-Analysis sections now.  "
                    "Skip `## Divergence' for faithful renderings.")))
        (cons system user)))))

;; ============================================================================
;; PARSER
;; ============================================================================

(defun tibetan-analysis-combined--parse-claude-sections (response)
  "Split a Combined Claude RESPONSE on `## Translation' /
`## Sanskrit-Tibetan Comparison' headings.

Returns a plist with `:translation' and `:comparison' keys.
Missing sections are nil.

Phase 3.1 of layout-revision §5.18 (2026-05-04):  the second
section is now always emitted (with `[Faithful — …]' for faithful
renderings).  Renamed from `:divergence' to `:comparison'.  The
parser accepts THREE heading aliases for the comparison body —
the new `## Sanskrit-Tibetan Comparison', the bare `## Comparison',
and the legacy `## Divergence' (so archived Claude responses still
round-trip)."
  (let ((result (list :translation nil :comparison nil))
        (re (concat "^## "
                    "\\(Translation"
                    "\\|Sanskrit-Tibetan Comparison"
                    "\\|Comparison"
                    "\\|Divergence"
                    "\\)[ \t]*$")))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              (let* ((token (match-string 1))
                     (key (cond
                           ((string= token "Translation") :translation)
                           ;; Sanskrit-Tibetan Comparison / Comparison /
                           ;; Divergence all route to :comparison.
                           (t :comparison))))
                (push (list key (match-end 0)) matches)))
            (setq matches (nreverse matches))
            (cl-loop for (cell . rest) on matches
                     for key = (car cell)
                     for start = (cadr cell)
                     for end = (if rest
                                   (save-excursion
                                     (goto-char (cadr (car rest)))
                                     (beginning-of-line)
                                     (point))
                                 (point-max))
                     for body = (string-trim
                                 (buffer-substring-no-properties
                                  start end))
                     do (setq result
                              (plist-put result
                                         key
                                         (and (not (string-empty-p body))
                                              body))))))))
    result))

;; ============================================================================
;; SECTION ORDER + WRITER
;; ============================================================================

(defconst tibetan-analysis-combined--section-order
  '((:translation "Combined Translation"          2)
    (:comparison  "Sanskrit-Tibetan Comparison"   2))
  "Canonical order, heading names, levels for Combined sections
inside `* Combined Analysis'.  Both at level 2.

Phase 3.2 of layout-revision §5.18 (2026-05-04):  `:divergence' →
`:comparison' and heading rename `Divergence' → `Sanskrit-Tibetan
Comparison'.  The Combined Claude prompt now ALWAYS emits the
comparison section (with `[Faithful — …]' for faithful
renderings — see Phase 3.3).")

(defun tibetan-analysis-combined--ensure-parent (buffer)
  "Ensure `* Combined Analysis' top-level heading exists in BUFFER.
Inserts at end of buffer when absent.  Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Combined Analysis$" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (unless (looking-back "\n\n" 2) (insert "\n"))
        (insert "* Combined Analysis\n"
                ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")))))

(defun tibetan-analysis-combined--ensure-section (buffer heading)
  "Ensure HEADING (a level-2 string) exists inside `* Combined Analysis'
in BUFFER.  Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\*\\* %s$" (regexp-quote heading))))
        (unless (re-search-forward heading-re nil t)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Combined Analysis$" nil t)
            (forward-line 1)
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)))
            (if (re-search-forward "^\\* " nil t)
                (beginning-of-line)
              (goto-char (point-max)))
            (unless (looking-back "\n\n" 2) (insert "\n"))
            (insert "** " heading "\n\n\n")))))))

(defun tibetan-analysis-combined--replace-section-body (buffer heading body)
  "Replace the body under HEADING (a level-2 string) inside
`* Combined Analysis' in BUFFER with BODY."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\*\\* %s$" (regexp-quote heading))))
        (when (re-search-forward heading-re nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward "^\\*\\{1,2\\}[^*\n]" nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            (insert (format "%s\n\n" (string-trim body)))))))))

(defun tibetan-analysis-combined--migrate-legacy-divergence-heading (buffer)
  "Rename any legacy `** Divergence' inside `* Combined Analysis' →
`** Sanskrit-Tibetan Comparison' (Phase 3.2 of layout-revision
§5.18, 2026-05-04).  Idempotent — no-op when the file already uses
the new heading name.

Called at the start of `--insert-sections' / `--restore-sections'
so subsequent existence checks find the new name on legacy files."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Combined Analysis$" nil t)
        (let ((bound (save-excursion
                       (if (re-search-forward "^\\* " nil t)
                           (line-beginning-position)
                         (point-max)))))
          (while (re-search-forward "^\\*\\* Divergence$" bound t)
            (replace-match "** Sanskrit-Tibetan Comparison" t t)))))))

(defun tibetan-analysis-combined--insert-sections (response analysis-file)
  "Parse a Combined Claude RESPONSE and write its sections into
ANALYSIS-FILE under `* Combined Analysis' (top-level).

Returns t on successful write, nil when no sections were
parsed or ANALYSIS-FILE is missing."
  (when (and response analysis-file (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis-combined--parse-claude-sections
                      response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-combined--section-order)
          (tibetan-analysis-combined--ensure-parent buf)
          ;; Phase 3.2 of layout-revision §5.18 (2026-05-04): rename
          ;; any legacy `** Divergence' before existence checks run.
          (tibetan-analysis-combined--migrate-legacy-divergence-heading buf)
          (dolist (entry tibetan-analysis-combined--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-combined--ensure-section buf heading)
                (tibetan-analysis-combined--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; READ + RESTORE
;; ============================================================================

(defun tibetan-analysis-combined--read-section-body (filepath heading)
  "Return the body under `** HEADING' inside `* Combined Analysis'
in FILEPATH."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Combined Analysis$" nil t)
        (let ((parent-end (save-excursion
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max)))))
          (when (re-search-forward
                 (format "^\\*\\* %s$" (regexp-quote heading))
                 parent-end t)
            (forward-line 1)
            (let* ((body-start (point))
                   (body-end
                    (or (save-excursion
                          (when (re-search-forward
                                 "^\\*\\{1,2\\}[^*\n]" parent-end t)
                            (line-beginning-position)))
                        parent-end))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (and (not (string-empty-p body)) body))))))))

(defun tibetan-analysis-combined--read-sections (filepath)
  "Return preserved Combined-Claude content as a plist with
`:translation' / `:comparison' keys.

Phase 3.2 of layout-revision §5.18 (2026-05-04):  the `:comparison'
slot's body lookup tries the new heading `Sanskrit-Tibetan
Comparison' first and falls back to the legacy `Divergence' name
so files written before this commit still resolve cleanly."
  (list :translation
        (tibetan-analysis-combined--read-section-body
         filepath "Combined Translation")
        :comparison
        (or (tibetan-analysis-combined--read-section-body
             filepath "Sanskrit-Tibetan Comparison")
            (tibetan-analysis-combined--read-section-body
             filepath "Divergence"))))

(defun tibetan-analysis-combined--restore-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's `* Combined
Analysis' section."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-combined--section-order)
          (tibetan-analysis-combined--ensure-parent buf)
          ;; Phase 3.2 of layout-revision §5.18 (2026-05-04): same
          ;; legacy-heading migration as `--insert-sections'.
          (tibetan-analysis-combined--migrate-legacy-divergence-heading buf)
          (dolist (entry tibetan-analysis-combined--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-combined--ensure-section buf heading)
                (tibetan-analysis-combined--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; PREDICATES + ASYNC FIRE
;; ============================================================================

(defun tibetan-analysis-combined--needs-fire-p
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation)
  "Return non-nil when the Combined call has all four inputs and
should be fired.  All four must be non-empty strings (with
SANSKRIT-PLIST carrying a non-empty `:iast')."
  (and tibetan-text
       (stringp tibetan-text)
       (not (string-empty-p (string-trim tibetan-text)))
       sanskrit-plist
       (let ((iast (plist-get sanskrit-plist :iast)))
         (and iast (stringp iast)
              (not (string-empty-p (string-trim iast)))))
       tibetan-translation
       (stringp tibetan-translation)
       (not (string-empty-p (string-trim tibetan-translation)))
       sanskrit-translation
       (stringp sanskrit-translation)
       (not (string-empty-p (string-trim sanskrit-translation)))
       t))

;;;###autoload
(defun tibetan-analysis-combined--request-synthesis
    (tibetan-text sanskrit-plist tibetan-translation sanskrit-translation
                  source-file analysis-file &optional callback)
  "Fire an async Combined Claude call.

On response, parses sections + writes them under `* Combined
Analysis' in ANALYSIS-FILE.  CALLBACK (if non-nil) is called
with one arg — the parsed plist — after the write.

Goes through `tibetan-claude-queue' so the request shares the
rate-limit budget + retry-on-429 logic with the Tibetan and
Sanskrit calls (concurrency optimization, 2026-04-30:  before
this commit the Combined call bypassed the queue entirely).
The Combined call is naturally serial relative to Tibetan +
Sanskrit (it chains off the Sanskrit callback, runs only when
both translations are present), so queueing it adds rate-limit
safety without changing the per-segment latency profile.

No-op when `--needs-fire-p' returns nil or gptel /
tibetan-claude-queue are missing."
  (when (and (tibetan-analysis-combined--needs-fire-p
              tibetan-text sanskrit-plist
              tibetan-translation sanskrit-translation)
             (fboundp 'gptel-request)
             (fboundp 'tibetan-analysis--ensure-gptel-ready)
             (fboundp 'tibetan-claude-queue-submit))
    (require 'tibetan-claude-queue)
    (let* ((label (and analysis-file
                       (concat "com:"
                               (file-name-nondirectory analysis-file))))
           (prompts (tibetan-analysis-combined--build-prompts
                     tibetan-text sanskrit-plist
                     tibetan-translation sanskrit-translation
                     source-file analysis-file)))
      (when prompts
        (tibetan-claude-queue-submit
         (lambda (done)
           (condition-case err
               (progn
                 (tibetan-analysis--ensure-gptel-ready)
                 (let ((gptel-cache '(system)))
                   (gptel-request
                    (cdr prompts)
                    :system (car prompts)
                    :callback
                    (lambda (response info)
                      (cond
                       ((and response (stringp response)
                             (not (string-empty-p response)))
                        (condition-case e
                            (let ((parsed
                                   (tibetan-analysis-combined--parse-claude-sections
                                    response)))
                              (tibetan-analysis-combined--insert-sections
                               response analysis-file)
                              (when callback (funcall callback parsed)))
                          (error
                           (message "Combined insert failed for %s: %s"
                                    (or label "<file>")
                                    (error-message-string e))))
                        (funcall done '(:status ok)))
                       ((and (fboundp 'tibetan-analysis--claude-status-rate-limited-p)
                             (tibetan-analysis--claude-status-rate-limited-p info))
                        (funcall done '(:status rate-limited)))
                       (t
                        (funcall done
                                 (list :status 'error
                                       :error (format "%s"
                                                      (or (and (listp info)
                                                               (plist-get info :status))
                                                          "no response"))))))))))
             (error
              (funcall done (list :status 'error
                                  :error (error-message-string err))))))
         :label label
         :on-fail
         (lambda (status)
           (let ((kind (plist-get status :status)))
             (message "Combined Claude request failed for %s: %s"
                      (or label "<file>")
                      (cond
                       ((eq kind 'rate-limited)
                        "rate-limited (HTTP 429) after retries")
                       (t (or (plist-get status :error) "unknown")))))))))))

(provide 'tibetan-analysis-combined)
;;; tibetan-analysis-combined.el ends here
