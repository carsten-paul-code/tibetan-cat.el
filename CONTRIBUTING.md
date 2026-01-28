# Contributing to tibetan-cat.el

Thank you for your interest in contributing to the Tibetan CAT system! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful, inclusive, and constructive. We're building tools for Buddhist studies, so let's embody the values of compassion and wisdom in our collaboration.

## Getting Started

### Prerequisites

1. **Emacs 27.1+** - Required for lexical-binding and modern features
2. **Git** - For version control
3. **Make** (optional) - For build automation

### Setting Up Development Environment

```bash
# Clone the repository
git clone https://github.com/carsten-paul-code/tibetan-cat.el.git
cd tibetan-cat.el

# Run tests to verify setup
make test

# Or without make
emacs -batch -l test/run-all-tests.el
```

### Project Structure

```
tibetan-cat.el/
├── tibetan-cat.el       # Main entry point
├── core/                # Core utilities (utils, wylie, vocabulary)
├── analysis/            # Grammar analysis modules
├── workspace/           # Translation workspace
├── philology/           # Verse analysis
├── persist/             # Persistent analysis with notes
├── doc-prep/            # Document preparation (OCR, formatting)
├── config/              # Keybindings, menus
├── data/glossaries/     # Dictionary files
├── test/                # Unit tests
└── spec/                # BDD specifications
```

## How to Contribute

### Reporting Bugs

1. Check existing issues first
2. Create a new issue with:
   - Emacs version (`M-x emacs-version`)
   - tibetan-cat version (`M-x tibetan-cat-version`)
   - Steps to reproduce
   - Expected vs actual behavior
   - Sample Tibetan text if relevant

### Suggesting Features

1. Open an issue with the "enhancement" label
2. Describe the use case
3. Explain how it fits with existing functionality

### Submitting Code

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Write code** following our style guide (below)
4. **Add tests** for new functionality
5. **Run tests**:
   ```bash
   make test
   ```
6. **Commit** with clear messages:
   ```
   Add verb classification for imperative stems

   - Extend tibetan-verb-classifier with imperative detection
   - Add test cases for common imperatives
   - Update documentation
   ```
7. **Push** and create a Pull Request

## Code Style

### Elisp Conventions

```elisp
;;; module-name.el --- Short description -*- lexical-binding: t -*-

;;; Commentary:
;; Longer description of what this module does.
;; Include references to academic sources if applicable.

;;; Code:

(require 'cl-lib)

;; Use defcustom for user-configurable options
(defcustom tibetan-feature-enabled t
  "Whether to enable this feature.
When non-nil, does something useful."
  :type 'boolean
  :group 'tibetan-cat)

;; Use defvar for internal state
(defvar tibetan--internal-cache nil
  "Internal cache. Do not modify directly.")

;; Prefix private functions with double-dash
(defun tibetan--internal-helper (arg)
  "Internal helper for ARG."
  ...)

;; Public functions use single-dash or no prefix
(defun tibetan-public-function (text)
  "Process TEXT and return result.
This is a public API function."
  ...)

(provide 'module-name)
;;; module-name.el ends here
```

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Public function | `tibetan-feature-action` | `tibetan-analyze-segment` |
| Private function | `tibetan--helper` | `tibetan--parse-particles` |
| Variable | `tibetan-feature-name` | `tibetan-default-text-type` |
| Constant | `tibetan-CONSTANT` | `tibetan-SHAD` |
| Customization | `tibetan-feature-option` | `tibetan-auto-save-enabled` |

### Documentation

- Every public function needs a docstring
- First line: brief summary ending with period
- Include parameter descriptions
- Reference academic sources for grammar rules

```elisp
(defun tibetan-classify-particle (particle context)
  "Classify PARTICLE according to Bialek grammar.
CONTEXT is the surrounding text for disambiguation.

Returns a plist with :type, :function, and :reference.

Reference: Bialek (2022), Chapter 4."
  ...)
```

## Testing

### Running Tests

```bash
# All tests
make test

# Quick tests (skip glossary loading)
make test-quick

# Specific test file
emacs -batch -l test/tibetan-utils-test.el -f ert-run-tests-batch
```

### Writing Tests

Use ERT (Emacs Lisp Regression Testing):

```elisp
;;; tibetan-feature-test.el --- Tests for feature

(require 'ert)
(require 'tibetan-feature)

(ert-deftest tibetan-feature-basic-test ()
  "Test basic feature functionality."
  (should (equal (tibetan-feature-function "input") "expected")))

(ert-deftest tibetan-feature-edge-case ()
  "Test edge case handling."
  (should-error (tibetan-feature-function nil)))

(provide 'tibetan-feature-test)
```

### BDD Specifications

We use a custom BDD framework for behavioral specs:

```elisp
(tibetan-describe "Particle Analysis"
  (tibetan-it "identifies topic markers"
    (let ((result (tibetan-analyze-particles "སེམས་ནི་")))
      (tibetan-expect (plist-get result :type) :to-equal 'topic-marker)))

  (tibetan-it "handles agentive case"
    (let ((result (tibetan-analyze-particles "བདག་གིས་")))
      (tibetan-expect (plist-get result :case) :to-equal 'agentive))))
```

## Areas for Contribution

### High Priority

1. **Test Coverage** - Many modules need more tests
2. **Grammar Rules** - Refine particle analysis based on Bialek
3. **Verb Database** - Extend Hill 2010 verb entries

### Medium Priority

4. **Documentation** - Improve inline docstrings
5. **OCR Integration** - Better BDRC OCR support
6. **Performance** - Optimize dictionary lookups

### Low Priority (But Welcome)

7. **UI Improvements** - Better display formatting
8. **Additional Dictionaries** - More specialized vocabulary
9. **Translations** - Documentation in other languages

## Glossary Contributions

To add dictionary entries:

1. Edit `data/glossaries/unified-tibetan.txt`
2. Format: `tibetan_word|english_definition|pos|source`
3. Example: `བདག་|self, I, ego|n|contributor`

For specialized terminology:
- Madhyamaka: `data/glossaries/madhyamaka-specialized.txt`
- Yogacara: Create `data/glossaries/yogacara-specialized.txt`

## Questions?

- Open an issue with the "question" label
- Email: post@carstenpaul.de

## License

By contributing, you agree that your contributions will be licensed under the GPL-3.0 license.

---

*Thank you for helping improve Tibetan translation tools!*
