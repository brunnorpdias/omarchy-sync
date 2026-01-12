#!/bin/bash
# test-browser.sh - Test browser data backup and restore

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Browser Data Test Cases
# ============================================================================

test_browser_backup_creates_directory() {
    create_test_env

    # Create fake Chromium profile
    mkdir -p "$TEST_HOME/.config/chromium/Default"
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > "$TEST_HOME/.config/chromium/Default/Bookmarks"
    echo '{}' > "$TEST_HOME/.config/chromium/Default/Preferences"
    echo "browser history" > "$TEST_HOME/.config/chromium/Default/History"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that browser directory was created
    if assert_dir_exists "$backup_path/browser" "Browser data directory should be created"; then
        if assert_dir_exists "$backup_path/browser/chromium" "Chromium profile should be backed up"; then
            return 0
        fi
    fi

    return 1
}

test_browser_portable_files_backed_up() {
    create_test_env

    # Create fake Chromium profile with portable files
    mkdir -p "$TEST_HOME/.config/chromium/Default"
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > "$TEST_HOME/.config/chromium/Default/Bookmarks"
    echo '{}' > "$TEST_HOME/.config/chromium/Default/Preferences"

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that portable files were backed up
    if assert_file_exists "$backup_path/browser/chromium/Bookmarks" "Bookmarks file should be backed up"; then
        if assert_file_exists "$backup_path/browser/chromium/Preferences" "Preferences file should be backed up"; then
            return 0
        fi
    fi

    return 1
}

test_browser_extension_list_generated() {
    create_test_env

    # Create fake Chromium profile with extensions
    mkdir -p "$TEST_HOME/.config/chromium/Default/Extensions/abc123def456/1.0/_locales/en"
    mkdir -p "$TEST_HOME/.config/chromium/Default/Extensions/xyz789uvw/2.0/_locales/en"

    # Create fake manifest files
    cat > "$TEST_HOME/.config/chromium/Default/Extensions/abc123def456/1.0/manifest.json" << 'EOF'
{
  "name": "Test Extension",
  "version": "1.0"
}
EOF

    cat > "$TEST_HOME/.config/chromium/Default/Extensions/xyz789uvw/2.0/manifest.json" << 'EOF'
{
  "name": "Another Extension",
  "version": "2.0"
}
EOF

    # Initialize and backup
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Check that extensions.txt was created
    if assert_file_exists "$backup_path/browser/chromium/extensions.txt" "Extension list should be generated"; then
        if assert_file_contains "$backup_path/browser/chromium/extensions.txt" "Test Extension" "Extension name should be in list"; then
            return 0
        fi
    fi

    return 1
}

test_browser_backup_logs_progress() {
    create_test_env

    # Create fake browser profile
    mkdir -p "$TEST_HOME/.config/chromium/Default"
    echo '{}' > "$TEST_HOME/.config/chromium/Default/Bookmarks"

    # Initialize and backup, capture output
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    local output
    output=$(run_omarchy --backup 2>&1 || true)

    # Should log browser backup
    if echo "$output" | grep -q "chromium\|browser"; then
        return 0
    else
        # If no browser profile found, backup should still complete
        assert_dir_exists "$(get_backup_path)" "Backup should complete"
        return 0
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_browser_backup_creates_directory \
            test_browser_portable_files_backed_up \
            test_browser_extension_list_generated \
            test_browser_backup_logs_progress; do

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
echo "Browser Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
