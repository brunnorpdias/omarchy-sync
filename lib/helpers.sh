#!/bin/bash
# helpers.sh - Logging, prompts, and utility functions

# ============================================================================
# Global state for cleanup
# ============================================================================
_MOUNTED_DEVICES=()
_CLEANUP_DONE=false

# ============================================================================
# Logging configuration
# ============================================================================
LOG_FILE=""
LOG_ENABLED=false

init_logging() {
    local file="${1:-$HOME/.local/share/omarchy-sync/omarchy-sync.log}"
    mkdir -p "$(dirname "$file")"
    LOG_FILE="$file"
    LOG_ENABLED=true
    log_write "INFO" "=== Session started: $(date -Iseconds) ==="
}

log_write() {
    [[ "$LOG_ENABLED" != true ]] && return
    local level="$1"
    local msg="$2"
    echo "[$(date -Iseconds)] [$level] $msg" >> "$LOG_FILE"
}

# ============================================================================
# Output functions
# ============================================================================
log() {
    echo "[*] $1"
    log_write "INFO" "$1"
}

error() {
    echo "[ERROR] $1" >&2
    log_write "ERROR" "$1"
}

done_() {
    echo "[DONE] $1"
    log_write "INFO" "DONE: $1"
}

warn() {
    echo "[WARN] $1" >&2
    log_write "WARN" "$1"
}

notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical

    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "omarchy-sync" "$title" "$message" 2>/dev/null || true
    fi
    log_write "INFO" "NOTIFY: $title - $message"
}

# ============================================================================
# Mount tracking for cleanup
# ============================================================================
register_mount() {
    local device="$1"
    _MOUNTED_DEVICES+=("$device")
    log_write "INFO" "Registered mount: $device"
}

unregister_mount() {
    local device="$1"
    local new_array=()
    for d in "${_MOUNTED_DEVICES[@]}"; do
        [[ "$d" != "$device" ]] && new_array+=("$d")
    done
    _MOUNTED_DEVICES=("${new_array[@]}")
    log_write "INFO" "Unregistered mount: $device"
}

# ============================================================================
# Cleanup handler
# ============================================================================
cleanup() {
    [[ "$_CLEANUP_DONE" == true ]] && return
    _CLEANUP_DONE=true

    local exit_code=$?

    # Unmount any drives we mounted
    for device in "${_MOUNTED_DEVICES[@]}"; do
        if [[ -n "$device" ]]; then
            log_write "WARN" "Cleanup: unmounting $device"
            udisksctl unmount -b "$device" --no-user-interaction 2>/dev/null || true
        fi
    done

    # Log if we're exiting due to error
    if [[ $exit_code -ne 0 ]]; then
        log_write "ERROR" "Script exited with code $exit_code. Cleanup performed."
    fi
}

# ============================================================================
# Error handling helper
# ============================================================================
run_or_fail() {
    local context="$1"
    shift
    if ! "$@"; then
        error "$context failed"
        return 1
    fi
}

prompt() {
    local message="$1"
    local default="${2:-}"
    local result
    read -rp "$message" result
    echo "${result:-$default}"
}

check_dependencies() {
    local missing=()
    for cmd in rsync pacman git find lsblk udisksctl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# ============================================================================
# Git wrapper for 1Password compatibility in test mode
# ============================================================================
# When in test mode, HOME is changed which breaks 1Password's socket lookup.
# This wrapper temporarily restores HOME for git commands that need signing.
git_with_signing() {
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        HOME="$ORIGINAL_HOME" git "$@"
    else
        git "$@"
    fi
}

# ============================================================================
# Filesystem helpers
# ============================================================================
# Returns rsync options for a given path based on filesystem capabilities
get_rsync_opts_for_path() {
    local path="$1"
    local opts="-aq --delete"

    # Get filesystem type for the path
    local fstype
    fstype=$(df --output=fstype "$path" 2>/dev/null | tail -1)

    # Filesystems that don't support symlinks
    case "$fstype" in
        exfat|vfat|fat32|ntfs|msdos)
            opts="$opts --copy-links"
            log_write "INFO" "Using --copy-links for $fstype filesystem at $path"
            ;;
    esac

    echo "$opts"
}
