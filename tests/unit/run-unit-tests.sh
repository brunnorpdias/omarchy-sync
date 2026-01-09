#!/bin/bash
# run-unit-tests.sh - Unit test runner

set -euo pipefail

UNIT_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$UNIT_TEST_DIR")")"

# Source the test setup
source "$UNIT_TEST_DIR/../setup.sh"

# Unit test counters
UNIT_PASSED=0
UNIT_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Unit test assertions
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assertion failed}"
    if [[ "$expected" == "$actual" ]]; then
        UNIT_PASSED=$((UNIT_PASSED + 1))
        return 0
    else
        UNIT_FAILED=$((UNIT_FAILED + 1))
        echo -e "  ${RED}FAIL:${NC} $msg"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local msg="${2:-value should not be empty}"
    if [[ -n "$value" ]]; then
        UNIT_PASSED=$((UNIT_PASSED + 1))
        return 0
    else
        UNIT_FAILED=$((UNIT_FAILED + 1))
        echo -e "  ${RED}FAIL:${NC} $msg"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-'$needle' not found in output}"
    if [[ "$haystack" == *"$needle"* ]]; then
        UNIT_PASSED=$((UNIT_PASSED + 1))
        return 0
    else
        UNIT_FAILED=$((UNIT_FAILED + 1))
        echo -e "  ${RED}FAIL:${NC} $msg"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local msg="${2:-condition should be true}"
    if eval "$condition"; then
        UNIT_PASSED=$((UNIT_PASSED + 1))
        return 0
    else
        UNIT_FAILED=$((UNIT_FAILED + 1))
        echo -e "  ${RED}FAIL:${NC} $msg"
        return 1
    fi
}

# Setup for unit tests - sets HOME and sources modules
setup_unit_test_env() {
    create_test_env
    HOME="$TEST_HOME"
    export HOME
    CONFIG_DIR="$HOME/.config/omarchy-sync"
    CONFIG_FILE="$CONFIG_DIR/config.toml"
    DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"
    export CONFIG_DIR CONFIG_FILE DEFAULT_LOCAL_PATH

    # Source library modules
    source "$PROJECT_DIR/lib/helpers.sh"
    source "$PROJECT_DIR/lib/config.sh"
    source "$PROJECT_DIR/lib/metadata.sh"
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    echo -e "${YELLOW}  Testing:${NC} $test_name"

    # Reset test environment for each test
    setup_unit_test_env

    # Run the test function
    if "$test_func"; then
        echo -e "  ${GREEN}PASS${NC}"
    else
        echo -e "  ${RED}FAIL${NC}"
    fi
}

echo "=== Omarchy-Sync Unit Tests ==="
echo ""

# Set up initial test environment once
setup_unit_test_env

# Collect and run all test files
for test_file in "$UNIT_TEST_DIR"/test-*.sh; do
    if [[ -f "$test_file" ]]; then
        echo ""
        echo "--- $(basename "$test_file") ---"
        source "$test_file"
    fi
done

echo ""
echo "=== Unit Test Summary ==="
echo -e "Passed: ${GREEN}$UNIT_PASSED${NC}"
echo -e "Failed: ${RED}$UNIT_FAILED${NC}"

# Cleanup
cleanup_test_env

# Exit with failure if any tests failed
[[ "$UNIT_FAILED" -eq 0 ]]
