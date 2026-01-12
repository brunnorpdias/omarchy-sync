#!/bin/bash
# run-tests.sh - Test runner for omarchy-sync

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

PASSED=0
FAILED=0
SKIPPED=0

run_test() {
    local name="$1"
    local func="$2"

    log_test "Running: $name"
    create_test_env

    # Run test function directly
    # Note: Tests output verbose info, but we need to see failures
    if $func; then
        log_pass "$name"
        PASSED=$((PASSED + 1))
    else
        log_fail "$name"
        FAILED=$((FAILED + 1))
    fi

    echo ""
}

skip_test() {
    local name="$1"
    local reason="$2"

    echo -e "${YELLOW}[SKIP]${NC} $name - $reason"
    SKIPPED=$((SKIPPED + 1))
    echo ""
}

# --- Test Cases ---

test_init_fresh() {
    # Test 1.1: --init fresh, no remote
    # Note: git commit may fail due to GPG signing, but backup structure should be created
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)
    local config_path
    config_path=$(get_config_path)

    assert_file_exists "$config_path" "Config file should be created" || return 1
    assert_dir_exists "$backup_path" "Backup directory should be created" || return 1
    assert_dir_exists "$backup_path/.git" "Git repo should be initialized" || return 1
    assert_dir_exists "$backup_path/config" "Config backup should exist" || return 1
    assert_dir_exists "$backup_path/packages" "Packages backup should exist" || return 1
    assert_file_exists "$backup_path/.backup-meta" "Metadata should be created" || return 1

    return 0
}

test_backup_local() {
    # Test 3.1: --backup local only
    # First init
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    # Add new file and backup
    echo "new content" > "$TEST_HOME/.config/small-app/new-file.txt"
    printf 'n\nn\n' | run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    assert_file_exists "$backup_path/config/small-app/new-file.txt" "New file should be backed up" || return 1

    return 0
}

test_backup_large_skip() {
    # Test 3.4: Large dir skipped and recorded in .restore-excludes
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # large-app should be skipped (25MB > 20MB threshold)
    assert_file_not_exists "$backup_path/config/large-app/bigfile" "Large file should not be backed up" || return 1
    assert_file_exists "$backup_path/.restore-excludes" "Restore excludes should exist" || return 1
    assert_file_contains "$backup_path/.restore-excludes" "large-app" "large-app should be in excludes" || return 1

    return 0
}

test_backup_git_excluded() {
    # Test: .git directories should be excluded and recorded
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # .git dirs should NOT be in backup
    assert_file_not_exists "$backup_path/config/nested/with/.git/HEAD" ".git should not be backed up" || return 1
    # But nested config should be backed up
    assert_file_exists "$backup_path/config/nested/with/config.txt" "Nested config should be backed up" || return 1
    # .git path should be in excludes
    assert_file_contains "$backup_path/.restore-excludes" ".git" ".git should be in excludes" || return 1

    return 0
}

test_status() {
    # Test 5.1: --status shows all locations with timestamps
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local output
    output=$(run_omarchy --status 2>&1)

    echo "$output" | grep -q "Local backup:" || { log_fail "Status should show local backup"; return 1; }
    echo "$output" | grep -q "Last backup:" || { log_fail "Status should show last backup time"; return 1; }
    echo "$output" | grep -q "From host:" || { log_fail "Status should show hostname"; return 1; }

    return 0
}

test_config_view() {
    # Test 2.1: --config view
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local output
    output=$(echo "6" | run_omarchy --config 2>&1)

    echo "$output" | grep -q "Current settings:" || { log_fail "Config should show current settings"; return 1; }
    echo "$output" | grep -q "Backup directory:" || { log_fail "Config should show backup directory"; return 1; }
    echo "$output" | grep -q "Size limit:" || { log_fail "Config should show size limit"; return 1; }

    return 0
}

test_restore_preview() {
    # Test: --restore shows dry-run preview
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    # Select source 1 (local), confirm component selection (Enter), and abort (n)
    local output
    output=$(printf '1\n\nn\n' | run_omarchy --restore 2>&1)

    echo "$output" | grep -q "Available restore sources:" || { log_fail "Restore should list sources"; return 1; }
    echo "$output" | grep -q "Local" || { log_fail "Restore should show local source"; return 1; }
    echo "$output" | grep -q "Aborted" || { log_fail "Restore should show aborted when declined"; return 1; }

    return 0
}

test_install_creates_script() {
    # Test: --install creates single-file script
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    echo "n" | run_omarchy --install >/dev/null 2>&1 || true

    local install_path="$TEST_HOME/.local/bin/omarchy-sync"
    assert_file_exists "$install_path" "Installed script should exist" || return 1

    # Verify script is executable and works
    if ! "$install_path" --version >/dev/null 2>&1; then
        log_fail "Installed script should be runnable"
        return 1
    fi

    return 0
}

test_already_initialized() {
    # Test 1.4: --init when already configured prompts to reconfigure
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local output
    output=$(echo "n" | run_omarchy --init 2>&1)

    # Note: read -rp prompt doesn't appear when stdin is piped
    # So we can only check for "Already initialized" detection
    echo "$output" | grep -q "Already initialized" || { log_fail "Should detect existing config"; return 1; }

    return 0
}

test_internal_drive_path_appends() {
    # Test: Internal drive path has /omarchy-backup appended
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    local config_path
    config_path=$(get_config_path)

    # Add internal drive config
    cat >> "$config_path" << 'EOF'

[[internal_drives]]
path = "/mnt/data"
label = "Test Drive"
EOF

    local output
    output=$(run_omarchy --status 2>&1)

    # The path shown should have /omarchy-backup appended
    echo "$output" | grep -q "/mnt/data/omarchy-backup" || { log_fail "Internal drive path should have /omarchy-backup appended"; return 1; }

    return 0
}

# --- Run Tests ---

echo "============================================"
echo "   Omarchy-Sync Test Suite"
echo "============================================"
echo ""

run_test "Init fresh (no remote)" test_init_fresh
run_test "Backup local only" test_backup_local
run_test "Backup skips large dirs" test_backup_large_skip
run_test "Backup excludes .git dirs" test_backup_git_excluded
run_test "Status shows info" test_status
run_test "Config view" test_config_view
run_test "Restore preview and abort" test_restore_preview
run_test "Install creates single-file script" test_install_creates_script
run_test "Already initialized detection" test_already_initialized
run_test "Internal drive path appends /omarchy-backup" test_internal_drive_path_appends

# Tests that require special setup or manual verification
skip_test "Init with remote" "Requires git remote access"
skip_test "Init clone existing" "Requires existing remote repo"
skip_test "Backup to cloud" "Requires git remote access"
skip_test "Backup to external drive" "Requires physical drive"
skip_test "Restore full flow" "Requires interactive confirmation and system changes"
skip_test "Restore preserves excluded" "Requires full restore flow"
skip_test "Hostname mismatch warning" "Requires different hostname in backup"

echo "============================================"
echo "   Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"
echo "============================================"

# Cleanup
cleanup_test_env

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
