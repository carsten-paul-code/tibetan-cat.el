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
⟦105⟧The lama went to rNgog's place⟦/105⟧ and ⟦106⟧requested the dharma⟦/106⟧.
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
    ;; §5.42: the whole-sentence translation carries the raw span
    ;; markers; consumers strip/render them.
    (should (string-match-p "went to rNgog's place" 
                            (plist-get p :translation-whole)))
    (should (string-match-p "⟦105⟧" (plist-get p :translation-whole)))
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

;; ----------------------------------------------------------------------------
;; Phase 2 — sentence-first prompts
;; ----------------------------------------------------------------------------

(defun tstc--make-sentence (&rest children)
  "Walker-shaped plist for CHILDREN given as (SEG-NUM . TEXT) conses."
  (list :sent-num 4
        :seg-nums (mapcar #'car children)
        :children (mapcar (lambda (c)
                            (list :seg-num (car c) :text (cdr c)))
                          children)
        :tibetan-text (mapconcat #'cdr children " ")))

(ert-deftest tibetan-sentence-claude-prompt-enumerates-each-child ()
  "The user prompt carries the whole sentence AND a `### Segment N'
enumeration of every child's Tibetan, in order."
  (let* ((sent (tstc--make-sentence '(105 . "ཁོ་སོང་ནས།") '(106 . "ཆོས་བྱས།")))
         (prompts (tibetan-sentence-claude--build-prompts sent nil nil))
         (user (cdr prompts)))
    (should (string-match-p "### Segment 105\n ?ཁོ་སོང་ནས" user))
    (should (string-match-p "### Segment 106\n ?ཆོས་བྱས" user))
    (should (< (string-match "### Segment 105" user)
               (string-match "### Segment 106" user)))
    ;; Whole text appears before the enumeration.
    (should (string-match-p "ཁོ་སོང་ནས། ཆོས་བྱས།" user))))

(ert-deftest tibetan-sentence-claude-prompt-system-constant-per-document ()
  "The sentence-first system prompt is identical for two different
sentences of the same document (Anthropic cache invariant), differs
from the segment-level system prompt, and instructs the subsection
format."
  (let* ((s1 (car (tibetan-sentence-claude--build-prompts
                   (tstc--make-sentence '(1 . "བདག")) nil nil)))
         (s2 (car (tibetan-sentence-claude--build-prompts
                   (tstc--make-sentence '(7 . "ཆོས") '(8 . "བྱས")) nil nil))))
    (should (equal s1 s2))
    (should (string-match-p "### Segment" s1))
    (when (boundp 'tibetan-analysis--claude-system-prompt)
      (should-not (equal s1 tibetan-analysis--claude-system-prompt)))))

(ert-deftest tibetan-sentence-claude-prompt-child-grounding-labeled ()
  "Per-child Interlinear grounding appears under a segment label."
  (let* ((dir (make-temp-file "tstc-ground" t))
         (child (expand-file-name "seg-105.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file child
            (insert "** Interlinear Gloss\n"
                    "[[term-kho][kho]] [he]\n\n** Translation\nx\n"))
          (let* ((sent (tstc--make-sentence '(105 . "ཁོ།") '(106 . "བྱས།")))
                 (user (cdr (tibetan-sentence-claude--build-prompts
                             sent nil dir))))
            (should (string-match-p "Segment 105" user))
            (should (string-match-p "kho = he" user))))
      (delete-directory dir t))))

(ert-deftest tibetan-analysis-static-system-blocks-compose-segment-prompt ()
  "Golden regression for the refactor: the segment builder's system
prompt equals base prompt + the shared static-blocks helper output —
per-document constancy is guaranteed by construction for BOTH
builders."
  (skip-unless (fboundp 'tibetan-analysis--build-claude-prompts))
  (let ((src (make-temp-file "tstc-src" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: T\n#+TIBETAN_TARGET_LANG: de\n\n* Tibetan Text\n"))
          (let ((sys (car (tibetan-analysis--build-claude-prompts "བདག" src))))
            (should (equal sys
                           (concat tibetan-analysis--claude-system-prompt
                                   (tibetan-analysis--claude-static-system-blocks
                                    src))))
            ;; German directive present via the helper.
            (should (string-match-p "GERMAN" sys))))
      (delete-file src))))

;; ----------------------------------------------------------------------------
;; Phase 3 — dispatcher, fan-out, dedup, stubs
;; ----------------------------------------------------------------------------

(defun tstc--scaffold-seg (dir n &optional populated)
  "Write a segment-layout scaffold for segment N in DIR."
  (let ((f (expand-file-name (format "seg-%03d.org" n) dir)))
    (with-temp-file f
      (insert (format "#+TITLE: Segment %d Analysis\n\n" n)
              "* Tibetan Text\nབདག\n\n"
              "* Tibetan Analysis\n"
              "** Translation\n"
              (if populated "POPULATED TRANSLATION\n" "[Awaiting Claude…]\n")
              "\n** Claude Vocabulary\n"
              (if populated "pop, noun, \"x\"\n" "[Awaiting Claude…]\n")
              "\n** Grammar\n*** Claude Grammar\n\n"
              "** Provided Translations\n*** Claude Particles\n\n"
              "** Concept Notes\n[Awaiting Claude…]\n\n"
              "* Footnotes\n"))
    f))

(ert-deftest tibetan-sentence-claude-handle-response-writes-all ()
  "The fan-out lands each child's subsections in its own file and the
sentence-level pieces in the sent file; Concept Notes are copied to
children under the sentence label."
  (let ((dir (make-temp-file "tstc-fan" t)))
    (unwind-protect
        (let* ((c105 (tstc--scaffold-seg dir 105))
               (c106 (tstc--scaffold-seg dir 106))
               (sent (expand-file-name "sent-004.org" dir)))
          (with-temp-file sent
            (insert "#+TITLE: Sentence 4 Analysis\n\n"
                    "* Tibetan Text\nx\n\n* Tibetan Analysis\n"
                    "** Claude Vocabulary\n\n** Translation\n[Awaiting Claude…]\n\n"
                    "** Grammar\n*** Claude Grammar\n\n"
                    "** Concept Notes\n[Awaiting Claude…]\n\n* Footnotes\n"))
          (tibetan-sentence-claude--handle-response
           tstc--full-response
           (list :sent-num 4 :seg-nums '(105 106)
                 :child-files (list c105 c106) :sent-file sent :force t))
          (let ((s105 (with-temp-buffer (insert-file-contents c105)
                                        (buffer-string)))
                (s106 (with-temp-buffer (insert-file-contents c106)
                                        (buffer-string)))
                (ssent (with-temp-buffer (insert-file-contents sent)
                                         (buffer-string))))
            (should (string-match-p "Having gone" s105))
            (should (string-match-p "rngog, proper noun" s105))
            (should (string-match-p "requested the dharma" s106))
            ;; Concept Notes labelled + copied to children.
            (should (string-match-p "(Sentence 4 — segments 105–106)" s105))
            (should (string-match-p "four pillars" s105))
            ;; Sent file: whole translation + grammar preamble.
            (should (string-match-p "went to rNgog's place and requested"
                                    ssent))
            (should (string-match-p "two-clause chain" ssent))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-claude-handle-response-missing-stub ()
  "A child absent from the response gets a VISIBLE stub — never a
silent blank — and the stub counts as still-needing a request."
  (let ((dir (make-temp-file "tstc-miss" t)))
    (unwind-protect
        (let ((c105 (tstc--scaffold-seg dir 105))
              (c107 (tstc--scaffold-seg dir 107)))
          (tibetan-sentence-claude--handle-response
           tstc--full-response
           (list :sent-num 4 :seg-nums '(105 107)
                 :child-files (list c105 c107) :sent-file nil :force t))
          (let ((s107 (with-temp-buffer (insert-file-contents c107)
                                        (buffer-string))))
            (should (string-match-p "\\[Claude sentence response missing Segment 107"
                                    s107)))
          (should (tibetan-analysis--claude-needs-request-p c107)))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-claude-landing-gate ()
  "Non-FORCE: a populated child keeps its content; the empty sibling
is filled.  FORCE: both rewritten."
  (let ((dir (make-temp-file "tstc-gate" t)))
    (unwind-protect
        (let ((c105 (tstc--scaffold-seg dir 105 'populated))
              (c106 (tstc--scaffold-seg dir 106)))
          (tibetan-sentence-claude--handle-response
           tstc--full-response
           (list :sent-num 4 :seg-nums '(105 106)
                 :child-files (list c105 c106) :sent-file nil :force nil))
          (should (string-match-p "POPULATED TRANSLATION"
                                  (with-temp-buffer
                                    (insert-file-contents c105)
                                    (buffer-string))))
          (should (string-match-p "requested the dharma"
                                  (with-temp-buffer
                                    (insert-file-contents c106)
                                    (buffer-string))))
          ;; FORCE pass overwrites the populated child too.
          (tibetan-sentence-claude--handle-response
           tstc--full-response
           (list :sent-num 4 :seg-nums '(105 106)
                 :child-files (list c105 c106) :sent-file nil :force t))
          (should (string-match-p "Having gone"
                                  (with-temp-buffer
                                    (insert-file-contents c105)
                                    (buffer-string)))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-claude-dispatch-dedup-and-fallbacks ()
  "Two children of one sentence → ONE queue submit; flat layout /
single-segment sentences → nil (caller falls back to per-segment)."
  (let ((dir (make-temp-file "tstc-disp" t))
        (submits 0))
    (unwind-protect
        (let* ((src (expand-file-name "doc.org" dir)))
          ;; §5.44: children carry a #+SOURCE link to doc.org so the
          ;; suffix-aware resolver reuses these bare names (single-source
          ;; folder).  A bare file with no parseable #+SOURCE is treated
          ;; as not-ours, so the resolver would otherwise look for a
          ;; `-doc' suffix and the file-exists gate would fail.
          (dolist (n '(105 106))
            (with-temp-file (expand-file-name (format "seg-%03d.org" n) dir)
              (insert (format
                       "#+SOURCE: [[file:doc.org::*Segment %d][doc / Segment %d]]\n"
                       n n)
                      "* Tibetan Text\nx\n")))
          (with-temp-file src
            (insert "#+TITLE: D\n\n* Tibetan Text\n"
                    "*** Sentence 4\n"
                    "**** Segment 105\nབདག\n\n"
                    "**** Segment 106\nཆོས\n\n"
                    "*** Sentence 5\n"
                    "**** Segment 107\nབདག\n"))
          (tibetan-sentence-claude-clear-inflight)
          (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                     (lambda (&rest _) (cl-incf submits))))
            ;; Two children, same sentence → one submit.
            (should (eq 'fired
                        (tibetan-analysis--fire-sentence-level
                         "བདག" (expand-file-name "seg-105.org" dir)
                         src 105 t)))
            (should (eq 'dedup-hit
                        (tibetan-analysis--fire-sentence-level
                         "ཆོས" (expand-file-name "seg-106.org" dir)
                         src 106 t)))
            (should (= 1 submits))
            ;; Single-seg sentence → nil (fall back).
            (should-not (tibetan-analysis--fire-sentence-level
                         "བདག" (expand-file-name "seg-107.org" dir)
                         src 107 t))
            ;; Flat layout → nil.
            (let ((flat (expand-file-name "flat.org" dir)))
              (with-temp-file flat
                (insert "* Tibetan Text\n** Section 1\n*** Segment 9\nབདག\n"))
              (should-not (tibetan-analysis--fire-sentence-level
                           "བདག" (expand-file-name "seg-009.org" dir)
                           flat 9 t)))))
      (tibetan-sentence-claude-clear-inflight)
      (delete-directory dir t))))

;; ----------------------------------------------------------------------------
;; Phase 5 — fire-site wiring
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-claude-reanalyze-routes-to-dispatcher ()
  "reanalyze-file with re-request: when the dispatcher CLAIMS the
sentence, the per-segment Claude and DM fires are suppressed; when it
DECLINES (nil), the per-segment path fires unchanged."
  (let ((dir (make-temp-file "tstc-wire" t))
        (per-seg-claude 0) (per-seg-dm 0) (dispatcher 'fired))
    (unwind-protect
        (let ((f (tstc--scaffold-seg dir 105)))
          (cl-letf (((symbol-function 'tibetan-analysis--fire-sentence-level)
                     (lambda (&rest _) dispatcher))
                    ((symbol-function 'tibetan-analysis--request-claude-translation)
                     (lambda (&rest _) (cl-incf per-seg-claude)))
                    ((symbol-function 'tibetan-dharmamitra-translation-fire-for-segment)
                     (lambda (&rest _) (cl-incf per-seg-dm)))
                    ((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (&rest _) "** Wylie Transliteration\nx\n")))
            ;; Dispatcher claims → no per-segment fires.
            (tibetan-analysis-reanalyze-file f :re-request-claude t)
            (should (= 0 per-seg-claude))
            (should (= 0 per-seg-dm))
            ;; Dispatcher declines → per-segment fires as before.
            (setq dispatcher nil)
            (tibetan-analysis-reanalyze-file f :re-request-claude t)
            (should (= 1 per-seg-claude))
            (should (= 1 per-seg-dm))))
      (when (get-file-buffer (expand-file-name "seg-105.org" dir))
        (kill-buffer (get-file-buffer (expand-file-name "seg-105.org" dir))))
      (delete-directory dir t))))

;; ----------------------------------------------------------------------------
;; §5.42 — own-segment span highlighting in the whole-sentence translation
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-sentence-claude-render-marked-whole-basic ()
  "Own pair → ⟪…⟫; sibling markers stripped; no ⟦ tokens survive."
  (let ((out (tibetan-sentence-claude--render-marked-whole
              "⟦105⟧He went⟦/105⟧ and ⟦106⟧asked⟦/106⟧." 105)))
    (should (equal "⟪He went⟫ and asked." out)))
  ;; The other child sees ITS span highlighted.
  (let ((out (tibetan-sentence-claude--render-marked-whole
              "⟦105⟧He went⟦/105⟧ and ⟦106⟧asked⟦/106⟧." 106)))
    (should (equal "He went and ⟪asked⟫." out))))

(ert-deftest tibetan-sentence-claude-render-marked-whole-degrades ()
  "Missing / duplicated / unbalanced own markers → ALL tokens stripped,
plain whole returned (Pitfall B: a raw ⟦ must never land)."
  ;; Own marker missing entirely.
  (should (equal "He went and asked."
                 (tibetan-sentence-claude--render-marked-whole
                  "⟦106⟧He went⟦/106⟧ and asked." 105)))
  ;; Duplicated own open-marker.
  (should (equal "a b c"
                 (tibetan-sentence-claude--render-marked-whole
                  "⟦105⟧a ⟦105⟧b⟦/105⟧ c" 105)))
  ;; Close before open.
  (should (equal "x y"
                 (tibetan-sentence-claude--render-marked-whole
                  "⟦/105⟧x ⟦105⟧y" 105)))
  ;; nil-safe.
  (should-not (tibetan-sentence-claude--render-marked-whole nil 105)))

(ert-deftest tibetan-sentence-claude-render-marked-whole-multiline ()
  "A span crossing newlines splits into one ⟪…⟫ pair PER LINE
\(Pitfall A: the single-line font-lock pattern must match each)."
  (let ((out (tibetan-sentence-claude--render-marked-whole
              "⟦105⟧first line\nsecond line⟦/105⟧ tail" 105)))
    (should (equal "⟪first line⟫\n⟪second line⟫ tail" out))))

(ert-deftest tibetan-sentence-claude-child-translation-layout ()
  "End-to-end: the child's Translation = label + highlighted whole +
blank line + `This segment:' sub-translation; NO ⟦ token lands in any
file; the sent file's whole translation is marker-free."
  (let ((dir (make-temp-file "tstc-span" t)))
    (unwind-protect
        (let* ((c105 (tstc--scaffold-seg dir 105))
               (c106 (tstc--scaffold-seg dir 106))
               (sent (expand-file-name "sent-004.org" dir)))
          (with-temp-file sent
            (insert "#+TITLE: Sentence 4 Analysis\n\n"
                    "* Tibetan Text\nx\n\n* Tibetan Analysis\n"
                    "** Translation\n[Awaiting Claude…]\n\n"
                    "** Grammar\n*** Claude Grammar\n\n* Footnotes\n"))
          (tibetan-sentence-claude--handle-response
           tstc--full-response
           (list :sent-num 4 :seg-nums '(105 106)
                 :child-files (list c105 c106) :sent-file sent :force t))
          (let ((s105 (with-temp-buffer (insert-file-contents c105)
                                        (buffer-string)))
                (ssent (with-temp-buffer (insert-file-contents sent)
                                         (buffer-string))))
            ;; Label + highlighted whole + own line.
            (should (string-match-p "(Sentence 4 — segments 105–106)" s105))
            (should (string-match-p "⟪The lama went to rNgog's place⟫"
                                    s105))
            (should (string-match-p "This segment: Having gone" s105))
            ;; No raw markers anywhere.
            (should-not (string-match-p "⟦" s105))
            (should-not (string-match-p "⟦" ssent))
            ;; Sent file: plain whole, no highlight glyphs either.
            (should (string-match-p "The lama went to rNgog's place and"
                                    ssent))
            (should-not (string-match-p "⟪" ssent))))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-claude-sentence-label-body-is-populated ()
  "A Translation body opening with the `(Sentence …)' label counts as
POPULATED for the needs-request gate."
  (skip-unless (fboundp 'tibetan-analysis--claude-needs-request-p))
  (let ((dir (make-temp-file "tstc-pop" t)))
    (unwind-protect
        (let ((f (expand-file-name "seg-009.org" dir)))
          (with-temp-file f
            (insert "* Tibetan Analysis\n** Translation\n"
                    "(Sentence 2 — segments 8–9)\nWhole text here.\n\n"
                    "This segment: part.\n\n"
                    "** Claude Vocabulary\nx, noun, \"y\"\n"))
          (should-not (tibetan-analysis--claude-needs-request-p f)))
      (delete-directory dir t))))

(ert-deftest tibetan-sentence-claude-fire-resolves-suffixed-children ()
  "§5.44: `tibetan-analysis--fire-sentence-level' must resolve its child
seg / sent files through the §5.23/§5.37 suffix resolver, so the
sentence path FIRES in a suffixed multi-source folder instead of
falling back to per-segment.  With bare `seg-NNN.org' paths (the old
hardcode) the file-exists gate fails in such a folder and the dispatcher
returns nil."
  (let* ((root (make-temp-file "tstc-suffix" t))
         (src (expand-file-name "source.org" root))
         (folder (file-name-as-directory (expand-file-name "analysis" root))))
    (unwind-protect
        (progn
          (make-directory folder t)
          (with-temp-file src
            (insert "#+TITLE: T\n\n* Tibetan Text\n"
                    "*** Sentence 1\n**** Segment 1\nབདག\n\n"
                    "**** Segment 2\nཅིག\n"))
          ;; SUFFIXED children only (source short-name = "source");
          ;; the bare `seg-001.org' / `seg-002.org' deliberately absent.
          (with-temp-file (expand-file-name "seg-001-source.org" folder)
            (insert "x\n"))
          (with-temp-file (expand-file-name "seg-002-source.org" folder)
            (insert "x\n"))
          (let ((requested nil) (dm nil))
            (cl-letf (((symbol-function 'tibetan-sentence-claude--claim)
                       (lambda (&rest _) t))
                      ((symbol-function 'tibetan-sentence-claude--request)
                       (lambda (&rest _) (setq requested t)))
                      ((symbol-function 'tibetan-sentence-claude--schedule-dm)
                       (lambda (&rest _) (setq dm t))))
              (let ((r (tibetan-analysis--fire-sentence-level
                        "" (expand-file-name "seg-001-source.org" folder)
                        src 1 t)))
                (should (eq r 'fired))
                (should requested)
                (should dm)))))
      (delete-directory root t))))

(provide 'tibetan-sentence-claude-test)
;;; tibetan-sentence-claude-test.el ends here
