;;; tibetan-analysis-combine.el --- Combine segment analyses into one file -*- lexical-binding: t -*-

;;; Commentary:
;; Produces a single `analysis/combined.org' document that stitches
;; together every `seg-NNN*.org' in the analysis folder, in segment
;; order, with a slim per-segment body:
;;
;;   * Segment N — ⟨Tibetan snippet⟩
;;   ** Tibetan Text
;;   ** Wylie Transliteration
;;   ** Particle Map
;;   ** Interlinear Gloss
;;   ** Verb Classification (Hill 2010)
;;   ** Claude Translation
;;   ** Claude Grammar
;;
;; Followed by a consolidated appendix:
;;
;;   * Appendix A — Grammatical Markers
;;   * Appendix B — Detailed Dictionary
;;
;; Each appendix entry carries back-references to the segments it
;; appeared in, so a reader can jump from a curated entry to every
;; place where that marker / word surfaces in the corpus.
;;
;; Public entry points:
;;
;;   M-x tibetan-analysis-combine-document         (bound to C-c u C)
;;       Build / rebuild `combined.org' in the analysis folder of the
;;       current source file and open it in a side window.

;;; Code:

(require 'cl-lib)
(require 'tibetan-analysis-persist)

;; Forward declarations (defined in tibetan-analysis-persist.el).
(declare-function tibetan-analysis-get-folder "tibetan-analysis-persist" ())
(declare-function tibetan-analysis--folder-analysis-files
                  "tibetan-analysis-persist" (folder))
(declare-function tibetan-analysis--seg-id-from-filename
                  "tibetan-analysis-persist" (filepath))
(declare-function tibetan-analysis--split-level2-sections
                  "tibetan-analysis-persist" (content))
(declare-function tibetan-analysis--read-section-body
                  "tibetan-analysis-persist" (filepath section-name))
(declare-function tibetan-analysis--filter-to-tibetan-lines
                  "tibetan-analysis-persist" (text))

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defconst tibetan-analysis-combine--per-segment-order
  '("** Tibetan Text"
    "** Wylie Transliteration"
    "** Particle Map"
    "** Interlinear Gloss"
    "** Verb Classification (Hill 2010)"
    "** Claude Translation"
    "** Claude Grammar")
  "Level-2 section headings (in display order) that each segment
block in `combined.org' reproduces.  `** Tibetan Text' is sourced
from the analysis file's top-level `* Tibetan Text' section and
downleveled to `**' for the combined output; the rest are copied
verbatim from the per-segment `* Auto-Analysis' subtree.")

(defconst tibetan-analysis-combine--appendix-section-names
  '("** Grammatical Markers" "** Detailed Dictionary")
  "Section headings whose bodies are collected across all segments
and consolidated into the combined document's appendix.")

(defvar tibetan-analysis-combine--snippet-max 40
  "Maximum length of the Tibetan snippet appended to each segment
heading in the combined document, in characters.")

;; ============================================================================
;; SEGMENT PARSING
;; ============================================================================

(defun tibetan-analysis-combine--read-auto-sections (filepath)
  "Return the list of (HEADING . BODY) cons cells inside the
`* Auto-Analysis' subtree of FILEPATH.  Nil if the file is missing
or has no auto-analysis subtree."
  (when (file-exists-p filepath)
    (let ((content (with-temp-buffer
                     (insert-file-contents filepath)
                     (goto-char (point-min))
                     (when (re-search-forward "^\\* Auto-Analysis" nil t)
                       (let ((start (1+ (match-end 0)))
                             (end (or (save-excursion
                                        (when (re-search-forward
                                               "^\\* " nil t)
                                          (match-beginning 0)))
                                      (point-max))))
                         (buffer-substring-no-properties start end))))))
      (when content
        (cdr (tibetan-analysis--split-level2-sections content))))))

(defun tibetan-analysis-combine--tibetan-text (filepath)
  "Return the body of `* Tibetan Text' in FILEPATH (trimmed, filtered).

The raw body often interleaves Tibetan with non-Tibetan cruft that
should never surface in the combined document:

  - Org `#+TITLE:' / `#+AUTHOR:' / `#+TIBETAN_CLAUDE_CONTEXT:'
    headers captured inside a segment when the `〔seg:N〕' marker
    was placed above the source-file preamble.
  - `#'-prefixed editorial / OCR comments.
  - Blank separators.

We reuse `tibetan-analysis--filter-to-tibetan-lines' (the same
pre-parser sanitiser the per-segment generator runs) to keep only
lines that contain at least one Tibetan character.  Returns nil
when the filtered result is empty — the caller uses that to decide
whether the segment should be rendered at all."
  (let ((raw (tibetan-analysis--read-section-body filepath "Tibetan Text")))
    (when raw
      (let ((filtered (tibetan-analysis--filter-to-tibetan-lines
                       (string-trim raw))))
        (when (and filtered (not (string-empty-p (string-trim filtered))))
          filtered)))))

(defun tibetan-analysis-combine--snippet (text)
  "Return a one-line snippet of TEXT suitable for a heading suffix.
Only Tibetan-script characters are kept (non-Tibetan lines are
dropped so OCR-comment debris never surfaces), and the result is
truncated to `tibetan-analysis-combine--snippet-max' characters
with a trailing ellipsis when longer."
  (when text
    (let* ((tib-only
            (mapconcat
             #'identity
             (cl-remove-if-not
              (lambda (ln) (string-match-p "[ༀ-࿿]" ln))
              (split-string text "\n"))
             " "))
           (one-line (string-trim
                      (replace-regexp-in-string "[ \t]+" " " tib-only))))
      (if (> (length one-line) tibetan-analysis-combine--snippet-max)
          (concat (substring one-line 0
                             tibetan-analysis-combine--snippet-max)
                  "…")
        one-line))))

(defun tibetan-analysis-combine--render-segment (filepath seg-id)
  "Return a string containing the combined-doc block for one segment,
or nil when the segment has no Tibetan content to render.

FILEPATH points at the seg-NNN*.org file, SEG-ID is the numeric id.

A segment is skipped when `tibetan-analysis-combine--tibetan-text'
returns nil (the `* Tibetan Text' body had no Tibetan characters
once non-Tibetan lines were filtered out).  This typically happens
for seg-001 in sources where the `〔seg:1〕' marker sits above the
#+TITLE / #+AUTHOR / #+TIBETAN_CLAUDE_CONTEXT preamble — the
segment captures the preamble but no actual passage, so including
it in the combined document would only produce a run of
`[Not available]' placeholders."
  (let* ((tibetan (tibetan-analysis-combine--tibetan-text filepath))
         (sections (tibetan-analysis-combine--read-auto-sections filepath))
         (snippet (tibetan-analysis-combine--snippet tibetan)))
    (when tibetan
      (with-temp-buffer
        (insert (format "* Segment %d%s\n"
                        seg-id
                        (if (and snippet (not (string-empty-p snippet)))
                            (concat " — " snippet)
                          "")))
        (dolist (heading tibetan-analysis-combine--per-segment-order)
          (cond
           ;; Tibetan Text comes from the top-level * Tibetan Text.
           ((string= heading "** Tibetan Text")
            (insert "** Tibetan Text\n")
            (insert tibetan)
            (insert "\n\n"))
           ;; The others come from the auto-analysis sections map.
           (t
            (let ((body (cdr (assoc heading sections))))
              (insert heading "\n")
              (if (and body (not (string-empty-p (string-trim body))))
                  (insert (string-trim-right body) "\n\n")
                (insert "[Not available]\n\n"))))))
        (buffer-string)))))

;; ============================================================================
;; APPENDIX COLLECTION AND DEDUP
;; ============================================================================

(defun tibetan-analysis-combine--collect-appendix-bodies
    (analysis-files heading)
  "Walk ANALYSIS-FILES and return a list of (SEG-ID . BODY) for every
occurrence of HEADING (a level-2 heading string like
`** Grammatical Markers').  Empty bodies are skipped."
  (let ((out '()))
    (dolist (f analysis-files)
      (let* ((sid (tibetan-analysis--seg-id-from-filename f))
             (sections (tibetan-analysis-combine--read-auto-sections f))
             (body (cdr (assoc heading sections))))
        (when (and body
                   (not (string-empty-p (string-trim body))))
          (push (cons sid (string-trim body)) out))))
    (nreverse out)))

(defun tibetan-analysis-combine--split-grammatical-entries (body)
  "Split a Grammatical Markers BODY into individual bullet entries.

The renderer emits markers as a bulleted list:

    - དེ [de] in «...» → CONVERBIAL: COORDINATIVE … [Portfolio §2.4]
    - ལ [la] in «...» → DATIVE (DAT) …
    - …

We split on `^- ' so each particle annotation becomes its own entry,
which lets the dedup collapse common markers (every `ལ DATIVE' hit
across the corpus folds into a single appendix line with all the
source segment ids).  Continuation lines (indented lines belonging
to the previous bullet) are attached to whichever bullet preceded
them.  Empty or whitespace-only entries are dropped."
  (let ((entries '())
        (current nil))
    (dolist (line (split-string body "\n"))
      (cond
       ;; Bullet start — finalise the previous entry (if any) and
       ;; begin a new one.
       ((string-match-p "^-[ \t]" line)
        (when current
          (push (string-trim (mapconcat #'identity
                                        (nreverse current) "\n"))
                entries))
        (setq current (list line)))
       ;; Continuation of the current entry.
       (current
        (push line current))
       ;; Text before the first bullet — treat as its own entry if
       ;; non-empty (so we don't silently swallow prefatory prose).
       ((not (string-empty-p (string-trim line)))
        (push (string-trim line) entries))))
    (when current
      (push (string-trim (mapconcat #'identity (nreverse current) "\n"))
            entries))
    (cl-remove-if (lambda (p) (string-empty-p (string-trim p)))
                  (nreverse entries))))

(defun tibetan-analysis-combine--split-detailed-entries (body)
  "Split a Detailed Dictionary BODY into individual `◆'-prefixed
entries.  Text before the first `◆' is dropped (typically empty)."
  (let* ((pieces (split-string body "^◆" t))
         (result '()))
    (dolist (p pieces)
      (let ((trimmed (string-trim p)))
        (unless (string-empty-p trimmed)
          (push (concat "◆ " trimmed) result))))
    (nreverse result)))

(defun tibetan-analysis-combine--entry-key (entry)
  "Return a stable dedup KEY for ENTRY.
For a Detailed Dictionary entry `◆ word [wylie] …' the key is the
`◆ word' head line.  For a Grammatical Markers entry the key is
the first non-empty line trimmed."
  (let ((first-line (car (split-string entry "\n" t))))
    (string-trim first-line)))

(defun tibetan-analysis-combine--dedup-entries (per-seg-bodies splitter)
  "Dedup entries extracted from PER-SEG-BODIES by entry key.
PER-SEG-BODIES is the list returned by
`tibetan-analysis-combine--collect-appendix-bodies'.
SPLITTER is a function that converts one body string into a list of
entry strings (e.g. `--split-grammatical-entries').

Returns a list of plists in encounter order:
  (:key KEY :entry ENTRY :segments (SEG-ID ...))
SEG-IDs are sorted numerically ascending and deduplicated."
  (let ((table (make-hash-table :test 'equal))
        (order '()))
    (dolist (pair per-seg-bodies)
      (let ((sid (car pair))
            (body (cdr pair)))
        (dolist (entry (funcall splitter body))
          (let* ((key (tibetan-analysis-combine--entry-key entry))
                 (existing (gethash key table)))
            (if existing
                (unless (member sid (plist-get existing :segments))
                  (puthash key
                           (plist-put existing :segments
                                      (sort (cons sid
                                                  (plist-get existing
                                                             :segments))
                                            #'<))
                           table))
              (puthash key
                       (list :key key :entry entry :segments (list sid))
                       table)
              (push key order))))))
    (let ((out '()))
      (dolist (k (nreverse order))
        (push (gethash k table) out))
      (nreverse out))))

(defun tibetan-analysis-combine--render-appendix (title entries)
  "Render TITLE (a full `* Appendix X — …' heading) followed by the
rendered ENTRIES list.  Each entry shows its body and a
`(segments: 3, 7, 12)' trailer."
  (with-temp-buffer
    (insert title "\n\n")
    (if entries
        (dolist (e entries)
          (let ((body (plist-get e :entry))
                (sids (plist-get e :segments)))
            (insert (string-trim-right body) "\n")
            (insert (format "(segments: %s)\n\n"
                            (mapconcat #'number-to-string sids ", ")))))
      (insert "[No entries across any segment]\n\n"))
    (buffer-string)))

;; ============================================================================
;; MAIN COMMAND
;; ============================================================================

;;;###autoload
(defun tibetan-analysis-combine-document (&optional folder)
  "Build `analysis/combined.org' by stitching together every
`seg-NNN*.org' file in FOLDER, using the same priority section
order as the per-segment analysis view and appending a
consolidated dictionary and grammatical-markers appendix.

Interactive: FOLDER defaults to the analysis folder of the current
source file (via `tibetan-analysis-get-folder').  A universal
prefix argument prompts for the folder instead.

Writes `combined.org' in the folder and opens it in a side window."
  (interactive
   (list (if current-prefix-arg
             (read-directory-name "Analysis folder: ")
           nil)))
  (let* ((folder (or folder (tibetan-analysis-get-folder)))
         (files (tibetan-analysis--folder-analysis-files folder))
         (output-path (expand-file-name "combined.org" folder)))
    (unless files
      (user-error "No seg-NNN*.org files found in %s" folder))
    (let ((included 0) (skipped 0))
      (with-temp-file output-path
        (insert "#+TITLE: Combined Segment Analyses\n")
        (insert (format "#+GENERATED: %s\n"
                        (format-time-string "%Y-%m-%d %H:%M:%S")))
        (insert (format "#+SEGMENT_COUNT: %d\n" (length files)))
        (insert "#+STARTUP: showall\n")
        ;; Export directives: no table of contents, no section numbers.
        ;; With 200+ per-segment top-level headings a TOC would fill
        ;; the first several pages of any exported PDF / HTML with a
        ;; list the reader already knows.
        (insert "#+OPTIONS: toc:nil num:nil\n\n")
        (insert "* Overview\n\n")
        (insert (format "Generated from %d segment files under =%s=.\n\n"
                        (length files) folder))
        (insert "This document is regenerated by =M-x ")
        (insert "tibetan-analysis-combine-document= (bound to =C-c u C=).  ")
        (insert "Edit the per-segment =seg-NNN.org= files, not this one — ")
        (insert "changes here are overwritten on next rebuild.\n\n")
        ;; Per-segment blocks — segments whose `* Tibetan Text' has no
        ;; Tibetan content (preamble-only, common on seg-001) are
        ;; silently dropped so the combined doc stays signal-heavy.
        (dolist (f files)
          (let* ((sid (or (tibetan-analysis--seg-id-from-filename f) 0))
                 (block (tibetan-analysis-combine--render-segment f sid)))
            (if block
                (progn (insert block) (insert "\n")
                       (cl-incf included))
              (cl-incf skipped))))
      ;; Appendix A — Grammatical Markers
      (let* ((gm-bodies (tibetan-analysis-combine--collect-appendix-bodies
                         files "** Grammatical Markers"))
             (gm-entries (tibetan-analysis-combine--dedup-entries
                          gm-bodies
                          #'tibetan-analysis-combine--split-grammatical-entries)))
        (insert (tibetan-analysis-combine--render-appendix
                 "* Appendix A — Grammatical Markers"
                 gm-entries)))
      ;; Appendix B — Detailed Dictionary
      (let* ((dd-bodies (tibetan-analysis-combine--collect-appendix-bodies
                         files "** Detailed Dictionary"))
             (dd-entries (tibetan-analysis-combine--dedup-entries
                          dd-bodies
                          #'tibetan-analysis-combine--split-detailed-entries)))
        (insert (tibetan-analysis-combine--render-appendix
                 "* Appendix B — Detailed Dictionary"
                 dd-entries))))
      (message
       (if (> skipped 0)
           (format "Combined document: %s (%d segment%s, %d skipped — no Tibetan content)"
                   output-path
                   included (if (= included 1) "" "s")
                   skipped)
         (format "Combined document: %s (%d segments)"
                 output-path included)))
      (let ((buf (find-file-noselect output-path)))
        (display-buffer-in-side-window
         buf '((side . right) (window-width . 0.5)))
        buf))))

(provide 'tibetan-analysis-combine)
;;; tibetan-analysis-combine.el ends here
