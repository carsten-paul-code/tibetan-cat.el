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

(defun tibetan-cascade--write-subsegment-section-in-buffer
    (seg-num heading body)
  "Buffer-local core of `tibetan-cascade--write-subsegment-section'.
Replaces the body of `*** HEADING' inside the `** Segment SEG-NUM'
subtree of the CURRENT buffer.  Returns t when replaced."
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
    done))

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
          (when (tibetan-cascade--write-subsegment-section-in-buffer
                 seg-num heading body)
            (write-region (point-min) (point-max) file nil 'silent)
            t))
      (error nil))))

;; ============================================================================
;; C2.3 — regenerate with preservation (the §5.26 discipline)
;; ============================================================================

(defconst tibetan-cascade--known-l1-sections
  '("My Notes" "Working Translation" "Tibetan Text" "Tibetan Analysis"
    "Subsegments" "Footnotes")
  "The L1 headings the cascade scaffold owns.  Anything else found in
an existing file is preserved verbatim across regenerate
\(§5.38-H2: preserve-by-default, never a whitelist wipe).")

(defun tibetan-cascade--read-l1-body (file heading)
  "Trimmed body of `* HEADING' in FILE (bounded at the next L1
heading, so the user's own sub-structure inside survives), or nil
when absent / empty."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\* %s$" (regexp-quote heading)) nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (if (re-search-forward "^\\* " nil t)
                            (line-beginning-position)
                          (point-max)))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (string-empty-p body) body))))
      (error nil))))

(defun tibetan-cascade--read-l3-body (file heading)
  "Trimmed body of the (unique) `*** HEADING' in FILE, or nil.
Used for the sentence-level `*** Claude Grammar' — subsegments never
carry that heading, so a file-wide search is unambiguous."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*\\*\\* %s$" (regexp-quote heading)) nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (if (re-search-forward "^\\*\\{1,3\\} " nil t)
                            (line-beginning-position)
                          (point-max)))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (or (string-empty-p body)
                          (string-match-p "\\`\\[Awaiting" body))
                body))))
      (error nil))))

(defun tibetan-cascade--collect-unknown-l1-sections (file)
  "List of verbatim L1 subtrees in FILE whose headings the scaffold
does not own (`tibetan-cascade--known-l1-sections')."
  (when (and file (stringp file) (file-exists-p file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (let ((subtrees '()))
            (while (re-search-forward "^\\* \\(.+\\)$" nil t)
              (let ((heading (string-trim (match-string 1)))
                    (start (line-beginning-position)))
                (unless (member heading tibetan-cascade--known-l1-sections)
                  (let ((end (save-excursion
                               (if (re-search-forward "^\\* " nil t)
                                   (line-beginning-position)
                                 (point-max)))))
                    (push (buffer-substring-no-properties start end)
                          subtrees)))))
            (nreverse subtrees)))
      (error nil))))

(defun tibetan-cascade--set-body-in-buffer (level heading body)
  "Replace the body of the first LEVEL-star HEADING in the current
buffer (skipping a :PROPERTIES: drawer; bounded at the next heading
of level ≤ LEVEL, so a subtree body keeps its children).  Returns t
when replaced."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\*\\{%d\\} %s$" level (regexp-quote heading)) nil t)
      (forward-line 1)
      (when (looking-at "^:PROPERTIES:$")
        (when (re-search-forward "^:END:$" nil t)
          (forward-line 1)))
      (let ((start (point))
            (end (if (re-search-forward
                      (format "^\\*\\{1,%d\\} " level) nil t)
                     (line-beginning-position)
                   (point-max))))
        (delete-region start end)
        (goto-char start)
        (insert (string-trim-right body) "\n\n")
        t))))

(defun tibetan-cascade--regenerate (filepath sent-num segs source-file)
  "Regenerate FILEPATH's deterministic sections; preserve everything
user-valuable.  PRESERVE → REBUILD (via `tibetan-cascade--scaffold')
→ RESTORE, the §5.18 sentence pattern.  Preserved: the three user
slots, populated sentence-level bodies (Translation / DharmaMitra
Translation / Claude Vocabulary / Concept Notes / Provided
Translations subtree / *** Claude Grammar), populated subsegment
`*** Rendering' bodies for segments still present in SEGS, and every
UNKNOWN top-level section verbatim (§5.38-H2).  Placeholders
regenerate freshly.  Idempotent modulo the LAST_ANALYZED stamp.
Returns FILEPATH."
  (let* ((keep-l1
          (cl-remove-if-not
           #'cdr
           (mapcar (lambda (h)
                     (cons h (tibetan-cascade--read-l1-body filepath h)))
                   '("My Notes" "Working Translation" "Footnotes"))))
         (keep-l2
          (when (fboundp 'tibetan-sentence--read-l2-body)
            (cl-remove-if-not
             #'cdr
             (mapcar (lambda (h)
                       (cons h (tibetan-sentence--read-l2-body filepath h)))
                     '("Translation" "DharmaMitra Translation"
                       "Claude Vocabulary" "Concept Notes"
                       "Provided Translations")))))
         (claude-grammar (tibetan-cascade--read-l3-body
                          filepath "Claude Grammar"))
         (renderings
          (cl-loop for n in (tibetan-cascade--subsegment-numbers filepath)
                   when (and (assq n segs)
                             (not (tibetan-cascade--subsegment-rendering-needs-request-p
                                   filepath n)))
                   collect (cons n (tibetan-cascade--read-subsegment-section
                                    filepath n "Rendering"))))
         (unknown (tibetan-cascade--collect-unknown-l1-sections filepath)))
    (with-temp-buffer
      (insert (tibetan-cascade--scaffold sent-num segs source-file))
      (dolist (kv keep-l1)
        (tibetan-cascade--set-body-in-buffer 1 (car kv) (cdr kv)))
      (dolist (kv keep-l2)
        (tibetan-cascade--set-body-in-buffer 2 (car kv) (cdr kv)))
      (when claude-grammar
        (tibetan-cascade--set-body-in-buffer 3 "Claude Grammar"
                                             claude-grammar))
      (dolist (r renderings)
        (when (cdr r)
          (tibetan-cascade--write-subsegment-section-in-buffer
           (car r) "Rendering" (cdr r))))
      (dolist (u unknown)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (string-trim-right u) "\n\n"))
      (write-region (point-min) (point-max) filepath nil 'silent))
    filepath))

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

;; ============================================================================
;; C3.1 — span extraction + response landing
;; ============================================================================

(declare-function tibetan-sentence-claude--parse-response
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--strip-span-markers
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--synthesize-segment-markdown
                  "tibetan-sentence-claude")
(declare-function tibetan-analysis--insert-claude-sections
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--claude-needs-request-p
                  "tibetan-analysis-claude")

(defun tibetan-cascade--extract-span (whole seg-num)
  "The text between `⟦SEG-NUM⟧' and `⟦/SEG-NUM⟧' in WHOLE, or nil.
Any residual span markers inside the extract are stripped
defensively (the schema forbids nesting, but Claude occasionally
misplaces a sibling marker).  nil on absent or malformed pairs —
the caller then writes a visible stub, never a silent blank."
  (when (and whole (stringp whole) seg-num)
    (let* ((open (format "⟦%d⟧" seg-num))
           (close (format "⟦/%d⟧" seg-num))
           (s (string-search open whole))
           (e (string-search close whole)))
      (when (and s e (< s e))
        (let ((span (string-trim
                     (replace-regexp-in-string
                      "⟦/?[0-9]+⟧" ""
                      (substring whole (+ s (length open)) e)))))
          (unless (string-empty-p span) span))))))

(defun tibetan-cascade--reassemble-subsections (parsed key seg-nums
                                                &optional preamble)
  "Rebuild the `### Segment N' markdown for KEY from PARSED slots.
PREAMBLE (e.g. the cross-clause Grammar overview) opens the body.
nil when nothing is available for any segment."
  (let* ((blocks
          (delq nil
                (mapcar
                 (lambda (n)
                   (let* ((slot (cdr (assq n (plist-get parsed
                                                        :per-segment))))
                          (body (and slot (plist-get slot key))))
                     (when (and body (not (string-empty-p body)))
                       (format "### Segment %d\n%s" n body))))
                 seg-nums)))
         (parts (if (and preamble (not (string-empty-p (or preamble ""))))
                    (cons preamble blocks)
                  blocks)))
    (when parts
      (mapconcat #'identity parts "\n\n"))))

(defun tibetan-cascade--land-response (response ctx)
  "Land a sentence-first RESPONSE into the ONE cascade file.
CTX: (:sent-num N :seg-nums L :sent-file FILE :cascade t :force BOOL).

Sentence level (landing-gated like every Claude write): Translation =
the whole-sentence rendering with the ⟦N⟧ markers STRIPPED;
Vocabulary / Grammar / Particles keep their per-segment subsections
\(reassembled from the parse); Concept Notes as-is — all through
`tibetan-analysis--insert-claude-sections' (heading placement, md-h3
conversion, §5.38-C1b sanitization, zettel cross-links for free).
The `### Segment N' SUB-TRANSLATIONS are DISCARDED by design — the
subsegment rendering is always the extracted span of the whole, so
the subsegment translation is contained in the sentence translation
by construction.

Per subsegment (gated per Rendering): the extracted span, or a
visible `[Claude sentence response missing Segment N …]' stub that
still counts as needs-request.  Returns non-nil when the file was
touched."
  (let* ((sent-num (plist-get ctx :sent-num))
         (seg-nums (plist-get ctx :seg-nums))
         (file (or (plist-get ctx :cascade-file)
                   (plist-get ctx :sent-file)))
         (force (plist-get ctx :force))
         (parsed (and (fboundp 'tibetan-sentence-claude--parse-response)
                      (tibetan-sentence-claude--parse-response
                       response seg-nums)))
         (whole (plist-get parsed :translation-whole)))
    (ignore sent-num)
    (when (and parsed file (file-exists-p file))
      ;; Sentence-level sections.
      (let ((md (tibetan-sentence-claude--synthesize-segment-markdown
                 (list :translation
                       (and whole
                            (tibetan-sentence-claude--strip-span-markers
                             whole))
                       :vocabulary (tibetan-cascade--reassemble-subsections
                                    parsed :vocabulary seg-nums)
                       :grammar (tibetan-cascade--reassemble-subsections
                                 parsed :grammar seg-nums
                                 (plist-get parsed :grammar-preamble))
                       :particles (tibetan-cascade--reassemble-subsections
                                   parsed :particles seg-nums)
                       :concepts (plist-get parsed :concepts)))))
        (when (and md (not (string-empty-p md))
                   (or force
                       (tibetan-analysis--claude-needs-request-p file)))
          (tibetan-analysis--insert-claude-sections md file)))
      ;; Subsegment renderings — span or visible stub, per-unit gated.
      (dolist (n seg-nums)
        (when (or force
                  (tibetan-cascade--subsegment-rendering-needs-request-p
                   file n))
          (let ((span (tibetan-cascade--extract-span whole n)))
            (tibetan-cascade--write-subsegment-section
             file n "Rendering"
             (if span
                 ;; §5.38-C1b: neutralise line-leading `*' runs.
                 (replace-regexp-in-string "^\\(\\*+\\)" " \\1" span)
               (format "[Claude sentence response missing Segment %d — re-fire the sentence (C-c u R)]"
                       n))))))
      t)))

;; ============================================================================
;; C3.2 — cascade fire (claim + request + DM through the §5.40 machinery)
;; ============================================================================

(declare-function tibetan-sentence-claude--claim "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--request "tibetan-sentence-claude")
(declare-function tibetan-sentence-claude--schedule-dm
                  "tibetan-sentence-claude")
(declare-function tibetan-sentence--filepath "tibetan-sentence-persist")

(defun tibetan-cascade--prompt-grounding (sentence source-file folder)
  "Per-subsegment Interlinear grounding for the sentence-first prompt.
In cascade mode there are no child seg files — the grounding blocks
come from the cascade file's own subsegment `*** Interlinear Gloss'
sections (same anti-hallucination purpose as the §5.34 child
grounding).  nil when the file or every gloss is unavailable."
  (let* ((sent-num (plist-get sentence :sent-num))
         (file (and sent-num
                    (fboundp 'tibetan-sentence--filepath)
                    (tibetan-sentence--filepath sent-num folder
                                                source-file))))
    (when (and file (file-exists-p file))
      (let ((blocks
             (delq nil
                   (mapcar
                    (lambda (n)
                      (let ((gloss (tibetan-cascade--read-subsegment-section
                                    file n "Interlinear Gloss")))
                        (when (and gloss
                                   (not (string-match-p "\\`\\[" gloss)))
                          (format "=== Segment %d ===\n%s" n gloss))))
                    (plist-get sentence :seg-nums)))))
        (when blocks
          (concat "\n\nPer-segment vocabulary matches (the tool's own "
                  "layered dictionary lookup; dictionary-attested — base "
                  "the Vocabulary subsections on them and do NOT invent "
                  "meanings for listed words):\n"
                  (mapconcat #'identity blocks "\n")))))))

(defun tibetan-cascade--fire-sentence (sentence source-file folder
                                       &optional force)
  "Fire ONE sentence-level Claude call for a CASCADE document.
SENTENCE is the walker plist; the target is the single cascade file
\(resolved suffix-aware in FOLDER) — there are no child seg files.
Fire gate: FORCE, the sentence-level Claude slots still needing a
request, or ANY subsegment Rendering still a placeholder/stub.
Claim/request/DM all ride the §5.40 machinery — the request carries
the `:cascade' context flag so the response lands through
`tibetan-cascade--land-response'; DM targets the cascade file's own
nested slot.  Returns `fired' / `dedup-hit' / nil (does not apply)."
  ;; P1 discipline: this is a LEAF fire entry point — the defer-MT
  ;; guard applies here too, not only in the dispatcher above it
  ;; (create-all and future batch drivers call this directly).
  (if (and (fboundp 'tibetan-analysis--defer-mt-p)
           (tibetan-analysis--defer-mt-p source-file))
      'deferred
    (tibetan-cascade--fire-sentence-1 sentence source-file folder force)))

(defun tibetan-cascade--fire-sentence-1 (sentence source-file folder force)
  "Unguarded body of `tibetan-cascade--fire-sentence'."
  (let* ((sent-num (plist-get sentence :sent-num))
         (seg-nums (plist-get sentence :seg-nums))
         (file (and sent-num
                    (fboundp 'tibetan-sentence--filepath)
                    (tibetan-sentence--filepath sent-num folder
                                                source-file))))
    (when (and file (file-exists-p file) seg-nums
               (fboundp 'tibetan-sentence-claude--claim)
               (fboundp 'tibetan-sentence-claude--request))
      (when (or force
                (and (fboundp 'tibetan-analysis--claude-needs-request-p)
                     (tibetan-analysis--claude-needs-request-p file))
                (cl-some
                 (lambda (n)
                   (tibetan-cascade--subsegment-rendering-needs-request-p
                    file n))
                 seg-nums))
        (let ((label (format "sent-%03d (cascade)" sent-num)))
          (if (not (tibetan-sentence-claude--claim
                    source-file sent-num label))
              'dedup-hit
            (tibetan-sentence-claude--request
             sentence nil file source-file folder force 'cascade)
            (when (fboundp 'tibetan-sentence-claude--schedule-dm)
              (tibetan-sentence-claude--schedule-dm
               sentence (list file) nil force))
            'fired))))))

;; ============================================================================
;; C4.1 — create-all (the cascade branch of C-c u B / C-c s N)
;; ============================================================================

(defvar tibetan-auto-fire-claude-on-create)

(defun tibetan-cascade--collect-sentences ()
  "Collect the current buffer's sentences with per-segment texts.
Ordered list of plists (:sent-num N :segs ((GLOBAL-NUM . TEXT) …)).
Sentences without segment children are skipped.  Matches both
`*** Sentence' and legacy `** Sentence' levels; segments at any
deeper level (the `tibetan-auto--collect-segments' convention)."
  (save-excursion
    (goto-char (point-min))
    (let ((sentences '()))
      (while (re-search-forward "^\\(\\*+\\) Sentence \\([0-9]+\\)" nil t)
        (let* ((level (length (match-string 1)))
               (sent-num (string-to-number (match-string 2)))
               (limit (save-excursion
                        (if (re-search-forward
                             (format "^\\*\\{1,%d\\} " level) nil t)
                            (line-beginning-position)
                          (point-max))))
               (segs '()))
          (while (re-search-forward "^\\*+ Segment \\([0-9]+\\)" limit t)
            (let ((n (string-to-number (match-string 1)))
                  (text (and (fboundp 'tibetan-org-get-segment-text)
                             (tibetan-org-get-segment-text))))
              (when (and text (not (string-empty-p (string-trim text))))
                (push (cons n text) segs))))
          (when segs
            ;; CH2: record the enclosing Section (position anchor,
            ;; heading label, Lopez number) for chunk grouping.
            (let (section-pos section-label lopez)
              (save-excursion
                (goto-char (point-min))
                (let ((sent-pos (progn
                                  (re-search-forward
                                   (format "^\\*+ Sentence %d\\b" sent-num)
                                   nil t)
                                  (match-beginning 0))))
                  (goto-char sent-pos)
                  (when (re-search-backward
                         "^\\*\\{1,2\\} \\(Section\\b.*\\)$" nil t)
                    (setq section-pos (point)
                          section-label (string-trim (match-string 1)))
                    (forward-line 1)
                    (when (looking-at "^:PROPERTIES:$")
                      (let ((end (save-excursion
                                   (re-search-forward "^:END:$" nil t))))
                        (when (and end
                                   (re-search-forward
                                    "^:LOPEZ_SECTION:[ \t]*\\([0-9]+\\)"
                                    end t))
                          (setq lopez (string-to-number
                                       (match-string 1)))))))))
              (push (list :sent-num sent-num :segs (nreverse segs)
                          :section-pos section-pos
                          :section-label section-label
                          :lopez lopez)
                    sentences)))
          (goto-char limit)))
      (nreverse sentences))))

(defcustom tibetan-cascade-chunk-max-segments 40
  "Hard cap on segments per chunk-fire call.
The §5.40 record shows output LENGTH is the reliability ceiling —
chunk responses carry only the marked translation, but an unbounded
passage still risks marker drop-off.  Oversized sections split at
sentence boundaries."
  :type 'integer
  :group 'tibetan-cat)

(defun tibetan-cascade--collect-section-chunks ()
  "Group the current buffer's sentences into section chunks.
Ordered list of plists (:label STR-or-nil :lopez N-or-nil
:sentences SENTENCE-PLISTS) — one chunk per Section (sentences
before/without any Section form an implicit chunk), split further
when a chunk would exceed `tibetan-cascade-chunk-max-segments'."
  (let ((chunks '())
        (cur-sentences '())
        (cur-label nil) (cur-lopez nil)
        (cur-key 'none) (cur-count 0))
    (cl-flet ((flush ()
                (when cur-sentences
                  (push (list :label cur-label :lopez cur-lopez
                              :sentences (nreverse cur-sentences))
                        chunks))
                (setq cur-sentences '() cur-count 0)))
      (dolist (s (tibetan-cascade--collect-sentences))
        (let ((key (or (plist-get s :section-pos) 0))
              (nsegs (length (plist-get s :segs))))
          (when (or (not (equal key cur-key))
                    (and cur-sentences
                         (> (+ cur-count nsegs)
                            tibetan-cascade-chunk-max-segments)))
            (flush))
          (setq cur-key key
                cur-label (plist-get s :section-label)
                cur-lopez (plist-get s :lopez))
          (push s cur-sentences)
          (cl-incf cur-count nsegs)))
      (flush))
    (nreverse chunks)))

(defconst tibetan-cascade--chunk-system-addendum
  "

CHUNK MODE — this request covers a PASSAGE spanning several
sentences (the shad-delimited segments your user prompt lists under
`### Segment N' headers).  Produce ONLY the section
`## Translation': ONE fluent translation of the WHOLE passage.
Inside it, wrap the English span corresponding to EACH listed
segment in markers `⟦N⟧' before and `⟦/N⟧' after, using the exact
segment numbers — every listed segment exactly once, no nesting, no
overlaps (English may reorder the segments; mark the spans wherever
they fall).  NO `### Segment' subsections, NO other `## ' sections,
no commentary before or after."
  "System-prompt addendum for the chunk-fire translation layer.
Constant per document — a third coexisting Anthropic cache prefix
beside the segment-level and sentence-level ones.  Output is the
translation ONLY: the §5.40 record shows long multi-section
responses drop content, so vocabulary/grammar stay per-sentence.")

(defun tibetan-cascade--build-chunk-prompts (chunk source-file)
  "Build (SYSTEM . USER) for a chunk-fire call over CHUNK."
  (let* ((system (concat
                  (if (boundp 'tibetan-analysis--claude-system-prompt)
                      tibetan-analysis--claude-system-prompt
                    "")
                  tibetan-cascade--chunk-system-addendum
                  (if (and source-file
                           (fboundp
                            'tibetan-analysis--claude-static-system-blocks))
                      (tibetan-analysis--claude-static-system-blocks
                       source-file)
                    "")))
         (sentences (plist-get chunk :sentences))
         (all-segs (apply #'append
                          (mapcar (lambda (s) (plist-get s :segs))
                                  sentences)))
         (text (mapconcat #'cdr all-segs ""))
         (enumeration
          (mapconcat (lambda (sp)
                       (format "### Segment %d\n%s"
                               (car sp) (string-trim (cdr sp))))
                     all-segs "\n"))
         (refs (when (fboundp 'tibetan-cascade--section-refs-block)
                 (tibetan-cascade--section-refs-block
                  (car sentences) source-file)))
         (user (concat
                (format "Classical Tibetan passage (%s — segments %s):\n\n"
                        (or (plist-get chunk :label) "passage")
                        (mapconcat (lambda (sp)
                                     (number-to-string (car sp)))
                                   all-segs ", "))
                (string-trim text)
                "\n\nThe passage consists of these segments:\n"
                enumeration
                (or refs "")
                "\n\nProduce ONLY the `## Translation' section now, with every listed segment's span marked ⟦N⟧…⟦/N⟧ exactly as instructed.")))
    (cons system user)))

(defun tibetan-cascade--chunk-translation-body (response)
  "The `## Translation' body of RESPONSE (whole response when the
heading is absent — the markers still carry the information)."
  (when (and response (stringp response))
    (if (string-match "^## Translation[ \t]*\n" response)
        (let* ((start (match-end 0))
               (end (or (and (string-match "^## " response start)
                             (match-beginning 0))
                        (length response))))
          (string-trim (substring response start end)))
      (string-trim response))))

(defun tibetan-cascade--land-chunk-response (response ctx)
  "Land a chunk-fire RESPONSE into every member cascade file.
CTX: (:chunk t :label STR :sentences ((:sent-num N :seg-nums L
:file F) …) :force BOOL).

Per subsegment: the extracted ⟦N⟧ span (or the visible missing-span
stub — the C3 sentence-level dispatcher is the automatic fallback on
the next open/batch).  Per sentence: the SLICE of the whole between
its first span opening and its last span closing, all markers
stripped — preserving the connective English between the sentence's
own segments — labeled `(Sentence N — LABEL chunk)'.  All writes
landing-gated per file (§5.38-M7)."
  (let ((sentences (plist-get ctx :sentences))
        (force (plist-get ctx :force))
        (label (or (plist-get ctx :label) "section"))
        (whole (tibetan-cascade--chunk-translation-body response)))
    (when (and whole (not (string-empty-p whole)) sentences)
      (dolist (s sentences)
        (let ((file (plist-get s :file))
              (sent-num (plist-get s :sent-num))
              (seg-nums (plist-get s :seg-nums)))
          (when (and file (file-exists-p file))
            ;; Subsegment renderings.
            (dolist (n seg-nums)
              (when (or force
                        (tibetan-cascade--subsegment-rendering-needs-request-p
                         file n))
                (let ((span (tibetan-cascade--extract-span whole n)))
                  (tibetan-cascade--write-subsegment-section
                   file n "Rendering"
                   (if span
                       (replace-regexp-in-string "^\\(\\*+\\)" " \\1"
                                                 span)
                     (format "[Claude sentence response missing Segment %d — re-fire the sentence (C-c u R)]"
                             n))))))
            ;; Sentence Translation: the marker-bounded slice.
            (when (and (fboundp 'tibetan-analysis--claude-needs-request-p)
                       (or force
                           (tibetan-analysis--claude-needs-request-p
                            file)))
              (let* ((opens (delq nil
                                  (mapcar (lambda (n)
                                            (string-search
                                             (format "⟦%d⟧" n) whole))
                                          seg-nums)))
                     (closes (delq nil
                                   (mapcar
                                    (lambda (n)
                                      (let* ((c (format "⟦/%d⟧" n))
                                             (p (string-search c whole)))
                                        (and p (+ p (length c)))))
                                    seg-nums))))
                (when (and opens closes)
                  (let* ((slice (substring whole
                                           (apply #'min opens)
                                           (apply #'max closes)))
                         (plain (string-trim
                                 (replace-regexp-in-string
                                  "⟦/?[0-9]+⟧" "" slice))))
                    (unless (string-empty-p plain)
                      (tibetan-analysis--insert-claude-sections
                       (format "## Translation\n(Sentence %s — %s chunk)\n%s\n"
                               sent-num label plain)
                       file)))))))))
      t)))


;;;###autoload
(defun tibetan-cascade-create-all (&optional force)
  "Create the cascade sent file for EVERY sentence of the current
source buffer (one file per sentence — no seg files).  Skips
existing files unless FORCE.  When
`tibetan-auto-fire-claude-on-create' is non-nil, fires the
sentence-level Claude/DM call for each newly-created file (the
queue throttles; `tibetan-cascade--fire-sentence' itself defers
under `#+TIBETAN_DEFER_MT').  Returns
\(:created N :skipped M :files LIST)."
  (interactive "P")
  (unless (buffer-file-name)
    (error "Buffer must be saved to a file first"))
  (let* ((source-file (buffer-file-name))
         (sentences (tibetan-cascade--collect-sentences))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (created '())
         (skipped 0))
    (unless sentences
      (error "No sentences found. Run tibetan-prepare-document first"))
    (dolist (s sentences)
      (let* ((sent-num (plist-get s :sent-num))
             (file (if (fboundp 'tibetan-sentence--filepath)
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder))))
        (if (and (file-exists-p file) (not force))
            (cl-incf skipped)
          (tibetan-cascade--create-file sent-num (plist-get s :segs)
                                        source-file)
          (push (cons s file) created))))
    (setq created (nreverse created))
    ;; CH (2026-07-29, after the live §167 evaluation — 9/9 spans):
    ;; cascade auto-fire is CHUNKED — one translation-layer call +
    ;; one DM call per SECTION.  Fire gates skip populated members,
    ;; and missing spans fall back to the C3 sentence dispatcher on
    ;; the next open/batch.
    (when (and created
               (boundp 'tibetan-auto-fire-claude-on-create)
               tibetan-auto-fire-claude-on-create)
      (dolist (chunk (tibetan-cascade--collect-section-chunks))
        (condition-case err
            (tibetan-cascade--fire-section chunk source-file folder)
          (error (message "Cascade chunk fire skipped (%s): %s"
                          (or (plist-get chunk :label) "chunk")
                          (error-message-string err))))))
    (message "Cascade: %d sentence file%s created, %d skipped"
             (length created) (if (= 1 (length created)) "" "s") skipped)
    (list :created (length created) :skipped skipped
          :files (mapcar #'cdr created))))

;; ============================================================================
;; C4.2 — open dispatch (C-c u A at a segment of a cascade document)
;; ============================================================================

(declare-function tibetan-sentence--sentence-for-segment
                  "tibetan-sentence-persist")

(defun tibetan-cascade--segs-for-sentence (source-file sent-num)
  "SOURCE-FILE's sentence SENT-NUM as (GLOBAL-NUM . TEXT) pairs, or nil."
  (when (and source-file (file-readable-p source-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents source-file)
          (org-mode)
          (plist-get
           (cl-find sent-num (tibetan-cascade--collect-sentences)
                    :key (lambda (p) (plist-get p :sent-num)))
           :segs))
      (error nil))))

;;;###autoload
(defun tibetan-cascade-open-for-segment (seg-id source-file)
  "Open the cascade file owning SEG-ID; point on its subsegment subtree.
Resolves the sentence through the §5.40 walker, creates the cascade
file when missing (C-c u A parity: opening implies creating), and
displays it in the side window.  Returns the buffer.

SEG-ID may be a number or a composite label like `\"Sentence 5,
Segment 107\"' (what `tibetan-get-current-segment-any-format'
returns for the nested §2.12 layout) — the trailing segment number
is what counts."
  (when (and (stringp seg-id)
             (string-match "Segment \\([0-9]+\\)" seg-id))
    (setq seg-id (string-to-number (match-string 1 seg-id))))
  (let* ((sentence (and (fboundp 'tibetan-sentence--sentence-for-segment)
                        (condition-case nil
                            (tibetan-sentence--sentence-for-segment
                             seg-id source-file)
                          (error nil))))
         (sent-num (plist-get sentence :sent-num)))
    (unless sent-num
      (user-error "Segment %s is not inside a sentence of %s"
                  seg-id (file-name-nondirectory (or source-file "?"))))
    (let* ((folder (file-name-as-directory
                    (expand-file-name
                     "analysis" (file-name-directory source-file))))
           (file (if (fboundp 'tibetan-sentence--filepath)
                     (tibetan-sentence--filepath sent-num folder
                                                 source-file)
                   (expand-file-name (format "sent-%03d.org" sent-num)
                                     folder))))
      (unless (file-exists-p file)
        (tibetan-cascade--create-file
         sent-num
         (tibetan-cascade--segs-for-sentence source-file sent-num)
         source-file))
      (let ((buf (find-file-noselect file)))
        (with-current-buffer buf
          (when (fboundp 'tibetan-analysis-setup-faces)
            (tibetan-analysis-setup-faces))
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*\\* Segment %d$" seg-id) nil t)
            (beginning-of-line)))
        (let ((win (display-buffer-in-side-window
                    buf '((side . right) (window-width . 0.5)))))
          (when (windowp win)
            (set-window-point win (with-current-buffer buf (point)))))
        buf))))

;; ============================================================================
;; C4.3 — reanalyze routing (single file, per-segment, batch guard)
;; ============================================================================

(declare-function tibetan-sentence--sent-id-from-filename
                  "tibetan-sentence-persist")
(declare-function tibetan-sentence--source-file-from-analysis
                  "tibetan-sentence-persist")
(declare-function tibetan-analysis--should-fire-claude-p
                  "tibetan-analysis-claude")

(cl-defun tibetan-cascade-reanalyze-file (filepath &key source-file
                                                   re-request-claude)
  "Headless re-analysis of the cascade file FILEPATH.
Sentence number from the filename; segs freshly re-read from
SOURCE-FILE (or the file's #+SOURCE link); regenerate preserves all
user/Claude/DM content (C2.3).  RE-REQUEST-CLAUDE follows the
§5.22-follow-up policy (nil / t / :missing-only) — the fire itself
still defers under #+TIBETAN_DEFER_MT.  Returns
\(:file F :sent-id N :ok BOOL :error STR)."
  (let* ((sent-id (and (fboundp 'tibetan-sentence--sent-id-from-filename)
                       (tibetan-sentence--sent-id-from-filename filepath)))
         (src (or source-file
                  (and (fboundp 'tibetan-sentence--source-file-from-analysis)
                       (tibetan-sentence--source-file-from-analysis
                        filepath))))
         (segs (and sent-id src
                    (tibetan-cascade--segs-for-sentence src sent-id))))
    (cond
     ((null sent-id)
      (list :file filepath :ok nil
            :error "Could not extract sent-id from filename"))
     ((null src)
      (list :file filepath :sent-id sent-id :ok nil
            :error "Could not resolve source file"))
     ((null segs)
      (list :file filepath :sent-id sent-id :ok nil
            :error (format "Sentence %d not found in source" sent-id)))
     (t
      (condition-case err
          (progn
            (tibetan-cascade--regenerate filepath sent-id segs src)
            (when (and re-request-claude
                       (or (not (fboundp 'tibetan-analysis--should-fire-claude-p))
                           (tibetan-analysis--should-fire-claude-p
                            re-request-claude filepath)))
              (tibetan-cascade--fire-sentence
               (list :sent-num sent-id
                     :seg-nums (mapcar #'car segs)
                     :tibetan-text (mapconcat #'cdr segs ""))
               src (file-name-directory (expand-file-name filepath))
               (eq re-request-claude t)))
            (list :file filepath :sent-id sent-id :ok t))
        (error (list :file filepath :sent-id sent-id :ok nil
                     :error (error-message-string err))))))))

;;;###autoload
(defun tibetan-cascade-reanalyze-for-segment (seg-id source-file
                                              &optional re-request-claude)
  "Re-analyze the cascade file owning SEG-ID (the C-c u R branch).
SEG-ID as in `tibetan-cascade-open-for-segment' (number or composite
label).  Returns the `tibetan-cascade-reanalyze-file' plist."
  (when (and (stringp seg-id)
             (string-match "Segment \\([0-9]+\\)" seg-id))
    (setq seg-id (string-to-number (match-string 1 seg-id))))
  (let* ((sentence (and (fboundp 'tibetan-sentence--sentence-for-segment)
                        (condition-case nil
                            (tibetan-sentence--sentence-for-segment
                             seg-id source-file)
                          (error nil))))
         (sent-num (plist-get sentence :sent-num)))
    (if (not sent-num)
        (list :ok nil
              :error (format "Segment %s not inside a sentence" seg-id))
      (let* ((folder (file-name-as-directory
                      (expand-file-name
                       "analysis" (file-name-directory source-file))))
             (file (if (fboundp 'tibetan-sentence--filepath)
                       (tibetan-sentence--filepath sent-num folder
                                                   source-file)
                     (expand-file-name (format "sent-%03d.org" sent-num)
                                       folder))))
        (if (file-exists-p file)
            (tibetan-cascade-reanalyze-file
             file :source-file source-file
             :re-request-claude re-request-claude)
          (list :ok nil :error (format "No cascade file for sentence %d"
                                       sent-num)))))))

(defun tibetan-cascade-file-p (filepath)
  "Non-nil when FILEPATH itself carries `#+TIBETAN_LAYOUT: cascade'.
The batch-safety predicate: folder batches must route such files to
the cascade regenerate — the two-file sentence regenerate would
destroy the * Subsegments tree."
  (and filepath (stringp filepath) (file-exists-p filepath)
       (fboundp 'tibetan-analysis--read-source-metadata)
       (equal "cascade"
              (plist-get (tibetan-analysis--read-source-metadata filepath)
                         :layout))))

;; ============================================================================
;; C5.2 — one-time source transform: segment = shad unit
;; ============================================================================

(declare-function tibetan-analysis--folder-analysis-files-strict
                  "tibetan-analysis-persist")
(declare-function tibetan-analysis--file-source-basename
                  "tibetan-analysis-persist")

;;;###autoload
(defun tibetan-shad-split-segments ()
  "Split every Segment of the current source buffer into shad units.
One-time SOURCE transform preparing a document for cascade analysis
\(segment = shad unit; sentence = group of segments).  Renumbers ALL
segments globally from 1 afterwards — therefore it REFUSES with a
`user-error' when analysis/ already holds seg files for this source:
renumbering would orphan them (the §5.26/§5.33 data-loss class).
Never run it on a two-file corpus.

A `:PROPERTIES:' drawer (e.g. :FOLIO:) stays on the FIRST unit of a
split segment; Working Translation siblings are untouched; the
concatenated Tibetan is preserved (the C1 splitter's contract).
Returns (:segments-before N :segments-after M)."
  (interactive)
  (unless (buffer-file-name)
    (user-error "Buffer must be saved to a file first"))
  (let* ((source-file (buffer-file-name))
         (folder (expand-file-name
                  "analysis" (file-name-directory source-file))))
    (when (file-directory-p folder)
      (let ((seg-files
             (if (fboundp 'tibetan-analysis--folder-analysis-files-strict)
                 (tibetan-analysis--folder-analysis-files-strict
                  folder "seg")
               (directory-files folder t "\\`seg-"))))
        (when (cl-some
               (lambda (f)
                 (if (fboundp 'tibetan-analysis--file-source-basename)
                     (equal (tibetan-analysis--file-source-basename f)
                            (file-name-nondirectory source-file))
                   ;; Resolver unavailable → any seg file blocks.
                   t))
               seg-files)
          (user-error
           "analysis/ holds seg files for this source — shad-splitting would renumber and orphan them"))))
    (let ((before 0) (after 0))
      (save-excursion
        ;; Pass 1: split each multi-unit segment in place.
        (goto-char (point-min))
        (while (re-search-forward "^\\(\\*+\\) Segment [0-9]+.*$" nil t)
          (cl-incf before)
          (let* ((stars (match-string 1))
                 (h-start (line-beginning-position))
                 (h-end (line-end-position))
                 (subtree-end (save-excursion
                                (goto-char h-end)
                                (if (re-search-forward "^\\*+ " nil t)
                                    (line-beginning-position)
                                  (point-max))))
                 (drawer
                  (save-excursion
                    (goto-char h-end)
                    (forward-line 1)
                    (when (looking-at "^:PROPERTIES:$")
                      (let ((ds (point)))
                        (when (re-search-forward "^:END:$" subtree-end t)
                          (forward-line 1)
                          (buffer-substring-no-properties ds (point)))))))
                 (body-start (save-excursion
                               (goto-char h-end)
                               (forward-line 1)
                               (when drawer
                                 (re-search-forward "^:END:$" subtree-end t)
                                 (forward-line 1))
                               (point)))
                 (body (buffer-substring-no-properties body-start
                                                       subtree-end))
                 (units (tibetan-cascade-split-shad-units
                         (string-trim body))))
            (if (or (null units) (< (length units) 2))
                (progn (cl-incf after)
                       (goto-char subtree-end))
              (cl-incf after (length units))
              (delete-region h-start subtree-end)
              (goto-char h-start)
              (let ((first t))
                (dolist (u units)
                  (insert stars " Segment 0\n")
                  (when (and first drawer) (insert drawer))
                  (setq first nil)
                  (insert (string-trim u) "\n\n"))))))
        ;; Pass 2: renumber globally from 1.
        (goto-char (point-min))
        (let ((n 0))
          (while (re-search-forward "^\\(\\*+\\) Segment [0-9]+" nil t)
            (cl-incf n)
            (replace-match (format "\\1 Segment %d" n) t nil))))
      (when (called-interactively-p 'any)
        (message "Shad-split: %d segment%s → %d shad-unit segments"
                 before (if (= 1 before) "" "s") after))
      (list :segments-before before :segments-after after))))

;; ============================================================================
;; C7.1 — comparative-document importer (the Rgyan §-layer)
;; ============================================================================

;;;###autoload
(defun tibetan-cascade-import-comparative (comparative-file output-file)
  "One-time import of a §-comparative document into a cascade CAT source.

COMPARATIVE-FILE is GENERATOR-OWNED (build_comparative_doc.py —
hand-edits are lost on re-run), so it must never become the CAT
source itself.  This importer extracts, per `** §N' subtree, the
`*** Tibetisch (B2)' body and the Lopez anchors
\(:SECTION:/:B2_SEG_START:/:B2_SEG_END:) into OUTPUT-FILE:

  ** Section §N          with :LOPEZ_SECTION: + the B2 anchors
  *** Segment M          ONE initial segment per § (global numbering)

The copyrighted §-level reference translations (Lopez, Wangjié &
Mulligan, …) and the Wylie are NEVER copied — the CAT source points
back via `#+TIBETAN_SECTION_REFS:' and the prompt builder injects
them as ¶-context at request time (C7.2).

After importing: run `tibetan-shad-split-segments' (segment = shad
unit) and then the genre-aware `tibetan-add-sentence-structure' on
OUTPUT-FILE.  Refuses to overwrite an existing OUTPUT-FILE — it is
hand-owned from the moment it exists.  Returns
\(:sections N :segments N :file OUTPUT-FILE)."
  (interactive
   (list (read-file-name "Comparative document: " nil nil t)
         (read-file-name "CAT source to create: ")))
  (unless (and comparative-file (file-readable-p comparative-file))
    (user-error "Comparative document not readable: %s" comparative-file))
  (when (file-exists-p output-file)
    (user-error
     "%s already exists — the CAT source is hand-owned once created"
     (file-name-nondirectory output-file)))
  (let ((sections '()))
    ;; Collect (§-num b2-start b2-end tibetan-body) per § subtree.
    (with-temp-buffer
      (insert-file-contents comparative-file)
      (goto-char (point-min))
      (while (re-search-forward "^\\*\\* §\\([0-9]+\\)" nil t)
        (let* ((secnum (string-to-number (match-string 1)))
               (limit (save-excursion
                        (if (re-search-forward "^\\*\\* " nil t)
                            (line-beginning-position)
                          (point-max))))
               (b2-start nil) (b2-end nil) (tib nil))
          (save-excursion
            (when (re-search-forward
                   "^:B2_SEG_START:[ \t]*\\([0-9]+\\)" limit t)
              (setq b2-start (match-string 1))))
          (save-excursion
            (when (re-search-forward
                   "^:B2_SEG_END:[ \t]*\\([0-9]+\\)" limit t)
              (setq b2-end (match-string 1))))
          (save-excursion
            (when (re-search-forward "^\\*\\*\\* Tibetisch (B2)$" limit t)
              (forward-line 1)
              (let ((start (point))
                    (end (if (re-search-forward "^\\*\\{1,3\\} " limit t)
                             (line-beginning-position)
                           limit)))
                (setq tib (string-trim
                           (buffer-substring-no-properties start end))))))
          (push (list secnum b2-start b2-end tib) sections)
          (goto-char limit))))
    (setq sections (nreverse sections))
    (unless sections
      (user-error "No `** §N' subtrees found in %s"
                  (file-name-nondirectory comparative-file)))
    ;; Emit the CAT source.
    (let ((refs (file-relative-name
                 comparative-file (file-name-directory
                                   (expand-file-name output-file))))
          (seg 0))
      (with-temp-file output-file
        (insert (format "#+TITLE: %s — CAT-Quelle (B2)\n"
                        (file-name-base output-file)))
        (insert "#+STARTUP: showall\n")
        (insert "#+OPTIONS: toc:nil num:nil\n")
        (insert "#+TIBETAN_LAYOUT: cascade\n")
        (insert "#+TIBETAN_TARGET_LANG: de\n")
        (insert (format "#+TIBETAN_SECTION_REFS: %s\n" refs))
        (insert (format "#+CREATED: %s\n"
                        (format-time-string "%Y-%m-%d")))
        (insert "\n")
        (insert "# Einmalig importiert aus dem generator-eigenen\n"
                (format "# Komparativdokument (%s).\n"
                        (file-name-nondirectory comparative-file))
                "# Ab jetzt HAND-EIGEN — der Importer überschreibt nie.\n"
                "# Nächste Schritte: M-x tibetan-shad-split-segments,\n"
                "# dann C-c s S (genre-bewusste Satzstruktur).\n\n")
        (insert "* Tibetan Text\n")
        (dolist (sec sections)
          (cl-destructuring-bind (secnum b2-start b2-end tib) sec
            (insert (format "** Section §%d\n" secnum))
            (insert ":PROPERTIES:\n")
            (insert (format ":LOPEZ_SECTION: %d\n" secnum))
            (when b2-start
              (insert (format ":B2_SEG_START: %s\n" b2-start)))
            (when b2-end
              (insert (format ":B2_SEG_END: %s\n" b2-end)))
            (insert ":END:\n\n")
            (cl-incf seg)
            (insert (format "*** Segment %d\n" seg))
            (insert (if (and tib (not (string-empty-p tib)))
                        tib
                      "[B2-Text fehlt — im Komparativdokument ergänzen]")
                    "\n\n"))))
      (when (called-interactively-p 'any)
        (message "Imported %d §§ → %s (now: shad-split + C-c s S)"
                 (length sections)
                 (file-name-nondirectory output-file)))
      (list :sections (length sections) :segments seg
            :file output-file))))

;; ============================================================================
;; C7.2 — §-refs ¶-context (USER prompt only; system stays constant)
;; ============================================================================

(defun tibetan-cascade--sentence-lopez-section (source-file sent-num)
  "The :LOPEZ_SECTION: of the Section wrapping SENT-NUM, or nil."
  (when (and source-file (file-readable-p source-file) sent-num)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents source-file)
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^\\*+ Sentence %d\\b" sent-num) nil t)
            (when (re-search-backward "^\\*\\{1,2\\} Section\\b" nil t)
              (forward-line 1)
              (when (looking-at "^:PROPERTIES:$")
                (let ((end (save-excursion
                             (re-search-forward "^:END:$" nil t))))
                  (when (and end
                             (re-search-forward
                              "^:LOPEZ_SECTION:[ \t]*\\([0-9]+\\)" end t))
                    (string-to-number (match-string 1))))))))
      (error nil))))

(defun tibetan-cascade--section-refs-block (sentence source-file)
  "The §-level reference-translation block for SENTENCE's Section.
Resolves `#+TIBETAN_SECTION_REFS:' relative to SOURCE-FILE, locates
the `** §N' subtree, and collects every `*** <name>' child EXCEPT
the B2 Tibetan and the Wylie — i.e. Lopez, Wangjié & Mulligan, and
any additional §-indexed translations the generator carries.  The
bodies stay in the comparative file and the prompt: they are NEVER
written into analysis files (copyright + regen safety).  nil when
anything along the chain is missing."
  (let* ((refs-rel (and (fboundp 'tibetan-analysis--read-source-metadata)
                        (plist-get
                         (tibetan-analysis--read-source-metadata
                          source-file)
                         :section-refs)))
         (refs-file (and refs-rel
                         (expand-file-name
                          refs-rel (file-name-directory
                                    (expand-file-name source-file)))))
         (secnum (and refs-file (file-readable-p refs-file)
                      (tibetan-cascade--sentence-lopez-section
                       source-file (plist-get sentence :sent-num)))))
    (when secnum
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents refs-file)
            (goto-char (point-min))
            (when (re-search-forward
                   (format "^\\*\\* §%d\\b" secnum) nil t)
              (let ((limit (save-excursion
                             (if (re-search-forward "^\\*\\* " nil t)
                                 (line-beginning-position)
                               (point-max))))
                    (blocks '()))
                (while (re-search-forward
                        "^\\*\\*\\* \\(.+\\)$" limit t)
                  (let ((name (string-trim (match-string 1))))
                    (forward-line 1)
                    ;; Skip a :PROPERTIES: drawer (:READ_ONLY: etc.).
                    (when (looking-at "^:PROPERTIES:$")
                      (when (re-search-forward "^:END:$" limit t)
                        (forward-line 1)))
                    (let* ((start (point))
                           (end (if (re-search-forward
                                     "^\\*\\{1,3\\} " limit t)
                                    (progn (goto-char
                                            (line-beginning-position))
                                           (point))
                                  limit))
                           (body (string-trim
                                  (buffer-substring-no-properties
                                   start end))))
                      (unless (or (string-prefix-p "Tibetisch" name)
                                  (string-prefix-p "Wylie" name)
                                  (string-empty-p body))
                        (push (format "=== %s ===\n%s" name body)
                              blocks)))))
                (when blocks
                  (concat
                   (format
                    "\n\nReference translations for Lopez §%d (¶-level context ONLY — they span several sentences; do NOT copy their wording, and never reproduce them in your output sections):\n"
                    secnum)
                   (mapconcat #'identity (nreverse blocks) "\n"))))))
        (error nil)))))

;; ============================================================================
;; CH2c — fire-section + UX
;; ============================================================================

(declare-function tibetan-dharmamitra-translation-fire-section
                  "tibetan-dharmamitra-translation")
(defvar tibetan-sentence-claude--dm-schedule-count)
(defvar tibetan-dharmamitra-sentence-request-delay)

(defun tibetan-cascade--schedule-dm-section (chunk files force)
  "Schedule ONE DharmaMitra call for CHUNK's whole text — staggered
against the 10/min limit like the §5.40 sentence DM, but one call
per SECTION instead of one per sentence."
  (when (and files
             (fboundp 'tibetan-dharmamitra-translation-fire-section)
             (boundp 'tibetan-sentence-claude--dm-schedule-count)
             (boundp 'tibetan-dharmamitra-sentence-request-delay))
    (let ((delay (* tibetan-sentence-claude--dm-schedule-count
                    tibetan-dharmamitra-sentence-request-delay))
          (text (mapconcat (lambda (s)
                             (mapconcat #'cdr (plist-get s :segs) ""))
                           (plist-get chunk :sentences) ""))
          (label (or (plist-get chunk :label) "Section")))
      (cl-incf tibetan-sentence-claude--dm-schedule-count)
      (run-at-time
       delay nil
       (lambda ()
         (condition-case err
             (tibetan-dharmamitra-translation-fire-section
              text label files force)
           (error (message "Section DM fire failed (%s): %s"
                           label (error-message-string err)))))))))

(defun tibetan-cascade--fire-section (chunk source-file folder
                                      &optional force)
  "Fire ONE chunk-level Claude call (translation layer) for CHUNK.
Resolves every member sentence's cascade file; gate = FORCE, any
member needing Claude, or any member Rendering placeholder.  Claim,
queue, and gptel all ride the §5.40 machinery (`chunk' request
flavor); DM rides the same claim at SECTION granularity.  Returns
`fired' / `dedup-hit' / `deferred' / nil."
  (if (and (fboundp 'tibetan-analysis--defer-mt-p)
           (tibetan-analysis--defer-mt-p source-file))
      'deferred
    (let ((sentences
           (delq nil
                 (mapcar
                  (lambda (s)
                    (let* ((sent-num (plist-get s :sent-num))
                           (file (and sent-num
                                      (fboundp 'tibetan-sentence--filepath)
                                      (tibetan-sentence--filepath
                                       sent-num folder source-file))))
                      (when (and file (file-exists-p file))
                        (list :sent-num sent-num
                              :seg-nums (mapcar #'car
                                                (plist-get s :segs))
                              :segs (plist-get s :segs)
                              :file file))))
                  (plist-get chunk :sentences)))))
      (when (and sentences
                 (fboundp 'tibetan-sentence-claude--claim)
                 (fboundp 'tibetan-sentence-claude--request))
        (when (or force
                  (cl-some
                   (lambda (s)
                     (let ((file (plist-get s :file)))
                       (or (and (fboundp
                                 'tibetan-analysis--claude-needs-request-p)
                                (tibetan-analysis--claude-needs-request-p
                                 file))
                           (cl-some
                            (lambda (n)
                              (tibetan-cascade--subsegment-rendering-needs-request-p
                               file n))
                            (plist-get s :seg-nums)))))
                   sentences))
          (let* ((key (cons 'chunk (plist-get (car sentences) :sent-num)))
                 (label (format "chunk %s"
                                (or (plist-get chunk :label) key))))
            (if (not (tibetan-sentence-claude--claim
                      source-file key label))
                'dedup-hit
              (tibetan-sentence-claude--request
               (list :sent-num key
                     :seg-nums (apply #'append
                                      (mapcar (lambda (s)
                                                (plist-get s :seg-nums))
                                              sentences))
                     :label (plist-get chunk :label)
                     :sentences sentences)
               nil nil source-file folder force 'chunk)
              (tibetan-cascade--schedule-dm-section
               (list :label (plist-get chunk :label)
                     :sentences sentences)
               (mapcar (lambda (s) (plist-get s :file)) sentences)
               force)
              'fired)))))))

;;;###autoload
(defun tibetan-cascade-fire-sections (&optional force)
  "Chunk-fire every section of the current cascade source buffer.
One translation-layer Claude call + one DharmaMitra call per section
chunk (`tibetan-cascade--collect-section-chunks'); everything lands
into the member cascade files.  With prefix FORCE, re-fires
populated sections too."
  (interactive "P")
  (unless (buffer-file-name)
    (user-error "Buffer must be saved to a file first"))
  (unless (and (fboundp 'tibetan-analysis--cascade-p)
               (tibetan-analysis--cascade-p (buffer-file-name)))
    (user-error "Not a cascade document (#+TIBETAN_LAYOUT: cascade)"))
  (let* ((source-file (buffer-file-name))
         (folder (file-name-as-directory
                  (expand-file-name
                   "analysis" (file-name-directory source-file))))
         (chunks (tibetan-cascade--collect-section-chunks))
         (fired 0) (other 0))
    (unless chunks
      (user-error "No sentences found"))
    (dolist (c chunks)
      (if (eq 'fired (tibetan-cascade--fire-section
                      c source-file folder force))
          (cl-incf fired)
        (cl-incf other)))
    (message "Chunk-fire: %d section call%s queued, %d skipped/deferred"
             fired (if (= 1 fired) "" "s") other)
    (list :fired fired :skipped other)))

(provide 'tibetan-cascade)
;;; tibetan-cascade.el ends here
