;;; tibetan-sanskrit-parallel.el --- Sanskrit-parallel reading support -*- lexical-binding: t -*-

;; Copyright (C) 2026 Carsten Paul

;; Author: Carsten Paul <post@carstenpaul.de>
;; Keywords: Tibetan, Sanskrit, parallel-reading, classroom

;;; Commentary:
;;
;; Bridge module for the Yogācārabhūmi parallel-reading workflow,
;; where Sanskrit is the primary source and Tibetan the secondary
;; translation.  Phase 1 (2026-04-27) of the sanskrit-parallel-
;; workflow feature ships read-only primitives:
;;
;;   tibetan-sanskrit-parallel-text-for-segment ()
;;     Walks the current `**** Segment N' subtree's siblings within
;;     the same Sentence, finds the next `**** Sanskrit' heading,
;;     reads its body, and returns a plist describing the IAST and
;;     (optional) Devanagari content.
;;
;;   tibetan-sanskrit-parallel-text-for-segment-id (source-file seg-id)
;;     Same answer accessible by `(SOURCE-FILE SEG-ID)' rather than
;;     point-in-buffer.  Used by the Phase 3 Claude prompt builder.
;;
;;   tibetan-cat--source-mode-parallel-p (source-file)
;;     t iff SOURCE-FILE has `#+SOURCE_MODE: parallel-sanskrit'.
;;     Read directly from the file (no `persist/' dependency).
;;
;; Source-file conventions (per design decision validated by
;; Carsten on 2026-04-27, see `docs/feature-sanskrit-parallel.org'):
;;
;;   * Tibetan Text
;;   ** Section 1
;;   *** Sentence 1
;;   **** Segment 1
;;   :PROPERTIES:
;;   :FOLIO: D ya 1a1
;;   :END:
;;   <Tibetan Unicode>
;;
;;   **** Sanskrit
;;   :PROPERTIES:                          ; optional metadata drawer
;;   :EDITION: Bhattacharya 1957:1         ; allowed but not required
;;   :END:
;;   yathā vā punaḥ kaścid evam āha        ; line 1: IAST (required)
;;   यथा वा पुनः कश्चिद् एवम् आह              ; line 2: Devanagari (optional)
;;
;;   **** Working Translation
;;   <user-edited translation, Sanskrit-driven by convention>
;;
;; Sanskrit storage choices (a) sibling-heading not property-drawer,
;; (b) IAST primary not Devanagari primary, (c) line-positional not
;; tagged keys are documented in the design doc; the body parser
;; here implements them.  Future Sanskrit CAT will read the same
;; source files; this module's API is stable.
;;
;; Module independence:
;;   - This module sits in `core/' and intentionally does NOT
;;     depend on `persist/'.  The parallel-mode predicate reads the
;;     `#+SOURCE_MODE:' header inline rather than calling
;;     `tibetan-analysis--read-source-metadata'.
;;   - The metadata reader gains a `:source-mode' plist key in the
;;     same phase (extension lives in `persist/tibetan-analysis-
;;     claude.el') so other consumers — Phase 3 Claude prompt
;;     builder — get the value uniformly.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'tibetan-org-structure)

;; ----------------------------------------------------------------------------
;; Devanagari script sniff
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel--has-devanagari-p (str)
  "Return non-nil when STR contains a baseline Devanagari codepoint.

Tested range is U+0900–U+097F (the standard Devanagari block).
Vedic Extensions (U+1CD0–U+1CFF) and Devanagari Extended
(U+A8E0–U+A8FF) are intentionally excluded — for prose
Yogācārabhūmi reading the baseline block is sufficient and the
heuristic stays predictable.  Future Vedic-quoting sources can
opt into the broader range without disturbing this default.

Returns nil for nil, non-string, or empty input."
  (and (stringp str)
       (not (string-empty-p str))
       (let ((case-fold-search nil))
         (string-match-p "[ऀ-ॿ]" str))))

;; ----------------------------------------------------------------------------
;; Placeholder marker recognition (alignment-fix work, 2026-04-30)
;; ----------------------------------------------------------------------------

(defconst tibetan-sanskrit-parallel--placeholder-prefixes
  '("[Sanskrit alignment pending"
    "[Sanskrit alignment exhausted"
    "[No Sanskrit counterpart")
  "Recognised prefixes for `**** Sanskrit' placeholder bodies.

A `**** Sanskrit' sibling whose body starts with any of these
strings is treated as `no Sanskrit available' — the walker
returns nil rather than a plist, so the DM Sanskrit-fire path,
the Claude parallel-mode user-prompt builder, and the
`** Sanskrit Source' renderer all behave the same as for a
segment that has no `**** Sanskrit' sibling at all.

Three markers exist today:

  `[Sanskrit alignment pending …]' — universal pending marker.
    The current alignment is known-invalid (e.g.  daṇḍa-split
    that crossed a structural boundary between Tibetan and
    Sanskrit recensions); the editorial pass hasn't happened
    yet.  Most segments of `gotrapatala.org' carry this after
    2026-04-30's bulk-mark.

  `[Sanskrit alignment exhausted …]' — the daṇḍa-split prep
    ran out of Sanskrit clauses before reaching the end of the
    Tibetan segments (gotrapatala.org segs 70-97 originally).

  `[No Sanskrit counterpart …]' — explicit Tibetan-only
    marker for translator's homages, uddāna verses, or other
    canon-side editorial material with no Sanskrit equivalent
    in any extant edition.  Reserved for class-time use.

Adding a new prefix here is the only change required to teach
the whole parallel-mode pipeline about a new marker shape.")

(defun tibetan-sanskrit-parallel--placeholder-text-p (str)
  "Return non-nil when STR is a Sanskrit-alignment placeholder marker.

Checks STR against
`tibetan-sanskrit-parallel--placeholder-prefixes' via
`string-prefix-p'.  Defensive against nil and non-string
input — returns nil for both.

Used by `--parse-body' to short-circuit placeholder bodies into
nil so the walker reports `no Sanskrit available'.  Other
modules (DM fire-sanskrit, Claude prompt user-block) can call
this directly to apply the same gate without re-implementing
the prefix list."
  (and (stringp str)
       (cl-some (lambda (prefix) (string-prefix-p prefix str))
                tibetan-sanskrit-parallel--placeholder-prefixes)))

;; ----------------------------------------------------------------------------
;; Body parser
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel--parse-body (body)
  "Parse BODY (a string) into a Sanskrit-text plist or nil.

Splits BODY on newlines.  The first non-empty trimmed line is
taken as IAST.  If the second non-empty line contains Devanagari
codepoints (per `tibetan-sanskrit-parallel--has-devanagari-p')
it is taken as Devanagari; otherwise it is dropped.  Subsequent
lines are ignored.

Returned plist:
  (:iast STRING                  ; trimmed line 1
   :devanagari STRING-or-nil     ; trimmed line 2 if Devanagari
   :script-source SYMBOL)        ; `iast-line' or `iast-and-devanagari'

Returns nil when:
  - BODY is nil, empty, or contains no IAST line.
  - The IAST line is a placeholder marker recognised by
    `tibetan-sanskrit-parallel--placeholder-text-p' (alignment-
    fix work, 2026-04-30).  Placeholder segments thus look the
    same to downstream consumers as segments that have no
    `**** Sanskrit' sibling at all."
  (when (and body (stringp body) (not (string-empty-p (string-trim body))))
    (let* ((lines (split-string body "\n"))
           (trimmed (mapcar #'string-trim lines))
           (non-empty (cl-remove-if #'string-empty-p trimmed))
           (iast (car non-empty))
           (line2 (cadr non-empty))
           devanagari script-source)
      (when (and iast
                 (not (tibetan-sanskrit-parallel--placeholder-text-p iast)))
        (cond
         ((and line2 (tibetan-sanskrit-parallel--has-devanagari-p line2))
          (setq devanagari line2
                script-source 'iast-and-devanagari))
         (t
          (setq script-source 'iast-line)))
        (list :iast iast
              :devanagari devanagari
              :script-source script-source)))))

;; ----------------------------------------------------------------------------
;; Sibling walker (point-based)
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-text-for-segment ()
  "Return Sanskrit-text plist for the current `**** Segment' subtree.

When point is in or under a `**** Segment' heading, scans the
same-level siblings within the enclosing Sentence subtree for a
heading whose text starts with `Sanskrit'.  Reads that subtree's
body via `tibetan-org--read-subtree-body' and parses it via
`tibetan-sanskrit-parallel--parse-body'.

Walking semantics:
  - Stops at the next `**** Segment' sibling (Sanskrit belongs
    to the segment that immediately precedes it).
  - Stops at any heading shallower than the current Segment
    (Sentence boundary).
  - Skips intervening siblings such as `**** Working Translation'
    so a Sanskrit heading placed AFTER Working Translation is
    still found.

Returns nil when:
  - Point is not in or under a Segment.
  - The Segment has no Sanskrit sibling within its Sentence.
  - The Sanskrit sibling has an empty body."
  (when (and (derived-mode-p 'org-mode)
             (tibetan-org-at-segment-p))
    (save-excursion
      (condition-case nil
          (let (seg-level)
            (unless (org-at-heading-p)
              (org-back-to-heading t))
            (setq seg-level (org-current-level))
            ;; Skip past this segment's subtree.  The second `t' is
            ;; INVISIBLE-OK; the third `t' is TO-HEADING — leaves
            ;; point at the next heading line (or `point-max').
            (org-end-of-subtree t t)
            (let ((found nil)
                  (stopped nil))
              (while (and (not found)
                          (not stopped)
                          (looking-at "^\\*+ "))
                (let ((heading-level (org-current-level))
                      (heading-text (org-get-heading t t t t)))
                  (cond
                   ;; Walked out of the parent Sentence subtree.
                   ((< heading-level seg-level)
                    (setq stopped t))
                   ;; Next Segment sibling — Sanskrit found here
                   ;; would belong to that segment, not ours.
                   ((and (= heading-level seg-level)
                         heading-text
                         (string-prefix-p "Segment" heading-text))
                    (setq stopped t))
                   ;; Sanskrit sibling — win.
                   ((and (= heading-level seg-level)
                         heading-text
                         (string-prefix-p "Sanskrit" heading-text))
                    (setq found
                          (tibetan-sanskrit-parallel--parse-body
                           (tibetan-org--read-subtree-body)))))
                  ;; Advance past this heading's subtree to the next.
                  (unless (or found stopped)
                    (org-end-of-subtree t t))))
              found))
        (error nil)))))

;; ----------------------------------------------------------------------------
;; File-based lookup (used by the Claude prompt builder in Phase 3)
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-text-for-segment-id (source-file seg-id)
  "Return Sanskrit-text plist for SEG-ID inside SOURCE-FILE, or nil.

Opens SOURCE-FILE in a temporary org buffer, navigates to the
heading `Segment SEG-ID', and delegates to
`tibetan-sanskrit-parallel-text-for-segment'.

Returns nil when SOURCE-FILE is nil/empty/missing, when SEG-ID
is not an integer, when the file has no matching `Segment N'
heading, or when the Segment has no Sanskrit sibling.  Never
errors — wrapped in `condition-case' so callers can use the
result directly without guarding."
  (when (and source-file
             (stringp source-file)
             (not (string-empty-p source-file))
             (file-exists-p source-file)
             (integerp seg-id))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents source-file)
          (org-mode)
          (when (fboundp 'org-set-regexps-and-options)
            (org-set-regexps-and-options))
          (goto-char (point-min))
          (let (found)
            (while (and (not found)
                        (re-search-forward
                         "^\\*+[ \t]+Segment[ \t]+\\([0-9]+\\)" nil t))
              (when (= (string-to-number (match-string 1)) seg-id)
                (setq found t)
                (beginning-of-line)))
            (when found
              (tibetan-sanskrit-parallel-text-for-segment))))
      (error nil))))

;; ----------------------------------------------------------------------------
;; Source-mode predicate
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;; Mode-gated walker (Phase 6, 2026-04-27)
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-plist-for-segment-id (source-file seg-id)
  "Return the Sanskrit plist for SEG-ID in SOURCE-FILE — gated by mode.

This is a convenience wrapper for analysis call sites
(`tibetan-auto-analyze-document', `tibetan-analysis-reanalyze-
file', the per-segment open / reanalyse paths).  Returns:

  - the walker plist
    `(:iast STR :devanagari STR-or-nil :script-source SYM)'
    when SOURCE-FILE has `#+SOURCE_MODE: parallel-sanskrit' AND
    the segment has a `**** Sanskrit' sibling.

  - nil otherwise — including when SOURCE-FILE is not in
    parallel mode (today's behaviour preserved byte-for-byte for
    Tibetan-only documents), when the file is missing, or when
    SEG-ID is not an integer.

Call sites bind `tibetan-analysis--sanskrit-text-for-render' to
this function's return value and the renderer fires conditionally
in `tibetan-analysis--render-sanskrit-source' (Phase 2)."
  (when (and source-file
             (integerp seg-id)
             (tibetan-cat--source-mode-parallel-p source-file))
    (tibetan-sanskrit-parallel-text-for-segment-id source-file seg-id)))

;; ----------------------------------------------------------------------------
;; Sentence-level aggregation walker (sentence wiring, 2026-04-30)
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-text-for-sentence (source-file seg-ids)
  "Return an aggregated Sanskrit plist for a SENTENCE in SOURCE-FILE.

SEG-IDS is a list of integer segment ids that constitute the
sentence.  Walks each child segment, collects its Sanskrit
plist via `tibetan-sanskrit-parallel-text-for-segment-id'
\(which already filters out placeholder bodies — see
`tibetan-sanskrit-parallel--placeholder-text-p').  Concatenates
the surviving IAST lines (separated by blank lines) and the
surviving Devanagari lines (same).

Returns:
  - `(:iast CONCAT-IAST :devanagari CONCAT-DEV-or-nil
     :script-source SYM)'  when at least one child segment has
    real (non-placeholder) Sanskrit content.
  - nil when SOURCE-FILE is non-parallel, when SEG-IDS is empty,
    or when every child segment's Sanskrit is missing /
    placeholder.

Used by the sentence-level dispatch (sent-NNN.org
reanalyse paths) to fire ONE Sanskrit Claude call covering the
whole sentence — granularity matching the sentence-scoped
Tibetan analysis.

Devanagari aggregation rule: if ANY child segment has
Devanagari, the aggregated `:devanagari' is the concatenation
of those that have it (segments without Devanagari contribute
nothing).  When NO child has Devanagari, `:devanagari' is nil
and `:script-source' is `iast-line'.

Mode-gated:  returns nil when SOURCE-FILE lacks
`#+SOURCE_MODE: parallel-sanskrit'.  Same gate as
`tibetan-sanskrit-parallel-plist-for-segment-id'."
  (when (and source-file
             (listp seg-ids) seg-ids
             (tibetan-cat--source-mode-parallel-p source-file))
    (let (iast-lines dev-lines)
      (dolist (seg-id seg-ids)
        (when (integerp seg-id)
          (let ((p (condition-case nil
                       (tibetan-sanskrit-parallel-text-for-segment-id
                        source-file seg-id)
                     (error nil))))
            (when p
              (let ((iast (plist-get p :iast))
                    (dev  (plist-get p :devanagari)))
                (when (and iast (stringp iast)
                           (not (string-empty-p (string-trim iast))))
                  (push iast iast-lines))
                (when (and dev (stringp dev)
                           (not (string-empty-p (string-trim dev))))
                  (push dev dev-lines)))))))
      (when iast-lines
        (let ((iast (mapconcat #'identity (nreverse iast-lines) "\n"))
              (dev  (and dev-lines
                         (mapconcat #'identity (nreverse dev-lines)
                                    "\n"))))
          (list :iast iast
                :devanagari dev
                :script-source (if dev
                                   'iast-and-devanagari
                                 'iast-line)))))))

;; ----------------------------------------------------------------------------
;; Source-mode header management (Phase 5, 2026-04-27)
;; ----------------------------------------------------------------------------
;;
;; Three commands manage the `#+SOURCE_MODE:' header on source
;; documents.  They are patterned on `tibetan-analysis-set-source-
;; target-lang' (`persist/tibetan-analysis-claude.el:367') —
;; replace-in-place when the header exists, insert after `#+TITLE:'
;; when missing, prepend when no `#+TITLE:' either.  No interactive
;; arguments beyond the source file path; the toggle command picks
;; up `parallel-sanskrit' from a defcustom-able default below.

(defcustom tibetan-cat-source-mode-default-parallel "parallel-sanskrit"
  "The mode token written by `tibetan-cat-toggle-source-mode-parallel'.

Currently `parallel-sanskrit' is the only implemented mode.
Future modes (`parallel-pali', `commentary-with-base', …) would
extend this list and route through the same toggle command via
a per-mode interactive variant — for now the constant default
keeps the toggle one-keystroke."
  :type 'string
  :group 'tibetan-cat)

(defun tibetan-cat-set-source-mode (source-file mode)
  "Set `#+SOURCE_MODE:' to MODE on SOURCE-FILE.

When SOURCE-FILE already has a `#+SOURCE_MODE:' line, the value
is replaced in place.  Otherwise the new line is inserted right
after the first `#+TITLE:' line so document metadata stays
contiguous at the top of the file.  When neither header is
present, the mode header is prepended to the buffer.

Re-analyses of this document pick up the new value automatically
via `tibetan-analysis--read-source-metadata' — no manual reload
needed.  Interactive callers get a final-state message.

Errors when MODE is nil / empty, or when SOURCE-FILE is nil /
non-existent / not writable."
  (interactive
   (list (or (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                  (tibetan-analysis--source-file-from-analysis
                   (buffer-file-name)))
             buffer-file-name
             (read-file-name "Source file: " nil nil t))
         (read-string "Source mode (e.g. parallel-sanskrit): "
                      tibetan-cat-source-mode-default-parallel)))
  (unless (and mode (stringp mode) (not (string-empty-p (string-trim mode))))
    (user-error "Source mode must be a non-empty string (got %S)" mode))
  (unless (and source-file (stringp source-file)
               (not (string-empty-p source-file))
               (file-exists-p source-file)
               (file-writable-p source-file))
    (user-error
     "Cannot write source-mode header — source file missing / not writable: %s"
     source-file))
  (let ((mode (string-trim mode)))
    (with-temp-buffer
      (insert-file-contents source-file)
      (goto-char (point-min))
      (cond
       ;; Replace existing line in place.
       ((re-search-forward "^#\\+SOURCE_MODE:[ \t]*.*$" nil t)
        (replace-match (format "#+SOURCE_MODE: %s" mode) t t))
       ;; Insert immediately after the first #+TITLE: line.
       ((progn (goto-char (point-min))
               (re-search-forward "^#\\+TITLE:.*$" nil t))
        (end-of-line)
        (insert (format "\n#+SOURCE_MODE: %s" mode)))
       ;; No #+TITLE either — prepend to the buffer.
       (t
        (goto-char (point-min))
        (insert (format "#+SOURCE_MODE: %s\n" mode))))
      (write-region (point-min) (point-max) source-file))
    (when (called-interactively-p 'any)
      (message "Source mode set to `%s' on %s" mode
               (file-name-nondirectory source-file)))))

(defun tibetan-cat-clear-source-mode (source-file)
  "Remove the `#+SOURCE_MODE:' header from SOURCE-FILE, if present.

No-op (and no error) when the header is absent.  Returns the
document to today's Tibetan-only behaviour: the next reanalyse
emits no `** Sanskrit Source' section, the Claude system prompt
reverts to Tibetan-only translation, and the user prompt drops
the Sanskrit (primary) block.

Errors when SOURCE-FILE is nil / non-existent / not writable."
  (interactive
   (list (or (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                  (tibetan-analysis--source-file-from-analysis
                   (buffer-file-name)))
             buffer-file-name
             (read-file-name "Source file: " nil nil t))))
  (unless (and source-file (stringp source-file)
               (not (string-empty-p source-file))
               (file-exists-p source-file)
               (file-writable-p source-file))
    (user-error
     "Cannot clear source-mode header — source file missing / not writable: %s"
     source-file))
  (with-temp-buffer
    (insert-file-contents source-file)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+SOURCE_MODE:.*\n?" nil t)
      (replace-match "" t t)
      (write-region (point-min) (point-max) source-file)))
  (when (called-interactively-p 'any)
    (message "Source mode cleared on %s"
             (file-name-nondirectory source-file))))

;;;###autoload
(defun tibetan-cat-toggle-source-mode-parallel ()
  "Toggle `#+SOURCE_MODE: parallel-sanskrit' on the current source file.

When the source file is in parallel-sanskrit mode, the header is
removed (back to today's Tibetan-only behaviour).  Otherwise the
header is set (or replaced if a different mode token was
present) to `parallel-sanskrit'.

Source file resolution:
  1. If the current buffer is an analysis file (seg-NNN*.org),
     follow its `#+SOURCE:' link to the source document.
  2. Otherwise, treat the current buffer's file as the source.
  3. If neither resolves, prompt for a path.

Bound to `C-c u z P' (parallel-Sanskrit) under the existing
`C-c u z' source-document prefix.  Sibling of `C-c u z L'
(target language)."
  (interactive)
  (let* ((source-file
          (or (and (fboundp 'tibetan-analysis--source-file-from-analysis)
                   (tibetan-analysis--source-file-from-analysis
                    (buffer-file-name)))
              buffer-file-name
              (read-file-name "Source file: " nil nil t))))
    (unless (and source-file (file-exists-p source-file))
      (user-error "Cannot resolve source file: %S" source-file))
    (cond
     ((tibetan-cat--source-mode-parallel-p source-file)
      (tibetan-cat-clear-source-mode source-file)
      (message "Sanskrit-parallel mode DISABLED on %s"
               (file-name-nondirectory source-file)))
     (t
      (tibetan-cat-set-source-mode source-file
                                    tibetan-cat-source-mode-default-parallel)
      (message "Sanskrit-parallel mode ENABLED on %s — next %s will %s"
               (file-name-nondirectory source-file)
               "C-c u R / C-c u r"
               "render ** Sanskrit Source and ask Claude to translate from Sanskrit")))))

(defun tibetan-cat--source-mode-parallel-p (source-file)
  "Return non-nil iff SOURCE-FILE has `#+SOURCE_MODE: parallel-sanskrit'.

The header is read directly from the file (no `persist/'
dependency) — this lets `core/' callers ask the question without
pulling in the analysis pipeline.

The persist-layer metadata reader,
`tibetan-analysis--read-source-metadata', exposes the same value
on its `:source-mode' plist key for callers that already build
the full metadata plist (Phase 3 Claude prompt builder).

Safe when SOURCE-FILE is nil, empty, or missing — returns nil."
  (and source-file
       (stringp source-file)
       (not (string-empty-p source-file))
       (file-exists-p source-file)
       (condition-case nil
           (with-temp-buffer
             (insert-file-contents source-file)
             (goto-char (point-min))
             (when (re-search-forward
                    "^#\\+SOURCE_MODE:[ \t]*\\(.*?\\)[ \t]*$" nil t)
               (equal (string-trim (match-string 1)) "parallel-sanskrit")))
         (error nil))))

;; ----------------------------------------------------------------------------
;; By-ID segment data reader (Phase 4 of dharmamitra-realign, 2026-04-27)
;; ----------------------------------------------------------------------------

(defun tibetan-sanskrit-parallel-segment-data-for-id (source-file seg-id)
  "Return `(:tibetan STR :current-sanskrit STR)' for SEG-ID in SOURCE-FILE.

Walks SOURCE-FILE's `**** Segment N' headings, narrows to the
matching one, extracts the Tibetan body via
`tibetan-org-get-segment-text' and the current `**** Sanskrit'
sibling's body via `tibetan-sanskrit-parallel-text-for-segment'.

Returns nil when:
  - SOURCE-FILE is nil / unreadable
  - SEG-ID has no matching `**** Segment SEG-ID' heading

The `:current-sanskrit' value is nil when the segment has no
`**** Sanskrit' sibling yet (legacy or fresh document).  The
realign workflow treats nil current-sanskrit as a fill, not a
change."
  (when (and source-file
             (stringp source-file)
             (file-exists-p source-file)
             (integerp seg-id))
    (with-temp-buffer
      (insert-file-contents source-file)
      (org-mode)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\*\\*\\* Segment %d[ \t]*$" seg-id) nil t)
        (let* ((tibetan (tibetan-org-get-segment-text))
               (sanskrit-plist
                (condition-case nil
                    (tibetan-sanskrit-parallel-text-for-segment)
                  (error nil)))
               (current-sanskrit
                (and sanskrit-plist
                     (or (plist-get sanskrit-plist :iast)
                         (plist-get sanskrit-plist :devanagari)))))
          (when tibetan
            (list :tibetan tibetan
                  :current-sanskrit current-sanskrit)))))))

;; ----------------------------------------------------------------------------
;; (REMOVED 2026-04-30) `--write-sanskrit-for-segment-id'
;; ----------------------------------------------------------------------------
;;
;; Phase 7 of dharmamitra-realign retired the source-side Sanskrit
;; writer.  Architectural rule:  the analysis pipeline must never
;; modify the user's source file (CLAUDE.md §6 — preserve user
;; content; the source is the user's curated input).
;;
;; The realign command's apply mode now writes its output to the
;; per-segment analysis file (seg-NNN.org) as a top-level
;; `* Sanskrit (DharmaMitra)' section instead.  See
;; `core/tibetan-sanskrit-parallel-dharmamitra.el' for the
;; analysis-file writer that replaces this function.

;; ----------------------------------------------------------------------------
;; Reset Sanskrit-side sections (alignment-fix work, 2026-04-30)
;; ----------------------------------------------------------------------------
;;
;; When a parallel-Sanskrit source file's `**** Sanskrit' alignment
;; changes structurally — the most common trigger is a bulk re-mark
;; to `[Sanskrit alignment pending …]' after the daṇḍa-split is
;; deemed structurally invalid — every existing analysis file in
;; the folder still carries Sanskrit-side sections whose bodies
;; were generated against the OLD alignment.  These commands
;; remove those sections cleanly so the next reanalyse regenerates
;; them from the new source (or omits them if the source is now
;; pending).
;;
;; Sections targeted:
;;
;;   level 2 (inside `* Auto-Analysis'):
;;     `** Sanskrit Source'
;;     `** Claude Translation (Sanskrit)'
;;     `** Claude Translation (Combined)'
;;     `** Claude Divergence'
;;
;;   level 1 (top-level):
;;     `* DharmaMitra Translation (Sanskrit)'
;;
;; PRESERVED — never touched by reset:
;;   `** Claude Translation' (Tibetan-side bare heading)
;;   `* DharmaMitra Translation (Tibetan)'
;;   All parser-side sections (Wylie, Interlinear, Grammar, Sentence
;;     Structure, Verb Classification, Detailed Dictionary,
;;     Provided Translations and its `*** Claude *' children)
;;   `* My Notes', `* Working Translation', `* Footnotes' — user
;;     content (CLAUDE.md §6 invariant).

(defconst tibetan-sanskrit-parallel--reset-level2-headings
  '("Sanskrit Source"
    "Claude Translation (Sanskrit)"
    "Claude Translation (Combined)"
    "Claude Divergence")
  "Level-2 headings (inside `* Auto-Analysis') that the reset
command removes from each analysis file.

Adding a new heading here is the only change needed to teach
the reset command about a new Sanskrit-side section type — the
buffer-level deletion algorithm is heading-name driven.")

(defconst tibetan-sanskrit-parallel--reset-level1-headings
  '("DharmaMitra Translation (Sanskrit)")
  "Level-1 (top-level) headings that the reset command removes.
Currently the only such heading is the Sanskrit-side DharmaMitra
translation — the Tibetan-side counterpart `* DharmaMitra
Translation (Tibetan)' is intentionally NOT in this list.")

(defun tibetan-sanskrit-parallel--reset-delete-section-in-buffer
    (heading-text level)
  "Delete the section under HEADING-TEXT at org LEVEL in the current buffer.
Stops the deletion at the next heading at LEVEL-or-shallower or
end of buffer.  Returns t if a section was deleted, nil
otherwise.  Idempotent — re-running on a buffer where the
section is already absent is a safe no-op."
  (save-excursion
    (goto-char (point-min))
    (let ((heading-re
           (format "^%s %s[ \t]*$"
                   (regexp-quote (make-string level ?*))
                   (regexp-quote heading-text)))
          ;; `*\\{1,N\\}' plus a mandatory non-`*' follower so the
          ;; stop matches level-N-or-shallower headings only —
          ;; deeper headings don't trigger the stop, so the section
          ;; body (with its child sub-headings) is fully captured.
          (stop-re (format "^\\*\\{1,%d\\}[^*\n]" level))
          (deleted nil))
      (while (re-search-forward heading-re nil t)
        (let* ((heading-start (line-beginning-position))
               (after-heading (progn (forward-line 1) (point)))
               (section-end
                (or (save-excursion
                      (goto-char after-heading)
                      (when (re-search-forward stop-re nil t)
                        (line-beginning-position)))
                    (point-max))))
          (delete-region heading-start section-end)
          (setq deleted t)
          ;; After deletion, re-anchor at the deletion point so the
          ;; outer loop's re-search-forward resumes correctly when
          ;; multiple instances of the same heading exist (rare but
          ;; possible after a botched batch).
          (goto-char heading-start)))
      deleted)))

(defun tibetan-sanskrit-parallel--reset-squash-blank-runs ()
  "Collapse runs of 3+ blank lines down to a single blank line.
The deletion above can leave \"\\n\\n\\n\\n\" gaps where two
adjacent target sections both got removed; this restores normal
spacing.  Operates on the current buffer."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "\n\n\n+" nil t)
      (replace-match "\n\n"))))

;;;###autoload
(defun tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file (filepath)
  "Remove Sanskrit-side sections from FILEPATH, save, return count.

Removes every section listed in
`tibetan-sanskrit-parallel--reset-level2-headings' (level-2
inside `* Auto-Analysis') and
`tibetan-sanskrit-parallel--reset-level1-headings' (level-1
top-level).  See the commentary above for the full list and
the preserved-content invariants.

Returns the integer count of sections removed (0 when the file
was already clean).  Idempotent: re-running on a clean file
returns 0 and leaves the file byte-identical.

The buffer is saved only when at least one section was
removed — clean files don't generate a no-op save event that
would alter `mtime' or trigger external file-watchers."
  (let ((touched 0)
        (buf (find-file-noselect filepath)))
    (unwind-protect
        (with-current-buffer buf
          (let ((was-modified (buffer-modified-p)))
            (org-mode)
            (dolist (h tibetan-sanskrit-parallel--reset-level2-headings)
              (when (tibetan-sanskrit-parallel--reset-delete-section-in-buffer
                     h 2)
                (cl-incf touched)))
            (dolist (h tibetan-sanskrit-parallel--reset-level1-headings)
              (when (tibetan-sanskrit-parallel--reset-delete-section-in-buffer
                     h 1)
                (cl-incf touched)))
            (when (> touched 0)
              (tibetan-sanskrit-parallel--reset-squash-blank-runs)
              (save-buffer))
            ;; If file was unvisited before this call AND we made
            ;; no changes, leave its modified flag untouched.  No-
            ;; op safety: don't accidentally save other buffers.
            (unless was-modified
              (set-buffer-modified-p nil))))
      ;; Don't kill the buffer — caller might be batching and
      ;; killing each buffer would defeat any user-side caching.
      ;; (Unit tests delete the temp file at unwind time, which
      ;; auto-clears the buffer via Emacs' built-in cleanup.)
      nil)
    touched))

;;;###autoload
(defun tibetan-sanskrit-parallel--reset-sanskrit-sections-in-folder (folder)
  "Run `--reset-sanskrit-sections-in-file' on every `seg-NNN.org'
and `sent-NNN.org' file in FOLDER.

Returns a plist summary:
  (:files-touched     N
   :files-clean       M
   :sections-removed  K)

When FOLDER is nil, missing, or not a directory, returns
  (:error \"reason …\")
so the interactive command can report the failure without an
exception.

Files outside the seg/sent naming convention are silently
skipped — the reset target is a parallel-Sanskrit reading's
analysis folder, not arbitrary org files."
  (cond
   ((or (null folder)
        (not (stringp folder))
        (string-empty-p folder))
    (list :error "FOLDER must be a non-empty string."))
   ((not (file-directory-p folder))
    (list :error (format "Not a directory: %s" folder)))
   (t
    (let ((files
           (sort (directory-files
                  folder t "^\\(seg\\|sent\\)-[0-9]+.*\\.org\\'")
                 #'string-lessp))
          (touched 0)
          (clean 0)
          (sections 0))
      (dolist (f files)
        (let ((n (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-file
                  f)))
          (cl-incf sections n)
          (if (> n 0) (cl-incf touched) (cl-incf clean))))
      (list :files-touched touched
            :files-clean   clean
            :sections-removed sections)))))

;;;###autoload
(defun tibetan-sanskrit-parallel-reset-sanskrit-sections-in-folder
    (folder)
  "Interactive entry point — reset Sanskrit-side sections in FOLDER.

Removes every `** Sanskrit Source', `** Claude Translation
(Sanskrit)', `** Claude Translation (Combined)', `** Claude
Divergence', and `* DharmaMitra Translation (Sanskrit)' from
every `seg-NNN.org' / `sent-NNN.org' analysis file in FOLDER.

Designed for after-the-fact cleanup when the parallel-Sanskrit
source's `**** Sanskrit' alignment is bulk-changed (e.g. marked
as `[Sanskrit alignment pending …]' for class-time editorial
verification).  Existing analysis files generated against the
old alignment carry Sanskrit-side sections that no longer
match; this command removes them cleanly so the next reanalyse
regenerates them — or, when the source is now pending, omits
them.

Prompts for confirmation.  Default FOLDER is the current
analysis folder per `tibetan-analysis-get-folder' (when
available); otherwise the user is prompted for a directory.

Reports the summary in `*Messages*' on completion."
  (interactive
   (list (read-directory-name
          "Reset Sanskrit-side sections in folder: "
          (when (fboundp 'tibetan-analysis-get-folder)
            (ignore-errors (tibetan-analysis-get-folder))))))
  (when (yes-or-no-p
         (format "Remove Sanskrit-side sections from every seg-/sent-NNN.org in %s? "
                 folder))
    (let ((summary
           (tibetan-sanskrit-parallel--reset-sanskrit-sections-in-folder
            folder)))
      (cond
       ((plist-get summary :error)
        (message "tibetan-sanskrit-parallel-reset: %s"
                 (plist-get summary :error)))
       (t
        (message
         "tibetan-sanskrit-parallel-reset: folder=%s touched=%d clean=%d sections-removed=%d"
         folder
         (plist-get summary :files-touched)
         (plist-get summary :files-clean)
         (plist-get summary :sections-removed))))
      summary)))

(provide 'tibetan-sanskrit-parallel)
;;; tibetan-sanskrit-parallel.el ends here
