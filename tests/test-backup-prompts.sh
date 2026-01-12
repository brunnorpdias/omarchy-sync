#!/bin/bash
# test-backup-prompts.sh - Test backup prompts and interactive workflow

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Helper to run commands with isolated HOME
# ============================================================================
run_isolated() {
    HOME="$TEST_HOME" "$OMARCHY_SYNC" "$@"
}

# ============================================================================
# Backup Prompt Tests
# ============================================================================

test_backup_completes_without_errors() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Run backup and capture output
    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should reach the end without error
    if echo "$output" | grep -q "Backup complete\|DONE"; then
        return 0
    else
        log_fail "Backup should complete successfully. Output:\n$output"
        return 1
    fi
}

test_backup_shows_local_backup_message() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should show local backup is being done
    if echo "$output" | grep -q "Backing up to local\|Syncing"; then
        return 0
    else
        log_fail "Backup should show local backup progress"
        return 1
    fi
}

test_backup_shows_filesystem_type() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should show filesystem type in brackets
    if echo "$output" | grep -q "\[.*\]"; then
        return 0
    else
        log_fail "Backup should show filesystem type like [btrfs]"
        return 1
    fi
}

test_backup_no_prompt_mode_skips_external() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Run backup with --no-prompt flag
    local output
    output=$(run_isolated --no-prompt --backup 2>&1 || true)

    # Should NOT ask for external drive backup
    if ! echo "$output" | grep -q "external drive"; then
        return 0
    else
        log_fail "--no-prompt should not ask about external drives"
        return 1
    fi
}

test_backup_continues_after_internal_drive_error() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Add internal drive config pointing to inaccessible location
    local config_path
    config_path=$(get_config_path)

    cat >> "$config_path" << 'EOF'

[[internal_drives]]
path = "/tmp/nonexistent-location-12345"
label = "Broken Drive"
EOF

    # Backup should continue despite broken internal drive
    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should complete successfully
    if echo "$output" | grep -q "Backup complete\|DONE"; then
        return 0
    else
        log_fail "Backup should continue even if internal drive is unavailable"
        return 1
    fi
}

test_backup_logs_skipped_files() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should log skipped large files
    if echo "$output" | grep -q "Skipped\|large"; then
        return 0
    else
        log_fail "Backup should log skipped large files"
        return 1
    fi
}

test_backup_logs_symlinks_recorded() {
    create_test_env

    # Create symlinks
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should log symlinks recorded
    if echo "$output" | grep -q "symlink"; then
        return 0
    else
        log_fail "Backup should log symlinks being recorded"
        return 1
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_backup_completes_without_errors \
            test_backup_shows_local_backup_message \
            test_backup_shows_filesystem_type \
            test_backup_no_prompt_mode_skips_external \
            test_backup_continues_after_internal_drive_error \
            test_backup_logs_skipped_files \
            test_backup_logs_symlinks_recorded; do

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
echo "Backup Prompt Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
