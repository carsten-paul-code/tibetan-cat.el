# CLAUDE.md — Agent handoff for tibetan-cat.el

This file briefs Claude Code (or any other Claude surface) picking up
work on **tibetan-cat.el**, Carsten Paul's Emacs-Lisp Computer-Assisted
Translation (CAT) system for Classical Tibetan. Read it in full before
editing. Last updated 2026-04-24 (added §5.10–§5.13: dictionary polish,
grammar unification, thesaurus + target-language pipeline, three-level
dispatch).

Companion files worth reading alongside this one:
- `~/.claude/projects/-Users-cp/memory/working_discipline.md` — the
  project-agnostic baseline extract of §2.1–§2.5 (applies to every
  Carsten repo).  This file refines but does not override them.
- `~/.claude/projects/-Users-cp/memory/project_tibetan_cat.md` — the
  one-page pointer from auto-memory; older / less detailed than this
  doc.  If the two disagree, believe this one.

---

## 1. Who you're working with

- **Carsten**, researcher in Buddhist studies. Works primarily on
  Classical Tibetan sources (Bhutan-Kagyu Madhyamaka context, Milarepa
  material, verse philology).
- He is the tool's author and only current user; the system is being
  prepared for a workshop presentation.
- Project order he is following: **refactor → extend → document →
  presentation.** We are currently in the "extend" phase with a few
  targeted items still open. Documentation and presentation come
  **after** the code is where he wants it. Do not start on docs or
  slides unless he explicitly asks.

## 2. How Carsten likes to work

These are hard preferences. Treat them as rules, not suggestions.

1. **Bug fixing always first.** If a bug surfaces during any session
   — live review of an analysis file, a regression spotted mid-
   feature, a failing ERT test, a warning Claude notices in passing —
   fix the bug BEFORE continuing the current feature work. Don't
   defer with a "I'll flag it for later"; the correct default is to
   pause the feature, fix the bug (tests + commit), then resume.
   Only defer when (a) the bug is clearly out of scope for this
   session AND (b) you explicitly ask Carsten and he says OK.
2. **Test first — always.** The workflow has three flavours, and
   tests come BEFORE the code in each:

   - **BDD for specifications.** When Carsten asks for a new
     behaviour, write a failing ERT test that encodes the acceptance
     criteria (inputs → expected output / state change) BEFORE any
     implementation.  The test is the spec; the code is what makes
     the spec pass.  Prefer one test per observable behaviour, named
     after the behaviour not the function.

   - **TDD for functions.** New helper / new branch / new edge case
     → failing test first, minimal implementation to pass, refactor
     with tests green.

   - **Regression-test-first for bugs.** When a bug surfaces:
     1. Reproduce it — isolate the minimum input that triggers it.
     2. Write a failing test (or several) that nails it down: the
        exact misbehaviour, plus adjacent cases the fix must not
        break.  Check the tests fail on the current code for the
        reason you expect — if they pass or fail in a different way,
        your understanding of the bug is wrong and you need to go
        back to step 1.
     3. Fix the code.  All your new tests go green; the suite stays
        green.
     4. Only now do manual verification.  The tests guarantee the
        specific bug class can't come back silently — manual testing
        just confirms UX polish.

     Do NOT fix a bug by writing the patch first and a test
     "afterwards to lock it in"; that path produces tests that pass
     by construction and don't actually guard against the bug
     re-appearing via a different code path.

   Stub external dependencies (SQLite, network, glossary files) so
   tests run in batch without side effects.  Keep the suite green
   after every commit — `make test` is the baseline gate.
3. **Verify failure mode before implementing.** After writing a
   regression test (rule 2), RUN it and confirm it fails for the
   reason you expect — the specific bug you're targeting, not a
   typo, missing import, wrong assertion, or unrelated environment
   issue.  If the test passes or fails in an unexpected way, your
   understanding of the bug is wrong; go back to reproduce.

   Before moving to the fix, include the failing test output in
   your report to Carsten.  He reads it to confirm you're fixing
   the right thing.  This is the discipline that turns "tests that
   pass by construction" into "tests that cannot pass without the
   bug being gone".
4. **One logical change per commit.** Each commit is the minimum
   reviewable unit.  If a session adds a feature AND fixes an
   adjacent bug AND refactors unrelated code, that is three
   commits, not one.  Default to splitting; only combine if
   Carsten explicitly asks.  The rationale is both `git bisect`
   hygiene (a future bisect lands on a single change) and review
   cost (a reviewer can accept/reject one piece without rejecting
   the whole).

   Corollary: never squash a green interim commit into a
   follow-up refinement after the fact — the interim state is
   itself a useful reference point.
5. **Commit messages document the WHY with concrete examples.**
   Subject line: imperative mood, ~60 chars, names the change
   (`thesaurus: add gap report for German prep`).  Body structure:

   - Problem / observation — what went wrong or what user need
     surfaced; include the concrete reproducer or a quote from
     a live review when available.
   - Root cause — the INSIGHT, not just the symptom.  Why did
     this bug exist / this feature matter?
   - Fix — what the code now does differently, at the level of
     mechanism (not just "added function X").
   - Tests — names of new / modified tests and what they guard
     against.  Report the suite totals after the change.

   Reference earlier commits by short hash when relevant (e.g.
   "extends commit 259d00b's Hill-DB guard pattern").  A future
   session reading `git log` should understand not only WHAT
   changed but the REASONING — the project has several polish
   bugs whose fix is one line but whose explanation is three
   paragraphs.  Preserve the explanation.
6. **Preserve user content.** Any operation that regenerates analysis
   files must preserve `* My Notes`, `* Working Translation`,
   `* Footnotes`, and an existing `*** Claude` translation. If you
   touch the regenerate / batch-reanalyze path, add a test that
   asserts preservation.
7. **Persistent analysis is the canonical workflow.** He uses `C-c u A`
   (persistent analysis file per segment) — not `C-c u i` (classroom /
   scratch view). Design features around the persistent-file flow
   first; the classroom view is secondary.
8. **Don't silently change behaviour.** If a fix alters what users see
   in their analysis files, say so and ask before rewriting files he
   has invested hours annotating.
9. **German and English side by side.** Many glosses are bilingual
   (`DE // EN`). Don't collapse this — the `tibetan-analysis--format-bilingual-gloss`
   helper exists for a reason. Resources/Custom entries are hand-written
   and must never be truncated or rewritten.  Pass 5c adds a per-
   document `#+TIBETAN_TARGET_LANG:` header that determines which
   half the Interlinear / CAT Gloss / Claude Translation show;
   the bilingual pair stays in the Detailed Dictionary regardless.
10. **Aim close to perfect.** He is not looking for "ship it" output;
    he wants careful, correct code. If a solution is 80% there, say so
    and propose the remaining work rather than declaring it done.
11. **Explain what you're about to do before doing it** for anything
    that touches more than one module, then run the tests after.
12. **New reading source files follow the Section → Sentence → Segment
    layout.** Every new `.org` source document for the CAT pipeline
    (MA Readings Tibetan, Tibetisch IV, any future reading corpus)
    uses this nested structure:

    ```
    * Tibetan Text
    ** Section N. <label>        ← optional; only for editorial
                                    divisions (e.g. the three-persons
                                    [I]/[II]/[III] in a lam-rim;
                                    stanza groups; opening/body/colophon)
    *** Sentence N               ← one per prose paragraph or verse
                                    stanza; global numbering from 1
    **** Segment M               ← shad-bounded clause; global
                                    numbering from 1
    :PROPERTIES:
    :FOLIO:    <ref>             ← only when folio refs matter
    :END:

    <Tibetan Unicode>

    **** Working Translation     ← sibling of Segment; empty
                                    placeholder at creation time
    ```

    Reference implementation:
    `/Users/cp/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/SS26/Tibetisch IV/work in progress/Milarepa-prepared.org`.
    The sentence-aware commands (`C-c u B` auto-analyze-document,
    `C-c s N` sentence-create-all, `C-c s Z` resegment) expect this
    hierarchy — flat `** Section → *** Segment` layouts (older Gal
    chen nyi shu style) miss the Sentence level and don't feed
    `sent-*.org` creation cleanly.  Do NOT regenerate older flat
    files unless Carsten explicitly asks.

## 3. Repository shape

```
tibetan-cat.el/
├── core/         primitives: wylie, vocabulary, verb-classifier,
│                 steinert (SQLite), doc-display, etc.
├── analysis/     segment / compound / clause / round1+round2 analysis
├── persist/      tibetan-analysis-persist.el — the persistent
│                 analysis-file machinery (generate, regenerate, batch)
├── workspace/    sentence-workspace, verse-workspace buffers
├── philology/    madhyamaka-terms, verse-philology, particles
├── doc-prep/     OCR runner, doc-format, ocr-correct
├── config/       tibetan-keybindings.el, tibetan-menu.el
├── test/         ERT test suite, run-all-tests.el is the entry point
├── data/         dictionaries/steinert.db (SQLite, built via make)
├── Resources/    per-document vocabulary lists (user-curated)
├── Makefile      `make test` runs the full batch suite
└── tibetan-cat.el  top-level loader
```

Key invariants:

- All source files start with `;;; foo.el --- … -*- lexical-binding: t -*-`.
- Every module provides itself: `(provide 'foo)` at the bottom.
- Soft-requires use `(require 'x nil t)` so an optional module missing
  does not break loading.
- Test files live in `test/` and get added by `(condition-case nil
  (require 'foo-test) (error nil))` in `run-all-tests.el`.

## 4. Running the tests

```sh
cd test
emacs -batch -l run-all-tests.el -f ert-run-tests-batch-and-exit 2>&1 | tail -25
```

Or: `make test` from the project root.

Current state (2026-04-24): **1452 tests, 1449 expected, 0 unexpected
failures, 3 intentional skips (text-scale / compound-analysis-callable).**
Carsten runs this after every change and expects it to stay green.

When adding a test, always wire it into `test/run-all-tests.el` via
`condition-case`. Otherwise the suite silently doesn't pick it up and
you'll think your tests passed when they didn't run.

## 5. What was done in the last block of work

This is the recent history. Read it so you don't re-do finished work.

### 5.1 Round-2 clause analysis (done, tested)
- **New module** `analysis/tibetan-clause-segmenter.el` with three
  composable public entry points:
  - `tibetan-clause-segment (words verbs &optional _mwu)` —
    position-indexed clause segmentation on converb / final-particle /
    verb-end boundaries.
  - `tibetan-np-chunk (words &optional clauses mwu)` — NP chunking
    with case-tagging (ERG/GEN/DAT/LOC/TERM/ABL/COM).
  - `tibetan-build-argument-structure (clauses nps)` — assigns subject
    / agent / object / oblique roles using verb case-frames from the
    Hill 2010 classifier.
  - `tibetan-analyze-round2` — convenience wrapper that calls all three.
- Tests: `test/tibetan-round2-clause-segmenter-test.el` (11 tests,
  including an end-to-end seg-012 integration test).
- **Not yet wired** into `tibetan-analysis-generate-content` as a
  `** Clause Structure` section in the analysis file — see §6.

### 5.2 Batch reanalysis (done, tested)
- Added to `persist/tibetan-analysis-persist.el`:
  - `tibetan-analysis-reanalyze-file (filepath &key source-file
    re-request-claude dry-run)` — regenerates one analysis file while
    preserving all user sections AND an existing non-placeholder
    `*** Claude` translation.
  - `tibetan-analysis-batch-reanalyze (&key folder source-file
    re-request-claude dry-run)` — iterates every `seg-NNN*.org` in a
    folder, in seg-id order.
  - Helpers: `--read-section-body`, `--read-claude-translation`,
    `--restore-claude-translation`, `--seg-id-from-filename`,
    `--folder-analysis-files`.
- Keybinding: `C-c u r` (lowercase r — distinct from `C-c u R` which
  is single-segment reanalyze and `C-c u B` which is "analyze all
  segments, create missing files").
- Menu entry: `Tibetan → Persistent Analysis → Batch Re-analyze Folder`.
- Tests: `test/tibetan-batch-reanalyze-test.el` (6 tests covering
  notes preservation, Claude preservation, placeholder-not-persisted,
  dry-run, missing seg-id, folder iteration).

### 5.3 Detailed Dictionary multi-source rendering (done, eyeball-verified on seg-4)
- **Problem observed:** verbose polysemous words like ཡུལ produced a
  huge block from whichever single source `tibetan-vocab-lookup-detailed`
  picked. Also, Sanskrit was being synthesised from Sanskrit-indexed
  tables even when the entry itself didn't carry it.
- **New rule** agreed with Carsten ("rule A"):
  1. Provided vocabulary list (Resources) entry appears first when present.
  2. Steinert aggregated block (top hits, deduplicated internally).
  3. Rangjung Yeshe standalone.
  4. Bundled / DharmaMitra *only* if they add a genuinely different gloss.
  5. Sanskrit surfaced **only** when the source entry natively carries it.
- **Implementation:**
  - `core/tibetan-vocabulary-detailed.el` gained
    `tibetan-vocab--dedup-fingerprint` (normalised gloss fingerprint)
    and `tibetan-vocab-multisource-entries (word)` which returns the
    ordered list of per-source plists.
  - `persist/tibetan-analysis-persist.el` — the `** Detailed Dictionary`
    renderer (around line 1834) now walks that multi-source list.
  - Tests: `test/tibetan-vocab-multisource-test.el` (8 tests with fully
    stubbed sources).
- **Verified on seg-4 (2026-04-15)**: cap tuned from 8 → 5 via the
  `tibetan-vocab--steinert-cap' defconst.  Knobs for further tuning:
  the cap defconst itself, and the 80-char fingerprint length in
  `tibetan-vocab--dedup-fingerprint'.

### 5.4 Display consistency + Bialek terminology (done, verified)
Two cross-cutting cleanups:
- **`SCRIPT [wylie]` everywhere** except the top-level `* Tibetan
  Text` section.  One helper `tibetan-analysis--format-word-with-wylie'
  in `persist/tibetan-analysis-persist.el' is the single source of
  truth; six callers (Word/Particle List, Grammatical Markers,
  Sentence Structure, Verb Classification lemma + STEMS, Detailed
  Dictionary head) route through it.  Particle Map stays wylie-only
  by design.
- **Bialek terminology unified**.  Both the Word/Particle List and
  the Grammatical Markers section now route through
  `tibetan-analyze-grammar-bialek' via the `tibetan-analysis--bialek-type'
  helper.  The legacy hardcoded role table in
  `tibetan-analysis--get-grammatical-role' was deleted; the verb
  suffix labeller (`tibetan-analysis--detect-verb-suffix') now
  delegates to the same helper.  The legacy Sentence Structure
  argument analyser (`tibetan-analyze-arguments' in
  `analysis/tibetan-enhanced-display.el') was also routed through
  the segmenter's case-of helper so single-char ས/ལ/ར/ན don't get
  mistaken for case particles.

### 5.5 Round-2 wired into analysis output, with chunker fixes (done)
- `** Clause Structure' section (gated by
  `tibetan-analysis-show-clause-structure', default `t').  Renderer
  `tibetan-analysis--render-clause-structure' uses `tibetan-analyze-round2'.
- `tibetan-clause-segmenter' is now hard-required from
  `tibetan-cat.el' (and soft-required from the persist module) so
  the renderer always sees `tibetan-analyze-round2' at runtime.
- Three Round-2 chunker bugs fixed:
  1. **Single-char case particles standalone-only** (ས/ལ/ར/ན as
     final consonants no longer mis-stripped).  New helper
     `tibetan-clause-seg--multichar-suffix-p' applied to
     `--classify-word', `--case-of', `--case-strip'.  Also added
     `("ལས" . ABL)' to `--case-particles' (was missing — already
     present in bialek).
  2. **Content-word gluing** for compound proper nouns.  Plus a
     compound-`Xར' terminative rule in the NP chunker that mirrors
     bialek's seg-4 fallback.
  3. **Nominalised verbs filtered out of clause segmentation**.  New
     `tibetan-clause-seg--nominaliser-suffixes' defconst.  When a
     verb is followed by a bare nominaliser (`པ' / `པའི' / etc., but
     NOT `པས'/`བས' which are causal converbs), the verb does not
     form a clause; the last surviving clause's end is extended to
     cover any uncovered tail.  Falls back to the unfiltered list
     if filtering would produce zero clauses.
- MWU spans truncate at verb positions (Resources-supplied MWU like
  `ཡུལ་འཐོན' no longer absorbs the verb into the NP head).

### 5.9 Tokenization, section reorder, robust fallback (done, tested, 2026-04-21)

Three related fixes in response to user review of a live Milarepa
segment (seg-026 `བདག་ལ་སྟོད་ནས་འོངས།`) and a Yogācārabhūmi
class-prep QA sweep:

1. **Particle-tail / particle-head MWU rejection** (`core/tibetan-vocabulary.el`
   + `core/tibetan-vocabulary-detailed.el`, commit `29da547`):
   The two greedy 4/3/2-syllable compound loops that feed the
   Word/Particle List, Interlinear Gloss, and Detailed Dictionary
   were picking up real dictionary idioms like `བདག་ལ` (Skt. `naḥ`
   "to me") and `སྟོད་ནས` (Skt. `uparimāt` "from above") as single
   lexical units, hiding the grammatical `stem + PARTICLE` split
   that Particle Map / Clause Structure / Grammatical Markers
   otherwise render correctly.

   Fix: reject any compound whose head OR tail syllable is in
   `tibetan-extract-vocab--particle-tails` (the same list the MWU
   parser already used via `tibetan-enhanced-parser--case-particle-
   tail-p`).  Nominaliser tails (`པ` / `བ` / `མ`) are explicitly
   EXCLUDED so `བསྐལ་པ` (kalpa) etc. remain intact.  +3 ERT tests.

2. **Section reorder: Claude Translation + Grammar before Verb
   Classification** (`persist/tibetan-analysis-persist.el`, commit
   `ad7dd6c`).  New priority order in
   `tibetan-analysis--priority-section-order`:

       ** Wylie Transliteration       — sounded reading
       ** Particle Map
       ** Interlinear Gloss           — word-for-word trot
       ** Claude Translation          ← was position 5, now 4
       ** Claude Grammar              ← was position 6, now 5
       ** Verb Classification (Hill 2010)  ← was 4, now 6
       (… Word/Particle List, Clause Structure, Detailed Dictionary …)

   Reader flow: sound → particle-annotated skeleton → word-for-word
   trot → fluent translation + grammar explanation → parser-side
   reference tables.  Applies uniformly to seg- and sent-*.org via
   the shared renderer + reorder post-pass.  +1 ERT test on the
   Claude<VerbClass ordering invariant; existing priority-order
   test updated.

3. **Richer error fallback** (`persist/tibetan-analysis-persist.el`,
   commit `aa60337`).  When `tibetan-analysis-generate-content`'s
   outer condition-case fires, the fallback template used to emit
   only three `[Error]` stubs, wiping a file that had working
   Wylie + Claude content.  New fallback still emits:
     - `** Wylie Transliteration` with real Wylie (safe path)
     - `** Claude Translation [Requesting translation...]` placeholder
     - `** Claude Grammar` empty but present
     - `** [Analysis error — partial file only]` with diagnostic
   So a parser failure on ONE section no longer destroys the whole
   file — student sees Tibetan + Wylie + full Claude content with
   a visible marker flagging the degraded parser output.

   Used to recover YBh seg-030..034 on 2026-04-21: a parser corner-
   case on `gyur pa'o` (nominaliser + declarative particle) made
   `cl-remove-if-not` receive word-strings where verb-alists were
   expected.  Underlying bug not yet root-caused — see §6 P5.

Full suite at end of 2026-04-21: **1337 / 1334 expected / 0
unexpected / 3 intentional skips.**

### 5.10 Condensed Detailed Dictionary + ★-Resources marker (done, 2026-04-21/22)

Four commits refining the Detailed Dictionary block that ships under
every STEM in the analysis file.  Motivation: the multi-source block
from §5.3 was correct but visually dense, and it was hard to tell at
a glance which entries came from Carsten's hand-curated Resources
list versus auto-sourced dictionaries.

1. **Slimmer Detailed Dictionary — Pass B** (`e56dd7d`).  Added a
   per-source cap, a Sanskrit filter (synthesised Skt from reverse-
   indexed tables no longer surfaces when the source entry doesn't
   carry it), and a particle exemption so case-particle entries
   don't get truncated like content words.
2. **Condensed dictionary foundation — Pass 5a** (`8f3d40b`).
   New ranker with anchored source ordering (Resources-first,
   Steinert, then the long tail) + first-sense bracket-aware
   extraction that keeps `(1) [accusative, …]` intact instead of
   chopping at the first comma.
3. **Detailed Dictionary renders under the STEM — Pass 5a.1**
   (`1a4e48e`).  The DD block now appears nested under the
   Word/Particle List STEM heading instead of as a sibling —
   reader's eye stays on the stem while scanning senses.
4. **★ marks Resources / Custom / Thesaurus entries in Interlinear**
   (`4d2792d`).  Curated sources get a ★ prefix in the word-for-word
   gloss so at a glance Carsten can see "this is my own gloss, not
   an auto-lookup".  Same commit removed the now-redundant
   `** Word/Particle List` top-level section (the info lives inside
   Interlinear and Detailed Dictionary).

### 5.11 Grammar section unification (done, 2026-04-22)

The analysis file used to carry four overlapping grammar-ish
sections: `** Particle Map`, `** Claude Grammar`, `** Particle
Overview`, `** Grammatical Markers`.  Carsten called this "a lot of
redundancy" on live review.  Result is a single `** Grammar`
section with a Particle Map subsection and per-particle Portfolio-
cross-referenced entries.

1. **Pass 6b — merge into `** Grammar`** (`0de3e31`).  Single
   top-level section replaces the four.  Particle Map is now a
   nested `*** Particle Map` rendering the stem+particle skeleton;
   the bialek/Claude per-particle analysis follows as numbered
   entries.
2. **Pass 6c — per-particle function IDs + self-contained Portfolio
   snippets** (`8b30377`).  Each particle entry carries an id like
   `[[id:XYZ][Portfolio §1.6 ↗]]` linking into Carsten's Bialek
   Portfolio zettel, AND inlines the relevant Portfolio paragraph
   in the analysis file so a reader without access to the Portfolio
   can still follow the grammar.  Snippet body indented via
   `(replace-regexp-in-string "\n" "\n    " raw)` so the multi-line
   body doesn't leak as a sibling bullet.
3. **Dynamic Portfolio section-number injection into Claude prompt**
   (`0636665`).  Claude's `*** Claude Particles` output references
   Portfolio section numbers (`§1.6 Terminative`).  Previously
   Claude used its own guessed numbering (e.g. §1.5), which drifted
   from Carsten's actual Portfolio (§1.6).  Fix: the system prompt
   now includes `tibetan-interlinear-portfolio-reference-block` —
   a dynamic list of the real section numbers parsed from the
   Portfolio zettel.
4. **Particle-map presentation polish** (four commits):
   - Apply face via font-lock bypassing org emphasis word-boundary
     rule (`fa671e2`) — `'i` now renders magenta even when flanked
     by `=` delimiters where org won't parse emphasis.
   - Hide `=` / `~` delimiters, keep only the particle visible
     (`743535a`) — invisible text property + namespaced
     `tibetan-analysis-particle-marker` in buffer-invisibility-spec.
   - Lowercase particle tokens inside markup (`94652dc`).
   - Multi-tuple matching — one bialek entry, multiple Claude tuples
     per occurrence, dedup by sub-id, annotate with context word
     (`4b122ba`).  `r` ↔ `ra` Wylie normalisation via
     `--particle-wylie-normalise` so bare `ར` matches Claude's `r`.
5. **Auto-regen Grammar when Claude Particles arrives** (`ca2e6c5`).
   `insert-claude-sections` now calls `reanalyze-file` with
   `:re-request-claude nil` when Particles are present, so the
   Grammar section rebuilds with Claude data without re-firing
   the Claude translation request.

### 5.12 Thesaurus + target-language pipeline (done, 2026-04-22)

User-editable multilingual glossary layered on top of the dictionary
stack, plus per-document target-language selection and a gap-report
designed to prep a source file for translation (currently the German
Milarepa workflow).  This is the biggest single feature since the
Round-2 clause segmenter.

**New module** `core/tibetan-thesaurus.el`:

- File-per-term org zettels in `~/Documents/tibetan-thesaurus/` with
  `:ID:` property + `:wylie:` + `:script:` + bilingual
  `:primary:` / `:detailed:` fields.  Each zettel carries back-links
  to the analysis segments that use the term.
- Rank-1 injection into `tibetan-vocab-multisource-entries` (above
  Resources).  Overrides `:primary`/`:detailed` with the full
  bilingual `DE // EN` string so the parser's first-sense extraction
  doesn't truncate at the bilingual separator.
- Sliding-window tokenised Wylie matching via
  `tibetan-thesaurus--tokenise-wylie-text` +
  `tibetan-thesaurus--count-mentions` (replaced a regex-with-
  boundary-consumption approach that miscounted consecutive
  occurrences — `bdag bdag bdag` scored 2 instead of 3).

**Commands** under `C-c u z` prefix:

| binding    | command                                   |
|------------|-------------------------------------------|
| `C-c u z e`| `tibetan-thesaurus-edit-at-point`         |
| `C-c u z n`| `tibetan-thesaurus-new-entry-interactively` |
| `C-c u z r`| `tibetan-thesaurus-reload`                |
| `C-c u z i`| `tibetan-thesaurus-initialize-from-kramer`|
| `C-c u z a`| `tibetan-thesaurus-audit-folder-display`  |
| `C-c u z R`| `tibetan-thesaurus-rerun-affected-by-zettel` |
| `C-c u z L`| `tibetan-analysis-set-source-target-lang` |
| `C-c u z g`| `tibetan-thesaurus-translation-gaps-display` |

**Pass 5b** (`7dc80d6`) — user-editable glossary at rank 1; new zettels
take precedence over all dictionary sources in the renderer.

**Pass 5b.2** (`f6ddf48`) — create/edit entries from analysis buffer.
`--wylie-at-point` recognises the word under cursor in `** Detailed
Dictionary`; the new-entry command pre-fills script + wylie from the
analysis context.  `case-fold-search` must be `nil` inside the wylie
detector — default case-insensitive matching caused `[A-Z]+` to
match lowercase Wylie and filter real words out.

**Pass 5c** (`ec5b1a9`) — per-document DE/EN target-language picker.
`#+TIBETAN_TARGET_LANG:` header added to source files via
`tibetan-analysis-set-source-target-lang` (`C-c u z L`).  Value is
threaded through `tibetan-analysis--target-lang` dynamic var into
`generate-content`, `--cat-english-gloss`, and the Claude system
prompt (`target-lang-block` conditional — adds a German directive
when de-selected).  The bilingual DE // EN pair always remains in
the Detailed Dictionary; only Interlinear / CAT Gloss / Claude
Translation narrow to the selected half.

**Pass 5d** (`8476eef`) — cross-document consistency audit +
targeted rerun.  `audit-folder` walks all seg-*.org in a folder and
flags segments whose Interlinear gloss for a given term doesn't
match the thesaurus.  `rerun-affected-by-zettel` re-analyses only
the segments touched by a specific zettel, avoiding a full
`batch-reanalyze` when one gloss changes.

**Translation-gap report** (`6e78c22`) — `C-c u z g` lists every
segment where the thesaurus zettel has `[to be researched]` or an
empty target-lang side, so Carsten can walk the list and fill
entries before translating.  Designed for the German Milarepa prep
workflow: `C-c u z i` → `C-c u z L de` → `C-c u B` → `C-c u z g` →
walk the list.

**Tests**: `test/tibetan-thesaurus-test.el` (37 tests),
`test/tibetan-analysis-claude-prompt-test.el` (target-lang +
set-source tests), `tibetan-wylie-test.el` (`'adra`/`'dra`
regression from `d0e9f8a`), `tibetan-particles-bialek-test.el`
(single-`s` ergative tests from `259d00b`).

### 5.13 Three-level analysis dispatch (done, 2026-04-23)

`C-c u A` and `C-c u R` used to always target the segment the cursor
was on.  New behaviour: **detect context and route** — segment if
cursor is under a `**** Segment`, sentence if under `*** Sentence`,
paragraph if under `** §N` or similar.  Added via three commits:

1. **Generic §-level paragraph analysis** (`19b19ff`) — new
   `tibetan-paragraph-*` machinery for `** §N` (paragraph) context,
   bound to `C-c p A` / `C-c p R` as dedicated paragraph commands.
2. **Paragraph dispatch from `C-c u A` / `C-c u R`** (`03ff719`) —
   cursor-context detection hook added.
3. **Three-level unification** (`2b82b5f`) — dispatcher routes
   between segment/sentence/paragraph handlers based on the
   nearest enclosing heading.

Also in this window: `19a95f6` (specs/tigress + document-prep
updated to the current reading-file layout from §2.12).

### 5.8 Claude integration hardening + Anthropic prompt caching (done, 2026-04-20)

Five cumulative improvements to the Claude request path, all
motivated by running real batch fills against the 97-segment YBh
corpus and the 85-sentence Milarepa corpus:

1. **Batch-create fires Claude automatically** (commits `bac120b`
   + `bd3ef40`).  `tibetan-auto-analyze-document' (C-c u B) and
   `tibetan-sentence-create-all' (C-c s N) previously left every
   newly-created file with a `[Requesting translation...]'
   placeholder, requiring a separate
   `tibetan-auto-request-claude-translations' pass to fill them —
   parity broken with the single-file `C-c u A' / `C-c s A' path
   that always fired Claude on create.  Both batch commands now
   queue staggered async Claude requests for every newly-created
   file.  Gated by `tibetan-auto-fire-claude-on-create' (default
   `t`).  +6 ERT tests.  The placeholder-detector regex was also
   relaxed from `^\\*\\*\\* Claude\\$' (three stars, no suffix) to
   `^\\*+ Claude\\(?: Translation\\)?[ \\t]*\\$' so both the Auto-
   Analysis two-star and Provided-Translations three-star layouts
   register as "needs Claude".  +4 ERT tests.

2. **Drawer-aware segment-text extractor** (commit `ebac416`).
   `tibetan-org-get-segment-text' used to return everything between
   the `*** Segment' heading line and the subtree end — which on YBh
   segments carrying a `:FOLIO: Dxxxx' property drawer meant the
   drawer body (`:PROPERTIES: :FOLIO: D3a3 :END:') was concatenated
   into the "Tibetan text" handed to the structural analyser,
   sometimes tripping `(wrong-type-argument stringp nil)` downstream.
   Fixed to skip a leading `:PROPERTIES: … :END:' drawer and stop
   at the first child heading (any depth) so `**** Working
   Translation' siblings also don't leak.  +2 ERT tests.

   Known regression: the drawer-skip fix meant newly-created
   analysis files no longer carry the `:FOLIO:' property on their
   own `* Tibetan Text' heading (the drawer is stripped during
   read).  Low priority — the folio is still visible in the source
   seg's drawer.  See §6 P6.

3. **Skip-check path matches create-file's write path** (commit
   `28deda7`).  `tibetan-auto-analyze-document's skip-check called
   `(tibetan-analysis-get-filepath seg-num source-file)' which
   returns a SUFFIXED path like `seg-NNN-<shortname>.org', but
   `tibetan-analysis-create-file' internally re-computes the path
   WITHOUT source-file and writes to the UNSUFFIXED `seg-NNN.org'.
   The mismatch meant every existing seg-NNN.org was silently
   OVERWRITTEN on every re-run of `C-c u B' — wiping Claude
   translations.  Fix: drop the source-file arg from the skip-check
   so both sides use the unsuffixed path.  Lost ~3 hours of API
   spend rediscovering this; regression test in place (`auto-analyze-
   skip-check-matches-create-path').

4. **Anthropic prompt caching** (commit `cc582ff`).
   Every Claude request from the tool uses the SAME system prompt
   across all segments of a given document (it's `tibetan-analysis--
   claude-system-prompt' + the source file's `#+TIBETAN_CLAUDE_CONTEXT'
   block).  Wrapping each `gptel-request' call in
   `(let ((gptel-cache '(system))) ...)' tells gptel to attach
   `cache_control: {"type": "ephemeral"}' to the system prompt —
   Anthropic then serves it from cache at 10% of normal input cost
   on requests 2..N within the 5-min TTL.  Verified working via
   direct API probe (`cache_read_input_tokens' jumps to non-zero
   after first request).  Net savings: ~50% of input cost on warm
   cache.

5. **Operational outcomes** delivered 2026-04-20:
   - **Milarepa Tibetisch IV**: 85/85 `sent-*.org' filled via
     headless batch (12-min wallclock), preserved across
     re-segmentation disaster.
   - **Yogācārabhūmi Gotrapaṭala**: 97/97 `seg-*.org' filled via
     three-pass headless batch (first pass 39/92 ok, OTPM
     rate-limited; second pass with concurrency=1 delay=15s got
     the rest after user bought Anthropic API credits).
   - **Credit-balance vs Max-plan-subscription** distinction
     documented — the tool uses a separate `~/.authinfo' API key,
     NOT the Claude Code Max subscription.

### 5.7 Sentence re-segmentation workflow + bare-seg migrator (done, tested, 2026-04-20)

Two related workflows added/fixed for the Milarepa re-segmentation
and Josefine layout-harmonisation passes:

1. **Re-segmentation orchestrator** (`persist/tibetan-sentence-persist.el`):
   - `tibetan-sentence-resegment` (`C-c s Z`) — orchestrator chaining
     archive → reset → re-segment → create-all behind a single yes/no.
   - Sub-commands: `…-archive-analysis-folder` (`C-c s X`),
     `…-reset-structure` (`C-c s U`, actually lives in
     `doc-prep/tibetan-sentence-structure.el`), `…-create-all`
     (`C-c s N`).
   - Tests: 18 ERT (8 reset, 4 archive, 4 create-all, 2 resegment).
2. **Segment-structure demotion fix** (`doc-prep/tibetan-sentence-structure.el`):
   `tibetan-add-sentence-structure' previously only demoted the first
   segment of each sentence, leaving continuation segments orphaned
   at `*** Segment' sibling of `*** Sentence'.  Fixed; all segments
   now demote to `**** Segment'.  +3 ERT tests.
3. **WT-leak fix in `create-all`**: body-end detector now stops at
   any heading (`^\\*+ `) instead of only `**** Segment', so sibling
   `**** Working Translation' doesn't leak into the sentence's
   concatenated Tibetan text.  +1 ERT test.
4. **Bare-seg migrator** (`doc-prep/tibetan-segment-migrate.el`):
   `tibetan-migrate-bare-segments-to-headings` — converts
   `〔seg:N〕…〔/seg〕' markers (no `〔trans:N〕' pairs — the
   Thar-rgyan / Josefine pipeline) to `*** Segment M' headings.
   Pipeline: split+flatten Tibetan-title headings to `** Section',
   hoist `#+KEYWORD:' metadata to document header, renumber from 1,
   drop segments that become empty after hoisting.  +10 ERT tests.
5. **Yogācārabhūmi Wylie preparation** (`doc-prep/tibetan-ybh-prep.py`):
   Python script (pyewts dependency) that prepares a Wylie Derge-style
   śāstra source into the Milarepa segment layout.  Used 2026-04-20
   to prep `gotrapatala.org' (97 segments × 97 sentences, 97 :FOLIO:
   properties inheritance-filled).  Install pyewts with
   `pip3 install --break-system-packages --user --no-build-isolation pyewts'.

### 5.6 Bug fixes shipped this round
- **`པ' / `པའི' tagged as verbs (P1 from §6).** Added
  `tibetan-verb-detect--nominalizer-set' in
  `analysis/tibetan-enhanced-display.el'; `--lookup' rejects bare
  nominalisers regardless of which dictionary path matches.
- **Steinert cap drift fix** (the original 7 multisource tests were
  red — fingerprint regex bracket-class typo + lexical-binding
  `set'/`symbol-value' pattern; both rewritten).
- **`ལ' detailed dictionary primary chopped at `(1) [accusative'.**
  `tibetan-vocab--parse-entry' now uses a bracket-aware
  `--first-sense-bracket-aware' scanner so commas inside `[…]' or
  `(…)' don't terminate the first-sense extraction.
- **Word/Particle List vs Detailed Dictionary out of sync** (entries
  showed Steinert/IvesWaldo gloss while DD showed Resources).  Word
  list now routes through `tibetan-vocab-multisource-entries' too,
  taking the first entry — Resources-first across the board.
- **Dictionary reload on every reanalysis**.
  `data/tibetan-glossary-loader.el's `load-all-glossaries' was
  unguarded (always `clrhash' + reload).  Added the
  `tibetan-glossaries-loaded' flag and an idempotent guard;
  `tibetan-analysis--ensure-vocabulary' short-circuits on the flag.

## 6. Open work (prioritised)

### P0 — Verify Detailed Dictionary on a real segment ✓ DONE 2026-04-15
Cap tuned 8 → 5 after seg-4 review.  Knob is the
`tibetan-vocab--steinert-cap' defconst at `core/tibetan-vocabulary-detailed.el'.

### P1 — Fix `པ` / `པའི` being tagged as verbs ✓ DONE 2026-04-15
Fixed in `analysis/tibetan-enhanced-display.el' via the
`tibetan-verb-detect--nominalizer-set' guard.  Tests in
`test/tibetan-round1-verb-extraction-test.el'.

### P2 — Wire Round-2 into analysis file output ✓ DONE 2026-04-15
Section is gated by `tibetan-analysis-show-clause-structure'
(default `t').  Renderer + 5 tests in `tibetan-analysis-persist-test.el',
plus 9 tests for the chunker fixes in `tibetan-round2-clause-segmenter-test.el'.

### P3 — Documentation phase (explicitly deferred)
Only start when Carsten says so. When that time comes:
- Update `README.md`, `FEATURES.md`, `ARCHITECTURE.md`,
  `VERSE-ANALYSIS-GUIDE.md` to reflect the batch-reanalyze command,
  multi-source Detailed Dictionary, and Round-2 clause analysis.
- Also `CHANGELOG.md` — follow the existing format.

### P4 — Workshop presentation (explicitly deferred)
A `.pptx` / walkthrough for the workshop. Don't start without
explicit instruction.

### P5 — Root-cause the `gyur pa'o' parser crash (flagged 2026-04-21)
Five YBh segments (Gotrapaṭala seg-030..034) trip
`(wrong-type-argument listp "གྱུར")` from `cl-remove(nil
("གྱུར" "པའོ") :if-not ...)` inside `tibetan-analysis-generate-
content`.  Minimal reproducer is just the text `གྱུར་པའོ་༎`.
The immediate symptom is dodged by §5.9.3's richer fallback —
affected files render with Tibetan + Wylie + Claude but no
parser-side sections — but the underlying path where a verbs-list
gets replaced by a words-list needs a focused bisect.  Advice-based
tracing didn't find it (outer condition-case absorbs before any
wrapper fires); will need to temporarily disable the outer
condition-case or instrument each inner `cl-remove-if-not` call
site explicitly.

Repro:
```elisp
(tibetan-analysis-generate-content "གྱུར་པའོ་༎")
;; Returns the fallback template (starts "** Wylie Transliteration\ngyur pa'o //").
```

### P6 — Preserve `:FOLIO:' drawer on analysis-file `* Tibetan Text' (low priority, 2026-04-21)
The drawer-aware extractor (§5.8.2) correctly strips the
`:PROPERTIES: :FOLIO: Dxxxx :END:' drawer from the source
segment's body before feeding the analyser — but a side-effect is
that newly-created analysis files no longer carry `:FOLIO:' on
their own `* Tibetan Text' heading.  Fix: have
`tibetan-analysis-create-file' accept an optional folio argument
and write the drawer explicitly, AND have
`tibetan-org-get-segment-text' (or a companion helper) return the
folio alongside the text so the caller can thread it through.

## 7. Pitfalls / things that have bitten us

- **Trailing tsheg after case-stripping**: `"བདག་གིས"` minus `"གིས"`
  leaves `"བདག་"`, not `"བདག"`. The fix in `tibetan-clause-seg--case-strip`
  does a final `(replace-regexp-in-string "་+$" "" stem)`. If you write
  similar code elsewhere, apply the same trim.
- **`cl-defun` vs `defun`**: if a helper uses `&key`, it must be
  `cl-defun`. We wasted a test cycle on this once.
- **Test discovery silently fails**: new test files do NOT run unless
  added to `test/run-all-tests.el`. The overall count will look fine.
  Always sanity-check the total test count moved up after adding tests.
- **Rangjung Yeshe lazy load**: the 162k-entry RY dictionary is
  lazy-loaded. Tests that touch it should stub
  `tibetan-lookup-word-in-rangjung-yeshe` so they don't depend on
  load state.
- **Steinert DB may be absent**: tests that need it should check
  `(tibetan-steinert-available-p)` and `skip-unless`. Several already
  do this.
- **Placeholder translations**: `[Requesting translation...]`,
  `[Claude unavailable`, `[Translation not available` — these are NOT
  real translations. Any "preserve existing Claude translation" logic
  must skip these placeholder patterns.

## 8. Conventions for Claude Code in this repo

- Use the ERT loader, not a custom test harness.
- Stub external deps in tests (SQLite, HTTP, file system outside
  tempdirs) — tests must run in batch without side effects.
- When renaming or moving a function, keep the old name as an alias
  or update every caller and test — Carsten runs into the difference
  immediately.
- Byte-compile cleanly: `make compile` should not introduce new
  warnings.
- Keep commit messages factual: what changed, which tests were added,
  what behaviour users will see.
- Don't commit without Carsten asking.

## 9. First thing to do in a new session

1. `make test` (or the batch command in §4). Confirm baseline green
   (expect 1452 / 1449 expected / 0 unexpected / 3 skipped at 2026-04-24).
2. Skim `MEMORY.md` (auto-memory) — `working_discipline.md` is the
   baseline rule set; this file refines it for tibetan-cat.el.
3. Skim `git log --oneline -20` for anything newer than §5.13 (this
   file may be stale; the log is authoritative).
4. Ask Carsten which P-level from §6 he wants to tackle — don't guess.
5. Write tests before code. Run tests after each edit.
6. Report back with: what changed, which files, which tests now
   cover it, and the updated test count.

### Active workflow: preparing a new document for German translation

Carsten's current priority is preparing new reading sources for
translation into German.  The end-to-end pipeline for a fresh
source file:

1. Create the source file in the §2.12 reading-file layout
   (Section → Sentence → Segment, with `**** Working Translation`
   siblings).
2. `C-c u z i` — initialise thesaurus from Kramer glossary (one-
   time; skip if already done).
3. `C-c u z L de` — set this source's target language to German.
   Writes `#+TIBETAN_TARGET_LANG: de` into the source header.
4. `C-c u B` — auto-analyse the whole document, creating all
   `seg-NNN*.org` analysis files with the German-side gloss in
   Interlinear + CAT Gloss + Claude Translation; bilingual DE // EN
   stays in Detailed Dictionary.
5. `C-c u z g` — run the translation-gap report.  It lists every
   segment whose thesaurus zettel has `[to be researched]` or an
   empty DE side.  Walk the list with `C-c u z e` (edit-at-point)
   to fill entries.
6. `C-c u z R <zettel>` — after editing a zettel, re-run just the
   affected segments instead of a full `C-c u r` batch.

This workflow is the reason §5.12 exists; when in doubt treat it
as the driving use case for that subsystem.

---

*If this file gets out of date, update it as part of the same change
that made it stale. A wrong handoff doc is worse than no doc.*
