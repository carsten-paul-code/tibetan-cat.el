;;; tibetan-sanskrit-parallel-dharmamitra.el --- DharmaMitra realign orchestrator -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase 2 of the dharmamitra-realign workflow (2026-04-27).
;;
;; Drives the per-segment Sanskrit alignment lookup: given a Tibetan
;; segment text and the parent source file, returns a ranked list of
;; candidate Sanskrit parallels from DharmaMitra's corpus.  The
;; downstream realign command (Phase 4) takes this list, asks Claude
;; to disambiguate (Phase 3), and writes the chosen Sanskrit into
;; the segment's `**** Sanskrit' sibling on `C-u' apply.
;;
;; The orchestration is two API calls:
;;   1. chat-translate Tibetan → English (DM autodetects encoding).
;;   2. semantic search the DM corpus with the English translation,
;;      filtered to `#+DM_SANSKRIT_SOURCE:' from the source-file
;;      headers, with `filter_source_language: sa' so we only get
;;      Sanskrit hits.
;;
;; Both API calls are cached by `tibetan-dharmamitra-api', so re-
;; running the same query is free after the first round.
;;
;; This module returns nil for every failure mode (missing header,
;; empty Tibetan, translate failure, search failure) — callers do
;; not need to distinguish between them.  The realign command can
;; report aggregate counts (`X of N segments failed') without
;; needing per-failure breakdown.

;;; Code:

(require 'cl-lib)
(require 'tibetan-dharmamitra-api)

;; The metadata reader lives in `persist/'; soft-required so this
;; module can stand alone for unit testing if needed.  Falls back
;; to nil-everywhere when the persist module isn't loaded.
(declare-function tibetan-analysis--read-source-metadata
                  "tibetan-analysis-claude" (source-file))

(defun tibetan-sanskrit-parallel-dm--shape-result (alist rank)
  "Convert a DharmaMitra search-result ALIST to a candidate plist.
RANK is the 1-based position in the search response.

Pure function — no I/O.  Robust to missing alist keys: each
slot defaults to nil / empty string so downstream callers always
receive a fully-populated plist."
  (list :id        (alist-get 'id alist)
        :text      (or (alist-get 'text alist) "")
        :segmentnr (alist-get 'segmentnr alist)
        :title     (alist-get 'title alist)
        :rank      rank))

;;;###autoload
(cl-defun tibetan-sanskrit-parallel-dm-candidates-for-tibetan
    (tibetan-text source-file &key (max-candidates 5))
  "Find Sanskrit alignment candidates for TIBETAN-TEXT in DM corpus.

Workflow:
  1. Read `#+DM_SANSKRIT_SOURCE:' from SOURCE-FILE.  Returns nil
     when missing — without a target work, searching the whole
     DM corpus would surface unrelated hits (e.g. high-rank
     prajñāpāramitā passages instead of Bodhisattvabhūmi).
  2. Translate TIBETAN-TEXT → English via
     `tibetan-dharmamitra-api-chat-translate'.  Returns nil if
     translation fails (HTTP error / empty response).
  3. Search the DM primary corpus with the English translation,
     filtered to the configured Sanskrit work, with
     `:source-lang sa' so only Sanskrit hits are returned.  Returns
     nil if search fails or yields no hits.
  4. Take the top MAX-CANDIDATES (default 5) hits, shape each as a
     plist `(:id ID :text STR :segmentnr STR :title STR :rank N)'.

Returns the candidate list, or nil for any failure mode (missing
header, empty Tibetan input, translate failure, search failure,
zero hits, missing/unreadable SOURCE-FILE).

Both underlying API calls are cached by request body hash, so
repeated invocations with the same inputs cost nothing after the
first."
  (when (and (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text)))
             source-file
             (stringp source-file)
             (file-exists-p source-file)
             (fboundp 'tibetan-analysis--read-source-metadata))
    (let* ((meta (tibetan-analysis--read-source-metadata source-file))
           (sa-source (plist-get meta :dm-sanskrit-source)))
      (when (and sa-source (stringp sa-source)
                 (not (string-empty-p sa-source)))
        (let ((english (tibetan-dharmamitra-api-chat-translate
                        tibetan-text)))
          (when (and english (not (string-empty-p english)))
            (let ((hits (tibetan-dharmamitra-api-search
                         english
                         :source-lang "sa"
                         :include-files (list sa-source)
                         :max-depth (max max-candidates 10))))
              (when hits
                (let ((out '()))
                  (cl-loop for hit in hits
                           for i from 1 to max-candidates
                           do (push (tibetan-sanskrit-parallel-dm--shape-result
                                     hit i)
                                    out))
                  (nreverse out))))))))))

;; ============================================================================
;; PHASE 3 — Claude disambiguation among DM candidates
;; ============================================================================
;;
;; Semantic-search rank is not always right (verified: rank 2 was
;; the correct match in our gotrapatala probe, rank 1 was
;; thematically-related-but-topically-wrong).  Phase 3 layers
;; Claude on top: given Tibetan + N candidates, ask Claude to
;; identify the actual parallel.  Falls back to top candidate when
;; Claude is unavailable or its response is unparseable, with the
;; reason stamped in the return plist for the dry-run preview.

(defcustom tibetan-sanskrit-parallel-dm-claude-pick-timeout 30
  "Seconds to wait for Claude's pick response before falling back
to the top candidate."
  :type 'integer
  :group 'tibetan-cat)

(defun tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
    (tibetan-text candidates)
  "Build the disambiguation prompt for CANDIDATES given TIBETAN-TEXT.

Pure function — no I/O.  The output is plain text Claude can
read; the response is expected back in the `## Choice' / `##
Reason' schema parsed by
`tibetan-sanskrit-parallel-dm--parse-claude-pick-response'."
  (concat
   "You are a Buddhist studies scholar comparing a Classical "
   "Tibetan canonical translation with candidate Sanskrit "
   "parallels from the same śāstra.  Identify which Sanskrit "
   "candidate is the actual source/parallel of the Tibetan "
   "passage.\n\n"
   "Tibetan passage:\n"
   tibetan-text
   "\n\n"
   "Sanskrit candidates (ranked by DharmaMitra semantic search; "
   "rank 1 was the search system's top match, but it may not be "
   "the correct parallel):\n\n"
   (mapconcat
    (lambda (cand)
      (format "Rank %d:\n%s"
              (or (plist-get cand :rank) 0)
              (or (plist-get cand :text) "[no text]")))
    candidates "\n\n")
   "\n\n"
   "Respond in EXACTLY this format (no preamble, no closing "
   "remarks):\n\n"
   "## Choice\n"
   "<single integer: the rank number of the correct candidate>\n\n"
   "## Reason\n"
   "<one or two sentences explaining the lexical / grammatical "
   "match>\n"))

(defun tibetan-sanskrit-parallel-dm--parse-claude-pick-response
    (response candidates)
  "Parse RESPONSE against CANDIDATES into a `(:chosen-rank N :reason STR)' plist.

Pure function — no I/O.  Returns nil when:
  - RESPONSE is nil / empty / not a string
  - `## Choice' heading is missing or carries no integer
  - parsed rank is outside [1, length-of-CANDIDATES]

When parsing succeeds, returns the plist; the calling
`claude-pick' uses it to look up the matching candidate."
  (when (and (stringp response)
             (not (string-empty-p response)))
    (let (rank reason)
      (when (string-match
             "## Choice[ \t]*\n[ \t]*\\([0-9]+\\)[ \t]*"
             response)
        (setq rank (string-to-number (match-string 1 response))))
      (when (string-match
             "## Reason[ \t]*\n\\(\\(?:.\\|\n\\)+?\\)\\(?:\n##\\|\\'\\)"
             response)
        (setq reason (string-trim (match-string 1 response))))
      (when (and rank
                 (>= rank 1)
                 (<= rank (length candidates)))
        (list :chosen-rank rank
              :reason (or reason ""))))))

(defun tibetan-sanskrit-parallel-dm--ask-claude-sync (prompt)
  "Synchronously call Claude with PROMPT.  Returns response string or nil.

Uses gptel under the hood (same Claude infrastructure as
`tibetan-analysis--request-claude-translation') but blocks on
`accept-process-output' until the callback fires or
`tibetan-sanskrit-parallel-dm-claude-pick-timeout' seconds
elapse.  No queue — this runs outside `tibetan-claude-queue' so
it doesn't compete with translation requests for slots.

Returns nil for any failure (gptel not loaded, HTTP error,
timeout, empty response).  Tests `cl-letf' this function so the
caller orchestration can be exercised without network."
  (condition-case err
      (when (and (featurep 'gptel) (fboundp 'gptel-request))
        (let ((response nil)
              (done nil))
          (gptel-request prompt
            :callback (lambda (r _info)
                        (setq response r)
                        (setq done t)))
          (with-timeout
              (tibetan-sanskrit-parallel-dm-claude-pick-timeout nil)
            (while (not done)
              (accept-process-output nil 0.1)))
          (and done response)))
    (error
     (message "DharmaMitra realign: Claude pick failed: %s"
              (error-message-string err))
     nil)))

;;;###autoload
(defun tibetan-sanskrit-parallel-dm-claude-pick (tibetan-text candidates)
  "Ask Claude to identify the correct Sanskrit parallel from CANDIDATES.

CANDIDATES is the list of plists returned by
`tibetan-sanskrit-parallel-dm-candidates-for-tibetan'.

Returns a plist:
  (:chosen-id ID :chosen-text TEXT :chosen-rank N :reason STR)

The `:reason' field carries either Claude's explanation or a
fallback marker — `single-candidate', `claude-unavailable-...',
`claude-response-unparseable-...' — so the realign command's
dry-run preview shows what happened.  Returns nil when CANDIDATES
is empty.

When CANDIDATES has exactly one entry, returns it directly without
calling Claude (no disambiguation needed)."
  (cond
   ((null candidates) nil)
   ((= (length candidates) 1)
    (let ((c (car candidates)))
      (list :chosen-id (plist-get c :id)
            :chosen-text (plist-get c :text)
            :chosen-rank (plist-get c :rank)
            :reason "single-candidate")))
   (t
    (let* ((prompt (tibetan-sanskrit-parallel-dm--build-claude-pick-prompt
                    tibetan-text candidates))
           (response (tibetan-sanskrit-parallel-dm--ask-claude-sync prompt))
           (parsed (and response
                        (tibetan-sanskrit-parallel-dm--parse-claude-pick-response
                         response candidates)))
           (chosen-rank (or (plist-get parsed :chosen-rank) 1))
           (reason
            (cond
             (parsed (plist-get parsed :reason))
             ((null response) "claude-unavailable-fallback-to-top")
             (t "claude-response-unparseable-fallback-to-top")))
           (chosen (cl-find-if
                    (lambda (c) (= (plist-get c :rank) chosen-rank))
                    candidates)))
      (when chosen
        (list :chosen-id (plist-get chosen :id)
              :chosen-text (plist-get chosen :text)
              :chosen-rank (plist-get chosen :rank)
              :reason (or reason "")))))))

;; ============================================================================
;; PHASE 4 — Proposal builder + document walker + preview renderer (read-only)
;; ============================================================================
;;
;; The realign command's three-stage pipeline:
;;
;;   1. Read (Tibetan, current Sanskrit) for each segment via
;;      `tibetan-sanskrit-parallel-segment-data-for-id'.
;;   2. Run Phase-2 candidates → Phase-3 claude-pick to identify
;;      the best Sanskrit parallel.
;;   3. Compare current vs proposed; build a proposal plist.
;;
;; The document walker iterates segment IDs and aggregates
;; proposals.  The preview renderer formats the result list into
;; a `*Sanskrit Realign Preview*' buffer the user reviews before
;; applying (Phase 5).

(declare-function tibetan-sanskrit-parallel-segment-data-for-id
                  "tibetan-sanskrit-parallel" (source-file seg-id))

(defun tibetan-sanskrit-parallel-dm--normalise-whitespace (s)
  "Normalise whitespace in S for proposal-comparison purposes.
Trims leading/trailing whitespace and collapses runs of
whitespace into single spaces.  Empty / nil → empty string."
  (if (and s (stringp s))
      (string-trim
       (replace-regexp-in-string "[ \t\n]+" " " s))
    ""))

(defun tibetan-sanskrit-parallel-dm--build-proposal
    (seg-id tibetan-text current-sanskrit pick)
  "Build a realign proposal plist for SEG-ID.

PICK is the plist returned by
`tibetan-sanskrit-parallel-dm-claude-pick' (or nil when no
candidates were found).  CURRENT-SANSKRIT is the body of the
segment's existing `**** Sanskrit' sibling (or nil / empty when
the segment has none yet).

Returns:
  (:seg-id N :tibetan-text TIB :current-sanskrit CUR
   :proposed-sanskrit PROP :proposed-rank R :proposed-segmentnr SN
   :reason STR :status SYM)

Status values:
  `change'         — current and proposed differ (after whitespace
                     normalisation)
  `unchanged'      — current ≈ proposed; no edit needed
  `no-candidates'  — PICK was nil (DM returned no hits, translate
                     failed, or no DM_SANSKRIT_SOURCE configured)

Pure function — no I/O.  The caller (the document walker)
handles I/O around it."
  (let* ((proposed (and pick (plist-get pick :chosen-text)))
         (cur-norm (tibetan-sanskrit-parallel-dm--normalise-whitespace
                    current-sanskrit))
         (prop-norm (tibetan-sanskrit-parallel-dm--normalise-whitespace
                     proposed))
         (status (cond
                  ((null pick) 'no-candidates)
                  ((string= cur-norm prop-norm) 'unchanged)
                  (t 'change))))
    (list :seg-id seg-id
          :tibetan-text tibetan-text
          :current-sanskrit current-sanskrit
          :proposed-sanskrit proposed
          :proposed-rank (and pick (plist-get pick :chosen-rank))
          :proposed-segmentnr (and pick (plist-get pick :chosen-id))
          :reason (or (and pick (plist-get pick :reason)) "")
          :status status)))

(defun tibetan-sanskrit-parallel-dm--collect-segment-ids (source-file)
  "Return sorted list of segment IDs found in SOURCE-FILE.
Walks every `**** Segment N' heading."
  (let (ids)
    (when (and source-file (file-exists-p source-file))
      (with-temp-buffer
        (insert-file-contents source-file)
        (goto-char (point-min))
        (while (re-search-forward
                "^\\*\\*\\*\\* Segment \\([0-9]+\\)[ \t]*$" nil t)
          (push (string-to-number (match-string 1)) ids))))
    (sort (delete-dups ids) #'<)))

;;;###autoload
(defun tibetan-sanskrit-parallel-dm-realign-document-proposals (source-file)
  "Return a list of realign proposals for every segment in SOURCE-FILE.

For each `**** Segment N' heading, runs the three-stage pipeline
(read segment data → DM candidates → Claude pick → build proposal)
and collects the result.  Order matches the source file's
segment IDs (sorted ascending).

Returns nil when SOURCE-FILE is missing / unreadable.  On per-
segment failures (translate / search failure, no candidates),
the proposal carries `:status' `no-candidates' so the preview
buffer can list it; the walker continues to the next segment.

This is the orchestrator for `realign-document'.  Phase 5 will
wrap it in an interactive command that calls this, hands the
result to the preview renderer, and (with `C-u') applies the
changes."
  (when (and source-file (file-exists-p source-file))
    (let ((seg-ids (tibetan-sanskrit-parallel-dm--collect-segment-ids
                    source-file))
          (out '()))
      (dolist (seg-id seg-ids)
        (let* ((data (tibetan-sanskrit-parallel-segment-data-for-id
                      source-file seg-id))
               (tibetan (and data (plist-get data :tibetan)))
               (current (and data (plist-get data :current-sanskrit))))
          (when tibetan
            (let* ((cands (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                           tibetan source-file))
                   (pick (and cands
                              (tibetan-sanskrit-parallel-dm-claude-pick
                               tibetan cands))))
              (push (tibetan-sanskrit-parallel-dm--build-proposal
                     seg-id tibetan current pick)
                    out)))))
      (nreverse out))))

(defun tibetan-sanskrit-parallel-dm--count-status (proposals status)
  "Count proposals in PROPOSALS with `:status' equal to STATUS."
  (cl-count-if (lambda (p) (eq (plist-get p :status) status))
               proposals))

(defun tibetan-sanskrit-parallel-dm--render-preview-buffer
    (source-file proposals)
  "Render a `*Sanskrit Realign Preview*' buffer for PROPOSALS.

SOURCE-FILE is the path of the source document being aligned;
displayed in the buffer header for context.  PROPOSALS is the
list returned by
`tibetan-sanskrit-parallel-dm-realign-document-proposals'.

The buffer shows:
  - a summary line with counts (changes / unchanged /
    no-candidates)
  - per-proposal blocks with seg-id, Tibetan, current Sanskrit,
    proposed Sanskrit, Claude reason, status

Returns the buffer.  Caller decides whether to display, kill, or
read from it; the renderer does not display the buffer itself."
  (let ((buf (get-buffer-create "*Sanskrit Realign Preview*"))
        (n-change (tibetan-sanskrit-parallel-dm--count-status
                   proposals 'change))
        (n-unchanged (tibetan-sanskrit-parallel-dm--count-status
                      proposals 'unchanged))
        (n-no-cand (tibetan-sanskrit-parallel-dm--count-status
                    proposals 'no-candidates)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Sanskrit Realign Preview\n")
        (insert "========================\n\n")
        (insert (format "Source: %s\n" source-file))
        (insert (format "Total segments scanned: %d\n" (length proposals)))
        (insert (format "  change:        %d\n" n-change))
        (insert (format "  unchanged:     %d\n" n-unchanged))
        (insert (format "  no-candidates: %d\n" n-no-cand))
        (insert "\n")
        (insert "----------------------------------------\n\n")
        (dolist (p proposals)
          (let ((seg (plist-get p :seg-id))
                (tib (plist-get p :tibetan-text))
                (cur (plist-get p :current-sanskrit))
                (prop (plist-get p :proposed-sanskrit))
                (segnr (plist-get p :proposed-segmentnr))
                (rank (plist-get p :proposed-rank))
                (reason (plist-get p :reason))
                (status (plist-get p :status)))
            (insert (format "Segment %d  [%s]\n" seg
                            (upcase (symbol-name status))))
            (when tib
              (insert (format "  Tibetan:   %s\n" tib)))
            (insert (format "  Current:   %s\n"
                            (or cur "[no Sanskrit sibling]")))
            (insert (format "  Proposed:  %s\n"
                            (or prop "[no candidates]")))
            (when segnr
              (insert (format "  DM ID:     %s (rank %s)\n"
                              segnr (or rank "?"))))
            (when (and reason (not (string-empty-p reason)))
              (insert (format "  Reason:    %s\n" reason)))
            (insert "\n")))
        (goto-char (point-min)))
      (setq buffer-read-only t))
    buf))

;; ============================================================================
;; PHASE 7 — Apply writes to analysis files only (NEVER source)
;; ============================================================================
;;
;; Architectural rule:  analysis pipeline must never modify the
;; source file.  Phase 5's source-side writer was deleted; this
;; phase ships the replacement analysis-file writer.
;;
;; Output lands as a TOP-LEVEL `* Sanskrit (DharmaMitra)' section
;; in each per-segment analysis file (seg-NNN.org).  Top-level
;; placement (outside `* Auto-Analysis') means it survives
;; reanalysis naturally — no preserve-list change needed.

(declare-function tibetan-analysis-get-filepath
                  "tibetan-analysis-persist" (seg-id &optional source-file))

(defun tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
    (analysis-file proposal)
  "Write PROPOSAL's realign output to ANALYSIS-FILE.

Creates or replaces a top-level `* Sanskrit (DharmaMitra)'
section.  The section's property drawer carries:

  :DM_SEGMENTNR:   the chosen DharmaMitra segment ID
  :DM_RANK:        the rank within the candidates list
  :CLAUDE_REASON:  the reason string from claude-pick (or
                   fallback marker)
  :LAST_REALIGN:   today's date stamp (YYYY-MM-DD)

The body is the proposed Sanskrit text.

Top-level placement (outside `* Auto-Analysis') ensures the
section survives reanalysis without changes to the existing
preserve-list machinery — `regenerate-auto' only rebuilds the
`* Auto-Analysis' subtree.

Returns t on success, nil when ANALYSIS-FILE is missing or
unwritable."
  (when (and analysis-file
             (stringp analysis-file)
             (file-exists-p analysis-file)
             (file-writable-p analysis-file))
    (let ((buf (find-file-noselect analysis-file)))
      (with-current-buffer buf
        (org-mode)
        (save-excursion
          (goto-char (point-min))
          ;; Locate or create the section.
          (let ((existing-section
                 (re-search-forward
                  "^\\* Sanskrit (DharmaMitra)[ \t]*$" nil t)))
            (cond
             (existing-section
              ;; Replace from heading through end of subtree.
              (beginning-of-line)
              (let ((start (point))
                    (end (save-excursion
                           (org-end-of-subtree t t)
                           (point))))
                (delete-region start end)))
             (t
              ;; Append at end of buffer (after a blank line if needed).
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (unless (looking-back "\n\n" 2) (insert "\n")))))
          ;; Write the new section.
          (insert
           (tibetan-sanskrit-parallel-dm--render-dharmamitra-section
            proposal))))
      (with-current-buffer buf
        (save-buffer))
      t)))

(defun tibetan-sanskrit-parallel-dm--render-dharmamitra-section (proposal)
  "Render PROPOSAL as the body text of a `* Sanskrit (DharmaMitra)'
section.  Pure function — no I/O.  Used by the analysis-file
writer; also useful for tests that want to inspect the output
shape without going through file I/O."
  (let ((segnr (or (plist-get proposal :proposed-segmentnr) ""))
        (rank (or (plist-get proposal :proposed-rank) ""))
        (reason (or (plist-get proposal :reason) ""))
        (sanskrit (or (plist-get proposal :proposed-sanskrit) "")))
    (concat
     "* Sanskrit (DharmaMitra)\n"
     ":PROPERTIES:\n"
     (format ":DM_SEGMENTNR: %s\n" segnr)
     (format ":DM_RANK: %s\n" rank)
     (format ":CLAUDE_REASON: %s\n" reason)
     (format ":LAST_REALIGN: %s\n" (format-time-string "%Y-%m-%d"))
     ":END:\n\n"
     sanskrit
     "\n")))

(defun tibetan-sanskrit-parallel-dm--apply-proposal (analysis-file proposal)
  "Apply PROPOSAL to ANALYSIS-FILE if its `:status' is `change'.

Skips proposals with status `unchanged' (no edit needed) or
`no-candidates' (DM had nothing to propose; we don't blank the
existing section).  Phase 7 (2026-04-30):  ANALYSIS-FILE is
the per-segment seg-NNN.org analysis file, NOT the source.

Returns the writer's return value (t / nil) on `change',
otherwise nil."
  (when (eq (plist-get proposal :status) 'change)
    (let ((proposed (plist-get proposal :proposed-sanskrit)))
      (when (and proposed (not (string-empty-p proposed)))
        (tibetan-sanskrit-parallel-dm--write-dharmamitra-sanskrit-to-analysis
         analysis-file proposal)))))

(defun tibetan-sanskrit-parallel-dm--apply-proposals (source-file proposals)
  "Apply every PROPOSAL in PROPOSALS whose `:status' is `change'.

Resolves each proposal's analysis file via
`tibetan-analysis-get-filepath' (which uses
`tibetan-analysis-folder' / current buffer's directory).
SOURCE-FILE is visited in a buffer first so the path resolver
gets the right context.

Returns count of successfully applied proposals.  SOURCE-FILE
itself is NEVER modified — verified by regression test."
  (let ((count 0))
    (when (and source-file (file-exists-p source-file))
      (with-current-buffer (find-file-noselect source-file)
        (dolist (p proposals)
          (let* ((seg-id (plist-get p :seg-id))
                 (analysis-file (and seg-id
                                     (fboundp 'tibetan-analysis-get-filepath)
                                     (condition-case nil
                                         (tibetan-analysis-get-filepath seg-id)
                                       (error nil)))))
            (when (and analysis-file
                       (tibetan-sanskrit-parallel-dm--apply-proposal
                        analysis-file p))
              (cl-incf count))))))
    count))

;; ----------------------------------------------------------------------------
;; Interactive commands
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-dm--resolve-source-file ()
  "Return the source file for the realign command.
If the current buffer is an analysis seg-NNN.org file, follow
its `#+SOURCE:' link.  Otherwise treat the current buffer as
the source.  Falls back to a prompt."
  (or (and (fboundp 'tibetan-analysis--source-file-from-analysis)
           (tibetan-analysis--source-file-from-analysis
            (buffer-file-name)))
      buffer-file-name
      (read-file-name "Source file: " nil nil t)))

;;;###autoload
(defun tibetan-sanskrit-parallel-dm-realign-document (&optional apply)
  "DharmaMitra-driven re-alignment of all `**** Sanskrit' siblings.

Without prefix arg: pops a `*Sanskrit Realign Preview*' buffer
showing per-segment proposals (current vs proposed Sanskrit,
Claude reason).  Re-run with `C-u' to apply the changes.

With `C-u' prefix: applies every proposal whose `:status' is
`change' to the source file's `**** Sanskrit' siblings, then
displays a summary buffer.

Source file is resolved from the current buffer (analysis or
source); falls back to a prompt.  Requires
`#+DM_SANSKRIT_SOURCE:' on the source file's headers — without
it the per-segment pipeline returns no candidates and every
proposal lands as `no-candidates'.

The pipeline calls DharmaMitra (chat-translate + search) and
Claude (disambiguation) once per segment.  Plan ~3 sec per
segment; gotrapatala (97 segments) is roughly 5 minutes."
  (interactive "P")
  (let ((source-file (tibetan-sanskrit-parallel-dm--resolve-source-file)))
    (unless (and source-file (file-exists-p source-file))
      (user-error "Cannot resolve source file"))
    (message "DharmaMitra realign: scanning %s — this calls DM + Claude per segment, may take several minutes..."
             (file-name-nondirectory source-file))
    (let ((proposals (tibetan-sanskrit-parallel-dm-realign-document-proposals
                      source-file)))
      (cond
       (apply
        (let ((n (tibetan-sanskrit-parallel-dm--apply-proposals
                  source-file proposals)))
          (display-buffer
           (tibetan-sanskrit-parallel-dm--render-preview-buffer
            source-file proposals))
          (message "DharmaMitra realign: applied %d change%s to %s"
                   n (if (= n 1) "" "s")
                   (file-name-nondirectory source-file))))
       (t
        (display-buffer
         (tibetan-sanskrit-parallel-dm--render-preview-buffer
          source-file proposals))
        (message "DharmaMitra realign preview: %d proposal%s. Re-run with C-u to apply."
                 (length proposals)
                 (if (= (length proposals) 1) "" "s")))))))

;;;###autoload
(defun tibetan-sanskrit-parallel-dm-realign-segment (&optional apply)
  "DharmaMitra-driven re-alignment of the `**** Sanskrit' sibling
for the segment under cursor.

Without prefix arg: pops a preview buffer showing the proposal
for this single segment.  With `C-u': applies it directly.

Like `tibetan-sanskrit-parallel-dm-realign-document' but
narrowed to one segment — useful for spot-checking a specific
segment without firing the full document pipeline."
  (interactive "P")
  (unless (and (derived-mode-p 'org-mode)
               (fboundp 'tibetan-org-at-segment-p)
               (tibetan-org-at-segment-p))
    (user-error "Not in a `**** Segment' subtree"))
  (let* ((source-file (tibetan-sanskrit-parallel-dm--resolve-source-file))
         (seg-id (tibetan-org-get-segment-id)))
    (unless (and source-file (file-exists-p source-file))
      (user-error "Cannot resolve source file"))
    (unless seg-id
      (user-error "Cannot resolve segment ID"))
    (message "DharmaMitra realign: querying segment %d..." seg-id)
    (let* ((data (tibetan-sanskrit-parallel-segment-data-for-id
                  source-file seg-id))
           (tibetan (and data (plist-get data :tibetan)))
           (current (and data (plist-get data :current-sanskrit)))
           (cands (and tibetan
                       (tibetan-sanskrit-parallel-dm-candidates-for-tibetan
                        tibetan source-file)))
           (pick (and cands
                      (tibetan-sanskrit-parallel-dm-claude-pick
                       tibetan cands)))
           (proposal (tibetan-sanskrit-parallel-dm--build-proposal
                      seg-id tibetan current pick))
           (proposals (list proposal)))
      (cond
       (apply
        (let ((n (tibetan-sanskrit-parallel-dm--apply-proposals
                  source-file proposals)))
          (display-buffer
           (tibetan-sanskrit-parallel-dm--render-preview-buffer
            source-file proposals))
          (message "DharmaMitra realign: applied %d change to segment %d"
                   n seg-id)))
       (t
        (display-buffer
         (tibetan-sanskrit-parallel-dm--render-preview-buffer
          source-file proposals))
        (message "DharmaMitra realign preview for segment %d. C-u to apply."
                 seg-id))))))

(provide 'tibetan-sanskrit-parallel-dharmamitra)
;;; tibetan-sanskrit-parallel-dharmamitra.el ends here
