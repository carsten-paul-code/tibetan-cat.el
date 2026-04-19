# Makefile for tibetan-cat.el
# Tibetan Computer-Assisted Translation System for Emacs

EMACS ?= emacs
PACKAGE_NAME = tibetan-cat
VERSION = 2.1.0
INSTALL_DIR = ~/.emacs.d/tibetan-cat

.PHONY: all install uninstall test clean compile help docs docs-bdd docs-ert docs-funcs build-steinert

all: help

help:
	@echo "tibetan-cat.el - Tibetan CAT for Emacs"
	@echo ""
	@echo "Usage:"
	@echo "  make install    - Install to ~/.emacs.d/tibetan-cat/"
	@echo "  make uninstall  - Remove installation"
	@echo "  make test       - Run test suite"
	@echo "  make compile    - Byte-compile all .el files"
	@echo "  make docs       - Generate all living documentation (HTML)"
	@echo "  make docs-bdd   - Generate BDD spec documentation only"
	@echo "  make docs-ert   - Generate ERT test documentation only"
	@echo "  make docs-funcs - Generate function overview with test coverage"
	@echo "  make build-steinert - Build Steinert SQLite dictionary (needs steinert-src/)"
	@echo "  make clean      - Remove compiled files"
	@echo ""
	@echo "After installation, add to your init.el:"
	@echo '  (add-to-list '\''load-path "~/.emacs.d/tibetan-cat/")'
	@echo '  (require '\''tibetan-cat)'

install:
	@echo "Installing tibetan-cat.el to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@cp -r core analysis workspace philology persist config data doc-prep setup $(INSTALL_DIR)/
	@cp tibetan-cat.el $(INSTALL_DIR)/
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "Add to your ~/.emacs.d/init.el:"
	@echo '  (add-to-list '\''load-path "~/.emacs.d/tibetan-cat/")'
	@echo '  (require '\''tibetan-cat)'
	@echo ""
	@echo "Then restart Emacs or run: M-x eval-buffer"

build-steinert:
	@echo "Building Steinert SQLite dictionary..."
	@if [ ! -d steinert-src/_input/dictionaries/public ]; then \
	  echo "ERROR: steinert-src/ missing."; \
	  echo "Clone https://github.com/christian-steinert/dictionary into steinert-src/ first."; \
	  exit 2; \
	fi
	@python3 scripts/build-steinert-db.py
	@echo "Done: data/dictionaries/steinert.db"

uninstall:
	@echo "Removing $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)
	@echo "Uninstalled. Don't forget to remove the lines from your init.el"

test:
	@echo "Running tibetan-cat.el tests..."
	$(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-L spec \
		-L test \
		-l tibetan-cat.el \
		-l spec/run-specs.el \
		-f tibetan-bdd-run-all-specs

test-quick:
	@echo "Running quick tests..."
	$(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-L test \
		-l tibetan-cat.el \
		-l test/run-all-tests.el \
		-f ert-run-tests-batch-and-exit

compile:
	@echo "Byte-compiling..."
	$(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-f batch-byte-compile \
		tibetan-cat.el \
		core/*.el \
		analysis/*.el \
		workspace/*.el \
		philology/*.el \
		persist/*.el \
		config/*.el \
		data/*.el \
		doc-prep/*.el \
		setup/*.el

docs: docs-bdd docs-ert docs-funcs
	@echo "Open docs/living-documentation.html, docs/test-documentation.html, and docs/function-overview.html in your browser."

docs-bdd:
	@mkdir -p docs
	@echo "Generating BDD living documentation..."
	PROJECT_ROOT=$(CURDIR) $(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-L spec \
		-L test \
		-l tibetan-cat.el \
		-l spec/generate-living-doc.el \
		-f tibetan-bdd-generate-living-doc

docs-ert:
	@mkdir -p docs
	@echo "Generating ERT test documentation..."
	PROJECT_ROOT=$(CURDIR) $(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-L spec \
		-L test \
		-l tibetan-cat.el \
		-l test/run-all-tests.el \
		-l test/generate-test-doc.el \
		-f tibetan-ert-generate-living-doc

docs-funcs:
	@mkdir -p docs
	@echo "Generating function overview..."
	PROJECT_ROOT=$(CURDIR) $(EMACS) --batch \
		-L . \
		-L core \
		-L analysis \
		-L workspace \
		-L philology \
		-L persist \
		-L config \
		-L data \
		-L doc-prep \
		-L setup \
		-L spec \
		-L test \
		-l tibetan-cat.el \
		-l test/run-all-tests.el \
		-l test/generate-test-doc.el \
		-l test/generate-func-overview.el \
		-f tibetan-func-overview-generate

clean:
	@echo "Cleaning compiled files..."
	@find . -name "*.elc" -delete
	@echo "Done."
