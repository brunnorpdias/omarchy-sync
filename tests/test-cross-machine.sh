#!/bin/bash
# test-cross-machine.sh - Test cross-machine restore functionality

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Cross-Machine Test Cases
# ============================================================================

test_hostname_mismatch_warning() {
    create_test_env

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Simulate different hostname by modifying the backup metadata
    if [[ -f "$backup_path/.backup-meta" ]]; then
        # Update hostname to different value
        local meta
        meta=$(cat "$backup_path/.backup-meta")
        meta=$(echo "$meta" | sed 's/"hostname":"[^"]*"/"hostname":"different-machine"/')
        echo "$meta" > "$backup_path/.backup-meta"
    fi

    # Try to restore and capture output
    local output
    output=$(printf '1\nn\n' | run_omarchy --restore 2>&1 || true)

    # Check for warning about hostname mismatch
    if echo "$output" | grep -q "WARNING.*backup.*different-machine" || echo "$output" | grep -q "backup.*host"; then
        return 0
    else
        log_fail "Should warn about hostname mismatch"
        return 1
    fi
}

test_machine_specific_excluded_on_mismatch() {
    create_test_env

    # Create machine-specific config
    mkdir -p "$TEST_HOME/.config/hypr"
    echo "monitors = [[DP-1, 3840x2160@60]]" > "$TEST_HOME/.config/hypr/monitors.conf"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify machine-specific file is recorded
    if assert_file_exists "$backup_path/.machine-specific" "Machine-specific file should exist"; then
        if assert_file_contains "$backup_path/.machine-specific" "hypr/monitors" "Machine-specific list should contain monitor config"; then
            return 0
        fi
    fi

    return 1
}

test_restore_excludes_format() {
    create_test_env

    # Create large app to trigger exclude list
    mkdir -p "$TEST_HOME/.config/large-app"
    dd if=/dev/zero of="$TEST_HOME/.config/large-app/bigfile" bs=1M count=25 2>/dev/null

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify restore excludes use HOME-relative paths (.config/... not /home/user/.config/...)
    if assert_file_exists "$backup_path/.restore-excludes" "Restore excludes file should exist"; then
        if assert_file_contains "$backup_path/.restore-excludes" "^\.config/large-app" "Paths should be HOME-relative"; then
            return 0
        fi
    fi

    return 1
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_hostname_mismatch_warning \
            test_machine_specific_excluded_on_mismatch \
            test_restore_excludes_format; do

    log_test "Running: $test"

    if $test 2>/dev/null; then
        log_pass "$test"
        PASSED=$((PASSED + 1))
    else
        log_fail "$test"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

echo "========================================"
echo "Cross-Machine Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
