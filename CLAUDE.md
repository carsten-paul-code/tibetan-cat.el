# CLAUDE.md — Agent handoff for tibetan-cat.el

This file briefs Claude Code (or any other Claude surface) picking up
work on **tibetan-cat.el**, Carsten Paul's Emacs-Lisp Computer-Assisted
Translation (CAT) system for Classical Tibetan. Read it in full before
editing. Last updated 2026-04-15 (post P0/P1/P2 + display-consistency
+ Round-2 polish round).

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

1. **Test first.** For any non-trivial change, write or extend an ERT
   test before (or alongside) the implementation. The repo has a deep
   ERT suite — respect it, keep it green. Stub external dependencies
   (SQLite, network, glossary files) so tests don't require the full
   environment.
2. **Aim close to perfect.** He is not looking for "ship it" output;
   he wants careful, correct code. If a solution is 80% there, say so
   and propose the remaining work rather than declaring it done.
3. **Preserve user content.** Any operation that regenerates analysis
   files must preserve `* My Notes`, `* Working Translation`,
   `* Footnotes`, and an existing `*** Claude` translation. If you
   touch the regenerate / batch-reanalyze path, add a test that
   asserts preservation.
4. **Persistent analysis is the canonical workflow.** He uses `C-c u A`
   (persistent analysis file per segment) — not `C-c u i` (classroom /
   scratch view). Design features around the persistent-file flow
   first; the classroom view is secondary.
5. **Don't silently change behaviour.** If a fix alters what users see
   in their analysis files, say so and ask before rewriting files he
   has invested hours annotating.
6. **German and English side by side.** Many glosses are bilingual
   (`DE // EN`). Don't collapse this — the `tibetan-analysis--format-bilingual-gloss`
   helper exists for a reason. Resources/Custom entries are hand-written
   and must never be truncated or rewritten.
7. **Small, focused edits.** He prefers one logical change per pass
   with tests, rather than sweeping rewrites.
8. **Explain what you're about to do before doing it** for anything
   that touches more than one module, then run the tests after.

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

Current state (2026-04-15): **~1002 tests, 0 unexpected failures, 3
intentional skips (text-scale / compound-analysis-callable).** Carsten
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

1. `make test` (or the batch command in §4). Confirm baseline green.
2. Skim `MEMORY.md` (auto-memory, if you have access to it) and the
   last paragraph of `CHANGELOG.md` for anything new.
3. Ask Carsten which P-level from §6 he wants to tackle — don't guess.
4. Write tests before code. Run tests after each edit.
5. Report back with: what changed, which files, which tests now
   cover it, and the updated test count.

---

*If this file gets out of date, update it as part of the same change
that made it stale. A wrong handoff doc is worse than no doc.*
