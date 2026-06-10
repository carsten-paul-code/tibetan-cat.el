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

(provide 'tibetan-sentence-claude)
;;; tibetan-sentence-claude.el ends here
