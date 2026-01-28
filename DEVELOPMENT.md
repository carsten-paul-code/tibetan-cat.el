# Development Guide

This guide covers setting up a development environment and common development tasks for tibetan-cat.el.

## Quick Start

```bash
# Clone
git clone https://github.com/carsten-paul-code/tibetan-cat.el.git
cd tibetan-cat.el

# Run tests
make test

# Start Emacs with the package loaded
make run
```

## Development Environment

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Emacs | 27.1+ | Runtime environment |
| Git | 2.0+ | Version control |
| Make | 3.0+ | Build automation (optional) |

### Recommended Emacs Packages

```elisp
;; For development
(use-package flycheck)          ; Syntax checking
(use-package elisp-slime-nav)   ; Navigate to definitions
(use-package macrostep)         ; Expand macros
(use-package ert-runner)        ; Test runner
```

### Directory Structure

```
tibetan-cat.el/
├── tibetan-cat.el       # Main entry point (load this)
├── core/                # Core modules
├── analysis/            # Analysis engines
├── workspace/           # Translation workspace
├── philology/           # Verse analysis
├── persist/             # Persistent storage
├── doc-prep/            # Document preparation
├── config/              # Configuration
├── data/glossaries/     # Dictionary files (25MB)
├── test/                # Unit tests
├── spec/                # BDD specifications
├── Makefile             # Build automation
└── install.sh           # Installation script
```

## Development Workflow

### Loading the Package

From Emacs:

```elisp
;; Load for development
(add-to-list 'load-path "~/path/to/tibetan-cat.el")
(add-to-list 'load-path "~/path/to/tibetan-cat.el/core")
(add-to-list 'load-path "~/path/to/tibetan-cat.el/analysis")
;; ... other subdirectories

(require 'tibetan-cat)
```

Or use the Makefile:

```bash
make run  # Starts Emacs with package loaded
```

### Making Changes

1. Edit the relevant `.el` file
2. Reload the module: `M-x load-file RET path/to/file.el`
3. Test your changes interactively
4. Write/run tests

### Byte Compilation

```bash
# Compile all files
make compile

# Check for warnings
make lint

# Clean compiled files
make clean
```

## Testing

### Running All Tests

```bash
# Full test suite
make test

# Quick tests (no glossary loading)
make test-quick

# Verbose output
make test-verbose
```

### Running Specific Tests

```bash
# Single test file
emacs -batch -l test/tibetan-utils-test.el -f ert-run-tests-batch

# Single test by name
emacs -batch -l test/tibetan-utils-test.el \
  -eval "(ert-run-tests-batch-and-exit 'tibetan-utils-split-syllables)"
```

### Running BDD Specs

```bash
# All specs
emacs -batch -l spec/run-specs.el

# Specific spec file
emacs -batch -l spec/segment-analysis-spec.el -f tibetan-bdd-run-specs
```

### Writing Tests

Create a test file in `test/`:

```elisp
;;; tibetan-my-feature-test.el --- Tests for my feature

(require 'ert)
(require 'tibetan-my-feature)

(ert-deftest tibetan-my-feature-basic ()
  "Test basic functionality."
  (should (equal (tibetan-my-function "input") "output")))

(ert-deftest tibetan-my-feature-tibetan-text ()
  "Test with actual Tibetan."
  (let ((result (tibetan-my-function "བདག་")))
    (should (stringp result))
    (should (string-match-p "self" result))))

(ert-deftest tibetan-my-feature-error-handling ()
  "Test error handling."
  (should-error (tibetan-my-function nil) :type 'wrong-type-argument))

(provide 'tibetan-my-feature-test)
;;; tibetan-my-feature-test.el ends here
```

### Writing BDD Specs

Create a spec file in `spec/`:

```elisp
;;; my-feature-spec.el --- BDD specs for my feature

(require 'tibetan-bdd)
(require 'tibetan-my-feature)

(tibetan-describe "My Feature"
  (tibetan-context "with valid input"
    (tibetan-it "returns expected result"
      (let ((result (tibetan-my-function "བདག་")))
        (tibetan-expect result :to-equal "self")))

    (tibetan-it "handles particles"
      (let ((result (tibetan-my-function "བདག་གི་")))
        (tibetan-expect result :to-contain "genitive"))))

  (tibetan-context "with invalid input"
    (tibetan-it "returns nil for empty string"
      (tibetan-expect (tibetan-my-function "") :to-be-nil))

    (tibetan-it "signals error for nil"
      (tibetan-expect (tibetan-my-function nil) :to-throw 'error))))

(provide 'my-feature-spec)
```

## Debugging

### Interactive Debugging

```elisp
;; Enable debug on error
(setq debug-on-error t)

;; Set a breakpoint
(debug)  ; Insert in code where you want to stop

;; Trace a function
(trace-function 'tibetan-analyze-segment)
(untrace-function 'tibetan-analyze-segment)
```

### Logging

```elisp
;; Enable verbose logging
(setq tibetan-debug-mode t)

;; View messages
(switch-to-buffer "*Messages*")

;; Custom debug output
(tibetan--debug "Processing: %s" some-variable)
```

### Common Issues

#### Glossary Not Loading

```elisp
;; Check glossary path
(message "Glossary dir: %s" tibetan-cat-data-dir)

;; Manual reload
(tibetan-vocabulary-reload)

;; Check hash table
(hash-table-count tibetan-comprehensive-vocabulary)
```

#### Keybindings Not Working

```elisp
;; Check if function exists
(fboundp 'tibetan-segment-info)

;; Check keybinding
(key-binding (kbd "C-c u i"))

;; Reload keybindings
(load-file "config/tibetan-keybindings.el")
```

#### Analysis Returning Empty

```elisp
;; Check text type
(tibetan-get-text-type)

;; Check if on valid segment
(tibetan-org-get-current-segment)

;; Test vocabulary lookup
(tibetan-vocabulary-lookup "བདག")
```

## Performance Profiling

```elisp
;; Profile a function
(profiler-start 'cpu+mem)
(tibetan-analyze-segment)
(profiler-stop)
(profiler-report)

;; Time a specific operation
(benchmark-run 10
  (tibetan-vocabulary-lookup "བྱང་ཆུབ"))
```

## Release Process

### Version Bump

1. Update version in `tibetan-cat.el`:
   ```elisp
   ;; Version: X.Y.Z
   (defconst tibetan-cat-version "X.Y.Z")
   ```

2. Update README.md version history

3. Create CHANGELOG entry

### Creating a Release

```bash
# Ensure tests pass
make test

# Byte-compile
make compile

# Tag the release
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z

# Create GitHub release with changelog
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make test` | Run all tests |
| `make test-quick` | Run tests without glossary |
| `make compile` | Byte-compile all files |
| `make lint` | Check for style issues |
| `make clean` | Remove compiled files |
| `make run` | Start Emacs with package |
| `make install` | Install to ~/.emacs.d |
| `make docs` | Generate documentation |

## Code Organization Patterns

### Module Template

```elisp
;;; tibetan-module.el --- Brief description -*- lexical-binding: t -*-

;; Author: Your Name <email@example.com>
;; Keywords: languages, tibetan

;;; Commentary:
;; Detailed description of the module.
;; Include academic references if applicable.

;;; Code:

(require 'cl-lib)
(require 'tibetan-utils)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defgroup tibetan-module nil
  "Module description."
  :group 'tibetan-cat)

(defcustom tibetan-module-option t
  "Option description."
  :type 'boolean
  :group 'tibetan-module)

;; ============================================================================
;; INTERNAL VARIABLES
;; ============================================================================

(defvar tibetan-module--cache nil
  "Internal cache.")

;; ============================================================================
;; INTERNAL FUNCTIONS
;; ============================================================================

(defun tibetan-module--helper (arg)
  "Internal helper for ARG."
  ...)

;; ============================================================================
;; PUBLIC API
;; ============================================================================

;;;###autoload
(defun tibetan-module-function (text)
  "Process TEXT and return result."
  (interactive "sText: ")
  ...)

(provide 'tibetan-module)
;;; tibetan-module.el ends here
```

## Getting Help

- Open an issue on GitHub
- Email: post@carstenpaul.de
- Check existing tests for examples
