# Emacs Tibetan CAT (Computer-Assisted Translation)

A modular Emacs-based Computer-Assisted Translation system for Tibetan Buddhist texts, designed for classroom use.

## Features

### 📖 Segment Analysis (C-c u i)
- **Tibetan Text** - Original text display
- **Wylie Transliteration** - Fixed vowel placement for reading aloud
- **DharmaMitra Translation** - Automatic translation from external API
- **Vocabulary** - Word-by-word meanings with DharmaMitra fallback
- **Grammatical Analysis** - Context-aware particle identification with:
  - Particle type (GEN, ERG, ABL, SEQ, CAUSAL)
  - Function in specific context
  - Translation guidance
  - Schwieger textbook references

### 📝 Sentence Workspace (C-c s w)
- **Line-by-line Format** - Aligned Tibetan/Wylie/Vocabulary
- **Grammatical Analysis** - Per-segment context-aware analysis
- **Translation Section** - Editable translation area
- **Notes Section** - Study notes and commentary

### ⚡ Auto-Analysis Mode (C-c u E)
- Automatically updates analysis as you navigate through text
- Perfect for quick review sessions

## Installation

### Prerequisites

1. **Emacs 27.1+** with lexical binding support
2. **Glossary files** - 17,777 entry comprehensive Tibetan-English dictionary
3. **DharmaMitra API** (optional) - For vocabulary fallback

### Quick Start

1. Clone or copy to `~/emacs-tibetan-cat/`:

```bash
cd ~
cp -r /path/to/emacs-tibetan-cat ~/emacs-tibetan-cat
```

2. Add to your `~/.emacs.d/init.el`:

```elisp
;; Load Tibetan CAT system
(add-to-list 'load-path "~/emacs-tibetan-cat/")
(require 'tibetan-cat)

;; Load glossaries (required)
(load-file "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")

;; Load DharmaMitra (optional, for fallback)
(add-to-list 'load-path "~/emacs-pkgs/dharmamitra/")
(require 'dharmamitra nil t)
```

3. Restart Emacs or evaluate the code with `M-x eval-buffer`

### Verification

Test that the system is loaded:

```
M-x tibetan-cat-version
```

Should display: "Tibetan CAT v1.0.0 - Classroom Edition"

## Usage

### Basic Workflow

1. Open a Tibetan text file with segment markers:
   ```
   〔seg:1〕ཕུག་རོན་གསུམ་ཞིག〔/seg〕
   〔seg:2〕ཀུན་ཏུ་འཕུར་ཞིང་〔/seg〕
   〔seg:3〕རྩེ་བ་ལས།〔/seg〕
   ```

2. Place cursor in a segment

3. Press `C-c u i` to see analysis in right window

4. Navigate through segments - analysis updates automatically with `C-c u E`

### Sentence Workspace

1. Mark sentence boundaries in your text:
   ```
   ** Sentence 1
   〔seg:1〕ཕུག་རོན་གསུམ་ཞིག〔/seg〕
   〔seg:2〕ཀུན་ཏུ་འཕུར་ཞིང་〔/seg〕
   〔seg:3〕རྩེ་བ་ལས།〔/seg〕
   ```

2. Place cursor in the sentence

3. Press `C-c s w` to create workspace below

4. Edit translation and notes in the workspace

5. Save with `C-c C-c` (if implemented)

## Keybindings

All keybindings are centralized in `config/tibetan-keybindings.el`

### Segment Analysis
- `C-c u i` - Show segment analysis (right window)
- `C-c u E` - Toggle auto-analysis mode
- `C-c u e` - Same as above (lowercase)

### Sentence Workspace
- `C-c s w` - Create sentence workspace (below window)

### Vocabulary
- `C-c u v` - Reload all glossaries

## Architecture

### Modular Structure

```
emacs-tibetan-cat/
├── tibetan-cat.el              # Main entry point
│
├── core/                       # Core functionality
│   ├── tibetan-utils.el       # Utility functions
│   ├── tibetan-wylie.el       # Wylie conversion
│   └── tibetan-vocabulary.el  # Vocabulary lookup
│
├── analysis/                   # Analysis modules
│   ├── tibetan-particles.el   # Particle analysis
│   └── tibetan-classroom.el   # Segment analysis
│
├── workspace/                  # Workspace modules
│   └── tibetan-sentence-workspace.el
│
├── config/                     # Configuration
│   └── tibetan-keybindings.el # All keybindings
│
├── data/                       # Data files
│   └── glossaries/            # Vocabulary files
│
└── legacy/                     # Archived legacy code
```

### Module Dependencies

```
tibetan-cat.el
  ├── core/tibetan-utils.el
  ├── core/tibetan-wylie.el
  ├── core/tibetan-vocabulary.el
  ├── analysis/tibetan-particles.el
  │   └── requires: tibetan-utils
  ├── analysis/tibetan-classroom.el
  │   └── requires: tibetan-utils, tibetan-wylie, tibetan-vocabulary, tibetan-particles
  ├── workspace/tibetan-sentence-workspace.el
  │   └── requires: tibetan-utils, tibetan-wylie, tibetan-vocabulary, tibetan-particles
  └── config/tibetan-keybindings.el
```

## Customization

### Adding New Keybindings

Edit `config/tibetan-keybindings.el`:

```elisp
(global-set-key (kbd "C-c u n") 'your-new-function)
```

### Extending Functionality

1. **Add new analysis types** - Create module in `analysis/`
2. **Add new workspace types** - Create module in `workspace/`
3. **Add utility functions** - Extend `core/tibetan-utils.el`

### Vocabulary Sources

The system uses a two-tier vocabulary lookup:

1. **Local glossaries** (17,777 entries) - Fast, instant lookup
   - Hopkins Tibetan-Sanskrit-English Dictionary
   - Bialek Classical Tibetan Dictionary
   - Additional specialized glossaries

2. **DharmaMitra API** (optional) - Fallback for missing words
   - Cached to avoid repeated API calls
   - Automatic cleanup of results

## Troubleshooting

### Analysis shows "[look up]" for common words

**Solution**: Reload glossaries with `C-c u v`

### Wylie conversion shows wrong vowels

**Problem**: Using old wylie converter
**Solution**: System includes fixed version (`core/tibetan-wylie.el`)

### Auto-analysis not working

**Solution**: Toggle off and on with `C-c u E`

### DharmaMitra fallback not working

1. Check DharmaMitra is installed:
   ```elisp
   M-: (fboundp 'dharmamitra-text-get-translation)
   ```
   Should return `t`

2. Reload system:
   ```elisp
   M-x eval-buffer
   ```

## Development

### Running Tests

```bash
emacs --batch -l tibetan-cat.el -f ert-run-tests-batch-and-exit
```

### Code Style

- Use lexical binding: `;;; -*- lexical-binding: t -*-`
- Prefix all functions with `tibetan-`
- Document all public functions
- Keep modules focused and single-purpose

## History

### Version 1.0.0 (2025-11-07)

- ✨ Modular refactoring complete
- ✨ Centralized keybindings
- ✨ DharmaMitra vocabulary fallback
- ✨ Context-aware particle analysis
- ✨ Fixed Wylie transliteration
- ✨ Line-by-line sentence workspace
- 📚 Comprehensive documentation

### Previous Versions

- Monolithic `init.el` configuration (pre-1.0.0)
- Multiple test files and iterations
- Integrated classroom analysis tools

## Contributing

This is a specialized tool for Buddhist Studies classroom use. Contributions welcome:

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Submit pull request

## License

This tool was developed for academic use in Buddhist Studies.

## Credits

- **Development**: For classroom use at Buddhist Studies program
- **Wylie Converter**: Fixed vowel placement algorithm
- **DharmaMitra**: External translation API integration
- **Schwieger References**: Based on "A Tibetan Grammar" textbook

## Contact

For questions, issues, or feature requests, please create an issue in the repository.

---

**Tibetan CAT v1.0.0** - *Enhancing Tibetan translation pedagogy through computational tools*
