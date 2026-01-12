#!/bin/bash
# test-backup-integration.sh - Real end-to-end backup tests

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# Helper to run commands with isolated HOME (without --test mode for backup)
run_isolated() {
    HOME="$TEST_HOME" "$OMARCHY_SYNC" "$@"
}

# ============================================================================
# Real Backup Integration Tests
# ============================================================================

test_backup_creates_directory_structure() {
    create_test_env

    # Initialize in isolated environment
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify backup structure exists
    assert_dir_exists "$backup_path" "Backup directory should exist" || return 1
    assert_dir_exists "$backup_path/config" "Config directory should exist" || return 1
    assert_dir_exists "$backup_path/packages" "Packages directory should exist" || return 1
    assert_dir_exists "$backup_path/local_share/applications" "Applications directory should exist" || return 1
    assert_dir_exists "$backup_path/bin" "Bin directory should exist" || return 1
    assert_dir_exists "$backup_path/etc" "Etc directory should exist" || return 1
    assert_dir_exists "$backup_path/shell" "Shell directory should exist" || return 1

    return 0
}

test_backup_copies_config_files() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Create test config files
    echo "test config content" > "$TEST_HOME/.config/small-app/custom.conf"

    # Run backup
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify files were actually copied to backup
    if assert_file_exists "$backup_path/config/small-app/config.txt" "Config file should be backed up"; then
        if assert_file_contains "$backup_path/config/small-app/config.txt" "small config" "Config content should match"; then
            if assert_file_exists "$backup_path/config/small-app/custom.conf" "Custom config should be backed up"; then
                return 0
            fi
        fi
    fi
    return 1
}

test_backup_creates_metadata() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify metadata file exists and has content
    if ! assert_file_exists "$backup_path/.backup-meta" "Metadata file should exist"; then
        return 1
    fi

    # Check metadata contains expected fields
    if assert_file_contains "$backup_path/.backup-meta" "timestamp" "Metadata should have timestamp"; then
        if assert_file_contains "$backup_path/.backup-meta" "hostname" "Metadata should have hostname"; then
            return 0
        fi
    fi
    return 1
}

test_backup_copies_packages_list() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify package lists were created (pacman lists will be empty in test env, but files should exist)
    if assert_file_exists "$backup_path/packages/pkglist-repo.txt" "Repo package list should exist"; then
        if assert_file_exists "$backup_path/packages/pkglist-aur.txt" "AUR package list should exist"; then
            return 0
        fi
    fi
    return 1
}

test_backup_excludes_large_files() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # large-app was created with 25MB file in setup
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    # Verify large file NOT in backup
    if assert_file_not_exists "$backup_path/config/large-app/bigfile" "Large file should NOT be backed up"; then
        # Verify it's in exclude list
        if assert_file_exists "$backup_path/.restore-excludes" "Exclude list should exist"; then
            if assert_file_contains "$backup_path/.restore-excludes" "large-app" "large-app should be in excludes"; then
                return 0
            fi
        fi
    fi
    return 1
}

test_backup_records_symlinks() {
    create_test_env

    # Create symlinks
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    ln -s /usr/share/doc "$TEST_HOME/.config/doc-link"

    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify symlinks manifest exists and has entries
    if assert_file_exists "$backup_path/.symlinks" "Symlinks manifest should exist"; then
        if assert_file_contains "$backup_path/.symlinks" ".local/bin/my-bash" "Symlink should be recorded"; then
            if assert_file_contains "$backup_path/.symlinks" ".config/doc-link" "Config symlink should be recorded"; then
                return 0
            fi
        fi
    fi
    return 1
}

test_backup_creates_git_repo() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify .git directory exists
    if assert_dir_exists "$backup_path/.git" "Git repository should be created"; then
        # Verify there are commits
        local commit_count
        commit_count=$(cd "$backup_path" && git rev-list --count HEAD 2>/dev/null || echo 0)
        if [[ "$commit_count" -gt 0 ]]; then
            return 0
        else
            log_fail "Git repository should have at least one commit"
            return 1
        fi
    fi
    return 1
}

test_restore_after_backup() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Remove original config to test restore
    rm -f "$TEST_HOME/.config/small-app/config.txt"
    [[ -f "$TEST_HOME/.config/small-app/config.txt" ]] && {
        log_fail "Failed to remove config for restore test"
        return 1
    }

    # Now restore
    printf '1\nn\n' | run_isolated --restore 2>&1 || true

    # Verify file was restored
    if assert_file_exists "$TEST_HOME/.config/small-app/config.txt" "Config file should be restored"; then
        if assert_file_contains "$TEST_HOME/.config/small-app/config.txt" "small config" "Restored content should match"; then
            return 0
        fi
    fi
    return 1
}

test_restore_recreates_symlinks() {
    create_test_env

    # Create and backup symlinks
    ln -s /usr/bin/bash "$TEST_HOME/.local/bin/my-bash"
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    # Convert symlink to regular file (simulate exFAT behavior)
    rm "$TEST_HOME/.local/bin/my-bash"
    echo "regular file content" > "$TEST_HOME/.local/bin/my-bash"

    # Verify it's no longer a symlink
    if [[ -L "$TEST_HOME/.local/bin/my-bash" ]]; then
        log_fail "Test setup: symlink should be converted to regular file"
        return 1
    fi

    # Restore - symlink should be recreated
    printf '1\nn\n' | run_isolated --restore 2>&1 || true

    # Verify symlink is restored
    if [[ -L "$TEST_HOME/.local/bin/my-bash" ]]; then
        return 0
    else
        log_fail "Symlink should be restored from manifest"
        return 1
    fi
}

test_backup_respects_excludes_on_restore() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Backup with large app excluded
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify large-app is in exclude list
    if ! grep -q "large-app" "$backup_path/.restore-excludes" 2>/dev/null; then
        log_fail "large-app should be in restore excludes"
        return 1
    fi

    # Remove large-app from home to test restore
    rm -rf "$TEST_HOME/.config/large-app"

    # Restore - large-app should NOT be restored because it's in excludes
    printf '1\nn\n' | run_isolated --restore 2>&1 || true

    # Verify large-app was NOT restored
    if [[ ! -d "$TEST_HOME/.config/large-app" ]]; then
        return 0
    else
        log_fail "Excluded directory should not be restored"
        return 1
    fi
}

test_backup_copies_local_bin() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # test-script was created in setup
    if assert_file_exists "$backup_path/bin/test-script" "Local script should be backed up"; then
        if assert_file_contains "$backup_path/bin/test-script" "Hello from test script" "Script content should match"; then
            return 0
        fi
    fi
    return 1
}

test_backup_copies_applications() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # test.desktop was created in setup
    if assert_file_exists "$backup_path/local_share/applications/test.desktop" "Desktop entry should be backed up"; then
        if assert_file_contains "$backup_path/local_share/applications/test.desktop" "Test App" "Desktop entry content should match"; then
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

for test in test_backup_creates_directory_structure \
            test_backup_copies_config_files \
            test_backup_creates_metadata \
            test_backup_copies_packages_list \
            test_backup_excludes_large_files \
            test_backup_records_symlinks \
            test_backup_creates_git_repo \
            test_restore_after_backup \
            test_restore_recreates_symlinks \
            test_backup_respects_excludes_on_restore \
            test_backup_copies_local_bin \
            test_backup_copies_applications; do

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
echo "Backup Integration Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
