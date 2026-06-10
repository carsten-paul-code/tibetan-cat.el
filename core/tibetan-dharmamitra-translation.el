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
;; Untrusted-text sanitiser
;; ----------------------------------------------------------------------------

(defun tibetan-dharmamitra-translation--sanitize-body (text)
  "Neutralise org structural markers in untrusted TEXT before it is
inserted into an analysis buffer.

DharmaMitra responses are network/LLM text.  A body line beginning with
`*' would otherwise become a top-level org heading mid-file — silently
restructuring the document and confusing later regenerate passes that
treat top-level headings as section boundaries.  Prefix any line-leading
run of `*' with a space so the line renders as body text / a list item
instead of a heading.  Returns TEXT unchanged when it carries no such
line; nil-safe."
  (if (stringp text)
      (replace-regexp-in-string "^\\(\\*+\\)" " \\1" text)
    text))

;; ----------------------------------------------------------------------------
;; Writer
;; ----------------------------------------------------------------------------

(defun tibetan-dharmamitra-translation--write-nested-tibetan-section
    (analysis-file translation)
  "Write the DharmaMitra Tibetan TRANSLATION into the level-2
`** DharmaMitra Translation' section inside `* Tibetan Analysis'.

The renderer emits a `** DharmaMitra Translation\\n[Awaiting…]'
placeholder during analysis generation;  this writer locates the
placeholder and replaces its body with the real translation, plus
a `:PROPERTIES:' drawer carrying `:LAST_TRANSLATED:'.

When the placeholder is absent (legacy files generated before
the 2026-05-19 layout revision), creates the heading immediately
after `** Translation' / `** Claude Translation' inside
`* Tibetan Analysis'.  When the parent is also absent, falls
back to top-level `* DharmaMitra Translation (Tibetan)' (the
pre-layout-revision behaviour) for safety.

Returns t on success, nil otherwise."
  (when (and analysis-file
             (stringp analysis-file)
             (file-exists-p analysis-file)
             (file-writable-p analysis-file)
             (stringp translation)
             (not (string-empty-p translation)))
    (let ((buf (find-file-noselect analysis-file)))
      (with-current-buffer buf
        (org-mode)
        (save-excursion
          (goto-char (point-min))
          ;; Migrate legacy top-level section if present:  read its
          ;; body, delete the section, and we'll re-insert at the
          ;; new location below.  Idempotent — no-op when absent.
          (tibetan-dharmamitra-translation--delete-legacy-toplevel-section
           buf "Tibetan")
          (goto-char (point-min))
          (cond
           ;; New layout:  level-2 placeholder under * Tibetan Analysis.
           ((re-search-forward
             "^\\*\\* DharmaMitra Translation[ \t]*$" nil t)
            ;; Replace from heading line through next ^** / ^* heading.
            (beginning-of-line)
            (let* ((start (point))
                   (end (save-excursion
                          (forward-line 1)
                          (if (re-search-forward
                               "^\\*\\{1,2\\}[^*\n]\\|^\\* " nil t)
                              (line-beginning-position)
                            (point-max)))))
              (delete-region start end)
              (goto-char start))
            (insert "** DharmaMitra Translation\n")
            (insert ":PROPERTIES:\n")
            (insert (format ":LAST_TRANSLATED: %s\n"
                            (format-time-string "%Y-%m-%d")))
            (insert ":END:\n\n")
            (insert (tibetan-dharmamitra-translation--sanitize-body translation))
            (unless (string-suffix-p "\n" translation) (insert "\n"))
            (insert "\n"))
           ;; New layout with no placeholder yet:  insert after
           ;; `** Translation' / `** Claude Translation' inside
           ;; `* Tibetan Analysis'.
           ((tibetan-dharmamitra-translation--insert-after-translation
             buf translation))
           ;; Fallback:  top-level (legacy / no Tibetan Analysis parent).
           (t
            (tibetan-dharmamitra-translation--write-toplevel-section
             buf translation "Tibetan")))))
      (with-current-buffer buf (save-buffer))
      t)))

(defun tibetan-dharmamitra-translation--delete-legacy-toplevel-section
    (buffer source-lang)
  "Delete any legacy top-level `* DharmaMitra Translation (SOURCE-LANG)'
section in BUFFER.  Idempotent — no-op when absent.  Used by the
Tibetan-side migration to clear the top-level section before
reinserting the body at the new nested location."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((heading-re (format "^\\* DharmaMitra Translation (%s)[ \t]*$"
                                (regexp-quote source-lang))))
        (when (re-search-forward heading-re nil t)
          (beginning-of-line)
          (let ((start (point))
                (end (save-excursion (org-end-of-subtree t t) (point))))
            (delete-region start end)
            t))))))

(defun tibetan-dharmamitra-translation--insert-after-translation
    (buffer translation)
  "Insert a fresh `** DharmaMitra Translation' block inside
`* Tibetan Analysis'.

Placement:
  (a) immediately after `** Translation' or `** Claude
      Translation' (whichever appears first) — the canonical
      side-by-side layout;
  (b) when no Translation sibling exists, at the end of the
      `* Tibetan Analysis' subtree — better than dropping the
      body or punting to top-level.

Returns t when `* Tibetan Analysis' is present, nil otherwise.
The caller falls back to top-level placement when this returns
nil."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Analysis$" nil t)
        (let* ((parent-end (save-excursion
                             (if (re-search-forward "^\\* " nil t)
                                 (line-beginning-position)
                               (point-max))))
               (after-trans-pos
                (save-excursion
                  (when (re-search-forward
                         "^\\*\\* \\(Translation\\|Claude Translation\\)[ \t]*$"
                         parent-end t)
                    (forward-line 1)
                    (if (re-search-forward "^\\*\\* " parent-end t)
                        (line-beginning-position)
                      parent-end))))
               (insert-pos (or after-trans-pos parent-end)))
          (goto-char insert-pos)
          (insert "** DharmaMitra Translation\n")
          (insert ":PROPERTIES:\n")
          (insert (format ":LAST_TRANSLATED: %s\n"
                          (format-time-string "%Y-%m-%d")))
          (insert ":END:\n\n")
          (insert (tibetan-dharmamitra-translation--sanitize-body translation))
          (unless (string-suffix-p "\n" translation) (insert "\n"))
          (insert "\n")
          t)))))

(defun tibetan-dharmamitra-translation--write-toplevel-section
    (buffer-or-file translation source-lang)
  "Write `* DharmaMitra Translation (SOURCE-LANG)' at top-level.

BUFFER-OR-FILE is either a buffer or a file path.  Used for
Sanskrit (which stays at top-level in parallel-Sanskrit mode)
and as a fallback for Tibetan in legacy files without a
`* Tibetan Analysis' parent.

Creates or replaces the section.  Body is TRANSLATION;  property
drawer carries `:LAST_TRANSLATED:' for freshness tracking."
  (let ((buf (if (bufferp buffer-or-file) buffer-or-file
               (find-file-noselect buffer-or-file)))
        (heading (format "* DharmaMitra Translation (%s)" source-lang))
        (heading-re (format "^\\* DharmaMitra Translation (%s)[ \t]*$"
                            (regexp-quote source-lang))))
    (with-current-buffer buf
      (org-mode)
      (save-excursion
        (goto-char (point-min))
        (cond
         ((re-search-forward heading-re nil t)
          (beginning-of-line)
          (let ((start (point))
                (end (save-excursion (org-end-of-subtree t t) (point))))
            (delete-region start end)))
         (t
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (unless (looking-back "\n\n" 2) (insert "\n"))))
        (insert heading "\n")
        (insert ":PROPERTIES:\n")
        (insert (format ":LAST_TRANSLATED: %s\n"
                        (format-time-string "%Y-%m-%d")))
        (insert ":END:\n\n")
        (insert (tibetan-dharmamitra-translation--sanitize-body translation))
        (unless (string-suffix-p "\n" translation) (insert "\n"))))
    t))

(defun tibetan-dharmamitra-translation--write-section
    (analysis-file translation source-lang)
  "Dispatch the DharmaMitra writer based on SOURCE-LANG.

Tibetan side (`source-lang' = \"Tibetan\") writes into the
level-2 `** DharmaMitra Translation' inside `* Tibetan Analysis',
sitting as a peer of `** Translation' (the Claude rendering).
Sanskrit side stays at top-level `* DharmaMitra Translation
\(Sanskrit)' for parallel-mode workflow symmetry with the legacy
Sanskrit pipeline.

Returns t on success, nil otherwise."
  (when (and analysis-file
             (stringp analysis-file)
             (file-exists-p analysis-file)
             (file-writable-p analysis-file)
             (stringp translation)
             (not (string-empty-p translation))
             (stringp source-lang)
             (not (string-empty-p source-lang)))
    (cond
     ((string= source-lang "Tibetan")
      (tibetan-dharmamitra-translation--write-nested-tibetan-section
       analysis-file translation))
     (t
      (tibetan-dharmamitra-translation--write-toplevel-section
       analysis-file translation source-lang)
      (with-current-buffer (find-file-noselect analysis-file)
        (save-buffer))
      t))))

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

Heading location (matters — write/read must agree):
  - Tibetan side:  since §5.20 (2026-05-19) the writer puts the
    translation in the NESTED level-2 `** DharmaMitra Translation'
    inside `* Tibetan Analysis'.  This predicate therefore checks
    that heading FIRST, and accepts the legacy top-level
    `* DharmaMitra Translation (Tibetan)' for unmigrated files.
    (Before this fix it checked ONLY the legacy top-level heading,
    never matched the nested section the writer actually fills, and
    so always returned t — re-firing DM on every file open.)
  - Other languages (Sanskrit):  top-level
    `* DharmaMitra Translation (SOURCE-LANG)'.

A body that is empty OR a `[Awaiting…' / `[Requesting…' placeholder
counts as still-needing, so a freshly-rendered file (which carries the
`[Awaiting DharmaMitra…]' placeholder) is correctly filled.

Used by the existing-file open path so re-running `C-c u A' on a
file that already has a DM translation doesn't re-fire the API
unnecessarily.  Explicit reanalysis (`C-c u R') passes FORCE to
`tibetan-dharmamitra-translation-fire-for-segment' to refresh anyway."
  (let ((source-lang (or source-lang "Tibetan")))
    (when (and analysis-file
               (stringp analysis-file)
               (file-exists-p analysis-file))
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((heading-res
               (if (string= source-lang "Tibetan")
                   '("^\\*\\* DharmaMitra Translation[ \t]*$"
                     "^\\* DharmaMitra Translation (Tibetan)[ \t]*$")
                 (list (format "^\\* DharmaMitra Translation (%s)[ \t]*$"
                               (regexp-quote source-lang))))))
          (catch 'done
            (dolist (heading-re heading-res)
              (goto-char (point-min))
              (when (re-search-forward heading-re nil t)
                ;; Section present — decide from its body.
                (forward-line 1)
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
                  (throw 'done
                         (or (string-empty-p body)
                             (string-prefix-p "[Awaiting" body)
                             (string-prefix-p "[Requesting" body))))))
            ;; No candidate heading found → section absent → needs request.
            t))))))

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
    (tibetan-text analysis-file &optional source-file seg-id force)
  "Fire DharmaMitra translation(s) for a segment.

Fires the Tibetan translation when TIBETAN-TEXT is non-empty AND
either FORCE is non-nil OR the Tibetan DM section is empty / a
placeholder (`tibetan-dharmamitra-translation-needs-request-p').  In
other words a POPULATED Tibetan DM section is left alone unless FORCE
is given — this is what stops the request storm on file open, where
the segment already has a DM translation.  Pass FORCE non-nil from the
explicit-refresh path (`C-c u R').

Additionally fires Sanskrit translation when:
  - SOURCE-FILE is non-nil
  - SOURCE-FILE has `#+SOURCE_MODE: parallel-sanskrit'
  - The segment SEG-ID has a `**** Sanskrit' sibling on the source
  - The sibling's IAST text is not a placeholder marker
  - FORCE is non-nil OR the Sanskrit DM section needs a request

Sanskrit parallel-mode gating is delegated to
`tibetan-sanskrit-parallel-plist-for-segment-id', which returns
nil for any of the above failures.

This is the call site's main entry point — replaces the
single-language `fire-tibetan' calls."
  ;; Tibetan path — fire only when forced or the section needs it, so a
  ;; populated DM translation is not silently re-requested on open.
  (when (and tibetan-text
             (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text)))
             (or force
                 (tibetan-dharmamitra-translation-needs-request-p
                  analysis-file "Tibetan")))
    (tibetan-dharmamitra-translation-fire-tibetan tibetan-text analysis-file))
  ;; Sanskrit path — gated on parallel-mode + sibling-present, and on
  ;; the Sanskrit section needing a request (unless forced).
  (when (and source-file seg-id
             (fboundp 'tibetan-sanskrit-parallel-plist-for-segment-id)
             (or force
                 (tibetan-dharmamitra-translation-needs-request-p
                  analysis-file "Sanskrit")))
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

(defun tibetan-dharmamitra-translation-fire-tibetan-sentence
    (sentence-text sent-num seg-nums child-files sent-file &optional force)
  "Fire ONE DharmaMitra translation for a whole SENTENCE (§5.40).
SENTENCE-TEXT is the concatenated sentence; SENT-NUM / SEG-NUMS
identify it; CHILD-FILES are the child seg-NNN.org paths and
SENT-FILE the sent-NNN.org path (nil to skip).  The full sentence
translation is written into EVERY child's nested `** DharmaMitra
Translation' slot AND the sent file, under a `(Sentence N — segments
A–B)' label that travels INSIDE the body (so the §5.28 sanitizer and
the §5.20 preserve machinery handle it untouched).

Fire gate: FORCE, or ANY child still needs a DM request.  Landing
gate per file: FORCE or that file needs it — a populated section is
never overwritten by a non-FORCE fire (§5.29 policy).  An empty API
response writes nothing (preserve pattern, like --fire-tibetan)."
  (when (and sentence-text (stringp sentence-text)
             (not (string-empty-p (string-trim sentence-text)))
             child-files
             (or force
                 (cl-some (lambda (f)
                            (tibetan-dharmamitra-translation-needs-request-p
                             f "Tibetan"))
                          child-files)))
    (let ((translation
           (condition-case err
               (tibetan-dharmamitra-api-chat-translate sentence-text)
             (error
              (message "DharmaMitra sentence request failed (Sentence %s): %s"
                       sent-num (error-message-string err))
              nil))))
      (when (and translation (stringp translation)
                 (not (string-empty-p (string-trim translation))))
        (let ((body (format "(Sentence %s — segments %s–%s)\n\n%s"
                            sent-num
                            (apply #'min seg-nums) (apply #'max seg-nums)
                            (string-trim translation))))
          (dolist (f (append child-files (and sent-file (list sent-file))))
            (when (and f (file-exists-p f)
                       (or force
                           (tibetan-dharmamitra-translation-needs-request-p
                            f "Tibetan")))
              (tibetan-dharmamitra-translation--write-nested-tibetan-section
               f body)))
          t)))))

(provide 'tibetan-dharmamitra-translation)
;;; tibetan-dharmamitra-translation.el ends here
