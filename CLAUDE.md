# CLAUDE.md — Agent handoff for tibetan-cat.el

This file briefs Claude Code (or any other Claude surface) picking up
work on **tibetan-cat.el**, Carsten Paul's Emacs-Lisp Computer-Assisted
Translation (CAT) system for Classical Tibetan. Read it in full before
editing. Last updated 2026-05-26 (§5.26: BUG fix — regenerate-
auto preserves Claude content under `:missing-only' too;
`(not re-request-claude)' was treating `:missing-only' as
truthy → wipe.  Caused 274 / 287 Milarepa segs to lose Claude
content on a 2026-05-24 batch run.  Fix:  preserve unless
`re-request-claude' is the symbol `t'.  267 files restored
from git blob `bc5cbe9' (the buddhist-studies/ folder is git-
tracked).  Regression test locked in.  Previous: §5.25 added:
thesaurus zettel
cross-link in Concept Notes — Claude cites `[[id:ZID][zettel ↗]]'
inline for any term that has a curated zettel in
`~/Documents/tibetan-thesaurus/';  writer post-processes the
response as a safety net.  §5.24 added: `** Concept
Notes' replaces `*** Claude Context' — class-reading aid that
surfaces Buddhist + Sanskrit technical concepts with encyclopedia
notes instead of the old narrative-arc commentary.  Heading
promoted from L3 to L2 (segment + sentence).  Migration
automatic on first regenerate.  Previous:  §5.23 added: per-source
filename suffix `seg-NNN-SHORT.org' for ALL new analysis files;
fixes silent multi-source overwrite in MA Reading folder.
Migration helper `tibetan-analysis-migrate-suffix-in-folder'
renames existing files based on each file's `#+SOURCE:' link.
Ran on Yogācārabhūmi (96) + MA Reading (39); created + Claude-
filled 23 previously-overwritten MA Reading segs.  Previous:
§5.22 final: sentence-analysis
files unconditionally render the in-class compressed layout —
Vocabulary + Translation + Grammar (with the converb-rich
`*** Particles' section) + Provided Translations only;  7
reference sections stripped (Wylie / Phonetics / Interlinear /
DharmaMitra / Sentence Structure / Verb Classification /
Detailed Dictionary).  The opt-in machinery from §5.22 initial
(`#+TIBETAN_SENTENCE_COMPRESSED:' header + `C-c u z C' toggle +
dynamic var + metadata-reader key) is RETIRED.  Per-segment
seg-NNN.org keeps the full §5.21 layout — clean split of class-
reading vs deep-analysis surfaces.  Also: `#+OPTIONS: toc:nil
num:nil' on all analysis-file scaffolds.  Previous: §5.21 Mid-
class Cleanup (CAT Gloss retired, Claude Vocabulary promoted
to level-2, Particle Map + Particles merged with Bialek 2022
refs, Detailed Dictionary moved to bottom, Provided
Translations user-content); §5.20 DM-Tibetan nested; §5.19
Phonetics; §5.18 Sanskrit-first layout revision; §5.17 two-
language-parallel architecture; §5.10–§5.13 dictionary polish,
grammar unification, thesaurus + target-language pipeline,
three-level dispatch).

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
├── Makefile      `make test` = ERT (test-quick) + BDD (test-bdd)
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

The project has TWO suites:

- **ERT** — the unit / regression tests in `test/`.  This is the
  primary gate.
  ```sh
  cd test
  emacs -batch -l run-all-tests.el -f ert-run-tests-batch-and-exit 2>&1 | tail -25
  ```
  Or `make test-quick` from the project root.
- **BDD** — the behaviour specs in `spec/`.  `make test-bdd`, or
  `./run-specs.sh`.

`make test` runs **both** (`test-quick` then `test-bdd`) and stops on
the first failure — this is the full batch suite.  (Before 2026-06-01
`make test` ran only the BDD specs and its `-f tibetan-bdd-run-all-specs`
flag named a non-existent function that never executed; the spec suite
also made a live dharmamitra.org request on every run.  Both fixed.)

Current state (2026-06-03, post-§5.36 shad markers):  **ERT
2138 tests, 2137 expected, 0 unexpected, 1 intentional skip
(compound-analysis-callable); BDD 244 / 244.**  Full `make compile` is
clean (zero warnings).  Carsten runs `make test` after every change and
expects it to stay green.

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

### 5.19 Phonetics section below Wylie (THL, Lhasa, 2026-05-19)

Class-reading aid.  Wylie alone is unforgiving when the
student just needs to vocalise a line;  THL Simplified
Phonetic Transcription (Germano & Tournadre 2003)
approximates Lhasa pronunciation in Wylie-friendly Roman
orthography (sh / ch / zh / ng).  Sits at level-2 directly
under `** Wylie Transliteration' in every per-segment AND
per-sentence analysis file (segment renderer flows through
the shared `tibetan-analysis-generate-content' pipeline).

#### Layout

```
* Tibetan Analysis
  ** Wylie Transliteration
  bkra shis bde legs phun sum tshogs

  ** Phonetics                              ← NEW (auto-generated)
  tra shi de lek phün sum tshok

  ** Interlinear Gloss
  …
```

#### Module

`core/tibetan-phonetics.el' (~370 lines + 46 ERT specs).
Public entry points:

  - `tibetan-to-phonetics (TEXT)` — Tibetan Unicode OR Wylie
    input;  returns space-separated THL string, shad-preserving,
    nil-safe.
  - `tibetan-wylie-syllable-to-phonetic (WYLIE-SYL)` — single-
    syllable converter, exposed for thesaurus UI + tests.
  - `tibetan-phonetics--curated-override (WYLIE)` — looks up
    a `:phonetics:' field on a thesaurus zettel;  when present,
    takes precedence over the rule engine.

#### Algorithm

Per syllable:
1. Parse into prefix / superscript / root / subscript / vowel /
   suffix / post-suffix using validated combo tables
   (`--valid-prefix-combos', `--valid-super-combos') to
   disambiguate cases like `by-' (root b + y-subscript, NOT
   prefix b + root y).
2. Map initial cluster (root + subscript) to THL initial via
   `--cluster-overrides' table (palatalisations like `by → j',
   retroflexes like `kr → tr', etc.).  Prefix + superscript
   silently drop.
3. Apply vowel umlaut when suffix ∈ {i, e, n, l, d, s}.
   Post-suffix is NEVER an umlaut trigger (so `tshogs' with
   suffix `g' + post-suffix `s' stays unumlauted → `tshok',
   while `chos' with suffix `s' alone umlauts → `chö').
4. Apply final consonant rules:
   - `-ng' / `-m' kept
   - `-g' (+ silent `-s') → `-k'
   - `-b' → `-p' (final devoicing)
   - `-n' / `-l' kept (visual cue post-umlaut)
   - `-s' / `-d' / `-'` / `-r' silent

#### Tone marking

THL formal documents distinguish high/low tone via diacritics
(`á' vs `à').  This implementation OMITS tone — consistent
with simplified renderings in most published THL texts.  Tone
can be inferred from the prefix/superscript when needed;
omitting it keeps the phonetic line readable.

#### Curated overrides

When the rule engine produces wrong output for a specific
word (Madhyamaka terms, Sanskrit loanwords, monastic-tradition
readings), the fix is to populate the per-word thesaurus
zettel's `:phonetics:' field — not to complicate the rules
table.  The override path checks for this field and uses it
verbatim when present.

#### Wiring

- `tibetan-analysis--priority-section-order' (in
  `persist/tibetan-analysis-persist.el', line 2948+) extended
  with `"** Phonetics"' at position 2 (right after Wylie).
- `tibetan-analysis-generate-content' (~line 3308) inserts
  the heading + body inline with the Wylie pass.  Soft-required
  — emits `[Phonetics not available]' when the converter
  module isn't loaded.
- Sentence files inherit automatically via
  `tibetan-sentence--render-auto-analysis' (sentence renderer
  re-uses the segment generator).
- Top-level `(require 'tibetan-phonetics)' in `tibetan-cat.el'.

#### Suite trajectory

1882 → 1929 / 1928 expected / 0 unexpected / 1 skipped.  46
phonetics specs + 1 integration spec.  BDD 244 / 244.  Lint
clean.

#### Live spot-check (seg-049, Tibetisch IV)

Wylie:  `khyed rang sgor shog dang  mdang mkha' 'gro chos
skyong rnams ngo so zla ba bzhin phyar nas/'

Phonetics:  `khye rang go shok dang dang kha dro chö kyong
nam ngo so da ba zhin cha ne/'

Readable, faithful to Lhasa pronunciation;  `'gro' →  `dro'
(retroflex r-subscript), `chos' → `chö' (umlaut), `mdang' →
`dang' (m-prefix silent, homophone with `dang').

### 5.20 DharmaMitra Tibetan next to Claude Translation (done, 2026-05-19)

Layout-only revision:  the top-level `* DharmaMitra
Translation (Tibetan)' section moved INSIDE `* Tibetan
Analysis' as a level-2 sibling of `** Translation' (Claude).
Reader gets both AI translations side-by-side under one parent
heading instead of one at the top and one at the bottom of the
file.  Sanskrit-side DM stays at top-level (parallel-mode
only).

Mechanics:  new `tibetan-dharmamitra-translation--write-
nested-tibetan-section' writer locates the nested slot and
overwrites the body atomically;  `--read-dharmamitra-tibetan-
nested-body' reader pulls the body from the new location;
`regenerate-auto' reads BEFORE buffer erase, writes BACK after
save.  Same dual-name preserve pattern as §5.18:  legacy
top-level body still preserved on first regenerate, then
migrated to the new nested location.

### 5.21 Per-segment layout revision — Mid-class Cleanup (done, 2026-05-20)

Class-use feedback after §5.18 / §5.19 / §5.20 layout-revisions:
the per-segment file flows better than before but five concrete
frictions remained.  Each was small in isolation;  together
they pushed the file into the shape Carsten wants for the
Tibetisch IV Milarepa class reading.

#### Target on-disk layout (post-§5.21)

```
* My Notes                            user-edited (preserved)
* Working Translation                 user-edited (preserved)
* Tibetan Text                        raw Tibetan
* Tibetan Analysis
  ** Wylie Transliteration
  ** Phonetics
  ** Interlinear Gloss
  ** Claude Vocabulary                ← MOVED from Provided Translations
  ** Translation                      Claude
  ** DharmaMitra Translation          peer of Translation
  ** Grammar
    *** Particles                     ← MERGED (Particle Map + Particles
                                        in This Segment) with Bialek 2022
                                        textbook refs in the bullet bracket
    *** Claude Grammar                Claude prose, kept
  ** Sentence Structure
  ** Verb Classification (Hill 2010)
  ** Provided Translations            ← USER-CONTENT; preserved across
                                        regenerate (Carsten pastes
                                        Roehrich / Lopez here)
  ** Detailed Dictionary              ← MOVED to bottom (reference, not
                                        flow)
* Footnotes                           user-edited (preserved)
* DharmaMitra Translation (Sanskrit)  parallel-mode only
* Sanskrit (DharmaMitra)              parallel-mode only
```

#### Commits (7 commits)

| Commit | Subject                                                | Tests |
|--------|--------------------------------------------------------|-------|
| 1/7    | `*** CAT Gloss' + 248-line composer retired            | +2    |
| 2/7    | `** Claude Vocabulary' promoted to level 2 below Interlinear | +3 |
| 3/7    | `*** Particle Map' + `*** Particles in This Segment' merged into `*** Particles' | +2 (updated) |
| 4/7    | Bialek 2022 published-textbook refs added to particle bullets | +4 |
| 5/7    | `** Detailed Dictionary' moved to bottom of `* Tibetan Analysis' | +2 |
| 6/7    | `** Provided Translations' becomes user-content (preserved across reanalyze) | +3 |
| 7/7    | CLAUDE.md §5.21 + final verification                   | docs  |

Each commit is a single logical change per CLAUDE.md §2.4 and
follows the §5.18 / §5.19 / §5.20 layout-revision mechanics
(dual-name parsers + new-name writers + migration helpers,
signed off three times before this batch).

#### Particle bullet shape (Commits 3+4)

```
*** Particles
=CASE= (magenta) · ~CONVERB~ (orange) · Ø zero-marked

khyed rang sgor shog =dang=  mdang mkha' 'gro ... =gyi= ... ~nas~

- དང [dang] · COMITATIVE (COM)
    [Bialek 2022 §1.7 (Comitative); Portfolio §1.9]
    §1.7.1 Accompaniment — the comitative links two nouns that
    co-participate in an event or state.

    - byams pa dang snying rjer ldan te
      "endowed with kindness and compassion"  (LBRG)

- ནས [nas] · CONVERBIAL: ABLATIVE CONVERB
    [Bialek 2022 §2.11 (V+nas); Portfolio §2.11]
    §2.4 approx-sequential
```

Visual skeleton at the top of the merged section, per-particle
bullets below.  Each bullet's bracket carries BOTH `Bialek 2022
§X.Y (Title)' (published textbook, canonical numbering, via the
new `philology/tibetan-bialek-textbook-refs.el' alist) AND
`Portfolio §X.Y' (Carsten's hand-written zettel, may differ
from the textbook numbering).  Either side may be absent →
bracket falls back to whichever is available.  Portfolio sub-
function snippet inlined below the bullet (existing Pass 6c
behaviour preserved).

#### Provided Translations preservation (Commit 6)

Renderer emits `** Provided Translations\n\n\n' as a pristine
empty placeholder.  `tibetan-analysis--read-provided-
translations-nested-body' reads the existing body BEFORE the
buffer is erased;  `tibetan-analysis--write-nested-provided-
translations-body' restores it AFTER save.  Same pattern as
the §5.20 DharmaMitra Tibetan nested body.

`*** Reference Translations' auto-fill (which used to pull
external PDF text from Resources) retired — Carsten now pastes
reference translations manually, and the new preservation
machinery keeps them verbatim across regenerate.  Paragraph-
mode files (`par-NNN.org') still get top-level `* Reference
Translations' from
`tibetan-analysis-create-paragraph-file' (unchanged).

#### Deferred (per AskUserQuestion during plan mode)

Two specific improvements were explicitly deferred to keep the
batch layout-only:

- **Zero-marker (Ø) function improvements in the particle
  skeleton.**  The current `Ø zero-marked' rendering correctly
  marks unmarked clausal positions but the heuristic for which
  positions to mark is hand-tuned and occasionally surfaces a
  spurious `Ø' on transitive subjects.  Layout is correct;
  body needs work in a follow-up.
- **Detailed Dictionary per-entry rendering polish.**  The
  multi-source block from §5.3 is correct but visually dense.
  Improvement deferred — moving the section to the bottom
  (Commit 5) is the layout-level win;  per-entry tuning is a
  separate polish pass.

#### Suite trajectory

1929 (post-§5.20) → 1938 (Commit 1, +2 -1 retire) → 1938
(Commit 2, +3 -3 retire) → 1938 (Commit 3, +2 updated) →
1942 (Commit 4, +4) → 1944 (Commit 5, +2) → **1947** (Commit 6,
+3) / 1946 expected / 0 unexpected / 1 skipped.  Plus BDD
specs 244 / 244 unchanged.

#### Verification recipe

After Commit 7 lands:

1. `cd /Users/cp/tibetan-cat.el && make test` (or the batch
   command from §4) → 1947 / 1946 expected / 0 unexpected /
   1 skipped.  `make compile` clean (no new warnings).

2. **Live regenerate.**  On the Tibetisch IV / Milarepa
   analysis folder:
   - `M-x tibetan-analysis-batch-reanalyze` with
     `:re-request-claude nil` (preserve Claude content;  the
     new layout takes effect, Claude content lands in the new
     slots).
   - Spot-check seg-049:
     - `*** CAT Gloss' heading absent.
     - `** Claude Vocabulary' heading present, level 2, AFTER
       `** Interlinear Gloss', BEFORE `** Translation'.
     - `*** Particles' heading present;  `*** Particle Map'
       and `*** Particles in This Segment' absent.
     - Particle bullet for `nas' shows `[Bialek 2022 §2.11
       (V+nas); Portfolio §2.11]'.
     - `** Provided Translations' heading present but EMPTY
       body (or carrying just Carsten's hand-paste, no auto-
       children).
     - `** Detailed Dictionary' is the LAST `** ' heading
       inside `* Tibetan Analysis'.

3. **User-content preservation test.**  Paste a reference
   translation into `** Provided Translations' on a seg file,
   re-run `C-c u R' on that segment, confirm paste survives.

4. **Export safety.**  `M-x org-html-export-to-html' on a
   regen'd seg file succeeds (the §5.18 dangling-term-link
   strip + the §5.21 layout integration both fire).

5. **Idempotency.**  Re-run `batch-reanalyze' a second time;
   diff should be empty modulo `:LAST_ANALYZED:' timestamps.

Yogācārabhūmi explicitly deferred per Carsten's "for the
moment only Milarepa is urgent" comment.

#### Files changed (across all 7 commits)

| Path | Role |
|------|------|
| `persist/tibetan-analysis-persist.el` | Renderer, regenerate-auto, scaffold, priority section order, particle skeleton + bullets + grammar section, detailed dictionary placement, provided translations nested read/write |
| `persist/tibetan-analysis-claude.el` | Claude section-order (Vocabulary → level 2), `--migrate-legacy-claude-headings' Step 4, `--insert-claude-vocabulary-heading' helper, `--merge-claude-vocabulary' retired, `--place-claude-grammar-heading' updated for merged `*** Particles' |
| `philology/tibetan-bialek-textbook-refs.el` (NEW) | Defconst alist + `tibetan-bialek-textbook-ref' lookup helper |
| `test/tibetan-analysis-persist-test.el` | +14 ERT specs across the batch |
| `test/tibetan-analysis-claude-sections-test.el` | Claude tests updated for level-2 Vocabulary + retired merge |
| `test/tibetan-analysis-claude-prompt-test.el` | CAT-Gloss prompt test retired |
| `tibetan-cat.el` | `(require 'tibetan-bialek-textbook-refs nil t)' |
| `CLAUDE.md` | §5.21 added |

### 5.22 Compressed sentence-analysis layout for class reading (done, 2026-05-21)

Class-use feedback the day after §5.21 shipped:  the per-sentence
analysis files (`sent-NNN.org') inherit the full per-segment
renderer output (~11 level-2 sections inside `* Tibetan
Analysis').  In class, the reference sections (Detailed
Dictionary, Verb Classification, Sentence Structure) are prep-
time tools, not in-class tools.

Carsten:  *"the full layout isn't necessary for the sentence,
only for the segments… max 2 pages A4 per sentence with the
really important information for the sentence esp. the
structure (with converbs)."*

Solution evolved over the day:

1. **Initial (Commits 1-5):**  opt-in compressed layout via per-
   source `#+TIBETAN_SENTENCE_COMPRESSED: t' header + `C-c u z C'
   toggle command + dynamic var + metadata-reader key.  Matched
   the §5.12 / §5.14 per-source-header pattern.
2. **Drop DD always (Commit 6):**  even without the header, sentence
   files balloon when DD lists 20+ entries for a multi-segment
   sentence.  DD became always-stripped from sentence files.
3. **Final (Commit 7):**  retire the opt-in entirely — sentence
   files are unconditionally compressed.  The toggle + header +
   dynamic var + metadata key are removed.  Per-segment seg-NNN.org
   files keep the full §5.21 layout.

Net result:  sentence files render the in-class compressed shape
by default;  segment files keep the full prep-time shape.  Clean
split of class-reading vs deep-analysis surfaces.

#### Target on-disk layout (sent-NNN.org)

```
* My Notes                            user-edited (preserved)
* Working Translation                 user-edited (preserved)
* Tibetan Text                        raw Tibetan (full sentence)
* Tibetan Analysis
  ** Claude Vocabulary                ← KEPT (Claude per-word)
  ** Translation                      ← KEPT (Claude)
  ** Grammar                          ← KEPT (prose + Particles)
    *** Particles                     legend + skeleton + bullets
                                        with [Bialek 2022 §X.Y;
                                        Portfolio §A.B] refs
                                        (the converb-rich
                                        structure section)
    *** Claude Grammar                Claude's prose reading
  ** Provided Translations            ← KEPT (user-content slot)
    *** Roehrich                      hand-paste of published English
    *** Class Translation             working class translation
    *** Claude Context                discourse-level Claude reading
* Footnotes                           user-edited (preserved)
```

Compare to FULL §5.21 sent-NNN.org:  11 level-2 sections inside
`* Tibetan Analysis' → 4 always.

DROPPED in sentence files (unconditional):  `** Wylie
Transliteration', `** Phonetics', `** Interlinear Gloss', `**
DharmaMitra Translation', `** Sentence Structure', `** Verb
Classification (Hill 2010)', `** Detailed Dictionary'.

Per-segment `seg-NNN.org' files are UNAFFECTED — segment scaffold
keeps the full §5.21 layout.

#### Activation

None needed.  Sentence files are unconditionally compressed.
The `C-c u z' prefix loses one command (`C-c u z C' freed up
for future use);  per-source `#+TIBETAN_SENTENCE_COMPRESSED:'
header is ignored if present (backwards-tolerant).

#### Commits (7)

| Commit | Subject                                                                  | Tests |
|--------|--------------------------------------------------------------------------|-------|
| 1      | `--read-source-metadata' extension:  `:sentence-compressed' plist key    | +1    |
| 2      | Dynamic strip-list:  defconst → defun accessor + new compressed-strip-list| +3   |
| 3      | Wire flag through `--scaffold' (used by both `--create-file' + `--regenerate')| +2 |
| 4      | `tibetan-sentence-toggle-source-compressed' + `C-c u z C' + menu         | +1    |
| 5      | CLAUDE.md §5.22 initial + verification                                   | docs  |
| 6      | Always-strip Detailed Dictionary from sentence files (full + compressed) | +1, ±3 |
| 7      | Retire opt-in machinery;  compressed becomes unconditional default       | −3, ±4|

Commits 1-5 set up the opt-in;  Commit 6 broadened the strip;
Commit 7 retired the opt-in and made the strip unconditional.
A pragmatic but slightly long path — kept here in the §5.22
entry rather than fragmented across §5.22 + §5.23 because the
whole arc is one logical batch (one day's iteration on class-
reading sentence files).

#### Mechanism (post-Commit 7)

The §5.18 sentence alignment already had a stripper hook
(`tibetan-sentence--strip-segment-claude-sections') reading from
a `defconst' filter list (empty since §5.18 alignment landed).
§5.22 final keeps that mechanism, simplified:

  · `tibetan-sentence--strip-list' (defconst, 7 entries):
    Wylie / Phonetics / Interlinear / DharmaMitra Translation /
    Sentence Structure / Verb Classification (Hill 2010) /
    Detailed Dictionary.
  · `--segment-claude-sections' accessor returns the list
    unconditionally.

No dynamic var, no metadata-reader key, no header, no toggle.

Sentence-only L3 extras (Roehrich / Class Translation / Claude
Context) survive the strip:  the filter operates on level-2
headings, and `** Provided Translations' is NOT in the strip
list, so `--inject-sentence-l3-entries' continues to attach
them under that parent.

#### Verification recipe

1. **ERT**:  `make test-quick' → 1955 / 1954 expected / 0
   unexpected / 1 skipped.  `make test' (BDD) stays 244 / 244.
   `make compile' clean.

2. **Live spot-check** on Milarepa source:
   - `M-x tibetan-sentence-batch-reanalyze' with
     `:re-request-claude nil' on the Tibetisch IV analysis
     folder.
   - Open any sent-NNN.org:  inside `* Tibetan Analysis' only
     `** Claude Vocabulary', `** Translation', `** Grammar', `**
     Provided Translations' — the 7 reference sections absent.
     Roehrich / Class Translation / Claude Context still under
     Provided Translations.

3. **Segment-file regression** (no behavioural change expected):
   pick a seg-NNN.org file, confirm the full §5.21 layout
   (Wylie / Phonetics / Interlinear / Vocabulary / Translation /
   DM Translation / Grammar / Sentence Structure / Verb
   Classification / Provided Translations / Detailed
   Dictionary) is intact.

4. **Idempotency**:  re-run batch-reanalyse a second time;  diff
   should be empty modulo `:LAST_ANALYZED:' timestamps.

#### Files changed (across the 7 commits)

| Path | Role |
|------|------|
| `persist/tibetan-analysis-claude.el` | `:sentence-compressed' plist key (added Commit 1, retired Commit 7) |
| `persist/tibetan-sentence-persist.el` | `tibetan-sentence--strip-list' defconst (Commit 7 consolidation of the intermediate accessor + strip-list pair from Commits 2+6);  `--scaffold' uses the unconditional strip |
| `config/tibetan-keybindings.el` | `C-c u z C' binding (added Commit 4, retired Commit 7) |
| `config/tibetan-menu.el` | "Toggle Compressed Sentence Layout" entry (added Commit 4, retired Commit 7) |
| `test/tibetan-analysis-claude-prompt-test.el` | Metadata-reader spec (added Commit 1, flipped to absence guard in Commit 7) |
| `test/tibetan-sentence-persist-test.el` | ERT specs across the arc:  +6 in Commits 2-4, ±4 / -3 in Commit 7 |
| `CLAUDE.md` | §5.22 added Commit 5, reframed Commit 7 |

#### TOC + section-numbering disabled on export (follow-up, 2026-05-21)

Independent of the sentence-layout work:  all three analysis-
file scaffolds (`tibetan-analysis-create-file' for segment files,
`tibetan-analysis-create-paragraph-file' for paragraph files,
`tibetan-sentence--scaffold' for sentence files) now emit
`#+OPTIONS: toc:nil num:nil' right after `#+STARTUP: showall'.
HTML / PDF / LaTeX export of any analysis file no longer
includes an auto-generated table of contents or numbered
section prefixes (`1. My Notes' / `1.1. …').

### 5.23 Per-source filename suffix for analysis files (done, 2026-05-22)

Class-use feedback (2026-05-22):  the MA Reading folder shares
one `analysis/` between four source documents (`gal-chen-nyi-
shu.org', `lam-rim-thun-cig.org', `title-colophon.org', `reading-
companion.org').  Each source numbers segments from 1 — so
`Segment 6' exists in BOTH gal-chen AND lam-rim AND title-
colophon → all three wanted to write `seg-006.org' in the same
folder → second writer silently overwrote first.

Visible damage:  on inspection 2026-05-22, gal-chen had 22 seg
analysis files (segs 0-21), lam-rim had 17 seg files (numbered
22-38 — its TRUE segs 22-38), and lam-rim's segs 1-21 +
title-colophon's segs 1-2 were entirely MISSING (silent
overwrite by gal-chen, which was created first).

#### Root cause

`tibetan-analysis-make-short-name' (line 549, infrastructure
existed) derives a short-name suffix from any source file
\(`gal-chen-nyi-shu.org' → `gal',  `Milarepa-prepared.org' →
`milarepa', etc.).  `tibetan-analysis-get-filepath' emits
`seg-NNN-SHORT.org' when given a source-file argument, plain
`seg-NNN.org' when not.

`tibetan-analysis-create-file' (line 659) called `(tibetan-
analysis-get-filepath seg-id)' WITHOUT source-file → wrote to
the UNSUFFIXED path.  Per §5.8.3 (2026-04-20), this was a
deliberate fix for the inverse bug (skip-check used suffixed,
create wrote unsuffixed → every C-c u B overwrote existing
seg-NNN.org silently).  The §5.8.3 fix locked both paths to the
UNSUFFIXED form, which worked for single-source folders
(Milarepa) but broke multi-source folders.

Sentence files (`sent-NNN.org') already used the suffix in some
paths — saw `sent-001-lam.org' alongside `sent-001.org' in the
MA Reading folder — confirming the infrastructure works.

#### Fix — pass source-file in BOTH create-path AND skip-check

Restoring §5.8.3's symmetry but in the OTHER direction:  both
sides now produce / look at the SUFFIXED path.  Three call-sites
updated:

  · `tibetan-analysis-create-file' (line 659)         — the writer.
  · `tibetan-auto-analyze-document' (auto-analysis    — the batch
    line 403)                                            skip-check.
  · `tibetan-open-segment-analysis' (line 4040)       — interactive
                                                         `C-c u A'.
  · `tibetan--reanalyze-segment-impl' (line 4219)     — interactive
                                                         `C-c u R'.
                                                         Backwards-
                                                         compat:
                                                         falls back
                                                         to UNSUFFIXED
                                                         when
                                                         SUFFIXED
                                                         absent.

Going forward, ALL new analysis files carry the per-source
suffix.  Multi-source folders are collision-free.

#### Migration helper

`tibetan-analysis-migrate-suffix-in-folder' (autoloaded) walks
FOLDER, for each unsuffixed `seg-NNN.org' / `sent-NNN.org' reads
the `#+SOURCE:' header to derive the source-doc path, computes
short-name, and renames in place.  Idempotent:  already-suffixed
files filtered by directory regex;  orphan files without
`#+SOURCE:' skipped;  target-already-exists conflict detected
and skipped rather than clobbered.

Returns plist summary `(:folder F :total N :renamed N-ren
:skipped N-skip :failed N-bad :results RESULTS)'.  Interactive
callers get a final `message'.

#### Migrations run 2026-05-22

  · Yogācārabhūmi (`gotrapatala.org', single source):  96
    files renamed to `seg-NNN-gotrapat.org' /
    `sent-NNN-gotrapat.org'.  3 skipped (Emacs `.org~' backup
    files, correctly excluded by regex).
  · MA Readings (multi-source, 4 sources):  39 files renamed.
    1 skipped (an orphan `sent-001.org' without `#+SOURCE:'
    link — predates the auto-creator; user can hand-rename or
    delete).
  · Milarepa (Tibetisch IV):  NOT migrated (single-source,
    no collision urgency).  User can run the migration command
    when convenient;  `--reanalyze-segment-impl' backwards-compat
    fallback handles UNSUFFIXED files until then.

After MA Reading migration:  ran `tibetan-auto-analyze-document'
on `lam-rim-thun-cig.org' + `title-colophon.org' which created
the previously-overwritten 23 missing analysis files (21 lam-rim
segs 1-21 + 2 title-colophon segs 1-2).  Then fired Claude+DM
for the 23 newly-created files via `:re-request-claude
:missing-only' (yesterday's §5.22-follow-up policy) — only the
empty files got API calls;  the 58 already-populated files
were correctly skipped.  All 23 now carry real Claude
Vocabulary / Translation + DM Translation.

#### Commits (3)

| Commit | Subject |
|---|---|
| 1c8332d | Code fix:  always suffix seg/sent filenames |
| 1c99d90 | Migration helper for unsuffixed analysis filenames |
| (this)  | CLAUDE.md §5.23 entry + final tally |

#### Tests (+2)

  · `create-file-emits-suffixed-filename' — asserts the
    SUFFIXED filename is written;  legacy UNSUFFIXED file is NOT.
  · `migrate-suffix-in-folder-renames' — temp-folder fixture
    with two unsuffixed files (different sources), one
    already-suffixed, one orphan;  asserts:  2 renamed, 1 orphan
    skipped, already-suffixed untouched, new names exist, old
    names gone.

Suite total:  1958 → 1960 / 1959 expected / 0 unexpected / 1
skipped.  `make compile' clean.

#### Files changed

| Path | Role |
|------|------|
| `persist/tibetan-analysis-persist.el` | `create-file' threads source-file;  `open-segment-analysis' + `reanalyze-segment-impl' wrappers; `migrate-suffix-in-folder' command |
| `persist/tibetan-auto-analysis.el` | Skip-check threads source-file (preserves §5.8.3 symmetry) |
| `test/tibetan-analysis-persist-test.el` | +2 ERT specs |
| `CLAUDE.md` | §5.23 added |

### 5.24 `** Concept Notes' replaces `*** Claude Context' (done, 2026-05-24)

Class-use feedback after the MA Reading class (2026-05-24).
Carsten:  *"Claude Context isn't that useful at the moment.  In
the class I got the idea, that we should reuse this for
additional information about the segment/sentence if there is a
Buddhist concept in the text that I get more information about
it."*

The pre-§5.24 `*** Claude Context' surfaced narrative-arc /
discourse-position information — useful occasionally but not
the high-value class artefact.  Higher-value:  Buddhist +
Sanskrit technical concepts (doctrine, doxography, lineage and
person and place names, category-lists like the five aggregates).
Claude-provided encyclopedia notes that keep students in the
text rather than breaking flow to look terms up.

#### What changed

| Aspect | Before | After |
|---|---|---|
| **Heading** (segment) | `*** Claude Context' (L3 inside Provided Translations) | `** Concept Notes' (L2, after DharmaMitra Translation, before Grammar) |
| **Heading** (sentence) | `*** Claude Context' (L3 inside nested Provided Translations) | `** Concept Notes' (L2, segment-renderer-emitted, kept in §5.22 compressed strip) |
| **Claude prompt section** | `## Context` — discourse-position narration | `## Concept Notes` — 0-3 technical-concept encyclopedia notes |
| **Sub-concept handling** | n/a | 1-sentence parenthetical gloss inline (e.g. "one of the twelve dhutaguṇas (the canonical list of ascetic disciplines)") — one level of recursion |
| **Empty-passage behaviour** | Claude wrote something even when narratively thin | Explicit `[No notable concepts in this passage]` placeholder |
| **Elisp key** | `:context` | `:concepts` |
| **Heading name flexibility** | Buddhist-only ("Claude Context") | Neutral — accommodates non-Buddhist terms (clans, places, lineages) |

#### Migration

Existing files migrate naturally on first regenerate post-§5.24:

  · `--migrate-legacy-claude-headings' Step 5 (segment layout) /
    Step 6 (sentence layout) renames `*** Claude Context' →
    `** Concept Notes' (segment) or `*** Concept Notes' (sentence),
    preserving body verbatim.
  · Reader's fallback chain checks `** Concept Notes' L2 → `***
    Concept Notes' L3 → legacy `*** Claude Context' L3.  First
    non-nil wins, so an already-migrated file's L2 body takes
    precedence over any stale L3 remnant.
  · Parser `## Concept Notes` and legacy `## Context' both route
    to the `:concepts' plist slot.

Preserved bodies carry the OLD narrative-arc content from the
pre-§5.24 prompt;  the user re-fires Claude (`C-c u R' or
`:re-request-claude :missing-only' batch) to get fresh
concept-notes content in place.

#### Sentence renderer changes

  · `tibetan-sentence--scaffold-sentence-only-l3-entries' drops
    `Claude Context' from the L3 inject list — the renamed
    `** Concept Notes' lives at L2 in both segment and sentence
    files (single source of truth, no duplication).
  · Sentence regenerate's preserved-body reader extended for
    `** Concept Notes' L2 + `*** Concept Notes' L3 + legacy
    `*** Claude Context' L3.  Writer uses the L2 path
    (`--set-l2-body-in-buffer').

#### Commits (2)

| Commit  | Subject |
|---------|---|
| f6b3f67 | Code + tests:  heading rename, prompt rewrite, migration, parser/reader/writer all aligned |
| (this)  | CLAUDE.md §5.24 entry |

#### Verification

  · `make test`        → 244 / 244 BDD specs pass.
  · `make test-quick'  → 1965 / 1964 expected / 0 unexpected /
                         1 intentional skip.
  · `make compile`     → clean (no NEW warnings).

#### Pending follow-ups

User raised two extensions during the class-reading review;
the first ships in §5.25 (below);  the second has no concrete
proposal yet:

1. **Thesaurus zettel cross-link** — shipped as §5.25 (next
   subsection).
2. (none open)

### 5.25 Thesaurus zettel cross-link in Concept Notes (done, 2026-05-24)

Carsten's follow-up to §5.24's `** Concept Notes':  *"should
also always check if there is a Zettel for this concept
available."*  Where the user has a curated thesaurus zettel for
a term that Claude discusses, the Concept Notes body should
link to it directly — let the reader jump from the in-passage
explanation to the zettel's full content.

#### Architecture choice

User picked option **(C) Both — prompt-cite + post-process
safety net** from a three-way AskUserQuestion.  The two paths
work together:

  1. **Pre-load (in-prompt)**:  before each Claude call, walk
     the passage's tokenised words, look each up in the
     thesaurus, inject the matches into the user prompt with
     instructions to cite as `[[id:ZID][zettel ↗]]'.  Claude
     does the semantic matching — it knows which zettel
     applies to the term *as used* in this context.

  2. **Post-process (writer-side safety net)**:  after Claude
     returns the Concept Notes body, scan bolded Tibetan terms
     and auto-append `[[id:ZID][zettel ↗]]' to any line that
     matches a zettel but didn't get cited in Claude's output.
     Lines that already carry a link are skipped (idempotent).

The two paths give robustness through overlap:  Claude usually
cites correctly in-prompt;  the post-process catches the
occasional miss.

#### Three new helpers (`persist/tibetan-analysis-claude.el')

| Helper | Returns |
|---|---|
| `--collect-zettel-references (tibetan-text)' | Deduplicated list of zettel plists matching tokens in `tibetan-text` (via `tibetan-thesaurus-lookup', Wylie key) |
| `--format-zettel-references-block (zettels)' | User-prompt-injectable text block — header instructing Claude how to cite + one bullet per zettel (Wylie / ZID / Skt. / EN-or-DE primary) |
| `--cross-link-zettels-in-body (body)' | Post-processed copy of `body` with `[[id:ZID][zettel ↗]]' appended to bolded-term lines that have a zettel but no link yet.  Idempotent. |

All three are no-ops when the thesaurus module isn't loaded —
silent fall-through preserves the no-zettel UX.

#### Wiring

  · `--build-claude-prompts' (segment) — injects the zettel
    block right before "Produce the five sections now."
  · `tibetan-sentence--build-claude-prompts' — same injection,
    guarded by `fboundp' so the sentence module loads cleanly
    without the analysis-claude module.
  · `--insert-claude-sections' — pre-write step post-processes
    the `:concepts' plist slot through `--cross-link-zettels-in-
    body'.

End-to-end flow:
  1. Prompt builder collects relevant zettels.
  2. User prompt carries the zettel block.
  3. Claude emits Concept Notes with inline `[[id:ZID][zettel ↗]]'
     citations.
  4. Writer's post-process catches any zettel Claude missed,
     auto-appends the link.
  5. On-disk `** Concept Notes' carries clickable cross-links
     to every relevant zettel.

#### Verification

  · `make test'        → 244 / 244 BDD specs pass.
  · `make test-quick'  → 1971 / 1970 expected / 0 unexpected /
                         1 intentional skip (compound-
                         analysis-callable).
  · `make compile'     → clean (pre-existing warnings only).

#### Pending (truly open now)

  · (none for the Concept Notes thread)

### 5.26 BUG: `:missing-only` wiped Claude content + restore (done, 2026-05-26)

Class-day discovery — Carsten ran `M-x tibetan-analysis-batch-
reanalyze' on the Milarepa folder on 2026-05-24 with the default
`:missing-only' answer (from the §5.22-follow-up three-way
prompt), expecting populated files to be SKIPPED.  Result on
inspection 2026-05-26 (today, just before class):  **274 of 287
seg-NNN.org files lost their Claude content**.  Pure silent
data loss.

#### Root cause

`tibetan-analysis-reanalyze-file' had the gate:

    (existing-sections
     (and (not re-request-claude)
          (tibetan-analysis--read-claude-sections filepath)))

When `re-request-claude' is `:missing-only', `(not :missing-only)'
is nil → `existing-sections' is nil → the file's populated Claude
content is NEVER READ INTO MEMORY before the regenerate-auto
write.  regenerate-auto overwrites the file with the fresh
scaffold → content gone.  `:missing-only' then sees an empty
file and queues a Claude refire.  Async queue (concurrency 3
over 284 files) + writer hooks / rate limits / network +
user-quits-Emacs all conspire to lose most responses.

The `--should-fire-claude-p' policy added in §5.22-follow-up
gated the API CALL correctly, but didn't gate the WIPE.

#### Fix

One-line gate change:

    (and (not (eq re-request-claude t))
         (tibetan-analysis--read-claude-sections filepath))

Now `nil' AND `:missing-only' both preserve;  only literal `t'
(explicit force-refresh) wipes.  Matches the user's stated
expectation:  *"if Claude/DharmaMitra are in the analyses it
should stay there except a renew is explicit requested."*

Also extended `has-any-section' to look at `:concepts' (the
§5.24 rename of `:context') and `:vocabulary' — both are
populated-Claude indicators that should trigger the restore
path.  Previously a file with only Vocabulary (no Translation
yet) would have been treated as "no Claude content" and wiped
even with the gate fixed.

Regression test (`tibetan-batch-reanalyze-missing-only-
preserves-claude') verified to FAIL without the gate fix, PASS
with it.  Locked in so this can't silently regress again.

#### Disaster recovery — restored from git

Carsten's `~/.../buddhist-studies/' folder is a git repo.  The
pre-wipe versions of all 284 Milarepa seg-NNN.org files were
preserved in commit `bc5cbe9' (the original `SS26: bring
semester coursework into git' commit).  Built a one-shot Elisp
script (`/tmp/restore-milarepa-claude.el', not checked in;  it's
a one-time tool):

  1. For each unsuffixed seg-NNN.org in the Milarepa analysis/
     folder, check if it has the `[Awaiting Claude…]' / `[Requesting
     translation...]' placeholder.
  2. If yes, fetch the git-blob version from `bc5cbe9'.
  3. Parse the git version's Claude bodies via `--read-claude-
     sections' (which handles legacy `*** Claude Translation' L2
     / `*** Claude Vocabulary' L3 / `** Claude Grammar' L2 / etc.
     thanks to its fallback chain).
  4. If the parsed plist has any populated slot, call
     `--restore-claude-sections' to write the bodies back into
     the current (new-§5.24-layout) file.

Result:  **267 files restored** from git blobs (zero API
spend);  12 were already populated (skipped — restore is
idempotent);  3 had no Claude content even in the git version
(true bottom of the well);  2 not in git (recently-created files
that postdated the `bc5cbe9' commit).

Post-restore tally:  **280 / 287 seg files have populated
Claude Vocabulary + Translation**.  The 7 still empty are split
between the 3 that never had content + the 2 not-in-git + 2
edge cases (seg-IDs from non-Milarepa source debris in the
folder).  Effectively complete recovery for class.

#### Commits

| Commit  | Subject |
|---------|---|
| a66b8a7 | BUG: regenerate-auto preserves content under :missing-only too (gate fix + regression test) |
| (this)  | CLAUDE.md §5.26 entry |

#### Verification

  · `make test'       → 244 / 244 BDD specs pass.
  · `make test-quick' → 1972 / 1971 expected / 0 unexpected /
                        1 intentional skip.  +1 regression test.
  · `make compile'    → clean.

#### Lessons captured

1. **`(not X)' is treacherous when X is a symbol that's not just
   `nil' / `t'.**  `:missing-only' is non-nil — `(not :missing-
   only)' returns nil, NOT t.  When the legacy code path was
   "preserve unless force-refresh", that should have been
   `(not (eq X t))', not `(not X)'.

2. **Policy gates should be CONSISTENT across the pipeline.**
   §5.22-follow-up added `:missing-only' semantics at the
   API-call site but left the wipe-decision-site with the old
   `(not re-request-claude)' check.  Two policy gates with
   different semantics ate the content.

3. **Per-file restore from git is FAR cheaper than re-firing
   Claude.**  267 API calls saved by checking
   `git show bc5cbe9:analysis/seg-NNN.org' before queueing.

### 5.27 Unified document-preparation wizard (done, 2026-05-27)

**Problem.** Preparing a new Tibetan document for class analysis
required six+ separate commands across two tooling surfaces (CLI
+ Emacs):  decide input route (OCR / Wylie / Tibetan-script
paste), shell out to `doc-prep/tibetan-ybh-prep.py` if Wylie, mv
the result into `work in progress/`, hand-edit the
`#+TIBETAN_TARGET_LANG:` / `#+TIBETAN_TEXT_TYPE:` /
`#+TIBETAN_CLAUDE_CONTEXT:` headers, run
`tibetan-add-sentence-structure`, run `C-c u B`, run
`tibetan-sentence-create-all` if reading-class.  No single
entry-point, no genre help, no Claude pre-fill of metadata.

**Decision.** One guided wizard exposing every decision as a
prompt, with the Phase 1-5 building blocks composing under the
hood.  `M-x tibetan-document-prep-wizard` (bound to `C-c o d`,
menu *Tibetan > Document Preparation > Document Wizard
(unified)...*).

**Architecture.** Seven phases, all shipped 2026-05-27:

  · **Phase 1** — Header plumbing.
    `tibetan-analysis--read-source-metadata' (in
    `persist/tibetan-analysis-claude.el') gains four new keys —
    `:text-type', `:class-mode', `:sentence-detail', `:author' —
    parsing the matching `#+TIBETAN_*:' single-line headers.
    `:author' falls back to the PROPERTIES drawer's `:AUTHOR:'
    entry for backwards compatibility.  See commit `5710e64'.

  · **Phase 2** — Wylie ingest wrapper.
    `doc-prep/tibetan-wylie-ingest.el' shells out to
    `tibetan-ybh-prep.py' via `call-process'.  Pre-flight gates
    check `python3' + `pyewts' + script presence;  validation
    helper (`--validate-input', interactive variant
    `-interactive') reports paragraph + segment counts and flags
    suspicious characters (embedded Tibetan Unicode, smart
    quotes / em-dashes) before conversion.  See commits
    `9e03d5f' (wrapper) and `fcd8379' (post-ingest relocation
    into `../work in progress/' — defcustom
    `tibetan-doc-prep-work-in-progress-folder', default
    `"work in progress"').

  · **Phase 3** — Genre taxonomy + selectbox.
    `doc-prep/tibetan-document-genres.el' carries a single
    defconst with 14 entries — 12 traditional Tibetan genres
    (rNam thar, Lam rim, mGur, mDo, rGyud, bsTan bcos, sNyan
    ngag, gTam rgyud, 'Grel pa, Ṭīkā, gTer ma, gDams ngag) + 2
    legacy keys (`classical' / `madhyamaka-verse').  Each entry
    carries `:tibetan' (Wylie name), `:label' (display),
    `:description', and `:claude-hint' (genre-tailored Claude
    system-prompt guidance).  Reader
    `tibetan-document-genres-read &optional default prompt'
    runs `completing-read';  vertico / marginalia honour the
    alist-mapped completion table.  See commit `682f093'.

  · **Phase 4** — Async Claude metadata pre-fill.
    `doc-prep/tibetan-document-prep-claude.el' fires a small
    Claude call early in the wizard, asking for `{genre,
    author, context}' as a JSON object.  Submitted via
    `tibetan-claude-queue-submit' so throttle / retry / rate-
    limit handling matches the rest of the pipeline.  Parser
    tolerates code-fence wrapping;  unknown genre keys collapse
    to `:genre nil';  `"unknown"' author (case-insensitive)
    collapses to `:author nil'.  Result is cached as a buffer-
    local plist `tibetan-document-prep--claude-suggestions';
    interactive applier
    `tibetan-document-prep-apply-claude-suggestions' (bound
    `C-c o D') writes the headers and reverts the buffer.  See
    commit `d0431d6'.

  · **Phase 5** — Sentence-detail switch.  When the source
    carries `#+TIBETAN_SENTENCE_DETAIL: detailed', the §5.22
    7-entry strip-list is suppressed and `sent-NNN.org' files
    carry the FULL §5.21 segment layout (all 11 L2 sections).
    Wired via the dynamic var
    `tibetan-sentence--detail-for-render', bound inside
    `tibetan-sentence--scaffold' from the source-file's
    metadata so both create-file AND regenerate paths inherit
    the preference.  See commit `b2347da'.

  · **Phase 6** — Wizard module.
    `doc-prep/tibetan-document-prep-wizard.el' — pure
    orchestration walking twelve steps:  input route → (Wylie)
    validate + convert + relocate → target language → fire async
    Claude → genre selectbox (Claude-suggested default) →
    author + context (Claude-suggested defaults) → class mode →
    (reading) sentence detail → optional Resources/vocabulary.org
    scaffold → optional `tibetan-add-sentence-structure' →
    optional `tibetan-auto-analyze-document' + (reading)
    `tibetan-sentence-create-all' → final summary buffer.
    Resume support is built in:  every step reads existing
    header as completing-read default, so re-running on a
    partially-prepared source just re-confirms each value.  See
    commit `15fee53'.

  · **Phase 7** — Menu + keybindings + docs.  Menu entries
    *Document Wizard (unified)...* + *Apply Claude Metadata
    Suggestions* land at the top of *Tibetan > Document
    Preparation*;  the legacy OCR wizard is renamed *OCR /
    Format Wizard...* one slot below.  Keymap `C-c o' gains
    `d' (unified wizard), `D' (apply Claude suggestions),
    `y' (Wylie ingest), `Y' (Wylie validate-only);  the legacy
    `C-c o o' (OCR wizard) stays for backwards compatibility.

**Verification.** ERT suite 1976 → 2081 specs (+105) all green;
single pre-existing skip unchanged.  Compile clean.  Sanskrit-
included documents are deliberately out of scope — users enable
the parallel-Sanskrit path via the existing `C-c u z P' toggle.

**User-facing recipe** (a Wylie source for the SS26 Tibetisch
IV class):

```
~/buddhist-studies/SS26/Tibetisch IV/raw/foo.org   ← Wylie input
M-x tibetan-document-prep-wizard      (or C-c o d)
  Input route:    Wylie file (.org with Wylie body) ...
  Wylie source:   ~/.../raw/foo.org
  → validates, converts via pyewts, relocates to
    ~/buddhist-studies/SS26/Tibetisch IV/work in progress/foo.org
  Target language: de
  → async Claude metadata call fires
  Genre:           (Claude-suggested default or `classical')
  Author:          (Claude-suggested or freeform)
  Context line:    (Claude-suggested or freeform, RET to finish)
  Class mode:      grammar | reading
  Sentence detail: compressed | detailed   (reading mode only)
  Create Resources/vocabulary.org? y
  Run sentence-structure demotion? y
  Run full Claude analysis now? y/n
  → final summary buffer
```

When the async Claude call returns post-wizard:
`M-x tibetan-document-prep-apply-claude-suggestions` (`C-c o D`)
opens the source file and writes the cached suggestions into
the metadata headers.

### 5.28 Opus 4.8 full-codebase audit + fixes (done, 2026-06-01)

A comprehensive audit of the whole tree (correctness / security /
design / dead code / test gaps), fanned out over parallel reviewers,
followed by a fix pass.  Every fix was regression-test-first and is its
own commit.  Suite 2107 → **2119** ERT (BDD 244/244); full `make
compile` is now clean (zero warnings).

**Two CRITICALs:**
- **No TLS verification on outbound HTTPS** (`tibetan-dharmamitra-api`,
  `tibetan-mitra-translation`).  `url-retrieve-synchronously` ran with
  Emacs' default `gnutls-verify-error' = nil, so a forged/MITM cert did
  not abort — the bearer token was sent and the response trusted over an
  unverified channel.  Fixed by binding `gnutls-verify-error' t +
  `network-security-level' 'high.  **Follow-up bug (also fixed):** the
  bindings were LEXICAL under byte-compilation (the special vars weren't
  declared), so the enforcement was silently inert in `.elc` —
  `(require 'gnutls)`/`(require 'nsm)` makes them genuinely special.
  Caught by `make compile`'s unused-lexical warning; now tested against
  compiled code.
- **Sentence regenerate wiped parallel-mode top-level sections**
  (`* Sanskrit Analysis' / `* Combined Analysis' / DM-Sanskrit /
  realign).  The §5.26 data-loss class on the un-patched sentence path —
  latent (no current parallel-Sanskrit corpus uses sentence files) but
  real.  `tibetan-sentence--regenerate' now preserves + re-appends them
  (idempotent), mirroring the segment path.

**HIGH:** dead `C-c u D`/`C-c u W` bindings (void-function) removed;
`make test' fixed to run BOTH ERT + BDD (its `-f' named a non-existent
function and only worked by accident) and made network-free (the BDD
run hit dharmamitra.org live); `tibetan-auto--claude-needs-request-p'
taught the post-§5.18 `** Translation' heading + `[Awaiting' placeholder
(it was failing closed-as-populated, skipping real refires);
§5.23 suffix threaded through the reorg-rename and DM-realign-apply
paths (both wrote bare seg-NNN.org → multi-source collision); DM /
realign responses sanitised before org insertion (line-leading `*' →
heading injection; `:reason' newlines → forged property-drawer
entries); leftover `DEBUG' messages stripped from `C-c u I'.

**MEDIUM:** ནས/ལས ablative no longer over-matches lexemes like གནས;
`tibetan-clause-segment' tolerates malformed VERBS (the §5.9/P5
`wrong-type-argument listp' crash class); zero-marker analysis stops
excluding root-final-ས content words (སེམས/ལུས); `tibetan-verb-lookup'
trims a trailing tsheg; Steinert SQLite handle released on
`kill-emacs-hook'; SSE parser tolerates `data:{…}' (no space); workspace
defvars no longer wipe ox-latex's class defaults; wizard seeds class
mode from the existing header on non-Wylie resume (was silently flipping
grammar→reading); `#+TIBETAN_CLAUDE_CONTEXT:' append now dedups.

**Two audit findings DISPROVEN on inspection** (recorded so they aren't
re-investigated): the "German leaks into the English gloss slot"
case-fold claim — `tibetan-extract-english-from-bilingual' /
`-format-bilingual-meaning' are output-invariant, the predicates are
dead but harmless; and the reading-mode adjacent-`||' "bug" — it is an
intentional, test-locked design choice (`||' no-space = segment
boundary even in reading mode; the spaced `| |' is the within-paragraph
double-shad).

**Cleanup:** removed grep-confirmed dead code (`--get-word-info',
`tibetan-detect-verb-with-suffix' + its defconsts — which also resolved
a `tibetan-converb-particles' name collision with the live
clause-analysis copy —, a dead `(and … nil)' clause, redundant
string-suffix guards, an empty banner, the `test-tibetan-functions.el'
scratch file); added a run-all-tests.el visibility guard that warns
about any `*-test.el' that fails to load (the `(condition-case nil …
(error nil))' wiring silently swallows such failures); fixed a
byte-compile forward-ref + a Python invalid-escape warning.

**Deliberately NOT done** (Carsten's call): the M12 shared
section-body-reader refactor; renaming `tibetan-analysis-combine.el'
\(corpus-stitch) to disambiguate from `combined.el'; wiring/relocating
the orphaned `setup/` modules.  Also left as enhancements, not bugs:
auth-source lookup for a private DharmaMitra token (the default token is
public), and the benign gptel sync-timeout reason-string race.

### 5.29 BUG: DharmaMitra re-fired populated sections on open (done, 2026-06-02)

User report: "a lot of DharmaMitra requests" — opening an already-
translated segment re-hit the DM API every time and overwrote the
existing translation.  Two compounding bugs (split into two commits):

- `tibetan-dharmamitra-translation-needs-request-p' searched the
  OBSOLETE top-level `* DharmaMitra Translation (Tibetan)' heading, but
  §5.20 moved the Tibetan section to the NESTED `** DharmaMitra
  Translation' that the writer fills.  Read != write location → always
  "needs request".  Fixed to read the nested heading (legacy top-level
  fallback; `[Awaiting…' / `[Requesting…' count as still-needed).
- `tibetan-dharmamitra-translation-fire-for-segment' fired the Tibetan
  path UNCONDITIONALLY.  Added `&optional force'; each language fires
  only when FORCE or its needs-request-p.  C-c u R passes FORCE=t;
  batch passes (eq re-request-claude t).  Implements the policy: a
  populated Claude/DM section is renewed only on explicit request.
  (Claude's on-open fire was already gated by --claude-needs-request-p.)

### 5.30 Opus 4.8 audit round 2 + fixes (done, 2026-06-02)

A second whole-tree audit (the §5.28 fixes were re-verified present).
Fixed, each regression-test-first, one commit each:

- **H2** wizard metadata loss: header writes went to disk via
  write-region while --fire-async-claude kept a stale visiting buffer;
  the kickoff save-buffer then clobbered the headers.  New
  `--edit-source' routes source mutations through the visiting buffer.
- **M1** `tibetan-reorg--collect-document-segments' matched only heading
  levels 2-3 → found ZERO segments in the canonical §2.12 nested layout
  (Sentence@3 / Segment@4); now level-agnostic.
- **M4** DharmaMitra dictionary lookup now negative-caches misses (was
  re-hitting the network on every miss).
- **M5** Steinert URL JSON built with json-encode (was a raw format
  string → malformed JSON for quote/backslash terms).
- **M6** Madhyamaka term match requires whole tsheg/shad-delimited units
  (was raw substring match → e.g. `ལམ' inside `ལམས'); compound-internal
  matches (`ལམ' in `ལམ་རིམ') remain an inherent-segmentation limitation.
- **M7** removed contradictory duplicate `བཙོང' verb-DB entry (the `ཚོང'
  alias pointed at the dead one).
- **M8** moved reorg's load-time global-set-key (C-c u O / C-c u U) into
  config/tibetan-keybindings.el; same for the duplicate C-c u P /
  C-c s w / C-c s p / C-c e p module bindings.
- **DEBUG** removed leftover message spam (workspace C-c s w; wylie
  safe-substring + a provably-dead BUG message).
- **Dead code** removed: module `analysis/tibetan-particles.el' (a
  Schwieger duplicate of -bialek), `tibetan-steinert-format-matches',
  `tibetan-extract-particle-text'.
- **ocr-validate** the audit's "zero coverage" was a FALSE POSITIVE
  (10 tests live in tibetan-doc-prep-test.el); added the two untested
  paths (subscript-start, suspicious) + tidied a redundant format.

**Deferred (need design / too risky for a cleanup pass — proposed as
follow-ups):**
- **H3** parallel-Sanskrit unscoped `** Translation' read: scoping the
  reader alone broke a test because the WRITER + migrate/ensure helpers
  also operate buffer-wide and round-trip the Sanskrit body.  A correct
  fix needs reader+writer+migrate scoped together (or the Sanskrit
  pipeline to use distinct heading names).  Latent — parallel-Sanskrit
  docs only (gotrapaṭala), not the normal workflow.  Reverted the
  partial change.
- **M2** `tibetan-verb-lookup' blind `ས$' strip: purely latent (the
  gethash guard prevents current misfires); a real fix needs noun-
  awareness.  No reproducible bug → left.
- **M9** `tibetan-auto--create-sentence-file' emits a legacy/orphan
  layout: reconciling it with the canonical sentence creator is a
  design task (the auto path doesn't collect per-sentence seg-nums);
  legacy files migrate on regenerate anyway.

### 5.31 Grammar-section improvements + sentence-structure feature (done, 2026-06-02)

Class-reading improvements to the per-segment + per-sentence analysis
files (planned in `~/.claude/plans/synthetic-stargazing-anchor.md`).
Five items, each test-first, one commit each:

- **A. Zero-marker fix** (`tibetan-analysis--render-particle-skeleton`):
  the persistent-file `Ø` is now stamped before a verb ONLY when the
  immediately-preceding token is a bare content word — suppressed when
  it is already markup (`=case=` / `~converb~` / `*final*`).  Fixes the
  §5.21-deferred "spurious Ø on an overt ergative subject".
- **B. Reading-optimized section order** (`--priority-section-order`):
  Sentence Structure elevated ABOVE Grammar; Concept Notes demoted to a
  reference block just above Detailed Dictionary.  Existing reorder
  post-pass migrates files on regenerate.
- **C. Hill verb stems** (`tibetan-verb-classifier`): a normalization
  pass auto-indexes every entry's present/past/future/imperative stems
  as lookup keys (8 were missing — e.g. སྨྲོས, ཐོབས, མཐོངས); new
  `tibetan-verb-matched-stem' tags WHICH stem appeared, surfaced in Verb
  Classification as `ATTESTED: <form> — perfect (past) stem'.
- **D. Subjects/objects + full sentence structure** (the new feature):
  `--render-clause-structure' now prints explicit SUBJECT / DIRECT
  OBJECT / oblique labels (new `--role-order' / `--role-labels' /
  `--role-label') with the full NP, ordered subject→object→oblique.
  Sentence files: `** Sentence Structure' DROPPED from
  `tibetan-sentence--strip-list' so the full per-clause structure
  survives; the main-clause-only summary (`--render-main-clause' /
  `--append-main-clause' / `--role-display' / `--main-clause-role-order')
  retired/removed.
- **E. Role-based highlighting**: new `tibetan-analysis-verb-face'
  (blue) + `-structure-role-face' (green-bold); the Sentence Structure
  role labels + clause verbs are font-locked (verified).  A Tibetan-
  script base layer (`--tibetan-script-matcher', a FUNCTION matcher —
  a `[ༀ-࿿]' char-range as a STRING in font-lock-keywords is silently
  dropped when other keywords are present) colours Tibetan runs;  under
  batch `font-lock-ensure' this base layer is inconsistent (jit-lock
  artifact) — **eyeball + tune colours live**.

NOTE: §5.21 layout (and now these changes on regenerate) apply to
Milarepa; Yogācārabhūmi is still pre-§5.21 — propagating is a regenerate
run (Carsten's call, and §5.29 governs Claude/DM re-firing).  The
verb-extractor not recognising some past stems in running text
(e.g. བལྟམས) is a separate data-coverage matter, not part of this batch.

### 5.32 seg-039 analysis-quality fixes (done, 2026-06-03)

Live-review of a regenerated Milarepa segment
(`རྔོག་གི་དྲུང་དུ་ཕྱིན་ནས།', "Segment 39") surfaced four GENERAL quality
bugs.  Each test-first, one commit (plan
`~/.claude/plans/synthetic-stargazing-anchor.md`).  Verified read-only
on the real segment — see file-naming NOTE below.

- **A. Wylie ra-mgo + nga stack** (`d24e1fa`,
  `core/tibetan-wylie.el`).  `རྔ` was absent from the consonant-stacks
  table → `རྔོག` (rNgog) rendered "raog", which cascaded to a junk
  `term-raog` anchor, a wrong dictionary key, and bad Phonetics
  ("rao").  Added `("རྔ" . "rng")` (2-char) + `("རྔྱ" . "rngy")`
  (3-char).  `རྔོག` → "rngog"; Phonetics auto-corrects → "ngok".

- **B. `ཕྱིན` = past of `འགྲོ`** (`2485344`,
  `analysis/tibetan-verb-classifier.el`).  `འགྲོ` ("to go") had
  `past_stem` "སོང", so the literary past `ཕྱིན` ("went") was
  unindexed → `Verb Classification: [No Hill-DB verbs detected]` and
  the §5.31-elevated `** Sentence Structure` was EMPTY.  Set
  `past_stem` → "ཕྱིན" (kept `imperative_stem` "སོང" + its alias).  The
  §5.31 stem-normalization pass auto-indexes ཕྱིན;  detection +
  "ATTESTED: ཕྱིན — perfect (past) stem" + a populated clause all work.

- **C. MWU verb-tail guard, BOTH loops** (`207d034` +
  `e05bd4a`).  The greedy MWU matchers accepted a Rangjung-Yeshe
  *phrasal* entry `དྲུང་དུ་ཕྱིན' that ENDS in a verb — gluing it into
  one unit, swallowing `ཕྱིན', and surfacing the RY entry's Tibetan
  EXAMPLE sentence (`bcom ldan 'das kyi drung du') as the gloss.  Two
  loops needed fixing: `tibetan-find-multiword-units`
  (`analysis/tibetan-enhanced-parser.el`, the clause/structure path)
  AND `tibetan-extract-vocabulary` (`core/tibetan-vocabulary.el`, the
  §5.9 Interlinear path).  New predicates
  `tibetan-enhanced-parser--verb-tail-p` /
  `tibetan-extract-vocab--tail-is-verb-p` (both reuse
  `tibetan-verb-lookup`);  guard rejects a ≥3-syll (parser) / ≥2-syll
  (interlinear) candidate whose tail is a Hill verb — UNLESS it is a
  user-curated Resources / Custom MWU (e.g. `ཆུང་མ་བྱེད' "to take a
  wife" stays a unit).  Interlinear now: `drung [beside] / du [TERM] /
  phyin [pf. of 'gro; to go]`.

- **D (deferred — dictionary-quality, not quick fixes).**  Two
  residuals visible on this segment are inherent lookup limitations,
  flagged not fixed: (1) `rngog [mane]` — rNgog is the proper name of
  Mila's teacher (rNgog ston), but RY glosses the common noun "mane /
  dewlap";  needs proper-noun awareness.  (2) `nas [ABL/CONV:nas]` —
  a particle shows its grammatical label (correct — no lexical sense)
  but the format is terse.  The general example-sentence-as-gloss
  filter (skip a leading Tibetan example in
  `tibetan-vocab--parse-entry`) is also still open;  C fixed the
  verb-tail case, but a non-verb-tail compound with an example-only
  `:primary` could still surface one.

**NOTE — file-naming mess in the Milarepa analysis folder.**  The
on-disk `seg-039.org` does NOT contain "Segment 39"
(`རྔོག་གི་དྲུང་དུ་ཕྱིན`) — that text lives in `seg-110.org` (and a
duplicate `seg-110-milarepa.org`).  The folder mixes bare `seg-NNN.org`
with §5.23-suffixed `seg-NNN-milarepa.org' duplicates AND iCloud
conflict copies (`seg-10492 2.org' etc.), so the seg-id ↔ segment
mapping is scrambled.  Cleaning this (de-dup + canonical naming) should
precede any corpus-wide re-regenerate so the fixes land on the right
files.  Verification above was done on copies in /tmp via
`tibetan-analysis-reanalyze-file … :re-request-claude nil` (preserve
mode, zero network) — the live corpus was NOT mutated.

Suite 2119 → **2125** / 2124 expected / 0 unexpected / 1 skipped.
`make compile` clean.  REFERENCE.org regenerated (`56a68d9`).

### 5.33 Milarepa folder cleanup + item D + corpus regenerate (done, 2026-06-03)

Follow-up to §5.32.  Two user decisions (AskUserQuestion): clean up the
analysis-folder file-naming FIRST, then tackle item D INCLUDING the
proper-noun gloss.  Then re-regenerate the corpus so all fixes land.

#### Folder cleanup — the seg-id↔segment scramble

The Milarepa `analysis/` folder had grown to **728 files**.  Root cause:
the §5.8.3 / §5.23 filename history left TWO numbering schemes coexisting
— the original bare `seg-NNN.org` (created 2026-04-14, correctly mapped
to the current 282-segment source) AND 123 `seg-NNN-milarepa.org`
duplicates from a 2026-06-02 regen whose `#+SOURCE'/`#+TITLE' labels were
written WRONG (e.g. `seg-110-milarepa.org' carried the rNgog text — real
Segment 110 — but was labelled "Segment 39").  Plus ~330 junk files
(`.org~' backups, `.bak*', garbage `seg-10491/10492.*', iCloud
conflict copies `seg-N N.org').

Audit method (all read-only): the source `Milarepa-prepared.org' has a
clean 282 segments (1..282, no dups).  Verified the bare files match the
CURRENT source by content (Segment 39 = `kho'i rtsar…', Segment 110 =
`rngog… phyin nas') — bare filename-num == source segment for all of
them.  Proved every one of the 123 `-milarepa' duplicates has a FULL
bare counterpart at the same filename-number → dropping them loses zero
content.

Action: moved **332 files** to a sibling `analysis-quarantine-2026-06-03/`
(with `MANIFEST.txt`; NOTHING deleted — fully reversible).  Folder now
holds exactly 282 bare `seg-001..282.org` + 85 `sent-001..085.org` +
legit `.tex/.pdf` exports + the pre-existing `archive/`.  Segments
**140, 141, 142** have no Claude content anywhere (need a refire).

#### Item D — both halves done (the §5.32 "D deferred" note is now closed)

- **D2 proper-noun gloss** (`1e830cc`).  The Claude-vocab override
  (`tibetan-analysis--apply-claude-vocab-override') only fired on Steinert
  `<person>'/`<place>' tags.  New `tibetan-analysis--claude-vocab-proper-
  noun-p' reads Claude's part-of-speech field (text before the quoted
  gloss, so a comma in the gloss can't trip it); when it says "proper",
  an UNTAGGED common-noun dict gloss is overridden with Claude's name.
  `རྔོག' → "mane" (Rangjung-Yeshe) now renders `[rNgog]' because the
  file's own Claude Vocabulary classifies it `proper noun, "rNgog"'.
  Fires on the regen path (preserved Claude vocab is bound into
  `--claude-vocabulary-for-render'); first-time generate is a no-op.
- **D1 example-sentence filter** (`17eacee`).  New `tibetan-vocab--mostly-
  tibetan-p' (Tibetan-block chars, zero Latin = a usage example, since
  real glosses are English/German).  `tibetan-vocab--parse-entry' skips
  such a first sense and falls back to the first `;'-separated sense with
  a Latin gloss.  General defence behind §5.32-C for the example-sentence-
  as-gloss class.

#### Corpus regenerate (preserve mode, zero network)

`tibetan-analysis-batch-reanalyze :re-request-claude nil` → **282/282
ok, 0 failed, all `:claude-preserved t'**.  `tibetan-sentence-batch-
reanalyze` → **85/85 ok**.  All §5.32 A/B/C + §5.33 D fixes are render-
time (D2 uses the preserved Claude vocab), so preserve mode lands them
without re-firing Claude.  Verified live on seg-110: `rngog gi drung du
phyin nas' Wylie, `[[term-rngog][rngog]] [rNgog] gi [GEN] drung [beside]
du [TERM] phyin [pf. of 'gro; to go] nas', ATTESTED past-stem ཕྱིན.
Backup of the clean pre-regen folder at
`/tmp/milarepa-analysis-backup-*.tar.gz'.

STILL OPEN: segments 140, 141, 142 need a Claude/DM fire (e.g.
`:re-request-claude :missing-only' or interactive `C-c u R' on each) —
they carry no content to preserve.

Suite 2125 → **2129** / 2128 expected / 0 unexpected / 1 skip.  Compile
clean.  REFERENCE.org regenerated (`0341768`).

### 5.34 phru rlog hallucination → grounding fix + Resources-load regression (done, 2026-06-03)

Live review of a (mislabeled) "Segment 37" file: Claude's Vocabulary
glossed `ཕྲུ་རློག' as "hand-mill turning" — a hallucination.  The
dictionary is unambiguous: Resources curated "Feldarbeit // farm work",
Steinert/Dan-Martin `sa zhing gsar pa rmos pa' (ploughing), Negi-Skt
`= rmo rko' (agriculture).  Diagnosis uncovered THREE things:

1. **File was mislabeled (already fixed by §5.33).**  The pasted file
   titled "Segment 37" actually held source **Segment 97**'s text — a
   pre-cleanup corrupted copy.  After §5.33 the content is correctly in
   `seg-097.org'; `seg-037.org' is the real Segment 37.

2. **Claude vocabulary prompt had NO dictionary grounding** (`4fbc7d3`).
   `--format-segment-vocabulary' read the §5.10-RETIRED `** Word /
   Particle List' section → nil for every current file → Claude guessed
   meanings for rare words.  Fix: new
   `tibetan-analysis--read-interlinear-glosses' extracts `wylie = gloss'
   pairs from `** Interlinear Gloss' (the layered lookup incl. ★
   Resources); `--format-segment-vocabulary' falls back to it and the
   instruction now says base the Vocabulary on these attested glosses,
   do NOT invent meanings for listed words.  Takes effect on the next
   Claude re-fire.

3. **Resources-load regression — corpus-wide silent wipe** (`747030a`).
   While verifying (2), found that the §5.33 preserve-mode batch
   regenerate had DROPPED every curated Resources gloss (0 files with
   `[Resources (provided)]', down from 8).  Root cause:
   `tibetan-find-resources-folder' resolves `Resources/' only via
   `buffer-file-name'; in a headless `emacs -batch' run
   `generate-content' executes in `*scratch*' (nil buffer-file-name) →
   finder returns nil → Resources never load → Interlinear/DD fall
   through to generic glosses.  Interactive `C-c u R' was unaffected
   (runs from the analysis buffer).  Fix: the finder falls back to
   `default-directory', and `reanalyze-file' binds `default-directory'
   to the analysis file's folder around `generate-content'.  A fresh
   preserve-mode batch then RESTORED Resources to **161 files** (★ +
   `[Resources (provided)]') — more than ever, since the
   buffer-file-name dependency had been quietly losing them in many
   prior generations too.  `seg-097' `phru rlog' → "farm work"; bonus
   `mar ★ [Mar pa]' (D2 proper-noun + Resources both live).

LESSON: any code reachable from a headless batch must not depend on
`buffer-file-name' for locating per-document assets — derive from the
file path / `default-directory' instead.

Corpus re-regenerated twice in preserve mode (282 seg + 85 sent, 0
failed, content preserved).  Segments 140-142 still need a Claude fire.
Suite 2129 → **2132** / 2131 expected / 0 unexpected / 1 skip.  Compile
clean.  REFERENCE.org regenerated.

### 5.35 Claude Vocabulary term highlighting (done, 2026-06-03)

Class-use request: the headwords in `** Claude Vocabulary' were hard to
recognise.  Each entry is `WYLIE-TERM, part-of-speech, "gloss",
commentary' — and because the term is Wylie (Latin script) the §5.31
Tibetan-script font-lock colourizer never touched it, so the headword
blended into the POS / gloss / commentary.

Fix: new face `tibetan-analysis-vocabulary-term-face' (bold teal) + a
section-bounded font-lock matcher `tibetan-analysis--vocab-term-matcher'
(gated by `tibetan-analysis--in-claude-vocab-section-p') that bolds the
run before the first comma, ONLY inside `** Claude Vocabulary'.
Identically shaped `term, …' lines in `*** Claude Particles' are left
alone.  Registered in `tibetan-analysis-setup-faces'; applies on the
next open/refresh of an analysis buffer (font-lock only — no file
rewrite, so the corpus needs no regenerate).  Suite 2132 → **2134**.

Matcher tested directly (font-lock-ensure in batch is unreliable —
§5.31); verified live on seg-097 that the `bla ma' term carries the
face.

### 5.36 Shad-boundary markers in word lists (done, 2026-06-03)

Class-use request (MA Reading): the section is read whole, but analysed
shad-by-shad.  An MA Reading `segment' often spans several shad (།)-
delimited units (34 of 88 files), and the Interlinear Gloss + Claude
Vocabulary listed every word with no indication of where each shad-unit
ended.  ("Later we should make sentence/verse/paragraph the main unit —
but for now just a marker.")

Render-time marker `──────── ། ────────' at each INTERNAL shad boundary
(a shad with content after it), in the Interlinear Gloss AND Claude
Vocabulary.  Placement is by the boundary word — the last syllable
before the shad:
- `tibetan-analysis--shad-boundary-words' — Wylie boundary words from the
  file's Tibetan Text.
- `--mark-shads-in-vocab' — marker after the entry whose term ends in the
  boundary word.
- `--mark-shads-in-interlinear' — marker spliced after that token's
  `[gloss]' in the flowing line.
- `--apply-shad-markers' (via `--mark-l2-section') rewrites both sections;
  wired into `reanalyze-file' after regenerate + Claude restore.

Idempotent (stripped + re-placed each pass), no-op on single-shad
segments (Milarepa untouched), render-time only (no Claude re-fire).
Approach was an AskUserQuestion pick: scope = Vocabulary + Interlinear,
glyph = rule-with-shad.  Suite 2134 → 2138.

**MA Reading application — markers-only, NOT a full regenerate.**  A
full preserve-mode batch over MA Reading WIPED 48 files' baked-in
`[Resources (provided)]' glosses, because the per-document Resources
`wordlist' is now an EMPTY §5.27 scaffold (`work in progress/Resources/
vocabulary.org' = template only) — regenerate re-derives Resources from
the current (empty) wordlist, so the old glosses (from a wordlist that
no longer exists) are not reproducible.  Recovery: restored the folder
from the pre-regen backup, then ran `--apply-shad-markers' on each file
directly (markers splice into the EXISTING Interlinear/Vocab text;  no
regenerate, Resources untouched).  Result: 31 marker files + 48 ★
Resources files, both intact.

CAVEAT for a future session:  **regenerating MA Reading will lose those
48 Resources glosses** until the wordlist is repopulated (or the glosses
are moved to thesaurus zettels).  Unlike §5.34 (a buffer-file-name bug),
this is missing source data, not a code bug — the §5.34 default-directory
fix is working;  there is simply no wordlist to load.

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

## 10. REFERENCE.org maintenance (added 2026-05-24)

This repo ships a `REFERENCE.org` at the project root listing every
top-level Emacs Lisp definition (1100+ forms across 64 modules) with
docstring, signature, interactive flag, and autoload marker.
Auto-generated by `~/emacs-zettelkasten/generate-function-reference.py`.

**Hard requirement:** when you add, remove, or rename a `defun` /
`cl-defun` / `defcustom` / `defvar` / `defconst` in any `.el` file
under this repo, re-run the generator BEFORE the next commit:

```bash
python3 ~/emacs-zettelkasten/generate-function-reference.py \
    ~/tibetan-cat.el \
    ~/tibetan-cat.el/REFERENCE.org
```

Commit `REFERENCE.org` in the SAME commit as the `.el` change (or as
the very next commit).  The reference should never lag the source
by more than one commit.

Skip when:
- The change is in `test/` or `data/`.
- The change is a docstring tweak only (the reference picks it up
  on the next regular re-run anyway).
- The change doesn't touch any `def…` form.

A future enhancement is to add a `make reference` target and a
pre-commit hook so this becomes automatic.  Until then it's manual
discipline plus this section.
