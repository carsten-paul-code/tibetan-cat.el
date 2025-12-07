#!/bin/bash
# Run all Tibetan CAT tests
# Usage: ./run-tests.sh [pattern]
#   pattern: Optional ERT selector (e.g., "tibetan-verb" to run only verb tests)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Tibetan CAT Test Suite"
echo "========================================="
echo ""

# Build selector
if [ -n "$1" ]; then
    SELECTOR="\"$1\""
    echo -e "${YELLOW}Running tests matching: $1${NC}"
else
    SELECTOR="t"
    echo "Running all tests..."
fi
echo ""

# Run tests
emacs -batch \
    -l "$TEST_DIR/run-all-tests.el" \
    --eval "(ert-run-tests-batch-and-exit $SELECTOR)" \
    2>&1

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}All tests passed!${NC}"
    echo -e "${GREEN}=========================================${NC}"
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}Some tests failed (exit code: $EXIT_CODE)${NC}"
    echo -e "${RED}=========================================${NC}"
fi

exit $EXIT_CODE
