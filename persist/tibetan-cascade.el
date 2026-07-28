;;; tibetan-cascade.el --- CASCADE layout: sentence files with shad subsegments -*- lexical-binding: t -*-

;;; Commentary:
;;
;; CASCADE v2 (plan 2026-07-22, implementation started 2026-07-28):
;; for a document carrying `#+TIBETAN_LAYOUT: cascade' the sentence
;; file `sent-NNN-SHORT.org' is the ONLY persisted analysis artifact.
;; The shad-delimited units of the sentence live as nested subsegments
;; inside it (`* Subsegments' → `** Segment N', keyed by the source's
;; GLOBAL segment numbers), and every subsegment rendering is an
;; extracted ⟦N⟧-span of the whole-sentence translation — the
;; subsegment translation is always contained in the complete
;; sentence translation, by construction.
;;
;; The architectural point (preserve in commit messages): in cascade
;; mode NOTHING user-valuable is keyed to segment numbers — subsegment
;; shells are regenerable, so shad renumbering (the §5.26/§5.33 top
;; data-loss class) can no longer orphan anything.  Only sentence
;; numbers must stay stable.
;;
;; This module grows in stages:
;;   C1 (here)  — the pure shad-unit splitter.  The mode marker and
;;                `tibetan-analysis--cascade-p' predicate live in
;;                tibetan-analysis-claude.el beside --defer-mt-p.
;;   C2         — sent-file scaffold + subsegment subtree I/O +
;;                regenerate.
;;   C3         — sentence-level fire + response landing + span
;;                extraction into `*** Rendering'.
;;   C4         — dispatch/UX (open-at-segment, batches).
;;
;; Splitting at shads is DETERMINISTIC — mechanical, never wrong —
;; which is exactly why it is the subsegment generator: all linguistic
;; intelligence (main-verb recognition, verse grouping, speech frames)
;; stays at the sentence boundary.

;;; Code:

(defun tibetan-cascade-split-shad-units (text)
  "Split TEXT into its shad-terminated units.

Returns a list of strings whose CONCATENATION reproduces TEXT
exactly: each unit carries its terminating shad run — including
double shads `།།', the pecha-style spaced `། །', and any following
whitespace (so the next unit starts clean at its first content
character).  Text after the last shad, or text containing no shad at
all, forms a final (or only) unit — a fused segment like Khu-dbon's
seg-137 becomes one subsegment, never zero.

Recognised shads: ། (U+0F0D) and ༎ (U+0F0E).  Rarer marks (ter-shad
etc.) are treated as ordinary content — extend the character class
here if a corpus needs them.

Pure and deterministic; nil for nil / empty / whitespace-only input;
never signals."
  (when (and (stringp text)
             (not (string-empty-p (string-trim text))))
    (let ((units '())
          (start 0)
          (len (length text)))
      (while (< start len)
        (if (string-match
             "[།༎]+\\(?:[ \t\n]+[།༎]+\\)*[ \t\n]*" text start)
            (let ((end (match-end 0)))
              (push (substring text start end) units)
              (setq start end))
          ;; No further shad — the remainder is the final unit.
          (push (substring text start) units)
          (setq start len)))
      (nreverse units))))

;; ============================================================================
;; C2.1 — sent-file scaffold + create-file
;; ============================================================================

(defconst tibetan-cascade-rendering-placeholder
  "[Awaiting sentence translation…]"
  "Placeholder body of a subsegment's `*** Rendering' section.
Counts as needs-request: a subsegment whose Rendering still carries
this (or any `[…'-anchored placeholder) re-fires at SENTENCE level —
there is no per-segment fallback in cascade mode.")

(defun tibetan-cascade--extract-l2-body (content heading)
  "Body of `** HEADING' inside the renderer output CONTENT, or nil.
Bounds follow the §5.38-C1 discipline (stars-then-SPACE), so
markdown-bold body lines never truncate the section."
  (when (and content heading)
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* %s$" (regexp-quote heading)) nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                        (line-beginning-position)
                      (point-max)))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (unless (string-empty-p body) body))))))

(defun tibetan-cascade--extract-particles-body (content)
  "Body of the `*** Particles' subsection in CONTENT, or nil."
  (when content
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\*\\* Particles$" nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                        (line-beginning-position)
                      (point-max)))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (unless (string-empty-p body) body))))))

(defun tibetan-cascade--subsegment-block (seg-num ordinal text)
  "The `** Segment SEG-NUM' subtree for one shad unit (a string).
ORDINAL is the 1-based position inside the sentence — display /
bookkeeping only, never a file key (the GLOBAL segment number is the
key).  The four deterministic sections are extracted from one
segment-renderer pass over TEXT (★ Resources glosses, Steinert web
links, and Bialek particle bullets come along for free); when the
renderer is unavailable the Wylie/Phonetics fall back to the pure
converters and the rest degrade to visible markers."
  (let* ((content (and (fboundp 'tibetan-analysis-generate-content)
                       (condition-case nil
                           (tibetan-analysis-generate-content text)
                         (error nil))))
         (wylie (or (tibetan-cascade--extract-l2-body
                     content "Wylie Transliteration")
                    (and (fboundp 'tibetan-to-wylie-fixed)
                         (condition-case nil
                             (tibetan-to-wylie-fixed text)
                           (error nil)))
                    "[Wylie not available]"))
         (phonetics (or (tibetan-cascade--extract-l2-body
                         content "Phonetics")
                        (and (fboundp 'tibetan-to-phonetics)
                             (condition-case nil
                                 (tibetan-to-phonetics text)
                               (error nil)))
                        "[Phonetics not available]"))
         (gloss (or (tibetan-cascade--extract-l2-body
                     content "Interlinear Gloss")
                    "[Interlinear not available]"))
         (particles (or (tibetan-cascade--extract-particles-body content)
                        "[Particles not available]")))
    (concat (format "** Segment %d\n" seg-num)
            ":PROPERTIES:\n"
            (format ":SUBSEG: %d\n" ordinal)
            ":END:\n\n"
            (string-trim text) "\n\n"
            "*** Rendering\n" tibetan-cascade-rendering-placeholder "\n\n"
            "*** Wylie\n" (string-trim wylie) "\n\n"
            "*** Phonetics\n" (string-trim phonetics) "\n\n"
            "*** Interlinear Gloss\n" (string-trim gloss) "\n\n"
            "*** Particles\n" (string-trim particles) "\n\n")))

(defun tibetan-cascade--scaffold (sent-num segs source-file)
  "Return the full cascade sent-file body for SENT-NUM (a string).
SEGS is an ordered list of (GLOBAL-SEG-NUM . TEXT) conses — the
sentence's shad units as they appear in the source.  SOURCE-FILE is
the absolute source path (nil tolerated: no #+SOURCE header).

Layout: user slots on top, `* Tibetan Analysis' (sentence-level —
rendered through the compressed sentence renderer when available),
`* Subsegments' with one `** Segment N' subtree per unit, and
`* Footnotes' at the bottom.  The `#+TIBETAN_LAYOUT: cascade' header
marks the file for every reader (§2.8: explicit, never sniffed)."
  (let* ((source-name (and source-file
                           (file-name-nondirectory source-file)))
         (date (format-time-string "%Y-%m-%d"))
         (tibetan-text (mapconcat #'cdr segs ""))
         (hash (and (fboundp 'tibetan-sentence--compute-hash)
                    (condition-case nil
                        (tibetan-sentence--compute-hash tibetan-text)
                      (error nil))))
         (segs-csv (mapconcat (lambda (s) (number-to-string (car s)))
                              segs ", ")))
    (with-temp-buffer
      (insert (format "#+TITLE: Sentence %d Analysis\n" sent-num))
      (insert "#+STARTUP: showall\n")
      (insert "#+OPTIONS: toc:nil num:nil\n")
      (insert "#+TIBETAN_LAYOUT: cascade\n")
      (when source-name
        (insert (format
                 "#+SOURCE: [[file:../%s::*Sentence %d][%s / Sentence %d]]\n"
                 source-name sent-num source-name sent-num)))
      (insert (format "#+SEGMENTS: %s\n" segs-csv))
      (when hash
        (insert (format "#+TIBETAN_HASH: %s\n" hash)))
      (insert (format "#+CREATED: %s\n" date))
      (insert (format "#+LAST_ANALYZED: %s\n" date))
      (insert "\n")
      (insert "* My Notes\n\n\n")
      (insert "* Working Translation\n\n\n")
      (insert "* Tibetan Text\n")
      (insert (string-trim-right tibetan-text))
      (insert "\n\n")
      ;; Sentence-level analysis — compressed sentence renderer when
      ;; loaded (Claude Vocabulary / Translation / Grammar / Sentence
      ;; Structure / Concept Notes / Provided Translations), minimal
      ;; placeholders otherwise.
      (insert "* Tibetan Analysis\n")
      (insert ":PROPERTIES:\n:GENERATED: t\n:END:\n\n")
      (let ((auto (and (fboundp 'tibetan-sentence--render-auto-analysis)
                       (condition-case nil
                           (tibetan-sentence--render-auto-analysis
                            tibetan-text)
                         (error nil)))))
        (if auto
            (progn (insert auto)
                   (unless (string-suffix-p "\n" auto) (insert "\n")))
          (insert "** Translation\n[Requesting translation...]\n\n")
          (insert "** Provided Translations\n\n"))
        ;; The sentence-level DM fire lands in a nested slot — make
        ;; sure it exists whichever renderer path ran.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* DharmaMitra Translation$"
                                     nil t))
          (insert "** DharmaMitra Translation\n[Awaiting DharmaMitra…]\n\n")))
      ;; Subsegments — the cascade's replacement for seg files.
      (insert "* Subsegments\n\n")
      (let ((ordinal 0))
        (dolist (seg segs)
          (cl-incf ordinal)
          (insert (tibetan-cascade--subsegment-block
                   (car seg) ordinal (cdr seg)))))
      (insert "* Footnotes\n\n")
      (buffer-string))))

(defun tibetan-cascade--create-file (sent-num segs source-file)
  "Write the cascade sent file for SENT-NUM; return its path.
SEGS as in `tibetan-cascade--scaffold'.  The path comes from the
suffix-aware `tibetan-sentence--filepath' (cascade files KEEP the
`sent-NNN-SHORT.org' name — every resolver/glob/batch works
unchanged); falls back to a bare `sent-NNN.org' beside
SOURCE-FILE when the sentence module is not loaded."
  (let* ((folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (filepath (if (fboundp 'tibetan-sentence--filepath)
                       ;; Explicit FOLDER: the sentence module's default
                       ;; derivation needs the source BUFFER current,
                       ;; which batch/cascade callers don't guarantee.
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder)))
         (body (tibetan-cascade--scaffold sent-num segs source-file)))
    (make-directory (file-name-directory filepath) t)
    (with-temp-file filepath
      (insert body))
    filepath))

;; ============================================================================
;; C2.2 — subsegment subtree I/O (keyed by GLOBAL segment number)
;; ============================================================================

(defun tibetan-cascade--subsegment-bounds (seg-num)
  "In the current buffer: (START . END) of `** Segment SEG-NUM' under
`* Subsegments', or nil.  END stops at the next L1/L2 heading (§5.38-C1
stars-then-space) or at the * Subsegments region's end."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^\\* Subsegments$" nil t)
      (let ((limit (save-excursion
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
        (when (re-search-forward
               (format "^\\*\\* Segment %d$" seg-num) limit t)
          (let ((start (line-beginning-position))
                (end (if (re-search-forward "^\\*\\{1,2\\} " limit t)
                         (line-beginning-position)
                       limit)))
            (cons start end)))))))

(defun tibetan-cascade--subsegment-numbers (file)
  "Ordered list of GLOBAL segment numbers under FILE's * Subsegments.
nil for nil / missing / non-cascade files; never signals."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward "^\\* Subsegments$" nil t)
            (let ((limit (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max))))
                  (nums '()))
              (while (re-search-forward
                      "^\\*\\* Segment \\([0-9]+\\)$" limit t)
                (push (string-to-number (match-string 1)) nums))
              (nreverse nums))))
      (error nil))))

(defun tibetan-cascade--read-subsegment-section (file seg-num heading)
  "Body of `*** HEADING' inside FILE's `** Segment SEG-NUM' subtree.
Trimmed string, or nil when the subsegment or heading is absent /
the body is empty.  Placeholders are returned verbatim — use
`tibetan-cascade--subsegment-rendering-needs-request-p' for gating."
  (when (and file (stringp file) (file-exists-p file) heading)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (let ((bounds (tibetan-cascade--subsegment-bounds seg-num)))
            (when bounds
              (save-restriction
                (narrow-to-region (car bounds) (cdr bounds))
                (goto-char (point-min))
                (when (re-search-forward
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       nil t)
                  (forward-line 1)
                  (let* ((start (point))
                         (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                                  (line-beginning-position)
                                (point-max)))
                         (body (string-trim
                                (buffer-substring-no-properties
                                 start end))))
                    (unless (string-empty-p body) body)))))))
      (error nil))))

(defun tibetan-cascade--write-subsegment-section (file seg-num heading body)
  "Replace the body of `*** HEADING' in FILE's `** Segment SEG-NUM'.
Returns t on success; nil (file untouched) when the subsegment or
heading is absent.  BODY is inserted verbatim — the C3 landing path
sanitizes Claude-derived text (line-leading `*', §5.28 class) BEFORE
calling this primitive."
  (when (and file (stringp file) (file-exists-p file) heading body)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (let ((bounds (tibetan-cascade--subsegment-bounds seg-num))
                (done nil))
            (when bounds
              (save-restriction
                (narrow-to-region (car bounds) (cdr bounds))
                (goto-char (point-min))
                (when (re-search-forward
                       (format "^\\*\\*\\* %s$" (regexp-quote heading))
                       nil t)
                  (forward-line 1)
                  (let ((start (point))
                        (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                                 (line-beginning-position)
                               (point-max))))
                    (delete-region start end)
                    (goto-char start)
                    (insert (string-trim-right body) "\n\n")
                    (setq done t)))))
            (when done
              (write-region (point-min) (point-max) file nil 'silent)
              t)))
      (error nil))))

(defun tibetan-cascade--subsegment-rendering-needs-request-p (file seg-num)
  "Non-nil when SEG-NUM's `*** Rendering' still needs the sentence fire.
Missing body, the creation placeholder, or a failure/missing stub all
count.  Deliberately NOT `[`-anchored wholesale: a real extracted span
may open with an editorial bracket (`[He] spoke…' — the §5.40 lesson),
so only the known machine prefixes gate."
  (let ((body (tibetan-cascade--read-subsegment-section
               file seg-num "Rendering")))
    (or (null body)
        (string-match-p "\\`\\[Awaiting" body)
        (string-match-p "\\`\\[Claude" body)
        (string-match-p "\\`\\[Requesting" body))))

(provide 'tibetan-cascade)
;;; tibetan-cascade.el ends here
