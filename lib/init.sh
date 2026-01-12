#!/bin/bash
# init.sh - Initialization, configuration view/modify, and status commands

setup_encryption_key() {
    echo ""
    log "Encryption key setup for secrets backup..."
    echo ""

    local generate_key
    generate_key=$(prompt "Generate new age encryption key? (Y/n): " "y")

    if [[ "$generate_key" =~ ^[yY]$ ]]; then
        # Generate new age key
        log "Generating new age encryption key..."

        if ! command -v age-keygen &>/dev/null; then
            error "age-keygen not installed. Install with: sudo pacman -S age"
            exit 1
        fi

        # Generate key, capture output
        local keygen_output
        keygen_output=$(age-keygen 2>&1)

        # Extract public key (format: "# public key: age1...")
        local public_key
        public_key=$(echo "$keygen_output" | grep "^# public key:" | cut -d' ' -f4)

        # Extract private key (format: "AGE-SECRET-KEY-1...")
        local private_key
        private_key=$(echo "$keygen_output" | grep "^AGE-SECRET-KEY-")

        if [[ -z "$public_key" ]] || [[ -z "$private_key" ]]; then
            error "Failed to generate age key"
            exit 1
        fi

        # Save public key to config
        set_encryption_public_key "$public_key"
        log "Public key saved to config."

        # Show private key ONCE - user must save it
        echo ""
        echo "=========================================="
        echo "⚠️  SAVE YOUR ENCRYPTION PRIVATE KEY  ⚠️"
        echo "=========================================="
        echo ""
        echo "This key will be shown ONLY ONCE."
        echo "Save it in your password manager (1Password, Bitwarden, etc.)"
        echo "You will need it to restore your backup."
        echo ""
        echo "Private key:"
        echo ""
        echo "$private_key"
        echo ""
        echo "=========================================="
        echo ""
        read -rp "Press Enter after saving the key to continue..."

    else
        # Manual key import
        local existing_pubkey
        read -rp "Enter your age public key (age1...): " existing_pubkey

        if [[ ! "$existing_pubkey" =~ ^age1[a-z0-9]{58}$ ]]; then
            error "Invalid age public key format. Must start with 'age1' and be 62 characters."
            exit 1
        fi

        set_encryption_public_key "$existing_pubkey"
        log "Public key saved to config."
    fi

    echo ""
}

init_command() {
    echo "--- Omarchy Sync: Setup ---"
    echo ""

    # Check if already initialized
    if config_exists; then
        local existing_path
        existing_path=$(get_local_path)
        log "Already initialized. Config: $CONFIG_FILE"
        log "Backup location: $existing_path"
        echo ""
        local reinit
        reinit=$(prompt "Reconfigure? (y/N): " "n")
        [[ ! "$reinit" =~ ^[yY]$ ]] && exit 0
    fi

    # Ask if existing remote
    echo ""
    local has_remote
    has_remote=$(prompt "Do you have an existing backup remote? (y/N): " "n")

    if [[ "$has_remote" =~ ^[yY]$ ]]; then
        # Clone from existing
        local remote_url
        read -rp "Remote URL: " remote_url

        if [[ -z "$remote_url" ]]; then
            error "Remote URL required."
            exit 1
        fi

        log "Testing git authentication..."
        if ! git ls-remote "$remote_url" &>/dev/null; then
            error "Cannot access remote. Check URL and authentication."
            exit 1
        fi
        log "Authentication successful."

        local local_path
        read -rp "Local backup directory [Enter for $DEFAULT_LOCAL_PATH]: " local_path
        local_path="${local_path:-$DEFAULT_LOCAL_PATH}"

        # Expand ~
        local_path="${local_path/#\~/$HOME}"

        log "Cloning to $local_path..."
        mkdir -p "$(dirname "$local_path")"
        git clone "$remote_url" "$local_path"

        # Create config
        create_default_config
        set_config_value "path" "$local_path"
        set_config_value "url" "$remote_url"

        # Setup encryption key
        setup_encryption_key

        local backup_host
        backup_host=$(get_metadata_field "$local_path" "hostname")
        local backup_ts
        backup_ts=$(get_metadata_field "$local_path" "timestamp")

        # Ensure backup directory has proper permissions
        chmod 700 "$local_path" 2>/dev/null || true
        if [[ -d "$local_path/.git" ]]; then
            chmod 700 "$local_path/.git" 2>/dev/null || true
        fi

        echo ""
        done_ "Setup complete."
        log "Found backup from host '$backup_host' ($backup_ts)"
        log "Run 'omarchy-sync --restore' to restore configs."

        # Offer to install executable
        echo ""
        local install_confirm
        install_confirm=$(prompt "Install executable to ~/.local/bin? (Y/n): " "y")
        if [[ "$install_confirm" =~ ^[yY]$ ]]; then
            install_command
        fi

    else
        # Fresh setup
        local local_path
        read -rp "Local backup directory [Enter for $DEFAULT_LOCAL_PATH]: " local_path
        local_path="${local_path:-$DEFAULT_LOCAL_PATH}"
        local_path="${local_path/#\~/$HOME}"

        local remote_url
        read -rp "Git remote URL (empty for local-only): " remote_url

        # Test remote if provided
        if [[ -n "$remote_url" ]]; then
            log "Testing git authentication..."
            if ! git ls-remote "$remote_url" &>/dev/null; then
                error "Cannot access remote. Check URL and authentication."
                exit 1
            fi
            log "Authentication successful."
        fi

        # Create config
        create_default_config
        set_config_value "path" "$local_path"
        [[ -n "$remote_url" ]] && set_config_value "url" "$remote_url"

        # Setup encryption key
        setup_encryption_key

        # Create backup directory and init git
        mkdir -p "$local_path"
        cd "$local_path" || exit 1
        git init

        if [[ -n "$remote_url" ]]; then
            git remote add origin "$remote_url"
        fi

        # Run first backup
        log "Running first backup..."
        if ! do_backup_to_target "$local_path"; then
            error "Initial backup failed"
            rm -rf "$local_path"
            return 1
        fi

        cd "$local_path" || exit 1
        git add -A
        if ! git_with_signing commit -m "Initial backup: $(date +'%Y-%m-%d %H:%M')"; then
            error "Failed to commit initial backup"
            error "Check git configuration: git config --list"
            return 1
        fi
        log "Initial backup committed."

        if [[ -n "$remote_url" ]]; then
            log "Pushing to remote..."
            if ! git_with_signing push -u origin HEAD; then
                error "Failed to push to remote"
                error "Check authentication: git ls-remote \"$remote_url\""
                warn "Backup is local only until authentication is fixed"
            fi
        fi

        # Ensure backup directory has proper permissions
        chmod 700 "$local_path" 2>/dev/null || true
        if [[ -d "$local_path/.git" ]]; then
            chmod 700 "$local_path/.git" 2>/dev/null || true
        fi

        echo ""
        done_ "Setup complete."
        log "Config saved to: $CONFIG_FILE"
        log "Backup location: $local_path"
        log "Run 'omarchy-sync --backup' to create new backups."

        # Offer to install executable
        echo ""
        local install_confirm
        install_confirm=$(prompt "Install executable to ~/.local/bin? (Y/n): " "y")
        if [[ "$install_confirm" =~ ^[yY]$ ]]; then
            install_command
        fi
    fi
}

config_command() {
    echo "--- Omarchy Sync: Configuration ---"
    echo ""

    if ! config_exists; then
        error "Not initialized. Run 'omarchy-sync --init' first."
        exit 1
    fi

    local local_path
    local_path=$(get_local_path)
    local remote_url
    remote_url=$(get_remote_url)
    local size_limit
    size_limit=$(get_size_limit)

    local encryption_pubkey
    encryption_pubkey=$(get_encryption_public_key)

    echo "Current settings:"
    echo "  1. Backup directory: $local_path"
    echo "  2. Remote: ${remote_url:-<not set>}"
    echo "  3. Size limit: ${size_limit}MB"
    echo "  4. Internal drives: $(get_internal_drives | wc -l) configured"
    echo "  5. Encryption key: $(echo "${encryption_pubkey:0:20}..." | sed 's/\.\.\.$//')"
    echo "  6. View config file"
    echo "  7. Exit"
    echo ""

    local choice
    read -rp "What would you like to change? (1-7): " choice

    case "$choice" in
    1)
        local new_path
        read -rp "New backup directory ($local_path): " new_path
        new_path="${new_path:-$local_path}"
        new_path="${new_path/#\~/$HOME}"
        set_config_value "path" "$new_path"
        log "Backup directory updated to: $new_path"
        ;;
    2)
        local new_remote
        read -rp "New remote URL (empty to remove): " new_remote
        set_config_value "url" "$new_remote"
        if [[ -n "$new_remote" ]]; then
            cd "$local_path" || exit 1
            if git remote get-url origin &>/dev/null; then
                git remote set-url origin "$new_remote"
            else
                git remote add origin "$new_remote"
            fi
            log "Remote updated to: $new_remote"
        else
            log "Remote removed."
        fi
        ;;
    3)
        local new_limit
        read -rp "New size limit in MB ($size_limit): " new_limit
        new_limit="${new_limit:-$size_limit}"
        set_config_value "size_limit_mb" "$new_limit"
        log "Size limit updated to: ${new_limit}MB"
        ;;
    4)
        echo ""
        echo "To add internal drives, edit $CONFIG_FILE and add:"
        echo ""
        echo '[[internal_drives]]'
        echo 'path = "/mnt/your-drive"'
        echo 'label = "My Internal Drive"'
        echo ""
        echo "Note: /omarchy-backup will be appended automatically to the path."
        echo ""
        echo "Currently mounted drives:"
        lsblk -o NAME,SIZE,MOUNTPOINT,LABEL -p | grep -E "/$|/mnt|/media" | head -10
        ;;
    5)
        echo ""
        echo "Current encryption public key:"
        if [[ -n "$encryption_pubkey" ]]; then
            echo "  $encryption_pubkey"
        else
            echo "  <not set>"
        fi
        echo ""
        local new_key
        read -rp "New age public key (or Enter to keep current): " new_key
        if [[ -n "$new_key" ]]; then
            if [[ ! "$new_key" =~ ^age1[a-z0-9]{58}$ ]]; then
                error "Invalid age public key format. Must start with 'age1' and be 62 characters."
            else
                set_encryption_public_key "$new_key"
                log "Encryption key updated"
            fi
        fi
        ;;
    6)
        echo ""
        cat "$CONFIG_FILE"
        ;;
    7)
        exit 0
        ;;
    *)
        error "Invalid choice."
        ;;
    esac
}

status_command() {
    echo "--- Omarchy Sync: Status ---"
    echo ""

    if ! config_exists; then
        error "Not initialized. Run 'omarchy-sync --init' first."
        exit 1
    fi

    local local_path
    local_path=$(get_local_path)
    local remote_url
    remote_url=$(get_remote_url)

    echo "Configuration: $CONFIG_FILE"
    echo ""

    # Local backup status
    echo "Local backup: $local_path"
    if [[ -d "$local_path" ]]; then
        local local_ts
        local_ts=$(get_metadata_field "$local_path" "timestamp")
        local local_host
        local_host=$(get_metadata_field "$local_path" "hostname")
        echo "  Last backup: $local_ts"
        echo "  From host: $local_host"
        echo "  Repo packages: $(wc -l <"$local_path/packages/pkglist-repo.txt" 2>/dev/null || echo 0)"
        echo "  AUR packages: $(wc -l <"$local_path/packages/pkglist-aur.txt" 2>/dev/null || echo 0)"
        echo "  Config dirs: $(ls "$local_path/config" 2>/dev/null | wc -l)"
        if [[ -f "$local_path/.restore-excludes" ]]; then
            echo "  Excluded paths: $(wc -l <"$local_path/.restore-excludes")"
        fi
        if [[ -d "$local_path/.git" ]]; then
            echo "  Git status: $(git -C "$local_path" status --porcelain | wc -l) uncommitted changes"
        fi
    else
        echo "  Status: Not found"
    fi

    echo ""

    # Remote status
    echo "Remote: ${remote_url:-<not configured>}"
    if [[ -n "$remote_url" ]] && [[ -d "$local_path/.git" ]]; then
        local ahead_behind
        ahead_behind=$(git -C "$local_path" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || echo "? ?")
        local ahead="${ahead_behind%% *}"
        local behind="${ahead_behind##* }"
        echo "  Ahead: $ahead commits"
        echo "  Behind: $behind commits"
    fi

    echo ""

    # Internal drives
    echo "Internal drives:"
    local internal_drives
    internal_drives=$(get_internal_drives)
    if [[ -n "$internal_drives" ]]; then
        while IFS='|' read -r path label; do
            if [[ -d "$path" ]]; then
                local drive_ts
                drive_ts=$(get_metadata_field "$path" "timestamp")
                echo "  $label: $path (last: $drive_ts)"
            else
                echo "  $label: $path (not available)"
            fi
        done < <(echo "$internal_drives")
    else
        echo "  (none configured)"
    fi

    echo ""

    # External drives
    echo "External drives (available):"
    local drives
    drives=$(get_safe_drives)
    if [[ -n "$drives" ]]; then
        while IFS='|' read -r device size fstype mountpoint label status; do
            local display="${label:-$device}"
            if [[ "$status" == "mounted" ]] && [[ -d "$mountpoint/omarchy-backup" ]]; then
                local drive_ts
                drive_ts=$(get_metadata_field "$mountpoint/omarchy-backup" "timestamp")
                echo "  $display ($size): has backup (last: $drive_ts)"
            else
                echo "  $display ($size): no backup found"
            fi
        done < <(echo "$drives")
    else
        echo "  (none detected)"
    fi
}

reset_command() {
    echo "--- Omarchy Sync: Reset ---"
    echo ""

    if ! config_exists; then
        error "Not initialized. Run 'omarchy-sync --init' first."
        exit 1
    fi

    local local_path
    local_path=$(get_local_path)

    # Show strong warning
    echo ""
    echo "=========================================="
    echo "⚠️  WARNING: THIS WILL DELETE ALL BACKUPS ⚠️"
    echo "=========================================="
    echo ""
    echo "This will PERMANENTLY DELETE:"
    echo "  - All backup data at: $local_path"
    echo "  - Git history"
    echo "  - All symlink manifests and metadata"
    echo ""
    echo "This action CANNOT be undone."
    echo ""

    # Require explicit confirmation
    local confirm1
    confirm1=$(prompt "Type 'delete all backups' to confirm: " "")

    if [[ "$confirm1" != "delete all backups" ]]; then
        echo "Reset cancelled."
        exit 0
    fi

    echo ""
    local confirm2
    confirm2=$(prompt "Are you absolutely sure? Type 'yes' to proceed: " "")

    if [[ "$confirm2" != "yes" ]]; then
        echo "Reset cancelled."
        exit 0
    fi

    echo ""
    log "Deleting backup directory..."
    rm -rf "$local_path"

    log "Recreating backup directory..."
    mkdir -p "$local_path"
    cd "$local_path" || exit 1
    git init

    local remote_url
    remote_url=$(get_remote_url)
    if [[ -n "$remote_url" ]]; then
        git remote add origin "$remote_url"
    fi

    echo ""
    done_ "Backup reset complete. All previous backups deleted."
    log "Run 'omarchy-sync --backup' to create a new backup."
}
