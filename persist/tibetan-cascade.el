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

(provide 'tibetan-cascade)
;;; tibetan-cascade.el ends here
