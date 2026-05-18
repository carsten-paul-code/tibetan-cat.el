# CLAUDE.md — Agent handoff for tibetan-cat.el

This file briefs Claude Code (or any other Claude surface) picking up
work on **tibetan-cat.el**, Carsten Paul's Emacs-Lisp Computer-Assisted
Translation (CAT) system for Classical Tibetan. Read it in full before
editing. Last updated 2026-05-04 (§5.18 added: per-segment layout
revision for Sanskrit-first reading workflow — Sanskrit grouped above
Tibetan, parent rename `* Auto-Analysis' → `* Tibetan Analysis', level-2
`** Claude Translation' → `** Translation' on both sides, `** Divergence'
→ `** Sanskrit-Tibetan Comparison' always-emitted with `[Faithful — …]'
marker.  Architecture unchanged from §5.17.  Previous: §5.17 two-
language-parallel architecture; §5.10–§5.13 dictionary polish, grammar
unification, thesaurus + target-language pipeline, three-level
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

Current state (2026-05-04): **1839 tests, 1838 expected, 0 unexpected
failures, 1 intentional skip (compound-analysis-callable).**  Carsten
runs this after every change and expects it to stay green.

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

### 5.14 Sanskrit-parallel reading workflow (done, tested, 2026-04-27)

Per-document opt-in parallel-Sanskrit reading mode for the
Yogācārabhūmi class.  Sanskrit is treated as the primary source;
the Tibetan canonical translation is the secondary.  The
analysis pipeline emits a `** Sanskrit Source` section above
Wylie, the Claude prompt becomes Sanskrit-primary with optional
`### Tibetan Divergence` notes, and a toggle command manages the
opt-in header.

Six phases shipped (1 commit each):

1. `cf8b635` — Walker + source-mode predicate
   (`core/tibetan-sanskrit-parallel.el`).  `**** Sanskrit`
   sibling lookup at-cursor and by-id; `--source-mode-parallel-p`
   reads `#+SOURCE_MODE: parallel-sanskrit`.
2. `4e27bdf` — `** Sanskrit Source` rendering, prepended to
   `tibetan-analysis--priority-section-order`.  Emitted only
   when the dynamic var `--sanskrit-text-for-render` is bound
   (caller-controlled gate).
3. `d68f37d` — Claude prompt directive: when `:source-mode` is
   `parallel-sanskrit`, system prompt gains a Sanskrit-primary
   block; user prompt prepends the IAST + Devanagari above the
   Tibetan passage.  Cache-warm: system block constant per doc.
4. `6b84d17` — Markdown `### Tibetan Divergence` →
   `(parent-level + 1)`-star org sub-heading via
   `--claude-body-md-h3-to-org` in
   `--replace-claude-section-body`.  Foldable, navigable.
5. `75eb837` — `tibetan-cat-toggle-source-mode-parallel`
   (`C-c u z P`) + menu.
6. `b33e864` — End-to-end wiring: dynamic var bound from the
   walker on the four real call paths
   (`tibetan-auto-analyze-document`,
   `--open-segment-analysis-impl`,
   `--reanalyze-segment-impl`,
   `tibetan-analysis-reanalyze-file`).

Tests: 61 ERT specs across
`test/tibetan-sanskrit-parallel-test.el` and the existing
prompt / sections test files.

Source files using the workflow: `gotrapatala.org` (97 segments
of Bodhisattvabhūmi) currently.  Other YBh chapters or the
Hausarbeit Tibetisch IV Milarepa work could opt in via
`#+SOURCE_MODE: parallel-sanskrit`.

Design doc: `docs/feature-sanskrit-parallel.org` (not yet
written; see this section for the summary).

### 5.15 DharmaMitra-driven Sanskrit re-alignment (done, tested, 2026-04-30)

Five-phase feature that uses DharmaMitra's public search +
chat-translate APIs to correct the rough daṇḍa-split alignment
of `**** Sanskrit` siblings in parallel-mode documents.
Workflow per segment:  translate Tibetan → English (DM) →
search Sanskrit corpus (DM) → ask Claude to disambiguate
candidates → build proposal (current vs proposed + status) →
preview / apply.

Phases:

1. `307183f` — DharmaMitra HTTP client
   (`core/tibetan-dharmamitra-api.el`): SSE parser, request
   builders, sha256-keyed in-memory cache, error handling.
2. `88385cd` — Per-segment candidates orchestrator
   (`core/tibetan-sanskrit-parallel-dharmamitra.el`):
   `--read-source-metadata` extended with
   `:dm-sanskrit-source` / `:dm-tibetan-source` plist keys
   from `#+DM_SANSKRIT_SOURCE:` / `#+DM_TIBETAN_SOURCE:`
   headers.
3. `4e881d1` — Claude disambiguation: prompt builder, response
   parser (`## Choice` + `## Reason` schema), synchronous
   gptel wrapper outside `tibetan-claude-queue`, top-hit
   fallback with stamped `:reason`.
4. `4b54f7b` — Proposals + walker + preview renderer.
   `tibetan-sanskrit-parallel-dm-realign-document-proposals`
   walks every `**** Segment N` heading; preview buffer
   summarises change / unchanged / no-candidates counts and
   shows per-segment current vs proposed Sanskrit + Claude
   reason.
5. `41689ac` — Writer + apply + interactive commands (initial).
   Source-side writer
   `tibetan-sanskrit-parallel-write-sanskrit-for-segment-id`
   that replaced segment's `**** Sanskrit` sibling body.
   `C-c u z d` segment, `C-c u z D` document; both default to
   preview, `C-u` applies.

6. `31ad7dd` — First design doc + CLAUDE.md + first live test
   on three gotrapatala segments.

7. `9c12060` — **Architectural correction.**  The source-side
   writer was retired.  Live test on segment 5 showed that DM
   segment granularity is coarser than Tibetan segment
   granularity (a 1-line uddāna verse line received a 10-line
   full-chapter-opening replacement).  More fundamentally,
   modifying the user's source from an analysis command
   violates CLAUDE.md §6.  New behaviour: apply mode writes to
   the per-segment analysis file (seg-NNN.org) as a top-level
   `* Sanskrit (DharmaMitra)` section.  Source file is NEVER
   touched (regression-tested).  The new section carries
   DM_SEGMENTNR / DM_RANK / CLAUDE_REASON / LAST_REALIGN in
   its property drawer + the proposed Sanskrit in its body.
   Top-level placement means it survives reanalysis naturally
   without preserve-list changes.

8. `(this commit)` — **Clause extraction polish.**  Phase 7
   wrote the FULL multi-line DM candidate text to the analysis
   file, addressing the source-write violation but leaving the
   granularity mismatch unfixed.  Phase 8 closes the gap:
   Claude's pick prompt schema gains a `## Clause' section;
   parser captures `:chosen-clause' alongside `:chosen-rank' /
   `:reason';  pick output plist carries `:chosen-clause'
   (full `:chosen-text' retained for provenance);
   `--build-proposal' uses `:chosen-clause' for
   `:proposed-sanskrit' when present + non-empty, falls back
   to full text otherwise.  Result: the analysis file's
   `* Sanskrit (DharmaMitra)' body contains just the matching
   line(s), not the full corpus chunk.

Tests: 89 ERT specs across
`test/tibetan-dharmamitra-api-test.el` (19) and
`test/tibetan-sanskrit-parallel-dharmamitra-test.el` (53).

Strict test-first discipline applied throughout: empty stubs
before implementation, run-against-stub to confirm each test
fails with a `should` assertion (not `void-function`),
implement, run-against-implementation to confirm pass.

Design doc: `docs/feature-dharmamitra-realign.org` — quickstart
+ architecture + design decisions + DM API surface findings.

DM endpoint base URL `https://dharmamitra.org/api-search/`,
public bearer `sthiramati` (default — overridable via
`tibetan-dharmamitra-api-token`).  Full OpenAPI spec at
`/api-search/openapi.json` (no auth).

### 5.16 Multi-translator parallel reading (done, tested, 2026-04-30)

Major feature pivot from §5.15's realign work: DharmaMitra is
added as a *translator* alongside Claude in the analysis files,
and Claude in parallel-Sanskrit mode now produces THREE
translation sections (Tibetan / Sanskrit / Combined synthesis)
plus an optional flagged-divergence note.  Per-segment analysis
files in parallel mode now carry up to seven translation-related
artefacts:

| Section                                | Engine | Source   |
|----------------------------------------|--------|----------|
| `* DharmaMitra Translation (Tibetan)`  | DM     | Tibetan  |
| `* DharmaMitra Translation (Sanskrit)` | DM     | Sanskrit |
| `** Sanskrit Source` (raw IAST + Devan)| —      | source   |
| `** Claude Translation`                | Claude | Tibetan  |
| `** Claude Translation (Sanskrit)`     | Claude | Sanskrit |
| `** Claude Translation (Combined)`     | Claude | Both     |
| `** Claude Divergence` (when flagged)  | Claude | Both     |

Non-parallel documents render identically to before — only the
Tibetan-side artefacts appear.  The two top-level DM sections sit
OUTSIDE `* Auto-Analysis` so they survive reanalysis without
preserve-list machinery.

Phases (6 commits, all green):

1. `09cba65` — Phase A.1: DM as Tibetan translator.  New module
   `core/tibetan-dharmamitra-translation.el` with synchronous
   `chat-translate` calls + section writer.  Fires on file
   create via `tibetan-auto-fire-dm-on-create` defcustom
   (default `t`).
2. `a90e6e4` — Phase A.1.5: existing-file open path also fires
   DM when section is missing (predicate
   `--needs-request-p` avoids redoing good translations).
3. `b5d5b43` — Phase A.2: Sanskrit DM fire when source-mode
   parallel-Sanskrit AND segment has a non-placeholder
   `**** Sanskrit` sibling.  Umbrella `fire-for-segment`
   dispatches both languages.
4. `59b2f5e` — Phase A.3: batch DM fire on `C-c u B` and
   `C-u C-c u r`.  Stagger via `tibetan-auto-dm-request-delay`
   (default 0.5s).
5. `c6e4d59` — Phase B: parallel-mode prompt directive +
   `## Translation (Sanskrit)` schema.  Parser, section-order,
   reader, scaffolder.
6. `de1fba0` — Phase C: `## Divergence` opt-in commentary,
   only when Claude flags serious differences.
7. `77e23b4` — Phase D: `## Translation (Combined)` synthesis.
   Reading order: Tibetan → Sanskrit → Combined → Divergence.

Live test on gotrapatala.org seg-005 surfaced two follow-up
concerns:

- **Source alignment was structurally invalid.**  The 2026-04-27
  daṇḍa-split positionally aligned chapter-1 Sanskrit clauses
  with Tibetan segments, but the Tibetan canon's chapter 1 opens
  with translator's homages (segs 1-2) and a 10-dharma framework
  intro + uddāna verse (segs 3-8) that has no counterpart in the
  Dutt-edition Sanskrit (which begins directly with `ṣaḍ
  imāni...`).  The 10 dharmas are the canonical
  *mahāyānasaṃgraha* framework (ādhāra/lakṣaṇa/pakṣa/adhyāśaya/
  vihāra/upapatti/parigraha/bhūmi/caryā/pratiṣṭhā = gzhi/rtags/
  phyogs/lhag-bsam/gnas-pa/skye/yongs-'dzin/sa/spyod/rab-gnas) —
  faithful to a Sanskrit framework, just not one that appears
  in the Dutt etext.

  Fix: `0b19f34` generalized placeholder-marker recognition
  (new `tibetan-sanskrit-parallel--placeholder-text-p`
  predicate; recognises `[Sanskrit alignment pending`, `[Sanskrit
  alignment exhausted`, `[No Sanskrit counterpart`).  Source
  file's all 97 `**** Sanskrit` bodies bulk-marked with
  `[Sanskrit alignment pending …]`.  `52454ad` added
  `M-x tibetan-sanskrit-parallel-reset-sanskrit-sections-in-
  folder` so the wrongly-translated sections in existing
  analysis files can be cleared idempotently.

- **Verb-detect false positives in uddāna verses.**  `སྡོམ` and
  `རྣམས` were classified as verbs in seg-005's Sentence
  Structure block, contradicting Verb Classification's
  `[No Hill-DB verbs detected]`.  Root cause: vocab-fallback
  fired on Bialek glosses starting with `to X` (`to fetter |
  bind...`, `to choke | plural marker`) without checking if
  the rest of the gloss labels the word a particle / marker.

  Fix: `897235c` tightened `--vocab-says-verb-p` to AND its
  verbal-pattern check with a NOT-match against
  `\b(particle|marker|postposition|nominali[sz]er|enclitic)\b`,
  AND tagged minimal entries with `(source . closed-set)` vs
  `(source . vocab-fallback)`.  The clause-structure renderer
  now filters vocab-fallback entries before clause segmentation,
  restoring symmetry with Verb Classification.  Curated closed-
  set verbs (`གསོལ`, `མཛད`, `བྱུང`, …) still drive clauses.

Tests: 51 new ERT specs across the work series (Phase A.1: 14;
A.2: 8; A.3: 6; B: 10; C: 9; D: 10; placeholder: 8; reset: 6;
verb-detect: 6).

Suite progression today (all green): 1734 → 1744 (B) → 1753 (C)
→ 1764 (D) → 1772 (placeholder) → 1778 (reset) → **1784**
(verb-detect).

Design doc: `docs/feature-multi-translator-parallel-reading.org` —
phase walkthrough + reader-flow ordering + alignment workflow +
why automated realign couldn't fix gotrapatala + verb-detect
fix root-cause + commit trail.

**SUPERSEDED 2026-04-30 by §5.17.**  The Phase B–D suffixed
schema (`** Claude Translation (Sanskrit)' / `(Combined)' /
`** Claude Divergence' INSIDE `* Auto-Analysis') is retired.
Sanskrit and Combined output now live in dedicated top-level
sections via three independent Claude calls.  See §5.17 for
the new architecture.

### 5.17 Two-language parallel analysis (done, tested, 2026-04-30 — superseded by §5.18)

**SUPERSEDED 2026-05-04 by §5.18.**  The per-segment file layout
described below was reorganised for the Sanskrit-first reading
workflow:  parent heading rename `* Auto-Analysis' → `* Tibetan
Analysis'; level-2 `** Claude Translation' → `** Translation' on
both Tibetan and Sanskrit sides; section reorder Sanskrit-first;
`** Divergence' (opt-in) → `** Sanskrit-Tibetan Comparison'
(always-emitted with `[Faithful — …]' marker for faithful
renderings).  Architecture (three Claude calls, walker, queue,
dispatcher) unchanged.  See §5.18 for the layout-revision details.

**Architectural elevation** of yesterday's §5.16 work.  After
§5.16's seg-005 live test surfaced a Combined-translation
duplication bug (the parallel-mode prompt asked Claude for a
Combined section even when only Tibetan input was present),
Carsten asked for Sanskrit to become a first-class peer of
the Tibetan analysis with a dedicated synthesis layer above
both — instead of a sibling section inside the Tibetan
analysis file.

Per parallel-Sanskrit segment, three independent top-level
analysis sections in one `seg-NNN.org` file:

| Section                   | Producer                       | Pre-existing? |
|---------------------------|--------------------------------|---------------|
| `* Auto-Analysis`         | Claude (Tibetan call)          | yes (slimmed) |
| `* Sanskrit Text`         | walker (raw IAST + Devanagari) | NEW (Phase 3) |
| `* Sanskrit Analysis`     | Claude (Sanskrit call)         | NEW (Phase 2) |
| `* Combined Analysis`     | Claude (Combined call)         | NEW (Phase 4) |

Plus the three pre-existing top-level DM sections (`*
DharmaMitra Translation (Tibetan)' / `(Sanskrit)' / `*
Sanskrit (DharmaMitra)').

**Phases (two commits):**

1. `a5caeac` — Phases 1+2+3+4 bundled.
   - Phase 1: retired the §5.16 parallel-mode block
     instructions from the Tibetan prompt + the suffixed
     parser keys / scaffolders / section-order entries.
     Tibetan call now byte-identical for parallel and non-
     parallel docs.
   - Phase 2: NEW `persist/tibetan-analysis-sanskrit.el` —
     Sanskrit Claude pipeline (5-section response: Translation
     / Devanagari / Sandhi / Word List / Grammar).
   - Phase 3: `--render-sanskrit-source' rewritten to emit
     `* Sanskrit Text' top-level (was `** Sanskrit Source'
     under `* Auto-Analysis').
   - Phase 4: NEW `persist/tibetan-analysis-combined.el' —
     Combined synthesis pipeline (2-section response:
     Translation / Divergence; both gated on all four inputs
     being present).

2. `9802833` — Phase 5: dispatcher + reanalyse preservation.
   - New `tibetan-analysis--fire-parallel-mode-claude-calls'
     orchestrates Sanskrit + (chained) Combined.  Wired into
     `reanalyze-file' + auto-analyze batch + auto-fire-on-
     create batch.
   - `--get-user-sections' / `--regenerate-auto' extended to
     preserve the six new top-level sections.  Closes a
     latent regression where DM sections were silently
     destroyed by every reanalyse-without-refire.

**Three Claude calls in parallel mode:**

| Call     | Module                                      | Schema |
|----------|---------------------------------------------|--------|
| Tibetan  | `tibetan-analysis-claude.el` (slimmed)      | `## Translation` / `## Vocabulary` / `## Grammar` / `## Particles` |
| Sanskrit | `tibetan-analysis-sanskrit.el` (NEW)        | `## Translation` / `## Devanagari` / `## Sandhi` / `## Word List` / `## Grammar` |
| Combined | `tibetan-analysis-combined.el` (NEW)        | `## Translation` / `## Divergence` (the latter only when serious differences) |

Each call's system prompt is constant per document.  Anthropic
prompt cache stays warm for each call type independently.
Tibetan + Sanskrit fire concurrently; Combined chains off
Sanskrit's callback when both translations are present.

**Section independence:** each top-level analysis section is
owned by one call type — Tibetan reanalyse touches only `*
Auto-Analysis`, Sanskrit reanalyse only `* Sanskrit Analysis',
etc.  Same pattern as today's DM top-level sections.

**Reanalyse preservation (regression fix):**  before this
work, `--get-user-sections' didn't list the DM sections
(shipped Phase A.1–A.2 earlier today), so reanalyse-without-
refire silently destroyed them.  Phase A.3 masked the bug
because batch reanalyse typically runs with refire on.  Phase
5 extends the section list with all six new top-level names
\(Sanskrit Text, Sanskrit Analysis, Combined Analysis, three
DM variants).

**Migration of existing analysis files:** soft.  Existing
files keep their current layout until next reanalyse — at that
point the Tibetan side regenerates without the now-retired
suffixed sections, the Sanskrit/Combined sections appear on
re-fire, and the prior file's top-level sections are
preserved.  Phase 6 (a migration helper to drop the now-inert
`** Claude Translation (Sanskrit)' / `(Combined)' / `**
Claude Divergence' subsections lingering inside `* Auto-
Analysis' from yesterday's §5.16 work) is **deferred** —
pairs with the analysis-files refactoring Carsten plans.

**Suite trajectory:** 1792 (post-§5.16 + verb-detect work) →
1755 (Phase 1 retire) → 1771 (Phase 2 add) → 1769 (Phase 3
update) → 1783 (Phase 4 add) → **1787** (Phase 5 add).  Net
−5 because Phase 1 retired more tests than the new modules
added.  For a refactor that retires schema, lower-but-tighter
is the right outcome.

Design doc: `docs/feature-two-language-parallel.org` — full
phase walkthrough + per-segment file layout diagram + the
three Claude system-prompt drafts + dispatcher mechanics +
preservation invariants + verification recipe + commit trail.

### 5.18 Per-segment layout revision (Sanskrit-first reading, done, tested, 2026-05-04)

**Layout-only revision of §5.17.**  Architecture is unchanged
(three Claude calls per parallel-Sanskrit segment; walker +
queue + dispatcher all preserved).  This work reorganises the
on-disk shape of the per-segment analysis file to match the
class workflow:  Yogācārabhūmi reading reads the Sanskrit FIRST,
translates it, then checks the Tibetan against it.  Three
specific user-facing pain points:

1. Tibetan was first in the file order, with Sanskrit
   interleaved — wrong reading order.
2. Both `* Auto-Analysis' and `* Sanskrit Analysis' carried
   level-2 `** Claude Translation' — students couldn't tell at
   a glance which language a translation was in.
3. `** Divergence' was opt-in; faithful renderings produced
   no comparison section, so the reader couldn't tell whether
   comparison was performed.

#### Target on-disk layout

```
* My Notes                                    user-edited
* Working Translation                         user-edited

* Sanskrit Text                               raw IAST + Devanagari
* Sanskrit Analysis
  ** Devanagari                               (conditional)
  ** Sandhi Decomposition                     (conditional)
  ** Word List
  ** Translation                              ← was ** Claude Translation
  ** Grammar

* Tibetan Text                                raw Tibetan
* Tibetan Analysis                            ← was * Auto-Analysis
  ** Wylie Transliteration
  ** Interlinear Gloss
  ** Translation                              ← was ** Claude Translation
  ** Grammar
    *** Particle Map
    *** Claude Grammar                        (level-3, kept)
    *** Particles in This Segment
  ** Sentence Structure / Verb Classification / Detailed Dictionary
  ** Provided Translations
    *** Claude Vocabulary                     (level-3, kept)
    *** Claude Particles                      (level-3, kept)

* Combined Analysis
  ** Combined Translation
  ** Sanskrit-Tibetan Comparison              ← always emitted
                                                 ([Faithful — …] marker
                                                 when faithful)

* Footnotes                                   user-edited

* DharmaMitra Translation (Sanskrit)          ← Sanskrit-DM first now
* DharmaMitra Translation (Tibetan)
* Sanskrit (DharmaMitra)                      legacy realign output
```

#### Heading rename table

| Old (§5.17)              | New (§5.18)                      |
|--------------------------|----------------------------------|
| `* Auto-Analysis`        | `* Tibetan Analysis`             |
| `** Claude Translation`  | `** Translation` (both sides)    |
| `** Divergence`          | `** Sanskrit-Tibetan Comparison` |

Level-3 sub-headings under `** Grammar' / `** Provided
Translations' KEEP their `Claude' prefix:  `*** Claude
Vocabulary', `*** Claude Particles', `*** Claude Grammar'.
The prefix still disambiguates among multiple level-3 cousins
(DharmaMitra / Roehrich / Reference Translations).

#### Phases (13 commits, +30 tests)

| Phase | Commits | Tests | Description |
|-------|---------|-------|-------------|
| 1.1   | 1       | +2    | `--get-user-sections' lists Tibetan Analysis |
| 1.2   | 1       | +2    | Writers emit `* Tibetan Analysis` (paragraph carve-out kept) |
| 1.3   | 1       | +3    | Tibetan-side `** Claude Translation` → `** Translation` |
| 1.4   | 1       | +3    | Sanskrit-side same rename |
| 1.5   | 1       | +2    | Dispatcher reads `** Translation` for chained Combined call |
| 2.1   | 1       | +5    | Sanskrit-first section reorder in `regenerate-auto` + `create-file` |
| 3.1+2 | 1       | +8    | Combined parser/writer rename + on-disk migration |
| 3.3+4 | 1       | +5    | Combined system prompt always-emit + faithful marker + end-to-end |
| 4.1–3 | 3       | +0    | CLAUDE.md §5.18 + cross-doc sweep |

#### Migration story

**Dual-name parsers + new-name-only writers.**  Every reader
accepts both old and new heading names (preferring new); every
writer emits only the new name.  On first reanalyse of an OLD
file, the preserved-content path picks up bodies from old
headings, the regenerator emits using new headings — natural
one-pass migration, no manual sweep, no scripted batch.

Every rename has an in-place migration helper called from the
appropriate insert/restore entry point:
- `tibetan-analysis--migrate-legacy-claude-headings' renames
  level-2 `** Claude Translation' → `** Translation' (Tibetan
  side, segment layout only).
- `tibetan-analysis-sanskrit--migrate-legacy-translation-heading'
  same for Sanskrit-side.
- `tibetan-analysis-combined--migrate-legacy-divergence-heading'
  renames `** Divergence' → `** Sanskrit-Tibetan Comparison'.
- `regenerate-auto' rewrites `* Auto-Analysis' → `* Tibetan
  Analysis' on the next reanalyse pass.

All migrations are idempotent.  `--get-user-sections' lists both
old and new section names so the regenerator's alist consumer
sees the new heading on already-migrated files.

#### Carve-outs (deliberately untouched)

- **Sentence files (`sent-NNN*.org`):** ALIGNED with segment
  shape as of 2026-05-18 (the original §5.18 carve-out is retired
  — see "Sentence-file alignment" subsection below).  Sentence
  files now use `* Tibetan Analysis' parent, `** Translation' at
  level-2, nested `** Provided Translations' with sentence-only
  `*** Roehrich' / `*** Class Translation' / `*** Claude Context'
  alongside `*** Claude Vocabulary' / `*** Claude Particles'.
- **Paragraph files (`par-NNN.org`):** keep `* Auto-Analysis'.
  Different flow; not parallel-Sanskrit.
- **Compound analysis (`tibetan-compound-analysis.el`):** keeps
  `* Auto-Analysis'.  Multi-verb verse workflow, separate.

#### Sentence-file alignment (2026-05-18 follow-up)

The original §5.18 work carved sentence files out because their
discourse-level Claude pipeline (3 sections: Translation /
Grammar / Context) is distinct from the segment-level word-by-
word pipeline (4 sections: Translation / Vocabulary / Grammar /
Particles).  A subsequent user request — "I want sentence files
in the equal form like segment files" — drove a follow-up
alignment.

What aligned:
- Parent rename `* Auto-Analysis' → `* Tibetan Analysis'.
- User sections (My Notes, Working Translation) moved from
  BOTTOM to TOP (matching segment §5.18 ordering).
- Top-level `* Provided Translations' DROPPED;  the level-3
  entries (Roehrich, Class Translation, Claude Context) moved
  INSIDE a nested `** Provided Translations' under `* Tibetan
  Analysis'.
- Sentence-level Claude Translation promoted from level-3
  (`*** Claude Translation') to level-2 (`** Translation') —
  matches segment's primary slot.
- Footnotes stays at the BOTTOM.

Mechanics:
- `tibetan-sentence--segment-claude-sections' strip-list emptied;
  the segment-renderer's `** Translation' and `** Provided
  Translations' subtrees now flow through to the sentence file's
  `* Tibetan Analysis' body unchanged.
- `tibetan-sentence--inject-sentence-l3-entries' appends `***
  Roehrich' / `*** Class Translation' / `*** Claude Context' to
  the nested `** Provided Translations' block.
- `tibetan-sentence--regenerate' rebuilt to use a PRESERVE →
  REBUILD-via-scaffold → RESTORE pattern.  Reads bodies from
  legacy positions, scaffolds fresh, restores into new positions.
- `tibetan-analysis--claude-segment-layout-p' detector updated
  to recognise the new aligned sentence layout (presence of
  `* Tibetan Analysis' parent) as segment-shape for migration
  purposes.  Legacy sentence files (with `* Auto-Analysis' or
  top-level `* Provided Translations') still classify as sentence-
  shape so the Claude writer uses the level-3 layout expected
  by the pre-migration files.
- `tibetan-analysis--claude-section-order' extended with
  `(:context "Claude Context" 3)' so the writer can place the
  sentence-only Context body.  Segment Claude responses don't
  produce Context — the writer just skips it.

Migration:  on first `--regenerate' the old layout (Auto-Analysis
+ top-level Provided Translations + bottom user sections) is
rewritten into the new layout, preserving user-edited bodies
verbatim.  Idempotent — re-running on an already-migrated file
produces identical output.

#### Cache impact

Tibetan + Sanskrit Claude system prompts byte-identical pre/post
refactor — Anthropic prompt cache stays warm.  Only Combined
prompt changes in Phase 3.3 (one-time cache miss on the first
Combined call after the commit lands; subsequent calls re-cache
at the usual 10% input cost — bounded to one segment per active
Combined batch).

#### Suite trajectory

1809 (post-§5.17 + DSBC alignment + cleanup work) → 1811 (Phase
1.1) → 1813 (1.2) → 1816 (1.3) → 1819 (1.4) → 1821 (1.5) → 1826
(2.1) → 1834 (3.1+3.2) → **1839** (3.3+3.4).  Monotonic growth;
zero unexpected failures at any phase boundary.

#### Verification recipe

Run after migration ships:

1. `cd /Users/cp/tibetan-cat.el/test && emacs -batch -l
   run-all-tests.el -f ert-run-tests-batch-and-exit` → 1839
   pass / 0 unexpected / 1 intentional skip.

2. **Live migration**.  On a copy of the gotrapaṭala
   `analysis/` folder (~97 seg-NNN.org files):
   - `M-x tibetan-analysis-batch-reanalyze` with
     `:re-request-claude nil`.
   - Spot-check three random files:  confirm new top-level
     order (My Notes / Working Translation at top, Sanskrit
     pair before Tibetan pair, DM Sanskrit before DM Tibetan),
     `* Tibetan Analysis' parent heading, `** Translation'
     (both sides), `** Sanskrit-Tibetan Comparison' present.
   - `git diff` on the analysis folder:  heading renames +
     section reorder + `** Divergence' → `**
     Sanskrit-Tibetan Comparison', no lost user content.

3. **Live re-fire**.  Pick one segment, re-fire with
   `:re-request-claude t` to confirm the Combined Claude call's
   new prompt produces a non-empty `** Sanskrit-Tibetan
   Comparison' body on a previously faithful-rendering segment
   (the `[Faithful — …]' marker should appear).

4. **Idempotency**.  Re-run batch reanalyse a second time; diff
   should be empty modulo whitespace + LAST_ANALYZED stamps.

5. **Carve-out**.  Reanalyse a sentence file; confirm `*
   Auto-Analysis' stays unchanged.

#### Files changed

| Path | Role |
|------|------|
| `persist/tibetan-analysis-persist.el` | `regenerate-auto` reorder + parent rename, `create-file` reorder, `--get-user-sections` extension, `--fire-parallel-claude-with-plist` translation-readback chain |
| `persist/tibetan-analysis-claude.el` | `--claude-section-order` (segment) `Translation` rename, `--migrate-legacy-claude-headings` extension, `--insert-claude-translation-heading` rewrite + new fallback, `--ensure-claude-headings` dual-name accept, `--write-comparison-section` regex, `--write-claude-failure-stub` layout-aware dispatch, `--read-claude-sections` chain |
| `persist/tibetan-analysis-sanskrit.el` | `--section-order` `Translation` rename, `--migrate-legacy-translation-heading` helper, `--read-sections` fallback |
| `persist/tibetan-analysis-combined.el` | `:divergence` → `:comparison` parser key, `--section-order` `Sanskrit-Tibetan Comparison` rename, `--migrate-legacy-divergence-heading` helper, `--read-sections` fallback, `--system-prompt-base` rewrite (always-emit + `[Faithful — …]` marker) |
| `persist/tibetan-analysis-combine.el` | `--read-auto-sections` regex multi-name accept |
| `persist/tibetan-sentence-persist.el` | strip-list extended with `** Translation` for segment embeds |

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

### P5 — Root-cause the `gyur pa'o' parser crash ✓ DONE 2026-04-30
Bisect via instrumented checkpoints found the signal site: the
Section 2 vocab-pairs loop's first `short-meaning' binding.

Root cause: `tibetan-vocab-multisource-entries' returned a
detailed-entry whose `:primary' field was an empty string `""'.
`raw-meaning' became `""' (truthy in elisp), `(when raw-meaning
…)' entered the body, `(car (split-string "" ";" t))' returned
nil, and `(string-trim nil)' raised `Wrong type argument:
stringp, nil'.

The outer condition-case caught it and emitted the
`[Analysis error — partial file only]' fallback for these
segments (note: the original CLAUDE.md report cited
`(wrong-type-argument listp "གྱུར")' from `cl-remove' — likely
a different earlier symptom; the current crash is the
stringp-on-nil one above).

Fix: empty-string guard at the top of the FIRST short-meaning
let — short-circuit empty raw-meaning to nil so the binding
becomes nil and the downstream chain follows the same path as
a missing dictionary entry.  Patch in
`persist/tibetan-analysis-persist.el` Section 2 vocab-loop.

Tests: `tibetan-analysis-generate-content-gyur-pao-no-fallback'
asserts (a) full Section 1..8 layout is generated, (b)
fallback template's `[Analysis error]' marker is absent, (c)
all 8 user-facing section headings are present.

Suite total at fix: 1791 → 1792, 0 unexpected, 1 skipped.

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
   (expect 1787 / 1786 expected / 0 unexpected / 1 skipped at 2026-04-30).
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
