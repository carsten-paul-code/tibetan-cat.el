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
(with optional Devanagari) and must produce a Sanskrit-side \
philological analysis.  Emit each section as a single `## ' \
Markdown heading followed by its body.

REQUIRED sections (always emit; never abbreviate or omit):

`## Translation'
  Your translation of the Sanskrit into the target language. \
  Render the Sanskrit on its own terms — do not paraphrase the \
  Tibetan canon's reading; this analysis runs alongside an \
  independent Tibetan analysis and the reader compares them. \
  Required even for very short segments.

`## Word List'
  One bullet per content word.  Each line:  IAST word — lemma \
  (case + number + gender for nouns / pronouns; root + tense \
  + person + number for verbs) — short English gloss.  \
  Particles get compact entries (just the gloss).  Required.

`## Grammar'
  Prose reading: case-frame analysis, verb conjugation, \
  structural notes, clause-level dependencies.  Mention any \
  features that look unusual against typical Yogācāra prose. \
  Required even for short or simple passages — write at least \
  a sentence on what the case frame is doing.

CONDITIONAL sections (emit only when the predicate holds; \
otherwise skip the section heading entirely):

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
                   ;; `:claude-context' is a LIST of strings (one per
                   ;; `#+TIBETAN_CLAUDE_CONTEXT:' header line, in
                   ;; document order) — not a single concatenated
                   ;; string.  Mirror the Tibetan-side builder's
                   ;; per-line iteration:  prefix each line with a
                   ;; bullet and join with newlines.  Bug fix
                   ;; 2026-05-03:  earlier this passed the raw list
                   ;; to `concat', which treats list elements as
                   ;; characters and crashes with `(wrong-type-
                   ;; argument characterp <STRING>)' on any source
                   ;; that has at least one context header.
                   (when (and claude-context (listp claude-context))
                     (concat
                      "\nDocument context (genre / register / "
                      "vocabulary):\n"
                      (mapconcat (lambda (line) (format "  - %s" line))
                                 claude-context "\n")
                      "\n")))))
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
                         "\n\nProduce the Sanskrit-side analysis using this "
                         "EXACT response template.  Emit every REQUIRED "
                         "heading (the heading line PLUS its body) even "
                         "if the body is brief; do not silently merge "
                         "sections, do not abbreviate to fewer headings.  "
                         "Emit the CONDITIONAL headings only when their "
                         "predicate holds; otherwise omit both heading "
                         "and body.\n\n"
                         "REQUIRED — emit every time (do not skip even "
                         "for one-clause segments):\n\n"
                         "## Translation\n"
                         "[your translation here]\n\n"
                         "## Word List\n"
                         "[one bullet per content word with case/number/"
                         "gender (nouns) or root/tense/person/number "
                         "(verbs)]\n\n"
                         "## Grammar\n"
                         "[prose case-frame + structural analysis; at "
                         "minimum one sentence on what the case frame is "
                         "doing and what the verb is]\n\n"
                         "CONDITIONAL — emit only when predicate holds:\n\n"
                         "## Devanagari   (only if user prompt lacks "
                         "Devanagari)\n"
                         "[Devanagari rendering]\n\n"
                         "## Sandhi   (only if sandhi joints are present)\n"
                         "[one bullet per joint]\n\n"
                         "Brevity-as-quality-judgment is wrong here: even "
                         "a one-line Sanskrit clause needs Translation + "
                         "Word List + Grammar so the reader can compare "
                         "them to the parallel Tibetan analysis side-by-"
                         "side.  When in doubt, EMIT the section with a "
                         "brief body rather than dropping it.")))
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
;; POST-FIRE VALIDATION + RETRY (2026-05-04, Issue 1)
;; ============================================================================
;;
;; Live observation:  on short gotrapaṭala segments after the §5.18
;; layout-revision work landed, Sanskrit Claude was returning
;; partial responses missing `## Translation' and `## Grammar'.  The
;; system + user prompts had already been hardened to "REQUIRED
;; — emit every time" (see `--build-prompts'), but Claude still
;; collapsed brevity-as-quality on one-clause segments.
;;
;; Belt-and-braces fix:  AFTER parsing the response, detect missing
;; required sections and fire ONE focused retry through the same
;; in-flight queue thunk asking for ONLY the missing pieces.  The
;; retry's SYSTEM block is byte-identical to the first call's SYSTEM
;; block (Anthropic prompt cache stays warm).  The retry's USER
;; block re-includes the IAST + names the missing sections.
;;
;; On retry response, MERGE retry into original (original wins on
;; collisions — retry is fill-missing, not overwrite) and write the
;; merged plist via `--write-from-plist'.

(defconst tibetan-analysis-sanskrit--required-keys
  '(:translation :word-list :grammar)
  "Plist keys from `--parse-claude-sections' that MUST be populated
for the response to count as complete.  `:devanagari' and
`:sandhi' are conditional — Claude correctly omits them when the
predicate doesn't hold.")

(defun tibetan-analysis-sanskrit--missing-required-sections (parsed)
  "Return the subset of `--required-keys' that are missing or empty
in PARSED.  Empty list → response is complete enough to write
without retry."
  (cl-remove-if
   (lambda (key)
     (let ((val (plist-get parsed key)))
       (and val (stringp val)
            (not (string-empty-p (string-trim val))))))
   tibetan-analysis-sanskrit--required-keys))

(defun tibetan-analysis-sanskrit--merge-parsed (original retry)
  "Combine ORIGINAL and RETRY parsed plists.  For each section key
in `--section-order', prefer ORIGINAL's non-empty value;  fall
back to RETRY's value when ORIGINAL's slot is nil/empty.  Result
is a fresh plist (does not mutate inputs).

Original wins on collisions because the retry is FILL-MISSING,
not OVERWRITE — a verbose retry response should never clobber a
perfectly-good Word List from the first try."
  (let ((all-keys '(:translation :devanagari :sandhi :word-list :grammar))
        (out '()))
    (dolist (key all-keys)
      (let ((orig-val (plist-get original key))
            (retry-val (plist-get retry key)))
        (setq out
              (plist-put out key
                         (cond
                          ((and orig-val (stringp orig-val)
                                (not (string-empty-p (string-trim orig-val))))
                           orig-val)
                          ((and retry-val (stringp retry-val)
                                (not (string-empty-p (string-trim retry-val))))
                           retry-val)
                          (t nil))))))
    out))

(defun tibetan-analysis-sanskrit--key-to-heading (key)
  "Map a parsed plist KEY back to its `## ' heading token (for use
in retry prompts).  Inverse of `--heading-key'."
  (cond
   ((eq key :translation) "Translation")
   ((eq key :devanagari)  "Devanagari")
   ((eq key :sandhi)      "Sandhi")
   ((eq key :word-list)   "Word List")
   ((eq key :grammar)     "Grammar")
   (t nil)))

(defun tibetan-analysis-sanskrit--build-retry-prompts
    (sanskrit-plist source-file missing-keys)
  "Build (SYSTEM . USER) prompts for a focused Sanskrit retry.

SYSTEM is byte-identical to `--build-prompts' so the Anthropic
prompt cache stays warm — only the user-block delta is billed at
full rate on the retry.

USER re-includes the original IAST (and Devanagari when present)
and explicitly names the sections the previous response did not
emit, instructing Claude to produce ONLY those.

Returns nil when SANSKRIT-PLIST lacks IAST or MISSING-KEYS is
empty."
  (when (and sanskrit-plist
             (plist-get sanskrit-plist :iast)
             missing-keys
             (consp missing-keys))
    (let* ((base (tibetan-analysis-sanskrit--build-prompts
                  sanskrit-plist source-file nil)))
      (when base
        (let* ((system (car base))
               (iast (plist-get sanskrit-plist :iast))
               (devanagari (plist-get sanskrit-plist :devanagari))
               (heading-list
                (mapconcat
                 (lambda (k)
                   (format "  - ## %s"
                           (or (tibetan-analysis-sanskrit--key-to-heading k)
                               (symbol-name k))))
                 missing-keys "\n"))
               (user
                (concat
                 "Sanskrit passage (IAST):\n\n"
                 iast
                 (when (and devanagari (stringp devanagari)
                            (not (string-empty-p (string-trim devanagari))))
                   (format "\n\nSanskrit passage (Devanagari):\n\n%s"
                           devanagari))
                 "\n\nYour previous response for this passage was "
                 "incomplete:  the following REQUIRED sections were "
                 "not emitted:\n\n"
                 heading-list
                 "\n\nProduce ONLY the missing sections, each as a "
                 "single `## ' heading followed by its body, in the "
                 "same format the original prompt specified.  Do NOT "
                 "re-emit sections you already provided — emit only "
                 "the headings listed above.  Even for a one-clause "
                 "passage, give a complete Translation and at least "
                 "one sentence of Grammar (case-frame + verb)."
                 )))
          (cons system user))))))

;; ============================================================================
;; SECTION ORDER + WRITER (response → analysis file)
;; ============================================================================

(defconst tibetan-analysis-sanskrit--section-order
  '((:devanagari "Devanagari"            2)
    (:sandhi     "Sandhi Decomposition"  2)
    (:word-list  "Word List"             2)
    (:translation "Translation"          2)
    (:grammar    "Grammar"               2))
  "Canonical order, heading names, and org levels for Sanskrit
Claude sections inside `* Sanskrit Analysis'.  Every entry is
\(KEY HEADING LEVEL).  Devanagari is conditional (only when
source lacks it); the others are always present when the
Sanskrit pipeline fires.

Phase 1.4 of layout-revision §5.18 (2026-05-04): the `:translation'
slot's heading is `Translation' (was `Claude Translation').  Parent
context (`* Sanskrit Analysis') makes the language-attribution
clear so the redundant `Claude' qualifier on the level-2 heading
drops.  Mirrors the Tibetan-side rename in Phase 1.3.")

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

(defun tibetan-analysis-sanskrit--migrate-legacy-translation-heading (buffer)
  "Rename any legacy `** Claude Translation' inside `* Sanskrit
Analysis' → `** Translation' (Phase 1.4 of layout-revision §5.18,
2026-05-04).  Idempotent — no-op when the file already uses the
new heading name.

This runs at the start of `--insert-sections' /
`--restore-sections' so the existence checks downstream can search
for the new name and find it on legacy files."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Sanskrit Analysis$" nil t)
        (let ((bound (save-excursion
                       (if (re-search-forward "^\\* " nil t)
                           (line-beginning-position)
                         (point-max)))))
          (while (re-search-forward "^\\*\\* Claude Translation$" bound t)
            (replace-match "** Translation" t t)))))))

(defun tibetan-analysis-sanskrit--ensure-section (buffer heading)
  "Ensure HEADING (a level-2 string) exists inside `* Sanskrit Analysis'
in BUFFER.  Appends at the end of the parent section if absent.
Idempotent."
  ;; Phase 1.4 of layout-revision §5.18 (2026-05-04): rename any
  ;; legacy `** Claude Translation' before checking heading
  ;; existence.  This avoids creating a NEW `** Translation' next
  ;; to the legacy heading (would yield duplicate sections).
  (tibetan-analysis-sanskrit--migrate-legacy-translation-heading buffer)
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

(defun tibetan-analysis-sanskrit--write-from-plist (sections analysis-file)
  "Write SECTIONS (a parsed plist) into ANALYSIS-FILE under `*
Sanskrit Analysis' (top-level).  Each non-nil entry in
`--section-order' is written under its heading; nil entries are
skipped (their existing org body stays).

Returns t on successful write, nil when ANALYSIS-FILE is missing
or SECTIONS has no populated slots.

Extracted from `--insert-sections' (2026-05-04, Issue 1) so the
post-fire retry path can write a MERGED plist (original + retry)
without round-tripping through a synthesised response string."
  (when (and sections analysis-file (file-exists-p analysis-file))
    (let ((buf (or (find-buffer-visiting analysis-file)
                   (find-file-noselect analysis-file))))
      (with-current-buffer buf
        ;; Only proceed when at least one section was populated.
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

(defun tibetan-analysis-sanskrit--insert-sections (response analysis-file)
  "Parse a Sanskrit Claude RESPONSE and write its sections into
ANALYSIS-FILE under `* Sanskrit Analysis' (top-level).  Each
section named in `tibetan-analysis-sanskrit--section-order'
that the parser populated is written under its heading;
missing sections are skipped (their existing body stays).

Thin wrapper around `--write-from-plist' (2026-05-04 refactor):
parse → plist → write.  Existing call sites unchanged.

Returns t on successful write, nil when ANALYSIS-FILE is
missing or RESPONSE is empty."
  (when (and response analysis-file (file-exists-p analysis-file))
    (tibetan-analysis-sanskrit--write-from-plist
     (tibetan-analysis-sanskrit--parse-claude-sections response)
     analysis-file)))

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
nil.

Phase 1.4 of layout-revision §5.18 (2026-05-04):  the
`:translation' lookup tries the new heading `Translation' first
and falls back to the legacy `Claude Translation' so files
written with the old heading still resolve cleanly."
  (list :translation
        (or (tibetan-analysis-sanskrit--read-section-body
             filepath "Translation")
            (tibetan-analysis-sanskrit--read-section-body
             filepath "Claude Translation"))
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

(defun tibetan-analysis-sanskrit--fire-retry-for-missing
    (sanskrit-plist source-file analysis-file partial missing-keys label callback done)
  "Fire one focused Sanskrit Claude retry asking only for MISSING-KEYS.

PARTIAL is the original parsed plist (which slots were populated
by the first response).  On retry response, MERGE into PARTIAL
(original wins on collisions) and write the merged plist via
`--write-from-plist'.  CALLBACK is the user-supplied callback
from `--request-translation' (chains the Combined call).  DONE
is the queue thunk's done-callback.

When the retry prompt cannot be built, or the retry call itself
returns an empty response, fall back to writing PARTIAL alone —
the user gets whatever sections did make it on the first pass,
not nothing.  Done is always called exactly once per invocation
of this helper.

Caller stays inside the queue's in-flight thunk for the duration
of the retry — concurrency cap is correctly respected and the
rate-limit budget is shared with the Tibetan side."
  (let ((retry-prompts
         (tibetan-analysis-sanskrit--build-retry-prompts
          sanskrit-plist source-file missing-keys)))
    (cond
     ;; No retry possible (e.g. empty IAST).  Write what we have.
     ((not retry-prompts)
      (condition-case e
          (progn
            (tibetan-analysis-sanskrit--write-from-plist partial analysis-file)
            (when callback (funcall callback partial)))
        (error
         (message "Sanskrit partial-write failed for %s: %s"
                  (or label "<file>")
                  (error-message-string e))))
      (funcall done '(:status ok)))
     (t
      (condition-case err
          (let ((gptel-cache '(system)))
            (gptel-request
             (cdr retry-prompts)
             :system (car retry-prompts)
             :callback
             (lambda (retry-response _retry-info)
               (let* ((retry-parsed
                       (and retry-response (stringp retry-response)
                            (not (string-empty-p retry-response))
                            (tibetan-analysis-sanskrit--parse-claude-sections
                             retry-response)))
                      (merged
                       (if retry-parsed
                           (tibetan-analysis-sanskrit--merge-parsed
                            partial retry-parsed)
                         partial)))
                 (condition-case e
                     (progn
                       (tibetan-analysis-sanskrit--write-from-plist
                        merged analysis-file)
                       (when callback (funcall callback merged)))
                   (error
                    (message "Sanskrit retry-merge write failed for %s: %s"
                             (or label "<file>")
                             (error-message-string e))))
                 (funcall done '(:status ok))))))
        (error
         (message "Sanskrit retry submission failed for %s: %s"
                  (or label "<file>")
                  (error-message-string err))
         ;; Fall back to writing what we already have.
         (condition-case _e
             (progn
               (tibetan-analysis-sanskrit--write-from-plist
                partial analysis-file)
               (when callback (funcall callback partial)))
           (error nil))
         (funcall done '(:status ok))))))))

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
                        ;; Post-fire validation + optional retry
                        ;; (2026-05-04, Issue 1).  Parse first; if any
                        ;; required section (Translation / Word List
                        ;; / Grammar) is missing, fire ONE focused
                        ;; retry inside the same in-flight queue
                        ;; thunk.  Otherwise write + finish as
                        ;; before.
                        (condition-case e
                            (let* ((parsed
                                    (tibetan-analysis-sanskrit--parse-claude-sections
                                     response))
                                   (missing
                                    (tibetan-analysis-sanskrit--missing-required-sections
                                     parsed)))
                              (cond
                               ;; Complete response — fast path.
                               ((null missing)
                                (tibetan-analysis-sanskrit--write-from-plist
                                 parsed analysis-file)
                                (when callback (funcall callback parsed))
                                (funcall done '(:status ok)))
                               ;; Incomplete response — fire retry.
                               (t
                                (tibetan-analysis-sanskrit--fire-retry-for-missing
                                 sanskrit-plist source-file analysis-file
                                 parsed missing label callback done))))
                          (error
                           (message "Sanskrit insert failed for %s: %s"
                                    (or label "<file>")
                                    (error-message-string e))
                           (funcall done '(:status ok)))))
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
