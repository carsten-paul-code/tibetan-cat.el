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
;; §5.42 — own-segment span markers in the whole-sentence translation
;; ----------------------------------------------------------------------------

(defconst tibetan-sentence-claude--span-token-re "⟦/?[0-9]+⟧"
  "Any segment-span marker token (`⟦N⟧' or `⟦/N⟧') in the
whole-sentence translation.")

(defun tibetan-sentence-claude--strip-span-markers (s)
  "Remove every span-marker token from S.  nil-safe.
A raw `⟦' must NEVER land in a file — every consumer that does not
convert markers strips them unconditionally."
  (when s
    (replace-regexp-in-string "⟦/?[0-9]+⟧" "" s)))

(defun tibetan-sentence-claude--render-marked-whole (whole n)
  "Render WHOLE (the marked whole-sentence translation) for child N.
When WHOLE contains exactly one `⟦N⟧' before exactly one `⟦/N⟧', the
own span becomes `⟪…⟫' (split into one pair PER LINE — the font-lock
pattern is single-line) and all other marker tokens are stripped.
Any irregularity (missing, duplicated, inverted markers) degrades to
the fully stripped plain translation.  nil-safe."
  (when whole
    (let* ((open-tok (format "⟦%d⟧" n))
           (close-tok (format "⟦/%d⟧" n))
           (open-count 0) (close-count 0) (pos 0))
      (while (string-match (regexp-quote open-tok) whole pos)
        (cl-incf open-count) (setq pos (match-end 0)))
      (setq pos 0)
      (while (string-match (regexp-quote close-tok) whole pos)
        (cl-incf close-count) (setq pos (match-end 0)))
      (let ((open-at (string-match (regexp-quote open-tok) whole))
            (close-at (string-match (regexp-quote close-tok) whole)))
        (if (not (and (= open-count 1) (= close-count 1)
                      open-at close-at (< open-at close-at)))
            ;; Degrade: strip everything (Pitfall B).
            (tibetan-sentence-claude--strip-span-markers whole)
          (let* ((prefix (substring whole 0 open-at))
                 (span (substring whole (+ open-at (length open-tok))
                                  close-at))
                 (suffix (substring whole (+ close-at (length close-tok))))
                 ;; Pitfall A: one ⟪…⟫ pair per line.
                 (highlighted
                  (mapconcat (lambda (line)
                               (if (string-empty-p (string-trim line))
                                   line
                                 (format "⟪%s⟫" line)))
                             (split-string
                              (tibetan-sentence-claude--strip-span-markers
                               span)
                              "\n")
                             "\n")))
            (concat (tibetan-sentence-claude--strip-span-markers prefix)
                    highlighted
                    (tibetan-sentence-claude--strip-span-markers
                     suffix))))))))

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
   (list :translation (tibetan-sentence-claude--strip-span-markers
                       (plist-get parsed :translation-whole))
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
  sentence (no header before it).  Inside that whole-sentence
  translation, wrap the English span corresponding to EACH listed
  segment in markers: `⟦N⟧' before it and `⟦/N⟧' after it, using the
  exact segment numbers — every listed segment exactly once, no
  nesting, no overlaps (English may reorder the segments; mark the
  spans wherever they fall).  THEN, for EVERY listed segment, a
  `### Segment N' subsection containing the sub-translation of just
  that segment, consistent with the whole-sentence rendering (NO
  markers inside the subsections).
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

;; ----------------------------------------------------------------------------
;; Phase 3 — dispatcher, write fan-out, dedup registry
;; ----------------------------------------------------------------------------

(declare-function tibetan-analysis--insert-claude-sections
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--claude-needs-request-p
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--write-claude-failure-stub
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--ensure-gptel-ready
                  "tibetan-analysis-claude")
(declare-function tibetan-analysis--claude-status-rate-limited-p
                  "tibetan-analysis-claude")
(declare-function tibetan-sentence--sentence-for-segment
                  "tibetan-sentence-persist")
(declare-function tibetan-sentence--filepath "tibetan-sentence-persist")
(declare-function tibetan-claude-queue-submit "tibetan-claude-queue")
(declare-function tibetan-sanskrit-parallel--source-mode-parallel-p
                  "tibetan-sanskrit-parallel")
(declare-function gptel-request "gptel")
(defvar gptel-cache)

(defcustom tibetan-dharmamitra-sentence-request-delay 6.5
  "Seconds between scheduled sentence-level DharmaMitra fires.
DharmaMitra rate-limits at ~10 requests/minute (§5.29 history); a
batch firing 57 sentences must stagger.  Each scheduled fire adds
this delay to a cumulative counter, reset by
`tibetan-sentence-claude-clear-inflight'."
  :type 'number
  :group 'tibetan-cat)

(defvar tibetan-sentence-claude--dm-schedule-count 0
  "Cumulative counter for staggering sentence-level DM fires.")

(declare-function tibetan-dharmamitra-translation-fire-tibetan-sentence
                  "tibetan-dharmamitra-translation")

(defun tibetan-sentence-claude--schedule-dm (sentence child-files
                                             sent-file force)
  "Schedule the sentence-level DM fire, staggered against the 10/min
rate limit.  Timers run during the batch drain loop's
`accept-process-output'."
  (when (fboundp 'tibetan-dharmamitra-translation-fire-tibetan-sentence)
    (let ((delay (* tibetan-sentence-claude--dm-schedule-count
                    tibetan-dharmamitra-sentence-request-delay)))
      (cl-incf tibetan-sentence-claude--dm-schedule-count)
      (run-at-time
       delay nil
       (lambda ()
         (condition-case err
             (tibetan-dharmamitra-translation-fire-tibetan-sentence
              (plist-get sentence :tibetan-text)
              (plist-get sentence :sent-num)
              (plist-get sentence :seg-nums)
              child-files sent-file force)
           (error (message "Sentence DM fire failed (Sentence %s): %s"
                           (plist-get sentence :sent-num)
                           (error-message-string err)))))))))

(defvar tibetan-sentence-claude--inflight (make-hash-table :test #'equal)
  "In-flight sentence-level requests, keyed (TRUENAME . SENT-NUM).
A batch over 12 children of one sentence fires the call ONCE; the
later children see the claim and skip.  Entries are released in the
queue job's done path (ok AND fail).  Content gates — not this
registry — decide refiring on the next run, so a stale entry after a
crash only suppresses until `tibetan-sentence-claude-clear-inflight'.")

(defun tibetan-sentence-claude-clear-inflight ()
  "Clear the sentence-level in-flight registry (crash recovery)."
  (interactive)
  (clrhash tibetan-sentence-claude--inflight)
  (setq tibetan-sentence-claude--dm-schedule-count 0)
  (message "Sentence-level in-flight registry cleared"))

(defun tibetan-sentence-claude--claim (source-file sent-num label)
  "Claim (SOURCE-FILE . SENT-NUM); nil when already in flight."
  (let ((key (cons (file-truename source-file) sent-num)))
    (unless (gethash key tibetan-sentence-claude--inflight)
      (puthash key (list :label label) tibetan-sentence-claude--inflight)
      key)))

(defun tibetan-sentence-claude--release (key)
  "Release the in-flight claim KEY."
  (when key (remhash key tibetan-sentence-claude--inflight)))

(defun tibetan-sentence-claude--segment-label (sent-num seg-nums)
  "The `(Sentence N — segments A–B)' label line."
  (format "(Sentence %s — segments %s–%s)"
          sent-num (apply #'min seg-nums) (apply #'max seg-nums)))

(defun tibetan-sentence-claude--handle-response (response ctx)
  "Land a sentence-first RESPONSE into the files named by CTX.
CTX: (:sent-num N :seg-nums L :child-files L :sent-file F-or-nil
:force BOOL).  Per child: synthesize a standard five-section response
from its subsections and feed `tibetan-analysis--insert-claude-sections'
\(landing-gated: non-FORCE skips children whose Translation/Vocabulary
is already populated — M7 discipline).  Concept Notes are copied to
every child under the sentence label.  Children missing from the
response get a VISIBLE stub via the failure-stub writer — never a
silent blank.  The sent file gets the whole-sentence pieces."
  (let* ((sent-num (plist-get ctx :sent-num))
         (seg-nums (plist-get ctx :seg-nums))
         (child-files (plist-get ctx :child-files))
         (sent-file (plist-get ctx :sent-file))
         (force (plist-get ctx :force))
         (parsed (tibetan-sentence-claude--parse-response response seg-nums))
         (label (tibetan-sentence-claude--segment-label sent-num seg-nums))
         (concepts (plist-get parsed :concepts))
         (labelled-concepts
          (when (and concepts (not (string-empty-p concepts)))
            (concat label "\n" concepts))))
    (cl-loop for n in seg-nums
             for file in child-files
             do
             (let ((slot (cdr (assq n (plist-get parsed :per-segment)))))
               (cond
                ((null slot)
                 ;; Missing from the response → visible stub (the
                 ;; stub writer only fills empty/placeholder slots,
                 ;; so populated content survives).
                 (when (and file (file-exists-p file)
                            (fboundp 'tibetan-analysis--write-claude-failure-stub))
                   (tibetan-analysis--write-claude-failure-stub
                    file
                    (format "[Claude sentence response missing Segment %d — re-run C-c u R]"
                            n))))
                ((and file (file-exists-p file)
                      (or force
                          (tibetan-analysis--claude-needs-request-p file)))
                 ;; §5.42: the child's Translation = sentence label +
                 ;; the WHOLE-sentence translation with THIS segment's
                 ;; span highlighted (⟪…⟫, markers from the schema) +
                 ;; the standalone sub-translation.
                 (let* ((sub (plist-get slot :translation))
                        (whole (plist-get parsed :translation-whole))
                        (rendered
                         (and whole
                              (tibetan-sentence-claude--render-marked-whole
                               whole n)))
                        (new-tr
                         (cond
                          ((and rendered sub)
                           (concat label "\n" rendered
                                   "\n\nThis segment: " sub))
                          (rendered (concat label "\n" rendered))
                          (t sub)))
                        (slot2 (copy-sequence slot)))
                   (setq slot2 (plist-put slot2 :translation new-tr))
                   (tibetan-analysis--insert-claude-sections
                    (tibetan-sentence-claude--synthesize-segment-markdown
                     (append slot2 (list :concepts labelled-concepts)))
                    file))))))
    (when (and sent-file (file-exists-p sent-file))
      (let ((md (tibetan-sentence-claude--synthesize-sentence-markdown
                 parsed)))
        (when (and md (not (string-empty-p md))
                   (or force
                       (tibetan-analysis--claude-needs-request-p sent-file)))
          (tibetan-analysis--insert-claude-sections md sent-file))))))

(defun tibetan-sentence-claude--request (sentence child-files sent-file
                                         source-file folder force)
  "Queue the sentence-first Claude request.  Mirrors
`tibetan-analysis--request-claude-translation' (429 retry via the
queue; on exhaustion a visible failure stub lands in every child that
is still empty)."
  (require 'tibetan-claude-queue)
  (let* ((sent-num (plist-get sentence :sent-num))
         (seg-nums (plist-get sentence :seg-nums))
         (label (format "sent-%03d (segs %s)" (or sent-num 0)
                        (mapconcat #'number-to-string seg-nums ",")))
         (ctx (list :sent-num sent-num :seg-nums seg-nums
                    :child-files child-files :sent-file sent-file
                    :force force))
         (claim-key (cons (file-truename source-file) sent-num)))
    (tibetan-claude-queue-submit
     (lambda (done)
       (condition-case err
           (progn
             (unless (and (featurep 'gptel) (fboundp 'gptel-request))
               (error "gptel not loaded"))
             (when (fboundp 'tibetan-analysis--ensure-gptel-ready)
               (tibetan-analysis--ensure-gptel-ready))
             (let* ((prompts (tibetan-sentence-claude--build-prompts
                              sentence source-file folder))
                    (gptel-cache '(system)))
               (gptel-request
                (cdr prompts)
                :system (car prompts)
                :callback
                (lambda (response info)
                  (cond
                   ((and response (stringp response)
                         (not (string-empty-p response)))
                    ;; CRITICAL: defer the fan-out OUT of the gptel
                    ;; curl sentinel.  Landing N children (plus the
                    ;; auto-regen cascade) inside the sentinel
                    ;; corrupted gptel's process-buffer parsing
                    ;; (\"Search failed: <boundary>\" → batch emacs
                    ;; died mid-queue, first live re-fire 2026-06-10).
                    (run-at-time
                     0 nil
                     (lambda ()
                       (condition-case e
                           (tibetan-sentence-claude--handle-response
                            response ctx)
                         (error (message
                                 "Sentence-first insert failed (%s): %s"
                                 label (error-message-string e))))
                       (tibetan-sentence-claude--release claim-key)))
                    (funcall done '(:status ok)))
                   ((and (fboundp 'tibetan-analysis--claude-status-rate-limited-p)
                         (tibetan-analysis--claude-status-rate-limited-p info))
                    (funcall done '(:status rate-limited)))
                   (t
                    (tibetan-sentence-claude--release claim-key)
                    (funcall done
                             (list :status 'error
                                   :error (format "%s"
                                                  (or (and (listp info)
                                                           (plist-get info :status))
                                                      "no response"))))))))))
         (error
          (tibetan-sentence-claude--release claim-key)
          (funcall done (list :status 'error
                              :error (error-message-string err))))))
     :label label
     :on-fail
     (lambda (status)
       (tibetan-sentence-claude--release claim-key)
       (let ((msg (format "[Claude request failed: %s — re-run C-c u R later]"
                          (or (plist-get status :error)
                              (plist-get status :status) "unknown"))))
         (dolist (f child-files)
           (when (and f (file-exists-p f)
                      (fboundp 'tibetan-analysis--write-claude-failure-stub))
             (tibetan-analysis--write-claude-failure-stub f msg))))))))

(defun tibetan-analysis--fire-sentence-level (tibetan-text analysis-file
                                              source-file seg-id
                                              &optional force)
  "Fire ONE sentence-level Claude call for the sentence containing
SEG-ID, when applicable.  Returns nil when the sentence path does NOT
apply (flat layout, single-segment sentence, parallel-Sanskrit source,
missing child files, fire-gate says no) — the caller then runs the
existing per-segment fire UNCHANGED.  Returns `fired' or `dedup-hit'
when the sentence path owns this segment (caller must NOT also fire
per-segment Claude)."
  (ignore tibetan-text)
  (when (and analysis-file source-file seg-id
             (fboundp 'tibetan-sentence--sentence-for-segment)
             ;; Parallel-Sanskrit docs keep their three-call chain.
             (not (and (fboundp 'tibetan-sanskrit-parallel--source-mode-parallel-p)
                       (tibetan-sanskrit-parallel--source-mode-parallel-p
                        source-file))))
    (let ((sentence (condition-case nil
                        (tibetan-sentence--sentence-for-segment
                         seg-id source-file)
                      (error nil))))
      (when (and sentence (> (length (plist-get sentence :seg-nums)) 1))
        (let* ((folder (file-name-directory (expand-file-name analysis-file)))
               (seg-nums (plist-get sentence :seg-nums))
               ;; §5.44: resolve child seg / sent paths through the
               ;; §5.23/§5.37 suffix-aware resolvers (bare for an
               ;; un-migrated single-source folder, `-SHORT' for a
               ;; multi-source one).  The previous hardcoded bare
               ;; `seg-%03d.org' / `sent-%03d.org' didn't exist in a
               ;; suffixed folder, so the `cl-every #'file-exists-p'
               ;; gate below failed and the sentence path silently fell
               ;; back to per-segment Claude (no fan-out, no §5.42 span).
               (short (and (fboundp 'tibetan-analysis-make-short-name)
                           (tibetan-analysis-make-short-name source-file)))
               (child-files
                (mapcar (lambda (n)
                          (if (fboundp 'tibetan-analysis--resolve-filepath)
                              (tibetan-analysis--resolve-filepath
                               folder n short source-file)
                            (expand-file-name (format "seg-%03d.org" n) folder)))
                        seg-nums))
               (sent-file (if (fboundp 'tibetan-sentence--filepath)
                              (tibetan-sentence--filepath
                               (plist-get sentence :sent-num) folder source-file)
                            (expand-file-name
                             (format "sent-%03d.org"
                                     (plist-get sentence :sent-num))
                             folder))))
          ;; All children must exist (auto-analyze creates files before
          ;; firing) — otherwise fall back to the per-segment path.
          (when (cl-every #'file-exists-p child-files)
            ;; Fire gate: FORCE, or any child still needs Claude.
            (when (or force
                      (cl-some (lambda (f)
                                 (tibetan-analysis--claude-needs-request-p f))
                               child-files))
              (let ((label (format "sent-%03d" (plist-get sentence :sent-num))))
                (if (not (tibetan-sentence-claude--claim
                          source-file (plist-get sentence :sent-num) label))
                    'dedup-hit
                  (tibetan-sentence-claude--request
                   sentence child-files
                   (and (file-exists-p sent-file) sent-file)
                   source-file folder force)
                  ;; DM rides the same claim: one sentence-level DM
                  ;; fire, staggered against the 10/min limit.
                  (tibetan-sentence-claude--schedule-dm
                   sentence child-files
                   (and (file-exists-p sent-file) sent-file) force)
                  'fired)))))))))

(provide 'tibetan-sentence-claude)
;;; tibetan-sentence-claude.el ends here
