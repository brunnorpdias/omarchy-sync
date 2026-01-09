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
