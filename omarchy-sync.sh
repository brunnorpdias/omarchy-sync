#!/bin/bash
set -euo pipefail

VERSION="1.2.0"

# Determine script location for sourcing modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths (may be overridden by --test flag)
CONFIG_DIR="$HOME/.config/omarchy-sync"
CONFIG_FILE="$CONFIG_DIR/config.toml"
DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"

# --- Pre-parse flags (must happen before sourcing modules) ---
TEST_MODE=false
TEST_DIR=""
LOG_FLAG=false
LOG_PATH=""
NO_PROMPT=false
export NO_PROMPT
REMAINING_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            TEST_MODE=true
            # Check if next arg is a directory (not another flag)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                TEST_DIR="$2"
                shift
            else
                TEST_DIR="$HOME/.local/share/omarchy-sync/test-env"
            fi
            shift
            ;;
        --log)
            LOG_FLAG=true
            # Check if next arg is a path (not another flag)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                LOG_PATH="$2"
                shift
            fi
            shift
            ;;
        --no-prompt)
            NO_PROMPT=true
            export NO_PROMPT
            shift
            ;;
        *)
            REMAINING_ARGS+=("$1")
            shift
            ;;
    esac
done

# Set back the remaining args
set -- "${REMAINING_ARGS[@]:-}"

# Apply test mode if enabled
if [[ "$TEST_MODE" == true ]]; then
    echo "=== TEST MODE: Using HOME=$TEST_DIR ==="

    # Create test environment structure if it doesn't exist
    if [[ ! -d "$TEST_DIR/.config" ]]; then
        echo "[*] Creating test environment..."
        mkdir -p "$TEST_DIR/.config/test-app"
        mkdir -p "$TEST_DIR/.local/share/applications"
        mkdir -p "$TEST_DIR/.local/bin"
        echo "test config" > "$TEST_DIR/.config/test-app/config.txt"
        echo "[Desktop Entry]" > "$TEST_DIR/.local/share/applications/test.desktop"
        echo '#!/bin/bash' > "$TEST_DIR/.local/bin/test-script"
    fi

    HOME="$TEST_DIR"
    CONFIG_DIR="$HOME/.config/omarchy-sync"
    CONFIG_FILE="$CONFIG_DIR/config.toml"
    DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"
fi

# --- Source modules ---
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/metadata.sh"
source "$SCRIPT_DIR/lib/drives.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/restore.sh"
source "$SCRIPT_DIR/lib/init.sh"

# --- Set up trap for cleanup ---
trap cleanup EXIT

# --- Initialize logging if requested ---
if [[ "$LOG_FLAG" == true ]]; then
    init_logging "${LOG_PATH:-}"
fi

# --- Install Command ---
install_command() {
    local install_dir="$HOME/.local/bin"
    local install_path="$install_dir/omarchy-sync"

    mkdir -p "$install_dir"

    log "Building single-file distribution..."

    # Concatenate all modules into one file
    {
        echo '#!/bin/bash'
        echo "# omarchy-sync v$VERSION - installed $(date -Iseconds)"
        echo '# Single-file distribution - do not edit, regenerate with --install'
        echo 'set -euo pipefail'
        echo ''
        echo "VERSION=\"$VERSION\""
        echo ''
        echo '# Default paths (may be overridden by --test flag)'
        echo 'CONFIG_DIR="$HOME/.config/omarchy-sync"'
        echo 'CONFIG_FILE="$CONFIG_DIR/config.toml"'
        echo 'DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"'
        echo ''
        echo '# --- Pre-parse flags ---'
        echo 'TEST_MODE=false'
        echo 'TEST_DIR=""'
        echo 'LOG_FLAG=false'
        echo 'LOG_PATH=""'
        echo 'NO_PROMPT=false'
        echo 'export NO_PROMPT'
        echo 'REMAINING_ARGS=()'
        echo ''
        echo 'while [[ $# -gt 0 ]]; do'
        echo '    case "$1" in'
        echo '        --test)'
        echo '            TEST_MODE=true'
        echo '            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then'
        echo '                TEST_DIR="$2"'
        echo '                shift'
        echo '            else'
        echo '                TEST_DIR="$HOME/.local/share/omarchy-sync/test-env"'
        echo '            fi'
        echo '            shift'
        echo '            ;;'
        echo '        --log)'
        echo '            LOG_FLAG=true'
        echo '            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then'
        echo '                LOG_PATH="$2"'
        echo '                shift'
        echo '            fi'
        echo '            shift'
        echo '            ;;'
        echo '        --no-prompt)'
        echo '            NO_PROMPT=true'
        echo '            export NO_PROMPT'
        echo '            shift'
        echo '            ;;'
        echo '        *)'
        echo '            REMAINING_ARGS+=("$1")'
        echo '            shift'
        echo '            ;;'
        echo '    esac'
        echo 'done'
        echo ''
        echo 'set -- "${REMAINING_ARGS[@]:-}"'
        echo ''
        echo 'if [[ "$TEST_MODE" == true ]]; then'
        echo '    echo "=== TEST MODE: Using HOME=$TEST_DIR ==="'
        echo '    if [[ ! -d "$TEST_DIR/.config" ]]; then'
        echo '        echo "[*] Creating test environment..."'
        echo '        mkdir -p "$TEST_DIR/.config/test-app"'
        echo '        mkdir -p "$TEST_DIR/.local/share/applications"'
        echo '        mkdir -p "$TEST_DIR/.local/bin"'
        echo '        echo "test config" > "$TEST_DIR/.config/test-app/config.txt"'
        echo '        echo "[Desktop Entry]" > "$TEST_DIR/.local/share/applications/test.desktop"'
        echo '        echo '"'"'#!/bin/bash'"'"' > "$TEST_DIR/.local/bin/test-script"'
        echo '    fi'
        echo '    HOME="$TEST_DIR"'
        echo '    CONFIG_DIR="$HOME/.config/omarchy-sync"'
        echo '    CONFIG_FILE="$CONFIG_DIR/config.toml"'
        echo '    DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"'
        echo 'fi'
        echo ''

        # Extract function definitions from each lib file (skip first 2 lines: shebang and comment)
        for lib in helpers config metadata drives backup restore init; do
            echo ""
            echo "# --- $lib ---"
            tail -n +3 "$SCRIPT_DIR/lib/$lib.sh"
        done

        echo ""
        echo "# --- Main ---"
        echo 'trap cleanup EXIT'
        echo ''
        echo 'if [[ "$LOG_FLAG" == true ]]; then'
        echo '    init_logging "${LOG_PATH:-}"'
        echo 'fi'
        echo ''
        echo 'check_dependencies'
        echo ''
        echo 'case "${1:-}" in'
        echo '--init) init_command ;;'
        echo '--config) config_command ;;'
        echo '--backup) backup_command ;;'
        echo '--restore) restore_command ;;'
        echo '--status) status_command ;;'
        echo '--version) echo "omarchy-sync v$VERSION" ;;'
        echo '--help | *)'
        echo '    cat <<EOF'
        echo "omarchy-sync v\$VERSION - Arch Linux system backup & restore"
        echo ''
        echo 'Usage: omarchy-sync [OPTIONS] <command>'
        echo ''
        echo 'Options:'
        echo '  --test [DIR]    Run in test mode with isolated environment'
        echo '                  Default: ~/.local/share/omarchy-sync/test-env'
        echo '  --log [FILE]    Enable logging to file'
        echo '                  Default: ~/.local/share/omarchy-sync/omarchy-sync.log'
        echo '  --no-prompt     Run without interactive prompts (for cron/scripts)'
        echo '                  Only backs up to local + configured internal drives'
        echo ''
        echo 'Commands:'
        echo '  --init      First-time setup or clone from existing remote'
        echo '  --config    View and modify settings'
        echo '  --backup    Backup to local, cloud, and/or external drives'
        echo '  --restore   Restore from local, cloud, or external drive'
        echo '  --status    Show backup status across all locations'
        echo '  --version   Show version'
        echo '  --help      Show this help'
        echo ''
        echo 'Examples:'
        echo '  omarchy-sync --init                 # First-time setup'
        echo '  omarchy-sync --backup               # Create backup'
        echo '  omarchy-sync --restore              # Restore from backup'
        echo '  omarchy-sync --test --init          # Test in isolated env'
        echo '  omarchy-sync --log --backup         # Backup with logging'
        echo '  omarchy-sync --no-prompt --backup   # Backup without prompts (cron)'
        echo 'EOF'
        echo '    ;;'
        echo 'esac'
    } > "$install_path"

    chmod +x "$install_path"
    log "Installed to $install_path"

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        echo ""
        log "WARNING: $install_dir is not in your PATH"
        local shell_rc=""
        if [[ -f "$HOME/.zshrc" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        fi

        if [[ -n "$shell_rc" ]]; then
            local add_path
            add_path=$(prompt "Add to $shell_rc? (Y/n): " "y")
            if [[ "$add_path" =~ ^[yY]$ ]]; then
                echo '' >> "$shell_rc"
                echo '# Added by omarchy-sync' >> "$shell_rc"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
                log "Added to $shell_rc. Run 'source $shell_rc' or restart your shell."
            fi
        else
            log "Add this to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi

    echo ""
    done_ "Installation complete. Run 'omarchy-sync --help' to get started."
}

# --- Main ---
check_dependencies

case "${1:-}" in
--init) init_command ;;
--config) config_command ;;
--backup) backup_command ;;
--restore) restore_command ;;
--status) status_command ;;
--install) install_command ;;
--version) echo "omarchy-sync v$VERSION" ;;
--help | *)
    cat <<EOF
omarchy-sync v$VERSION - Arch Linux system backup & restore

Usage: omarchy-sync [OPTIONS] <command>

Options:
  --test [DIR]    Run in test mode with isolated environment
                  Default: ~/.local/share/omarchy-sync/test-env
  --log [FILE]    Enable logging to file
                  Default: ~/.local/share/omarchy-sync/omarchy-sync.log
  --no-prompt     Run without interactive prompts (for cron/scripts)
                  Only backs up to local + configured internal drives

Commands:
  --init      First-time setup or clone from existing remote
  --config    View and modify settings
  --backup    Backup to local, cloud, and/or external drives
  --restore   Restore from local, cloud, or external drive
  --status    Show backup status across all locations
  --install   Install to ~/.local/bin/omarchy-sync
  --version   Show version
  --help      Show this help

Examples:
  omarchy-sync --init                 # First-time setup
  omarchy-sync --backup               # Create backup
  omarchy-sync --restore              # Restore from backup
  omarchy-sync --test --init          # Test in isolated env
  omarchy-sync --log --backup         # Backup with logging
  omarchy-sync --no-prompt --backup   # Backup without prompts (cron)
EOF
    ;;
esac
