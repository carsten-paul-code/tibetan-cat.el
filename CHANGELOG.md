# Changelog

All notable changes to tibetan-cat.el will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Cleaned codebase for open source release
- Removed 48 unused functions
- Removed 5 unused variables
- Deleted legacy archive directory
- Consolidated documentation

### Added
- CONTRIBUTING.md with contribution guidelines
- ARCHITECTURE.md with system design documentation
- DEVELOPMENT.md with development setup guide
- Unified CHANGELOG.md (this file)

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

### Features
- 162,000+ dictionary entries
- Bialek-based grammar analysis
- Translation suggestions
- Org-mode integration

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
