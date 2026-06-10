;;; tibetan-sentence-claude-test.el --- Tests for sentence-level Claude calls -*- lexical-binding: t -*-

;;; Commentary:
;; Phase 1 of the sentence-level translation redesign (§5.40): the
;; response splitter.  Claude self-segments its answer with
;; `### Segment N' subsections; the split back to seg files is a
;; deterministic parse — no heuristics, no network.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-sentence-claude)

(defconst tstc--full-response
  "## Translation
The lama went to rNgog's place and requested the dharma.
### Segment 105
Having gone to rNgog's place,
### Segment 106
[he] requested the dharma.

## Vocabulary
### Segment 105
rngog, proper noun, \"rNgog\", a disciple
### Segment 106
chos, noun, \"dharma\", the teaching

## Grammar
A two-clause chain: ablative converb then main verb.
### Segment 105
- *Verb backbone:* phyin is the past of 'gro.
### Segment 106
- *Verb backbone:* zhus is the past of zhu.

## Particles
### Segment 105
nas, nas, 2.11, ablative converb
### Segment 106
la, la, 1.4, dative

## Concept Notes
- **rNgog** — one of Mar pa's four pillars.
"
  "A complete sentence-first response for segments 105+106.")

;; ----------------------------------------------------------------------------
;; --split-subsections
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-claude-split-subsections-basic ()
  "Preamble before the first `### Segment' is separated; subsections
keyed by number."
  (let ((r (tibetan-sentence-claude--split-subsections
            "whole text here\n### Segment 105\nfoo\nbar\n### Segment 106\nbaz\n")))
    (should (equal "whole text here" (plist-get r :preamble)))
    (should (equal "foo\nbar" (cdr (assq 105 (plist-get r :segments)))))
    (should (equal "baz" (cdr (assq 106 (plist-get r :segments)))))))

(ert-deftest tibetan-sentence-claude-split-subsections-no-preamble-no-subs ()
  "No subsections → everything is preamble; empty body → both nil."
  (let ((r (tibetan-sentence-claude--split-subsections "just text")))
    (should (equal "just text" (plist-get r :preamble)))
    (should-not (plist-get r :segments)))
  (let ((r (tibetan-sentence-claude--split-subsections "")))
    (should-not (plist-get r :preamble))
    (should-not (plist-get r :segments))))

;; ----------------------------------------------------------------------------
;; --parse-response
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-claude-parse-full-response ()
  "All slots populated from the canonical response; :missing nil."
  (let* ((p (tibetan-sentence-claude--parse-response
             tstc--full-response '(105 106)))
         (s105 (cdr (assq 105 (plist-get p :per-segment))))
         (s106 (cdr (assq 106 (plist-get p :per-segment)))))
    (should (string-match-p "went to rNgog's place and requested"
                            (plist-get p :translation-whole)))
    (should (string-match-p "two-clause chain"
                            (plist-get p :grammar-preamble)))
    (should (string-match-p "four pillars" (plist-get p :concepts)))
    (should (string-match-p "Having gone" (plist-get s105 :translation)))
    (should (string-match-p "rngog, proper noun"
                            (plist-get s105 :vocabulary)))
    (should (string-match-p "phyin is the past" (plist-get s105 :grammar)))
    (should (string-match-p "ablative converb" (plist-get s105 :particles)))
    (should (string-match-p "requested the dharma"
                            (plist-get s106 :translation)))
    (should-not (plist-get p :missing))))

(ert-deftest tibetan-sentence-claude-parse-missing-segment ()
  "A segment absent from every section lands in :missing; the others
parse normally."
  (let ((p (tibetan-sentence-claude--parse-response
            tstc--full-response '(105 106 107))))
    (should (equal '(107) (plist-get p :missing)))
    (should (cdr (assq 105 (plist-get p :per-segment))))))

(ert-deftest tibetan-sentence-claude-parse-out-of-order ()
  "Subsections in any order key correctly."
  (let* ((resp "## Vocabulary\n### Segment 7\nseven\n### Segment 5\nfive\n")
         (p (tibetan-sentence-claude--parse-response resp '(5 7)))
         (s5 (cdr (assq 5 (plist-get p :per-segment)))))
    (should (equal "five" (plist-get s5 :vocabulary)))))

(ert-deftest tibetan-sentence-claude-parse-no-subsections-at-all ()
  "Claude ignored the format → :per-segment empty, ALL seg-nums
missing, whole bodies in the sentence-level slots (the visible-stub
path downstream — never silent)."
  (let ((p (tibetan-sentence-claude--parse-response
            "## Translation\njust prose\n## Vocabulary\nwords\n"
            '(5 6))))
    (should (equal '(5 6) (plist-get p :missing)))
    (should-not (plist-get p :per-segment))
    (should (equal "just prose" (plist-get p :translation-whole)))))

(ert-deftest tibetan-sentence-claude-parse-unexpected-segment-number ()
  "A `### Segment 999' not in SEG-NUMS is ignored, not crashed on."
  (let ((p (tibetan-sentence-claude--parse-response
            "## Vocabulary\n### Segment 999\nstray\n### Segment 5\nok\n"
            '(5))))
    (should (equal "ok" (plist-get (cdr (assq 5 (plist-get p :per-segment)))
                                   :vocabulary)))
    (should-not (assq 999 (plist-get p :per-segment)))))

(ert-deftest tibetan-sentence-claude-parse-concepts-never-split ()
  "Concept Notes stay sentence-level even if Claude sneaks a
`### Segment' inside — the whole body is kept."
  (let ((p (tibetan-sentence-claude--parse-response
            "## Concept Notes\nintro\n### Segment 5\nper-seg note\n"
            '(5))))
    (should (string-match-p "intro" (plist-get p :concepts)))
    (should (string-match-p "per-seg note" (plist-get p :concepts)))))

;; ----------------------------------------------------------------------------
;; Synthesis round-trip
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-claude-synthesize-segment-roundtrip ()
  "Synthesized per-segment markdown parses back identically through
the standard section parser (the write fan-out feeds it to
`tibetan-analysis--insert-claude-sections')."
  (skip-unless (fboundp 'tibetan-analysis--parse-claude-sections))
  (let* ((plist '(:translation "T body" :vocabulary "V body"
                  :grammar "G body" :particles "P body"
                  :concepts "C body"))
         (md (tibetan-sentence-claude--synthesize-segment-markdown plist))
         (back (tibetan-analysis--parse-claude-sections md)))
    (should (equal "T body" (plist-get back :translation)))
    (should (equal "V body" (plist-get back :vocabulary)))
    (should (equal "G body" (plist-get back :grammar)))
    (should (equal "P body" (plist-get back :particles)))
    (should (equal "C body" (plist-get back :concepts)))))

(ert-deftest tibetan-sentence-claude-synthesize-skips-nil-slots ()
  "nil slots produce NO section heading — the writer then leaves the
existing body untouched (preserve semantics)."
  (let ((md (tibetan-sentence-claude--synthesize-segment-markdown
             '(:translation "T only"))))
    (should (string-match-p "^## Translation$" md))
    (should-not (string-match-p "^## Vocabulary$" md))
    (should-not (string-match-p "^## Grammar$" md))))

(provide 'tibetan-sentence-claude-test)
;;; tibetan-sentence-claude-test.el ends here
