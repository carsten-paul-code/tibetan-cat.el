;;; tibetan-analysis-sanskrit.el --- Sanskrit-side Claude pipeline -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase 2 of two-language-parallel-analysis (2026-04-30).
;;
;; Sanskrit-side Claude analysis for parallel-mode documents.
;; Mirrors the structure of `persist/tibetan-analysis-claude.el'
;; but for Sanskrit input + Sanskrit-philological output:
;;
;;   tibetan-analysis-sanskrit--build-prompts
;;       Builds (SYSTEM . USER) Claude prompts for one segment's
;;       Sanskrit text + neighbour-Sanskrit context.  System block
;;       defines the Sanskrit-philologist role + target-lang;
;;       constant per document → Anthropic-cache friendly.
;;
;;   tibetan-analysis-sanskrit--parse-claude-sections
;;       Splits a Sanskrit response on `## Translation' /
;;       `## Devanagari' / `## Sandhi' / `## Word List' /
;;       `## Grammar' headings.  Returns plist with those keys.
;;
;;   tibetan-analysis-sanskrit--insert-sections
;;       Writes parsed sections under `* Sanskrit Analysis'
;;       (top-level).  Idempotent — replaces existing sections,
;;       creates the parent on first call.
;;
;;   tibetan-analysis-sanskrit--read-sections
;;   tibetan-analysis-sanskrit--restore-sections
;;       Round-trip helpers used by the reanalyse path to
;;       preserve existing Sanskrit Claude content across a
;;       regen.
;;
;;   tibetan-analysis-sanskrit--request-translation
;;       Async fire via `tibetan-claude-queue' (when available;
;;       else direct gptel-request).  Wired by Phase 5 dispatcher.
;;
;; All output goes under a TOP-LEVEL `* Sanskrit Analysis'
;; section (NOT under `* Auto-Analysis').  That placement means
;; the Tibetan reanalyse path doesn't touch the Sanskrit
;; analysis, and vice versa — same independence pattern as
;; today's `* DharmaMitra Translation (Tibetan)' / `(Sanskrit)'
;; top-level sections.
;;
;; Module is soft-required from `tibetan-cat.el'; without it the
;; Sanskrit pipeline simply doesn't exist (Tibetan side keeps
;; working).  Wiring lives in Phase 5 (`tibetan-analysis-
;; reanalyze-file' + `tibetan-auto-analyze-document').

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
;; PROMPT (system block — constant per document; user block — per segment)
;; ============================================================================

(defconst tibetan-analysis-sanskrit--system-prompt-base
  "You are a specialist in Classical Sanskrit philology, acting \
as a teaching assistant for a graduate Yogācārabhūmi reading \
class.  You will receive a single Sanskrit segment in IAST \
(with optional Devanagari) and must produce four to five \
sections, each headed by a single `## ' Markdown heading.

`## Translation'
  Your translation of the Sanskrit into the target language. \
  Render the Sanskrit on its own terms — do not paraphrase the \
  Tibetan canon's reading; this analysis runs alongside an \
  independent Tibetan analysis and the reader compares them.

`## Devanagari'
  Emit ONLY when the user prompt provides IAST without \
  Devanagari.  Provide the Devanagari rendering of the exact \
  IAST passage — no commentary, no extra punctuation.  Skip \
  the section entirely when the user prompt already includes \
  a Devanagari line.

`## Sandhi'
  Decompose every sandhi-joined compound in the passage.  One \
  bullet per joint:  surface form → component stems + sandhi \
  rule (e.g. `svānyāyena → sva + ānyāyena [savarṇa-dīrgha]'). \
  Skip the section entirely when no sandhi joints are present.

`## Word List'
  One bullet per content word.  Each line:  IAST word — lemma \
  (case + number + gender for nouns / pronouns; root + tense \
  + person + number for verbs) — short English gloss.  \
  Particles get compact entries (just the gloss).

`## Grammar'
  Prose reading: case-frame analysis, verb conjugation, \
  structural notes, clause-level dependencies.  Mention any \
  features that look unusual against typical Yogācāra prose.

Style notes:
  - Keep entries terse;  this is a reference for a reader
    who already knows Sanskrit basics, not a textbook.
  - The user prompt below may carry ±2 neighbour Sanskrit
    segments for context.  Do not translate them; they are
    reference for ambiguous cases only.
"
  "Constant base for the Sanskrit Claude system prompt.  Per-
document additions (target-lang directive, source genre context)
are appended at build time; the resulting full system prompt is
constant per document and so participates in Anthropic prompt
caching.")

(defun tibetan-analysis-sanskrit--build-prompts
    (sanskrit-plist source-file &optional _analysis-file)
  "Build (SYSTEM . USER) Claude prompts for SANSKRIT-PLIST.

SANSKRIT-PLIST is the walker plist
`(:iast STR :devanagari STR-or-nil :script-source SYM)' returned
by `tibetan-sanskrit-parallel-text-for-segment-id'.

SOURCE-FILE supplies metadata (target-lang, genre-context
headers) — read via
`tibetan-analysis--read-source-metadata' when available.

ANALYSIS-FILE (currently unused; reserved for future ±2
neighbour-Sanskrit context).

Returns nil when SANSKRIT-PLIST is nil / lacks `:iast'.  System
block is constant per document; user block carries IAST +
optional Devanagari.

Pure function — no buffer / network I/O."
  (when (and sanskrit-plist
             (plist-get sanskrit-plist :iast)
             (stringp (plist-get sanskrit-plist :iast))
             (not (string-empty-p
                   (string-trim (plist-get sanskrit-plist :iast)))))
    (let* ((iast (plist-get sanskrit-plist :iast))
           (devanagari (plist-get sanskrit-plist :devanagari))
           (meta (and source-file
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
              (concat "\nTarget language for `## Translation': GERMAN.\n"
                      "Word List + Grammar + Sandhi stay in English "
                      "(metalanguage).\n"))
             (t "\nTarget language for `## Translation': English.\n")))
           (genre-blocks
            (and meta
                 (let ((claude-context
                        (plist-get meta :claude-context)))
                   (and claude-context
                        (concat
                         "\nDocument context (genre / register / "
                         "vocabulary):\n"
                         claude-context)))))
           (system (concat tibetan-analysis-sanskrit--system-prompt-base
                           (or target-lang-block "")
                           (or genre-blocks "")))
           (user (concat "Sanskrit passage (IAST):\n\n"
                         iast
                         (when (and devanagari
                                    (stringp devanagari)
                                    (not (string-empty-p
                                          (string-trim devanagari))))
                           (format "\n\nSanskrit passage (Devanagari):\n\n%s"
                                   devanagari))
                         "\n\nProduce the Sanskrit-side analysis sections "
                         "now.  Skip `## Devanagari' if the user prompt "
                         "already provides it; skip `## Sandhi' if there "
                         "are no sandhi joints in this segment.")))
      (cons system user))))

;; ============================================================================
;; PARSER (response → plist)
;; ============================================================================

(defun tibetan-analysis-sanskrit--parse-claude-sections (response)
  "Split a Sanskrit Claude RESPONSE on `## …' markdown headings.

Returns a plist with keys `:translation' / `:devanagari' /
`:sandhi' / `:word-list' / `:grammar'.  Missing sections are
nil so the writer can leave the old org body in place when
Claude omitted a section (e.g. `## Devanagari' is conditional).

When RESPONSE is nil / empty / has no `## ' headings, returns
the all-nil plist."
  (let ((result (list :translation nil :devanagari nil
                      :sandhi nil :word-list nil :grammar nil))
        (re "^## \\(Translation\\|Devanagari\\|Sandhi\\|Word List\\|Grammar\\)[ \t]*$"))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              (push (list (tibetan-analysis-sanskrit--heading-key
                           (match-string 1))
                          (match-end 0))
                    matches))
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

(defun tibetan-analysis-sanskrit--heading-key (heading-token)
  "Map a parsed Sanskrit `## …' HEADING-TOKEN to its plist key.
Special-cases `Word List' → `:word-list' (downcased name has a
space, which can't be a symbol); other tokens go through
naive downcase + intern."
  (cond
   ((string= heading-token "Word List") :word-list)
   (t (intern (format ":%s" (downcase heading-token))))))

;; ============================================================================
;; SECTION ORDER + WRITER (response → analysis file)
;; ============================================================================

(defconst tibetan-analysis-sanskrit--section-order
  '((:devanagari "Devanagari"            2)
    (:sandhi     "Sandhi Decomposition"  2)
    (:word-list  "Word List"             2)
    (:translation "Claude Translation"   2)
    (:grammar    "Grammar"               2))
  "Canonical order, heading names, and org levels for Sanskrit
Claude sections inside `* Sanskrit Analysis'.  Every entry is
\(KEY HEADING LEVEL).  Devanagari is conditional (only when
source lacks it); the others are always present when the
Sanskrit pipeline fires.")

(defun tibetan-analysis-sanskrit--ensure-parent (buffer)
  "Ensure `* Sanskrit Analysis' top-level heading exists in BUFFER.
Inserts at end of buffer when absent.  Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (unless (re-search-forward "^\\* Sanskrit Analysis$" nil t)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (unless (looking-back "\n\n" 2) (insert "\n"))
        (insert "* Sanskrit Analysis\n"
                ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")))))

(defun tibetan-analysis-sanskrit--ensure-section (buffer heading)
  "Ensure HEADING (a level-2 string) exists inside `* Sanskrit Analysis'
in BUFFER.  Appends at the end of the parent section if absent.
Idempotent."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\*\\* %s$" (regexp-quote heading))))
        (unless (re-search-forward heading-re nil t)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Sanskrit Analysis$" nil t)
            (forward-line 1)
            ;; Skip property drawer.
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)))
            ;; Walk to end of `* Sanskrit Analysis' subtree.
            (if (re-search-forward "^\\* " nil t)
                (beginning-of-line)
              (goto-char (point-max)))
            (unless (looking-back "\n\n" 2) (insert "\n"))
            (insert "** " heading "\n\n\n")))))))

(defun tibetan-analysis-sanskrit--replace-section-body (buffer heading body)
  "Replace the body under HEADING (a level-2 string) inside `* Sanskrit
Analysis' in BUFFER with BODY.  Leaves the heading in place;
trims body + adds one trailing blank line."
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

(defun tibetan-analysis-sanskrit--insert-sections (response analysis-file)
  "Parse a Sanskrit Claude RESPONSE and write its sections into
ANALYSIS-FILE under `* Sanskrit Analysis' (top-level).  Each
section named in `tibetan-analysis-sanskrit--section-order'
that the parser populated is written under its heading;
missing sections are skipped (their existing body stays).

Returns t on successful write, nil when ANALYSIS-FILE is
missing or RESPONSE is empty."
  (when (and response analysis-file (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis-sanskrit--parse-claude-sections
                      response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        ;; Only proceed when at least one section was parsed.
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-sanskrit--section-order)
          (tibetan-analysis-sanskrit--ensure-parent buf)
          (dolist (entry tibetan-analysis-sanskrit--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-sanskrit--ensure-section buf heading)
                (tibetan-analysis-sanskrit--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; READ + RESTORE (preserve across reanalyse)
;; ============================================================================

(defun tibetan-analysis-sanskrit--read-section-body (filepath heading)
  "Return the body under `** HEADING' inside `* Sanskrit Analysis'
in FILEPATH, trimmed.  Nil when the heading is absent or body
is empty."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Sanskrit Analysis$" nil t)
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

(defun tibetan-analysis-sanskrit--read-sections (filepath)
  "Return preserved Sanskrit-Claude content in FILEPATH as a plist
with keys `:translation' / `:devanagari' / `:sandhi' /
`:word-list' / `:grammar'.  Each value is a non-empty string or
nil."
  (list :translation
        (tibetan-analysis-sanskrit--read-section-body
         filepath "Claude Translation")
        :devanagari
        (tibetan-analysis-sanskrit--read-section-body
         filepath "Devanagari")
        :sandhi
        (tibetan-analysis-sanskrit--read-section-body
         filepath "Sandhi Decomposition")
        :word-list
        (tibetan-analysis-sanskrit--read-section-body
         filepath "Word List")
        :grammar
        (tibetan-analysis-sanskrit--read-section-body
         filepath "Grammar")))

(defun tibetan-analysis-sanskrit--restore-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's `* Sanskrit Analysis'
section.  Any nil slot leaves the corresponding body
untouched.  Creates the parent `* Sanskrit Analysis' and
section headings if absent."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        ;; Only proceed when at least one slot is non-nil.
        (when (cl-some (lambda (entry)
                         (plist-get sections (nth 0 entry)))
                       tibetan-analysis-sanskrit--section-order)
          (tibetan-analysis-sanskrit--ensure-parent buf)
          (dolist (entry tibetan-analysis-sanskrit--section-order)
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry)))
              (when (plist-get sections key)
                (tibetan-analysis-sanskrit--ensure-section buf heading)
                (tibetan-analysis-sanskrit--replace-section-body
                 buf heading (plist-get sections key)))))
          (save-buffer)
          t)))))

;; ============================================================================
;; ASYNC FIRE (wired by Phase 5 dispatcher)
;; ============================================================================

;;;###autoload
(defun tibetan-analysis-sanskrit--request-translation
    (sanskrit-plist source-file analysis-file &optional callback)
  "Fire an async Sanskrit Claude call for SANSKRIT-PLIST.

On response, parses sections + writes them to ANALYSIS-FILE
under `* Sanskrit Analysis'.  CALLBACK (if non-nil) is called
with one arg — the parsed plist — after the write.  Phase 5's
Combined dispatcher uses CALLBACK to chain.

Goes through `tibetan-claude-queue' so the request shares the
rate-limit budget + retry-on-429 logic with Tibetan calls
\(concurrency optimization, 2026-04-30:  before this commit
the Sanskrit call bypassed the queue entirely, which meant a
batch of N segments fired N simultaneous Sanskrit requests
with no throttle and no 429 retry).  Per-segment
concurrency is preserved: with default concurrency cap of 3,
one segment's Tibetan + Sanskrit calls run in parallel, and
the chained Combined call follows once both finish.

No-op when:
  - SANSKRIT-PLIST is nil / lacks IAST.
  - `gptel' or `tibetan-claude-queue' is missing (soft-required).
  - Build prompts returns nil."
  (when (and sanskrit-plist
             (fboundp 'gptel-request)
             (fboundp 'tibetan-analysis--ensure-gptel-ready)
             (fboundp 'tibetan-claude-queue-submit))
    (require 'tibetan-claude-queue)
    (let* ((label (and analysis-file
                       (concat "skt:"
                               (file-name-nondirectory analysis-file))))
           (prompts (tibetan-analysis-sanskrit--build-prompts
                     sanskrit-plist source-file analysis-file)))
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
                                   (tibetan-analysis-sanskrit--parse-claude-sections
                                    response)))
                              (tibetan-analysis-sanskrit--insert-sections
                               response analysis-file)
                              (when callback (funcall callback parsed)))
                          (error
                           (message "Sanskrit insert failed for %s: %s"
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
             (message "Sanskrit Claude request failed for %s: %s"
                      (or label "<file>")
                      (cond
                       ((eq kind 'rate-limited)
                        "rate-limited (HTTP 429) after retries")
                       (t (or (plist-get status :error) "unknown")))))))))))

(provide 'tibetan-analysis-sanskrit)
;;; tibetan-analysis-sanskrit.el ends here
