#!/bin/bash
# test-filesystems.sh - Test filesystem detection, validation, and display

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/setup.sh"

# ============================================================================
# Filesystem Test Cases
# ============================================================================

test_get_filesystem_type() {
    # Mock df to return ext4
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Source helpers to test function
    source "$SCRIPT_DIR/../lib/helpers.sh"

    local fstype
    fstype=$(get_filesystem_type "/home/test")

    if [[ "$fstype" == "ext4" ]]; then
        return 0
    else
        log_fail "get_filesystem_type should return ext4, got: $fstype"
        return 1
    fi
}

test_format_path_with_fs() {
    # Mock df to return exfat
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "exfat"
        else
            command df "$@"
        fi
    }
    export -f df

    source "$SCRIPT_DIR/../lib/helpers.sh"

    local formatted
    formatted=$(format_path_with_fs "/mnt/drive")

    if [[ "$formatted" == "/mnt/drive [exfat]" ]]; then
        return 0
    else
        log_fail "format_path_with_fs should return '/mnt/drive [exfat]', got: $formatted"
        return 1
    fi
}

test_validate_filesystem_ext4() {
    # Mock df to return ext4
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock error function to not exit
    error() {
        echo "[ERROR] $1" >&2
    }
    export -f error

    source "$SCRIPT_DIR/../lib/helpers.sh"

    # Should return 0 for ext4 (valid)
    if validate_filesystem "/home/test"; then
        return 0
    else
        log_fail "validate_filesystem should accept ext4"
        return 1
    fi
}

test_validate_filesystem_ntfs_rejected() {
    # Mock df to return ntfs
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ntfs"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock error function
    error() {
        echo "[ERROR] $1" >&2
    }
    export -f error

    source "$SCRIPT_DIR/../lib/helpers.sh"

    # Should return 1 for ntfs (invalid)
    if ! validate_filesystem "/mnt/ntfs" 2>/dev/null; then
        return 0
    else
        log_fail "validate_filesystem should reject ntfs"
        return 1
    fi
}

test_validate_filesystem_vfat_rejected() {
    # Mock df to return vfat
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "vfat"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock error function
    error() {
        echo "[ERROR] $1" >&2
    }
    export -f error

    source "$SCRIPT_DIR/../lib/helpers.sh"

    # Should return 1 for vfat (invalid)
    if ! validate_filesystem "/boot/efi" 2>/dev/null; then
        return 0
    else
        log_fail "validate_filesystem should reject vfat"
        return 1
    fi
}

test_warn_symlink_conversion_exfat() {
    # Mock df to return exfat
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "exfat"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock warn function
    warn() {
        echo "[WARN] $1" >&2
    }
    export -f warn

    source "$SCRIPT_DIR/../lib/helpers.sh"

    # Capture output
    local output
    output=$(warn_symlink_conversion "/mnt/drive" 2>&1)

    # Check that warning was shown
    if echo "$output" | grep -q "symlinks"; then
        return 0
    else
        log_fail "warn_symlink_conversion should show warning for exfat"
        return 1
    fi
}

test_warn_symlink_conversion_ext4_no_warning() {
    # Mock df to return ext4
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock warn function
    warn() {
        echo "[WARN] $1" >&2
    }
    export -f warn

    source "$SCRIPT_DIR/../lib/helpers.sh"

    # Should return 1 when no warning is needed
    if ! warn_symlink_conversion "/home/test" 2>/dev/null; then
        return 0
    else
        log_fail "warn_symlink_conversion should not warn for ext4"
        return 1
    fi
}

test_get_rsync_opts_ext4() {
    # Mock df to return ext4
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock log_write to avoid file operations
    log_write() {
        :
    }
    export -f log_write

    source "$SCRIPT_DIR/../lib/helpers.sh"

    local opts
    opts=$(get_rsync_opts_for_path "/home/test")

    # ext4 should NOT have --copy-links
    if [[ "$opts" == "-aq --delete" ]]; then
        return 0
    else
        log_fail "get_rsync_opts_for_path should not include --copy-links for ext4, got: $opts"
        return 1
    fi
}

test_get_rsync_opts_exfat() {
    # Mock df to return exfat
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "exfat"
        else
            command df "$@"
        fi
    }
    export -f df

    # Mock log_write
    log_write() {
        :
    }
    export -f log_write

    source "$SCRIPT_DIR/../lib/helpers.sh"

    local opts
    opts=$(get_rsync_opts_for_path "/mnt/drive")

    # exfat SHOULD have --copy-links
    if [[ "$opts" == "-aq --delete --copy-links" ]]; then
        return 0
    else
        log_fail "get_rsync_opts_for_path should include --copy-links for exfat, got: $opts"
        return 1
    fi
}

test_backup_shows_filesystem_type() {
    # Create test environment
    create_test_env

    # Initialize
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true

    # Mock df to return ext4 for local backup
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Run backup and capture output
    local output
    output=$(run_omarchy --backup 2>&1 || true)

    local backup_path
    backup_path=$(get_backup_path)

    # Check that filesystem type is shown in output
    if echo "$output" | grep -q "\[ext4\]"; then
        return 0
    else
        log_fail "Backup output should show filesystem type [ext4]"
        return 1
    fi
}

test_restore_shows_filesystem_type() {
    # Create test environment and backup first
    create_test_env
    printf 'n\n\n\n' | run_omarchy --init 2>&1 || true
    run_omarchy --backup 2>&1 || true

    # Mock df to return ext4
    df() {
        if [[ "$1" == "--output=fstype" ]]; then
            echo "ext4"
        else
            command df "$@"
        fi
    }
    export -f df

    # Run restore (in test mode it will just list sources)
    local output
    output=$(printf '1\nn\n' | run_omarchy --restore 2>&1 || true)

    # Check that filesystem type is shown in restore source list
    if echo "$output" | grep -q "\[ext4\]"; then
        return 0
    else
        log_fail "Restore output should show filesystem type [ext4]"
        return 1
    fi
}

# ============================================================================
# Run all tests
# ============================================================================

PASSED=0
FAILED=0

for test in test_get_filesystem_type \
            test_format_path_with_fs \
            test_validate_filesystem_ext4 \
            test_validate_filesystem_ntfs_rejected \
            test_validate_filesystem_vfat_rejected \
            test_warn_symlink_conversion_exfat \
            test_warn_symlink_conversion_ext4_no_warning \
            test_get_rsync_opts_ext4 \
            test_get_rsync_opts_exfat \
            test_backup_shows_filesystem_type \
            test_restore_shows_filesystem_type; do

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
echo "Filesystem Tests: $PASSED passed, $FAILED failed"
echo "========================================"

[[ $FAILED -eq 0 ]]
