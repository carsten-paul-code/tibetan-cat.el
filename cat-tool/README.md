# Tibetan CAT Tool - Modular Architecture

Computer-Assisted Translation tool for Classical Tibetan, designed for classroom use.

## Quick Start

```elisp
;; Add to your init.el:
(add-to-list 'load-path "/path/to/emacs-tibetan-cat/cat-tool")
(require 'cat-init)
(cat-init-setup)
```

## Module Structure

```
cat-tool/
├── cat-mode.el          # Main entry point & minor mode
├── cat-init.el          # Initialization & compatibility
├── core/
│   ├── cat-utils.el     # Shared utilities (safe-substring, etc.)
│   ├── cat-grammar.el   # Unified grammar/particle analysis
│   └── cat-parser.el    # Text parsing & compound recognition
├── display/
│   └── cat-display.el   # Analysis display formatting
├── persist/
│   └── cat-persist.el   # Persistent analysis to org files
└── support/
    └── cat-translation.el # Translation generation
```

## Key Bindings

| Key       | Command                          | Description                    |
|-----------|----------------------------------|--------------------------------|
| `C-c u i` | `cat-mode-analyze-segment`       | Basic segment analysis         |
| `C-c u I` | `cat-mode-analyze-segment-enhanced` | Enhanced analysis (compound-aware) |
| `C-c u A` | `cat-mode-save-segment-analysis` | Save analysis to file          |
| `C-c u R` | `cat-mode-re-analyze-segment`    | Re-analyze (preserve notes)    |
| `C-c u E` | `cat-mode-open-segment-analysis` | Open existing analysis         |
| `C-c u t` | `cat-mode-show-translation`      | Show translation suggestion    |
| `C-c u p` | `cat-mode-show-particles`        | Show particle analysis         |
| `C-c u w` | `cat-mode-show-wylie`            | Show Wylie transliteration     |
| `C-c u W` | `cat-mode-copy-wylie`            | Copy Wylie to clipboard        |

## Modules

### cat-utils.el (Core Utilities)
Shared functions used across all modules:
- `cat-safe-substring` - Multi-byte safe string extraction
- `cat-segment-text` - Tsheg-delimited segmentation
- Particle pattern definitions (ergative, genitive, dative, etc.)
- Display formatting helpers

### cat-grammar.el (Grammar Analysis)
Unified particle and case analysis based on Bialek's terminology:
- `cat-grammar-analyze-text` - Full grammar analysis
- `cat-grammar-analyze-cases` - Case particles only
- `cat-grammar-analyze-converbs` - Converb particles only
- Structured `cat-particle` data type

Particle types detected:
- **Ergative**: ཀྱིས, གྱིས, གིས, འིས, ཡིས, ས
- **Genitive**: ཀྱི, གྱི, གི, འི, ཡི
- **Dative/Allative**: ལ, ར, དུ, ཏུ, སུ, རུ
- **Ablative**: ནས, ལས
- **Locative**: ན
- **Converbs**: ནས, སྟེ, ཏེ, དེ, ཅིང, ཞིང, ཤིང
- **Causal**: པས, བས
- **Nominalizers**: པ, བ, པོ, བོ, མ, མོ
- **Concessive**: ཀྱང, ཡང, འང

### cat-parser.el (Text Parser)
Enhanced parsing with compound recognition:
- `cat-parser-parse` - Main parsing entry point
- `cat-parser-find-multiword-units` - Compound detection
- `cat-parser-extract-verbs` - Verb extraction (compound-aware)

Uses dictionaries from `data/dictionaries/`:
- `compounds.json` - Multi-word compounds
- `proper_nouns.json` - Names and places

### cat-display.el (Display Module)
Formatted output for analysis results:
- `cat-display-basic-analysis` - Simple analysis view
- `cat-display-enhanced-analysis` - Full compound-aware view
- Verb display with Hill 2010 classification
- Word-by-word gloss tables

### cat-persist.el (Persistence)
Save analysis to org-mode files:
- `cat-persist-analyze-segment` - Save segment analysis
- `cat-persist-re-analyze-segment` - Regenerate preserving notes
- Hash-based change detection
- User notes preservation

Analysis files stored in `analysis/` subfolder:
```
your-text.org
└── analysis/
    ├── seg-001.org
    ├── seg-002.org
    └── ...
```

### cat-translation.el (Translation)
Translation suggestion generation:
- `cat-translation-suggest` - Generate suggestions
- Grammar-informed transformations
- Converb/connector handling for natural English
- Context-aware rendering

## Integration with Existing Modules

The CAT tool integrates with existing tibetan-* modules:
- Uses `tibetan-to-wylie-fixed` if available
- Uses `tibetan-verb-lookup` for verb data
- Uses `tibetan-comprehensive-vocabulary` for glosses
- Uses `tibetan-get-current-segment-any-format` for segment detection

Compatibility aliases provided:
- `tibetan-segment-info` → `cat-mode-analyze-segment`
- `tibetan-segment-info-enhanced` → `cat-mode-analyze-segment-enhanced`
- `tibetan-analyze-and-save` → `cat-mode-save-segment-analysis`
- `tibetan-re-analyze` → `cat-mode-re-analyze-segment`

## Configuration

```elisp
;; Set default translation context
(setq cat-mode-default-context 'bhutan-kagyu-madhyamaka)

;; Enable auto-analysis on cursor movement
(setq cat-mode-auto-analyze t)
```

## Data Requirements

The tool expects data in `emacs-tibetan-cat/data/`:
```
data/
├── glossaries/
│   └── tibetan-english.el    # Vocabulary (17,777 entries)
└── dictionaries/
    ├── compounds.json        # Multi-word compounds
    └── proper_nouns.json     # Proper nouns
```

## References

Grammar analysis based on:
- Bialek, Joanna. "A Textbook in Classical Tibetan"
- Hill, Nathan W. "A Lexicon of Tibetan Verb Stems" (2010)
- Schwieger, Peter. "Handbuch zur Grammatik der klassischen tibetischen Schriftsprache"
