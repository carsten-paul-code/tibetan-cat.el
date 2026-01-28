# Architecture

This document describes the architecture of tibetan-cat.el, a Computer-Assisted Translation system for Classical Tibetan.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        tibetan-cat.el                           │
│                      (Main Entry Point)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│      Core       │  │    Analysis     │  │    Workspace    │
│   Utilities     │  │    Engines      │  │   & Display     │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Data Layer (Glossaries)                    │
└─────────────────────────────────────────────────────────────────┘
```

## Module Categories

### Core (`core/`)

Foundational utilities used by all other modules.

| Module | Purpose | Dependencies |
|--------|---------|--------------|
| `tibetan-utils.el` | Helper functions (string ops, Unicode) | None |
| `tibetan-wylie.el` | Wylie transliteration | tibetan-utils |
| `tibetan-vocabulary.el` | Dictionary lookup | tibetan-utils |
| `tibetan-vocabulary-detailed.el` | Rich dictionary entries | tibetan-vocabulary |
| `tibetan-org-structure.el` | Org-mode document parsing | org |
| `tibetan-text-classifier.el` | Text type detection | tibetan-utils |

### Analysis (`analysis/`)

Grammar analysis and translation engines.

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `tibetan-classroom.el` | Main segment analysis | `tibetan-segment-info` |
| `tibetan-particles-bialek.el` | Particle grammar (Bialek) | `tibetan-analyze-particle` |
| `tibetan-verb-classifier.el` | Verb stems (Hill 2010) | `tibetan-classify-verb` |
| `tibetan-enhanced-parser.el` | Multi-word units | `tibetan-parse-enhanced` |
| `tibetan-translation-engine.el` | CAT suggestions | `tibetan-generate-translation` |
| `tibetan-translation-suggest.el` | Translation hints | `tibetan-suggest-translation` |
| `tibetan-clause-analysis.el` | Clause structure | `tibetan-analyze-clause` |
| `tibetan-mitra-translation.el` | AI translation (Ollama) | `tibetan-mitra-translate` |

### Workspace (`workspace/`)

Translation workspace and display.

| Module | Purpose |
|--------|---------|
| `tibetan-sentence-workspace.el` | Editable translation interface |

### Philology (`philology/`)

Specialized analysis for verse and terminology.

| Module | Purpose |
|--------|---------|
| `tibetan-verse-philology.el` | Meter analysis (7-syllable) |
| `tibetan-madhyamaka-terms.el` | Madhyamaka vocabulary (90+ terms) |

### Persistence (`persist/`)

Saving analysis with user notes.

| Module | Purpose |
|--------|---------|
| `tibetan-analysis-persist.el` | Save/load segment analysis |
| `tibetan-compound-analysis.el` | Save/load compound analysis |
| `tibetan-auto-analysis.el` | Batch document analysis |
| `tibetan-structure-reorg.el` | Reorganize analysis files |

### Document Preparation (`doc-prep/`)

OCR and document formatting.

| Module | Purpose |
|--------|---------|
| `tibetan-doc-prep.el` | Document preparation workflow |
| `tibetan-doc-format.el` | Org formatting |
| `tibetan-doc-display.el` | Display settings |
| `tibetan-ocr-runner.el` | BDRC OCR integration |
| `tibetan-ocr-correct.el` | OCR error correction |
| `tibetan-ocr-validate.el` | OCR validation |
| `tibetan-sentence-structure.el` | Sentence detection |

### Configuration (`config/`)

User-facing configuration.

| Module | Purpose |
|--------|---------|
| `tibetan-keybindings.el` | All keybindings |
| `tibetan-menu.el` | Menu bar integration |

## Data Flow

### Segment Analysis Flow

```
User presses C-c u i
        │
        ▼
┌───────────────────┐
│ tibetan-classroom │ ◄── Entry point
└───────────────────┘
        │
        ├───────────────────────────────────┐
        ▼                                   ▼
┌───────────────────┐               ┌───────────────────┐
│ tibetan-vocabulary│               │tibetan-particles- │
│    (lookup)       │               │    bialek         │
└───────────────────┘               └───────────────────┘
        │                                   │
        ▼                                   ▼
┌───────────────────┐               ┌───────────────────┐
│  data/glossaries/ │               │tibetan-verb-      │
│  (162,000 entries)│               │   classifier      │
└───────────────────┘               └───────────────────┘
        │                                   │
        └───────────────────┬───────────────┘
                            ▼
                    ┌───────────────────┐
                    │  Analysis Buffer  │
                    │    (display)      │
                    └───────────────────┘
```

### Vocabulary Lookup Chain

```
tibetan-vocabulary-lookup
        │
        ├── 1. Check tibetan-comprehensive-vocabulary (hash table)
        │
        ├── 2. Check tibetan-madhyamaka-terms (if context matches)
        │
        ├── 3. Check DharmaMitra API (if enabled, network)
        │
        └── 4. Return "unknown" if all fail
```

## Key Data Structures

### Analysis Result

```elisp
(:segment "བྱང་ཆུབ་སེམས་དཔའ་"
 :wylie "byang chub sems dpa'"
 :words ((:tibetan "བྱང་ཆུབ་"
          :wylie "byang chub"
          :english "enlightenment"
          :pos "noun"
          :source "Hopkins")
         (:tibetan "སེམས་དཔའ་"
          :wylie "sems dpa'"
          :english "hero, bodhisattva"
          :pos "noun"
          :source "RY"))
 :particles ((:particle "འ"
              :type 'genitive
              :function "connects to following word"))
 :verbs nil
 :translation-suggestion "enlightenment hero / bodhisattva")
```

### Verb Classification (Hill 2010)

```elisp
(:verb "བྱེད"
 :stems (:present "བྱེད"
         :past "བྱས"
         :future "བྱ"
         :imperative "བྱོས")
 :transitivity 'transitive
 :volitionality 'volitional
 :case-frame (:agent 'ergative
              :patient 'absolutive))
```

### Text Classification

```elisp
(:text-type 'classical          ; or 'madhyamaka-verse, 'tantra
 :context 'madhyamaka           ; specialized vocabulary
 :tradition 'gelug              ; tradition-specific terms
 :tools '(bialek-grammar        ; which analysis tools to use
          verb-classifier
          particle-analysis))
```

## Extension Points

### Adding New Grammar Rules

1. Edit `analysis/tibetan-particles-bialek.el`
2. Add pattern to `tibetan-particle-patterns`
3. Add test in `test/tibetan-particles-test.el`

### Adding New Vocabulary

1. Edit relevant glossary in `data/glossaries/`
2. Format: `tibetan|english|pos|source`
3. Reload with `M-x tibetan-reload-glossaries`

### Adding New Text Types

1. Edit `core/tibetan-text-classifier.el`
2. Add type to `tibetan-text-types` alist
3. Define which tools apply to this type

### Adding New Keybindings

1. Edit `config/tibetan-keybindings.el`
2. Use `C-c u` prefix for analysis
3. Use `C-c v` prefix for verse/compound
4. Use `C-c s` prefix for workspace

## Performance Considerations

### Dictionary Loading

- Dictionaries are loaded lazily on first lookup
- Once loaded, entries are cached in hash tables
- Full load takes ~2-3 seconds (162,000 entries)
- Subsequent lookups are O(1)

### Analysis Caching

- Segment analysis results are not cached by default
- Use persistent analysis (`C-c u A`) to save results
- Auto-analysis mode re-analyzes on cursor movement

### Memory Usage

- Loaded glossaries: ~50MB RAM
- Each analysis buffer: ~10KB
- Persistent analysis files: ~2KB per segment

## Testing Architecture

```
test/
├── run-all-tests.el           # Test runner
├── tibetan-utils-test.el      # Unit tests
├── tibetan-vocabulary-test.el # Dictionary tests
└── ...

spec/
├── tibetan-bdd.el             # BDD framework
├── segment-analysis-spec.el   # Behavioral specs
├── particle-analysis-spec.el  # Grammar specs
└── ...
```

### Test Categories

1. **Unit Tests** (`test/`) - Individual function behavior
2. **BDD Specs** (`spec/`) - Feature-level behavior
3. **Integration Tests** - Cross-module interaction

## Dependencies

### Required

- `cl-lib` - Common Lisp compatibility
- `org` - Org-mode (bundled with Emacs)
- `popup` - Popup menus (ELPA)

### Optional

- `treemacs` - File browser
- `company` - Completion framework
- `magit` - Git integration

## Future Architecture Plans

1. **Modular Dictionaries** - Load only needed glossaries
2. **Async Analysis** - Non-blocking for large documents
3. **LSP Integration** - Language server protocol support
4. **Web Interface** - Browser-based analysis viewer
