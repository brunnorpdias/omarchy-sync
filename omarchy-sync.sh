#!/bin/bash
set -euo pipefail

VERSION="0.9.0"
INSTALL_PATH="$HOME/.local/bin/omarchy-sync"
DEFAULT_TARGET="$HOME/.omarchy-backup"
SIZE_LIMIT_MB=20

# --- Helpers ---

log() { echo "[*] $1"; }
error() { echo "[ERROR] $1" >&2; }
done_() { echo "[DONE] $1"; }

get_target() {
  local flag_target="${1:-}"
  if [[ -n "$flag_target" ]]; then
    echo "$flag_target"
  else
    echo "$DEFAULT_TARGET"
  fi
}

install_command() {
  mkdir -p "$(dirname "$INSTALL_PATH")"
  cp "$0" "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
  echo "Installed to $INSTALL_PATH"
  echo "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
}

check_dependencies() {
  local missing=()
  for cmd in rsync pacman git; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required commands: ${missing[*]}"
    exit 1
  fi
}

# --- Core Functions ---

capture_system() {
  local target
  target=$(get_target "$1")

  echo "--- Omarchy Sync: Backup Mode ---"
  log "Target: $target"

  mkdir -p "$target"/{packages,config,etc,local_share/applications,bin}

  # Create .gitignore if it doesn't exist (safety net for sensitive files)
  if [[ ! -f "$target/.gitignore" ]]; then
    log "Creating .gitignore..."
    cat <<'EOF' >"$target/.gitignore"
# Prevent accidentally committing sensitive files
*.key
*.pem
id_rsa*
id_ed25519*
*.gpg
*.secret
EOF
  fi

  # A. Package Lists
  log "Saving package lists..."
  pacman -Qqen >"$target/packages/pkglist-repo.txt"
  pacman -Qqem >"$target/packages/pkglist-aur.txt"

  # B. Configs (with size threshold)
  log "Syncing ~/.config (threshold: ${SIZE_LIMIT_MB}MB)..."
  local skipped=()
  for item in "$HOME"/.config/*; do
    [[ -e "$item" ]] || continue
    local size
    size=$(du -sm "$item" 2>/dev/null | cut -f1)
    if [[ "$size" -lt "$SIZE_LIMIT_MB" ]]; then
      rsync -aq --delete --exclude='.git' --delete-excluded "$item" "$target/config/"
    else
      skipped+=("$(basename "$item") (${size}MB)")
    fi
  done

  if [[ ${#skipped[@]} -gt 0 ]]; then
    log "Skipped large dirs: ${skipped[*]}"
  fi

  # C. Local data
  log "Syncing local data..."
  rsync -aq --delete --exclude='.git' --delete-excluded "$HOME/.local/share/applications/" "$target/local_share/applications/"
  [[ -d "$HOME/.local/bin" ]] && rsync -aq --delete "$HOME/.local/bin/" "$target/bin/"

  # D. SSH keys (DISABLED - enable only with encryption)
  # TODO: Implement GPG encryption before enabling
  # [[ -d "$HOME/.ssh" ]] && rsync -aq --delete "$HOME/.ssh/" "$target/ssh/"

  # E. System configs
  log "Backing up system configs..."
  for file in /etc/pacman.conf /etc/hosts; do
    if [[ -r "$file" ]]; then
      cp "$file" "$target/etc/"
    elif [[ -f "$file" ]]; then
      sudo cp "$file" "$target/etc/"
      sudo chown "$USER:$USER" "$target/etc/$(basename "$file")"
    fi
  done

  # F. Dconf (GTK/GNOME settings) - optional
  if command -v dconf &>/dev/null; then
    log "Dumping dconf settings..."
    dconf dump / >"$target/dconf_settings.ini" || true
  fi

  done_ "Backup complete at $target"
}

push_to_git() {
  local target
  target=$(get_target "$1")

  if [[ ! -d "$target/.git" ]]; then
    error "$target is not a git repository. Initialize with: git -C \"$target\" init"
    exit 1
  fi

  log "Pushing to remote..."
  cd "$target" || exit 1

  git add -A
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git commit -m "Sync: $(date +'%Y-%m-%d %H:%M')"
    git push origin HEAD
  else
    log "No changes to push."
  fi
}

restore_system() {
  local target
  target=$(get_target "$1")

  echo "--- Omarchy Sync: Restore Mode ---"
  log "Source: $target"

  if [[ ! -d "$target/config" ]]; then
    error "Backup not found at $target"
    exit 1
  fi

  # Dry run preview
  log "Calculating changes (dry run)..."
  echo ""
  echo "=== Files to be DELETED from ~/.config ==="
  rsync -nrv --delete "$target/config/" "$HOME/.config/" 2>/dev/null | grep "^deleting " || echo "(none)"
  echo ""
  echo "=== Files to be ADDED/UPDATED ==="
  rsync -nrv "$target/config/" "$HOME/.config/" 2>/dev/null | grep -E "^[^.]" | head -20 || echo "(none)"
  echo ""

  read -rp "Proceed with restore? (y/N): " confirm
  [[ $confirm != [yY] ]] && {
    echo "Aborted."
    exit 0
  }

  # Restore configs
  log "Restoring ~/.config..."
  rsync -aq --delete "$target/config/" "$HOME/.config/"

  log "Restoring local data..."
  rsync -aq --delete "$target/local_share/applications/" "$HOME/.local/share/applications/"
  [[ -d "$target/bin" ]] && rsync -aq --delete "$target/bin/" "$HOME/.local/bin/"

  # Restore system configs (requires sudo)
  if [[ -f "$target/etc/pacman.conf" ]]; then
    log "Restoring /etc/pacman.conf..."
    sudo cp "$target/etc/pacman.conf" /etc/pacman.conf
  fi
  if [[ -f "$target/etc/hosts" ]]; then
    log "Restoring /etc/hosts..."
    sudo cp "$target/etc/hosts" /etc/hosts
  fi

  # Restore dconf
  if [[ -f "$target/dconf_settings.ini" ]] && command -v dconf &>/dev/null; then
    log "Loading dconf settings..."
    dconf load / <"$target/dconf_settings.ini" || true
  fi

  done_ "Restore complete."
  echo ""
  echo "Next steps:"
  echo "  1. Reinstall official packages:"
  echo "     sudo pacman -S --needed - < $target/packages/pkglist-repo.txt"
  echo "  2. Reinstall AUR packages (with yay/paru):"
  echo "     yay -S --needed - < $target/packages/pkglist-aur.txt"
  echo "  3. Reboot or re-login to apply all changes."
}

show_status() {
  local target
  target=$(get_target "$1")

  echo "--- Omarchy Sync: Status ---"
  echo "Target: $target"

  if [[ -d "$target" ]]; then
    echo "Last backup: $(stat -c %y "$target/packages/pkglist-repo.txt" 2>/dev/null | cut -d. -f1 || echo "unknown")"
    echo "Repo packages: $(wc -l <"$target/packages/pkglist-repo.txt" 2>/dev/null || echo 0)"
    echo "AUR packages:  $(wc -l <"$target/packages/pkglist-aur.txt" 2>/dev/null || echo 0)"
    echo "Config dirs:   $(ls "$target/config" 2>/dev/null | wc -l)"
    if [[ -d "$target/.git" ]]; then
      echo "Git status:    $(git -C "$target" status --porcelain | wc -l) uncommitted changes"
    fi
  else
    echo "No backup found."
  fi
}

# --- Main ---

check_dependencies

case "${1:-}" in
--install) install_command ;;
--backup) capture_system "${2:-}" ;;
--restore) restore_system "${2:-}" ;;
--push) push_to_git "${2:-}" ;;
--status) show_status "${2:-}" ;;
--version) echo "omarchy-sync v$VERSION" ;;
--help | *)
  cat <<EOF
omarchy-sync v$VERSION - Arch Linux system backup & restore

Usage: omarchy-sync <command> [target_path]

Commands:
  --backup   Capture system state to target directory
  --restore  Restore system state from target directory  
  --push     Commit and push target directory to git remote
  --status   Show backup status and statistics
  --install  Install this script to ~/.local/bin
  --version  Show version
  --help     Show this help

Default target: $DEFAULT_TARGET

Examples:
  omarchy-sync --backup                    # Backup to default location
  omarchy-sync --backup /mnt/usb/backup    # Backup to custom location
  omarchy-sync --restore                   # Restore from default location
  omarchy-sync --push                      # Push backup to git remote
EOF
  ;;
esac
