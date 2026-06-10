;;; tibetan-analysis-claude.el --- Claude pipeline for segment analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Extracted from `persist/tibetan-analysis-persist.el' — the
;; entire Claude-side pipeline that turns a segment's parser output
;; into a three-section Claude response (`** Claude Translation',
;; `*** Claude Vocabulary', `*** Claude Grammar') and wires it back
;; into the analysis file.
;;
;; Public entry points consumed by the renderer / commands /
;; batch-reanalysis code in `tibetan-analysis-persist':
;;
;;   tibetan-analysis--request-claude-translation
;;       Kick off a throttled Claude request via
;;       `tibetan-claude-queue-submit', passing the segment text and
;;       the parser-grounding context.  Writes results back into the
;;       analysis file and falls back to a visible failure stub when
;;       the request is ultimately rejected.
;;
;;   tibetan-analysis--insert-claude-sections
;;       Parse a fresh Claude response and insert / merge the three
;;       sections into the analysis buffer, running the legacy
;;       `*** Claude' migration first if needed.
;;
;;   tibetan-analysis--parse-claude-sections
;;       Plist-style parser for the raw three-section response
;;       (`## Translation' / `## Vocabulary' / `## Grammar').  Tolerant
;;       of legacy `## Context' so older responses in sentence-level
;;       files still round-trip.
;;
;;   tibetan-analysis--ensure-claude-headings
;;   tibetan-analysis--migrate-legacy-claude-headings
;;       Org-structure migration:  earlier tool versions produced a
;;       single `*** Claude Translation' at level-3 inside
;;       `** Provided Translations'.  These helpers walk any such
;;       analysis file and promote it to the current layout
;;       non-destructively.
;;
;;   tibetan-analysis--read-claude-sections / --read-claude-translation
;;   tibetan-analysis--restore-claude-sections / --restore-claude-translation
;;       Round-trip helpers used by `tibetan-analysis-batch-reanalyze'
;;       to preserve existing Claude output across a reanalysis.
;;
;;   tibetan-analysis--merge-claude-vocabulary
;;       Merge a Claude `## Vocabulary' block into the existing
;;       `*** Claude Vocabulary' section, de-duplicating by lemma.
;;
;; Shared helpers still live in `tibetan-analysis-persist':
;;   tibetan-analysis--read-section-body    (generic org section reader)
;;   tibetan-analysis--seg-id-from-filename (shared with batch)
;;   tibetan-analysis--claude-heading-re / --claude-stop-re /
;;     --claude-segment-layout-p / --claude-effective-section-order /
;;     --replace-claude-section-body / --insert-claude-translation-heading
;;   are all Claude-specific and live here.
;;
;; This module soft-requires `tibetan-claude-queue' (the throttled
;; request queue) and `gptel' (the actual HTTP layer).  Both are
;; optional: when absent the request path short-circuits with a clear
;; message rather than erroring.

;;; Code:

(require 'cl-lib)
(require 'md5)
(require 'tibetan-claude-queue nil t)
(require 'gptel nil t)
;; Phase 4 of zettel-in-translation-workflow (2026-04-24) — soft-require
;; so `--insert-claude-sections' can call `tibetan-zettel--cache-claude-
;; vocabulary' to write per-term cache entries.  Missing module → no
;; cache writes; the rest of the insert path is unaffected.
(require 'tibetan-zettel nil t)

;; External gptel symbols — declared so the byte-compiler doesn't warn
;; on fresh checkouts where gptel isn't installed.  Runtime guards
;; (`(fboundp 'gptel-request)') keep behaviour safe.
(defvar gptel-api-key)
(defvar gptel-backend)
(defvar gptel-model)
(defvar gptel-cache)                    ; gptel prompt-caching toggle
(declare-function gptel-request "gptel" (&optional prompt &rest args))
(declare-function gptel-make-anthropic "gptel" (name &rest args))

;; Forward declarations from the sibling render module
;; (`tibetan-analysis-persist').  Present at runtime once that module
;; is loaded.
(declare-function tibetan-analysis--read-section-body "tibetan-analysis-persist"
                  (filepath section-name))
(declare-function tibetan-analysis--seg-id-from-filename
                  "tibetan-analysis-persist" (filepath))
(declare-function tibetan-analysis--folder-analysis-files
                  "tibetan-analysis-persist" (folder))
(declare-function tibetan-analysis-get-folder "tibetan-analysis-persist" ())

;; ============================================================================
;; CLAUDE TRANSLATION (via gptel)
;; ============================================================================

(defvar tibetan-analysis--claude-system-prompt
  "You are a specialist in Classical Tibetan (chos skad) translation \
and philology, acting as a teaching assistant for a graduate classroom.

Produce FIVE sections, separated by the exact markdown headings \
shown below, in this order and nothing else:

## Translation
A translation that stays CLOSE TO THE GRAMMAR of the Tibetan. \
Prefer faithfulness over fluency:
- Honour the Tibetan clause structure.  If the source uses a \
conditional converb (V-na), render as \"if / when V...\"; do not \
paraphrase as \"while V\" or absorb the conditional into a \
participial clause.  If it uses a nominalised-verb + copula \
(V-pa + yin / che / yod), mirror the structure (\"the V-ing is \
important\", not \"it is important to V\").
- Preserve the case-marking pattern: ergative-marked agents become \
explicit subjects (\"by X, Y was done\"), ablatives mark cause or \
source explicitly (\"arises FROM X\", \"because of X\"), \
terminatives mark manner or goal.  Do not paraphrase grammar to \
sound more English-natural.
- Keep the particle sequence visible.  A reader comparing \
translation against Wylie should be able to track which Tibetan \
particle maps to which English word or phrase.
- Preserve technical Buddhist terminology (use Sanskrit where \
standard, e.g. dharma, bodhisattva, samādhi).  For fixed Buddhist \
terms (Four Immeasurables, Bodhicitta, Three Jewels, the five \
aggregates, etc.), include a short parenthetical explanation on \
first mention in this section — e.g. \"Four Immeasurables \
(tshad med bzhi: loving-kindness, compassion, joy, equanimity)\".
- Honorific forms (zhu, gsol, mdzad, etc.) should be reflected \
in the register, not merely flattened to plain forms.
- When a glossary for this passage is provided in the user prompt, \
prefer those renderings for proper names and technical terms.
- When ±2 surrounding segments are provided, use them as context to \
resolve ambiguous pronouns, discourse particles, and sentence-internal \
reference — but translate ONLY the target passage.
- No commentary in this section (justifications belong in ## Grammar).

## Vocabulary
Word-by-word analysis in DharmaMitra style.  For EACH word or \
compound in the passage, produce exactly one line with four fields \
separated by comma-space:

  wylie, grammatical-category, \"meaning\", contextual-note

Fields:
  1. wylie — EWTS romanisation, lowercase, e.g. \"mnyam med\".
  2. grammatical-category — one of: noun, proper noun, adjective, \
adverb, verb (hon.), verb, transitive verb, intransitive verb, \
converb, nominalizer, genitive, ergative/instrumental, terminative, \
ablative, locative, dative, particle, sentence-final particle, \
negation, conjunction, relative clause marker, or a similarly \
concise label.
  3. meaning — short English gloss in double quotes.  \
When a glossary entry is provided in the user prompt, prefer that \
rendering; otherwise give the contextually best fitting sense.
  4. contextual-note (optional) — e.g. \"epithet of ...\", \
\"honorific of byed pa\", \"marks the agent of mdzad\".  Omit \
the trailing comma when this field is absent.

Keep multi-word expressions (proper names, verb + nominaliser, \
particle compounds like \"pa'i\") together on one line.  \
Order follows the passage left-to-right.

Example:
  mnyam med, adjective, \"peerless\", epithet — literally \"without equal\"
  'gro ba'i, genitive, \"of beings\"
  mgon po, noun, \"protector\"

## Grammar
A SHORT, STRUCTURED analysis as labeled bullets — easier to scan \
than a wall of prose.  Use up to four bullets in this fixed order; \
SKIP any bullet that doesn't apply rather than padding.  Each \
bullet is 1–3 sentences; the whole section should fit in ~120–180 \
words total.

- *Verb backbone:* main finite verb(s) and any governing converb \
chain (V-nas / V-te / V-cing sequencing).  Name converb types \
explicitly (sequential, conditional, simultaneous, causal).
- *Case frame:* how the agent / patient / oblique arguments are \
marked — quote the actual Tibetan forms in parentheses, e.g. \
`ergative *kyis* on *bdag*' or `dative *la* marking the recipient'.
- *Notable constructions:* one or two noteworthy items if any — \
idioms, reported speech, hedges, nominalisation patterns, honorific \
register flips.  Skip when the passage is straightforward.
- *Translation justifications:* wherever the ## Translation above \
made a non-obvious choice, justify in one sentence — e.g. \
\"*blo sbyangs na* is rendered 'if one trains the mind' because \
*na* here is the conditional converb (V+na), not the locative \
particle\".  Two such notes per segment is a reasonable target; \
skip if mechanical.

Name metalanguage explicitly when useful (Ergative, Ablative, \
Dative, Terminative, Instrumental, Comitative, Genitive, \
nominalizer, honorific stem).  Reference Tibetan forms in italic \
parentheses (`*tshig*`).

You will be given the parser's own analysis in the user prompt — \
treat it as ground truth for case and verb tagging; if you \
disagree, flag the disagreement in one sentence rather than \
silently overruling.

Per-particle functional detail (which §1.5.x applies to THIS ར, \
which §2.11.x applies to THIS ནས, etc.) belongs in the later \
`## Particles' section — NOT here.  Keep this section at the \
passage level.

## Particles
One line per particle OCCURRENCE in the passage (not per particle \
type — if ནས appears twice in different functions, emit two lines). \
Each line has four comma-separated fields:

  word, particle, portfolio-sub-id, short-function-label

Fields:
  1. word — the Wylie word the particle attaches to, e.g. `mthu'i' \
or `bslabs nas' or `der'.  For a standalone particle use the \
particle's Wylie (`nas').
  2. particle — the particle's Wylie alone: `'i', `nas', `r', `la', \
`ni', `pas', `ste', etc.
  3. portfolio-sub-id — the EXACT sub-section ID from the user's \
Portfolio.  The Portfolio's section numbering is supplied below \
(look for `Portfolio section reference' — check it first, use its \
numbers, do NOT guess based on textbook-canonical numbering which \
may differ from the user's edition).  Format: `N.N.N' for case \
particles, `N.NN.N' or `N.N.N' for converbs.  If no sub-ID in the \
reference matches the function, use the TOP-LEVEL `N.N' of the \
best-matching section and flag the mismatch in field 4.  If no \
section at all matches (e.g. V+nas is not listed), use the closest \
parent section (for V+nas try Elative §N.N) and label accordingly.
  4. short-function-label — a 1–3-word English label naming the \
specific function: `place', `time', `attributive', `sequential', \
`causal', `manner', `concessive', etc.  Lowercase.  When a \
mismatch forced a fallback ID in field 3, prefix the label with \
`approx-' (e.g. `approx-sequential') so the renderer can flag it.

Use these exact particles for case: `'i', `kyi', `gyi', `gi', `yi' \
(GEN); `gis', `gyis', `kyis', `'is', `yis' (ERG); `r', `ru', `su', \
`tu', `du' (TERM); `la' (DAT); `las' (ABL); `na' (LOC); `ni' (TOPIC); \
`dang' (COM).  Converbs: `nas', `te', `ste', `de', `cing', `zhing', \
`shing', `pas', `bas', `na', `kyang', `yang', `'ang'.

Example format (numbers below are illustrative; use the Portfolio \
reference for real IDs):
  der, r, 1.6.1, place
  mthu'i, 'i, 1.1.1, attributive
  bslabs nas, nas, 1.8.2, approx-sequential-temporal
  tshim nas, nas, 1.8.4, approx-causal-sequential

## Concept Notes
Identify any notable technical concepts in THIS segment and give \
each a brief encyclopedia-style note for a graduate-classroom \
reader:  Buddhist doctrine and category-lists, doxographical \
school / tradition references, lineage and person names, place \
names, Sanskrit-derived technical terms.

For each concept (0–3 entries per segment is the typical range):
- **Tibetan term (Skt. / Pali equivalent if relevant) — short gloss**
  1–2 sentence explanation drawn from canonical or scholarly \
sources.  Note the doctrinal-context (Madhyamaka, Yogācāra, lam-rim, \
bKa'-gdams-pa, etc.) when relevant.  Cite primary sources only when \
genuinely illuminating;  avoid bibliographic padding.

If the segment is purely narrative / mechanical and contains no \
notable concepts, output EXACTLY (no other text in this section):
  [No notable concepts in this passage]

When your explanation references a SUB-CONCEPT that itself \
warrants a gloss (e.g. \"one of the twelve dhutaguṇas\", \"in \
the mahāyāna-saṃgraha framework\"), expand it with a 1-sentence \
parenthetical gloss inline — so the reader gets enough context \
without needing an external lookup.  One level of nesting is \
enough;  don't recurse further.

Avoid recapitulating the ## Vocabulary section above — that's word \
glosses;  this is conceptual depth.  Be terse;  the whole section \
should fit in ~180 words including any nested sub-concept glosses.

Use only these headings. No preamble, no closing remarks.

Genre, period and context hints (if any) are supplied below by the \
source file via `#+TIBETAN_CLAUDE_CONTEXT:' headers. Do NOT assume a \
specific genre unless such context is given."
  "System prompt sent to Claude for segment-level three-section analysis.
Produces a markdown response (Translation / Vocabulary / Grammar)
parsed by `tibetan-analysis--parse-claude-sections' and placed into
`** Claude Translation', `*** Claude Vocabulary', and
`*** Claude Grammar'.  Vocabulary uses DharmaMitra-style
word-by-word format as the second tier (after provided vocabulary,
before Steinert entries).  Genre-specific assumptions come from the
source file's `#+TIBETAN_CLAUDE_CONTEXT:' headers.")

;; ----------------------------------------------------------------------------
;; Source-aware prompt enrichment (workshop-ready)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-source-metadata (source-file)
  "Return a plist of prompt-relevant metadata extracted from SOURCE-FILE.
Keys:
  :title           value of the first `#+TITLE:' line
  :work            :WORK from the first :PROPERTIES: drawer
  :author          :AUTHOR from the first :PROPERTIES: drawer
  :sources         :SOURCES from the first :PROPERTIES: drawer
  :claude-context  list of all `#+TIBETAN_CLAUDE_CONTEXT:' values in order
  :vocab-file      value of `#+TIBETAN_VOCAB_FILE:' (relative to SOURCE-FILE)
  :corpus          value of `#+TIBETAN_CORPUS:' — the corpus identifier
                   used by the dictionary ranker to promote a
                   corpus-specific Steinert sub-dictionary (e.g.
                   `Yogacarabhumi' → `22-Yoghacharabhumi-glossary').
                   See `tibetan-vocab--corpus-source-map'.
  :target-lang     value of `#+TIBETAN_TARGET_LANG:' — the primary
                   visible translation language for this document
                   (`de' or `en', lowercased; nil when unset).
                   Drives `--prefer-target-lang' in the Interlinear
                   Gloss, the CAT Gloss, and the Claude Translation
                   prompt.  The Detailed Dictionary always keeps
                   the bilingual `DE // EN' form for reference.
  :source-mode     value of `#+SOURCE_MODE:' — the document's
                   reading mode (e.g. `parallel-sanskrit' for the
                   Yogācārabhūmi parallel-reading workflow where
                   Sanskrit is primary and Tibetan secondary).
                   nil when unset (today's default — Tibetan-only
                   source).  Phase 3 of sanskrit-parallel-workflow
                   (2026-04-27) injects a Sanskrit-primary system
                   block into the Claude prompt when this equals
                   `parallel-sanskrit'.  See
                   `core/tibetan-sanskrit-parallel.el' for the
                   inline reader used by `core/' callers without
                   the persist dependency.
  :dm-sanskrit-source  value of `#+DM_SANSKRIT_SOURCE:' — the
                   DharmaMitra source identifier for the Sanskrit-
                   side parallel work (e.g. `SA_T06_bsa034' for
                   Asaṅga's Bodhisattvabhūmi).  Phase 2 of the
                   dharmamitra-realign workflow (2026-04-27).
                   The realign command uses this to constrain
                   the search to the right corpus when re-aligning
                   `**** Sanskrit' siblings.  nil when unset.
  :dm-tibetan-source  value of `#+DM_TIBETAN_SOURCE:' — the DM
                   identifier for the Tibetan-side parallel
                   (e.g. `BO_T06_D4037' for the Derge
                   Bodhisattvabhūmi).  nil when unset.
  :text-type       value of `#+TIBETAN_TEXT_TYPE:' — canonical
                   Tibetan genre tag (`rnam-thar', `lam-rim',
                   `mgur', `mdo', `rgyud', `bstan-bcos',
                   `snyan-ngag', `gtam-rgyud', `'grel-pa',
                   `ti-ka', `gter-ma', `gdams-ngag', plus the
                   legacy values `classical' / `madhyamaka-
                   verse' / `sutra' / `commentary').  Threaded
                   into Claude system prompt by callers that
                   want to specialise the analysis to the
                   genre.  nil when unset.  §5.27 Phase 1
                   (2026-05-26).
  :class-mode      value of `#+TIBETAN_CLASS_MODE: grammar|reading'
                   — controls whether downstream commands default
                   to segment-focus (Tibetan grammar classes,
                   default) or sentence-focus (reading classes).
                   Persistent per-document;  command prefix-args
                   override ad-hoc.  §5.27 Phase 1 (2026-05-26).
  :sentence-detail value of `#+TIBETAN_SENTENCE_DETAIL:
                   compressed|detailed' — only meaningful when
                   `:class-mode' is `reading'.  `compressed' =
                   §5.22 default (Vocab + Translation + Grammar
                   + Provided Translations, ~2 A4 pages).
                   `detailed' = full §5.21 segment layout
                   (sentence file mirrors a segment file's
                   depth).  §5.27 Phase 1 (2026-05-26).

§5.22 final (2026-05-21):  the `:sentence-compressed' plist key
\(briefly added in §5.22 initial as an opt-in for compressed
sentence layout) is RETIRED.  Sentence files are now
unconditionally compressed;  no per-source header is consumed.
The `#+TIBETAN_SENTENCE_COMPRESSED:' line is ignored if present.

§5.27 Phase 1 (2026-05-26):  `:author' reader extended.  In
addition to the existing PROPERTIES-drawer `:AUTHOR:' path, a
new `#+TIBETAN_AUTHOR:' single-line header is also recognised.
Drawer wins when both are present (backwards-compatible);
header-only sources (the wizard-created common case) get the
same `:author' slot.

Safe when SOURCE-FILE is nil or does not exist — returns an empty plist."
  (let (title work author sources ctx vocab corpus target-lang source-mode
              dm-sanskrit-source dm-tibetan-source
              text-type class-mode sentence-detail
              author-header)
    (when (and source-file (file-exists-p source-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents source-file)
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
              (setq title (string-trim (match-string 1))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TIBETAN_VOCAB_FILE:[ \t]*\\(.*\\)$" nil t)
              (setq vocab (string-trim (match-string 1))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TIBETAN_CORPUS:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq corpus val))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+TIBETAN_TARGET_LANG:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq target-lang (downcase val)))))
            (goto-char (point-min))
            (when (re-search-forward "^#\\+SOURCE_MODE:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq source-mode val))))
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+DM_SANSKRIT_SOURCE:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq dm-sanskrit-source val))))
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+DM_TIBETAN_SOURCE:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq dm-tibetan-source val))))
            ;; §5.27 Phase 1 (2026-05-26):  text-type / class-mode /
            ;; sentence-detail / TIBETAN_AUTHOR — all single-line
            ;; per-document headers.
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+TIBETAN_TEXT_TYPE:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq text-type (downcase val)))))
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+TIBETAN_CLASS_MODE:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq class-mode (downcase val)))))
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+TIBETAN_SENTENCE_DETAIL:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq sentence-detail (downcase val)))))
            (goto-char (point-min))
            (when (re-search-forward
                   "^#\\+TIBETAN_AUTHOR:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (setq author-header val))))
            (goto-char (point-min))
            (while (re-search-forward
                    "^#\\+TIBETAN_CLAUDE_CONTEXT:[ \t]*\\(.*\\)$" nil t)
              (let ((val (string-trim (match-string 1))))
                (unless (string-empty-p val)
                  (push val ctx))))
            (setq ctx (nreverse ctx))
            ;; First :PROPERTIES: drawer
            (goto-char (point-min))
            (when (re-search-forward "^:PROPERTIES:$" nil t)
              (let ((drawer-end (save-excursion
                                  (re-search-forward "^:END:$" nil t))))
                (when drawer-end
                  (save-restriction
                    (narrow-to-region (point) drawer-end)
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:WORK:[ \t]*\\(.*\\)$" nil t)
                      (setq work (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:AUTHOR:[ \t]*\\(.*\\)$" nil t)
                      (setq author (string-trim (match-string 1))))
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^:SOURCES:[ \t]*\\(.*\\)$" nil t)
                      (setq sources (string-trim (match-string 1)))))))))
        (error nil))) ;; close condition-case and outer `when source-file'
    ;; §5.27 Phase 1 fallback:  PROPERTIES drawer `:AUTHOR:' wins
    ;; (backwards-compat with existing files);  fall back to the
    ;; new `#+TIBETAN_AUTHOR:' header when drawer is absent.
    (unless author
      (setq author author-header))
    (list :title title
          :work work
          :author author
          :sources sources
          :claude-context ctx
          :vocab-file vocab
          :corpus corpus
          :target-lang target-lang
          :source-mode source-mode
          :dm-sanskrit-source dm-sanskrit-source
          :dm-tibetan-source dm-tibetan-source
          :text-type text-type
          :class-mode class-mode
          :sentence-detail sentence-detail)))


;;;###autoload
(defun tibetan-analysis-set-source-target-lang (source-file lang)
  "Set `#+TIBETAN_TARGET_LANG:' to LANG on SOURCE-FILE.

LANG must be `\"de\"' or `\"en\"' — any other value signals a
user-error (the picker downstream only knows those two).

When the source already has a `#+TIBETAN_TARGET_LANG:' line the
value is replaced in place; otherwise a new line is inserted
immediately after the first `#+TITLE:' line so the metadata
block stays contiguous at the top of the file.

Re-analyses of this document will pick up the new value
automatically via `--read-source-metadata' — no manual reload
needed.  Interactive callers get progress + final-state messaging.

Errors when SOURCE-FILE is nil, non-existent, or the file cannot
be written to."
  (interactive
   (list (or (tibetan-analysis--source-file-from-analysis
              (buffer-file-name))
             buffer-file-name
             (read-file-name "Source file: " nil nil t))
         (completing-read "Target language: " '("de" "en") nil t
                          (let ((current
                                 (and buffer-file-name
                                      (plist-get
                                       (tibetan-analysis--read-source-metadata
                                        buffer-file-name)
                                       :target-lang))))
                            (or current "de")))))
  (unless (member lang '("de" "en"))
    (user-error "Target language must be `de' or `en' (got %S)" lang))
  (unless (and source-file (file-writable-p source-file))
    (user-error
     "Cannot write target-lang header — source file missing / not writable: %s"
     source-file))
  (with-temp-buffer
    (insert-file-contents source-file)
    (goto-char (point-min))
    (cond
     ;; Replace existing line in place.
     ((re-search-forward "^#\\+TIBETAN_TARGET_LANG:[ \t]*.*$" nil t)
      (replace-match (format "#+TIBETAN_TARGET_LANG: %s" lang) t t))
     ;; Insert after #+TITLE: if present.
     ((progn (goto-char (point-min))
             (re-search-forward "^#\\+TITLE:.*$" nil t))
      (end-of-line)
      (insert (format "\n#+TIBETAN_TARGET_LANG: %s" lang)))
     ;; Otherwise prepend to buffer.
     (t
      (goto-char (point-min))
      (insert (format "#+TIBETAN_TARGET_LANG: %s\n" lang))))
    (write-region (point-min) (point-max) source-file))
  (when (called-interactively-p 'any)
    (message "Target language set to `%s' on %s" lang
             (file-name-nondirectory source-file))))

(defun tibetan-analysis--source-file-from-analysis (analysis-file)
  "Return the absolute source file referenced by ANALYSIS-FILE.
Reads the `#+SOURCE:' header (an org link of the form
`[[file:../foo.org::*Segment N][…]]') and resolves it relative to
the directory of ANALYSIS-FILE.  Returns nil if nothing is found."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^#\\+SOURCE:[ \t]*\\[\\[file:\\([^]:]+\\)" nil t)
            (let ((rel (match-string 1)))
              (expand-file-name rel (file-name-directory analysis-file)))))
      (error nil))))

(defun tibetan-analysis--match-resources-vocab (tibetan-text vocab-file)
  "Return a list of (TERM . GLOSS) from VOCAB-FILE that occur in TIBETAN-TEXT.
VOCAB-FILE is an org file containing a table whose first column is the
Tibetan term and second column is the gloss."
  (let (matches)
    (when (and tibetan-text vocab-file (file-exists-p vocab-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents vocab-file)
            (goto-char (point-min))
            (while (re-search-forward
                    "^[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|[ \t]*\\([^|\n]+?\\)[ \t]*|"
                    nil t)
              (let ((term (string-trim (match-string 1)))
                    (gloss (string-trim (match-string 2))))
                (when (and (not (string-empty-p term))
                           ;; Skip header separator / "Term" header row
                           (not (string-match-p "\\`-+\\'" term))
                           (not (string= term "Term"))
                           ;; Must contain at least one Tibetan char
                           (string-match-p "[\u0F00-\u0FFF]" term)
                           (string-match-p (regexp-quote term) tibetan-text))
                  (push (cons term gloss) matches)))))
        (error nil)))
    (nreverse matches)))

;; ============================================================================
;; §5.25 (2026-05-24) — Thesaurus zettel cross-link for Concept Notes
;; ============================================================================
;;
;; The `** Concept Notes' section (§5.24) gets per-term cross-links to
;; thesaurus zettels in `~/Documents/tibetan-thesaurus/'.  Architecture
;; (the user picked option C, "Both — prompt-cite + post-process safety
;; net"):
;;
;;   1. PRE-LOAD:  before firing Claude, walk TIBETAN-TEXT, collect
;;      thesaurus zettels for words/compounds that match, inject their
;;      `ZID' / Wylie / Sanskrit / primary translation into the user
;;      prompt.  Prompt instruction tells Claude to cite as
;;      `[[id:ZID][zettel ↗]]' inline when discussing the term.
;;   2. POST-PROCESS:  after Claude returns the Concept Notes body, scan
;;      bolded Tibetan terms (`**…**'), look each up in the thesaurus,
;;      and APPEND `[[id:ZID][zettel ↗]]' to any line that matches but
;;      doesn't already carry the link.  Safety net for zettels Claude
;;      missed in its in-prompt citation.
;;
;; Both paths are no-ops when the thesaurus module isn't loaded or no
;; zettels match — silent fall-through preserves the no-zettel UX.

(defun tibetan-analysis--collect-zettel-references (tibetan-text)
  "Return a deduplicated list of thesaurus zettel plists for TIBETAN-TEXT.

Walks the tokenised words/compounds in TIBETAN-TEXT (via
`tibetan-tokenize-into-words'), looks each up in the thesaurus
\(via `tibetan-thesaurus-lookup' using the Wylie key), and returns
the unique zettels found.  Plist shape per element:

  (:id ID :wylie WYLIE :sanskrit SKT :primary-en EN :primary-de DE
   :path PATH)

Deduplication is by `:id'.  Returns nil when the thesaurus module
isn't loaded, the directory isn't configured, or no zettel
matches.  Safe to call from prompt builders — wrapped in
`condition-case' so a malformed zettel doesn't crash the analysis."
  (when (and tibetan-text (stringp tibetan-text)
             (fboundp 'tibetan-thesaurus-lookup)
             (fboundp 'tibetan-tokenize-into-words))
    (condition-case nil
        (let ((tokens (tibetan-tokenize-into-words tibetan-text))
              (seen (make-hash-table :test 'equal))
              (results '()))
          (dolist (tok tokens)
            (let* ((wylie (condition-case nil
                              (and (fboundp 'tibetan-to-wylie-fixed)
                                   (let ((w (tibetan-to-wylie-fixed tok)))
                                     (and w (string-trim w))))
                            (error nil)))
                   (zettels (and wylie
                                 (not (string-empty-p wylie))
                                 (tibetan-thesaurus-lookup wylie))))
              (dolist (z zettels)
                (let ((id (plist-get z :id)))
                  (when (and id (not (gethash id seen)))
                    (puthash id t seen)
                    (push z results))))))
          (nreverse results))
      (error nil))))

(defun tibetan-analysis--format-zettel-references-block (zettels)
  "Format ZETTELS (list of plists) as an injectable user-prompt block.

When non-empty, returns a string starting with two newlines + a
header line + one bullet per zettel.  When ZETTELS is nil or
empty, returns the empty string so the caller can unconditionally
concat the result.

Each bullet shows the Wylie key, the org ZID, the Sanskrit
equivalent (if known), and the primary translation (English
preferred, German fallback) — enough for Claude to recognise the
term as it appears in the passage and to cite it correctly."
  (if (null zettels)
      ""
    (concat
     "\n\nAvailable thesaurus zettels for cross-link in the "
     "## Concept Notes section.  When discussing a term listed below, "
     "cite the matching zettel with the org-link format "
     "`[[id:ZID][zettel ↗]]' immediately after the term — this lets "
     "the reader jump from Concept Notes to the curated zettel.\n"
     (mapconcat
      (lambda (z)
        (let* ((wylie (or (plist-get z :wylie) "?"))
               (id    (or (plist-get z :id) "?"))
               (skt   (plist-get z :sanskrit))
               (en    (plist-get z :primary-en))
               (de    (plist-get z :primary-de)))
          (format "  - %s (ZID:%s)%s%s"
                  wylie id
                  (if (and skt (not (string-empty-p skt)))
                      (format " ← Skt. %s" skt) "")
                  (cond
                   ((and en (not (string-empty-p en)))
                    (format " — %s" en))
                   ((and de (not (string-empty-p de)))
                    (format " — %s" de))
                   (t "")))))
      zettels "\n"))))

(defun tibetan-analysis--cross-link-zettels-in-body (body)
  "Append `[[id:ZID][zettel ↗]]' links to bolded Tibetan terms in BODY.

BODY is a string (typically the Concept Notes section's body
returned by Claude).  For each line matching `- **<term>**…',
extract the leading word, look it up in the thesaurus by Wylie,
and append the zettel link to the line if the zettel exists AND
the line doesn't already carry a `[[id:…]]' link.

The leading-word extractor splits on whitespace / `(' so terms
like `**'dod yon (Skt. pañca kāmaguṇa) — five sensory…**' yield
the bare Wylie key `'dod yon' for lookup.  When Claude bolded the
Tibetan-script form (`མཐུ'), the function first tries the script
as-is (some thesauruses have script keys), then converts to Wylie
and re-tries.

Returns the modified BODY string.  No-op (returns BODY unchanged)
when BODY is nil/empty, when the thesaurus module isn't loaded,
or when no bolded terms match a zettel.  Wrapped in
`condition-case' so any error in the regex / lookup path falls
back to the unmodified body."
  (if (or (null body) (not (stringp body))
          (string-empty-p body)
          (not (fboundp 'tibetan-thesaurus-lookup)))
      body
    (condition-case nil
        (with-temp-buffer
          (insert body)
          (goto-char (point-min))
          ;; Match line-starting `- **<term>**' (bullet + bold).  Claude's
          ;; Concept Notes uses this format consistently per the §5.24
          ;; prompt.  Avoid `**Concept**' mid-line matches that aren't
          ;; the entry header.
          (while (re-search-forward "^- \\*\\*\\([^*\n]+?\\)\\*\\*" nil t)
            (let* ((bold (match-string 1))
                   (eol-pos (line-end-position))
                   (existing-line (buffer-substring-no-properties
                                   (line-beginning-position) eol-pos)))
              (unless (string-match-p "\\[\\[id:" existing-line)
                ;; Extract just the leading word (Wylie or Tibetan) —
                ;; strip anything after the first space, `(', `—', or `,'.
                (let* ((first-word
                        (and (string-match
                              "\\`\\([^ (,—–-]+\\(?:[ ][^ (,—–]+\\)?\\)"
                              bold)
                             (string-trim (match-string 1 bold))))
                       ;; Try lookup as-is first (script);  fall back to
                       ;; Wylie conversion.
                       (zettels
                        (or (and first-word
                                 (tibetan-thesaurus-lookup first-word))
                            (and first-word
                                 (fboundp 'tibetan-to-wylie-fixed)
                                 (let ((w (condition-case nil
                                              (string-trim
                                               (tibetan-to-wylie-fixed
                                                first-word))
                                            (error nil))))
                                   (and w (not (string-empty-p w))
                                        (tibetan-thesaurus-lookup w))))))
                       (z (car zettels))
                       (id (and z (plist-get z :id))))
                  (when id
                    (goto-char eol-pos)
                    (insert (format " [[id:%s][zettel ↗]]" id)))))))
          (buffer-string))
      (error body))))

(defun tibetan-analysis--read-analysis-parser-sections (analysis-file)
  "Return a plist of parser-output sections extracted from ANALYSIS-FILE.
Used to give Claude the tool's own grammatical analysis as grounding
for the Grammar section of the three-section response.  Keys:
  :grammatical-markers   body of `** Grammatical Markers'
  :clause-structure      body of `** Clause Structure'
  :verb-classification   body of `** Verb Classification (Hill 2010)'
  :sentence-structure    body of `** Sentence Structure'
Any missing section is nil.  Safe when ANALYSIS-FILE is nil or absent."
  (let (markers clauses verbs sentences)
    (when (and analysis-file (file-exists-p analysis-file))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents analysis-file)
            (cl-labels
                ((body-of (heading-re)
                   (save-excursion
                     (goto-char (point-min))
                     (when (re-search-forward heading-re nil t)
                       (forward-line 1)
                       (let ((start (point))
                             (end (save-excursion
                                    (if (re-search-forward
                                         "^\\*\\* [^ \t\n]\\|^\\* [^ \t\n]"
                                         nil t)
                                        (line-beginning-position)
                                      (point-max)))))
                         (let ((body (string-trim
                                      (buffer-substring-no-properties
                                       start end))))
                           (unless (string-empty-p body) body)))))))
              (setq markers   (body-of "^\\*\\* Grammatical Markers$")
                    clauses   (body-of "^\\*\\* Clause Structure$")
                    verbs     (body-of
                               "^\\*\\* Verb Classification[^\n]*$")
                    sentences (body-of "^\\*\\* Sentence Structure$"))))
        (error nil)))
    (list :grammatical-markers markers
          :clause-structure    clauses
          :verb-classification verbs
          :sentence-structure  sentences)))

(defun tibetan-analysis--format-parser-grounding (parser-sections)
  "Format PARSER-SECTIONS (plist from `--read-analysis-parser-sections')
as a single text block suitable for embedding in the Claude user
prompt.  Returns nil when every section is empty."
  (let ((parts '())
        (markers (plist-get parser-sections :grammatical-markers))
        (clauses (plist-get parser-sections :clause-structure))
        (verbs   (plist-get parser-sections :verb-classification)))
    (when markers
      (push (concat "Grammatical markers (parser output):\n" markers)
            parts))
    (when clauses
      (push (concat "Clause structure (parser output):\n" clauses)
            parts))
    (when verbs
      (push (concat "Verb classification (parser output):\n" verbs)
            parts))
    (when parts
      (concat "\n\nParser analysis (ground truth for case and verb "
              "tagging — narrate this pedagogically, flag disagreements "
              "rather than silently overruling):\n\n"
              (mapconcat #'identity (nreverse parts) "\n\n")))))

;; ----------------------------------------------------------------------------
;; Per-segment vocabulary matches (from the analysis file itself)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--read-word-particle-list (analysis-file)
  "Return the body of `** Word / Particle List' in ANALYSIS-FILE, or nil.
This is the compact, numbered vocabulary list the tool generates for
each segment: `N. Tibetan [wylie]  [tag] — short gloss'.  Safe when
ANALYSIS-FILE is nil or does not exist."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward
                 "^\\*\\* Word / Particle List$" nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (save-excursion
                          (if (re-search-forward
                               (tibetan-analysis--claude-stop-re 2) nil t)
                              (line-beginning-position)
                            (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties start end))))
              (unless (or (string-empty-p body)
                          ;; Skip obvious placeholders
                          (string-match-p "\\`\\[" body))
                body))))
      (error nil))))

(defun tibetan-analysis--read-interlinear-glosses (analysis-file)
  "Return content-word glosses from the `** Interlinear Gloss' section
of ANALYSIS-FILE as a newline-joined `  - wylie = gloss' list, or nil.

Parses each `[[term-SLUG][WYLIE]] [★] [GLOSS]' token, capturing the
Wylie surface form and its first bracketed gloss (the tool's layered
lookup result; Resources-curated entries are marked ★ in the source).

This replaces the reader for the §5.10-retired `** Word / Particle
List' section.  Without it the Claude vocabulary prompt received NO
dictionary grounding, so Claude guessed meanings for rare words
(Milarepa Segment 37: `phru rlog' = \"farm work\" in Resources, but
Claude hallucinated \"hand-mill turning\").  Safe when ANALYSIS-FILE is
nil or absent."
  (when (and analysis-file (file-exists-p analysis-file))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents analysis-file)
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\* Interlinear Gloss$" nil t)
            (forward-line 1)
            (let* ((start (point))
                   (end (save-excursion
                          (if (re-search-forward "^\\*+ [^ \t\n]" nil t)
                              (line-beginning-position)
                            (point-max))))
                   (body (buffer-substring-no-properties start end))
                   (pairs '())
                   (pos 0))
              ;; L3 (Fable-5 audit): also capture zettel-linked
              ;; tokens (`[[id:ZID][wylie]] ♦ [gloss]') — those carry
              ;; the MOST curated glosses and were being omitted from
              ;; the grounding block.
              (while (string-match
                      (concat "\\[\\[\\(?:term-\\|id:\\)[^]]*\\]\\[\\([^]]*\\)\\]\\]"
                              "[ \t]*[★♦]?[ \t\n]*\\[\\([^]]*\\)\\]")
                      body pos)
                (let ((wylie (string-trim (match-string 1 body)))
                      (gloss (replace-regexp-in-string
                              "[ \t\n]+" " "
                              (string-trim (match-string 2 body)))))
                  (when (and (not (string-empty-p wylie))
                             (not (string-empty-p gloss)))
                    (push (format "  - %s = %s" wylie gloss) pairs)))
                (setq pos (match-end 0)))
              (when pairs
                (mapconcat #'identity (nreverse pairs) "\n")))))
      (error nil))))

(defun tibetan-analysis--format-segment-vocabulary (analysis-file)
  "Return the per-segment vocabulary block for the Claude user prompt.
Draws from the `** Word / Particle List' section of ANALYSIS-FILE
when present (legacy files), falling back to the `** Interlinear
Gloss' section (current layout — §5.10 retired Word / Particle List).
Either way the block carries the tool's own per-segment matches,
already enriched with Hill morphology and Resources entries.  Returns
nil when neither section yields content so the prompt builder can skip
it cleanly."
  (let ((body (or (tibetan-analysis--read-word-particle-list analysis-file)
                  (tibetan-analysis--read-interlinear-glosses analysis-file))))
    (when body
      (concat "\n\nPer-segment vocabulary matches (from the analysis "
              "file — the tool's own layered lookup across Resources, "
              "Hopkins, Bialek, and bundled glossaries).  These are "
              "dictionary-attested: base the Vocabulary section on them "
              "and do NOT invent an unattested meaning for a content "
              "word listed here.  Where context needs a different sense, "
              "choose among the attested senses rather than coining a "
              "new one; treat particle tags as authoritative.\n\n" body))))

;; ----------------------------------------------------------------------------
;; Translation Comparison (paragraph-only feature, separate command)
;; ----------------------------------------------------------------------------
;;
;; Refreshes the `* Translation Comparison' section of a par-NNN.org
;; analysis file: reads the available translations (Lopez 2006,
;; Wangjié & Mulligan, future DharmaMitra, plus the user's
;; `* Working Translation' if present), asks Claude for a pairwise
;; similarity matrix (0 = essentially incomparable, 1 = identical;
;; pure content + grammatical agreement) plus a diagnostic block
;; explaining substantive divergences, and writes the result back
;; into the file as an org-table + prose.
;;
;; Bound to `C-c u T'.  Separate from `C-c u R' (reanalyze) so the
;; matrix doesn't get silently overwritten — it's an explicit
;; comparison snapshot the user requests.

(defun tibetan-analysis--collect-paragraph-translations (analysis-file)
  "Return alist of (label . body) for translations in ANALYSIS-FILE.
Sources, in order:
  - `** <Translator>' subsections under `* Reference Translations'
    (Lopez, Wangjié, future DharmaMitra…)
  - `* Working Translation' top-level body (the user's own German
    rendering), labeled `Working Translation', omitted when empty.
Returns nil when neither source has populated content."
  (when (and analysis-file (file-exists-p analysis-file))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((collected '()))
        ;; (a) Reference Translations top-level section
        (goto-char (point-min))
        (when (re-search-forward "^\\* Reference Translations\\b" nil t)
          (let ((section-end
                 (save-excursion
                   (if (re-search-forward "^\\* " nil t)
                       (line-beginning-position)
                     (point-max)))))
            (while (re-search-forward "^\\*\\* \\(.+?\\)[ \t]*$"
                                      section-end t)
              (let* ((label (string-trim (match-string 1)))
                     (body-start
                      (save-excursion (forward-line 1) (point)))
                     (body-end
                      (save-excursion
                        (goto-char body-start)
                        (if (re-search-forward "^\\*+ " section-end t)
                            (line-beginning-position)
                          section-end)))
                     (body (string-trim
                            (buffer-substring-no-properties
                             body-start body-end))))
                (when (not (string-empty-p body))
                  (push (cons label body) collected))))))
        ;; (b) Working Translation top-level section (the user's own)
        (goto-char (point-min))
        (when (re-search-forward "^\\* Working Translation\\b" nil t)
          (let* ((body-start (save-excursion (forward-line 1) (point)))
                 (body-end
                  (save-excursion
                    (goto-char body-start)
                    (if (re-search-forward "^\\* " nil t)
                        (line-beginning-position)
                      (point-max))))
                 (body (string-trim
                        (buffer-substring-no-properties
                         body-start body-end))))
            (when (and body (not (string-empty-p body))
                       ;; Skip placeholder-only sections
                       (not (string-match-p "\\`#" body)))
              (push (cons "Working Translation" body) collected))))
        (nreverse collected)))))

(defun tibetan-analysis--build-comparison-prompts (tibetan-text translations)
  "Return (SYSTEM . USER) prompt cons for the translation comparison.
TIBETAN-TEXT is the source paragraph; TRANSLATIONS is alist of
(label . body) pairs as returned by
`tibetan-analysis--collect-paragraph-translations'.

The system prompt frames Claude as an evaluator scoring pairwise
content + grammatical similarity on a 0–1 scale.  The user prompt
lays out the source + each translation labeled, and requests two
markdown sections (`## Comparison Matrix' and `## Diagnostic')."
  (let* ((labels (mapcar #'car translations))
         (system
          (concat
           "You are evaluating multiple translations of the same "
           "Classical Tibetan passage for content and grammatical "
           "similarity.  Produce TWO sections in markdown, in this "
           "order and nothing else:\n\n"
           "## Comparison Matrix\n"
           "A symmetric markdown table with one row and one column "
           "per translation.  Pairwise score from 0 (essentially "
           "incomparable in content + grammar — different verb, "
           "different argument structure, different sentence "
           "boundaries) to 1.00 (identical / paraphrase-only).  "
           "Diagonal is 1.00.  Score with two decimals.  No prose "
           "in this section, just the table.\n\n"
           "## Diagnostic\n"
           "2–3 short paragraphs covering, in order:\n"
           "1. Where the translations agree (the shared backbone).\n"
           "2. Where they diverge meaningfully and WHY — Tibetan "
           "ambiguity / interpretive choice / different segmentation "
           "/ register / philological reading.  Quote the relevant "
           "Tibetan / Wylie in italics.\n"
           "3. Which reading the Tibetan grammar best supports, "
           "and a one-sentence verdict on each non-diagonal pair "
           "where the score is below 0.80."))
         (user
          (concat
           "Tibetan source:\n\n"
           tibetan-text
           "\n\nTranslations:\n\n"
           (mapconcat
            (lambda (tr)
              (format "- *%s:*\n%s" (car tr) (cdr tr)))
            translations
            "\n\n")
           "\n\nLabels for the matrix axes (use exactly these):\n"
           (mapconcat (lambda (l) (format "  - %s" l))
                      labels "\n")
           "\n\nProduce the two sections now.")))
    (cons system user)))

(defun tibetan-analysis--parse-comparison-response (response)
  "Parse Claude's translation-comparison RESPONSE.
Returns plist (:matrix STRING :diagnostic STRING) where:
  :matrix     is the markdown / org-compatible table block (the
              `| ... |' lines) extracted from the `## Comparison
              Matrix' section, or nil when no table was emitted.
  :diagnostic is the prose body of the `## Diagnostic' section
              (everything after the heading until end-of-response),
              or nil when absent."
  (when (and response (stringp response))
    (let (matrix diagnostic)
      ;; Matrix: extract ALL `|`-bounded lines that follow the
      ;; `## Comparison Matrix' heading until the next `##' or end.
      (when (string-match "^## Comparison Matrix[ \t]*\n+\\(\\(?:\\(?:|.*\\|[ \t]*\\)\n\\)+\\)"
                          response)
        (setq matrix (string-trim (match-string 1 response))))
      ;; Diagnostic: everything between `## Diagnostic' and end.
      (when (string-match "^## Diagnostic[ \t]*\n+\\(\\(?:.\\|\n\\)+\\)\\'"
                          response)
        (setq diagnostic (string-trim (match-string 1 response))))
      (when (or matrix diagnostic)
        (list :matrix matrix :diagnostic diagnostic)))))

(defun tibetan-analysis--write-comparison-section (analysis-file matrix-org diagnostic)
  "Write `* Translation Comparison' section into ANALYSIS-FILE.
MATRIX-ORG is the org-table body (string of `| ... |' rows).
DIAGNOSTIC is the prose body.  Either may be nil; the section is
still emitted if at least one is present.

Position invariant: the section sits between `* Working Translation'
and `* Auto-Analysis'.  If a `* Translation Comparison' section
already exists, it's replaced in place; otherwise inserted at the
canonical position.  Idempotent."
  (with-current-buffer (find-file-noselect analysis-file)
    (save-excursion
      (goto-char (point-min))
      ;; If already present, delete the existing block first.
      (when (re-search-forward "^\\* Translation Comparison\\b" nil t)
        (let ((start (line-beginning-position))
              (end (save-excursion
                     (forward-line 1)
                     (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max)))))
          (delete-region start end)))
      ;; Insertion point: just before `* Tibetan Analysis' (or
      ;; legacy `* Auto-Analysis'), or before first `* ' heading
      ;; after `* Working Translation', or at end.  Phase 1.2 of
      ;; layout-revision §5.18 (2026-05-04): the parent heading
      ;; rename means readers must accept BOTH names — old files
      ;; pre-migration still carry `* Auto-Analysis' until first
      ;; reanalyse rewrites them.
      (goto-char (point-min))
      (cond
       ((re-search-forward "^\\* \\(Tibetan Analysis\\|Auto-Analysis\\)\\b" nil t)
        (beginning-of-line))
       ((re-search-forward "^\\* Working Translation\\b" nil t)
        (forward-line 1)
        (if (re-search-forward "^\\* " nil t)
            (beginning-of-line)
          (goto-char (point-max))))
       (t (goto-char (point-max))))
      (let ((block
             (concat
              "* Translation Comparison\n"
              "# Pairwise content + grammatical similarity (0 = "
              "incomparable, 1 = identical).  Refresh via C-c u T.\n\n"
              (when matrix-org (concat matrix-org "\n\n"))
              (when diagnostic (concat diagnostic "\n\n")))))
        (insert block))
      (save-buffer))))

;;;###autoload
(defun tibetan-translation-comparison-refresh ()
  "Refresh the `* Translation Comparison' section of the current par-NNN.org.
Collects all available translations (Lopez, Wangjié, future
Mitra, plus the user's `* Working Translation' if non-empty),
asks Claude to score them pairwise (0 = incomparable, 1 =
identical) and explain divergences, and rewrites the section.
Bound to `C-c u T'.

Requires gptel + a configured Anthropic API key.  Errors are
surfaced via `message' rather than signalled."
  (interactive)
  (let* ((analysis-file (buffer-file-name))
         (label (and analysis-file
                     (file-name-nondirectory analysis-file))))
    (unless (and analysis-file
                 (string-match-p "/par-[0-9]+\\(?:-.*\\)?\\.org\\'"
                                 analysis-file))
      (error "Not in a par-NNN.org analysis file"))
    (let* ((translations
            (tibetan-analysis--collect-paragraph-translations analysis-file))
           (tibetan-text
            (with-temp-buffer
              (insert-file-contents analysis-file)
              (goto-char (point-min))
              (when (re-search-forward "^\\* Tibetan Text\\b" nil t)
                (let* ((body-start
                        (save-excursion (forward-line 1) (point)))
                       (body-end
                        (save-excursion
                          (goto-char body-start)
                          (if (re-search-forward "^\\* " nil t)
                              (line-beginning-position)
                            (point-max)))))
                  (string-trim
                   (buffer-substring-no-properties body-start body-end)))))))
      (when (or (null translations) (< (length translations) 2))
        (error "Need at least 2 translations to compare; found %d"
               (length (or translations '()))))
      (when (or (null tibetan-text) (string-empty-p tibetan-text))
        (error "Could not read Tibetan source from analysis file"))
      (require 'tibetan-claude-queue)
      (tibetan-claude-queue-submit
       (lambda (done)
         (condition-case err
             (progn
               (unless (and (featurep 'gptel) (fboundp 'gptel-request))
                 (error "gptel not loaded"))
               (tibetan-analysis--ensure-gptel-ready)
               (let* ((prompts (tibetan-analysis--build-comparison-prompts
                                tibetan-text translations))
                      (gptel-cache '(system)))
                 (gptel-request
                  (cdr prompts)
                  :system (car prompts)
                  :callback
                  (lambda (response info)
                    (condition-case cb-err
                        (cond
                         ((stringp response)
                          (let ((parsed
                                 (tibetan-analysis--parse-comparison-response
                                  response)))
                            (if parsed
                                (progn
                                  (tibetan-analysis--write-comparison-section
                                   analysis-file
                                   (plist-get parsed :matrix)
                                   (plist-get parsed :diagnostic))
                                  (message
                                   "Translation comparison refreshed: %s"
                                   label))
                              (message
                               "Translation comparison: response unparseable"))))
                         ((tibetan-analysis--claude-status-rate-limited-p info)
                          (message "Translation comparison: rate-limited; try again shortly"))
                         (t (message
                             "Translation comparison: no response (%S)"
                             info)))
                      (error (message "Translation comparison callback error: %s"
                                      (error-message-string cb-err))))
                    (funcall done))))
               nil)
           (error (message "Translation comparison failed: %s"
                           (error-message-string err))
                  (funcall done))))
       :label (format "tcomp:%s" (or label "?"))))))

;; ----------------------------------------------------------------------------
;; Reference-translations context (paragraph analysis files only)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--format-reference-translations (analysis-file)
  "Return the `* Reference Translations' block for the Claude user prompt.
Reads the top-level `* Reference Translations' section of
ANALYSIS-FILE and formats its `**'-subsections (one per translator —
Lopez, Wangjié, DharmaMitra, …) as labeled context blocks.  Returns
nil when:
  - the section is absent (e.g. seg-NNN.org without paragraph imports);
  - all `**'-subsection bodies are empty.
Instructs Claude to cross-check its translation against the references
and flag substantive divergences in the `## Grammar' section."
  (when (and analysis-file (file-exists-p analysis-file))
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (goto-char (point-min))
      (when (re-search-forward "^\\* Reference Translations\\b" nil t)
        (let ((section-end
               (save-excursion
                 (if (re-search-forward "^\\* " nil t)
                     (line-beginning-position)
                   (point-max))))
              (refs '()))
          (while (re-search-forward "^\\*\\* \\(.+?\\)[ \t]*$"
                                    section-end t)
            (let* ((heading (string-trim (match-string 1)))
                   (body-start
                    (save-excursion (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (goto-char body-start)
                      (if (re-search-forward "^\\*+ " section-end t)
                          (line-beginning-position)
                        section-end)))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (when (not (string-empty-p body))
                (push (cons heading body) refs))))
          (when refs
            (concat
             "\n\nExisting reference translations of THIS passage "
             "(read-only, imported from the comparative source).  "
             "Use them as calibration: cross-check your translation "
             "against them and prefer their conventions for proper "
             "names and technical terms when defensible.  In the "
             "`## Grammar' section, briefly note (one or two sentences) "
             "where your translation diverges substantively from them "
             "and which Tibetan reading supports your choice — this "
             "helps the user judge between competing interpretations.\n"
             (mapconcat
              (lambda (r)
                (format "\n— %s:\n%s" (car r) (cdr r)))
              (nreverse refs)
              ""))))))))

;; ----------------------------------------------------------------------------
;; Surrounding-segments context (±2 neighbors from the same analysis folder)
;; ----------------------------------------------------------------------------

(defun tibetan-analysis--neighbor-analysis-file (analysis-file seg-id)
  "Return the existing `seg-SEG-ID*.org' neighbor of ANALYSIS-FILE, or nil.
Looks in the same directory; if multiple variants exist (e.g. with a
short-title suffix), picks the one whose basename matches the exact
`seg-NNN' prefix first, otherwise falls back to directory-files
ordering.  SEG-ID is an integer."
  (when (and analysis-file seg-id)
    (let* ((dir (file-name-directory analysis-file))
           (prefix (format "seg-%03d" seg-id))
           ;; Accept either `seg-012.org' or `seg-012-short-title.org'.
           (candidates
            (and (file-directory-p dir)
                 (directory-files
                  dir t
                  (concat "\\`"
                          (regexp-quote prefix)
                          "\\(\\.org\\'\\|-\\)")))))
      (car candidates))))

(defun tibetan-analysis--format-neighbor-segment
    (analysis-file seg-id offset)
  "Return a text block describing ANALYSIS-FILE's neighbor at OFFSET.
Reads `* Tibetan Text' (required) and `* Working Translation'
(optional) from the neighbor file.  OFFSET is the signed distance
(e.g. -1 for preceding, +1 for following).  Returns nil when the
neighbor does not exist or has no Tibetan text."
  (let* ((neighbor-id (+ seg-id offset))
         (neighbor (tibetan-analysis--neighbor-analysis-file
                    analysis-file neighbor-id)))
    (when (and neighbor (file-exists-p neighbor))
      (let* ((tibetan (tibetan-analysis--read-section-body
                       neighbor "Tibetan Text"))
             (working (tibetan-analysis--read-section-body
                       neighbor "Working Translation"))
             (label (format "Segment %d (%s %d)"
                            neighbor-id
                            (if (< offset 0) "−" "+")
                            (abs offset))))
        (when (and tibetan (not (string-empty-p (string-trim tibetan))))
          (concat label "\n"
                  "  Tibetan: " (string-trim tibetan)
                  (when (and working
                             (not (string-empty-p (string-trim working))))
                    (concat "\n  Working translation: "
                            (string-trim working)))))))))

(defun tibetan-analysis--format-surrounding-segments (analysis-file)
  "Return a ±2 surrounding-segments block for the Claude user prompt.
For each of offsets -2, -1, +1, +2 that resolves to an existing
neighbor file (see `--neighbor-analysis-file'), include its Tibetan
text and Working Translation (if non-empty).  Returns nil when no
neighbors could be resolved so the prompt stays lean for isolated
segments."
  (when analysis-file
    (let ((seg-id (tibetan-analysis--seg-id-from-filename analysis-file)))
      (when seg-id
        (let ((parts '()))
          (dolist (offset '(-2 -1 1 2))
            (let ((block (tibetan-analysis--format-neighbor-segment
                          analysis-file seg-id offset)))
              (when block (push block parts))))
          (when parts
            (concat "\n\nSurrounding segments (±2) — context only; "
                    "translate ONLY the target passage.  Use these to "
                    "resolve pronouns, discourse particles, and "
                    "sentence-internal reference across segment "
                    "boundaries.\n\n"
                    (mapconcat #'identity (nreverse parts) "\n\n"))))))))

;; ----------------------------------------------------------------------------
;; Sanskrit-parallel reading mode (Phase 3, 2026-04-27)
;; ----------------------------------------------------------------------------
;;
;; Two helpers — system-block + user-block — emit the additions
;; injected when the source carries `#+SOURCE_MODE: parallel-sanskrit'
;; and (for the user-block) when the caller has located the
;; segment's Sanskrit text via `tibetan-sanskrit-parallel-text-for-
;; segment-id'.  Both are constant per document so they participate
;; in Anthropic prompt caching just like the existing target-lang
;; and portfolio blocks: the system prefix stays byte-identical
;; across every segment of a parallel-Sanskrit document, so
;; requests 2..N within the 5-min TTL hit warm cache.

;; Phase 1 of two-language-parallel-analysis (2026-04-30):
;; The Phase B–D parallel-mode block (which asked Claude to also
;; produce `## Translation (Sanskrit)' / `(Combined)' /
;; `## Divergence' on top of the Tibetan-only response) is retired.
;; The Tibetan call now does Tibetan only, byte-identical for
;; parallel and non-parallel documents.  Sanskrit-side analysis is
;; produced by a separate Sanskrit Claude call (see
;; `persist/tibetan-analysis-sanskrit.el', Phase 2); the Combined
;; synthesis comes from a third Combined call (Phase 4).  This
;; sharpens the per-call cache (parallel and non-parallel docs share
;; the same Tibetan-call cache prefix) and makes each call's
;; response schema small and unambiguous.

(defun tibetan-analysis--claude-static-system-blocks (source-file)
  "Return the per-DOCUMENT static system-prompt suffix for SOURCE-FILE.
Concatenation of the source-metadata block, the Portfolio reference
block, and the target-language directive — everything appended to the
base system prompt that is CONSTANT across all segments/sentences of
one document.  Shared by the segment builder and the sentence-first
builder (§5.40) so the Anthropic prompt-cache constancy of BOTH is
guaranteed by construction, not by parallel maintenance."
  (let* ((meta (tibetan-analysis--read-source-metadata source-file))
         (title (plist-get meta :title))
         (work (plist-get meta :work))
         (author (plist-get meta :author))
         (ctx (plist-get meta :claude-context))
         (meta-block
          (let (parts)
            (when work (push (format "Work: %s" work) parts))
            (when (and author (not (and work (string= work author))))
              (push (format "Author: %s" author) parts))
            (when (and title (not work))
              (push (format "Title: %s" title) parts))
            (when ctx
              (push "Context from source file:" parts)
              (dolist (line ctx)
                (push (format "  - %s" line) parts)))
            (when parts
              (concat "\n\nSource metadata for this passage:\n"
                      (mapconcat #'identity (nreverse parts) "\n")))))
         (portfolio-ref
          (and (fboundp 'tibetan-interlinear-portfolio-reference-block)
               (condition-case nil
                   (tibetan-interlinear-portfolio-reference-block)
                 (error ""))))
         (portfolio-part
          (and portfolio-ref (not (string-empty-p portfolio-ref))
               (concat "\n\n" portfolio-ref)))
         (target-lang-val (plist-get meta :target-lang))
         (lang-part
          (when (and target-lang-val (stringp target-lang-val)
                     (equal (downcase target-lang-val) "de"))
            (concat "\n\nTarget language for this document: GERMAN.\n"
                    "The `## Translation' section MUST be written in "
                    "German (not English), following the same guidelines "
                    "otherwise — fluent, idiomatic, Buddhist terminology "
                    "preserved, etc.  Vocabulary, Grammar, and Particles "
                    "sections stay in English (metalanguage)."))))
    (concat (or meta-block "") (or portfolio-part "") (or lang-part ""))))

(defun tibetan-analysis--build-claude-prompts
    (tibetan-text source-file &optional analysis-file)
  "Build (SYSTEM . USER) Claude prompts for TIBETAN-TEXT.
SOURCE-FILE, if non-nil, supplies genre/author/context metadata and a
Resources vocabulary file.  ANALYSIS-FILE, if non-nil, supplies four
forms of grounding:
  1. the parser's own output (grammatical markers, clause structure,
     verb classification) for the Grammar section;
  2. the tool's per-segment `** Word / Particle List' matches as a
     vocabulary hint for the Translation section;
  3. ±2 surrounding segments (Tibetan + Working Translation if present)
     from the same analysis folder so Claude can resolve anaphora and
     discourse without over-interpreting an isolated line;
  4. the file's own seg-id (used to resolve the neighbors in (3)).

SANSKRIT-PLIST, if non-nil, is the parallel-mode walker plist
`(:iast STR :devanagari STR-or-nil :script-source SYM)' returned
by `tibetan-sanskrit-parallel-text-for-segment-id'.  When supplied
together with `#+SOURCE_MODE: parallel-sanskrit' on the source
file, the user prompt prepends a Sanskrit (primary) block above
the Tibetan passage and the system prompt gains a Sanskrit-primary
directive (Phase 3 of sanskrit-parallel-workflow, 2026-04-27).
Backward compatible with all existing callers that pass only the
first three args."
  (let* ((meta   (tibetan-analysis--read-source-metadata source-file))
         ;; title/work/author/ctx now live in
         ;; `tibetan-analysis--claude-static-system-blocks' (§5.40).
         (vocab-rel (plist-get meta :vocab-file))
         (vocab-file (and vocab-rel source-file
                          (expand-file-name
                           vocab-rel (file-name-directory source-file))))
         (glossary (and vocab-file
                        (tibetan-analysis--match-resources-vocab
                         tibetan-text vocab-file)))
         (wylie (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (tibetan-to-wylie-fixed tibetan-text))
                  (error nil)))
         ;; Phase 1 of two-language-parallel-analysis (2026-04-30):
         ;; The parallel-mode injection (which extended this Tibetan
         ;; prompt with `## Translation (Sanskrit)' / `(Combined)' /
         ;; `## Divergence' instructions) is retired.  Sanskrit-side
         ;; output is now produced by a separate Sanskrit Claude
         ;; call; the Combined synthesis by a third Combined call.
         ;; This Tibetan call's system prompt is therefore
         ;; byte-identical for parallel and non-parallel documents,
         ;; and they share the same Anthropic cache prefix.
         ;; §5.40: the static blocks (metadata/Portfolio/target-lang)
         ;; come from the shared helper so the segment AND
         ;; sentence-first system prompts stay per-document constants
         ;; by construction.
         (system (concat tibetan-analysis--claude-system-prompt
                         (tibetan-analysis--claude-static-system-blocks
                          source-file)))
         (glossary-block
          (when glossary
            (concat
             "\n\nGlossary for this passage — authoritative. "
             "Prefer these renderings in the Translation section; "
             "treat proper names and epithets as single tokens in the "
             "Grammar section.\n"
             (mapconcat (lambda (kv)
                          (format "  - %s = %s" (car kv) (cdr kv)))
                        glossary "\n"))))
         (vocab-block
          (tibetan-analysis--format-segment-vocabulary analysis-file))
         (surrounding-block
          (tibetan-analysis--format-surrounding-segments analysis-file))
         (grounding-block
          (tibetan-analysis--format-parser-grounding
           (tibetan-analysis--read-analysis-parser-sections analysis-file)))
         ;; Reference translations: in paragraph analysis files
         ;; (par-NNN.org) these are imported from sibling subsections
         ;; of the source `** §N' paragraph (Lopez, Wangjié, future
         ;; DharmaMitra…).  Feeding them into the user prompt lets
         ;; Claude calibrate its translation against existing renderings
         ;; and flag interpretive divergences — see system prompt
         ;; addendum for the comparison instruction.
         (references-block
          (tibetan-analysis--format-reference-translations analysis-file))
         ;; Phase 3 of sanskrit-parallel-workflow (2026-04-27): when
         ;; Phase 1 of two-language-parallel-analysis (2026-04-30):
         ;; the Sanskrit user-block injection is retired.  Sanskrit
         ;; goes to a separate Sanskrit Claude call (Phase 2 module);
         ;; this Tibetan user prompt no longer mentions Sanskrit at
         ;; all — Tibetan-only, parallel-and-non-parallel-identical.
         ;; §5.25 (2026-05-24):  inject thesaurus zettel references
         ;; for any term in the passage that has a curated zettel.
         ;; Claude uses these to cite `[[id:ZID][zettel ↗]]' inline
         ;; in the Concept Notes section.  Empty string when no
         ;; zettel matches — silent fall-through.
         (zettel-block
          (tibetan-analysis--format-zettel-references-block
           (tibetan-analysis--collect-zettel-references tibetan-text)))
         (user (concat "Classical Tibetan passage:\n\n"
                       tibetan-text
                       (if wylie (format "\n\nWylie: %s" wylie) "")
                       (or glossary-block "")
                       (or vocab-block "")
                       (or surrounding-block "")
                       (or grounding-block "")
                       (or references-block "")
                       (or zettel-block "")
                       "\n\nProduce the five sections now.")))
    (cons system user)))

(defun tibetan-analysis--read-authinfo-key (host)
  "Read password for HOST from ~/.authinfo or ~/.authinfo.gpg.
Parses the file directly for reliability.
Returns the password string or nil."
  (let ((authinfo-files (list (expand-file-name "~/.authinfo")
                              (expand-file-name "~/.authinfo.gpg"))))
    (cl-loop for file in authinfo-files
             when (file-exists-p file)
             do (condition-case nil
                    (with-temp-buffer
                      (insert-file-contents file)
                      (goto-char (point-min))
                      (when (re-search-forward
                             (format "machine %s.*?password \\(\\S-+\\)"
                                     (regexp-quote host))
                             nil t)
                        (cl-return (match-string 1))))
                  (error nil)))))

(defun tibetan-analysis--ensure-gptel-ready ()
  "Ensure gptel is configured with Anthropic backend and API key.
Sets up the backend if claude-integration.el was not loaded.
Reads the API key from ~/.authinfo or environment.
Returns non-nil if gptel is ready to use."
  (when (featurep 'gptel)
    ;; Step 1: Ensure API key is set
    (unless (and (boundp 'gptel-api-key)
                 gptel-api-key
                 (stringp gptel-api-key)
                 (not (string-empty-p gptel-api-key)))
      ;; Read directly from ~/.authinfo (most reliable)
      (let ((key (tibetan-analysis--read-authinfo-key "api.anthropic.com")))
        (when key
          (setq gptel-api-key key)))
      ;; Fallback: environment variable
      (unless (and (boundp 'gptel-api-key) gptel-api-key)
        (let ((env-key (getenv "ANTHROPIC_API_KEY")))
          (when (and env-key (not (string-empty-p env-key)))
            (setq gptel-api-key env-key)))))

    ;; Step 2: Ensure Anthropic backend is configured
    (when (and (boundp 'gptel-api-key)
               gptel-api-key
               (stringp gptel-api-key))
      (unless (and (boundp 'gptel-backend)
                   gptel-backend
                   ;; Check name field for Anthropic/Claude
                   (ignore-errors
                     (string-match-p "Claude\\|Anthropic"
                                     (format "%s" gptel-backend))))
        ;; Configure Anthropic backend
        (when (fboundp 'gptel-make-anthropic)
          (setq gptel-backend (gptel-make-anthropic "Claude"
                                :stream t
                                :key gptel-api-key))
          (unless (and (boundp 'gptel-model) gptel-model)
            (setq gptel-model "claude-sonnet-4-20250514"))))
      t)))

(defun tibetan-analysis--write-claude-failure-stub (analysis-file msg)
  "Write MSG into the *** Claude Translation section of ANALYSIS-FILE.
Only writes if that section is currently empty, missing, or already
holds a prior failure stub — never overwrites a real Claude response.
This is what callers should do from a queue :on-fail handler so the
user can see at a glance which segments still need a real Claude pass."
  (when (and analysis-file (file-exists-p analysis-file))
    (let* ((existing (ignore-errors
                       (tibetan-analysis--read-claude-sections
                        analysis-file)))
           (translation (and existing (plist-get existing :translation)))
           (trimmed (and translation (string-trim translation))))
      (when (or (null trimmed)
                (string-empty-p trimmed)
                (string-prefix-p "[Claude" trimmed)
                (string-prefix-p "[Requesting translation" trimmed))
        (let ((buf (or (find-buffer-visiting analysis-file)
                       (find-file-noselect analysis-file))))
          (with-current-buffer buf
            (when (fboundp 'tibetan-analysis--ensure-claude-headings)
              (tibetan-analysis--ensure-claude-headings buf))
            (when (fboundp 'tibetan-analysis--replace-claude-section-body)
              ;; Phase 1.3 of layout-revision §5.18 (2026-05-04): pick
              ;; the right heading + level for the layout.  Segment
              ;; layout writes into `** Translation' (level 2) — the
              ;; new name.  Sentence layout writes into the legacy
              ;; `*** Claude Translation' (level 3) carve-out.
              (if (tibetan-analysis--claude-segment-layout-p buf)
                  (tibetan-analysis--replace-claude-section-body
                   buf "Translation" msg 2)
                (tibetan-analysis--replace-claude-section-body
                 buf "Claude Translation" msg 3)))
            (save-buffer)))))))

(defun tibetan-analysis--claude-status-rate-limited-p (info)
  "Non-nil when gptel callback INFO indicates HTTP 429 (rate limited)."
  (let ((s (and (listp info) (plist-get info :status))))
    (and s (stringp s) (string-match-p "\\b429\\b" s))))

(defun tibetan-analysis--request-claude-translation
    (tibetan-text analysis-file &optional source-file)
  "Request a Claude translation of TIBETAN-TEXT asynchronously.
When the response arrives, insert it into ANALYSIS-FILE under the
*** Claude heading in the Provided Translations section.

If SOURCE-FILE is given (or can be derived from ANALYSIS-FILE's
`#+SOURCE:' link), its `#+TIBETAN_CLAUDE_CONTEXT:' headers,
:WORK/:AUTHOR properties and a Resources vocabulary file are folded
into the prompts so Claude gets genre / author / glossary context.

Requests go through `tibetan-claude-queue' so concurrent requests
are capped (see `tibetan-claude-queue-concurrency') and HTTP 429
responses are retried with exponential backoff (see
`tibetan-claude-queue-max-retries').  When retries are exhausted, a
visible placeholder is written into the *** Claude Translation
section so the segment is easy to find and re-run later via C-c u R.

Requires gptel and a configured Anthropic API key.  Never signals —
failures are reported via `message' and the placeholder."
  (require 'tibetan-claude-queue)
  (let ((label (and analysis-file
                    (file-name-nondirectory analysis-file))))
    (tibetan-claude-queue-submit
     (lambda (done)
       (condition-case err
           (progn
             (unless (and (featurep 'gptel) (fboundp 'gptel-request))
               (error "gptel not loaded"))
             (tibetan-analysis--ensure-gptel-ready)
             (let* ((src (or source-file
                             (tibetan-analysis--source-file-from-analysis
                              analysis-file)))
                    ;; Phase 1 of two-language-parallel-analysis
                    ;; (2026-04-30): the Sanskrit-plist threading is
                    ;; retired here.  This Tibetan call no longer
                    ;; needs to know about Sanskrit;  Sanskrit-side
                    ;; output is produced by the new Sanskrit Claude
                    ;; call (Phase 2 module), which does its own
                    ;; walker lookup.
                    (prompts (tibetan-analysis--build-claude-prompts
                              tibetan-text src analysis-file))
                    (system-prompt (car prompts))
                    (user-prompt   (cdr prompts))
                    ;; Prompt caching: the system prompt is identical
                    ;; across every seg-*.org in a document (it's
                    ;; `tibetan-analysis--claude-system-prompt' +
                    ;; the source file's `#+TIBETAN_CLAUDE_CONTEXT'
                    ;; block).  Marking it as an Anthropic cached
                    ;; prefix means every request after the first
                    ;; within the 5-minute TTL pays only 10% of the
                    ;; normal input cost on the cached portion.
                    ;; One-time write overhead is +25% on the first
                    ;; request; savings compound from request 2 on.
                    ;; See gptel-anthropic.el line ~213 for the
                    ;; `cache_control: {"type": "ephemeral"}' wiring.
                    (gptel-cache '(system)))
               (gptel-request
                user-prompt
                :system system-prompt
                :callback
                (lambda (response info)
                  (cond
                   ;; Success: have a non-empty response body.
                   ((and response (stringp response)
                         (not (string-empty-p response)))
                    (condition-case e
                        (tibetan-analysis--insert-claude-translation
                         response analysis-file)
                      (error
                       (message "Claude insert failed for %s: %s"
                                (or label "<file>")
                                (error-message-string e))))
                    (funcall done '(:status ok)))
                   ;; HTTP 429 — let the queue retry.
                   ((tibetan-analysis--claude-status-rate-limited-p info)
                    (funcall done '(:status rate-limited)))
                   ;; Anything else — non-retryable from our point of view.
                   (t
                    (funcall done
                             (list :status 'error
                                   :error (format "%s"
                                                  (or (and (listp info)
                                                           (plist-get info :status))
                                                      "no response")))))))) ))
         (error
          (funcall done (list :status 'error
                              :error (error-message-string err))))))
     :label label
     :on-fail
     (lambda (status)
       (let* ((kind (plist-get status :status))
              (msg (cond
                    ((eq kind 'rate-limited)
                     "[Claude request failed: rate-limited (HTTP 429) after retries — re-run C-c u R later]")
                    (t (format "[Claude request failed: %s — re-run C-c u R later]"
                               (or (plist-get status :error) "unknown"))))))
         (tibetan-analysis--write-claude-failure-stub
          analysis-file msg))))))

(defun tibetan-analysis--parse-claude-sections (response)
  "Split RESPONSE on `## …' Translation / Vocabulary / Grammar /
Particles / `Concept Notes' (or legacy `Context') markdown headings.
Returns a plist with `:translation' / `:vocabulary' / `:grammar' /
`:particles' / `:concepts' string-or-nil values.

§5.24 (2026-05-22):  the legacy `## Context' heading is accepted
for backwards compatibility (older Claude responses still
delivered after a prompt change but before the model picks up
the rename) and routed to the `:concepts' slot.  The elisp key
`:context' is retired in favour of `:concepts'.

Missing sections are nil (not empty string) so the writer can leave
the old org body in place when Claude omitted a section.  When
RESPONSE contains no recognised heading, the whole (trimmed) string is
returned as `:translation' — this keeps backwards compatibility with
legacy single-translation responses.

`:particles' is a raw multi-line block of `word, particle, sub-id,
label' lines; parsing into structured tuples is downstream's job
(`tibetan-analysis--parse-claude-particles').

Phase 1 of two-language-parallel-analysis (2026-04-30):  the
suffixed `Translation (Sanskrit)' / `Translation (Combined)'
keys + the `Divergence' key (added in Phase B–D earlier today)
are retired.  Sanskrit-side and Combined-synthesis Claude output
is now produced by separate Claude calls (see
`persist/tibetan-analysis-sanskrit.el' and
`persist/tibetan-analysis-combined.el'), each with its own
parser.  This Tibetan parser goes back to its pre-Phase-B
five-key shape."
  (let ((result (list :translation nil :vocabulary nil :grammar nil
                      :particles nil :concepts nil))
        (re "^## \\(Translation\\|Vocabulary\\|Grammar\\|Particles\\|Concept Notes\\|Context\\)[ \t]*$"))
    (when (and response (stringp response) (not (string-empty-p response)))
      (with-temp-buffer
        (insert response)
        (goto-char (point-min))
        (if (not (re-search-forward re nil t))
            ;; Legacy response — whole thing is the translation.
            (setq result (plist-put result :translation
                                    (string-trim response)))
          ;; Structured response — walk the headings.
          (goto-char (point-min))
          (let ((matches '()))
            (while (re-search-forward re nil t)
              ;; §5.24:  `Concept Notes' and legacy `Context' both
              ;; route to the `:concepts' key.  Symbol-key lookup
              ;; mapping below.
              (let* ((raw (match-string 1))
                     (key (cond
                           ((string= raw "Concept Notes") 'concepts)
                           ((string= raw "Context") 'concepts)
                           (t (intern (downcase raw))))))
                (push (list key (match-end 0)) matches)))
            (setq matches (nreverse matches))
            (cl-loop for (cell . rest) on matches
                     for key = (car cell)
                     for start = (cadr cell)
                     for end = (if rest
                                   (save-excursion
                                     (goto-char (cadr (car rest)))
                                     (beginning-of-line)
                                     (point))
                                 (point-max))
                     for body = (string-trim
                                 (buffer-substring-no-properties
                                  start end))
                     do (setq result
                              (plist-put result
                                         (intern (format ":%s" key))
                                         (and (not (string-empty-p body))
                                              body))))))))
    result))

(defconst tibetan-analysis--claude-section-order
  '((:translation "Translation"        2)
    (:vocabulary  "Claude Vocabulary"  2)
    (:concepts    "Concept Notes"      2)
    (:grammar     "Claude Grammar"     3)
    (:particles   "Claude Particles"   3))
  "Canonical order, heading names, and org levels for Claude sections.
Each entry is (KEY HEADING LEVEL).

Translation sits at level 2 — the workshop-agreed slot, position 3
in the priority order (right after Wylie / Interlinear).  Phase
1.3 of layout-revision §5.18 (2026-05-04) renames the level-2
heading `Claude Translation' → `Translation'; parent context
\(`* Tibetan Analysis') makes the language-attribution clear so
the redundant `Claude' qualifier drops.  Level-3 `Claude
Vocabulary' / `Claude Grammar' / `Claude Particles' KEEP their
prefix — they nest under `** Grammar' or `** Provided
Translations' where the prefix still disambiguates.

Vocabulary lives at level 3 inside `** Provided Translations' —
a DharmaMitra-style word-by-word tier the reader consults alongside
the provided glosses.

Grammar (U4, 2026-04-24): moved from level 2 to level 3 so Claude's
prose reading nests UNDER `** Grammar' as `*** Claude Grammar',
placed between `*** Particle Map' and `*** Particles in This
Segment'.  The reader's Grammar section now flows visual-map →
prose-reading → detailed-particle-refs without a level-2 context
switch.  Existing files with `** Claude Grammar' at level 2 are
migrated on next regen by `--ensure-claude-headings'.

Particles is the Pass 6c addition (2026-04-22) — per-occurrence
`word, particle, portfolio-sub-id, label' tuples that let the
`*** Particles in This Segment' renderer attach a Portfolio
snippet to each specific particle function.  Stored at level 3
inside Provided Translations alongside Vocabulary.

The writer, reader, scaffolding, and migration all consult this
list so levels stay consistent everywhere.")

(defun tibetan-analysis--claude-heading-re (heading level)
  "Regexp that anchors `HEADING' at org LEVEL at beginning-of-line."
  (format "^%s %s$"
          (regexp-quote (make-string level ?*))
          (regexp-quote heading)))

(defun tibetan-analysis--claude-stop-re (level)
  "Regexp matching the start of any heading at org LEVEL or shallower."
  ;; Stars then a MANDATORY SPACE: real org headings are `*+ Title'.
  ;; The space (a) keeps `**' from matching inside `***' (backtracking
  ;; finds no space after either star run) and (b) — C1, Fable-5 audit
  ;; 2026-06-04 — keeps markdown-bold `**Clause 1:**' / org-emphasis
  ;; `*sic*' BODY lines from being mistaken for headings.  The previous
  ;; `[^*\n]' follower matched those, truncating every preserve-side
  ;; reader at the first such line; preserve-mode reanalyze then
  ;; destroyed the section tail (§5.26 data-loss class).
  (format "^\\*\\{1,%d\\} " level))

(defun tibetan-analysis--claude-segment-layout-p (buffer)
  "Return non-nil if BUFFER uses the segment-level analysis layout.

After the sentence-§5.18 alignment (2026-05-18), both segment
files AND aligned sentence files share the SAME shape:
`* Tibetan Analysis' parent, `** Translation' at level-2, nested
`** Provided Translations'.  We treat any buffer carrying
`* Tibetan Analysis' as segment-layout — the writer then uses the
level-2 Translation slot, the renamer migrates legacy `** Claude
Translation' → `** Translation' in place, etc.

Legacy sentence layout (`* Auto-Analysis' parent + top-level
`* Provided Translations') still returns nil so the writer uses
the level-3 Claude headings expected by the old shape.

Brand-new / empty buffers still default to segment layout so
fresh per-segment scaffolds get Translation promoted to level 2."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (cond
       ;; Aligned layout marker — `* Tibetan Analysis' parent.  Both
       ;; segment files AND new-style sentence files have this.
       ((re-search-forward "^\\* Tibetan Analysis$" nil t) t)
       ;; Legacy sentence marker — top-level `* Provided Translations'.
       ((progn
          (goto-char (point-min))
          (re-search-forward "^\\* Provided Translations$" nil t))
        nil)
       ;; Legacy sentence marker — `#+SEGMENTS:' header without a
       ;; `* Tibetan Analysis' parent (an old sentence file).  This
       ;; check ONLY applies when the buffer has the OLD shape;  the
       ;; new aligned shape is handled by the first clause above.
       ((progn
          (goto-char (point-min))
          (re-search-forward "^#\\+SEGMENTS:" nil t))
        nil)
       ;; Empty buffer or no sentence marker — segment layout.
       (t t)))))

(defun tibetan-analysis--claude-heading-inside-provided-p ()
  "Return non-nil if POINT is currently inside `* Provided Translations'.
Point should be on (or just after) a `*** Claude …' heading.  We
look up to find the nearest preceding `^\\* ' level-1 heading
and check whether its text is `Provided Translations'."
  (save-excursion
    (beginning-of-line)
    (when (re-search-backward "^\\* " nil t)
      (looking-at "^\\* Provided Translations$"))))

(defun tibetan-analysis--reparent-orphaned-claude-subsections (buffer)
  "Move level-3 Claude subsections that landed outside
`* Provided Translations' back into that section.

Earlier regenerate runs on sentence files (pre-reparent fix) could
append `*** Claude Translation' / `*** Claude Vocabulary' /
`*** Claude Grammar' at the end of the buffer (after `* Footnotes')
rather than inside Provided Translations.  This helper walks each
`^\\*\\*\\* Claude \\(Translation\\|Vocabulary\\|Grammar\\|Context\\)$'
heading, checks whether it sits inside `* Provided Translations',
and if not cuts the heading + body and re-inserts it at the end of
the Provided Translations section.  No-op when no Provided
Translations section exists or when no orphans are found."
  (with-current-buffer buffer
    (unless (save-excursion
              (goto-char (point-min))
              (not (re-search-forward "^\\* Provided Translations$" nil t)))
      (let ((headings '("Claude Translation" "Claude Vocabulary"
                        "Claude Grammar" "Claude Context")))
        (dolist (heading headings)
          (let (found-start body)
            ;; Scan for an orphaned instance; capture + delete it.
            (save-excursion
              (goto-char (point-min))
              (while (and (not found-start)
                          (re-search-forward
                           (format "^\\*\\*\\* %s$" (regexp-quote heading))
                           nil t))
                (unless (tibetan-analysis--claude-heading-inside-provided-p)
                  (let* ((h-start (line-beginning-position))
                         (body-start (progn (forward-line 1) (point)))
                         (body-end
                          (save-excursion
                            (if (re-search-forward
                                 (tibetan-analysis--claude-stop-re 3)
                                 nil t)
                                (line-beginning-position)
                              (point-max))))
                         (captured (string-trim
                                    (buffer-substring-no-properties
                                     body-start body-end))))
                    (setq found-start h-start
                          body captured)
                    (delete-region h-start body-end)))))
            ;; Re-insert inside Provided Translations at end.
            (when found-start
              (save-excursion
                (goto-char (point-min))
                (when (re-search-forward
                       "^\\* Provided Translations$" nil t)
                  (let ((section-end
                         (save-excursion
                           (if (re-search-forward "^\\* " nil t)
                               (line-beginning-position)
                             (point-max)))))
                    (goto-char section-end)
                    (skip-chars-backward " \t\n")
                    (insert (format "\n\n*** %s\n%s\n"
                                    heading
                                    (if (string-empty-p body) ""
                                      (concat body "\n"))))))))))))))

(defun tibetan-analysis--claude-l2-has-real-content-p (heading-re buffer)
  "Return non-nil when a level-2 heading matching HEADING-RE in BUFFER
carries non-placeholder body content.

\"Real content\" = body is non-empty AND does not match a known
Claude placeholder marker (`[Awaiting`, `[Requesting`, `[Claude
unavailable`, `[Claude request failed`, `[Translation not
available`).  Used by `--migrate-legacy-claude-headings' to
decide whether a level-2 slot is effectively empty (placeholder
only) and therefore eligible to receive migrated legacy
level-3 content.

§5.21 Commit 7 / §5.22 follow-up (2026-05-21):  added because
the prior guard checked only heading EXISTENCE, which made the
migration skip when the new §5.21 scaffold had emitted a fresh
`[Awaiting Claude…]' placeholder at level 2 — stranding legacy
level-3 content under `** Provided Translations'."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* \\(?:%s\\)$" heading-re) nil t)
        (forward-line 1)
        (let* ((start (point))
               (end (save-excursion
                      (if (re-search-forward
                           "^\\*\\* [^*\n]\\|^\\* " nil t)
                          (line-beginning-position)
                        (point-max))))
               (body (string-trim
                      (buffer-substring-no-properties start end))))
          (and (not (string-empty-p body))
               (not (string-match-p "\\`\\[Awaiting" body))
               (not (string-match-p "\\`\\[Requesting" body))
               (not (string-match-p "\\`\\[Claude unavailable" body))
               (not (string-match-p "\\`\\[Claude request failed" body))
               (not (string-match-p "\\`\\[Translation not available"
                                    body))))))))

(defun tibetan-analysis--delete-claude-l2-section (heading-re buffer)
  "Delete the level-2 heading matching HEADING-RE and its body from BUFFER.
No-op when no matching heading is present.

§5.22 follow-up (2026-05-21):  used by the migration helper to
clear a placeholder-only level-2 slot before re-inserting it
with migrated content from a legacy level-3 location."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (format "^\\*\\* \\(?:%s\\)$" heading-re) nil t)
        (let* ((start (line-beginning-position))
               (end (save-excursion
                      (forward-line 1)
                      (if (re-search-forward
                           "^\\*\\* [^*\n]\\|^\\* " nil t)
                          (line-beginning-position)
                        (point-max)))))
          (delete-region start end))))))

(defun tibetan-analysis--migrate-legacy-claude-headings (buffer)
  "Migrate legacy `*** Claude' / `*** Claude Translation' / `** Claude
Translation' headings in BUFFER.

Segment-layout buffers (with `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
2. Move `*** Claude Translation' (level-3, legacy placement under
   `** Provided Translations') to a new `** Translation'
   (level-2) directly after `** Wylie Transliteration', preserving
   its body.
3. Rename existing level-2 `** Claude Translation' → `** Translation'
   in place (Phase 1.3 of layout-revision §5.18, 2026-05-04 — the
   level-2 heading drops the redundant `Claude' qualifier).

Sentence-layout buffers (no `** Wylie Transliteration'):
1. Rename bare `*** Claude' → `*** Claude Translation'.
2. Reparent any level-3 Claude subsection that escaped
   `* Provided Translations' (e.g. appended after `* Footnotes' by
   a previous regenerate run) back into that section.

Both branches are no-ops when nothing to migrate."
  (with-current-buffer buffer
    (save-excursion
      ;; Step 1 (both layouts): bare `*** Claude' → `*** Claude Translation'
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\*\\* Claude$" nil t)
        (replace-match "*** Claude Translation" t t))
      ;; Step 2 (segment only): promote level-3 Translation → level-2.
      ;;
      ;; §5.22 follow-up (2026-05-21):  guard relaxed — migrate when the
      ;; level-2 slot is ABSENT *or* exists with only a placeholder
      ;; body (`[Awaiting…]' / `[Requesting…]' / etc.).  Prior guard
      ;; checked only heading existence, which made migration skip
      ;; when the new §5.21 scaffold had emitted a fresh placeholder
      ;; — stranding legacy L3 content under Provided Translations.
      (when (tibetan-analysis--claude-segment-layout-p buffer)
        (unless (tibetan-analysis--claude-l2-has-real-content-p
                 "Claude Translation\\|Translation" buffer)
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Translation$" nil t)
            (let* ((heading-start (line-beginning-position))
                   (body-start (progn (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties body-start body-end))))
              (delete-region heading-start body-end)
              ;; Clear any existing L2 placeholder before re-inserting
              ;; so we don't end up with two `** Translation' headings.
              (tibetan-analysis--delete-claude-l2-section
               "Claude Translation\\|Translation" buffer)
              (tibetan-analysis--insert-claude-translation-heading
               (current-buffer) body))))
        ;; Step 3 (segment only, Phase 1.3 of layout-revision §5.18):
        ;; rename existing level-2 `** Claude Translation' → `**
        ;; Translation' in place.  Idempotent — re-running on a
        ;; file already in the new shape is a no-op.
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\* Claude Translation$" nil t)
          (replace-match "** Translation" t t))
        ;; Step 4 (segment only, §5.21 Commit 2/7, 2026-05-20):
        ;; promote level-3 `*** Claude Vocabulary' → level-2 `**
        ;; Claude Vocabulary' (immediately after `** Interlinear
        ;; Gloss'), preserving body.
        ;;
        ;; §5.22 follow-up (2026-05-21):  guard relaxed — migrate when
        ;; the level-2 slot is ABSENT *or* exists with only a
        ;; placeholder body (`[Awaiting Claude…]').  Original guard
        ;; checked only heading existence;  the new §5.21 scaffold
        ;; emits a fresh placeholder at level 2, so on already-
        ;; analysed files the legacy L3 content got stranded under
        ;; Provided Translations.  Discovered on Milarepa seg-061
        ;; / seg-062 — segs had real legacy vocab under PT but
        ;; the L2 slot stayed `[Awaiting…]'.
        (unless (tibetan-analysis--claude-l2-has-real-content-p
                 "Claude Vocabulary" buffer)
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Vocabulary$" nil t)
            (let* ((heading-start (line-beginning-position))
                   (body-start (progn (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (delete-region heading-start body-end)
              ;; Clear any existing L2 placeholder before re-inserting
              ;; so we don't end up with two `** Claude Vocabulary'
              ;; headings (one placeholder, one with the migrated body).
              (tibetan-analysis--delete-claude-l2-section
               "Claude Vocabulary" buffer)
              (tibetan-analysis--insert-claude-vocabulary-heading
               (current-buffer) body))))
        ;; Step 5 (segment only, §5.24, 2026-05-22):  promote
        ;; legacy `*** Claude Context' (L3) → new `** Concept Notes'
        ;; (L2).  Same shape as Step 4 vocabulary promotion:
        ;; preserve body verbatim, clear any L2 placeholder, insert
        ;; at the canonical L2 slot.  Body content is preserved as-is
        ;; (it's the OLD narrative-arc content from the pre-§5.24
        ;; prompt — user can re-fire Claude to get the new concept-
        ;; notes content).
        (unless (tibetan-analysis--claude-l2-has-real-content-p
                 "Concept Notes" buffer)
          (goto-char (point-min))
          (when (re-search-forward "^\\*\\*\\* Claude Context$" nil t)
            (let* ((heading-start (line-beginning-position))
                   (body-start (progn (forward-line 1) (point)))
                   (body-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 3) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (body (string-trim
                          (buffer-substring-no-properties
                           body-start body-end))))
              (delete-region heading-start body-end)
              (tibetan-analysis--delete-claude-l2-section
               "Concept Notes" buffer)
              (tibetan-analysis--insert-concept-notes-heading
               (current-buffer) body))))))
      ;; Step 6 (sentence only, §5.24, 2026-05-22):  rename legacy
      ;; `*** Claude Context' → `*** Concept Notes' at L3 (sentence
      ;; layout keeps L3 placement).  Idempotent.
      (unless (tibetan-analysis--claude-segment-layout-p buffer)
        (goto-char (point-min))
        (while (re-search-forward "^\\*\\*\\* Claude Context$" nil t)
          (replace-match "*** Concept Notes" t t)))
      ;; Step 7 (sentence only): reparent any level-3 Claude subsection
      ;; that previously landed outside `* Provided Translations' back
      ;; into it.  Repairs files written by the pre-fix regenerate run
      ;; that appended orphaned Claude headings at end-of-buffer.
      (unless (tibetan-analysis--claude-segment-layout-p buffer)
        (tibetan-analysis--reparent-orphaned-claude-subsections buffer))))

(defun tibetan-analysis--insert-concept-notes-heading (buffer body)
  "Insert `** Concept Notes' with BODY into BUFFER.

§5.24 (2026-05-22):  the heading is placed AFTER the existing
`** Translation' (Claude) and `** DharmaMitra Translation' if
present, BEFORE `** Grammar'.  Reader-flow:  read Translation
→ glance at Concept Notes for technical terms → read Grammar.

Placement fallbacks (in decreasing preference):
  · After `** DharmaMitra Translation' body.
  · After `** Translation' / `** Claude Translation' body.
  · After `** Claude Vocabulary' body.
  · After `** Wylie Transliteration' body.
  · End of buffer (defensive).

BODY may be empty — the heading is still created with a `[Awaiting
Claude…]' placeholder body."
  (with-current-buffer buffer
    (save-excursion
      (let* ((effective-body
              (if (and body (stringp body) (not (string-empty-p body)))
                  body
                "[Awaiting Claude…]"))
             (insert-pos
              (cond
               ((save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward
                         "^\\*\\* DharmaMitra Translation$" nil t)
                    (forward-line 1)
                    (if (re-search-forward "^\\*\\* " nil t)
                        (line-beginning-position)
                      (point-max)))))
               ((save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward
                         "^\\*\\* \\(?:Translation\\|Claude Translation\\)$"
                         nil t)
                    (forward-line 1)
                    (if (re-search-forward "^\\*\\* " nil t)
                        (line-beginning-position)
                      (point-max)))))
               ((save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward
                         "^\\*\\* Claude Vocabulary$" nil t)
                    (forward-line 1)
                    (if (re-search-forward "^\\*\\* " nil t)
                        (line-beginning-position)
                      (point-max)))))
               ((save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward
                         "^\\*\\* Wylie Transliteration$" nil t)
                    (forward-line 1)
                    (if (re-search-forward "^\\*\\* " nil t)
                        (line-beginning-position)
                      (point-max)))))
               (t (point-max)))))
        (goto-char insert-pos)
        ;; Trim any leading blank lines at insert-pos so we don't
        ;; accumulate excess vertical whitespace.
        (skip-chars-backward " \t\n")
        (insert (format "\n\n** Concept Notes\n%s\n\n" effective-body))))))

(defun tibetan-analysis--insert-claude-vocabulary-heading (buffer body)
  "Insert `** Claude Vocabulary' with BODY into BUFFER.

Placement rule (§5.21 Commit 2/7, 2026-05-20):  prefer the slot
right after `** Interlinear Gloss' (the canonical scaffold
position — word-for-word trot → per-word annotations → fluent
translations).  Fallbacks in decreasing preference:  after
`** Wylie Transliteration', after `** Translation' / `** Claude
Translation', after the first `* ' top-level heading, end of
buffer.  BODY may be empty — the heading is still created with
two trailing newlines."
  (with-current-buffer buffer
    (save-excursion
      (let ((insert-pos
             (cond
              ;; Preferred:  after `** Interlinear Gloss' (and its
              ;; body) — matches the scaffold's renderer order.
              ((save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward "^\\*\\* Interlinear Gloss$" nil t)
                   (forward-line 1)
                   (if (re-search-forward "^\\*\\* " nil t)
                       (line-beginning-position)
                     (point-max)))))
              ;; Fallback A:  after `** Wylie Transliteration' (and
              ;; body) — segment-layout always has Wylie even when
              ;; the Interlinear marker hasn't fired yet.
              ((save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
                   (forward-line 1)
                   (if (re-search-forward "^\\*\\* " nil t)
                       (line-beginning-position)
                     (point-max)))))
              ;; Fallback B:  after `** Translation' / `** Claude
              ;; Translation' (legacy buffers without Wylie).
              ((save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward
                        "^\\*\\* \\(?:Translation\\|Claude Translation\\)$"
                        nil t)
                   (forward-line 1)
                   (if (re-search-forward "^\\*\\* " nil t)
                       (line-beginning-position)
                     (point-max)))))
              ;; Last resort:  after first `* ' heading or end of buffer.
              ((save-excursion
                 (goto-char (point-min))
                 (when (re-search-forward "^\\* " nil t)
                   (forward-line 1)
                   (point))))
              (t (point-max)))))
        (goto-char insert-pos)
        (insert "** Claude Vocabulary\n")
        (when (and body (not (string-empty-p body)))
          (insert body)
          (unless (string-suffix-p "\n" body) (insert "\n")))
        (insert "\n")))))


(defun tibetan-analysis--insert-claude-translation-heading (buffer body)
  "Insert `** Translation' with BODY into BUFFER at the top.
Placement rule: right after `** Wylie Transliteration' and its body
if that heading exists; otherwise right after the first `* ' top-level
heading; otherwise at point-max.  BODY may be empty — the heading is
still created with two trailing newlines.

Phase 1.3 of layout-revision §5.18 (2026-05-04):  the heading is
now `** Translation' (was `** Claude Translation'); see
`tibetan-analysis--claude-section-order' for the rename rationale."
  (with-current-buffer buffer
    (save-excursion
      (let ((content (if (and body (not (string-empty-p (string-trim body))))
                         (format "** Translation\n%s\n\n"
                                 (string-trim body))
                       "** Translation\n\n\n")))
        (goto-char (point-min))
        (cond
         ;; Prefer: end of the ** Wylie Transliteration section
         ((re-search-forward "^\\*\\* Wylie Transliteration$" nil t)
          (forward-line 1)
          (if (re-search-forward
               (tibetan-analysis--claude-stop-re 2) nil t)
              (beginning-of-line)
            (goto-char (point-max)))
          (insert content))
         ;; Phase 2.1 of layout-revision §5.18 (2026-05-04):  with the
         ;; new section ordering (My Notes first, Tibetan Analysis
         ;; later), the OLD fallback "first `* ' heading" would
         ;; mis-place the Translation under My Notes.  New fallback:
         ;; insert into `* Tibetan Analysis' (or legacy `* Auto-
         ;; Analysis') subtree, after its property drawer.
         ((re-search-forward
           "^\\* \\(?:Tibetan Analysis\\|Auto-Analysis\\)$" nil t)
          (forward-line 1)
          ;; Skip property drawer if present.
          (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
            (when (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
              (forward-line 1)))
          (insert content))
         ;; Fallback of last resort: after the first top-level heading's
         ;; opening line.
         ((progn
            (goto-char (point-min))
            (re-search-forward "^\\* " nil t))
          (forward-line 1)
          (insert content))
         (t
          (goto-char (point-max))
          (insert content)))))))

;; Phase 1 of two-language-parallel-analysis (2026-04-30):
;; The three scaffolders for `** Claude Translation (Sanskrit)' /
;; `(Combined)' / `** Claude Divergence' are retired.  Sanskrit
;; output now lives under `* Sanskrit Analysis' (Phase 2 module);
;; Combined + Divergence under `* Combined Analysis' (Phase 4).

(defun tibetan-analysis--migrate-claude-grammar-to-u4 ()
  "Relocate legacy Claude Grammar headings to the U4 target slot.
Three layouts exist in the wild:
  A (oldest): `*** Claude Grammar' at level 3 inside
      `** Provided Translations' (pre-Pass-6b).
  B: `** Claude Grammar' at level 2 (Pass 6b, 2026-04-22).
  C (U4 target): `*** Claude Grammar' at level 3 under
      `** Grammar' (2026-04-24).

Algorithm:
  1. Look for Layout B first (level-2).  If found, capture its body
     and delete the heading.
  2. Look for Layout A (level-3 inside Provided Translations).  Only
     treat as legacy if NO Layout-C heading is already in place under
     `** Grammar' (otherwise the Provided-Translations occurrence
     must already be a duplicate that `--extract-claude-grammar'
     missed — rare).  If found, capture body and delete.
  3. Ensure the U4 target `*** Claude Grammar' heading exists via
     `--place-claude-grammar-heading'.
  4. Drop the captured legacy body under the U4 heading, replacing
     any placeholder whitespace there.

Idempotent.  Operates on the CURRENT buffer — save-excursion is the
caller's responsibility."
  (let ((salvaged nil))
    ;; Layout B — `** Claude Grammar' at level 2.
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\*\\* Claude Grammar$" nil t)
        (let* ((heading-start (line-beginning-position))
               (body-start (progn (forward-line 1) (point)))
               (body-end
                (save-excursion
                  (if (re-search-forward
                       (tibetan-analysis--claude-stop-re 2) nil t)
                      (line-beginning-position)
                    (point-max))))
               (body (string-trim
                      (buffer-substring-no-properties
                       body-start body-end))))
          (unless (string-empty-p body) (setq salvaged body))
          (delete-region heading-start body-end))))
    ;; Layout A — `*** Claude Grammar' inside `** Provided Translations'.
    ;; Skip if we already captured from Layout B (rare double-legacy).
    (unless salvaged
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\*\\* Provided Translations$" nil t)
          (let ((pt-end
                 (save-excursion
                   (if (re-search-forward
                        (tibetan-analysis--claude-stop-re 2) nil t)
                       (line-beginning-position)
                     (point-max)))))
            (when (re-search-forward
                   "^\\*\\*\\* Claude Grammar$" pt-end t)
              (let* ((heading-start (line-beginning-position))
                     (body-start (progn (forward-line 1) (point)))
                     (body-end
                      (save-excursion
                        (if (re-search-forward
                             (tibetan-analysis--claude-stop-re 3)
                             pt-end t)
                            (line-beginning-position)
                          pt-end)))
                     (body (string-trim
                            (buffer-substring-no-properties
                             body-start body-end))))
                (unless (string-empty-p body) (setq salvaged body))
                (delete-region heading-start body-end)))))))
    ;; Step 3: ensure U4 target heading exists.
    (unless (save-excursion
              (goto-char (point-min))
              (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t))
      (tibetan-analysis--place-claude-grammar-heading))
    ;; Step 4: drop salvaged body under U4 heading (replacing
    ;; placeholder whitespace).
    (when salvaged
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\*\\*\\* Claude Grammar$" nil t)
          (forward-line 1)
          (let ((after-heading (point)))
            (skip-chars-forward " \t\n")
            (delete-region after-heading (point)))
          (insert salvaged "\n\n"))))))

(defun tibetan-analysis--place-claude-grammar-heading ()
  "Insert `*** Claude Grammar' heading under `** Grammar' (U4, 2026-04-24).
Preferred slot: between `*** Particle Map' and `*** Particles in
This Segment', per the canonical U4 layout.  Fallbacks: after
`*** Particle Map' alone, or at end of `** Grammar'.  When
`** Grammar' itself is missing (legacy / pre-Pass-6b buffer, or
test fixture that never ran through `render-grammar-section'), a
minimal `** Grammar' heading is created first — Claude Grammar
always ends up nested so the workflow invariant holds.

Placement site: after `** Claude Translation' when that heading is
present (keeps Grammar in the priority-order neighbourhood);
otherwise after `** Wylie Transliteration'; otherwise at point-min.

Idempotent: caller must check the heading isn't already present
before invoking."
  (goto-char (point-min))
  ;; Step 1: ensure `** Grammar' exists.  Create if missing so the
  ;; nested-Claude-Grammar invariant always holds.
  (unless (save-excursion
            (goto-char (point-min))
            (re-search-forward "^\\*\\* Grammar$" nil t))
    (goto-char (point-min))
    (cond
     ;; After `** Translation' (priority slot 4; Grammar is slot 5).
     ;; Phase 1.3 of layout-revision §5.18 (2026-05-04) renamed
     ;; `Claude Translation' → `Translation' at level 2; we still
     ;; tolerate the legacy name as a fallback.
     ((re-search-forward
       "^\\*\\* \\(?:Translation\\|Claude Translation\\)$" nil t)
      (forward-line 1)
      (if (re-search-forward
           (tibetan-analysis--claude-stop-re 2) nil t)
          (beginning-of-line)
        (goto-char (point-max)))
      (insert "** Grammar\n\n"))
     ;; After Wylie (always present in segment layout).
     ((progn
        (goto-char (point-min))
        (re-search-forward "^\\*\\* Wylie Transliteration$" nil t))
      (forward-line 1)
      (if (re-search-forward
           (tibetan-analysis--claude-stop-re 2) nil t)
          (beginning-of-line)
        (goto-char (point-max)))
      (insert "** Grammar\n\n"))
     ;; Bare buffer — append.
     (t
      (goto-char (point-max))
      (insert "\n** Grammar\n\n"))))
  ;; Step 2: place `*** Claude Grammar' inside `** Grammar'.
  (goto-char (point-min))
  (re-search-forward "^\\*\\* Grammar$" nil t)
  (let ((grammar-end
         (save-excursion
           (if (re-search-forward
                (tibetan-analysis--claude-stop-re 2) nil t)
               (line-beginning-position)
             (point-max)))))
    (cond
     ;; Preferred (§5.21 Commit 3/7):  just AFTER `*** Particles'
     ;; (the merged Particle Map + Particles in This Segment).
     ;; Reader flow:  particle markup + bullets → prose reading.
     ((save-excursion
        (re-search-forward "^\\*\\*\\* Particles$" grammar-end t))
      (re-search-forward "^\\*\\*\\* Particles$" grammar-end t)
      (forward-line 1)
      (if (re-search-forward
           (tibetan-analysis--claude-stop-re 3) grammar-end t)
          (beginning-of-line)
        (goto-char grammar-end))
      (insert "*** Claude Grammar\n\n\n"))
     ;; Legacy fallback A:  just before `*** Particles in This
     ;; Segment' (pre-§5.21 layout).
     ((save-excursion
        (re-search-forward "^\\*\\*\\* Particles in This Segment$"
                           grammar-end t))
      (re-search-forward "^\\*\\*\\* Particles in This Segment$"
                         grammar-end t)
      (beginning-of-line)
      (insert "*** Claude Grammar\n\n\n"))
     ;; Legacy fallback B:  after Particle Map body (oldest layout).
     ((save-excursion
        (re-search-forward "^\\*\\*\\* Particle Map$" grammar-end t))
      (re-search-forward "^\\*\\*\\* Particle Map$" grammar-end t)
      (forward-line 1)
      (if (re-search-forward
           (tibetan-analysis--claude-stop-re 3) grammar-end t)
          (beginning-of-line)
        (goto-char grammar-end))
      (insert "*** Claude Grammar\n\n\n"))
     ;; Last resort: at end of Grammar body (before next level-2).
     (t
      (goto-char grammar-end)
      (insert "*** Claude Grammar\n\n\n")))))

(defun tibetan-analysis--ensure-claude-headings (buffer)
  "Ensure the Claude Translation / Vocabulary / Grammar headings exist in BUFFER.

Segment-layout target (detected via `** Wylie Transliteration'):
  - `** Claude Translation'   at org level 2, right after Wylie.
  - `*** Claude Vocabulary'   at org level 3, inside
    `** Provided Translations' (after `*** DharmaMitra' if present).
  - `*** Claude Grammar'      at org level 3, nested UNDER
    `** Grammar', between `*** Particle Map' and `*** Particles in
    This Segment' (U4, 2026-04-24).  The reader flow inside Grammar
    is visual-map → prose-reading → per-particle Portfolio refs.
    Legacy files carrying `** Claude Grammar' at level 2 are
    migrated here — see the segment-layout migration block below.

Sentence-layout target (no `** Wylie Transliteration'):
  - `*** Claude Translation' at org level 3 (siblings under whatever
    parent the sentence scaffold provides).
  - `*** Claude Vocabulary'  at org level 3.
  - `*** Claude Grammar'     at org level 3.
  - `*** Claude Context'     at org level 3 — preserved for sentence
    files which still use the three/four-section layout.

Performs legacy-layout migration first (via
`tibetan-analysis--migrate-legacy-claude-headings'), then creates
whichever target heading is still missing.  Idempotent."
  (with-current-buffer buffer
    ;; Step 1 — migrate legacy layouts into the target shape.
    (tibetan-analysis--migrate-legacy-claude-headings buffer)
    (save-excursion
      (cond
       ;; -------------------------------------------------------------
       ;; SEGMENT LAYOUT: Translation at level 2, Vocab/Grammar at 3.
       ;; -------------------------------------------------------------
       ((tibetan-analysis--claude-segment-layout-p buffer)
        ;; Ensure `** Translation' exists.  After the migration step
        ;; in `--migrate-legacy-claude-headings' (called above) the
        ;; level-2 heading is always `** Translation'; we still
        ;; tolerate the legacy name in the existence check as belt-
        ;; and-braces.  Phase 1.3 of layout-revision §5.18.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward
                   "^\\*\\* \\(?:Translation\\|Claude Translation\\)$"
                   nil t))
          (tibetan-analysis--insert-claude-translation-heading
           buffer nil))
        ;; Ensure `** Claude Vocabulary' exists at LEVEL 2 (§5.21
        ;; Commit 2/7, 2026-05-20).  Placement:  after `**
        ;; Interlinear Gloss' if present;  else after `** Translation'
        ;; / `** Claude Translation';  else after first `* ' heading.
        ;; Idempotent — skipped when level-2 heading already exists.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Claude Vocabulary$" nil t))
          (tibetan-analysis--insert-claude-vocabulary-heading buffer nil))
        ;; U4 (2026-04-24): ensure `*** Claude Grammar' exists at level
        ;; 3 under `** Grammar', between Particle Map (visual) and
        ;; Particles in This Segment (detailed), following the reader
        ;; flow map → prose → particle-refs.
        ;;
        ;; Migration handles two legacy layouts:
        ;;   A (oldest, pre-Pass-6b): `*** Claude Grammar' at level 3
        ;;     inside `** Provided Translations'.  Already promoted
        ;;     to Layout B by `--extract-claude-grammar' during the
        ;;     reorder step; handled here only as a defensive fallback.
        ;;   B (Pass 6b): `** Claude Grammar' at level 2.
        ;;   C (U4 target): `*** Claude Grammar' at level 3 under
        ;;     `** Grammar'.
        ;;
        ;; Algorithm: find the one Claude Grammar heading NOT already
        ;; in U4 position (Layout B or orphaned Layout A), lift its
        ;; body, delete the legacy heading, ensure the U4 target
        ;; exists, drop the body under it.
        (tibetan-analysis--migrate-claude-grammar-to-u4)
        ;; §5.24 (2026-05-22):  ensure `** Concept Notes' exists at
        ;; level 2.  Placement after DharmaMitra Translation / Claude
        ;; Translation / Claude Vocabulary — see
        ;; `--insert-concept-notes-heading' for the full preference
        ;; ladder.  Idempotent — skipped when L2 heading exists.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\* Concept Notes$" nil t))
          (tibetan-analysis--insert-concept-notes-heading buffer nil))
        ;; Ensure `*** Claude Particles' exists inside Provided
        ;; Translations (Pass 6c).  Place after `*** Claude Vocabulary'
        ;; if present; otherwise at the end of Provided Translations.
        (unless (save-excursion
                  (goto-char (point-min))
                  (re-search-forward "^\\*\\*\\* Claude Particles$" nil t))
          (goto-char (point-min))
          (cond
           ((re-search-forward "^\\*\\* Provided Translations$" nil t)
            (let* ((section-end
                    (save-excursion
                      (if (re-search-forward
                           (tibetan-analysis--claude-stop-re 2) nil t)
                          (line-beginning-position)
                        (point-max))))
                   (vocab-end
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Claude Vocabulary$" section-end t)
                        (forward-line 1)
                        (if (re-search-forward
                             (tibetan-analysis--claude-stop-re 3)
                             section-end t)
                            (line-beginning-position)
                          section-end))))
                   (ref-pos
                    (save-excursion
                      (when (re-search-forward
                             "^\\*\\*\\* Reference Translations$"
                             section-end t)
                        (line-beginning-position)))))
              (goto-char (or vocab-end ref-pos section-end))
              (insert "*** Claude Particles\n\n\n")))
           (t
            (goto-char (point-max))
            (insert "\n*** Claude Particles\n\n")))))
       ;; -------------------------------------------------------------
       ;; SENTENCE LAYOUT: all four Claude headings at level 3 inside
       ;; the TOP-LEVEL `* Provided Translations' section.
       ;;
       ;; Sentence files emit `* Provided Translations' at org level 1
       ;; (as a peer of `* Tibetan Text' / `* Auto-Analysis'), with
       ;; Roehrich / Class / Claude subsections at level 3 inside.
       ;; The previous dolist-with-chained-prev algorithm worked on a
       ;; fresh file (all four Claude headings missing) but collapsed
       ;; when regenerate had just deleted and re-inserted the
       ;; Auto-Analysis block: `--read-claude-sections' had grabbed
       ;; Translation and Grammar bodies from their (bug-inserted)
       ;; level-2 positions, the delete removed those headings, and
       ;; the missing-heading restore then appended them at end of
       ;; file (after `* Footnotes') instead of slotting into the
       ;; actual Provided Translations section.
       ;;
       ;; This version anchors insertion on `* Provided Translations'
       ;; directly.  Each missing Claude heading is placed at the end
       ;; of that section (just before the next `* ' top-level
       ;; heading or end-of-buffer), so the order becomes Roehrich,
       ;; Class Translation, <existing Claude siblings>, <newly
       ;; inserted>.  Fallback (truly no Provided Translations block
       ;; at all) still appends at end of buffer so the headings
       ;; exist SOMEWHERE for the replace-body path to find.
       (t
        ;; §5.24 (2026-05-22):  `Claude Context' → `Concept Notes'.
        ;; The migration helper (Step 6) already renames any legacy
        ;; `*** Claude Context' in this buffer to `*** Concept Notes',
        ;; so by the time we ensure-headings the new heading is what
        ;; we should look for / create.
        (dolist (heading '("Claude Translation" "Claude Vocabulary"
                           "Claude Grammar" "Concept Notes"))
          (unless (save-excursion
                    (goto-char (point-min))
                    (re-search-forward
                     (format "^\\*\\*\\* %s$" (regexp-quote heading))
                     nil t))
            (goto-char (point-min))
            (cond
             ((re-search-forward "^\\* Provided Translations$" nil t)
              (let ((section-end
                     (save-excursion
                       (if (re-search-forward "^\\* " nil t)
                           (line-beginning-position)
                         (point-max)))))
                (goto-char section-end)
                (skip-chars-backward " \t\n")
                (insert (format "\n\n*** %s\n\n" heading))))
             (t
              (goto-char (point-max))
              (insert (format "\n*** %s\n\n" heading)))))))))))

(defun tibetan-analysis--claude-body-md-h3-to-org (body parent-level)
  "Convert markdown `### foo' lines in BODY to org headings.

Each line that starts with `### ' (three hashes followed by a
space, line-anchored) is rewritten to a real org heading at
PARENT-LEVEL + 1 — one level deeper than the section the body
belongs to, so it nests cleanly underneath.

  Parent at level 2 (`** Claude Translation', segment layout)
    `### Tibetan Divergence' → `*** Tibetan Divergence'
  Parent at level 3 (`*** Claude Translation', sentence layout)
    `### Tibetan Divergence' → `**** Tibetan Divergence'

Mid-line `###' (e.g. `section ### 4.5 of the text') is preserved
as plain text — only line-anchored matches are converted.

Pure function — used by `--replace-claude-section-body' to render
optional Claude-emitted sub-headings (currently
`### Tibetan Divergence' from sanskrit-parallel mode, Phase 3 of
sanskrit-parallel-workflow, 2026-04-27) as foldable, navigable
org headings rather than flat markdown text in the analysis file.

If BODY contains no `### ' lines the input is returned unchanged,
so non-parallel Translation bodies (today's overwhelming majority)
are byte-identical pre- and post-Phase 4."
  (let ((stars (make-string (1+ parent-level) ?*)))
    (replace-regexp-in-string "^### " (concat stars " ") body)))

(defun tibetan-analysis--replace-claude-section-body
    (buffer heading body &optional level)
  "Replace the body under `HEADING' at org LEVEL in BUFFER with BODY.
LEVEL defaults to 3 for backwards compatibility.  Leaves the heading
itself in place; body is trimmed + terminated with one trailing blank
line.

Phase 4 of sanskrit-parallel-workflow (2026-04-27): before insert,
the body passes through `tibetan-analysis--claude-body-md-h3-to-org'
which rewrites any line-anchored `### foo' markdown sub-heading to
a real org heading at LEVEL + 1.  This is how Claude's optional
`### Tibetan Divergence' note (parallel-Sanskrit mode) becomes a
nested org heading rather than flat markdown text in the analysis
file.  Non-divergence bodies (no `### ' lines) are unchanged."
  (let ((level (or level 3)))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward
               (tibetan-analysis--claude-heading-re heading level)
               nil t)
          (forward-line 1)
          (let ((start (point))
                (end (if (re-search-forward
                          (tibetan-analysis--claude-stop-re level) nil t)
                         (line-beginning-position)
                       (point-max))))
            (delete-region start end)
            (goto-char start)
            ;; C1b (Fable-5 audit, 2026-06-04): Claude bodies are LLM
            ;; text — neutralise line-leading `*' runs (space-prefix,
            ;; mirroring the §5.28 DM sanitizer) BEFORE the md-h3
            ;; transform, so genuine `### ' sub-headings still become
            ;; org headings while a stray `* line' cannot restructure
            ;; the file or truncate later preserve reads.
            (insert (format "%s\n\n"
                            (string-trim
                             (tibetan-analysis--claude-body-md-h3-to-org
                              (replace-regexp-in-string
                               "^\\(\\*+\\)" " \\1" body)
                              level))))))))))

(defun tibetan-analysis--claude-effective-section-order (buffer)
  "Return the layout-appropriate Claude section-order for BUFFER.

Segment layout (per-segment analysis files):
  `** Claude Translation' and `** Claude Grammar' both at level 2
  (the workshop-agreed priority slots), plus `*** Claude
  Vocabulary' at level 3 inside `** Provided Translations'.
  Context is dropped — the segment workflow is three-section only.

Sentence / legacy layout (sentence analysis files, or any buffer
without the segment-layout marker):
  Translation / Grammar / Context all at level 3 — preserves the
  existing sentence-level three-section workflow unchanged.

Callers that write Claude output (insert, restore) use this list so
a single buffer's layout drives heading levels consistently."
  (if (tibetan-analysis--claude-segment-layout-p buffer)
      tibetan-analysis--claude-section-order
    '((:translation "Claude Translation" 3)
      (:vocabulary  "Claude Vocabulary"  3)
      (:grammar     "Claude Grammar"     3)
      (:concepts    "Concept Notes"      3))))

(defcustom tibetan-analysis-auto-regen-on-claude-arrival t
  "When non-nil, the Grammar section is re-rendered after Claude
populates `*** Claude Particles' so the Portfolio snippets appear
inline without requiring a manual `C-c u R'.

Pass 6c (2026-04-22) introduced `## Particles' tuples that let the
Grammar section's `*** Particles in This Segment' attach per-
occurrence Bialek Portfolio function snippets.  Those tuples
arrive in Claude's response async; without this auto-regen the
student has to re-run reanalyse by hand to see the enriched
Grammar section.

Set to nil to keep the Pass 6b compact Grammar shape and do the
enriched re-render only on explicit reanalyse."
  :type 'boolean
  :group 'tibetan-cat)

(defun tibetan-analysis--insert-claude-sections (response analysis-file)
  "Parse RESPONSE and write its sections into ANALYSIS-FILE.
RESPONSE is the raw markdown returned by Claude; it is split by
`tibetan-analysis--parse-claude-sections'.  Each section named in
the buffer's effective section-order (see
`tibetan-analysis--claude-effective-section-order') that the parser
filled in is written under its corresponding org heading at the
configured level.  Legacy `*** Claude' and `*** Claude Translation'
placements are migrated to the current two-section segment layout on
first write; sentence files keep the legacy three-section layout.

When Claude's response includes a `## Particles' block AND
`tibetan-analysis-auto-regen-on-claude-arrival' is non-nil, the
Grammar section is re-rendered from scratch so the per-occurrence
Bialek Portfolio snippets (§1.5.1 Place, §2.11.1 Sequential, ...)
land inline under each particle without requiring a manual
reanalyse."
  (when (and response (file-exists-p analysis-file))
    (let* ((sections (tibetan-analysis--parse-claude-sections response))
           (buf (or (find-buffer-visiting analysis-file)
                    (find-file-noselect analysis-file))))
      (with-current-buffer buf
        ;; 2026-05-21:  suppress before/after-change-functions during
        ;; the regex-driven write loop.  Org-mode's incremental
        ;; fontification (and other after-change hooks) can clobber
        ;; match data set by `re-search-forward' before `replace-match'
        ;; runs — signalling `Match data clobbered by buffer
        ;; modification hooks' and dropping the Claude response on the
        ;; floor.  Discovered when a batch run on Milarepa segs 62-72
        ;; logged `Claude insert failed: Match data clobbered' on every
        ;; segment despite the API returning content cleanly.
        ;; §5.25 (2026-05-24):  post-process the Concept Notes body
        ;; to append `[[id:ZID][zettel ↗]]' links to bolded Tibetan
        ;; terms that have a thesaurus zettel — safety net for
        ;; zettels Claude missed in its in-prompt citation.  No-op
        ;; when no Concept Notes body, no thesaurus module loaded,
        ;; or no zettels match.
        (when (plist-get sections :concepts)
          (setq sections
                (plist-put sections :concepts
                           (tibetan-analysis--cross-link-zettels-in-body
                            (plist-get sections :concepts)))))
        (let ((inhibit-modification-hooks t))
          (tibetan-analysis--ensure-claude-headings buf)
          (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry))
                  (level (nth 2 entry)))
              (when (plist-get sections key)
                (tibetan-analysis--replace-claude-section-body
                 buf heading (plist-get sections key) level)))))
        ;; `--merge-claude-vocabulary' call retired 2026-05-20
        ;; (§5.21 Commit 2/7).  The merge targeted `** Word /
        ;; Particle List' which §5.10 retired — net no-op since
        ;; April.  Claude Vocabulary now lives at its own level-2
        ;; `** Claude Vocabulary' slot right after Interlinear.
        ;; Phase 4 of zettel-in-translation-workflow (2026-04-24):
        ;; cache each Claude Vocabulary line into the matching zettel's
        ;; `* Claude Explanation' section.  Only fills empty sections;
        ;; existing populated caches are left alone.  Stamps each
        ;; updated zettel with `:claude-cached:' / `:claude-model:' /
        ;; `:prompt-version:' for Phase 5's freshness check.  No-op
        ;; when the zettel module isn't loaded OR no vocab parsed.
        (when (and (plist-get sections :vocabulary)
                   (fboundp 'tibetan-zettel--cache-claude-vocabulary)
                   (fboundp 'tibetan-analysis--parse-claude-vocabulary))
          (let ((vocab (ignore-errors
                         (tibetan-analysis--parse-claude-vocabulary
                          (plist-get sections :vocabulary)))))
            (when vocab
              (let ((updated (ignore-errors
                               (tibetan-zettel--cache-claude-vocabulary
                                vocab))))
                (when (and updated (> updated 0))
                  (message "tibetan-zettel: cached Claude explanations into %d zettel(s)"
                           updated))))))
        (save-buffer))
      (message "Claude sections inserted into %s"
               (file-name-nondirectory analysis-file))
      ;; Pass 6c auto-regen: when Particles tuples just arrived, run a
      ;; non-Claude-refiring reanalyse so the Grammar section picks
      ;; them up via the dynamic `claude-particles-for-render' var
      ;; and emits `§ X.Y Portfolio-title' + snippet per occurrence.
      ;; Guarded by a customvar so power users can opt out.
      (when (and tibetan-analysis-auto-regen-on-claude-arrival
                 (plist-get sections :particles)
                 (fboundp 'tibetan-analysis-reanalyze-file))
        (condition-case err
            (tibetan-analysis-reanalyze-file analysis-file
                                             :re-request-claude nil)
          (error
           (message "Claude auto-regen skipped for %s: %s"
                    (file-name-nondirectory analysis-file)
                    (error-message-string err))))))))

;; ---------------------------------------------------------------------------
;; Claude Vocabulary → Word / Particle List merge
;; ---------------------------------------------------------------------------

(defun tibetan-analysis--parse-claude-vocabulary (vocab-text)
  "Parse VOCAB-TEXT (the `## Vocabulary' body) into an alist.
Each entry is (WYLIE-KEY . FULL-LINE) where WYLIE-KEY is the
lowercase, trimmed first field (before the first comma) and
FULL-LINE is the original line.  Blank lines and lines starting
with `---' are skipped."
  (let ((result '()))
    (when (and vocab-text (stringp vocab-text)
               (not (string-empty-p vocab-text)))
      (dolist (line (split-string vocab-text "\n" t))
        (let ((trimmed (string-trim line)))
          (unless (or (string-empty-p trimmed)
                      (string-prefix-p "---" trimmed))
            (when (string-match "\\`\\([^,]+\\)," trimmed)
              (let ((key (downcase (string-trim (match-string 1 trimmed)))))
                (push (cons key trimmed) result)))))))
    (nreverse result)))

;; Backwards-compatible alias — older callers still refer to the
;; one-section name `--insert-claude-translation'.  Restored here
;; (was previously near `--merge-claude-vocabulary' which was
;; retired in §5.21 Commit 2/7, 2026-05-20).
(defalias 'tibetan-analysis--insert-claude-translation
  'tibetan-analysis--insert-claude-sections)

(defun tibetan-analysis--read-claude-section-body (filepath heading &optional level)
  "Return the non-placeholder body under `HEADING' in FILEPATH, or nil.
LEVEL is the org heading level to look for (defaults to 3 for
backwards compatibility).  When nil is passed explicitly as LEVEL,
the reader tries level 2 first and falls back to level 3 — this is
useful during the Claude Translation migration, when an old file may
still carry a level-3 heading.  Skips placeholder `[Requesting …]'
and known error markers so we don't re-persist dead content."
  (when (file-exists-p filepath)
    (let ((levels (cond
                   ((null level) '(2 3))
                   ((listp level) level)
                   (t (list level)))))
      (cl-loop for lvl in levels
               for body = (with-temp-buffer
                            (insert-file-contents filepath)
                            (goto-char (point-min))
                            (when (re-search-forward
                                   (tibetan-analysis--claude-heading-re
                                    heading lvl)
                                   nil t)
                              (forward-line 1)
                              (let* ((start (point))
                                     (end (save-excursion
                                            (if (re-search-forward
                                                 (tibetan-analysis--claude-stop-re
                                                  lvl)
                                                 nil t)
                                                (line-beginning-position)
                                              (point-max))))
                                     (b (string-trim
                                         (buffer-substring-no-properties
                                          start end))))
                                (unless
                                    (or (string-empty-p b)
                                        (string-match-p "\\`\\[Awaiting" b)
                                        (string-match-p "\\`\\[Requesting" b)
                                        (string-match-p "\\`\\[Claude unavailable" b)
                                        (string-match-p "\\`\\[Claude request failed" b)
                                        (string-match-p "\\`\\[Translation not available" b))
                                  b))))
               when body return body))))

(defun tibetan-analysis--read-claude-sections (filepath)
  "Return preserved Claude content in FILEPATH as a plist.
Keys: `:translation', `:vocabulary', `:grammar', `:particles',
`:concepts'.  Each value is a non-empty string or nil.  Reads
from the current layout (Translation, Vocabulary, and Concept
Notes at level 2;  Grammar / Particles at level 3) and falls
back to the legacy level-3 placements so old analysis files do
not lose their work on reanalysis.

§5.24 (2026-05-22):  the `:context' slot is renamed to
`:concepts' and its heading promoted from level-3 `*** Claude
Context' to level-2 `** Concept Notes' (sentence files keep
level 3 — see `--claude-effective-section-order' else branch).
Reader does dual-name match so existing `*** Claude Context'
bodies migrate naturally on first regen.

Phase 1 of two-language-parallel-analysis (2026-04-30):  the
Phase B–D `:translation-sanskrit' / `:translation-combined' /
`:divergence' slots are retired.  Sanskrit + Combined +
Divergence content lives under separate top-level sections (`*
Sanskrit Analysis' / `* Combined Analysis') with their own
read / restore helpers in
`persist/tibetan-analysis-sanskrit.el' /
`persist/tibetan-analysis-combined.el'."
  (let ((translation
         (or
          ;; Current layout (Phase 1.3 of layout-revision §5.18,
          ;; 2026-05-04): level-2 `** Translation' under
          ;; `* Tibetan Analysis'.
          (tibetan-analysis--read-claude-section-body
           filepath "Translation" 2)
          ;; Legacy level-2 (pre-rename) — old segment files.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 2)
          ;; Legacy level-3 placement (sentence layout, or older
          ;; segment files before the 2026-04-16 promotion).
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Translation" 3)
          ;; Pre-three-section legacy heading.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude" 3)))
        (vocabulary
         (or
          ;; Current layout (§5.21 Commit 2/7, 2026-05-20): level 2,
          ;; sitting between `** Interlinear Gloss' and `**
          ;; Translation'.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Vocabulary" 2)
          ;; Legacy level-3 placement inside Provided Translations
          ;; (sentence files + pre-§5.21 segment files).
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Vocabulary" 3)))
        (grammar
         (or
          ;; Current layout: level 2 (promoted out of Provided
          ;; Translations so it can take the priority slot).
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Grammar" 2)
          ;; Legacy level-3 placement inside Provided Translations.
          (tibetan-analysis--read-claude-section-body
           filepath "Claude Grammar" 3)))
        (particles (tibetan-analysis--read-claude-section-body
                    filepath "Claude Particles" 3))
        ;; §5.24 (2026-05-22):  the canonical slot is `** Concept
        ;; Notes' at level 2 for segment layout, `*** Concept Notes'
        ;; at level 3 for sentence layout.  Reader checks both, plus
        ;; legacy `*** Claude Context' at L3 for round-trip migration.
        ;; First match wins.
        (concepts (or (tibetan-analysis--read-claude-section-body
                       filepath "Concept Notes" 2)
                      (tibetan-analysis--read-claude-section-body
                       filepath "Concept Notes" 3)
                      (tibetan-analysis--read-claude-section-body
                       filepath "Claude Context" 3))))
    (list :translation translation
          :vocabulary  vocabulary
          :grammar     grammar
          :particles   particles
          :concepts    concepts)))

(defun tibetan-analysis--parse-claude-particles (body)
  "Parse a `*** Claude Particles' BODY into a list of particle tuples.
Each line is `word, particle, portfolio-sub-id, label'; returns a
list of plists `(:word W :particle P :sub-id ID :label L)'.
Lines that don't match the 4-field shape are silently skipped
(Claude may emit commentary or sentinel `[none]' lines on short
passages — those shouldn't crash the caller)."
  (when (and body (stringp body) (not (string-empty-p body)))
    (let (result)
      (dolist (line (split-string body "\n" t))
        (let ((fields (mapcar #'string-trim (split-string line "," t))))
          (when (= (length fields) 4)
            (push (list :word     (nth 0 fields)
                        :particle (nth 1 fields)
                        :sub-id   (nth 2 fields)
                        :label    (nth 3 fields))
                  result))))
      (nreverse result))))

;; Backwards-compatible single-section reader — returns just the
;; translation body so legacy callers keep working.
(defun tibetan-analysis--read-claude-translation (filepath)
  "Return the preserved Claude translation in FILEPATH, or nil.
Legacy wrapper around `tibetan-analysis--read-claude-sections' that
returns only the `:translation' slot for callers that have not been
migrated yet."
  (plist-get (tibetan-analysis--read-claude-sections filepath) :translation))

(defun tibetan-analysis--claude-needs-request-p (filepath)
  "Return non-nil when FILEPATH lacks populated Claude content.

\"Populated\" = at least Translation OR Vocabulary slot has a
non-placeholder body (the slots `tibetan-analysis--read-claude-
sections' reads and filters for placeholders).  When BOTH are nil
\(missing or `[Awaiting…]' / `[Requesting…]' placeholders), the
file needs a Claude request.

§5.22 follow-up (2026-05-21):  used by the `:missing-only'
semantic of `re-request-claude' in `tibetan-analysis-reanalyze-
file' / `tibetan-sentence-reanalyze-file' to skip the API call
on files already populated."
  (when (and filepath (file-exists-p filepath))
    (let ((sections (tibetan-analysis--read-claude-sections filepath)))
      (and (null (plist-get sections :translation))
           (null (plist-get sections :vocabulary))))))

(defun tibetan-analysis--should-fire-claude-p (re-request-claude filepath)
  "Decide whether to fire a Claude request for FILEPATH.

RE-REQUEST-CLAUDE controls the policy:
  · nil             — never fire (preserve existing content).
  · t               — always fire (legacy behaviour;  forces
                       a fresh Claude call regardless of
                       existing content).
  · `:missing-only' — fire only when the file's Claude
                       Translation/Vocabulary slots are missing
                       or placeholders.

Returns non-nil when a request SHOULD be dispatched."
  (cond
   ((null re-request-claude) nil)
   ((eq re-request-claude :missing-only)
    (tibetan-analysis--claude-needs-request-p filepath))
   (t t)))

(defun tibetan-analysis--restore-claude-sections (filepath sections)
  "Write SECTIONS (a plist) back into FILEPATH's Claude headings.
SECTIONS has keys :translation, :vocabulary, :grammar, :particles,
:concepts;  any nil slot leaves the corresponding org body
untouched.  Creates the target headings if they are missing,
migrating legacy layouts on first encounter.

§5.24 (2026-05-22):  `:concepts' replaces the legacy `:context'
slot.  Heading promoted from `*** Claude Context' (L3) to
`** Concept Notes' (L2) for segment layout;  sentence layout keeps
L3 (via the else branch of `--claude-effective-section-order')."
  (when (and sections (file-exists-p filepath))
    (let ((buf (find-file-noselect filepath)))
      (with-current-buffer buf
        (tibetan-analysis--ensure-claude-headings buf)
        (let ((inhibit-modification-hooks t))
          (dolist (entry (tibetan-analysis--claude-effective-section-order buf))
            (let ((key (nth 0 entry))
                  (heading (nth 1 entry))
                  (level (nth 2 entry)))
              (when (plist-get sections key)
                (tibetan-analysis--replace-claude-section-body
                 buf heading (plist-get sections key) level)))))
        ;; `--merge-claude-vocabulary' call retired 2026-05-20
        ;; (§5.21 Commit 2/7) — see insert path for rationale.
        (save-buffer)))))

;; Backwards-compatible single-section restore — wraps the translation
;; string in a plist so old callers keep working.
(defun tibetan-analysis--restore-claude-translation (filepath translation)
  "Write TRANSLATION back under `*** Claude Translation' in FILEPATH.
Legacy wrapper around `tibetan-analysis--restore-claude-sections'."
  (tibetan-analysis--restore-claude-sections
   filepath (list :translation translation)))

(provide 'tibetan-analysis-claude)
;;; tibetan-analysis-claude.el ends here
