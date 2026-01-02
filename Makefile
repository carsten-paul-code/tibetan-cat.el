# Makefile for tibetan-cat.el
# Tibetan Computer-Assisted Translation System for Emacs

EMACS ?= emacs
PACKAGE_NAME = tibetan-cat
VERSION = 2.1.0
INSTALL_DIR = ~/.emacs.d/tibetan-cat

.PHONY: all install uninstall test clean compile help

all: help

help:
	@echo "tibetan-cat.el - Tibetan CAT for Emacs"
	@echo ""
	@echo "Usage:"
	@echo "  make install    - Install to ~/.emacs.d/tibetan-cat/"
	@echo "  make uninstall  - Remove installation"
	@echo "  make test       - Run test suite"
	@echo "  make compile    - Byte-compile all .el files"
	@echo "  make clean      - Remove compiled files"
	@echo ""
	@echo "After installation, add to your init.el:"
	@echo '  (add-to-list '\''load-path "~/.emacs.d/tibetan-cat/")'
	@echo '  (require '\''tibetan-cat)'

install:
	@echo "Installing tibetan-cat.el to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@cp -r core analysis workspace philology persist config data $(INSTALL_DIR)/
	@cp tibetan-cat.el $(INSTALL_DIR)/
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "Add to your ~/.emacs.d/init.el:"
	@echo '  (add-to-list '\''load-path "~/.emacs.d/tibetan-cat/")'
	@echo '  (require '\''tibetan-cat)'
	@echo ""
	@echo "Then restart Emacs or run: M-x eval-buffer"

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
		-f batch-byte-compile \
		tibetan-cat.el \
		core/*.el \
		analysis/*.el \
		workspace/*.el \
		philology/*.el \
		persist/*.el \
		config/*.el \
		data/*.el

clean:
	@echo "Cleaning compiled files..."
	@find . -name "*.elc" -delete
	@echo "Done."
