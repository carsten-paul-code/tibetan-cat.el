;;; tibetan-auto-analysis.el --- Automatic batch analysis generation -*- lexical-binding: t -*-

;;; Commentary:
;; Automatically generates analysis files for all segments and sentences
;; in a prepared Tibetan document.
;;
;; Usage:
;;   C-c u P  - Prepare document (tibetan-prepare-document)
;;   C-c u B  - Auto-analyze all (tibetan-auto-analyze-document)
;;
;; The auto-analyze command will:
;; 1. Create analysis/seg-NNN-*.org files for each segment
;; 2. Create analysis/sent-NNN-*.org files for each sentence
;; 3. Show progress as it processes
;; 4. Skip existing files (unless force flag is used)

;;; Code:

(require 'cl-lib)
;; Only require org when not in batch mode (can hang in batch)
(unless noninteractive
  (require 'org))

;; Load dependencies
(require 'tibetan-org-structure nil t)
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-clause-analysis nil t)
(require 'tibetan-utils nil t)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defcustom tibetan-auto-skip-existing t
  "If non-nil, skip analysis files that already exist.
Set to nil to regenerate all files."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-generate-sentences t
  "If non-nil, also generate sentence-level clause analysis files."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-show-progress t
  "If non-nil, show progress messages during batch analysis."
  :type 'boolean
  :group 'tibetan-cat)

;; ============================================================================
;; PROGRESS REPORTING
;; ============================================================================

(defvar tibetan-auto--progress-callback nil
  "Callback function for progress reporting.
Called with (CURRENT TOTAL MESSAGE).")

(defun tibetan-auto--report-progress (current total message)
  "Report progress: CURRENT of TOTAL, with MESSAGE."
  (when tibetan-auto-show-progress
    (message "%s... (%d/%d)" message current total))
  (when tibetan-auto--progress-callback
    (funcall tibetan-auto--progress-callback current total message)))

(defmacro tibetan-auto--with-progress (callback _total &rest body)
  "Execute BODY with progress CALLBACK for TOTAL items."
  (declare (indent 2))
  `(let ((tibetan-auto--progress-callback ,callback))
     ,@body))

;; ============================================================================
;; COUNTING FUNCTIONS
;; ============================================================================

(defun tibetan-auto--count-segments ()
  "Count number of segments in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^\\*\\*\\* Segment [0-9]+" nil t)
        (setq count (1+ count)))
      count)))

(defun tibetan-auto--count-sentences ()
  "Count number of sentences in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^\\*\\* Sentence [0-9]+" nil t)
        (setq count (1+ count)))
      count)))

;; ============================================================================
;; COLLECTION FUNCTIONS
;; ============================================================================

(defun tibetan-auto--seg-id->number (seg-id)
  "Convert a segment id (string like \"4\" or \"seg-4\") to an integer.
Returns nil if no digits are found."
  (cond
   ((numberp seg-id) seg-id)
   ((stringp seg-id)
    (when (string-match "\\([0-9]+\\)" seg-id)
      (string-to-number (match-string 1 seg-id))))
   (t nil)))

(defun tibetan-auto--collect-inline-segments ()
  "Collect segments marked with inline 〔seg:N〕...〔/seg〕 markers.
Returns alist of (SEGMENT-NUMBER . TIBETAN-TEXT) sorted by number."
  (when (fboundp 'tibetan-get-all-segments)
    (let (result)
      (dolist (seg (tibetan-get-all-segments))
        (let ((n (tibetan-auto--seg-id->number (car seg)))
              (text (cdr seg)))
          (when (and n text (not (string-empty-p (string-trim text))))
            (push (cons n text) result))))
      (sort (nreverse result) (lambda (a b) (< (car a) (car b)))))))

(defun tibetan-auto--collect-segments ()
  "Collect all segments from current buffer.

Supports both hierarchical org segments at any heading level (`***'
in the fresh-prep layout or `****' after `tibetan-add-sentence-structure'
demoted them under `*** Sentence N' wrappers) and inline `〔seg:N〕…〔/seg〕'
markers produced by `tibetan-doc-format'.  The hierarchical form wins
if present; otherwise the inline form is used.

The heading regex is `^\\*+ Segment ' so both `*** Segment 1' and
`**** Segment 1' are picked up.  Sentence wrappers (`*** Sentence N')
are NOT matched because the literal word differs.

Returns alist of (SEGMENT-NUMBER . TIBETAN-TEXT) for the
hierarchical form, or — when at least one segment carries a
`:FOLIO:' drawer (Yogācārabhūmi-style sources) — a list of
\(SEGMENT-NUMBER TIBETAN-TEXT FOLIO) triples so the create-file
caller can preserve the folio reference (P6, 2026-05-05).  The
inline-marker fallback always returns the cons-pair shape.

Mixed shape (pair vs triple) is fine for downstream:  callers
that want folio peek at the third element via `nth' / `caddr',
those that don't are unaware of it."
  (let ((org-segs
         (save-excursion
           (goto-char (point-min))
           (let ((segments '())
                 (any-folio nil))
             (while (re-search-forward "^\\*+ Segment \\([0-9]+\\)" nil t)
               (let* ((seg-num (string-to-number (match-string 1)))
                      (text (when (fboundp 'tibetan-org-get-segment-text)
                              (tibetan-org-get-segment-text)))
                      (folio (when (fboundp 'tibetan-org-get-segment-folio)
                               (tibetan-org-get-segment-folio))))
                 (when text
                   (when folio (setq any-folio t))
                   (push (list seg-num text folio) segments))))
             (let ((ordered (nreverse segments)))
               (if any-folio
                   ordered
                 ;; Backwards-compatible cons-pair shape when no
                 ;; segment in the document carries a folio (the
                 ;; common Milarepa / non-YBh case).  Keeps the
                 ;; downstream `(car seg)' / `(cdr seg)' destructuring
                 ;; in older / external callers working unchanged.
                 (mapcar (lambda (triple)
                           (cons (nth 0 triple) (nth 1 triple)))
                         ordered)))))))
    (if org-segs
        org-segs
      (tibetan-auto--collect-inline-segments))))

(defun tibetan-auto--collect-sentences ()
  "Collect all sentences from current buffer.

Heading regex `^\\*+ Sentence ' to match both the legacy `** Sentence N'
layout produced by `tibetan-prepare-document' and the current
`*** Sentence N' layout produced by `tibetan-add-sentence-structure'.

Returns alist of (SENTENCE-NUMBER . COMBINED-TEXT)."
  (save-excursion
    (goto-char (point-min))
    (let ((sentences '()))
      (while (re-search-forward "^\\*+ Sentence \\([0-9]+\\)" nil t)
        (let* ((sent-num (string-to-number (match-string 1)))
               (start-pos (point)))
          ;; Move to sentence heading
          (beginning-of-line)
          ;; Get combined text from all segments
          (when (tibetan-org-at-sentence-p)
            (let ((text (tibetan-org-get-sentence-text)))
              (when text
                (push (cons sent-num text) sentences))))
          ;; Move past this sentence for next iteration
          (goto-char start-pos)))
      (nreverse sentences))))

;; ============================================================================
;; SKIP LOGIC
;; ============================================================================

(defun tibetan-auto--should-skip-p (filepath)
  "Return t if we should skip generating FILEPATH."
  (and tibetan-auto-skip-existing
       (file-exists-p filepath)))

;; ============================================================================
;; FILENAME GENERATION
;; ============================================================================

(defun tibetan-auto--sentence-filename (sent-num source-file)
  "Generate filename for sentence SENT-NUM analysis.
SOURCE-FILE is used to generate a unique suffix."
  (let ((short-name (tibetan-analysis-make-short-name source-file)))
    (if short-name
        (format "sent-%03d-%s.org" sent-num short-name)
      (format "sent-%03d.org" sent-num))))

(defun tibetan-auto--sentence-filepath (sent-num)
  "Get full filepath for sentence SENT-NUM analysis."
  (let* ((folder (tibetan-analysis-get-folder))
         (source-file (buffer-file-name))
         (filename (tibetan-auto--sentence-filename sent-num source-file)))
    (expand-file-name filename folder)))

;; ============================================================================
;; SENTENCE ANALYSIS GENERATION
;; ============================================================================

(defun tibetan-auto--generate-sentence-analysis (_sent-num tibetan-text)
  "Generate sentence analysis content for SENT-NUM with TIBETAN-TEXT.
Returns the analysis as an org-mode formatted string."
  (let* ((clause-analysis (if (fboundp 'tibetan-analyze-clause-structure)
                              (tibetan-analyze-clause-structure tibetan-text)
                            "[Clause analysis not available]"))
         (converbs (when (fboundp 'tibetan-detect-converbs)
                     (tibetan-detect-converbs tibetan-text)))
         (main-verb (when (fboundp 'tibetan-find-main-verb)
                      (tibetan-find-main-verb tibetan-text))))
    (with-temp-buffer
      (insert "** Clause Structure\n\n")
      (insert clause-analysis)
      (insert "\n\n")

      ;; Main verb details
      (insert "** Main Verb\n\n")
      (if main-verb
          (insert (format "- Verb: %s\n- Position: %d\n"
                          (plist-get main-verb :verb)
                          (plist-get main-verb :position)))
        (insert "[No main verb identified]\n"))
      (insert "\n")

      ;; Converb list
      (insert "** Converbs (Dependent Clauses)\n\n")
      (if converbs
          (dolist (conv converbs)
            (insert (format "- %s (%s): %s\n"
                            (plist-get conv :particle)
                            (plist-get conv :type)
                            (plist-get conv :stem))))
        (insert "[No converbs detected]\n"))
      (insert "\n")

      (buffer-string))))

(defun tibetan-auto--create-sentence-file (sent-num tibetan-text source-file)
  "Create sentence analysis file for SENT-NUM.
TIBETAN-TEXT is the combined sentence text.
SOURCE-FILE is the path to the source document."
  (let* ((filepath (tibetan-auto--sentence-filepath sent-num))
         (content (tibetan-auto--generate-sentence-analysis sent-num tibetan-text))
         (date (format-time-string "%Y-%m-%d"))
         (source-name (file-name-nondirectory source-file)))
    (with-temp-file filepath
      (insert (format "#+TITLE: Sentence %d Analysis\n" sent-num))
      (insert "#+STARTUP: overview\n")
      (insert (format "#+SOURCE: [[file:../%s::*Sentence %d][%s / Sentence %d]]\n"
                      source-name sent-num source-name sent-num))
      (insert (format "#+CREATED: %s\n" date))
      (insert "\n")
      (insert "* Tibetan Text\n\n")
      (insert tibetan-text)
      (insert "\n\n")
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert content)
      (insert "\n")
      (insert "* Grammar Notes\n\n\n")
      (insert "* Translation\n\n\n"))
    filepath))

;; ============================================================================
;; MAIN AUTO-ANALYZE FUNCTION
;; ============================================================================

;;;###autoload
(defcustom tibetan-auto-fire-claude-on-create t
  "Whether initial batch creation should fire Claude translation requests.

When non-nil (default), `tibetan-auto-analyze-document' and
`tibetan-sentence-create-all' queue staggered gptel requests for
every newly-created `seg-*.org' (resp. `sent-*.org') file immediately
after the structural analysis is written — so a single
`C-c u B' / `C-c s N' produces both the structural skeleton AND
Claude translations, matching what the single-file `C-c u A' /
`C-c s A' commands have always done.

Set to nil to skip the Claude step and rely on a subsequent
`tibetan-auto-request-claude-translations' run.  Pre-existing files
(skipped by the structural pass) are NOT re-fired regardless of this
setting — use `C-u C-c u r' / `C-u C-c s r' for that.

The fire is async and throttled by `tibetan-auto-claude-request-delay'
(default 1.5s per request); results arrive in the background."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-fire-dm-on-create t
  "When non-nil, `tibetan-auto-analyze-document' fires DharmaMitra
translation for each newly-created segment file after Claude.

Phase A.3 of multi-translator-parallel-reading (2026-04-30).
Mirrors `tibetan-auto-fire-claude-on-create' for the DM
translator.  Set to nil to opt out of automatic DM translation
without disabling Claude."
  :type 'boolean
  :group 'tibetan-cat)

(defcustom tibetan-auto-dm-request-delay 0.5
  "Seconds between successive DharmaMitra translation requests
during batch fire.  DM's chat-translate is synchronous (~1-2 sec
per call), so 97 new segments take roughly 97 × (1.5 + 0.5) =
~3 min of queue time.  The 0.5-sec gap reduces the chance of
DM rate-limiting compared to back-to-back firing."
  :type 'number
  :group 'tibetan-cat)

(defun tibetan-auto-analyze-document (&optional force)
  "Automatically generate analysis files for all segments and sentences.

With prefix argument FORCE, regenerate all files even if they exist.
Otherwise, skips existing files based on `tibetan-auto-skip-existing'.

Creates:
- analysis/seg-NNN-*.org for each segment (word-by-word analysis)
- analysis/sent-NNN-*.org for each sentence (clause analysis)

After the structural pass, if `tibetan-auto-fire-claude-on-create'
is non-nil (default), queues Claude translation requests for every
newly-created `seg-*.org'.  Requests are staggered by
`tibetan-auto-claude-request-delay' (1.5s) and fire asynchronously.

Progress is shown in the echo area."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))

  (let* ((tibetan-auto-skip-existing (not force))
         (source-file (buffer-file-name))
         (segments (tibetan-auto--collect-segments))
         (sentences (when tibetan-auto-generate-sentences
                      (tibetan-auto--collect-sentences)))
         (total-segs (length segments))
         (total-sents (length sentences))
         (total (+ total-segs total-sents))
         (created-segs 0)
         (created-sents 0)
         (skipped 0)
         (current 0)
         (newly-created-files '()))

    (when (= total 0)
      (error "No segments or sentences found. Run tibetan-prepare-document first"))

    (message "Starting auto-analysis: %d segments, %d sentences..."
             total-segs total-sents)

    ;; Ensure analysis folder exists
    (tibetan-analysis-get-folder)

    ;; Process segments
    (dolist (seg segments)
      (setq current (1+ current))
      (let* ((triple-p (and (listp seg) (= 3 (safe-length seg))))
             (seg-num (if triple-p (nth 0 seg) (car seg)))
             (seg-text (if triple-p (nth 1 seg) (cdr seg)))
             ;; P6 (2026-05-05):  YBh-style sources surface a `:FOLIO:'
             ;; here from `--collect-segments';  Milarepa / non-YBh
             ;; sources return cons-pairs and folio is nil.  Threaded
             ;; into create-file below.
             (seg-folio (when triple-p (nth 2 seg)))
             ;; §5.23 (2026-05-22):  pass source-file to get the
             ;; SUFFIXED path `seg-NNN-<shortname>.org' (e.g.
             ;; `seg-006-gal.org' for `gal-chen-nyi-shu.org').  This
             ;; restores the §5.8.3 symmetry — both this skip-check
             ;; AND `tibetan-analysis-create-file' now pass
             ;; source-file, so both write to / look at the SAME
             ;; SUFFIXED path.  Previously both paths used the
             ;; UNSUFFIXED path, which silently collided when
             ;; multiple sources shared an analysis/ folder (MA
             ;; Readings:  gal-chen / lam-rim / title-colophon
             ;; overwrote each other on seg-1..seg-21).
             (filepath (tibetan-analysis-get-filepath seg-num source-file)))

        (tibetan-auto--report-progress current total
                                        (format "Segment %d" seg-num))

        (if (tibetan-auto--should-skip-p filepath)
            (setq skipped (1+ skipped))
          ;; Generate analysis.  Phase 6 of sanskrit-parallel-workflow
          ;; (2026-04-27): when the source is in parallel-Sanskrit
          ;; mode, thread the segment's `**** Sanskrit' sibling
          ;; through the dynamic render var so the section emitter
          ;; produces `** Sanskrit Source' above Wylie.  When the
          ;; source is not in parallel mode (or the walker module is
          ;; absent), the wrapper returns nil and behaviour is byte-
          ;; identical to pre-Phase-6.
          (let* ((tibetan-analysis--sanskrit-text-for-render
                  (and (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id)
                       (condition-case nil
                           (tibetan-sanskrit-parallel-plist-for-segment-id
                            source-file seg-num)
                         (error nil))))
                 (auto-content (tibetan-analysis-generate-content seg-text)))
            (tibetan-analysis-create-file
             seg-num seg-text source-file auto-content seg-folio)
            (setq created-segs (1+ created-segs))
            ;; Track for the Claude-fire pass below.  Store (filepath . text)
            ;; so we don't have to re-extract Tibetan from disk.
            (push (cons filepath seg-text) newly-created-files)))))

    ;; Process sentences
    (when tibetan-auto-generate-sentences
      (dolist (sent sentences)
        (setq current (1+ current))
        (let* ((sent-num (car sent))
               (sent-text (cdr sent))
               (filepath (tibetan-auto--sentence-filepath sent-num)))

          (tibetan-auto--report-progress current total
                                          (format "Sentence %d" sent-num))

          (if (tibetan-auto--should-skip-p filepath)
              (setq skipped (1+ skipped))
            ;; Generate sentence analysis
            (tibetan-auto--create-sentence-file sent-num sent-text source-file)
            (setq created-sents (1+ created-sents))))))

    ;; Report structural results BEFORE firing Claude so the user sees
    ;; the two-phase progression clearly in the echo area.
    (message "Auto-analysis complete: %d segment files, %d sentence files created (%d skipped)"
             created-segs created-sents skipped)

    ;; Fire Claude for every newly-created segment file (throttled, async).
    (when (and tibetan-auto-fire-claude-on-create
               newly-created-files
               (fboundp 'tibetan-analysis--request-claude-translation))
      (tibetan-auto--fire-claude-on-new-files
       (nreverse (copy-sequence newly-created-files))))
    ;; Phase A.3 of multi-translator-parallel-reading (2026-04-30):
    ;; Also fire DharmaMitra translations for the same set of new
    ;; files.  The two loops run in parallel — each timer fires
    ;; independently per `run-at-time'.  Tibetan + Sanskrit (in
    ;; parallel-mode docs) are handled by the umbrella
    ;; `fire-for-segment' function.
    (when (and tibetan-auto-fire-dm-on-create
               newly-created-files
               (fboundp 'tibetan-dharmamitra-translation-fire-for-segment))
      (tibetan-auto--fire-dm-on-new-files
       (nreverse newly-created-files)))))

(defun tibetan-auto--fire-dm-on-new-files (filepath-and-text-pairs)
  "Queue DharmaMitra translation requests for FILEPATH-AND-TEXT-PAIRS.

PAIRS is a list of (filepath . tibetan-text) cons cells — same
shape as `tibetan-auto--fire-claude-on-new-files'.  Each pair's
filepath is mapped to its source-file (via
`tibetan-analysis--source-file-from-analysis') and seg-id (via
`tibetan-analysis--seg-id-from-filename') so the umbrella
`tibetan-dharmamitra-translation-fire-for-segment' can fire
both Tibetan AND Sanskrit (parallel-mode) variants.

Each request fires via `run-at-time' with an offset of
`tibetan-auto-dm-request-delay' × index.  Individual failures
are swallowed to `message' and do not abort the batch.

Phase A.3 of multi-translator-parallel-reading (2026-04-30)."
  (let ((delay 0.0)
        (count (length filepath-and-text-pairs)))
    (message "Queueing DharmaMitra translation requests for %d newly-created file%s \
(one every %.1fs)..."
             count (if (= count 1) "" "s")
             (or tibetan-auto-dm-request-delay 0.5))
    (dolist (pair filepath-and-text-pairs)
      (let ((filepath (car pair))
            (text     (cdr pair))
            (this-delay delay))
        (when (and text (stringp text)
                   (not (string-empty-p (string-trim text))))
          (let* ((source-file
                  (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                       (condition-case nil
                           (tibetan-analysis--source-file-from-analysis filepath)
                         (error nil))))
                 (seg-id
                  (and (fboundp 'tibetan-analysis--seg-id-from-filename)
                       (condition-case nil
                           (tibetan-analysis--seg-id-from-filename filepath)
                         (error nil)))))
            (run-at-time
             this-delay nil
             (lambda ()
               (condition-case err
                   (when (fboundp 'tibetan-dharmamitra-translation-fire-for-segment)
                     (tibetan-dharmamitra-translation-fire-for-segment
                      text filepath source-file seg-id))
                 (error
                  (message "DharmaMitra request failed for %s: %s"
                           (file-name-nondirectory filepath)
                           (error-message-string err))))))
            (setq delay (+ delay
                           (or tibetan-auto-dm-request-delay 0.5)))))))))

(defun tibetan-auto--fire-claude-on-new-files (filepath-and-text-pairs)
  "Queue Claude translation requests for FILEPATH-AND-TEXT-PAIRS.

PAIRS is a list of (filepath . tibetan-text) cons cells.  Each request
fires via `run-at-time' with an offset of
`tibetan-auto-claude-request-delay' × index, so 97 new segments take
97 × 1.5 ≈ 2.5 min of queue time.  Individual request failures are
swallowed to `message' and do not abort the batch."
  (let ((delay 0.0)
        (count (length filepath-and-text-pairs)))
    (message "Queueing Claude translation requests for %d newly-created file%s \
(one every %.1fs, async)..."
             count (if (= count 1) "" "s")
             (or tibetan-auto-claude-request-delay 1.5))
    (dolist (pair filepath-and-text-pairs)
      (let ((filepath (car pair))
            (text     (cdr pair))
            (this-delay delay))
        (when (and text (not (string-empty-p text)))
          (run-at-time
           this-delay nil
           (lambda ()
             ;; §5.40: try the sentence-level path first — one call
             ;; per sentence, dedup'd across this loop's children; the
             ;; per-segment call below only fires when the sentence
             ;; path declines (flat layout, single-seg, parallel).
             (unless (and (fboundp 'tibetan-analysis--fire-sentence-level)
                          (condition-case nil
                              (tibetan-analysis--fire-sentence-level
                               text filepath
                               (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                                    (tibetan-analysis--source-file-from-analysis
                                     filepath))
                               (and (fboundp 'tibetan-analysis--seg-id-from-filename)
                                    (tibetan-analysis--seg-id-from-filename
                                     filepath))
                               nil)
                            (error nil)))
               (condition-case err
                   (tibetan-analysis--request-claude-translation text filepath)
                 (error
                  (message "Claude request failed for %s: %s"
                           (file-name-nondirectory filepath)
                           (error-message-string err)))))
             ;; Phase 5 of two-language-parallel-analysis (2026-04-30):
             ;; in parallel-Sanskrit mode, also fire Sanskrit +
             ;; (chained) Combined Claude calls.  Dispatcher gates
             ;; itself on parallel-mode + non-placeholder Sanskrit;
             ;; degrades to no-op for Tibetan-only segments / docs.
             (when (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls)
               (let ((src (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                               (tibetan-analysis--source-file-from-analysis
                                filepath))))
                 (condition-case e2
                     (tibetan-analysis--fire-parallel-mode-claude-calls
                      text src filepath)
                   (error
                    (message "Sanskrit/Combined fire failed for %s: %s"
                             (file-name-nondirectory filepath)
                             (error-message-string e2))))))))
          (setq delay (+ delay
                         (or tibetan-auto-claude-request-delay 1.5))))))))


;; ============================================================================
;; BATCH CLAUDE TRANSLATION (retroactively fill *** Claude sections)
;; ============================================================================

(defcustom tibetan-auto-claude-request-delay 1.5
  "Seconds to wait between successive Claude translation requests.
Batched gptel requests are fire-and-forget asynchronous, but throwing
hundreds at once causes rate-limit or timeout errors.  The staggered
fire loop in `tibetan-auto-request-claude-translations' spaces them
out by this many seconds."
  :type 'number
  :group 'tibetan-cat)

(defun tibetan-auto--extract-tibetan-text-from-analysis (filepath)
  "Read the Tibetan segment text out of the `* Tibetan Text' heading
of analysis file FILEPATH.  Returns a trimmed string, or nil."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text[ \t]*\n" nil t)
        (let ((start (point))
              (end (if (re-search-forward "^\\* " nil t)
                       (match-beginning 0)
                     (point-max))))
          (let ((text (string-trim (buffer-substring-no-properties start end))))
            (and text (not (string-empty-p text)) text)))))))

(defun tibetan-auto--claude-needs-request-p (filepath)
  "Non-nil if FILEPATH's Claude translation block is still a placeholder.

Matches the Claude Translation heading at any supported depth and form:
  * `^\\*+ Translation$'         (current — the §5.18 layout, 2026-05-04,
                                  dropped the `Claude' qualifier on the
                                  Tibetan-side translation heading)
  * `^\\*+ Claude Translation$'  (pre-§5.18 structured layout)
  * `^\\*+ Claude$'              (legacy — singular Claude block)

A translation is considered missing when the body under the first such
heading is blank, or begins with one of the standard placeholders:
`[Requesting translation...]', `[Awaiting Claude…]' (§5.21 scaffold),
`[Claude unavailable...]', `[Not available...]', or the `[Claude
request failed...]' fail-stub."
  (when (and filepath (file-exists-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward
             "^\\*+ \\(?:Claude\\(?: Translation\\)?\\|Translation\\)[ \t]*$"
             nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (if (re-search-forward "^\\*+ " nil t)
                        (line-beginning-position)
                      (point-max)))
               (body (string-trim (buffer-substring-no-properties start end))))
          (or (string-empty-p body)
              (string-match-p "\\`\\[Requesting translation" body)
              (string-match-p "\\`\\[Awaiting" body)
              (string-match-p "\\`\\[Claude unavailable" body)
              (string-match-p "\\`\\[Not available" body)
              (string-match-p "\\`\\[Claude request failed" body)))))))

(defun tibetan-auto--analysis-files (folder)
  "Return the list of per-segment analysis files under FOLDER.
Matches `seg-NNN*.org' — sentence files are deliberately excluded so
we focus the batch on the segments used in class."
  (when (and folder (file-directory-p folder))
    (sort (directory-files folder t "\\`seg-[0-9]+.*\\.org\\'")
          #'string<)))

;;;###autoload
(defun tibetan-auto-request-claude-translations (&optional force)
  "Request Claude translations for every segment analysis that is missing one.

Walks the analysis folder for the current source file, finds every
`seg-NNN*.org' whose *** Claude section is still a placeholder (or an
`unavailable' error marker), and queues an asynchronous gptel request
for each.  Requests are spaced by
`tibetan-auto-claude-request-delay' seconds so we do not trip
rate-limit guards.

With a prefix argument (FORCE non-nil), re-request translations for
every segment file regardless of whether one is already present.  Use
this after you've changed the system prompt or switched model."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))
  (unless (fboundp 'tibetan-analysis--request-claude-translation)
    (error "tibetan-analysis-persist not loaded"))
  (let* ((folder (tibetan-analysis-get-folder))
         (files (tibetan-auto--analysis-files folder))
         (targets (if force files
                    (seq-filter #'tibetan-auto--claude-needs-request-p
                                files)))
         (total (length targets))
         (queued 0)
         (skipped (- (length files) total))
         (delay 0.0))
    (cond
     ((null files)
      (message "No segment analysis files found under %s" folder))
     ((zerop total)
      (message "All %d segment analyses already have Claude translations \
(use C-u prefix to force re-request)" (length files)))
     (t
      (message "Queueing Claude translations for %d segment%s (skipping %d already filled)..."
               total (if (= total 1) "" "s") skipped)
      (dolist (file targets)
        (let ((tibetan-text
               (tibetan-auto--extract-tibetan-text-from-analysis file))
              (this-delay delay))
          (when (and tibetan-text (not (string-empty-p tibetan-text)))
            ;; Stagger so gptel does not fire all requests simultaneously.
            ;; `run-at-time' returns a timer object we don't need to track;
            ;; all failure modes are already swallowed inside
            ;; `tibetan-analysis--request-claude-translation'.
            (run-at-time
             this-delay nil
             (lambda ()
               (condition-case err
                   (tibetan-analysis--request-claude-translation
                    tibetan-text file)
                 (error
                  (message "Claude request failed for %s: %s"
                           (file-name-nondirectory file)
                           (error-message-string err))))
               ;; Phase 5 of two-language-parallel-analysis (2026-04-30):
               ;; also fire Sanskrit + Combined in parallel-mode.
               (when (fboundp 'tibetan-analysis--fire-parallel-mode-claude-calls)
                 (let ((src (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                                 (tibetan-analysis--source-file-from-analysis
                                  file))))
                   (condition-case e2
                       (tibetan-analysis--fire-parallel-mode-claude-calls
                        tibetan-text src file)
                     (error
                      (message "Sanskrit/Combined fire failed for %s: %s"
                               (file-name-nondirectory file)
                               (error-message-string e2))))))))
            (setq queued (1+ queued))
            (setq delay (+ delay
                           (or tibetan-auto-claude-request-delay 1.5))))))
      (message "Queued %d Claude translation request%s (one every %.1fs).  Results arrive asynchronously."
               queued (if (= queued 1) "" "s")
               (or tibetan-auto-claude-request-delay 1.5))))))


;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

;; Key bindings for this module live in `config/tibetan-keybindings.el',
;; which is the canonical binding surface.  Removed 2026-04-24:
;;   - `C-c u B' → `tibetan-auto-analyze-document' (now in keybindings.el)
;;   - `C-c u C' → `tibetan-auto-request-claude-translations' (bug: this
;;     clobbered `config/tibetan-keybindings.el's `C-c u C' → combine-
;;     document when loaded in the wrong order, silently preventing
;;     Claude fires).  Now bound to `C-c u F' in the central config.
;; Modules should not `global-set-key' — that's how the conflict happened.

(provide 'tibetan-auto-analysis)
;;; tibetan-auto-analysis.el ends here
