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

(provide 'tibetan-dharmamitra-translation)
;;; tibetan-dharmamitra-translation.el ends here
