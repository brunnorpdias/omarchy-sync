#!/bin/bash
# test-git-workflow.sh - Test git commit and push workflow during backup

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
# Git Workflow Tests
# ============================================================================

test_git_commit_on_backup() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Verify initial commit exists
    local initial_commits
    initial_commits=$(cd "$backup_path" && git rev-list --count HEAD 2>/dev/null || echo 0)

    [[ "$initial_commits" -gt 0 ]] || {
        log_fail "Initial backup should create git commit"
        return 1
    }

    # Make a change and backup again
    echo "new content" > "$TEST_HOME/.config/small-app/new-file.txt"
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    # Verify new commit was created
    local new_commits
    new_commits=$(cd "$backup_path" && git rev-list --count HEAD 2>/dev/null || echo 0)

    if [[ "$new_commits" -gt "$initial_commits" ]]; then
        return 0
    else
        log_fail "Backup should create new git commit"
        return 1
    fi
}

test_git_commit_message_format() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Get the latest commit message
    local latest_msg
    latest_msg=$(cd "$backup_path" && git log -1 --format=%B 2>/dev/null || echo "")

    # Should contain "Initial backup" or "Sync:" timestamp
    if echo "$latest_msg" | grep -q "Initial backup\|Sync:"; then
        return 0
    else
        log_fail "Commit message should have proper format, got: $latest_msg"
        return 1
    fi
}

test_backup_shows_git_status() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    # Make a change and backup, capture output
    echo "new content" > "$TEST_HOME/.config/small-app/new-file.txt"
    local output
    output=$(printf 'n\nn\n' | run_isolated --backup 2>&1 || true)

    # Should show either "Committed changes" or "No changes to commit"
    if echo "$output" | grep -q "commit\|Committed"; then
        return 0
    else
        log_fail "Backup output should show git commit status"
        return 1
    fi
}

test_no_duplicate_commits() {
    create_test_env
    printf 'n\n\n\n' | run_isolated --init 2>&1 || true

    local backup_path
    backup_path=$(get_backup_path)

    # Backup without changes
    local before
    before=$(cd "$backup_path" && git rev-list --count HEAD 2>/dev/null || echo 0)

    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    # Backup again without changes
    printf 'n\nn\n' | run_isolated --backup 2>&1 || true

    local after
    after=$(cd "$backup_path" && git rev-list --count HEAD 2>/dev/null || echo 0)

    # Commit count should not increase if there are no changes
    if [[ "$after" -eq "$before" ]]; then
        return 0
    else
        log_fail "Should not create commits when there are no changes"
        return 1
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_git_commit_on_backup \
            test_git_commit_message_format \
            test_backup_shows_git_status \
            test_no_duplicate_commits; do

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
echo "Git Workflow Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
