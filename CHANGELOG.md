# Changelog

All notable changes to tibetan-cat.el will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-11-01

### Added
- Initial public release
- Segment analysis (`C-c u i`)
- Sentence workspace (`C-c s w`)
- DharmaMitra vocabulary fallback
- Context-aware particle analysis
- Verb classification (Hill 2010)
- Hopkins dictionary integration
- Rangjung Yeshe dictionary integration
- 162,000+ dictionary entries
- Bialek-based grammar analysis
- Translation suggestions
- Org-mode integration

## [1.1.0] - 2024-11-10

### Added
- Verse philology tools (7-syllable meter analysis)
- Madhyamaka terminology database (90+ terms)
- Text type classification system
- Wylie transliteration for reading aloud
- Bialek grammar reference integration

### Changed
- Modular architecture refactoring
- Centralized keybindings in config/
- Improved error messages

## [2.0.0] - 2024-12-06

### Added
- Enhanced parsing with multi-word unit detection
- Persistent analysis with user notes (`C-c u A`)
- Compound/verse analysis (`C-c v A`)
- Mitra AI translation integration (Ollama backend)
- Auto-analysis toggle mode (`C-c u E`)
- Clause analysis with converb detection
- Structure reorganization tools

### Changed
- Improved particle detection accuracy
- Better handling of compound words
- Enhanced display formatting

### Fixed
- Nil handling in analysis functions
- Line-based segment detection
- Verb integration edge cases

## [2.1.0] - 2025-01-03

### Added
- Bundled glossaries (standalone package, no external dependencies)
- GitHub distribution ready
- Installation automation (Makefile, install.sh)
- MELPA-compatible package headers
- straight.el installation support

### Changed
- Glossaries now included in repository (~25MB)
- Simplified installation process

## [Unreleased]

### Added
- **core/tibetan-steinert**: SQLite-backed lookup against Christian
  Steinert's aggregated dictionary (800k+ entries, 60+ sources).
  `make build-steinert` + `scripts/build-steinert-db.py` build the DB
  locally; gracefully disabled when absent.
- **persist/tibetan-claude-queue**: throttled queue for outgoing Claude
  API requests with configurable concurrency cap, exponential backoff
  on HTTP 429, and per-job success/failure callbacks. Batch reanalysis
  no longer fan-outs hundreds of concurrent requests.
- **persist/tibetan-sentence-persist**: sentence-level analysis layer.
  Per-sentence `analysis/sent-NNN.org` files holding published
  reference translation, Claude discourse-level Translation/Grammar/
  Context, Working Translation, My Notes, Footnotes. New bindings
  `C-c s A` / `C-c s R` / `C-c s r`.
- **analysis/tibetan-interlinear**: Interlinear Gloss + Particle
  Overview sections. Wylie transliteration with inline Steinert links
  and English glosses; per-segment particle reference extracted from
  the user's Bialek Portfolio (path via
  `tibetan-interlinear-portfolio-file`).
- **Three-section Claude workflow** (segment-level): `** Claude
  Translation` (level 2, immediately after Wylie) + `*** Claude
  Vocabulary` + `*** Claude Grammar`. Legacy `*** Claude` / `***
  Claude Translation` placements are auto-migrated on first open.
- **Parser-grounded Claude prompts**: outgoing prompts now embed the
  tool's own Word/Particle List, Grammatical Markers, Clause
  Structure, Verb Classification, and Sentence Structure sections,
  plus neighbor-segment context, so Claude sees the analysis rather
  than only the raw Tibetan.
- **Configurable dictionary priority**: `tibetan-dictionary-priority`
  defcustom + `#+TIBETAN_DICT_PRIORITY:` org header override. New
  `resources` source auto-detects a wordlist under `../Resources/`.
- **CI workflow** (`.github/workflows/test.yml`): ERT + byte-compile
  on Emacs 27.1, 28.2, 29.4.
- **Living documentation generators**: `make docs-bdd` / `docs-ert` /
  `docs-funcs` produce HTML from the spec suite, ERT suite, and the
  public-function ↔ test map.
- **Quality report**: `bash run-quality-report.sh` runs tests + specs
  and writes a structured report to `quality-report.txt`.
- ERT suite grew from 1153 to 1224+ tests across the new modules and
  expanded coverage of wylie, vocabulary, verb-classifier,
  text-classifier, madhyamaka-terms, verse-philology, org-structure,
  sentence-workspace, auto-analysis, compound-analysis,
  clause-analysis, keybindings, menu, structure-reorg, doc-display,
  doc-prep, ocr-runner, ocr-correct, classroom, mitra-translation,
  translation-suggest, doc-format.
- Autoload cookies for 51 interactive entry-point functions across
  all modules.
- CONTRIBUTING.md, ARCHITECTURE.md, DEVELOPMENT.md, unified
  CHANGELOG.md.

### Changed
- Makefile `-L` paths extended with `doc-prep/` and `setup/`; new
  `docs`, `docs-bdd`, `docs-ert`, `docs-funcs`, `build-steinert`
  targets.
- Detailed Dictionary renderer embeds Steinert org-mode links
  alongside the existing multi-source block.
- BDD specs that reference absolute user-local paths now skip
  gracefully when those files are absent (CI + fresh-checkout safe).
- Keybinding `C-c u r` — batch reanalyze — now documented alongside
  the existing `C-c u R` (single-segment reanalyze).
- Cleaned codebase for open source release; zero byte-compile
  warnings; removed dead code (2 unused vars, 3 unused private
  functions, 48 legacy functions); legacy archive directory deleted.

### Fixed
- Batch reanalysis no longer silently leaves placeholder text in
  analysis files when Claude returns 429: the queue retries with
  backoff, and on exhaustion writes a visible failure stub.
- Interactive commands on text-scale helpers are now autoloaded so
  Tibetan text scaling works before the full package is loaded.
- `tibetan-clause-segmenter` is hard-required from `tibetan-cat.el`
  so `tibetan-analyze-round2` is always available to the renderer.
- Workspace module declares referenced `org-export-with-*` and
  `tibetan-workspace-file` externals so byte-compile is clean.
- Org-mode batch initialization for reliable test execution.
- Clause analysis converb scoping (removed no-op code path).
- Translation engine temporal clause handling.
- Multiple write-only variable warnings in wylie, vocabulary, and
  analysis modules.

---

## Version Numbering

- **Major**: Breaking changes or significant new features
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes, documentation updates

## Academic References

- Bialek, J. (2022). *Tibetan Grammar*
- Hill, N. (2010). *A Lexicon of Tibetan Verb Stems*
- Rangjung Yeshe Dictionary
- Hopkins Tibetan-Sanskrit-English Dictionary
