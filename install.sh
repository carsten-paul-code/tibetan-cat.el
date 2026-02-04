#!/usr/bin/env bash
#
# Tibetan CAT - Installer
# Computer-Assisted Translation for Classical Tibetan
#
# Usage:
#   ./install.sh              # Interactive install (all modules)
#   ./install.sh --core       # Core only (no UI)
#   ./install.sh --help       # Show help
#
# Requirements:
#   - macOS or Linux
#   - Emacs 27.1+ (will install via Homebrew if missing on macOS)
#

set -e

# ============================================================================
# COLORS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  ${BLUE}[INFO]${NC} $1"; }
step() { echo -e "\n${BOLD}$1${NC}"; }

# ============================================================================
# CONFIGURATION
# ============================================================================

INSTALL_DIR="${HOME}/tibetan-cat.el"
REPO_URL="https://github.com/carsten-paul-code/tibetan-cat.el.git"
EMACS_DIR="${HOME}/.emacs.d"

# Parse arguments
INSTALL_UI=true
INSTALL_FONTS=true
CONFIGURE_INIT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --core)
            INSTALL_UI=false
            shift
            ;;
        --no-fonts)
            INSTALL_FONTS=false
            shift
            ;;
        --no-init)
            CONFIGURE_INIT=false
            shift
            ;;
        --help|-h)
            echo "Tibetan CAT Installer"
            echo ""
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --core       Install core only (no UI packages)"
            echo "  --no-fonts   Skip font installation"
            echo "  --no-init    Don't modify init.el"
            echo "  --help       Show this help"
            echo ""
            echo "Modules:"
            echo "  Core:  Tibetan CAT analysis, vocabulary (162K+ entries),"
            echo "         verb classification, grammar analysis"
            echo "  UI:    Treemacs, doom-modeline, dashboard, beacon,"
            echo "         which-key, vertico, org-bullets"
            echo "  Fonts: Jomolhari, Noto Serif Tibetan (macOS only)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# ============================================================================
# BANNER
# ============================================================================

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}  Tibetan CAT - Computer-Assisted Translation${NC}"
echo -e "${BOLD}  Installation Script${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""

# ============================================================================
# STEP 1: CHECK / INSTALL PREREQUISITES
# ============================================================================

step "Step 1: Checking prerequisites"

# Check OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    ok "macOS detected"
elif [[ "$OSTYPE" == "linux"* ]]; then
    OS="linux"
    ok "Linux detected"
else
    warn "Unknown OS: $OSTYPE (proceeding anyway)"
    OS="other"
fi

# Check/install Homebrew (macOS only)
if [[ "$OS" == "macos" ]]; then
    if command -v brew &>/dev/null; then
        ok "Homebrew installed"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add to PATH for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    fi
fi

# Check/install Emacs
if command -v emacs &>/dev/null; then
    EMACS_VERSION=$(emacs --version | head -1 | grep -oE '[0-9]+\.[0-9]+')
    ok "Emacs ${EMACS_VERSION} found"
else
    if [[ "$OS" == "macos" ]]; then
        info "Installing Emacs via Homebrew..."
        brew install --cask emacs
        ok "Emacs installed"
    elif [[ "$OS" == "linux" ]]; then
        info "Installing Emacs..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y emacs
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y emacs
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm emacs
        else
            fail "Cannot auto-install Emacs. Please install manually."
            exit 1
        fi
        ok "Emacs installed"
    else
        fail "Emacs not found. Please install Emacs 27.1+ manually."
        exit 1
    fi
fi

# Check/install Git
if command -v git &>/dev/null; then
    ok "Git installed"
else
    fail "Git not found. Please install git."
    exit 1
fi

# ============================================================================
# STEP 2: CLONE OR UPDATE REPOSITORY
# ============================================================================

step "Step 2: Getting Tibetan CAT"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull origin main 2>/dev/null || git pull
    ok "Updated to latest version"
else
    if [[ -d "$INSTALL_DIR" ]]; then
        warn "Directory exists but is not a git repo: $INSTALL_DIR"
        warn "Backing up to ${INSTALL_DIR}.bak"
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)"
    fi
    info "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    ok "Cloned to $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# Verify glossary data
if [[ -f "data/glossaries/rangjung-yeshe-tibetan.txt" ]]; then
    ENTRIES=$(wc -l < "data/glossaries/rangjung-yeshe-tibetan.txt" | tr -d ' ')
    ok "Rangjung Yeshe dictionary: ${ENTRIES} entries"
else
    warn "Rangjung Yeshe dictionary not found in repo"
fi

# ============================================================================
# STEP 3: INSTALL FONTS (macOS)
# ============================================================================

if [[ "$INSTALL_FONTS" == "true" && "$OS" == "macos" ]]; then
    step "Step 3: Installing Tibetan fonts"

    # Check if fonts are already installed
    if system_profiler SPFontsDataType 2>/dev/null | grep -qi "jomolhari\|tibetan machine\|noto.*tibetan"; then
        ok "Tibetan fonts already installed"
    else
        info "Installing Tibetan fonts..."
        brew install --cask font-jomolhari 2>/dev/null || \
            warn "Could not install Jomolhari (try: brew tap homebrew/cask-fonts first)"
        brew install --cask font-noto-serif-tibetan 2>/dev/null || \
            warn "Could not install Noto Serif Tibetan"
        ok "Font installation attempted"
    fi
else
    if [[ "$INSTALL_FONTS" == "false" ]]; then
        info "Step 3: Skipping font installation (--no-fonts)"
    else
        info "Step 3: Font auto-install only on macOS. Install manually:"
        info "  Jomolhari: https://fonts.google.com/specimen/Jomolhari"
    fi
fi

# ============================================================================
# STEP 4: CONFIGURE EMACS
# ============================================================================

step "Step 4: Configuring Emacs"

# Create .emacs.d if needed
mkdir -p "$EMACS_DIR"

if [[ "$CONFIGURE_INIT" == "true" ]]; then
    INIT_FILE="$EMACS_DIR/init.el"

    if [[ -f "$INIT_FILE" ]] && grep -q "tibetan-cat" "$INIT_FILE" 2>/dev/null; then
        ok "Already configured in init.el"
    else
        info "Adding Tibetan CAT to init.el..."

        # Create init.el if it doesn't exist
        touch "$INIT_FILE"

        # Build the block to insert
        LOAD_BLOCK="
;; ============================================================================
;; TIBETAN CAT (Computer-Assisted Translation)
;; ============================================================================
(load \"${INSTALL_DIR}/tibetan-cat.el\")"

        if [[ "$INSTALL_UI" == "true" ]]; then
            LOAD_BLOCK="${LOAD_BLOCK}
(add-to-list 'load-path \"${INSTALL_DIR}/setup\")
(require 'tibetan-cat-ui)
(add-hook 'after-init-hook #'tibetan-cat-ui-setup)"
        fi

        # Append to init.el
        echo "$LOAD_BLOCK" >> "$INIT_FILE"
        ok "Added to $INIT_FILE"
    fi
else
    info "Skipping init.el configuration (--no-init)"
    info "Add this to your init.el manually:"
    echo ""
    echo "  (load \"${INSTALL_DIR}/tibetan-cat.el\")"
    echo ""
fi

# ============================================================================
# STEP 5: INSTALL EMACS PACKAGES
# ============================================================================

if [[ "$INSTALL_UI" == "true" ]]; then
    step "Step 5: Installing Emacs packages"
    info "This may take a minute on first install..."

    EMACS_BIN=$(command -v emacs)
    # On macOS, prefer the .app version if available
    if [[ "$OS" == "macos" && -x "/Applications/Emacs.app/Contents/MacOS/Emacs" ]]; then
        EMACS_BIN="/Applications/Emacs.app/Contents/MacOS/Emacs"
    fi

    $EMACS_BIN --batch \
        --eval "(require 'package)" \
        --eval "(setq package-archives '((\"melpa\" . \"https://melpa.org/packages/\") (\"gnu\" . \"https://elpa.gnu.org/packages/\")))" \
        --eval "(package-initialize)" \
        --eval "(package-refresh-contents)" \
        --eval "(dolist (pkg '(treemacs treemacs-projectile doom-modeline all-the-icons dashboard beacon dimmer which-key org-bullets vertico orderless marginalia company projectile popup)) (unless (package-installed-p pkg) (condition-case nil (package-install pkg) (error (message \"Could not install %s\" pkg)))))" \
        --eval "(message \"Package installation complete\")" \
        2>&1 | tail -5

    ok "Emacs packages installed"
else
    info "Step 5: Skipping UI packages (--core)"
fi

# ============================================================================
# DONE
# ============================================================================

echo ""
echo -e "${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo -e "${BOLD}================================================================${NC}"
echo ""
echo "  Install directory: $INSTALL_DIR"
echo "  Dictionaries:      162K+ entries (Rangjung Yeshe)"
echo "                     18K+ entries (Hopkins, Madhyamaka, etc.)"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    1. Start Emacs"
echo "    2. Open a .org file with Tibetan text"
echo "    3. C-c u A  -- Open segment analysis"
echo "    4. C-c u B  -- Batch analyze all segments"
echo ""
echo -e "  ${BOLD}Keybinding reference:${NC}  M-x tibetan-cat-setup"
echo -e "  ${BOLD}System status:${NC}         M-x tibetan-cat-status"
echo ""
