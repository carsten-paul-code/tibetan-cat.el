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

(provide 'tibetan-sanskrit-parallel)
;;; tibetan-sanskrit-parallel.el ends here
