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

Returns nil when BODY is nil, empty, or contains no IAST line."
  (when (and body (stringp body) (not (string-empty-p (string-trim body))))
    (let* ((lines (split-string body "\n"))
           (trimmed (mapcar #'string-trim lines))
           (non-empty (cl-remove-if #'string-empty-p trimmed))
           (iast (car non-empty))
           (line2 (cadr non-empty))
           devanagari script-source)
      (when iast
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

(provide 'tibetan-sanskrit-parallel)
;;; tibetan-sanskrit-parallel.el ends here
