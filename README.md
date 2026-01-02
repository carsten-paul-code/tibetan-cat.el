# tibetan-cat.el

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1+-purple.svg)](https://www.gnu.org/software/emacs/)

A Computer-Assisted Translation (CAT) system for Classical Tibetan Buddhist texts in Emacs.

Designed for classroom use and independent study of Tibetan Buddhist literature.

## Features

- **Segment Analysis** (`C-c u i`) - Comprehensive grammatical analysis with Bialek grammar
- **Sentence Workspace** (`C-c s w`) - Editable translation workspace
- **Auto-Analysis** (`C-c u E`) - Automatic updates as you navigate
- **162,000+ Dictionary Entries** - Rangjung Yeshe, Hopkins, Madhyamaka terms bundled
- **Verb Classification** - Based on Hill 2010, with transitivity and case frames
- **Verse Philology** - 7-syllable meter analysis, metrical fillers
- **Wylie Transliteration** - Accurate conversion for reading aloud
- **Text Classification** - Automatic detection of text types (classical, verse, etc.)

## Installation

### Option 1: Git Clone (Recommended)

```bash
git clone https://github.com/carsten-paul-code/tibetan-cat.el.git ~/.emacs.d/tibetan-cat
```

Add to your `~/.emacs.d/init.el`:

```elisp
(add-to-list 'load-path "~/.emacs.d/tibetan-cat")
(require 'tibetan-cat)
```

### Option 2: use-package with straight.el

```elisp
(use-package tibetan-cat
  :straight (:host github :repo "carsten-paul-code/tibetan-cat.el"))
```

### Option 3: Manual Installation

```bash
cd ~/path/to/tibetan-cat.el
./install.sh
```

Or use make:

```bash
make install
```

## Quick Start

1. Open a file with Tibetan text
2. Place cursor on a Tibetan line
3. Press `C-c u i` to see analysis

```
M-x tibetan-cat-setup    # Show all keybindings
M-x tibetan-cat-version  # Show version info
```

## Keybindings

### Segment Analysis
| Key | Function |
|-----|----------|
| `C-c u i` | Segment analysis (Bialek grammar + verb stems) |
| `C-c u I` | Enhanced segment analysis (improved parsing) |
| `C-c u A` | Persistent segment analysis (with notes) |
| `C-c u R` | Re-analyze segment (keep notes) |
| `C-c u E` | Toggle auto-analysis mode |

### Compound/Verse Analysis
| Key | Function |
|-----|----------|
| `C-c v v` | Quick verse analysis (meter + vocab) |
| `C-c v A` | Persistent compound analysis |
| `C-c v R` | Re-analyze compound (keep notes) |

### Translation
| Key | Function |
|-----|----------|
| `C-c u t` | Generate CAT translation |
| `C-c u T` | Translate selected region |
| `C-c s w` | Sentence workspace |

### Vocabulary
| Key | Function |
|-----|----------|
| `C-c u v` | Reload all glossaries |

## Text Classification

Add a header to your document to specify text type:

```org
#+TIBETAN_TEXT_TYPE: classical
#+TIBETAN_CONTEXT: gelug-madhyamaka
```

Supported types:
- `classical` - Uses Bialek grammar for prose texts
- `madhyamaka-verse` - Uses philology tools for verse texts
- `kagyu-verse` - Kagyu tradition verse analysis

## Architecture

```
tibetan-cat.el/
├── tibetan-cat.el          # Main entry point
├── core/                   # Core utilities
│   ├── tibetan-utils.el
│   ├── tibetan-wylie.el
│   ├── tibetan-vocabulary.el
│   └── tibetan-text-classifier.el
├── analysis/               # Grammar & translation
│   ├── tibetan-classroom.el
│   ├── tibetan-particles-bialek.el
│   ├── tibetan-verb-classifier.el
│   └── tibetan-enhanced-parser.el
├── workspace/              # Translation workspace
├── philology/              # Verse analysis
├── persist/                # Persistent analysis
├── config/                 # Keybindings
└── data/glossaries/        # Bundled dictionaries (25MB)
```

## Bundled Glossaries

- **Rangjung Yeshe** - 162,000+ entries
- **Hopkins** - Tibetan-Sanskrit-English
- **Madhyamaka Specialized** - Technical philosophical terms
- **Unified Tibetan** - Additional vocabulary

## Requirements

- Emacs 27.1+
- org-mode 9.0+

### Recommended Fonts

- Tibetan Machine Uni (free)
- Noto Sans Tibetan (free)
- Kailasa (macOS built-in)

## Development

```bash
# Run tests
make test

# Quick tests
make test-quick

# Byte-compile
make compile

# Clean
make clean
```

## History

### Version 2.1.0 (2025-01)
- Bundled glossaries (standalone package)
- GitHub distribution ready
- Installation automation (Makefile, install.sh)
- MELPA-compatible package headers

### Version 2.0.0 (2025-12)
- Enhanced parsing with multi-word units
- Persistent analysis with notes
- Compound/verse analysis
- Mitra AI translation integration

### Version 1.0.0 (2025-11)
- Modular refactoring
- Centralized keybindings
- DharmaMitra vocabulary fallback
- Context-aware particle analysis

## Author

Carsten Paul <post@carstenpaul.de>

## License

GPL-3.0 - See [LICENSE](LICENSE) file.

---

*Enhancing Tibetan translation pedagogy through computational tools*
