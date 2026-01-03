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

### Prerequisites

1. **Emacs 27.1 or later** - Download from [gnu.org/software/emacs](https://www.gnu.org/software/emacs/)
2. **Tibetan fonts** - Install at least one:
   - [Tibetan Machine Uni](https://collab.its.virginia.edu/access/content/group/26a34146-33a6-48ce-001e-f16ce7908a6a/Tibetan%20fonts/Tibetan%20Unicode%20fonts/TibetanMachineUnicodeFont.zip) (recommended)
   - [Noto Sans Tibetan](https://fonts.google.com/noto/specimen/Noto+Sans+Tibetan) (Google)
   - Kailasa (built-in on macOS)

### Option 1: use-package with straight.el (Recommended)

Add to your `~/.emacs.d/init.el`:

```elisp
;; Install straight.el if not present
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 6))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; Install tibetan-cat
(use-package tibetan-cat
  :straight (:host github :repo "carsten-paul-code/tibetan-cat.el")
  :config
  (tibetan-cat-setup))
```

### Option 2: Git Clone

```bash
git clone https://github.com/carsten-paul-code/tibetan-cat.el.git ~/.emacs.d/tibetan-cat
```

Add to your `~/.emacs.d/init.el`:

```elisp
(add-to-list 'load-path "~/.emacs.d/tibetan-cat")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/core")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/analysis")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/workspace")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/philology")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/persist")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/config")
(add-to-list 'load-path "~/.emacs.d/tibetan-cat/data")
(require 'tibetan-cat)
(tibetan-cat-setup)
```

### Option 3: Manual Installation Script

```bash
cd ~/path/to/tibetan-cat.el
./install.sh
```

Or use make:

```bash
make install
```

## Recommended: UI Enhancement Package

For a better visual experience, install the companion UI package:

```elisp
(use-package emacs-ui-essentials
  :straight (:host github :repo "carsten-paul-code/emacs-ui-essentials")
  :config
  (ui-essentials-setup))
```

This provides:
- Modern modeline with doom-modeline
- File tree sidebar with Treemacs
- All-the-icons support
- Dashboard on startup
- Better window management

## Quick Start

### 1. Open a Tibetan Text File

Create a new file `test.org` with Tibetan content:

```org
#+TITLE: Test Translation
#+TIBETAN_TEXT_TYPE: classical

བྱང་ཆུབ་སེམས་དཔའི་སྤྱོད་པ་ལ་འཇུག་པ།
```

### 2. Analyze a Segment

1. Place your cursor on the Tibetan line
2. Press `C-c u i` (Control-c, then u, then i)
3. A buffer will appear with:
   - Word-by-word breakdown
   - Grammatical analysis
   - Dictionary definitions
   - Verb classifications

### 3. Open Translation Workspace

1. Select a Tibetan sentence
2. Press `C-c s w`
3. An editable workspace opens with:
   - Original Tibetan text
   - Wylie transliteration
   - Space for your translation
   - Vocabulary sidebar

### 4. Enable Auto-Analysis

Press `C-c u E` to toggle auto-analysis mode. As you move between lines, the analysis updates automatically.

## Usage Examples

### Analyzing Classical Prose

For texts like the Bodhicaryāvatāra commentary:

```org
#+TIBETAN_TEXT_TYPE: classical
#+TIBETAN_CONTEXT: madhyamaka

སེམས་བསྐྱེད་པ་ནི་སེམས་ཅན་ཐམས་ཅད་ཀྱི་དོན་དུ་བྱང་ཆུབ་ཐོབ་པར་བྱ་བའི་ཕྱིར།
```

1. Place cursor on the Tibetan line
2. `C-c u i` shows:
   - སེམས་བསྐྱེད་པ་ = "generating the mind" (bodhicitta)
   - ནི་ = topic marker
   - སེམས་ཅན་ = sentient beings
   - ཐམས་ཅད་ = all
   - ཀྱི་ = genitive particle
   - དོན་དུ་ = "for the purpose of"
   - བྱང་ཆུབ་ = enlightenment (bodhi)
   - ཐོབ་པར་བྱ་བ་ = "to obtain" (purposive)
   - འི་ཕྱིར = "because/for"

### Analyzing Verse

For metrical texts:

```org
#+TIBETAN_TEXT_TYPE: madhyamaka-verse

གང་ཞིག་རྟེན་ཅིང་འབྲེལ་འབྱུང་བ།
```

1. Use `C-c v v` for verse analysis
2. Shows:
   - Syllable count (7-syllable meter)
   - Metrical pattern
   - Vocabulary with verse-specific meanings

### Persistent Analysis with Notes

For study sessions where you want to save your observations:

1. `C-c u A` - Opens persistent analysis
2. Add your notes in the designated section
3. `C-c u R` - Re-analyze while keeping your notes

## Complete Keybindings Reference

### Segment Analysis
| Key | Function | Description |
|-----|----------|-------------|
| `C-c u i` | `tibetan-segment-analysis` | Basic segment analysis |
| `C-c u I` | `tibetan-enhanced-segment-analysis` | Enhanced parsing with compounds |
| `C-c u A` | `tibetan-persistent-segment-analysis` | Analysis with notes (saved) |
| `C-c u R` | `tibetan-reanalyze-segment` | Re-analyze, keep notes |
| `C-c u E` | `tibetan-toggle-auto-analysis` | Toggle auto-analysis mode |

### Compound/Verse Analysis
| Key | Function | Description |
|-----|----------|-------------|
| `C-c v v` | `tibetan-quick-verse-analysis` | Quick verse/meter analysis |
| `C-c v A` | `tibetan-persistent-compound-analysis` | Compound analysis with notes |
| `C-c v R` | `tibetan-reanalyze-compound` | Re-analyze compound |

### Translation
| Key | Function | Description |
|-----|----------|-------------|
| `C-c u t` | `tibetan-cat-translate` | Generate CAT translation |
| `C-c u T` | `tibetan-translate-region` | Translate selected region |
| `C-c s w` | `tibetan-sentence-workspace` | Open translation workspace |

### Vocabulary
| Key | Function | Description |
|-----|----------|-------------|
| `C-c u v` | `tibetan-reload-glossaries` | Reload all dictionaries |

### Utility
| Key | Function | Description |
|-----|----------|-------------|
| `M-x tibetan-cat-setup` | | Show all keybindings |
| `M-x tibetan-cat-version` | | Show version info |

## Text Classification

Add headers to configure analysis behavior:

```org
#+TIBETAN_TEXT_TYPE: classical
#+TIBETAN_CONTEXT: gelug-madhyamaka
#+TIBETAN_TRADITION: gelug
```

### Text Types

| Type | Description | Best For |
|------|-------------|----------|
| `classical` | Bialek grammar analysis | Prose commentaries |
| `madhyamaka-verse` | Verse tools + Madhyamaka terms | Mūlamadhyamakakārikā |
| `kagyu-verse` | Kagyu tradition vocabulary | Mahāmudrā texts |
| `tantra` | Tantric terminology | Tantric texts |

### Contexts

| Context | Specialized Vocabulary |
|---------|----------------------|
| `madhyamaka` | Emptiness, two truths, etc. |
| `yogacara` | Mind-only, ālayavijñāna, etc. |
| `abhidharma` | Dharma categories, aggregates |
| `vinaya` | Monastic discipline terms |

## Architecture

```
tibetan-cat.el/
├── tibetan-cat.el              # Main entry point & loader
├── core/                       # Core utilities
│   ├── tibetan-utils.el        # Helper functions
│   ├── tibetan-wylie.el        # Wylie transliteration
│   ├── tibetan-vocabulary.el   # Dictionary lookup
│   └── tibetan-text-classifier.el  # Text type detection
├── analysis/                   # Grammar & translation
│   ├── tibetan-classroom.el    # Segment analysis
│   ├── tibetan-particles-bialek.el  # Particle grammar
│   ├── tibetan-verb-classifier.el   # Verb stems (Hill 2010)
│   └── tibetan-enhanced-parser.el   # Advanced parsing
├── workspace/                  # Translation workspace
│   └── tibetan-sentence-workspace.el
├── philology/                  # Verse analysis
│   └── tibetan-philology.el
├── persist/                    # Persistent analysis
│   └── tibetan-persist-analysis.el
├── config/                     # Configuration
│   └── tibetan-keybindings.el
└── data/glossaries/            # Bundled dictionaries (~25MB)
    ├── rangjung-yeshe-tibetan.txt
    ├── rangjung-yeshe-wylie.txt
    ├── hopkins-tib-skt-eng.txt
    └── madhyamaka-specialized.txt
```

## Bundled Glossaries

| Dictionary | Entries | Description |
|------------|---------|-------------|
| Rangjung Yeshe | 162,000+ | Comprehensive Tibetan-English |
| Hopkins | 18,000+ | Tibetan-Sanskrit-English |
| Madhyamaka | 2,000+ | Technical philosophical terms |
| Unified Tibetan | 5,000+ | Additional vocabulary |

Total: ~25MB of lexical data, loaded on demand.

## Troubleshooting

### Tibetan Text Not Displaying

1. Check font installation:
   ```elisp
   M-x describe-font RET
   ```

2. Set Tibetan font explicitly:
   ```elisp
   (set-fontset-font t 'tibetan "Tibetan Machine Uni")
   ```

### Analysis Not Working

1. Ensure glossaries are loaded:
   ```elisp
   M-x tibetan-reload-glossaries
   ```

2. Check text type is set:
   ```org
   #+TIBETAN_TEXT_TYPE: classical
   ```

### Slow Performance

The first analysis may be slow while loading dictionaries. Subsequent lookups are cached.

To pre-load dictionaries:
```elisp
(add-hook 'emacs-startup-hook #'tibetan-vocabulary-initialize)
```

## Development

```bash
# Run tests
make test

# Quick tests (no glossary loading)
make test-quick

# Byte-compile
make compile

# Clean compiled files
make clean
```

## Version History

### Version 2.1.0 (January 2025)
- Bundled glossaries (standalone package)
- GitHub distribution ready
- Installation automation (Makefile, install.sh)
- MELPA-compatible package headers

### Version 2.0.0 (December 2024)
- Enhanced parsing with multi-word units
- Persistent analysis with notes
- Compound/verse analysis
- Mitra AI translation integration

### Version 1.0.0 (November 2024)
- Modular refactoring
- Centralized keybindings
- DharmaMitra vocabulary fallback
- Context-aware particle analysis

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

Areas where help is appreciated:
- Additional glossary entries
- Grammar rule refinements
- Documentation translations
- Bug reports

## References

- Bialek, J. (2022). *Tibetan Grammar*. Comprehensive particle analysis.
- Hill, N. (2010). *A Lexicon of Tibetan Verb Stems*. Verb classification system.
- Rangjung Yeshe Dictionary. Primary lexical resource.

## Author

Carsten Paul <post@carstenpaul.de>

## License

GPL-3.0 - See [LICENSE](LICENSE) file.

---

*Enhancing Tibetan translation pedagogy through computational tools*
