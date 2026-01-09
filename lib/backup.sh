#!/bin/bash
# backup.sh - Backup functionality

do_backup_to_target() {
    local target="$1"
    local size_limit
    size_limit=$(get_size_limit)

    mkdir -p "$target"/{packages,config,etc,local_share/applications,bin}

    # Create .gitignore if it doesn't exist
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
    log "Syncing ~/.config (threshold: ${size_limit}MB)..."
    : >"$target/.restore-excludes"

    for item in "$HOME"/.config/*; do
        [[ -e "$item" ]] || continue
        local size
        size=$(du -sm "$item" 2>/dev/null | cut -f1)
        if [[ "$size" -lt "$size_limit" ]]; then
            rsync -aq --delete --exclude='.git' --delete-excluded "$item" "$target/config/"
        else
            echo "$item" >>"$target/.restore-excludes"
            log "Skipped large dir: $item (${size}MB)"
        fi
    done

    # Record .git directories found in source
    find "$HOME/.config" -name ".git" -type d 2>/dev/null >>"$target/.restore-excludes"

    # C. Local data
    log "Syncing local data..."
    rsync -aq --delete --exclude='.git' --delete-excluded "$HOME/.local/share/applications/" "$target/local_share/applications/"
    [[ -d "$HOME/.local/bin" ]] && rsync -aq --delete --exclude='.git' --delete-excluded "$HOME/.local/bin/" "$target/bin/"

    # D. System configs
    log "Backing up system configs..."
    for file in /etc/pacman.conf /etc/hosts; do
        if [[ -r "$file" ]]; then
            cp "$file" "$target/etc/"
        elif [[ -f "$file" ]]; then
            sudo cp "$file" "$target/etc/"
            sudo chown "$USER:$USER" "$target/etc/$(basename "$file")"
        fi
    done

    # E. Dconf (GTK/GNOME settings) - optional
    if command -v dconf &>/dev/null; then
        log "Dumping dconf settings..."
        dconf dump / >"$target/dconf_settings.ini" || true
    fi

    # F. Write metadata
    write_metadata "$target"
}

backup_command() {
    echo "--- Omarchy Sync: Backup ---"

    if ! config_exists; then
        error "Not initialized. Run 'omarchy-sync --init' first."
        exit 1
    fi

    local local_path
    local_path=$(get_local_path)
    local remote_url
    remote_url=$(get_remote_url)

    # 1. Always backup to local
    log "Backing up to local ($local_path)..."
    do_backup_to_target "$local_path"

    # Commit if git is configured
    if [[ -d "$local_path/.git" ]]; then
        cd "$local_path" || exit 1
        git add -A
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            git commit -m "Sync: $(date +'%Y-%m-%d %H:%M')"
            log "Committed changes."
        else
            log "No changes to commit."
        fi
    fi

    # 2. Backup to internal drives (always, if configured and available)
    local internal_drives
    internal_drives=$(get_internal_drives)
    if [[ -n "$internal_drives" ]]; then
        while IFS='|' read -r path label; do
            if [[ -d "$(dirname "$path")" ]]; then
                log "Backing up to internal drive: $label ($path)..."
                do_backup_to_target "$path"
            else
                log "Internal drive not available: $label ($path) - skipping"
            fi
        done < <(echo "$internal_drives")
    fi

    # 3. Push to remote (skip if --no-prompt)
    if [[ "${NO_PROMPT:-false}" != true ]] && [[ -n "$remote_url" ]] && [[ -d "$local_path/.git" ]]; then
        echo ""
        local push_confirm
        push_confirm=$(prompt "Push to cloud ($remote_url)? (y/N): " "n")
        if [[ "$push_confirm" =~ ^[yY]$ ]]; then
            log "Pushing to remote..."
            cd "$local_path" || exit 1
            git push origin HEAD || error "Push failed. Check your authentication."
        fi
    fi

    # 4. External drive (skip if --no-prompt)
    if [[ "${NO_PROMPT:-false}" != true ]]; then
        echo ""
        local drive_confirm
        drive_confirm=$(prompt "Backup to external drive? (y/N): " "n")
        if [[ "$drive_confirm" =~ ^[yY]$ ]]; then
            if display_available_drives; then
                local selected
                selected=$(select_drive)
                if [[ -n "$selected" ]]; then
                    IFS='|' read -r device size fstype mountpoint label status <<<"$selected"

                    local was_mounted=true
                    if [[ "$status" != "mounted" ]]; then
                        was_mounted=false
                        mountpoint=$(mount_drive "$device")
                    fi

                    if [[ -n "$mountpoint" ]]; then
                        local drive_target="$mountpoint/omarchy-backup"
                        log "Backing up to $drive_target..."
                        do_backup_to_target "$drive_target"

                        if [[ "$was_mounted" == false ]]; then
                            unmount_drive "$device"
                        fi
                    fi
                fi
            fi
        fi
    fi

    echo ""
    done_ "Backup complete."
}
