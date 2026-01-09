#!/bin/bash
# init.sh - Initialization, configuration view/modify, and status commands

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
        read -rp "Local backup directory ($DEFAULT_LOCAL_PATH): " local_path
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

        local backup_host
        backup_host=$(get_metadata_field "$local_path" "hostname")
        local backup_ts
        backup_ts=$(get_metadata_field "$local_path" "timestamp")

        echo ""
        done_ "Setup complete."
        log "Found backup from host '$backup_host' ($backup_ts)"
        log "Run 'omarchy-sync --restore' to restore configs."

    else
        # Fresh setup
        local local_path
        read -rp "Local backup directory ($DEFAULT_LOCAL_PATH): " local_path
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

        # Create backup directory and init git
        mkdir -p "$local_path"
        cd "$local_path" || exit 1
        git init

        if [[ -n "$remote_url" ]]; then
            git remote add origin "$remote_url"
        fi

        # Run first backup
        log "Running first backup..."
        do_backup_to_target "$local_path"

        cd "$local_path" || exit 1
        git add -A
        git commit -m "Initial backup: $(date +'%Y-%m-%d %H:%M')"

        if [[ -n "$remote_url" ]]; then
            log "Pushing to remote..."
            git push -u origin HEAD
        fi

        echo ""
        done_ "Setup complete."
        log "Config saved to: $CONFIG_FILE"
        log "Backup location: $local_path"
        log "Run 'omarchy-sync --backup' to create new backups."
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

    echo "Current settings:"
    echo "  1. Backup directory: $local_path"
    echo "  2. Remote: ${remote_url:-<not set>}"
    echo "  3. Size limit: ${size_limit}MB"
    echo "  4. Internal drives: $(get_internal_drives | wc -l) configured"
    echo "  5. View config file"
    echo "  6. Exit"
    echo ""

    local choice
    read -rp "What would you like to change? (1-6): " choice

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
        cat "$CONFIG_FILE"
        ;;
    6)
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
