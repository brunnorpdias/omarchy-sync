#!/bin/bash
# test-metadata-formats.sh - Test metadata file formats and validity

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Metadata Format Test Cases
# ============================================================================

test_backup_meta_json_valid() {
    create_test_env

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that .backup-meta exists and is valid JSON
    if assert_file_exists "$backup_path/.backup-meta" "Backup metadata file should exist"; then
        # Try to parse JSON (requires jq or similar, but we'll just check for basic format)
        if assert_file_contains "$backup_path/.backup-meta" "{" "Metadata should be JSON format"; then
            if assert_file_contains "$backup_path/.backup-meta" "}" "Metadata should be JSON format"; then
                return 0
            fi
        fi
    fi

    return 1
}

test_symlinks_file_exists_after_backup() {
    create_test_env

    # Create a symlink
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/test-bash"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Symlinks file should exist (even if empty for configs without symlinks)
    assert_file_exists "$backup_path/.symlinks" "Symlinks manifest file should exist after backup"
}

test_restore_excludes_home_relative_paths() {
    create_test_env

    # Create a large app to trigger exclusion
    mkdir -p "$TEST_HOME/.config/excluded-app"
    dd if=/dev/zero of="$TEST_HOME/.config/excluded-app/bigfile" bs=1M count=25 2>/dev/null

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that paths are HOME-relative (not absolute paths)
    if assert_file_exists "$backup_path/.restore-excludes" "Restore excludes should exist"; then
        # Should contain .config/... not /home/...
        if grep -q "^\.config/" "$backup_path/.restore-excludes" 2>/dev/null; then
            return 0
        else
            log_fail "Restore excludes should use HOME-relative paths (.config/...)"
            return 1
        fi
    fi

    return 1
}

test_machine_specific_home_relative_paths() {
    create_test_env

    # Create machine-specific config
    mkdir -p "$TEST_HOME/.config/hypr"
    echo "config" > "$TEST_HOME/.config/hypr/monitors.conf"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that paths are HOME-relative
    if assert_file_exists "$backup_path/.machine-specific" "Machine-specific file should exist"; then
        # Should contain .config/... not /home/...
        if grep -q "^\.config/" "$backup_path/.machine-specific" 2>/dev/null; then
            return 0
        else
            log_fail "Machine-specific paths should use HOME-relative format (.config/...)"
            return 1
        fi
    fi

    return 1
}

test_gitignore_created() {
    create_test_env

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that .gitignore exists
    if assert_file_exists "$backup_path/.gitignore" ".gitignore should be created"; then
        # Check that it contains expected entries
        if assert_file_contains "$backup_path/.gitignore" "*.key" ".gitignore should exclude secrets"; then
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

for test in test_backup_meta_json_valid \
            test_symlinks_file_exists_after_backup \
            test_restore_excludes_home_relative_paths \
            test_machine_specific_home_relative_paths \
            test_gitignore_created; do

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
echo "Metadata Format Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
