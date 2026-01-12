#!/bin/bash
# backup.sh - Backup functionality

generate_extension_list() {
    local browser_dir="$1"
    local output_file="$2"
    local ext_dir="$browser_dir/Extensions"

    [[ ! -d "$ext_dir" ]] && return

    {
        echo "# Browser Extensions (reinstall from Chrome Web Store)"
        echo "# Name | Extension ID | Version"
        echo ""

        for manifest in "$ext_dir"/*/*/manifest.json; do
            [[ ! -f "$manifest" ]] && continue

            local ext_id version name
            ext_id=$(echo "$manifest" | sed 's|.*/Extensions/\([^/]*\)/.*|\1|')
            version=$(echo "$manifest" | sed 's|.*/\([^/]*\)/manifest.json|\1|' | sed 's/_0$//')

            # Get name from manifest
            name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$manifest" 2>/dev/null | head -1)

            # If localized (__MSG_...__), try to get from _locales/en/messages.json
            if [[ "$name" == __MSG_*__ ]]; then
                local msg_key="${name#__MSG_}"
                msg_key="${msg_key%__}"
                local locale_file
                locale_file=$(dirname "$manifest")/_locales/en/messages.json
                if [[ -f "$locale_file" ]]; then
                    name=$(grep -A2 "\"$msg_key\"" "$locale_file" 2>/dev/null | grep '"message"' | \
                           sed 's/.*"message"\s*:\s*"\([^"]*\)".*/\1/' | head -1)
                fi
            fi

            [[ -n "$name" ]] && echo "$name | $ext_id | $version"
        done
    } > "$output_file"

    local count
    count=$(grep -c "|" "$output_file" 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]] && log "  Found $count extension(s)"
}

backup_browser_data() {
    local target="$1"

    local browser_dirs=(
        "$HOME/.config/chromium/Default"
        "$HOME/.config/google-chrome/Default"
    )

    for browser_dir in "${browser_dirs[@]}"; do
        [[ ! -d "$browser_dir" ]] && continue

        local browser_name
        browser_name=$(basename "$(dirname "$browser_dir")")
        local target_dir="$target/browser/$browser_name"
        mkdir -p "$target_dir"

        log "Backing up $browser_name portable data..."

        # Copy portable files
        for item in "Bookmarks" "Preferences" "History"; do
            [[ -f "$browser_dir/$item" ]] && cp "$browser_dir/$item" "$target_dir/"
        done

        # Copy extension settings (user data, NOT extension code)
        for dir in "Local Extension Settings" "Sync Extension Settings" "Managed Extension Settings"; do
            [[ -d "$browser_dir/$dir" ]] && \
                rsync -aq "$browser_dir/$dir/" "$target_dir/$dir/"
        done

        # Generate extension list for reinstallation
        generate_extension_list "$browser_dir" "$target_dir/extensions.txt"
    done
}

do_backup_to_target() {
    # Backup structure:
    #   packages/           - Package lists (pkglist-repo.txt, pkglist-aur.txt)
    #   config/             - ~/.config/* (excluding large dirs)
    #   local_share/apps/   - ~/.local/share/applications/
    #   bin/                - ~/.local/bin/
    #   etc/                - /etc/pacman.conf, /etc/hosts
    #   shell/              - Shell configs (.zshrc, .bashrc, etc.)
    #   browser/            - Browser data (bookmarks, preferences, extensions)
    #   secrets/            - Encrypted SSH keys (age)
    #   dconf_settings.ini  - GNOME/GTK settings
    #   .backup-meta        - Metadata (timestamp, hostname, checksums)
    #   .restore-excludes   - HOME-relative paths of skipped items (e.g., .config/chromium)
    #   .machine-specific   - HOME-relative paths of machine-specific configs
    #   .gitignore          - Prevent committing secrets
    #
    # Path convention: All paths in metadata files use HOME-relative format
    # (e.g., .config/hypr/monitors.conf) for portability across machines.

    local target="$1"
    local size_limit
    size_limit=$(get_size_limit)

    local mkdir_output
    mkdir_output=$(mkdir -p "$target"/{packages,config,etc,local_share/applications,bin} 2>&1)
    if [[ $? -ne 0 ]] || [[ ! -d "$target" ]]; then
        error "Failed to create backup directories at: $target"
        [[ -n "$mkdir_output" ]] && error "mkdir output: $mkdir_output"
        return 1
    fi

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
            # Store HOME-relative path (e.g., .config/chromium)
            echo "${item#$HOME/}" >>"$target/.restore-excludes"
            log "Skipped large dir: $item (${size}MB)"
        fi
    done

    # Record .git directories found in source (HOME-relative paths)
    find "$HOME/.config" -name ".git" -type d 2>/dev/null | \
        sed "s|^$HOME/||" >>"$target/.restore-excludes"

    # C. Local data
    log "Syncing local data..."
    [[ -d "$HOME/.local/share/applications" ]] && rsync -aq --delete --exclude='.git' --delete-excluded "$HOME/.local/share/applications/" "$target/local_share/applications/"
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

    # F. Shell configs
    log "Backing up shell configs..."
    mkdir -p "$target/shell"
    for rc in .zshrc .bashrc .profile .zshenv .bash_profile; do
        [[ -f "$HOME/$rc" ]] && cp "$HOME/$rc" "$target/shell/"
    done

    # G. Browser portable data (bookmarks, preferences, extension list)
    backup_browser_data "$target"

    # H. SSH keys (encrypted with age)
    backup_secrets "$target"

    # I. Tag machine-specific configs for cross-machine restore handling
    create_machine_specific_list "$target"

    # J. Write metadata
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
            git_with_signing commit -m "Sync: $(date +'%Y-%m-%d %H:%M')"
            log "Committed changes."
        else
            log "No changes to commit."
        fi
    fi

    # 2. Backup to internal drives (rsync from local backup for consistency)
    local internal_drives
    internal_drives=$(get_internal_drives)
    if [[ -n "$internal_drives" ]]; then
        while IFS='|' read -r path label; do
            local parent_dir
            parent_dir=$(dirname "$path")
            if [[ -d "$parent_dir" ]]; then
                # Test write access
                if [[ -w "$parent_dir" ]] || [[ -w "$path" ]]; then
                    log "Syncing to internal drive: $label ($path)..."
                    mkdir -p "$path"
                    local rsync_opts
                    rsync_opts=$(get_rsync_opts_for_path "$path")
                    # shellcheck disable=SC2086
                    rsync $rsync_opts "$local_path/" "$path/" || warn "Some files could not be synced (check filesystem limitations)"
                else
                    warn "No write access to $path - skipping internal drive backup"
                    warn "Fix: sudo chown -R $USER:$USER $path (or create with correct permissions)"
                fi
            else
                log "Internal drive not available: $label ($path) - skipping"
            fi
        done < <(echo "$internal_drives")
    fi

    # 3. Push to remote (skip if --no-prompt)
    if [[ "${NO_PROMPT:-false}" != true ]] && [[ -n "$remote_url" ]] && [[ -d "$local_path/.git" ]]; then
        echo ""
        local push_confirm
        push_confirm=$(prompt "Push to cloud ($remote_url)? (Y/n): " "y")
        if [[ "$push_confirm" =~ ^[yY]$ ]]; then
            log "Pushing to remote..."
            cd "$local_path" || exit 1
            git_with_signing push origin HEAD || error "Push failed. Check your authentication."
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

                    if [[ -n "$mountpoint" ]] && [[ -d "$mountpoint" ]]; then
                        local drive_target="$mountpoint/omarchy-backup"
                        log "Syncing to external drive: $drive_target..."
                        mkdir -p "$drive_target"
                        local rsync_opts
                        rsync_opts=$(get_rsync_opts_for_path "$drive_target")
                        # shellcheck disable=SC2086
                        rsync $rsync_opts "$local_path/" "$drive_target/" || warn "Some files could not be synced (check filesystem limitations)"

                        if [[ "$was_mounted" == false ]]; then
                            unmount_drive "$device"
                        fi
                    else
                        error "Failed to access mountpoint: $mountpoint"
                    fi
                fi
            fi
        fi
    fi

    echo ""
    done_ "Backup complete."
    notify "Backup Complete" "Successfully backed up to $local_path"
}
