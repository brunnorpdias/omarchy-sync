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
# Package management functions
# ============================================================================
# Check if a command/package is installed
check_package() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
    return $?
}

# Check for required packages and wait for user to install
# Does NOT install packages automatically - respects Omarchy philosophy
require_packages() {
    local packages=("$@")  # Array of "package:command" pairs

    local missing_packages=()
    local missing_commands=()

    # Detect what's missing
    for package_info in "${packages[@]}"; do
        local package="${package_info%:*}"
        local cmd="${package_info#*:}"

        if ! command -v "$cmd" &>/dev/null; then
            missing_packages+=("$package")
            missing_commands+=("$cmd")
        fi
    done

    # If nothing missing, we're good
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        return 0
    fi

    # In no-prompt mode, just fail if missing
    if [[ "$NO_PROMPT" == true ]]; then
        echo ""
        error "Required packages missing in non-interactive mode:"
        for pkg in "${missing_packages[@]}"; do
            error "  • $pkg"
        done
        error "Install packages first, then run with --no-prompt"
        exit 1
    fi

    # Show what's missing (no install commands)
    echo ""
    echo "⚠️  Required packages are missing:"
    echo ""
    for i in "${!missing_packages[@]}"; do
        local pkg="${missing_packages[$i]}"
        local cmd="${missing_commands[$i]}"
        echo "  • $pkg (provides: $cmd)"
    done
    echo ""

    # Wait for user to install
    echo "Please install the missing packages and press Enter to continue..."
    echo "(Use Omarchy menu: Super + Alt + Space → Install → Package)"
    echo ""
    read -rp "Press Enter after installing packages: "

    # Re-check if packages are now installed
    echo ""
    echo "Verifying packages..."
    local still_missing=()

    for package_info in "${packages[@]}"; do
        local package="${package_info%:*}"
        local cmd="${package_info#*:}"

        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$package")
        else
            log "$package is now available"
        fi
    done

    # If still missing, exit
    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo ""
        error "The following packages are still not installed:"
        for pkg in "${still_missing[@]}"; do
            error "  • $pkg"
        done
        error ""
        error "Cannot continue without required packages."
        error "Install them and run omarchy-sync --init again."
        exit 1
    fi

    echo ""
    log "All required packages are installed"
    return 0
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
# Get filesystem type for a given path
get_filesystem_type() {
    local path="$1"
    df --output=fstype "$path" 2>/dev/null | tail -1
}

# Format a path with its filesystem type in brackets
format_path_with_fs() {
    local path="$1"
    local fstype
    fstype=$(get_filesystem_type "$path")
    echo "$path [$fstype]"
}

# Validate that a filesystem is supported
# Returns 0 if valid, 1 if rejected with error message
validate_filesystem() {
    local path="$1"
    local fstype
    fstype=$(get_filesystem_type "$path")

    # Reject unsupported filesystems
    case "$fstype" in
        ntfs)
            error "NTFS is not supported (unreliable on Linux)"
            error "Please use exFAT or a native Linux filesystem instead"
            return 1
            ;;
        vfat)
            error "vfat is not supported (typically EFI/boot partitions)"
            error "Please use exFAT or a native Linux filesystem instead"
            return 1
            ;;
    esac
    return 0
}

# Warn about symlink conversion for filesystems that don't support them
# Returns 0 if warning shown, 1 if no warning needed
warn_symlink_conversion() {
    local path="$1"
    local fstype
    fstype=$(get_filesystem_type "$path")

    case "$fstype" in
        exfat|fat32|msdos)
            echo ""
            warn "Target filesystem: $fstype (does not support symlinks)"
            warn "Symlinks will be converted to regular files (reversible via .symlinks manifest)"
            warn "Backup size will be larger. Symlinks automatically recreated on restore."
            return 0
            ;;
    esac
    return 1
}

# Returns rsync options for a given path based on filesystem capabilities
get_rsync_opts_for_path() {
    local path="$1"
    local opts="-aq --delete"

    # Get filesystem type for the path
    local fstype
    fstype=$(get_filesystem_type "$path")

    # Filesystems that don't support symlinks (exFAT/FAT32/MSDOS only - NTFS/vfat rejected earlier)
    case "$fstype" in
        exfat|fat32|msdos)
            opts="$opts --copy-links"
            log_write "INFO" "Using --copy-links for $fstype filesystem at $path"
            ;;
    esac

    echo "$opts"
}
