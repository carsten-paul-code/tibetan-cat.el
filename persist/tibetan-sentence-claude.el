;;; tibetan-sentence-claude.el --- Sentence-level Claude calls, split per segment -*- lexical-binding: t -*-

;;; Commentary:
;; §5.40: send the COMPLETE SENTENCE to Claude (and DharmaMitra), not
;; just the segment — full-sentence context produces much better
;; translations — then split the response back into the per-segment
;; analysis files.
;;
;; The split is DETERMINISTIC, never heuristic: the user prompt
;; enumerates each child segment's Tibetan, and the sentence-first
;; system prompt instructs Claude to answer with `### Segment N'
;; subsections inside `## Translation' / `## Vocabulary' /
;; `## Grammar' / `## Particles'.  `## Translation' opens with the
;; fluent whole-sentence rendering (the sentence file's body) and
;; `## Grammar' with a cross-clause preamble; `## Concept Notes'
;; stays sentence-level and is copied to every child under a
;; `(Sentence N — segments A–B)' label.
;;
;; Per-segment landings are SYNTHESIZED markdown responses fed to the
;; unmodified `tibetan-analysis--insert-claude-sections', which buys
;; heading migration, the C1 sanitizer, zettel cross-linking, and the
;; auto-regen-on-particles path for free.
;;
;; Phase 1 (this lower half): the pure splitter + synthesizers.

;;; Code:

(require 'cl-lib)
(require 'tibetan-analysis-claude nil t)

;; ----------------------------------------------------------------------------
;; Subsection splitter
;; ----------------------------------------------------------------------------

(defconst tibetan-sentence-claude--subsection-re
  "^###[ \t]+Segment[ \t]+\\([0-9]+\\)[ \t]*$"
  "Regexp matching a `### Segment N' subsection header.
The standard section parser anchors on `^## ' exactly, so these
three-hash lines pass through into section bodies untouched —
the two-level parse composes cleanly.")

(defun tibetan-sentence-claude--split-subsections (body)
  "Split BODY at `### Segment N' headers.
Returns (:preamble STR-or-nil :segments ((N . STR) ...)): the
preamble is the trimmed text before the first subsection (nil when
empty), each subsection body is trimmed.  nil-safe."
  (if (or (null body) (string-empty-p (string-trim body)))
      (list :preamble nil :segments nil)
    (let ((case-fold-search nil)
          (matches '())
          (pos 0))
      (while (string-match tibetan-sentence-claude--subsection-re body pos)
        (push (list (string-to-number (match-string 1 body))
                    (match-beginning 0) (match-end 0))
              matches)
        (setq pos (match-end 0)))
      (setq matches (nreverse matches))
      (if (null matches)
          (list :preamble (string-trim body) :segments nil)
        (let* ((pre (string-trim (substring body 0 (nth 1 (car matches)))))
               (segments '()))
          (cl-loop for (num _start end) in matches
                   for rest on matches
                   do (let* ((next (cadr rest))
                             (seg-end (if next (nth 1 next) (length body)))
                             (text (string-trim (substring body end seg-end))))
                        (push (cons num text) segments)))
          (list :preamble (unless (string-empty-p pre) pre)
                :segments (nreverse segments)))))))

;; ----------------------------------------------------------------------------
;; Response parser
;; ----------------------------------------------------------------------------

(defun tibetan-sentence-claude--parse-response (response seg-nums)
  "Parse a sentence-first RESPONSE for the expected SEG-NUMS.
Returns a plist:
  :translation-whole  the `## Translation' preamble (whole sentence)
  :grammar-preamble   the `## Grammar' cross-clause preamble
  :concepts           the `## Concept Notes' body, WHOLE (never split
                      — sentence-level by design, even if Claude
                      sneaks a subsection in)
  :per-segment        ((SEG-NUM . (:translation S :vocabulary S
                                   :grammar S :particles S)) ...)
                      only for SEG-NUMS; stray numbers are ignored
  :missing            SEG-NUMS with no subsection in ANY section —
                      the caller writes a VISIBLE stub for these,
                      never a silent blank."
  (let* ((sections (if (fboundp 'tibetan-analysis--parse-claude-sections)
                       (tibetan-analysis--parse-claude-sections response)
                     nil))
         (tr (tibetan-sentence-claude--split-subsections
              (plist-get sections :translation)))
         (vo (tibetan-sentence-claude--split-subsections
              (plist-get sections :vocabulary)))
         (gr (tibetan-sentence-claude--split-subsections
              (plist-get sections :grammar)))
         (pa (tibetan-sentence-claude--split-subsections
              (plist-get sections :particles)))
         (per '())
         (missing '()))
    (dolist (n seg-nums)
      (let ((slot (list :translation (cdr (assq n (plist-get tr :segments)))
                        :vocabulary (cdr (assq n (plist-get vo :segments)))
                        :grammar (cdr (assq n (plist-get gr :segments)))
                        :particles (cdr (assq n (plist-get pa :segments))))))
        (if (cl-some (lambda (k) (plist-get slot k))
                     '(:translation :vocabulary :grammar :particles))
            (push (cons n slot) per)
          (push n missing))))
    (list :translation-whole (plist-get tr :preamble)
          :grammar-preamble (plist-get gr :preamble)
          :concepts (plist-get sections :concepts)
          :per-segment (nreverse per)
          :missing (nreverse missing))))

;; ----------------------------------------------------------------------------
;; Markdown synthesis (feeds tibetan-analysis--insert-claude-sections)
;; ----------------------------------------------------------------------------

(defun tibetan-sentence-claude--synthesize-segment-markdown (plist)
  "Build a standard five-section markdown response from PLIST.
Slots (:translation :vocabulary :grammar :particles :concepts) that
are nil produce NO heading — the section writer then leaves the
existing body untouched (preserve semantics)."
  (mapconcat
   #'identity
   (delq nil
         (mapcar (lambda (pair)
                   (let ((body (plist-get plist (car pair))))
                     (when (and body (not (string-empty-p body)))
                       (format "## %s\n%s\n" (cdr pair) body))))
                 '((:translation . "Translation")
                   (:vocabulary . "Vocabulary")
                   (:grammar . "Grammar")
                   (:particles . "Particles")
                   (:concepts . "Concept Notes"))))
   "\n"))

(defun tibetan-sentence-claude--synthesize-sentence-markdown (parsed)
  "Build the SENTENCE file's markdown from the PARSED response plist.
Translation = the whole-sentence rendering, Grammar = the cross-clause
preamble, Concept Notes = the sentence-level body."
  (tibetan-sentence-claude--synthesize-segment-markdown
   (list :translation (plist-get parsed :translation-whole)
         :grammar (plist-get parsed :grammar-preamble)
         :concepts (plist-get parsed :concepts))))

;; ----------------------------------------------------------------------------
;; Phase 2 — sentence-first prompts
;; ----------------------------------------------------------------------------

(declare-function tibetan-analysis--claude-static-system-blocks
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--read-interlinear-glosses
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--collect-zettel-references
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--format-zettel-references-block
                  "tibetan-analysis-claude")
(declare-function tibetan-sentence--collect-children-grounding
                  "tibetan-sentence-persist")
(declare-function tibetan-sentence--child-seg-filepath
                  "tibetan-sentence-persist")

(defconst tibetan-sentence-claude--system-addendum
  "

SENTENCE-FIRST MODE — this request covers a COMPLETE SENTENCE that
spans several numbered segments (the shad-delimited units your user
prompt lists under `### Segment N' headers).  Adjust the five
sections as follows, keeping all other rules unchanged:

- `## Translation': FIRST give the fluent translation of the WHOLE
  sentence (no header before it).  THEN, for EVERY listed segment, a
  `### Segment N' subsection containing the sub-translation of just
  that segment, consistent with the whole-sentence rendering.
- `## Vocabulary', `## Particles': organize ALL content under
  `### Segment N' subsections — one per listed segment, in order,
  covering every segment, using the EXACT numbers given.  No entries
  outside a subsection.
- `## Grammar': open with a 2-4 sentence cross-clause overview of the
  whole sentence (clause chain, converbs, anaphora) BEFORE the first
  subsection; then a `### Segment N' subsection per segment with the
  usual labeled bullets scoped to that segment.
- `## Concept Notes': sentence-level ONLY — no segment subsections.

Every listed segment MUST receive its subsections; never merge two
segments under one header."
  "System-prompt addendum that turns the segment schema into the
sentence-first schema.  Appended to the base segment system prompt;
constant per document, so it forms a stable Anthropic cache prefix
\(distinct from the segment-level prefix — the two coexist).")

(defun tibetan-sentence-claude--collect-children-vocab (seg-nums folder)
  "Per-child Interlinear grounding: `=== Segment N ===' labelled
`wylie = gloss' blocks from each child seg file.  nil when nothing."
  (when (and seg-nums folder
             (fboundp 'tibetan-analysis--read-interlinear-glosses)
             (fboundp 'tibetan-sentence--child-seg-filepath))
    (let ((blocks '()))
      (dolist (n seg-nums)
        (let* ((path (tibetan-sentence--child-seg-filepath n folder))
               (body (and path (tibetan-analysis--read-interlinear-glosses
                                path))))
          (when body
            (push (format "=== Segment %d ===\n%s" n body) blocks))))
      (when blocks
        (concat "\n\nPer-segment vocabulary matches (the tool's own "
                "layered dictionary lookup; dictionary-attested — base "
                "the Vocabulary subsections on them and do NOT invent "
                "meanings for listed words):\n"
                (mapconcat #'identity (nreverse blocks) "\n"))))))

(defun tibetan-sentence-claude--build-prompts (sentence source-file
                                               &optional folder)
  "Build (SYSTEM . USER) for a sentence-first call.
SENTENCE is the walker plist from
`tibetan-sentence--sentence-for-segment' (:sent-num :seg-nums
:children :tibetan-text).  SOURCE-FILE supplies the per-document
static system blocks (metadata/Portfolio/target-lang — shared helper,
cache-constant).  FOLDER locates the child seg files for grounding."
  (let* ((sent-num (plist-get sentence :sent-num))
         (seg-nums (plist-get sentence :seg-nums))
         (text (plist-get sentence :tibetan-text))
         (system (concat
                  (if (boundp 'tibetan-analysis--claude-system-prompt)
                      tibetan-analysis--claude-system-prompt
                    "")
                  tibetan-sentence-claude--system-addendum
                  (if (and source-file
                           (fboundp
                            'tibetan-analysis--claude-static-system-blocks))
                      (tibetan-analysis--claude-static-system-blocks
                       source-file)
                    "")))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed text))
                  (error nil)))
         (enumeration
          (mapconcat (lambda (c)
                       (format "### Segment %d\n%s"
                               (plist-get c :seg-num)
                               (string-trim (or (plist-get c :text) ""))))
                     (plist-get sentence :children) "\n"))
         (vocab-block (tibetan-sentence-claude--collect-children-vocab
                       seg-nums folder))
         ;; FOLDER must be explicit: the child-filepath helper falls
         ;; back to buffer-file-name-derived lookup, which errors in
         ;; headless batch (§5.34 class).  No folder → no grounding.
         (grounding-block
          (when (and folder
                     (fboundp 'tibetan-sentence--collect-children-grounding))
            (tibetan-sentence--collect-children-grounding
             seg-nums folder)))
         (zettel-block
          (when (and (fboundp 'tibetan-analysis--collect-zettel-references)
                     (fboundp 'tibetan-analysis--format-zettel-references-block))
            (tibetan-analysis--format-zettel-references-block
             (tibetan-analysis--collect-zettel-references text))))
         (user (concat
                (format "Classical Tibetan sentence (Sentence %s — segments %s):\n\n"
                        (or sent-num "?")
                        (mapconcat #'number-to-string seg-nums ", "))
                text
                (if wylie (format "\n\nWylie: %s" wylie) "")
                "\n\nThe sentence spans these segments:\n"
                enumeration
                (or vocab-block "")
                (or grounding-block "")
                (or zettel-block "")
                "\n\nProduce the five sections now, with `### Segment N' "
                "subsections exactly as instructed.")))
    (cons system user)))

(provide 'tibetan-sentence-claude)
;;; tibetan-sentence-claude.el ends here
