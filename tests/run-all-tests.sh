#!/bin/bash
# run-all-tests.sh - Master test runner for all test suites

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# Test counters
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

echo "=========================================="
echo "  Omarchy-Sync Full Test Suite"
echo "=========================================="
echo ""

# Run integration tests first
echo "Running Integration Tests..."
echo "=========================================="
if "$SCRIPT_DIR/run-tests.sh"; then
    echo ""
    echo "Integration tests: PASSED"
else
    echo ""
    echo "Integration tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Unit Tests..."
echo "=========================================="
if "$SCRIPT_DIR/unit/run-unit-tests.sh"; then
    echo ""
    echo "Unit tests: PASSED"
else
    echo ""
    echo "Unit tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Filesystem Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-filesystems.sh"; then
    echo ""
    echo "Filesystem tests: PASSED"
else
    echo ""
    echo "Filesystem tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Symlink Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-symlinks.sh"; then
    echo ""
    echo "Symlink tests: PASSED"
else
    echo ""
    echo "Symlink tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Cross-Machine Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-cross-machine.sh"; then
    echo ""
    echo "Cross-machine tests: PASSED"
else
    echo ""
    echo "Cross-machine tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Metadata Format Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-metadata-formats.sh"; then
    echo ""
    echo "Metadata format tests: PASSED"
else
    echo ""
    echo "Metadata format tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Secrets Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-secrets.sh"; then
    echo ""
    echo "Secrets tests: PASSED"
else
    echo ""
    echo "Secrets tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Browser Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-browser.sh"; then
    echo ""
    echo "Browser tests: PASSED"
else
    echo ""
    echo "Browser tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Backup Integration Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-backup-integration.sh"; then
    echo ""
    echo "Backup integration tests: PASSED"
else
    echo ""
    echo "Backup integration tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Git Workflow Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-git-workflow.sh"; then
    echo ""
    echo "Git workflow tests: PASSED"
else
    echo ""
    echo "Git workflow tests: FAILED"
fi

echo ""
echo "=========================================="
echo "Running Backup Prompt Tests..."
echo "=========================================="
if "$SCRIPT_DIR/test-backup-prompts.sh"; then
    echo ""
    echo "Backup prompt tests: PASSED"
else
    echo ""
    echo "Backup prompt tests: FAILED"
fi

echo ""
echo "=========================================="
echo "All Test Suites Complete"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Integration tests (10 tests)"
echo "- Unit tests (21 tests)"
echo "- Filesystem tests (11 tests)"
echo "- Symlink tests (6 tests)"
echo "- Cross-machine tests (3 tests)"
echo "- Metadata format tests (5 tests)"
echo "- Secrets tests (3 tests)"
echo "- Browser tests (4 tests)"
echo "- Backup integration tests (12 tests) - REAL BACKUP WORKFLOW"
echo "- Git workflow tests (4 tests)"
echo "- Backup prompt tests (7 tests)"
echo ""
echo "Total: 86+ tests (47+ real integration/workflow tests)"
echo "=========================================="

# Cleanup
cleanup_test_env
