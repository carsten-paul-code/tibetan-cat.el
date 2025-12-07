#!/bin/bash
# Run all Tibetan CAT tests: Unit tests + BDD specs
# Usage: ./run-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

TOTAL_FAILED=0

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         TIBETAN CAT - FULL TEST SUITE               ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# PART 1: Unit Tests (ERT)
# ============================================================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Part 1: Unit Tests (ERT)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

"$SCRIPT_DIR/run-tests.sh" || TOTAL_FAILED=$((TOTAL_FAILED + 1))

echo ""

# ============================================================================
# PART 2: BDD Specifications
# ============================================================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Part 2: BDD Specifications${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

"$SCRIPT_DIR/run-specs.sh" || TOTAL_FAILED=$((TOTAL_FAILED + 1))

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
if [ $TOTAL_FAILED -eq 0 ]; then
    echo -e "${GREEN}║              ALL TESTS PASSED                       ║${NC}"
else
    echo -e "${RED}║          $TOTAL_FAILED TEST SUITE(S) FAILED                      ║${NC}"
fi
echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"

exit $TOTAL_FAILED
