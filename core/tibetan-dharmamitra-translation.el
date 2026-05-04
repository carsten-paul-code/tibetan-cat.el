;;; tibetan-dharmamitra-translation.el --- DharmaMitra as a translator alongside Claude -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase A of multi-translator-parallel-reading (2026-04-30).
;;
;; Adds DharmaMitra alongside Claude as a translation engine in
;; per-segment analysis files.  Each segment receives a top-level
;; `* DharmaMitra Translation (Tibetan)' section after `C-c u A',
;; populated by the chat-translate API.  In parallel-Sanskrit mode
;; with a `**** Sanskrit' sibling on the source, a second section
;; `* DharmaMitra Translation (Sanskrit)' is added (Phase A.2).
;;
;; Top-level placement (single asterisk) means the section
;; survives reanalysis without touching the existing preserve-
;; list machinery — same pattern as `* Sanskrit (DharmaMitra)'
;; from the realign feature.  If we later want level-2 inside
;; `* Auto-Analysis' (more "like Claude" structurally), that's a
;; targeted migration.

;;; Code:

(require 'tibetan-dharmamitra-api)
(require 'tibetan-sanskrit-parallel nil t)

;; ----------------------------------------------------------------------------
;; Writer
;; ----------------------------------------------------------------------------

(defun tibetan-dharmamitra-translation--write-section
    (analysis-file translation source-lang)
  "Write `* DharmaMitra Translation (SOURCE-LANG)' to ANALYSIS-FILE.

Creates or replaces the section.  Body is TRANSLATION; property
drawer carries `:LAST_TRANSLATED:' (today's date) for freshness
tracking.

Returns t on success, nil when ANALYSIS-FILE is missing or any
input is invalid."
  (when (and analysis-file
             (stringp analysis-file)
             (file-exists-p analysis-file)
             (file-writable-p analysis-file)
             (stringp translation)
             (not (string-empty-p translation))
             (stringp source-lang)
             (not (string-empty-p source-lang)))
    (let ((buf (find-file-noselect analysis-file))
          (heading (format "* DharmaMitra Translation (%s)" source-lang))
          (heading-re (format "^\\* DharmaMitra Translation (%s)[ \t]*$"
                              (regexp-quote source-lang))))
      (with-current-buffer buf
        (org-mode)
        (save-excursion
          (goto-char (point-min))
          ;; Locate or create the section.
          (cond
           ((re-search-forward heading-re nil t)
            ;; Replace existing — delete from heading through end of subtree.
            (beginning-of-line)
            (let ((start (point))
                  (end (save-excursion (org-end-of-subtree t t) (point))))
              (delete-region start end)))
           (t
            ;; Append at end of buffer with separating blank line.
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (unless (looking-back "\n\n" 2) (insert "\n"))))
          ;; Insert the new section.
          (insert heading "\n")
          (insert ":PROPERTIES:\n")
          (insert (format ":LAST_TRANSLATED: %s\n"
                          (format-time-string "%Y-%m-%d")))
          (insert ":END:\n\n")
          (insert translation)
          (unless (string-suffix-p "\n" translation)
            (insert "\n"))))
      (with-current-buffer buf (save-buffer))
      t)))

;; ----------------------------------------------------------------------------
;; Fire function (orchestrates API call + writer)
;; ----------------------------------------------------------------------------

;; ----------------------------------------------------------------------------
;; Predicate (Phase A.1.5, 2026-04-30)
;; ----------------------------------------------------------------------------

(defun tibetan-dharmamitra-translation-needs-request-p
    (analysis-file &optional source-lang)
  "Return t when ANALYSIS-FILE lacks a populated DM translation section.

SOURCE-LANG defaults to `\"Tibetan\"'.

Returns:
  t   when the section `* DharmaMitra Translation (SOURCE-LANG)' is
      absent OR exists with empty / whitespace-only body
  nil when the section is present and populated, OR ANALYSIS-FILE
      is missing (caller can't write anyway)

Used by the existing-file open path so re-running `C-c u A' on a
file that already has a DM translation doesn't re-fire the API
unnecessarily.  Reanalysis (`C-c u R') bypasses this and always
refreshes."
  (let ((source-lang (or source-lang "Tibetan")))
    (when (and analysis-file
               (stringp analysis-file)
               (file-exists-p analysis-file))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (goto-char (point-min))
        (let ((heading-re (format "^\\* DharmaMitra Translation (%s)[ \t]*$"
                                  (regexp-quote source-lang))))
          (cond
           ;; Section absent → needs request.
           ((not (re-search-forward heading-re nil t))
            t)
           ;; Section present — check body.
           (t
            (forward-line 1)
            ;; Skip leading property drawer if any.
            (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
              (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                (forward-line 1)))
            (let* ((body-start (point))
                   (body-end
                    (or (save-excursion
                          (when (re-search-forward "^\\*+ " nil t)
                            (line-beginning-position)))
                        (point-max)))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (string-empty-p body)))))))))

;;;###autoload
(defun tibetan-dharmamitra-translation-needs-fire-on-open-p (analysis-file)
  "Return t when ANALYSIS-FILE needs ANY DharmaMitra section fired.

Specifically:  t when EITHER `* DharmaMitra Translation (Tibetan)'
OR `* DharmaMitra Translation (Sanskrit)' is missing or empty.

The umbrella `tibetan-dharmamitra-translation-fire-for-segment'
does internal per-language gating, so callers can fire the
umbrella whenever this predicate returns t — the populated side
is correctly skipped, the missing side is fired.

Bug fix 2026-05-04 (post-§5.18 layout-revision):  the existing-
file open path's DM auto-fire gate previously checked ONLY the
Tibetan side via `--needs-request-p filepath \"Tibetan\"'.  When
the Tibetan DM was populated (yesterday's run) but Sanskrit was
absent (DM Sanskrit fire missed), the gate returned nil and
`* DharmaMitra Translation (Sanskrit)' stayed permanently
missing.  This predicate triggers when EITHER side needs work."
  (or (tibetan-dharmamitra-translation-needs-request-p
       analysis-file "Tibetan")
      (tibetan-dharmamitra-translation-needs-request-p
       analysis-file "Sanskrit")))

;;;###autoload
(defun tibetan-dharmamitra-translation-fire-tibetan (tibetan-text analysis-file)
  "Translate TIBETAN-TEXT via DharmaMitra; write to ANALYSIS-FILE.

Calls `tibetan-dharmamitra-api-chat-translate' on TIBETAN-TEXT
with target-lang `english' and writes the result into the
analysis file's `* DharmaMitra Translation (Tibetan)' section.

No-op when:
  - TIBETAN-TEXT is nil / empty
  - chat-translate returns nil (HTTP error / empty response)

The latter avoids overwriting a previous good translation with
a failed one — same defensive pattern as Claude's restore path
(CLAUDE.md §6 — preserve user content).

Returns t on successful write, nil otherwise."
  (when (and tibetan-text
             (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text)))
             analysis-file)
    (let ((translation (tibetan-dharmamitra-api-chat-translate tibetan-text)))
      (when (and translation (not (string-empty-p translation)))
        (tibetan-dharmamitra-translation--write-section
         analysis-file translation "Tibetan")))))

;; ----------------------------------------------------------------------------
;; Sanskrit fire (Phase A.2, 2026-04-30)
;; ----------------------------------------------------------------------------

;;;###autoload
(defun tibetan-dharmamitra-translation-fire-sanskrit (sanskrit-text analysis-file)
  "Translate SANSKRIT-TEXT (IAST) via DharmaMitra; write result to
ANALYSIS-FILE's `* DharmaMitra Translation (Sanskrit)' section.

No-op when:
  - SANSKRIT-TEXT is empty / nil
  - SANSKRIT-TEXT is a Sanskrit-alignment placeholder marker
    recognised by
    `tibetan-sanskrit-parallel--placeholder-text-p'
    (`[Sanskrit alignment pending …]',
     `[Sanskrit alignment exhausted …]',
     `[No Sanskrit counterpart …]').  In practice the walker
    already returns nil for placeholders before we get here,
    but this defence-in-depth check guards against direct
    callers that bypass the walker.
  - chat-translate returns nil (HTTP error / empty response)

DM auto-detects the input encoding (IAST / Devanagari).  If
your sibling carries Devanagari instead of IAST, the same call
works — the function is encoding-agnostic.

Returns t on successful write, nil otherwise."
  (when (and sanskrit-text
             (stringp sanskrit-text)
             (not (string-empty-p (string-trim sanskrit-text)))
             (not (and (fboundp 'tibetan-sanskrit-parallel--placeholder-text-p)
                       (tibetan-sanskrit-parallel--placeholder-text-p
                        sanskrit-text)))
             analysis-file)
    (let ((translation (tibetan-dharmamitra-api-chat-translate sanskrit-text)))
      (when (and translation (not (string-empty-p translation)))
        (tibetan-dharmamitra-translation--write-section
         analysis-file translation "Sanskrit")))))

;; ----------------------------------------------------------------------------
;; Umbrella fire-for-segment — handles BOTH languages
;; ----------------------------------------------------------------------------

(declare-function tibetan-sanskrit-parallel-plist-for-segment-id
                  "tibetan-sanskrit-parallel" (source-file seg-id))

;;;###autoload
(defun tibetan-dharmamitra-translation-fire-for-segment
    (tibetan-text analysis-file &optional source-file seg-id)
  "Fire DharmaMitra translation(s) for a segment.

ALWAYS fires Tibetan translation when TIBETAN-TEXT is non-empty.

Additionally fires Sanskrit translation when:
  - SOURCE-FILE is non-nil
  - SOURCE-FILE has `#+SOURCE_MODE: parallel-sanskrit'
  - The segment SEG-ID has a `**** Sanskrit' sibling on the source
  - The sibling's IAST text is not a placeholder marker

Sanskrit gating is delegated to
`tibetan-sanskrit-parallel-plist-for-segment-id', which returns
nil for any of the above failures.

This is the call site's main entry point — replaces the
single-language `fire-tibetan' calls."
  ;; Tibetan path — always fires when text is present.
  (when (and tibetan-text
             (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text))))
    (tibetan-dharmamitra-translation-fire-tibetan tibetan-text analysis-file))
  ;; Sanskrit path — gated on parallel-mode + sibling-present.
  (when (and source-file seg-id
             (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id))
    (let ((skt-plist
           (condition-case nil
               (tibetan-sanskrit-parallel-plist-for-segment-id
                source-file seg-id)
             (error nil))))
      (when skt-plist
        (let ((iast (plist-get skt-plist :iast)))
          (when (and iast (stringp iast))
            (tibetan-dharmamitra-translation-fire-sanskrit
             iast analysis-file)))))))

(provide 'tibetan-dharmamitra-translation)
;;; tibetan-dharmamitra-translation.el ends here
