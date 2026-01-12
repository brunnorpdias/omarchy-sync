#!/bin/bash
set -euo pipefail

VERSION="1.4.0"

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
DRY_RUN=false
export DRY_RUN
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
  --dry-run)
    DRY_RUN=true
    export DRY_RUN
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
    echo "test config" >"$TEST_DIR/.config/test-app/config.txt"
    echo "[Desktop Entry]" >"$TEST_DIR/.local/share/applications/test.desktop"
    echo '#!/bin/bash' >"$TEST_DIR/.local/bin/test-script"
  fi

  # Preserve original HOME for 1Password/SSH agent access
  export ORIGINAL_HOME="$HOME"
  HOME="$TEST_DIR"
  CONFIG_DIR="$HOME/.config/omarchy-sync"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
  DEFAULT_LOCAL_PATH="$HOME/.local/share/omarchy-sync/backup"
fi

# --- Source modules ---
# IMPORTANT: Keep this source order in sync with the module list in install_command() (line 188)
# If you add a new module, update BOTH lists
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/metadata.sh"
source "$SCRIPT_DIR/lib/drives.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/restore.sh"
source "$SCRIPT_DIR/lib/secrets.sh"
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
    echo 'DRY_RUN=false'
    echo 'export DRY_RUN'
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
    echo '        --dry-run)'
    echo '            DRY_RUN=true'
    echo '            export DRY_RUN'
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
    # IMPORTANT: This list must match the source order at the top of omarchy-sync.sh (lines 84-91)
    # If a new module is added, update BOTH lists to maintain consistency
    local modules=(helpers config metadata drives backup restore secrets init)

    # Validate all modules exist
    for module in "${modules[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/lib/$module.sh" ]]; then
            error "Missing module: $SCRIPT_DIR/lib/$module.sh"
            return 1
        fi
    done

    for lib in "${modules[@]}"; do
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
  } >"$install_path"

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
        echo '' >>"$shell_rc"
        echo '# Added by omarchy-sync' >>"$shell_rc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$shell_rc"
        log "Added to $shell_rc. Run 'source $shell_rc' or restart your shell."
      fi
    else
      log "Add this to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
  fi

  echo ""
  done_ "Installation complete. Run 'omarchy-sync --help' to get started."
}

# --- Verify Command ---
verify_command() {
  echo "--- Omarchy Sync: Verify ---"

  if ! config_exists; then
    error "Not initialized. Run 'omarchy-sync --init' first."
    exit 1
  fi

  local backup_path
  backup_path=$(get_local_path)

  if [[ ! -d "$backup_path" ]]; then
    error "No backup found at $backup_path"
    exit 1
  fi

  log "Verifying backup integrity..."

  local meta
  meta=$(read_metadata "$backup_path")

  # Verify each component
  local failed=0
  for component in config shell packages; do
    local expected
    expected=$(echo "$meta" | grep -oP "\"$component\":\s*\"sha256:\K[^\"]+")

    if [[ -z "$expected" ]] || [[ "$expected" == "none" ]]; then
      log "  $component: SKIPPED (no checksum)"
      continue
    fi

    local actual
    actual=$(compute_checksum "$backup_path/$component")

    if [[ "$expected" == "$actual" ]]; then
      log "  $component: OK"
    else
      error "  $component: MISMATCH"
      ((failed++))
    fi
  done

  echo ""
  if [[ $failed -eq 0 ]]; then
    done_ "All checksums verified."
  else
    error "$failed component(s) failed verification."
    exit 1
  fi
}

# --- Main ---
check_dependencies

case "${1:-}" in
--init) init_command ;;
--config) config_command ;;
--backup)
  if [[ "$TEST_MODE" == true ]]; then
    error "Test mode not supported for backup operations."
    error "Use --restore --test to safely test restore to a temporary location."
    exit 1
  fi
  backup_command
  ;;
--restore) restore_command ;;
--verify) verify_command ;;
--status) status_command ;;
--reset) reset_command ;;
--install) install_command ;;
--version) echo "omarchy-sync v$VERSION" ;;
--help | *)
  cat <<EOF
omarchy-sync v$VERSION - Arch Linux system backup & restore

Usage: omarchy-sync [OPTIONS] <command>

Options:
  --test [DIR]    Test restore to isolated environment (restore only)
                  Default: ~/.local/share/omarchy-sync/test-env
  --log [FILE]    Enable logging to file
                  Default: ~/.local/share/omarchy-sync/omarchy-sync.log
  --no-prompt     Run without interactive prompts (for cron/scripts)
                  Only backs up to local + configured internal drives
  --dry-run       Show what would be changed without making changes
                  Works with --backup and --restore

Commands:
  --init      First-time setup or clone from existing remote
              (will offer to install executable to ~/.local/bin)
  --config    View and modify settings
  --backup    Backup to local, cloud, and/or external drives
  --restore   Restore from local, cloud, or external drive
  --verify    Verify backup integrity using checksums
  --status    Show backup status across all locations
  --reset     DELETE ALL BACKUPS and start fresh (requires confirmation)
  --install   Install to ~/.local/bin/omarchy-sync
  --version   Show version
  --help      Show this help

Examples:
  omarchy-sync --init                 # First-time setup
  omarchy-sync --backup               # Create backup
  omarchy-sync --restore              # Restore from backup
  omarchy-sync --test --restore       # Test restore to temp location
  omarchy-sync --log --backup         # Backup with logging
  omarchy-sync --no-prompt --backup   # Backup without prompts (cron)
  omarchy-sync --dry-run --backup     # Preview what would be backed up
  omarchy-sync --dry-run --restore    # Preview what would be restored
EOF
  ;;
esac
