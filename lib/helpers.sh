#!/bin/bash
# helpers.sh - Logging, prompts, and utility functions

log() { echo "[*] $1"; }
error() { echo "[ERROR] $1" >&2; }
done_() { echo "[DONE] $1"; }

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
