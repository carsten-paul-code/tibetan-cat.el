;;; tibetan-sentence-persist.el --- Persistent sentence-level analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Sentence-level analysis layer for the Tibetan CAT Tool.  A *sentence*
;; is a super-segmental grouping that wraps one or more contiguous
;; segments — declared in the source file as `*** Sentence N' headings
;; with `**** Segment M' children (the layout produced by
;; `tibetan-add-sentence-structure').
;;
;; Segments stay parsed individually for clause-level grammar work via
;; `tibetan-analysis-persist'.  This module persists a separate
;; `analysis/sent-NNN.org' file alongside the per-segment
;; `analysis/seg-NNN.org' files so that sentence-level work — published
;; reference translation (e.g. Roehrich), discourse-level Claude
;; analysis, working translation, notes — does not collide with the
;; segment-level scaffolding.
;;
;; Usage:
;;   C-c s A - Open/create analysis for current sentence
;;             (works from cursor on `*** Sentence N' heading or any
;;             `**** Segment M' inside it)
;;   C-c s R - Re-analyze current sentence (regenerates auto sections,
;;             preserves user notes and Roehrich/Class translations).
;;             With `C-u' prefix, also re-issues the Claude request.
;;   C-c s r - Batch reanalyze every sentence file in the analysis
;;             folder.  With `C-u' prefix, also re-issues Claude on
;;             every sentence (N async calls).
;;
;; File layout:
;;   your-text.org
;;   analysis/
;;     seg-001.org   ; segment-level (existing)
;;     seg-002.org
;;     ...
;;     sent-001.org  ; sentence-level (this module)
;;     sent-002.org
;;     ...
;;
;; Body shape of a sentence file:
;;   * Tibetan Text          — concatenated from child segments
;;   * Wylie                 — concatenated, when available
;;   * Provided Translations
;;     *** Roehrich          — published reference, hand-pasted
;;     *** Class Translation
;;     *** Claude Translation
;;     *** Claude Grammar
;;     *** Claude Context
;;   * Working Translation
;;   * My Notes
;;   * Footnotes
;;
;; Hash invariant: the `#+TIBETAN_HASH:' header is computed over the
;; concatenated child-segment text.  This catches both edits to any
;; child segment AND changes in segment membership of the sentence.

;;; Code:

(require 'cl-lib)
;; Only require org when not in batch mode (can hang in batch).
(unless noninteractive
  (require 'org))
(require 'md5)

;; The Claude integration — three-section system, parsing, scaffolding,
;; gptel readiness — is shared with the segment-level module.  Soft
;; require the per-segment module so we can reuse its primitives without
;; duplicating ~200 lines of buffer-rewriting helpers.
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-org-structure nil t)
(require 'tibetan-utils nil t)
(require 'gptel nil t)

;; Silence byte-compile warnings when gptel is not installed.
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(defvar gptel-cache)                    ; gptel prompt-caching toggle

;; Forward declarations for the auto-segmenter companion module.
;; `tibetan-sentence-resegment' (defined below) chains the
;; structural reset in `doc-prep/tibetan-sentence-structure.el'
;; together with this module's archive + batch-create helpers.
(declare-function tibetan-sentence-reset-structure
                  "tibetan-sentence-structure" ())
(declare-function tibetan-sentence-reset-structure--counts
                  "tibetan-sentence-structure" (buffer))
(declare-function tibetan-add-sentence-structure
                  "tibetan-sentence-structure" ())

(defconst tibetan-sentence-persist-version "1.0"
  "Version of the sentence analysis file format.")

;; ============================================================================
;; PATH AND FILENAME FUNCTIONS
;; ============================================================================

(defun tibetan-sentence--get-folder ()
  "Return the analysis folder for the current source buffer.
Reuses `tibetan-analysis-get-folder' so segment and sentence files
land in the same `analysis/' directory."
  (if (fboundp 'tibetan-analysis-get-folder)
      (tibetan-analysis-get-folder)
    ;; Fallback: derive from buffer-file-name.
    (let* ((src (buffer-file-name))
           (dir (and src (file-name-directory src)))
           (analysis-dir (and dir (expand-file-name "analysis" dir))))
      (unless (and analysis-dir (file-exists-p analysis-dir))
        (when analysis-dir (make-directory analysis-dir t)))
      analysis-dir)))

(defun tibetan-sentence--filename (sent-num)
  "Return basename `sent-NNN.org' for SENT-NUM (an integer)."
  (format "sent-%03d.org" sent-num))

(defun tibetan-sentence--filepath (sent-num &optional folder)
  "Return absolute path of `sent-NNN.org' for SENT-NUM.
FOLDER defaults to `tibetan-sentence--get-folder'."
  (let ((folder (or folder (tibetan-sentence--get-folder))))
    (when folder
      (expand-file-name (tibetan-sentence--filename sent-num) folder))))

(defun tibetan-sentence--sent-id-from-filename (filepath)
  "Extract numeric sentence id from FILEPATH's basename, or nil."
  (let ((base (file-name-nondirectory filepath)))
    (when (string-match "sent-\\([0-9]+\\)" base)
      (string-to-number (match-string 1 base)))))

(defun tibetan-sentence--seg-id-from-filename (filepath)
  "Extract numeric segment id from FILEPATH's basename, or nil."
  (let ((base (file-name-nondirectory filepath)))
    (when (string-match "seg-\\([0-9]+\\)" base)
      (string-to-number (match-string 1 base)))))

;; ============================================================================
;; SOURCE-FILE SENTENCE SCANNER
;; ============================================================================

(defun tibetan-sentence--current-sentence-bounds ()
  "Return the buffer position bounds of the current sentence as (BEG . END).
Works when point is on a `*** Sentence N' heading or anywhere inside
it (including under one of its `**** Segment M' children).  Returns
nil if no sentence is in scope."
  (save-excursion
    (catch 'no-sentence
      (condition-case nil
          (progn
            (unless (org-at-heading-p)
              (org-back-to-heading t))
            ;; Walk up until we land on a `Sentence' heading or run
            ;; out of parent headings.
            (while (and (org-current-level)
                        (not (string-match-p
                              "\\bSentence\\b"
                              (or (org-get-heading t t t t) ""))))
              (unless (org-up-heading-safe)
                (throw 'no-sentence nil)))
            (when (and (org-current-level)
                       (string-match-p
                        "\\bSentence\\b"
                        (or (org-get-heading t t t t) "")))
              (let ((beg (point))
                    (end (save-excursion
                           (org-end-of-subtree t t)
                           (point))))
                (cons beg end))))
        (error nil)))))

(defun tibetan-sentence--current-sentence-num ()
  "Return the sentence number of the sentence containing point, or nil."
  (save-excursion
    (let ((bounds (tibetan-sentence--current-sentence-bounds)))
      (when bounds
        (goto-char (car bounds))
        (let ((heading (org-get-heading t t t t)))
          (when (and heading
                     (string-match "Sentence \\([0-9]+\\)" heading))
            (string-to-number (match-string 1 heading))))))))

(defun tibetan-sentence--collect-children-in-range (beg end)
  "Collect Segment children of the sentence between BEG and END.
Returns a list of plists `(:seg-num N :text STR :beg POS :end POS)'
in source order, or nil when no segments are found.  Segments are
matched by heading text (`Segment N'), not by level, so the function
works for any heading depth produced by `tibetan-add-sentence-structure'
or `tibetan-prepare-document'."
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      ;; Skip the sentence heading itself.
      (when (org-at-heading-p)
        (forward-line 1))
      (let ((children '()))
        (while (re-search-forward "^\\*+[ \t]+Segment[ \t]+\\([0-9]+\\)"
                                  nil t)
          (let* ((seg-num (string-to-number (match-string 1)))
                 (heading-end (line-end-position))
                 (subtree-beg (1+ heading-end))
                 (subtree-end (save-excursion
                                (org-end-of-subtree t t)
                                (point)))
                 (raw (and (<= subtree-beg subtree-end)
                           (buffer-substring-no-properties
                            subtree-beg subtree-end)))
                 (text (and raw (string-trim raw))))
            (when (and text (not (string-empty-p text)))
              (push (list :seg-num seg-num
                          :text text
                          :beg (line-beginning-position)
                          :end subtree-end)
                    children))
            ;; Move past this subtree to the next sibling.
            (goto-char subtree-end)))
        (nreverse children)))))

(defun tibetan-sentence--collect-current-sentence ()
  "Collect data for the sentence at point.
Returns a plist
  (:sent-num N
   :children ((:seg-num M :text STR :beg POS :end POS) ...)
   :tibetan-text STR  ; concatenated child texts, blank-line separated
   :seg-nums (M1 M2 ...))
or nil when no sentence is in scope."
  (let* ((bounds (tibetan-sentence--current-sentence-bounds))
         (sent-num (tibetan-sentence--current-sentence-num)))
    (when (and bounds sent-num)
      (let* ((children (tibetan-sentence--collect-children-in-range
                        (car bounds) (cdr bounds)))
             (texts (mapcar (lambda (c) (plist-get c :text)) children))
             (joined (mapconcat #'identity texts "\n"))
             (seg-nums (mapcar (lambda (c) (plist-get c :seg-num))
                               children)))
        (list :sent-num sent-num
              :children children
              :tibetan-text (string-trim joined)
              :seg-nums seg-nums)))))

(defun tibetan-sentence--collect-from-source-buffer (sent-num)
  "Re-scan the current buffer for sentence SENT-NUM and return its data.
Like `tibetan-sentence--collect-current-sentence' but driven by
SENT-NUM rather than point position.  Returns nil when SENT-NUM is
not present in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\*+[ \t]+Sentence[ \t]+%d\\b" sent-num) nil t)
      (beginning-of-line)
      (tibetan-sentence--collect-current-sentence))))

;; ============================================================================
;; HASH FUNCTIONS
;; ============================================================================

(defun tibetan-sentence--compute-hash (concatenated-text)
  "Return MD5 of CONCATENATED-TEXT (utf-8) for change detection.
Reuses `tibetan-analysis-compute-hash' when the segment-persist
module is loaded so both hashing schemes stay identical."
  (if (fboundp 'tibetan-analysis-compute-hash)
      (tibetan-analysis-compute-hash concatenated-text)
    (md5 (encode-coding-string (or concatenated-text "") 'utf-8))))

(defun tibetan-sentence--get-stored-hash (filepath)
  "Return the `#+TIBETAN_HASH:' header value stored in FILEPATH, or nil."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH:[ \t]*\\(.+\\)$" nil t)
        (string-trim (match-string 1))))))

(defun tibetan-sentence--check-sync (filepath concatenated-text)
  "Return non-nil if FILEPATH's stored hash matches CONCATENATED-TEXT."
  (let ((stored  (tibetan-sentence--get-stored-hash filepath))
        (current (tibetan-sentence--compute-hash concatenated-text)))
    (and stored (string= stored current))))

;; ============================================================================
;; SECTION HELPERS — top-level (* …) sections
;; ============================================================================

(defun tibetan-sentence--find-section-bounds (buffer section-name)
  "Find positions of `* SECTION-NAME' in BUFFER.
Returns (START . END) or nil."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (let ((start (line-beginning-position))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (cons start end))))))

(defun tibetan-sentence--read-section-body (filepath section-name)
  "Return the trimmed body of `* SECTION-NAME' in FILEPATH, or nil."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\* %s$" (regexp-quote section-name)) nil t)
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (let ((body (string-trim
                       (buffer-substring-no-properties start end))))
            (unless (string-empty-p body) body)))))))

(defun tibetan-sentence--read-third-level-body (filepath heading)
  "Return the trimmed body under `*** HEADING' in FILEPATH, or nil.
Skips placeholder text so we don't carry empty scaffolding around."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\*\\* %s$" (regexp-quote heading))
             nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (save-excursion
                      (if (re-search-forward
                           "^\\*\\*\\*\\|^\\*\\*[^*]\\|^\\* " nil t)
                          (line-beginning-position)
                        (point-max))))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (unless (or (string-empty-p body)
                      (string-match-p "\\`\\[Awaiting" body)
                      (string-match-p "\\`\\[Hand-paste" body)
                      (string-match-p "\\`\\[Working " body)
                      (string-match-p "\\`\\[Requesting" body)
                      (string-match-p "\\`\\[Claude unavailable" body)
                      (string-match-p "\\`\\[Translation not available" body))
            body))))))

(defun tibetan-sentence--get-user-sections (filepath)
  "Read user-owned sections from FILEPATH.
Returns alist of (SECTION . CONTENT) for the trio that survives
re-analysis: My Notes, Working Translation, Footnotes.  Each CONTENT
covers the heading line through (just before) the next `* ' heading
or end-of-file, so it can be re-inserted verbatim if the section
gets clobbered by regeneration."
  (when (and filepath (file-exists-p filepath))
    (let (out)
      (with-temp-buffer
        (insert-file-contents filepath)
        (dolist (name '("My Notes" "Working Translation" "Footnotes"))
          (let ((bounds (tibetan-sentence--find-section-bounds
                         (current-buffer) name)))
            (when bounds
              (push (cons name
                          (buffer-substring-no-properties
                           (car bounds) (cdr bounds)))
                    out)))))
      (nreverse out))))

(defconst tibetan-sentence--parallel-top-level-sections
  '("Sanskrit Text"
    "Sanskrit Analysis"
    "Combined Analysis"
    "DharmaMitra Translation (Sanskrit)"
    "Sanskrit (DharmaMitra)")
  "Top-level analysis sections written by the parallel-Sanskrit Claude
/ DharmaMitra pipeline (`tibetan-analysis--fire-parallel-claude-with-
plist').  They live OUTSIDE `* Tibetan Analysis' and carry upstream
Claude / DM content that must survive regenerate without re-firing —
mirroring the segment path's `tibetan-analysis-get-user-sections'.
The level-2 `** DharmaMitra Translation' (Tibetan side) is deliberately
omitted: it is stripped from the compressed sentence layout (see
`tibetan-sentence--strip-list').")

(defun tibetan-sentence--read-parallel-top-level-sections (filepath)
  "Return alist (HEADING-NAME . FULL-SECTION-TEXT) for the parallel-mode
top-level sections present in FILEPATH.

FULL-SECTION-TEXT covers the `* HEADING' line through just before the
next top-level heading (or end-of-file), so it can be re-appended
verbatim by the regenerate RESTORE phase."
  (when (and filepath (file-exists-p filepath))
    (let (out)
      (with-temp-buffer
        (insert-file-contents filepath)
        (dolist (name tibetan-sentence--parallel-top-level-sections)
          (let ((bounds (tibetan-sentence--find-section-bounds
                         (current-buffer) name)))
            (when bounds
              (push (cons name
                          (buffer-substring-no-properties
                           (car bounds) (cdr bounds)))
                    out)))))
      (nreverse out))))

(defun tibetan-sentence--append-top-level-section (buffer full-text)
  "Append FULL-TEXT (a `* Heading' … block) at the end of BUFFER.
Ensures a blank-line separator before the new section.  No-op when
FULL-TEXT is blank."
  (when (and full-text (not (string-empty-p (string-trim full-text))))
    (with-current-buffer buffer
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      ;; Guarantee a blank line before the appended top-level section.
      (unless (looking-back "\n\n" 2) (insert "\n"))
      (insert (string-trim-right full-text) "\n"))))

(defun tibetan-sentence--read-translation-bodies (filepath)
  "Read user-owned third-level translation bodies from FILEPATH.
Returns plist `(:roehrich STR :class STR)' (each non-nil only when
the corresponding heading has real content, not placeholder text)."
  (list :roehrich (tibetan-sentence--read-third-level-body filepath "Roehrich")
        :class    (tibetan-sentence--read-third-level-body filepath "Class Translation")))

;; ============================================================================
;; FILE CREATION (scaffold)
;; ============================================================================

(defconst tibetan-sentence--strip-list
  '("** Wylie Transliteration"
    "** Phonetics"
    "** Interlinear Gloss"
    "** DharmaMitra Translation"
    ;; ** Sentence Structure is NO LONGER stripped (2026-06-02):  the
    ;; full per-clause subject/object structure is the headline class
    ;; tool for sentences and replaces the old `** Main Clause' summary.
    "** Verb Classification (Hill 2010)"
    "** Detailed Dictionary")
  "Level-2 headings dropped from the segment-renderer output before
it is embedded in a sentence file's `* Tibetan Analysis' block.

§5.22 final (2026-05-21):  sentence files are ALWAYS rendered in
the class-reading compressed layout.  Per-segment seg-NNN.org
files keep the full §5.21 layout (these sections only get
stripped from the sentence renderer's path;  the segment scaffold
is unaffected).

What stays (implicitly, by NOT being in this list):
  · `** Claude Vocabulary' — Claude's per-word annotations.
  · `** Translation' — Claude's primary translation.
  · `** Grammar' — Claude's prose + merged `*** Particles' with
    Bialek 2022 / Portfolio refs (the converb-rich structure
    section the in-class reading turns on).
  · `** Provided Translations' — user-content slot with sentence-
    only L3 extras (Roehrich / Class Translation / Claude Context)
    injected by `--inject-sentence-l3-entries' after stripping.

User feedback (2026-05-21):  \"the full layout isn't necessary
for the sentence, only for the segments… max 2 pages A4 per
sentence with the really important information, esp. the
structure (with converbs).\"  The opt-in machinery from §5.22
initial (`#+TIBETAN_SENTENCE_COMPRESSED:' header, toggle command,
keybinding) is retired in favour of unconditional compression.")

(defvar tibetan-sentence--detail-for-render nil
  "Dynamic binding:  the `:sentence-detail' value for the in-flight
sentence-scaffold render.  When `detailed', the strip-list is
suppressed so the embedded segment-renderer output passes
through unmodified — sentence files mirror the full §5.21
segment layout (Wylie / Phonetics / Interlinear / etc. all
present).

§5.27 Phase 5 (2026-05-26):  let-bound by
`tibetan-sentence--create-file' and `tibetan-sentence--regenerate'
based on the source-document's `#+TIBETAN_SENTENCE_DETAIL:'
header.  Consumed by `--segment-claude-sections' below.

Nil → default compressed behaviour from §5.22 final
\(backwards-compatible).  String `\"detailed\"' → full §5.21
layout.  Any other string treated as `compressed' (defensive).")

(defun tibetan-sentence--segment-claude-sections ()
  "Return the list of level-2 headings to strip from segment-renderer
output before embedding it in a sentence file.

§5.27 Phase 5 (2026-05-26):  consults
`tibetan-sentence--detail-for-render':
  · `\"detailed\"'  → empty list (no stripping;  full §5.21
                       segment layout flows through).  Reader
                       gets all 11 L2 sections in the sentence
                       file — for thorough reading classes.
  · `\"compressed\"' / nil / anything else → `--strip-list'
                       (the §5.22 default 7-entry filter,
                       sentence file collapses to 4 L2 sections,
                       ~2 A4 pages).

Pre-§5.27:  always returned `--strip-list' unconditionally
\(§5.22 final).  The dynamic-var gate restores per-document
control via the new `#+TIBETAN_SENTENCE_DETAIL:' header without
re-introducing the retired toggle command — the wizard sets the
header once, downstream renders honour it.

Consumed by `--strip-segment-claude-sections' below."
  (if (and tibetan-sentence--detail-for-render
           (stringp tibetan-sentence--detail-for-render)
           (string= (downcase tibetan-sentence--detail-for-render)
                    "detailed"))
      '()
    tibetan-sentence--strip-list))

(defun tibetan-sentence--strip-segment-claude-sections (content)
  "Return CONTENT with segment-level Claude sections removed.
Uses the segment-module splitter so heading boundaries are
consistent with the rest of the tool.

§5.22 (2026-05-21):  the strip list is now sourced from the defun
`tibetan-sentence--segment-claude-sections', which consults the
dynamic var `tibetan-sentence--detail-for-render' (§5.27 Phase 5
renamed from `--compressed-for-render').  See that accessor's
docstring for the two-mode behaviour."
  (if (not (and content (stringp content) (not (string-empty-p content))))
      ""
    (let* ((split (tibetan-analysis--split-level2-sections content))
           (preamble (car split))
           (strip (tibetan-sentence--segment-claude-sections))
           (sections
            (cl-remove-if
             (lambda (pair)
               (member (car pair) strip))
             (cdr split))))
      (concat (or preamble "")
              (mapconcat (lambda (p) (concat (car p) "\n" (cdr p)))
                         sections "")))))

(defun tibetan-sentence--render-auto-analysis (tibetan-text)
  "Return the body of the `* Auto-Analysis' block for TIBETAN-TEXT.

Runs the segment-level renderer
\(`tibetan-analysis-generate-content') on the concatenated
sentence text and strips segment-level Claude scaffolding.  The
result is the same parser-driven analysis the per-segment files
carry (Wylie / Particle Map / Interlinear Gloss / Verb
Classification / Word-Particle List / Grammatical Markers /
Sentence Structure / Clause Structure / Detailed Dictionary),
but computed over the whole sentence so cross-segment compounds
and clause chains surface in one place.

Returns nil when the renderer is unavailable or the text has no
Tibetan content (so the caller can emit a placeholder instead of
a misleading empty section).  The Tibetan-content check reuses
`tibetan-analysis--filter-to-tibetan-lines' — a sentence whose
only text is Latin / `#' comments / blank lines gets no
auto-analysis block at all."
  (when (and tibetan-text
             (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text)))
             (fboundp 'tibetan-analysis-generate-content)
             (fboundp 'tibetan-analysis--filter-to-tibetan-lines))
    (let ((filtered (tibetan-analysis--filter-to-tibetan-lines
                     tibetan-text)))
      (when (and filtered
                 (not (string-empty-p (string-trim filtered))))
        (condition-case _err
            (let ((content (tibetan-analysis-generate-content tibetan-text)))
              (when (and content (not (string-empty-p content)))
                ;; The full `** Sentence Structure' (now retained — see
                ;; `tibetan-sentence--strip-list') carries the per-clause
                ;; subject/object breakdown; no separate Main-Clause
                ;; summary is appended.
                (tibetan-sentence--strip-segment-claude-sections content)))
          (error nil))))))

(defconst tibetan-sentence--scaffold-sentence-only-l3-entries
  '(("Roehrich" .         "[Hand-paste the published Roehrich English here]")
    ("Class Translation" . "[Working class translation here]"))
  "Sentence-specific level-3 entries to inject into the nested
`** Provided Translations' block of a sent-NNN.org file.

Cons cells `(HEADING . PLACEHOLDER-BODY)'.  Heading order is
preserved — Roehrich (curated reference) before Class Translation
\(class-paste).

§5.24 (2026-05-22):  `Claude Context' retired from this list.
The renamed `** Concept Notes' lives at L2 in both segment and
sentence files (emitted by the segment renderer);  no L3 inject
needed.")

(defun tibetan-sentence--inject-sentence-l3-entries (buffer)
  "Inject sentence-only level-3 entries into the nested
`** Provided Translations' block inside `* Tibetan Analysis'.

For each `(HEADING . PLACEHOLDER)' in
`tibetan-sentence--scaffold-sentence-only-l3-entries' that is not
already present under the nested `** Provided Translations',
insert a `*** HEADING\\nPLACEHOLDER\\n\\n' block.  Existing
populated entries are left untouched (idempotent).

When `** Provided Translations' itself is absent (segment renderer
didn't emit it, e.g. degraded test harness), this is a no-op.

Called from the scaffold (fresh files) and from `--regenerate'
\(after relocation of preserved bodies, so already-populated
sentence-only entries don't get clobbered)."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\* Provided Translations$" nil t)
        ;; Find the end of this nested ** Provided Translations
        ;; subtree:  next ^** OR ^* OR end-of-buffer.
        (let* ((pt-body-start (progn (forward-line 1) (point)))
               (pt-end (save-excursion
                         (or (and (re-search-forward "^\\*\\{1,2\\}[^*\n]"
                                                     nil t)
                                  (line-beginning-position))
                             (point-max))))
               (subtree (buffer-substring-no-properties
                         pt-body-start pt-end)))
          (dolist (entry tibetan-sentence--scaffold-sentence-only-l3-entries)
            (let ((heading (car entry))
                  (placeholder (cdr entry)))
              (unless (string-match-p
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       subtree)
                ;; Insert at the END of the ** Provided Translations
                ;; subtree (just before the next sibling heading).
                (goto-char pt-end)
                (insert (format "*** %s\n%s\n\n" heading placeholder))
                ;; Recalculate bounds because the buffer grew.
                (setq pt-end (point))
                (setq subtree
                      (concat subtree
                              (format "*** %s\n%s\n\n" heading placeholder)))))))))))

(defun tibetan-sentence--sentence-detail-from-source (source-file)
  "Return the `:sentence-detail' string for SOURCE-FILE, or nil.
Reads via `tibetan-analysis--read-source-metadata' so the
heading is parsed by the canonical reader.  Safe when
SOURCE-FILE is nil or the metadata module isn't loaded."
  (when (and source-file
             (fboundp 'tibetan-analysis--read-source-metadata))
    (condition-case nil
        (plist-get
         (tibetan-analysis--read-source-metadata source-file)
         :sentence-detail)
      (error nil))))

(defun tibetan-sentence--scaffold (sent-num seg-nums tibetan-text wylie source-file)
  "Return the scaffold body for a new sent-NNN.org file (as string).
SENT-NUM is the sentence number, SEG-NUMS the list of contained
segment numbers, TIBETAN-TEXT the concatenated child text,
WYLIE its transliteration (may be nil — retained as a fallback
when `tibetan-analysis-generate-content' is unavailable),
SOURCE-FILE the absolute path of the source org buffer.

The scaffold emits the segment-§5.18 aligned layout (2026-05-18):

  * My Notes                          user-edited (top)
  * Working Translation               user-edited (top)
  * Tibetan Text                      concatenated child text
  * Tibetan Analysis                  was `* Auto-Analysis'
    ** Wylie / Particle Map / Interlinear …
    ** Translation                    sentence-level Claude lands here
    ** Grammar (with *** Claude Grammar / *** Particles)
    ** Verb Classification / Sentence Structure / Clause Structure /
       Detailed Dictionary / Main Clause
    ** Provided Translations          NESTED — segment shape
      *** Roehrich                    sentence-specific
      *** Class Translation           sentence-specific
      *** Claude Context              sentence-specific
      *** Claude Vocabulary           from segment renderer
      *** Claude Particles            from segment renderer
  * Footnotes                         user-edited (bottom)

Fallback:  when the segment renderer is unavailable
\(`tibetan-analysis-generate-content' missing or no Tibetan
content), the analysis parent gets a minimal `* Wylie' block
under `* Tibetan Analysis' instead of the rich segment-renderer
body.  The outer shape (My Notes / Working Translation top,
Footnotes bottom) is preserved either way.

§5.22 final (2026-05-21):  the embedded segment-renderer output
is unconditionally stripped to the in-class compressed layout
(Vocabulary + Translation + Grammar + Provided Translations
only).  Per-segment seg-NNN.org files are unaffected;  only the
sent-NNN.org embedded body is compressed.  See
`tibetan-sentence--strip-list' for the dropped sections and
their rationale."
  (let* ((source-name (and source-file
                           (file-name-nondirectory source-file)))
         (date (format-time-string "%Y-%m-%d"))
         (hash (tibetan-sentence--compute-hash tibetan-text))
         (segs-csv (mapconcat #'number-to-string seg-nums ", "))
         ;; §5.27 Phase 5:  consult the per-source
         ;; `#+TIBETAN_SENTENCE_DETAIL:' header.  When the caller has
         ;; already bound the dynamic var (e.g.  from a test or an
         ;; ad-hoc command override), preserve that;  otherwise pull
         ;; from the source file's metadata.  `--segment-claude-
         ;; sections' consults the var to decide whether to strip the
         ;; embedded segment-renderer output ("compressed", default)
         ;; or emit the full §5.21 layout ("detailed").
         (tibetan-sentence--detail-for-render
          (or tibetan-sentence--detail-for-render
              (tibetan-sentence--sentence-detail-from-source source-file))))
    (with-temp-buffer
      (insert (format "#+TITLE: Sentence %d Analysis\n" sent-num))
      (insert "#+STARTUP: showall\n")
      ;; §5.22 follow-up (2026-05-21):  HTML / PDF / LaTeX export of
      ;; the sentence file does NOT carry an auto-generated table of
      ;; contents AND does NOT prefix headings with section numbers.
      ;; The on-disk org headings already structure the document —
      ;; class-presentation cleaner without the numbered TOC overlay.
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (when source-name
        (insert (format "#+SOURCE: [[file:../%s::*Sentence %d][%s / Sentence %d]]\n"
                        source-name sent-num source-name sent-num)))
      (insert (format "#+SEGMENTS: %s\n" segs-csv))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-sentence-persist-version))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      ;; User sections at TOP (segment §5.18 ordering).
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      ;; Tibetan source text.
      (insert "* Tibetan Text\n")
      (insert tibetan-text)
      (insert "\n\n")
      ;; `* Tibetan Analysis' (renamed from `* Auto-Analysis' for
      ;; §5.18 alignment).  Body = full segment-renderer output,
      ;; including `** Translation' (placeholder — sentence-level
      ;; Claude lands here), `** Grammar' (with nested `*** Claude
      ;; Grammar' slot), `** Provided Translations' (with `*** Claude
      ;; Vocabulary' / `*** Claude Particles' placeholders).
      (let ((auto (tibetan-sentence--render-auto-analysis tibetan-text)))
        (cond
         (auto
          (insert "* Tibetan Analysis\n")
          (insert ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")
          (insert auto)
          (unless (string-suffix-p "\n" auto) (insert "\n"))
          (insert "\n"))
         (t
          (insert "* Tibetan Analysis\n")
          (insert ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")
          (insert "** Wylie\n")
          (if (and wylie (not (string-empty-p wylie)))
              (insert wylie)
            (insert "[Wylie transliteration not available]"))
          (insert "\n\n")
          ;; Degraded path: emit a `** Provided Translations'
          ;; placeholder so the injection helper has a parent block
          ;; to attach the sentence-specific level-3 entries to.
          (insert "** Provided Translations\n\n"))))
      ;; * Footnotes goes BEFORE the level-3 injection so the
      ;; injector's subtree-end detection lands the level-3 entries
      ;; INSIDE `** Provided Translations' (just before `* Footnotes')
      ;; rather than after everything else.
      (insert "* Footnotes\n\n")
      ;; Inject sentence-specific level-3 entries (*** Roehrich,
      ;; *** Class Translation, *** Claude Context) into the nested
      ;; `** Provided Translations' block.  No-op when the block is
      ;; absent.
      (tibetan-sentence--inject-sentence-l3-entries (current-buffer))
      (buffer-string))))

(defun tibetan-sentence--create-file (sent-num seg-nums tibetan-text source-file)
  "Create a new `sent-NNN.org' file for SENT-NUM, return its path."
  (let* ((filepath (tibetan-sentence--filepath sent-num))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error nil)))
         (body (tibetan-sentence--scaffold
                sent-num seg-nums tibetan-text wylie source-file)))
    (with-temp-file filepath
      (insert body))
    filepath))

;; ============================================================================
;; REGENERATE — preserves user content and translations
;; ============================================================================

(defun tibetan-sentence--read-l2-body (filepath heading)
  "Read body under `** HEADING' anywhere in FILEPATH.  Returns the
trimmed string, or nil when heading is absent / body is empty or
a placeholder."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* %s$" (regexp-quote heading)) nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (save-excursion
                      (if (re-search-forward
                           "^\\*\\{1,2\\}[^*\n]\\|^\\* " nil t)
                          (line-beginning-position)
                        (point-max))))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (unless (or (string-empty-p body)
                      (string-match-p "\\`\\[Awaiting" body)
                      (string-match-p "\\`\\[Requesting" body)
                      (string-match-p "\\`\\[Claude unavailable" body)
                      (string-match-p "\\`\\[Translation not available" body))
            body))))))

(defun tibetan-sentence--set-l3-body-in-buffer (buffer heading body)
  "Set the body under `*** HEADING' in BUFFER to BODY (trimmed).
Heading must already exist in the buffer."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\*\\* %s$" (regexp-quote heading)) nil t)
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward
                          "^\\*\\{1,3\\}[^*\n]\\|^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (delete-region start end)
          (goto-char start)
          (insert (string-trim body) "\n\n"))))))

(defun tibetan-sentence--set-l2-body-in-buffer (buffer heading body)
  "Set the body under `** HEADING' in BUFFER to BODY (trimmed)."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* %s$" (regexp-quote heading)) nil t)
        (forward-line 1)
        (let ((start (point))
              (end (save-excursion
                     (if (re-search-forward
                          "^\\*\\{1,2\\}[^*\n]\\|^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (delete-region start end)
          (goto-char start)
          (insert (string-trim body) "\n\n"))))))

(defun tibetan-sentence--set-top-level-body-in-buffer (buffer heading body)
  "Replace the FULL top-level `* HEADING' section in BUFFER with BODY.
BODY is the verbatim content captured by
`tibetan-sentence--get-user-sections' (heading line through next
top-level heading).  Idempotent — only replaces an existing section
in place;  callers ensure the heading is present first."
  (with-current-buffer buffer
    (save-excursion
      (let ((bounds (tibetan-sentence--find-section-bounds buffer heading)))
        (when bounds
          (delete-region (car bounds) (cdr bounds))
          (goto-char (car bounds))
          (insert body))))))

(defun tibetan-sentence--regenerate (filepath sent-num seg-nums tibetan-text)
  "Regenerate FILEPATH in the new segment-§5.18-aligned layout.

PRESERVE phase:  reads all bodies worth keeping:
  - User sections (My Notes, Working Translation, Footnotes).
  - Reference bodies (Roehrich, Class Translation).
  - Sentence-level Claude bodies (Claude Translation @ level-3
    legacy OR `** Translation' @ level-2 new, Claude Grammar,
    Claude Context).

REBUILD phase:  scaffolds a fresh file via
`tibetan-sentence--scaffold' in the NEW layout (My Notes /
Working Translation top, `* Tibetan Analysis' parent, nested
`** Provided Translations', Footnotes bottom).

RESTORE phase:  injects each preserved body into its slot in the
new layout:
  - Legacy `*** Claude Translation' body → `** Translation'
    \(level-2 promotion, matches segment §5.18 layout).
  - Roehrich / Class Translation / Claude Context → level-3
    inside nested `** Provided Translations'.
  - Claude Grammar → level-3 under `** Grammar'.
  - My Notes / Working Translation / Footnotes → top-level
    sections at their new positions (top / top / bottom).

Idempotent — re-running on an already-migrated file produces
identical output (modulo `#+LAST_ANALYZED:' timestamp).

Updates `#+SEGMENTS:' / `#+TIBETAN_HASH:' / `#+LAST_ANALYZED:'."
  ;; ============================================================================
  ;; PRESERVE phase — read everything we need to keep BEFORE rebuilding.
  ;; ============================================================================
  (let* ((user-sections (tibetan-sentence--get-user-sections filepath))
         (trans  (tibetan-sentence--read-translation-bodies filepath))
         ;; Claude Translation:  try level-2 `** Translation' (new
         ;; aligned layout) first;  fall back to level-3 `*** Claude
         ;; Translation' (legacy sentence-only layout).
         (claude-trans-body
          (or (tibetan-sentence--read-l2-body filepath "Translation")
              (tibetan-sentence--read-third-level-body
               filepath "Claude Translation")))
         (claude-grammar-body
          (tibetan-sentence--read-third-level-body filepath "Claude Grammar"))
         ;; §5.24 (2026-05-22):  rename `Claude Context' → `Concept
         ;; Notes' + promote to L2.  Reader checks legacy L3 names
         ;; (Claude Context, Concept Notes-at-L3 from interim
         ;; sentence layout) and current L2 `** Concept Notes' —
         ;; first non-nil wins, so already-migrated files keep their
         ;; L2 body, legacy files migrate on this regenerate pass.
         (concept-notes-body
          (or (tibetan-sentence--read-l2-body filepath "Concept Notes")
              (tibetan-sentence--read-third-level-body
               filepath "Concept Notes")
              (tibetan-sentence--read-third-level-body
               filepath "Claude Context")))
         (claude-vocabulary-body
          (tibetan-sentence--read-third-level-body filepath "Claude Vocabulary"))
         (claude-particles-body
          (tibetan-sentence--read-third-level-body filepath "Claude Particles"))
         ;; Parallel-Sanskrit top-level sections (Sanskrit Text /
         ;; Sanskrit Analysis / Combined Analysis / DM Sanskrit /
         ;; realign).  Captured verbatim so regenerate-without-refire
         ;; cannot silently destroy upstream Claude / DM content — the
         ;; §5.26 data-loss class on the sentence path.  The fresh
         ;; scaffold does not emit them (they are written by the fire
         ;; pipeline, not the scaffold), so they are re-APPENDED below.
         (parallel-sections
          (tibetan-sentence--read-parallel-top-level-sections filepath))
         (source-file (tibetan-sentence--source-file-from-analysis filepath))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error nil)))
         ;; ========================================================
         ;; REBUILD phase — generate the new-layout scaffold body.
         ;; ========================================================
         (new-body (tibetan-sentence--scaffold
                    sent-num seg-nums tibetan-text wylie source-file)))

    ;; Close any open buffer on this file so the write doesn't fight a
    ;; stale visit.
    (let ((open (get-file-buffer filepath)))
      (when open
        (with-current-buffer open (set-buffer-modified-p nil))
        (kill-buffer open)))

    ;; Write the fresh scaffold to disk.
    (with-temp-file filepath
      (insert new-body))

    ;; ========================================================
    ;; RESTORE phase — inject preserved content into the new file.
    ;; ========================================================
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        ;; Run the §5.18 Phase-1.3 migration in-place:  rename any
        ;; lingering `** Claude Translation' from the scaffold's
        ;; embedded segment-renderer output → `** Translation'.  The
        ;; layout detector (`--claude-segment-layout-p') recognises
        ;; the new aligned sentence shape (* Tibetan Analysis parent)
        ;; as segment-layout for migration purposes.
        (when (fboundp 'tibetan-analysis--migrate-legacy-claude-headings)
          (tibetan-analysis--migrate-legacy-claude-headings buf))
        ;; Level-2 ** Translation (claimed primary slot for the
        ;; sentence-level Claude translation, matching segment).
        (when claude-trans-body
          (tibetan-sentence--set-l2-body-in-buffer
           buf "Translation" claude-trans-body))
        ;; Level-3 *** Claude Grammar (nested under ** Grammar).
        (when claude-grammar-body
          (tibetan-sentence--set-l3-body-in-buffer
           buf "Claude Grammar" claude-grammar-body))
        ;; Sentence-specific level-3 entries (nested under
        ;; ** Provided Translations).
        (when (plist-get trans :roehrich)
          (tibetan-sentence--set-l3-body-in-buffer
           buf "Roehrich" (plist-get trans :roehrich)))
        (when (plist-get trans :class)
          (tibetan-sentence--set-l3-body-in-buffer
           buf "Class Translation" (plist-get trans :class)))
        ;; §5.24 (2026-05-22):  write preserved Concept Notes body
        ;; into the new L2 `** Concept Notes' slot (segment-renderer
        ;; emits that placeholder, so the slot already exists in the
        ;; new scaffold).
        (when concept-notes-body
          (tibetan-sentence--set-l2-body-in-buffer
           buf "Concept Notes" concept-notes-body))
        (when claude-vocabulary-body
          (tibetan-sentence--set-l3-body-in-buffer
           buf "Claude Vocabulary" claude-vocabulary-body))
        (when claude-particles-body
          (tibetan-sentence--set-l3-body-in-buffer
           buf "Claude Particles" claude-particles-body))
        ;; Top-level user sections — captured verbatim from the old
        ;; file (heading line through next ^* heading), re-inserted
        ;; in place of the scaffold's empty placeholder.
        (dolist (section user-sections)
          (tibetan-sentence--set-top-level-body-in-buffer
           buf (car section) (cdr section)))
        ;; Re-append the parallel-Sanskrit top-level sections captured
        ;; above (the scaffold doesn't emit them).  Skip any that the
        ;; rebuilt file somehow already carries, so the restore stays
        ;; idempotent.
        (dolist (sec parallel-sections)
          (unless (tibetan-sentence--find-section-bounds buf (car sec))
            (tibetan-sentence--append-top-level-section buf (cdr sec))))
        ;; Export safety:  strip Interlinear→DD dangling term-* links
        ;; (mirrors `tibetan-analysis-regenerate-auto' for segment
        ;; files;  the issue is the same — Interlinear emits link
        ;; targets whose `<<term-X>>' anchors may not exist in DD
        ;; if the divergence pre-dates the strict MWU detector).
        (when (fboundp 'tibetan-analysis--strip-dangling-term-links-in-buffer)
          (tibetan-analysis--strip-dangling-term-links-in-buffer))
        (save-buffer))
      (message "Re-analyzed sentence %d. User content preserved." sent-num))))

;; ============================================================================
;; DISCOURSE-LEVEL CLAUDE SYSTEM PROMPT
;; ============================================================================

(defvar tibetan-sentence--claude-system-prompt
  "You are a specialist in Classical Tibetan (chos skad) translation \
and philology, acting as a teaching assistant for a graduate classroom.

The passage below is one **sentence** — a discourse unit composed of \
one or more clauses (segments).  Your job is to analyse it at the \
sentence/discourse level, NOT word-by-word: cross-clause connectives, \
anaphora, narrative arc, and how the sentence sits in the surrounding \
text.

Produce THREE sections, separated by the exact markdown headings \
shown below, in this order and nothing else:

## Translation
A single, fluent English rendering of the whole sentence.
- Render the sentence as a coherent English sentence (or a small set \
of tightly linked clauses), not as a sequence of literal segments.
- Preserve technical Buddhist terminology (use Sanskrit where \
standard, e.g. dharma, bodhisattva, samādhi), with English gloss in \
parentheses on first occurrence only.
- Honorific forms (zhu, gsol, mdzad, etc.) should be reflected in \
the register.
- No commentary in this section.

## Grammar
Explain the **discourse-level** grammar pedagogically for readers \
learning Classical Tibetan.  Focus on:
- The clause chain: which clauses are subordinate (and via which \
converb — ablative ནས, simultaneous ཅིང/ཞིང/ཤིང, coordinative \
ཏེ/སྟེ/དེ, conditional ན, concessive ཀྱང/ཡང/འང, …) vs. the main \
clause that anchors the sentence.
- Anaphora and reference tracking across clauses (zero-anaphora is \
the Tibetan default; identify the implicit subjects/objects).
- Topic / focus structure marked by ནི, ཡང, etc.
- The sentence-final verb morphology and what tense / aspect / mood \
it imposes on the whole sentence.
Reference the actual Tibetan forms in parentheses.  Do NOT \
re-analyse individual particles in detail — that work is done at the \
segment level and you will be given the per-segment parser output as \
ground truth in the user prompt.  Treat that grounding as \
authoritative for case and verb tagging; narrate it pedagogically, \
flag disagreements rather than silently overruling.

## Concept Notes
Identify any notable technical concepts in THIS sentence and give \
each a brief encyclopedia-style note for a graduate-classroom \
reader:  Buddhist doctrine and category-lists, doxographical \
school / tradition references, lineage and person names, place \
names, Sanskrit-derived technical terms.

For each concept (0–3 entries per sentence is the typical range):
- **Tibetan term (Skt. / Pali equivalent if relevant) — short gloss**
  1–2 sentence explanation drawn from canonical or scholarly \
sources.  Note the doctrinal-context (Madhyamaka, Yogācāra, lam-rim, \
bKa'-gdams-pa, etc.) when relevant.  Cite primary sources only when \
genuinely illuminating;  avoid bibliographic padding.

If the sentence is purely narrative / mechanical and contains no \
notable concepts, output EXACTLY (no other text in this section):
  [No notable concepts in this passage]

When your explanation references a SUB-CONCEPT that itself \
warrants a gloss (e.g. \"one of the twelve dhutaguṇas\", \"in \
the mahāyāna-saṃgraha framework\"), expand it with a 1-sentence \
parenthetical gloss inline — so the reader gets enough context \
without needing an external lookup.  One level of nesting is \
enough;  don't recurse further.

Aim for sentence-level aggregation — don't repeat what the per-\
segment grounding (supplied in the user prompt) already covers at \
finer granularity.  Be terse;  the whole section should fit in \
~180 words including any nested sub-concept glosses.

Use only these three headings.  No preamble, no closing remarks.

Genre, period and context hints (if any) are supplied below by the \
source file via `#+TIBETAN_CLAUDE_CONTEXT:' headers.  Do NOT assume \
a specific genre unless such context is given."
  "System prompt for sentence-level (discourse) Claude analysis.
Mirrors the three-section schema of the segment-level prompt so the
existing parser (`tibetan-analysis--parse-claude-sections') can read
the response, but reframes the task at the sentence/discourse level
and tells Claude to defer to the per-segment parser output for
particle-level tagging.")

;; ============================================================================
;; PROMPT BUILDER — pulls per-segment grounding from CHILD seg-NNN.org
;; ============================================================================

(defun tibetan-sentence--child-seg-filepath (seg-num &optional folder)
  "Return absolute path to `seg-NNN.org' for SEG-NUM, or nil."
  (let ((folder (or folder (tibetan-sentence--get-folder))))
    (when folder
      (let ((p (expand-file-name (format "seg-%03d.org" seg-num) folder)))
        (when (file-exists-p p) p)))))

(defun tibetan-sentence--collect-children-grounding (seg-nums &optional folder)
  "Collect parser-grounding text from the seg-NNN.org files of SEG-NUMS.
Returns a single concatenated string suitable for embedding in the
Claude user prompt, or nil when no child files exist or none have
parser content."
  (when (and seg-nums (fboundp 'tibetan-analysis--read-analysis-parser-sections)
             (fboundp 'tibetan-analysis--format-parser-grounding))
    (let ((blocks '()))
      (dolist (seg-num seg-nums)
        (let* ((path (tibetan-sentence--child-seg-filepath seg-num folder))
               (sections (and path
                              (tibetan-analysis--read-analysis-parser-sections
                               path)))
               (formatted (and sections
                               (tibetan-analysis--format-parser-grounding
                                sections))))
          (when (and formatted (not (string-empty-p formatted)))
            (push (format "=== Segment %d ===%s" seg-num formatted)
                  blocks))))
      (when blocks
        (concat
         "\n\nPer-segment parser output (clause/case/verb tagging done by "
         "the tool — treat as ground truth, narrate pedagogically rather "
         "than re-tagging from scratch):\n\n"
         (mapconcat #'identity (nreverse blocks) "\n\n"))))))

(defun tibetan-sentence--build-claude-prompts
    (tibetan-text seg-nums source-file &optional folder)
  "Build (SYSTEM . USER) Claude prompts for sentence-level analysis.
TIBETAN-TEXT is the concatenated sentence text; SEG-NUMS the list of
child segment numbers used to look up their per-segment analysis
files for parser grounding; SOURCE-FILE the source org buffer path
(used for genre/author metadata via the same helper as
`tibetan-analysis-persist'); FOLDER the analysis folder."
  (let* ((meta   (and source-file
                      (fboundp 'tibetan-analysis--read-source-metadata)
                      (tibetan-analysis--read-source-metadata source-file)))
         (title  (plist-get meta :title))
         (work   (plist-get meta :work))
         (author (plist-get meta :author))
         (ctx    (plist-get meta :claude-context))
         (wylie  (condition-case nil
                     (when (fboundp 'tibetan-to-wylie-fixed)
                       (tibetan-to-wylie-fixed tibetan-text))
                   (error nil)))
         (src-block
          (let (parts)
            (when work   (push (format "Work: %s" work) parts))
            (when (and author (not (and work (string= work author))))
              (push (format "Author: %s" author) parts))
            (when (and title (not work)) (push (format "Title: %s" title) parts))
            (when ctx
              (push "Context from source file:" parts)
              (dolist (line ctx)
                (push (format "  - %s" line) parts)))
            (when parts
              (concat "\n\nSource metadata for this passage:\n"
                      (mapconcat #'identity (nreverse parts) "\n")))))
         (system (concat tibetan-sentence--claude-system-prompt
                         (or src-block "")))
         (grounding-block
          (tibetan-sentence--collect-children-grounding seg-nums folder))
         ;; §5.25 (2026-05-24):  inject thesaurus zettel references
         ;; for any term in the sentence that has a curated zettel.
         ;; Claude cites `[[id:ZID][zettel ↗]]' inline in Concept
         ;; Notes;  the post-process writer is a safety net for
         ;; zettels Claude missed.
         (zettel-block
          (and (fboundp 'tibetan-analysis--format-zettel-references-block)
               (fboundp 'tibetan-analysis--collect-zettel-references)
               (tibetan-analysis--format-zettel-references-block
                (tibetan-analysis--collect-zettel-references tibetan-text))))
         (segs-csv (mapconcat #'number-to-string seg-nums ", "))
         (user (concat "Classical Tibetan sentence "
                       (format "(spans segments: %s):\n\n" segs-csv)
                       tibetan-text
                       (if wylie (format "\n\nWylie: %s" wylie) "")
                       (or grounding-block "")
                       (or zettel-block "")
                       "\n\nProduce the three sections now.")))
    (cons system user)))

;; ============================================================================
;; CLAUDE REQUEST (async via gptel)
;; ============================================================================

(defun tibetan-sentence--source-file-from-analysis (analysis-file)
  "Return absolute source file referenced by sent-NNN.org ANALYSIS-FILE."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^#\\+SOURCE:[ \t]*\\[\\[file:\\([^]:]+\\)" nil t)
            (let ((rel (match-string 1)))
              (expand-file-name rel (file-name-directory analysis-file)))))
      (error nil))))

(defun tibetan-sentence--seg-nums-from-file (filepath)
  "Read the `#+SEGMENTS:' header value from FILEPATH and return a list of ints."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+SEGMENTS:[ \t]*\\(.*\\)$" nil t)
        (let ((csv (string-trim (match-string 1))))
          (when (and csv (not (string-empty-p csv)))
            (mapcar #'string-to-number
                    (split-string csv "[ ,\t]+" t))))))))

(defun tibetan-sentence--request-claude
    (tibetan-text seg-nums analysis-file &optional source-file folder)
  "Async-request a Claude sentence-level analysis of TIBETAN-TEXT.
On callback, parses the response and writes the three Claude
sections into ANALYSIS-FILE.  Reuses
`tibetan-analysis--insert-claude-sections' so the writer behaviour
stays identical to the segment-level flow.

Routed through `tibetan-claude-queue' so concurrent sentence-level
requests share the same throttle / retry budget as segment-level
requests, and a placeholder is written into the *** Claude
Translation section if retries are exhausted."
  (require 'tibetan-claude-queue)
  (let ((label (and analysis-file
                    (file-name-nondirectory analysis-file))))
    (tibetan-claude-queue-submit
     (lambda (done)
       (condition-case err
           (progn
             (unless (and (featurep 'gptel) (fboundp 'gptel-request))
               (error "gptel not loaded"))
             (when (fboundp 'tibetan-analysis--ensure-gptel-ready)
               (tibetan-analysis--ensure-gptel-ready))
             (let* ((src (or source-file
                             (tibetan-sentence--source-file-from-analysis
                              analysis-file)))
                    (prompts (tibetan-sentence--build-claude-prompts
                              tibetan-text seg-nums src folder))
                    (system-prompt (car prompts))
                    (user-prompt   (cdr prompts))
                    ;; Cache the system prompt (identical across every
                    ;; sent-*.org in a document) — see equivalent binding
                    ;; in `tibetan-analysis--request-claude-translation'.
                    ;; 5-min TTL; per-batch savings compound from the
                    ;; second request onward.
                    (gptel-cache '(system)))
               (gptel-request
                user-prompt
                :system system-prompt
                :callback
                (lambda (response info)
                  (cond
                   ((and response (stringp response)
                         (not (string-empty-p response)))
                    (when (fboundp 'tibetan-analysis--insert-claude-sections)
                      (condition-case e
                          (tibetan-analysis--insert-claude-sections
                           response analysis-file)
                        (error
                         (message "Sentence Claude insert failed for %s: %s"
                                  (or label "<file>")
                                  (error-message-string e)))))
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
                                                      "no response")))))))) ))
         (error
          (funcall done (list :status 'error
                              :error (error-message-string err))))))
     :label label
     :on-fail
     (lambda (status)
       (let* ((kind (plist-get status :status))
              (msg (cond
                    ((eq kind 'rate-limited)
                     "[Claude request failed: rate-limited (HTTP 429) after retries — re-run C-c s R later]")
                    (t (format "[Claude request failed: %s — re-run C-c s R later]"
                               (or (plist-get status :error) "unknown"))))))
         (when (fboundp 'tibetan-analysis--write-claude-failure-stub)
           (tibetan-analysis--write-claude-failure-stub
            analysis-file msg)))))))

;; ============================================================================
;; PUBLIC COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-sentence-open-analysis ()
  "Open or create analysis for the sentence at point in a side window.
Works from a `*** Sentence N' heading or any `**** Segment M' (or
`*** Segment M' in the fresh-prep layout) inside it.  When an
analysis file already exists, warn if its stored hash no longer
matches the current concatenated child text (i.e. the source has
changed)."
  (interactive)
  (let* ((data (tibetan-sentence--collect-current-sentence)))
    (unless data
      (user-error "Not in a sentence (point is not under any *** Sentence heading)"))
    (let* ((sent-num (plist-get data :sent-num))
           (seg-nums (plist-get data :seg-nums))
           (tib-text (plist-get data :tibetan-text))
           (source-file (buffer-file-name))
           (filepath (tibetan-sentence--filepath sent-num))
           (exists (and filepath (file-exists-p filepath))))
      (unless filepath
        (error "Could not determine sentence analysis filepath; \
source buffer must visit a file"))
      (cond
       (exists
        (unless (tibetan-sentence--check-sync filepath tib-text)
          (message "WARNING: Sentence %d source text has changed since last analysis"
                   sent-num))
        (let ((buf (find-file-noselect filepath)))
          (with-current-buffer buf
            (when (fboundp 'tibetan-analysis-setup-faces)
              (tibetan-analysis-setup-faces))
            ;; Land at the top so the reader sees `* Tibetan Text'
            ;; first — `save-place-mode' or the async-Claude-insert
            ;; callback would otherwise leave the cursor near the
            ;; bottom of the file.
            (goto-char (point-min)))
          (display-buffer-in-side-window
           buf '((side . right) (window-width . 0.5)))))
       (t
        (let ((newpath (tibetan-sentence--create-file
                        sent-num seg-nums tib-text source-file)))
          (message "Created sentence analysis: %s" newpath)
          (let ((buf (find-file-noselect newpath)))
            (with-current-buffer buf
              (when (fboundp 'tibetan-analysis-setup-faces)
                (tibetan-analysis-setup-faces))
              (goto-char (point-min)))
            (display-buffer-in-side-window
             buf '((side . right) (window-width . 0.5))))
          (condition-case err
              (tibetan-sentence--request-claude
               tib-text seg-nums newpath source-file)
            (error (message "Sentence Claude skipped: %s"
                            (error-message-string err))))
          ;; Sentence-level wiring of two-language-parallel-analysis
          ;; (2026-04-30): in parallel mode, also fire Sanskrit +
          ;; Combined for the new sentence file.  No-op when the
          ;; sentence's child segments lack real Sanskrit content.
          (when (and (fboundp 'tibetan-sanskrit-parallel-text-for-sentence)
                     (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
            (let ((skt-plist
                   (condition-case nil
                       (tibetan-sanskrit-parallel-text-for-sentence
                        source-file seg-nums)
                     (error nil))))
              (when skt-plist
                (condition-case e2
                    (tibetan-analysis--fire-parallel-claude-with-plist
                     tib-text skt-plist source-file newpath)
                  (error (message
                          "Sentence Sanskrit/Combined fire skipped: %s"
                          (error-message-string e2)))))))))))))

;;;###autoload
(defun tibetan-sentence-reanalyze ()
  "Re-analyze the sentence at point.
Regenerates Tibetan/Wylie/SEGMENTS/HASH; preserves My Notes,
Working Translation, Footnotes, Roehrich, Class Translation, and
the three Claude sections.  Re-issues the Claude request only when
called with a prefix argument."
  (interactive)
  (let ((data (tibetan-sentence--collect-current-sentence)))
    (unless data
      (user-error "Not in a sentence"))
    (let* ((sent-num (plist-get data :sent-num))
           (seg-nums (plist-get data :seg-nums))
           (tib-text (plist-get data :tibetan-text))
           (source-file (buffer-file-name))
           (filepath (tibetan-sentence--filepath sent-num)))
      (unless (file-exists-p filepath)
        (user-error
         "No sentence analysis file exists yet — use C-c u S first"))
      (when (yes-or-no-p
             (format "Re-analyze sentence %d (user content preserved)? "
                     sent-num))
        (tibetan-sentence--regenerate filepath sent-num seg-nums tib-text)
        ;; Refresh open buffer.
        (let ((buf (get-file-buffer filepath)))
          (when buf
            (with-current-buffer buf
              (revert-buffer t t))))
        (when current-prefix-arg
          (condition-case err
              (tibetan-sentence--request-claude
               tib-text seg-nums filepath source-file)
            (error (message "Sentence Claude skipped: %s"
                            (error-message-string err))))
          ;; Sentence-level wiring of two-language-parallel-analysis
          ;; (2026-04-30): also fire Sanskrit + Combined when in
          ;; parallel mode AND the sentence aggregates real (non-
          ;; placeholder) Sanskrit from at least one child segment.
          (when (and (fboundp 'tibetan-sanskrit-parallel-text-for-sentence)
                     (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
            (let ((skt-plist
                   (condition-case nil
                       (tibetan-sanskrit-parallel-text-for-sentence
                        source-file seg-nums)
                     (error nil))))
              (when skt-plist
                (condition-case e2
                    (tibetan-analysis--fire-parallel-claude-with-plist
                     tib-text skt-plist source-file filepath)
                  (error (message
                          "Sentence Sanskrit/Combined fire skipped: %s"
                          (error-message-string e2))))))))))))

(cl-defun tibetan-sentence-reanalyze-file
    (filepath &key source-file re-request-claude dry-run)
  "Headless single-file re-analysis of a sent-NNN.org FILEPATH.
Tibetan text is freshly derived from SOURCE-FILE (or from the
file's `#+SOURCE:' link if not given) by re-scanning the source
buffer for the sentence number encoded in the filename.

When RE-REQUEST-CLAUDE is non-nil, a fresh Claude request is
dispatched after regeneration.  With DRY-RUN, no files are written.

Returns plist:
  (:file F :sent-id ID :ok BOOL :error STR :seg-nums (...))."
  (let* ((sent-id (tibetan-sentence--sent-id-from-filename filepath))
         (src (or source-file
                  (tibetan-sentence--source-file-from-analysis filepath)))
         (data (when (and sent-id src (file-readable-p src))
                 (with-temp-buffer
                   (insert-file-contents src)
                   (org-mode)
                   (tibetan-sentence--collect-from-source-buffer sent-id)))))
    (cond
     ((null sent-id)
      `(:file ,filepath :ok nil
              :error "Could not extract sent-id from filename"))
     ((null src)
      `(:file ,filepath :sent-id ,sent-id :ok nil
              :error "Could not resolve source file"))
     ((null data)
      `(:file ,filepath :sent-id ,sent-id :ok nil
              :error ,(format "Sentence %d not found in source" sent-id)))
     (dry-run
      `(:file ,filepath :sent-id ,sent-id :ok t :dry-run t
              :seg-nums ,(plist-get data :seg-nums)))
     (t
      (condition-case err
          (let ((seg-nums (plist-get data :seg-nums))
                (tib-text (plist-get data :tibetan-text)))
            (tibetan-sentence--regenerate filepath sent-id seg-nums tib-text)
            ;; §5.22 follow-up (2026-05-21):  honour RE-REQUEST-CLAUDE
            ;; `:missing-only' here too — skip the Claude/parallel-mode
            ;; fire when the sentence file already has populated
            ;; Translation/Vocabulary slots.  See
            ;; `tibetan-analysis--should-fire-claude-p'.
            (let ((fire-p (tibetan-analysis--should-fire-claude-p
                           re-request-claude filepath)))
              (when fire-p
                (condition-case e2
                    (tibetan-sentence--request-claude
                     tib-text seg-nums filepath src)
                  (error (message "Sentence Claude re-request failed for %s: %s"
                                  (file-name-nondirectory filepath)
                                  (error-message-string e2)))))
              ;; Sentence-level wiring of two-language-parallel-
              ;; analysis (2026-04-30):  in parallel mode, also fire
              ;; the sentence-level Sanskrit + (chained) Combined
              ;; Claude calls.  Aggregates child-segment Sanskrit via
              ;; `tibetan-sanskrit-parallel-text-for-sentence' (skips
              ;; placeholders); no-op when no child has real Sanskrit
              ;; or the source isn't parallel-mode.
              (when (and fire-p
                         (fboundp 'tibetan-sanskrit-parallel-text-for-sentence)
                         (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
                (let ((skt-plist
                       (condition-case nil
                           (tibetan-sanskrit-parallel-text-for-sentence
                            src seg-nums)
                         (error nil))))
                  (when skt-plist
                    (condition-case e3
                        (tibetan-analysis--fire-parallel-claude-with-plist
                         tib-text skt-plist src filepath)
                      (error (message
                              "Sentence Sanskrit/Combined fire failed for %s: %s"
                              (file-name-nondirectory filepath)
                              (error-message-string e3))))))))
            `(:file ,filepath :sent-id ,sent-id :ok t
                    :seg-nums ,seg-nums))
        (error
         `(:file ,filepath :sent-id ,sent-id :ok nil
                 :error ,(error-message-string err))))))))

(defun tibetan-sentence--folder-sentence-files (folder)
  "Return sent-NNN*.org files in FOLDER, sorted by sentence id."
  (let* ((all (and (file-directory-p folder)
                   (directory-files folder t "\\`sent-[0-9]+.*\\.org\\'")))
         (ordered
          (sort (copy-sequence (or all '()))
                (lambda (a b)
                  (< (or (tibetan-sentence--sent-id-from-filename a) 0)
                     (or (tibetan-sentence--sent-id-from-filename b) 0))))))
    ordered))

;;;###autoload
(cl-defun tibetan-sentence-batch-reanalyze
    (&key folder source-file re-request-claude dry-run)
  "Re-run analysis on every `sent-NNN*.org' file in FOLDER.

FOLDER defaults to the analysis folder of the current buffer.
SOURCE-FILE defaults to the current buffer's file.  With
RE-REQUEST-CLAUDE non-nil, a fresh Claude request is dispatched
per file.  With DRY-RUN non-nil, nothing is written.

Returns plist:
  (:folder F :total N :ok N-ok :failed N-bad :results RESULTS)."
  (interactive
   (list :folder (let ((d (or (and (buffer-file-name)
                                   (tibetan-sentence--get-folder))
                              default-directory)))
                   (read-directory-name "Analysis folder: " d d t))
         :source-file (buffer-file-name)
         :re-request-claude
         ;; §5.22 follow-up (2026-05-21):  three-way prompt mirroring
         ;; the segment batch.  Default `:missing-only' skips files
         ;; already carrying populated Translation/Vocabulary;  no
         ;; wasted Claude calls on bulk layout-only reanalyses.
         (let ((c (read-char-choice
                   "Claude:  [m] missing-only (skip populated)  [a] always re-fire  [n] never  ? "
                   '(?m ?a ?n))))
           (cond ((eq c ?a) t)
                 ((eq c ?n) nil)
                 (t         :missing-only)))
         :dry-run nil))
  (let* ((folder (or folder
                     (and (buffer-file-name)
                          (tibetan-sentence--get-folder))
                     default-directory))
         (files (tibetan-sentence--folder-sentence-files folder))
         (results '())
         (n (length files))
         (i 0)
         (ok 0))
    (unless files
      (user-error "No sentence analysis files (sent-NNN*.org) in %s" folder))
    (dolist (f files)
      (cl-incf i)
      (message "[%d/%d] %s %s"
               i n (if dry-run "dry-run" "reanalyzing")
               (file-name-nondirectory f))
      (let ((r (tibetan-sentence-reanalyze-file
                f
                :source-file source-file
                :re-request-claude re-request-claude
                :dry-run dry-run)))
        (push r results)
        (when (plist-get r :ok) (cl-incf ok))))
    (let ((summary `(:folder ,folder
                     :total ,n
                     :ok ,ok
                     :failed ,(- n ok)
                     :dry-run ,(and dry-run t)
                     :results ,(nreverse results))))
      (message "Sentence batch reanalysis: %d/%d ok (%d failed)%s"
               ok n (- n ok) (if dry-run " — dry run" ""))
      summary)))

;; ============================================================================
;; ARCHIVE + BATCH-CREATE — used when re-segmenting a source file
;; ============================================================================

(defun tibetan-sentence--analysis-folder ()
  "Return the analysis folder path for the current source buffer.
Falls back to `<cwd>/analysis/' when not in a source buffer."
  (let ((base (or (and buffer-file-name
                       (file-name-directory buffer-file-name))
                  default-directory)))
    (file-name-as-directory (expand-file-name "analysis" base))))

;;;###autoload
(defun tibetan-sentence-archive-analysis-folder (&optional folder)
  "Move every `sent-NNN*.org' in FOLDER into a timestamped archive subdir.

FOLDER defaults to the analysis folder of the current source
buffer.  Creates `<folder>/archive/YYYY-MM-DD-HHMMSS/' and moves
all `sent-*.org' files into it.  `seg-*.org' and any other files
are left untouched.  Returns the archive directory path.

Intended use: before re-segmenting a source file whose sentence
numbering is about to change.  Archiving preserves the old
analysis work so the user can compare or selectively restore
content (Roehrich pastes, Class translations, Claude bodies,
My Notes, Working Translation, Footnotes) into the freshly-
generated sent files afterwards."
  (interactive
   (list (if current-prefix-arg
             (read-directory-name "Analysis folder: ")
           nil)))
  (let* ((folder (or folder (tibetan-sentence--analysis-folder)))
         (sent-files (when (file-directory-p folder)
                       (directory-files folder t "\\`sent-[0-9]+.*\\.org\\'")))
         (stamp (format-time-string "%Y-%m-%d-%H%M%S"))
         (archive-dir (expand-file-name
                       (concat "archive/" stamp "/")
                       folder)))
    (cond
     ((not sent-files)
      (message "No sent-*.org files in %s — nothing to archive." folder)
      nil)
     ((not (yes-or-no-p
            (format "Archive %d sent-*.org file%s from %s into archive/%s/? "
                    (length sent-files)
                    (if (= (length sent-files) 1) "" "s")
                    folder stamp)))
      (message "Archive cancelled.")
      nil)
     (t
      (make-directory archive-dir t)
      (let ((moved 0))
        (dolist (f sent-files)
          (rename-file f (expand-file-name
                          (file-name-nondirectory f) archive-dir))
          (setq moved (1+ moved)))
        (message "Archived %d sent-*.org file%s into %s"
                 moved (if (= moved 1) "" "s") archive-dir)
        archive-dir)))))

;;;###autoload
(defun tibetan-sentence-create-all ()
  "Create a fresh `sent-NNN.org' analysis file for every `*** Sentence N'
heading in the current source buffer.

Iterates top-to-bottom, calling the same scaffold + create path
used by `C-c s A'.  Any `sent-NNN.org' that already exists in
the analysis folder is skipped (re-creation would clobber a file
the user may have hand-edited since last segment change).  To
regenerate from scratch, archive first with
`tibetan-sentence-archive-analysis-folder'.

Reports created / skipped counts on completion."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer has no source file"))
  (let ((source-file buffer-file-name)
        (created 0) (skipped 0) (failed 0)
        (sentences '()))
    ;; First pass: find every `*** Sentence N' heading and the set
    ;; of child segments in its span.
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^\\*\\*\\* Sentence \\([0-9]+\\)\\b"
                                nil t)
        (let* ((sent-num (string-to-number (match-string 1)))
               (start (match-end 0))
               (end (save-excursion
                      (or (and (re-search-forward
                                "^\\*\\*\\* Sentence [0-9]+\\b" nil t)
                               (match-beginning 0))
                          (point-max))))
               (seg-nums '())
               (texts '()))
          (save-excursion
            (goto-char start)
            (while (re-search-forward
                    "^\\*\\*\\*\\* Segment \\([0-9]+\\)\\b" end t)
              (let* ((n (string-to-number (match-string 1)))
                     (body-start (progn (forward-line 1) (point)))
                     ;; Stop at the next Org heading (any level) so
                     ;; sibling subsections like `**** Working Translation'
                     ;; don't leak into the segment's Tibetan body.
                     (body-end
                      (save-excursion
                        (or (and (re-search-forward "^\\*+ " end t)
                                 (match-beginning 0))
                            end))))
                (push n seg-nums)
                (push (string-trim
                       (buffer-substring-no-properties
                        body-start body-end))
                      texts))))
          (push (list :sent-num sent-num
                      :seg-nums (nreverse seg-nums)
                      :tibetan (string-trim
                                (mapconcat #'identity (nreverse texts)
                                           "\n")))
                sentences))))
    (setq sentences (nreverse sentences))
    (unless sentences
      (user-error "No `*** Sentence N' headings in the current buffer — run `C-c s S' first"))
    ;; Second pass: create each sent-NNN.org.
    (let ((newly-created '()))
      (dolist (s sentences)
        (let* ((sent-num (plist-get s :sent-num))
               (seg-nums (plist-get s :seg-nums))
               (tibetan  (plist-get s :tibetan))
               (filepath (tibetan-sentence--filepath sent-num)))
          (cond
           ((file-exists-p filepath)
            (setq skipped (1+ skipped)))
           (t
            (condition-case _err
                (progn
                  (tibetan-sentence--create-file
                   sent-num seg-nums tibetan source-file)
                  (setq created (1+ created))
                  ;; Remember what we wrote so Claude can be fired below.
                  (push (list :sent-num sent-num
                              :seg-nums seg-nums
                              :tibetan tibetan
                              :filepath filepath)
                        newly-created))
              (error (setq failed (1+ failed))))))))
      (message "Sentence files: %d created, %d skipped (already existed), %d failed (total %d sentence%s)"
               created skipped failed
               (length sentences)
               (if (= (length sentences) 1) "" "s"))
      ;; Parallel to `tibetan-auto-analyze-document': fire Claude on
      ;; every newly-created sent-*.org (throttled, async) so initial
      ;; batch creation matches the single-file `C-c s A' behaviour
      ;; that fires Claude on file birth.
      (when (and (bound-and-true-p tibetan-auto-fire-claude-on-create)
                 newly-created)
        (tibetan-sentence--fire-claude-on-new-files
         (nreverse newly-created) source-file)))
    `(:created ,created :skipped ,skipped :failed ,failed
      :total ,(length sentences))))

(defun tibetan-sentence--fire-claude-on-new-files (plists source-file)
  "Queue Claude translation requests for sentence files in PLISTS.

Each PLIST has :sent-num, :seg-nums, :tibetan, :filepath.  Requests
are staggered by `tibetan-auto-claude-request-delay' (defaulting to
1.5s if the segment-level auto-analysis module isn't loaded), so 85
new sentences take 85 × 1.5 ≈ 2 min of async queue time.  Individual
failures are swallowed to `message'."
  (let* ((delay-step (or (bound-and-true-p tibetan-auto-claude-request-delay)
                         1.5))
         (delay 0.0)
         (count (length plists)))
    (message "Queueing Claude requests for %d newly-created sentence file%s \
(one every %.1fs, async)..."
             count (if (= count 1) "" "s") delay-step)
    (dolist (p plists)
      (let ((filepath (plist-get p :filepath))
            (tibetan  (plist-get p :tibetan))
            (seg-nums (plist-get p :seg-nums))
            (this-delay delay))
        (when (and tibetan (not (string-empty-p tibetan)))
          (run-at-time
           this-delay nil
           (lambda ()
             (condition-case err
                 (tibetan-sentence--request-claude
                  tibetan seg-nums filepath source-file)
               (error
                (message "Sentence Claude request failed for %s: %s"
                         (file-name-nondirectory filepath)
                         (error-message-string err))))
             ;; Sentence-level wiring of two-language-parallel-
             ;; analysis (2026-04-30): also fire Sanskrit + Combined
             ;; in parallel mode.  Same dispatcher as segment-level
             ;; reanalyse, but uses the sentence-level walker
             ;; aggregator (`text-for-sentence') across the
             ;; sentence's child segments.
             (when (and (fboundp 'tibetan-sanskrit-parallel-text-for-sentence)
                        (fboundp 'tibetan-analysis--fire-parallel-claude-with-plist))
               (let ((skt-plist
                      (condition-case nil
                          (tibetan-sanskrit-parallel-text-for-sentence
                           source-file seg-nums)
                        (error nil))))
                 (when skt-plist
                   (condition-case e2
                       (tibetan-analysis--fire-parallel-claude-with-plist
                        tibetan skt-plist source-file filepath)
                     (error (message
                             "Sentence Sanskrit/Combined fire failed for %s: %s"
                             (file-name-nondirectory filepath)
                             (error-message-string e2)))))))))
          (setq delay (+ delay delay-step)))))))

;;;###autoload
(defun tibetan-sentence-resegment ()
  "One-command re-segment workflow for an already-segmented source file.

Runs the four steps in order, with a single top-level confirmation:

  1. Archive `sent-NNN*.org' → `analysis/archive/<stamp>/'.
  2. Reset source-file structure (remove `*** Sentence N' headings,
     un-demote `**** Segment M' back to `*** Segment M').
  3. Re-run the auto-segmenter (`tibetan-add-sentence-structure').
  4. Create fresh `sent-NNN.org' for every new `*** Sentence N'.

Step 1 calls `tibetan-sentence-archive-analysis-folder'; the
individual commands' own interactive prompts are suppressed so
the user only sees ONE yes/no gate at the top.  Save the source
file yourself after reviewing the result — none of these steps
auto-save.

Intended use: after a boundary-detector upgrade (e.g. the
dialogue-framing step added on 2026-04-20) where the auto-
segmenter would now find more sentences than a previous pass.
Manual cleanup via regexp is viable but fiddly; this command
turns it into one confirmable operation."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer has no source file"))
  (let* ((counts (tibetan-sentence-reset-structure--counts
                  (current-buffer)))
         (sents  (car counts))
         (segs   (cdr counts))
         (folder (tibetan-sentence--analysis-folder))
         (sent-files (when (file-directory-p folder)
                       (directory-files folder t
                                        "\\`sent-[0-9]+.*\\.org\\'")))
         (summary
          (format "Resegment %s:
  1. Archive %d existing sent-*.org file%s into archive/
  2. Reset source: remove %d `*** Sentence' heading%s + re-promote %d `**** Segment' header%s
  3. Re-run the auto-segmenter (dialogue-boundary detection active)
  4. Create fresh sent-NNN.org for every new sentence
Proceed? "
                  (or (and buffer-file-name
                           (file-name-nondirectory buffer-file-name))
                      "<current buffer>")
                  (length sent-files)
                  (if (= (length sent-files) 1) "" "s")
                  sents (if (= sents 1) "" "s")
                  segs  (if (= segs  1) "" "s"))))
    (cond
     ((not (yes-or-no-p summary))
      (message "Resegment cancelled — nothing changed."))
     (t
      ;; Step 1 — archive (bypass its own prompt).
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (tibetan-sentence-archive-analysis-folder folder))
      ;; Step 2 — reset structure (bypass its own prompt).
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (tibetan-sentence-reset-structure))
      ;; Step 3 — re-segment.  Save first so the reset edit isn't
      ;; pending when the auto-segmenter walks the buffer.
      (when (buffer-modified-p) (save-buffer))
      (tibetan-add-sentence-structure)
      (when (buffer-modified-p) (save-buffer))
      ;; Step 4 — batch-create.
      (tibetan-sentence-create-all)
      (message "Resegment complete.  Review the source file and the new sent-*.org files; old work is in analysis/archive/.")))))

;; ============================================================================
;; §5.22 final (2026-05-21):  the opt-in toggle command
;; `tibetan-sentence-toggle-source-compressed' and its helper
;; `tibetan-sentence--source-file-for-toggle' are RETIRED.
;; Compressed sentence layout is now the unconditional default;
;; no per-source header switch needed (see
;; `tibetan-sentence--strip-list' for the dropped sections).
;; ============================================================================

(provide 'tibetan-sentence-persist)
;;; tibetan-sentence-persist.el ends here
