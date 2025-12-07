#!/bin/bash
# Run all BDD specifications
# Usage: ./run-specs.sh [tag]
#   tag: Optional tag filter (e.g., "regression", "critical", "verbs")

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="$SCRIPT_DIR/spec"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}Tibetan CAT - BDD Specifications${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

if [ -n "$1" ]; then
    echo -e "${YELLOW}Filter: $1${NC}"
fi
echo ""

# Run specs
emacs -batch \
    -l "$SPEC_DIR/run-specs.el" \
    2>&1

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}All specifications passed!${NC}"
    echo -e "${GREEN}=========================================${NC}"
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Some specifications failed!${NC}"
    echo -e "${RED}=========================================${NC}"
fi

exit $EXIT_CODE
