#!/bin/bash
# install.sh - Install tibetan-cat.el for Emacs
#
# Usage:
#   ./install.sh              # Install to ~/.emacs.d/tibetan-cat/
#   ./install.sh /custom/path # Install to custom location
#
# Author: Carsten Paul <post@carstenpaul.de>
# URL: https://github.com/carsten-paul-code/tibetan-cat.el

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default installation directory
INSTALL_DIR="${1:-$HOME/.emacs.d/tibetan-cat}"

# Get script directory (where tibetan-cat.el source is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  tibetan-cat.el Installer"
echo "  Tibetan Computer-Assisted Translation"
echo "============================================"
echo ""

# Check for Emacs
if ! command -v emacs &> /dev/null; then
    echo -e "${RED}Error: Emacs is not installed or not in PATH${NC}"
    echo "Please install Emacs 27.1 or later"
    exit 1
fi

# Check Emacs version
EMACS_VERSION=$(emacs --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
MAJOR_VERSION=$(echo "$EMACS_VERSION" | cut -d. -f1)

if [ "$MAJOR_VERSION" -lt 27 ]; then
    echo -e "${YELLOW}Warning: Emacs $EMACS_VERSION detected. Version 27.1+ recommended.${NC}"
fi

echo "Installing to: $INSTALL_DIR"
echo ""

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Copy files
echo "Copying files..."
cp -r "$SCRIPT_DIR/core" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/analysis" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/workspace" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/philology" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/persist" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/config" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/data" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/tibetan-cat.el" "$INSTALL_DIR/"

echo -e "${GREEN}Files copied successfully!${NC}"
echo ""

# Calculate glossary size
GLOSSARY_SIZE=$(du -sh "$INSTALL_DIR/data/glossaries" 2>/dev/null | cut -f1 || echo "unknown")
echo "Glossary size: $GLOSSARY_SIZE (includes 162K+ Rangjung Yeshe entries)"
echo ""

# Check for Tibetan fonts
echo "Checking for Tibetan fonts..."
FONTS_FOUND=0

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS font check
    if fc-list 2>/dev/null | grep -qi "tibetan\|kailasa\|jomolhari"; then
        FONTS_FOUND=1
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux font check
    if fc-list 2>/dev/null | grep -qi "tibetan"; then
        FONTS_FOUND=1
    fi
fi

if [ $FONTS_FOUND -eq 1 ]; then
    echo -e "${GREEN}Tibetan fonts found${NC}"
else
    echo -e "${YELLOW}Warning: No Tibetan fonts detected${NC}"
    echo "Recommended fonts:"
    echo "  - Tibetan Machine Uni (free)"
    echo "  - Noto Sans Tibetan (free)"
    echo "  - Kailasa (macOS built-in)"
fi
echo ""

# Generate init.el snippet
INIT_SNIPPET="
;; Tibetan CAT - Computer-Assisted Translation
(add-to-list 'load-path \"$INSTALL_DIR\")
(require 'tibetan-cat)
"

echo "============================================"
echo -e "${GREEN}Installation complete!${NC}"
echo "============================================"
echo ""
echo "Add the following to your ~/.emacs.d/init.el:"
echo ""
echo -e "${YELLOW}$INIT_SNIPPET${NC}"
echo ""
echo "Then restart Emacs or run: M-x eval-buffer"
echo ""
echo "Quick start:"
echo "  M-x tibetan-cat-setup    - Show keybinding summary"
echo "  M-x tibetan-cat-version  - Show version info"
echo "  C-c u i                  - Analyze Tibetan segment"
echo ""
