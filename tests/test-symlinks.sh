#!/bin/bash
# test-symlinks.sh - Test symlink manifest creation and restoration

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Symlink Test Cases
# ============================================================================

test_symlink_manifest_creation() {
    create_test_env

    # Create symlinks in test environment
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    ln -s "../other-config" "$TEST_HOME/.config/app/link-to-other"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify .symlinks manifest exists
    if ! assert_file_exists "$backup_path/.symlinks" "Symlink manifest should be created"; then
        return 1
    fi

    # Verify manifest contains symlink entries
    if ! assert_file_contains "$backup_path/.symlinks" ".local/bin/my-bash" "Manifest should contain symlink entry"; then
        return 1
    fi

    if ! assert_file_contains "$backup_path/.symlinks" ".config/app/link-to-other" "Manifest should contain nested symlink entry"; then
        return 1
    fi

    return 0
}

test_symlink_manifest_format() {
    create_test_env

    # Create a symlink
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify format: path|target (pipe-separated)
    if ! assert_file_contains "$backup_path/.symlinks" "|" "Manifest should use pipe-separated format"; then
        return 1
    fi

    # Verify HOME-relative path format (.local/bin/... not /home/user/.local/bin/...)
    if ! assert_file_contains "$backup_path/.symlinks" "^\.local/bin/" "Manifest should use HOME-relative paths"; then
        return 1
    fi

    return 0
}

test_symlink_count_logged() {
    create_test_env

    # Create multiple symlinks
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    ln -s /usr/bin/sh "$TEST_HOME/.local/bin/my-sh"
    ln -s /usr/share/doc "$TEST_HOME/.config/doc-link"

    # Initialize and backup, capture output
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    local output
    output=$(run_omarchy --backup 2>&1 || true)

    # Check that symlink count is logged
    if echo "$output" | grep -q "Recorded.*symlink"; then
        return 0
    else
        log_fail "Backup should log symlink count"
        return 1
    fi
}

test_symlink_restoration_creates_symlinks() {
    create_test_env

    # Create and backup symlinks
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    ln -s /usr/share/doc "$TEST_HOME/.config/doc-link"

    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    # Now simulate restoring: remove the symlink and replace with regular file
    local backup_path
    backup_path=$(get_backup_path)

    if [[ -L "$TEST_HOME/.local/bin/my-bash" ]]; then
        rm "$TEST_HOME/.local/bin/my-bash"
        echo "regular file content" > "$TEST_HOME/.local/bin/my-bash"
    fi

    # Restore from backup (using --test for safety)
    printf '1\nn\n' | run_omarchy --restore 2>&1 || true

    # Check that symlink was restored
    if [[ -L "$TEST_HOME/.local/bin/my-bash" ]]; then
        return 0
    else
        log_fail "Symlink should be restored from manifest"
        return 1
    fi
}

test_symlink_not_recreated_if_already_symlink() {
    create_test_env

    # Create symlink
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    # Restore (symlink already exists as symlink, should be skipped)
    printf '1\nn\n' | run_omarchy --restore 2>&1 || true

    # Symlink should still be a symlink
    if [[ -L "$TEST_HOME/.local/bin/my-bash" ]]; then
        return 0
    else
        log_fail "Existing symlink should be preserved"
        return 1
    fi
}

test_broken_symlinks_preserved() {
    create_test_env

    # Create symlink to non-existent target
    ln -s /nonexistent/path "$TEST_HOME/.local/bin/broken-link"
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify broken symlink is recorded
    if assert_file_contains "$backup_path/.symlinks" "broken-link" "Broken symlinks should be recorded"; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_symlink_manifest_creation \
            test_symlink_manifest_format \
            test_symlink_count_logged \
            test_symlink_restoration_creates_symlinks \
            test_symlink_not_recreated_if_already_symlink \
            test_broken_symlinks_preserved; do

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
echo "Symlink Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
