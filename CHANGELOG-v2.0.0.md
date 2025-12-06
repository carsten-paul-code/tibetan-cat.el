# Tibetan CAT-Tool v2.0.0 Changelog

## Version 2.0.0 - 2025-12-06

### Major Reorganization

This release restructures the codebase for better maintainability and shippability.

### New Features

- **Document Preparation Pipeline** (`doc-prep/`)
  - `tibetan-doc-prep.el` - Main pipeline orchestration
  - `tibetan-bdrc-ocr.el` - BDRC OCR integration
  - `tibetan-segmentation.el` - Text segmentation utilities
  - Comprehensive test suite (20 tests)

- **New Segment Marker Format**
  - `〔seg〕...〔/seg〕` - Unnumbered segments
  - `〔sent〕...〔/sent〕` - Sentences
  - `〔verse :num N〕...〔/verse〕` - Numbered verses
  - `〔prose :comment-on N〕...〔/prose〕` - Commentary blocks
  - Inline verse references: `〈v:N〉`

### Directory Structure

```
emacs-tibetan-cat/
├── tibetan-cat.el          # Main entry point (v2.0.0)
├── core/                   # Core utilities
│   ├── tibetan-utils.el
│   ├── tibetan-wylie.el
│   └── tibetan-vocabulary.el
├── analysis/               # Analysis modules
│   ├── tibetan-enhanced-display.el
│   ├── tibetan-particles.el
│   └── tibetan-particles-bialek.el
├── persist/                # Persistent analysis (NEW)
│   ├── tibetan-analysis-persist.el
│   └── tibetan-compound-analysis.el
├── doc-prep/               # Document preparation (NEW)
│   ├── tibetan-doc-prep.el
│   ├── tibetan-bdrc-ocr.el
│   └── tibetan-segmentation.el
├── test/                   # Consolidated tests
│   ├── tibetan-utils-test.el
│   ├── tibetan-compound-analysis-test.el
│   ├── tibetan-doc-prep-test.el
│   └── test-tibetan-functions.el
├── archive/                # Legacy code (archived)
│   ├── cat-tool/
│   └── legacy/
├── workspace/              # User workspace
├── philology/              # Philological tools
└── config/                 # Keybindings
```

### Keybindings

All keybindings work with new segment markers:

- `C-c u A` - Persistent segment analysis (saves to JSON)
- `C-c u i` - Ephemeral inline analysis
- `C-c u I` - Ephemeral inline with popup
- `C-c v A` - Analyze verse/sentence blocks

### Legacy Cleanup

- Archived unused `.emacs.d/tibetan-*.el` files
- Archived incomplete `cat-tool/` refactoring
- Consolidated all tests into `test/` directory

### Test Suite

29 tests total:
- 20 doc-prep tests
- 5 utils tests
- 4 compound analysis tests
