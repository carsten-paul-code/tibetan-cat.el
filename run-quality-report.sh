#!/bin/bash
# Generate a quality report for the Tibetan CAT project
# Runs all tests and specs, captures structured output to a file
# Usage: cd ~/tibetan-cat.el && bash run-quality-report.sh

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="$SCRIPT_DIR/quality-report.txt"

echo "=== TIBETAN CAT QUALITY REPORT ===" > "$REPORT_FILE"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "Emacs: $(emacs --version 2>&1 | head -1)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ============================================================================
# PART 1: Unit Tests (ERT)
# ============================================================================
echo "--- UNIT TESTS (ERT) ---" >> "$REPORT_FILE"
echo "Running unit tests..."

emacs -batch \
    -l "$SCRIPT_DIR/test/run-all-tests.el" \
    --eval "(ert-run-tests-batch-and-exit t)" \
    2>&1 | tee -a "$REPORT_FILE"

UNIT_EXIT=$?
echo "" >> "$REPORT_FILE"
echo "UNIT_TEST_EXIT_CODE=$UNIT_EXIT" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ============================================================================
# PART 2: BDD Specifications
# ============================================================================
echo "--- BDD SPECIFICATIONS ---" >> "$REPORT_FILE"
echo "Running BDD specs..."

emacs -batch \
    -l "$SCRIPT_DIR/spec/run-specs.el" \
    2>&1 | tee -a "$REPORT_FILE"

SPEC_EXIT=$?
echo "" >> "$REPORT_FILE"
echo "SPEC_EXIT_CODE=$SPEC_EXIT" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ============================================================================
# PART 3: Byte-compile check (catches undefined functions, unused vars, etc.)
# ============================================================================
echo "--- BYTE-COMPILE WARNINGS ---" >> "$REPORT_FILE"
echo "Running byte-compile check..."

# Byte-compile each source file and capture warnings
for dir in core analysis persist workspace philology doc-prep config; do
    for f in "$SCRIPT_DIR/$dir"/*.el; do
        [ -f "$f" ] || continue
        echo "Checking: $dir/$(basename "$f")" >> "$REPORT_FILE"
        emacs -batch \
            -l "$SCRIPT_DIR/test/run-all-tests.el" \
            --eval "(progn
                      (setq byte-compile-error-on-warn nil)
                      (byte-compile-file \"$f\"))" \
            2>&1 | grep -E "(Warning|Error|free variable|not known)" >> "$REPORT_FILE" 2>/dev/null
    done
done

# Clean up .elc files
find "$SCRIPT_DIR" -name "*.elc" -delete 2>/dev/null

echo "" >> "$REPORT_FILE"

# ============================================================================
# SUMMARY
# ============================================================================
echo "--- SUMMARY ---" >> "$REPORT_FILE"
echo "Unit test exit code: $UNIT_EXIT" >> "$REPORT_FILE"
echo "BDD spec exit code: $SPEC_EXIT" >> "$REPORT_FILE"

if [ $UNIT_EXIT -eq 0 ] && [ $SPEC_EXIT -eq 0 ]; then
    echo "OVERALL: ALL PASSED" >> "$REPORT_FILE"
else
    echo "OVERALL: FAILURES DETECTED" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "=== END OF REPORT ===" >> "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"
echo "Done! Please share this file or paste its contents."
