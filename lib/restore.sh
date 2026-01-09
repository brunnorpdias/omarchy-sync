#!/bin/bash
# restore.sh - Restore functionality

restore_command() {
    echo "--- Omarchy Sync: Restore ---"

    if ! config_exists; then
        error "Not initialized. Run 'omarchy-sync --init' first."
        exit 1
    fi

    local local_path
    local_path=$(get_local_path)
    local remote_url
    remote_url=$(get_remote_url)

    # Build list of available sources
    echo ""
    log "Available restore sources:"
    local sources=()
    local i=1

    # Local
    if [[ -d "$local_path/config" ]]; then
        local local_ts
        local_ts=$(get_metadata_field "$local_path" "timestamp")
        local local_host
        local_host=$(get_metadata_field "$local_path" "hostname")
        echo "    $i. Local ($local_path)"
        echo "       Last backup: $local_ts, host: $local_host"
        sources+=("local|$local_path")
        ((i++))
    fi

    # Remote
    if [[ -n "$remote_url" ]]; then
        echo "    $i. Cloud ($remote_url)"
        echo "       (will pull latest before restore)"
        sources+=("remote|$remote_url")
        ((i++))
    fi

    # External drives - Fixed: use process substitution to avoid subshell
    local drives
    drives=$(get_safe_drives)
    if [[ -n "$drives" ]]; then
        while IFS='|' read -r device size fstype mountpoint label status; do
            local check_path=""
            if [[ "$status" == "mounted" ]]; then
                check_path="$mountpoint/omarchy-backup"
            fi
            if [[ -n "$check_path" ]] && [[ -d "$check_path/config" ]]; then
                local drive_ts
                drive_ts=$(get_metadata_field "$check_path" "timestamp")
                local drive_host
                drive_host=$(get_metadata_field "$check_path" "hostname")
                echo "    $i. ${label:-$device} ($size, $fstype)"
                echo "       Last backup: $drive_ts, host: $drive_host"
                sources+=("drive|$device|$mountpoint")
                ((i++))
            fi
        done < <(echo "$drives")
    fi

    if [[ ${#sources[@]} -eq 0 ]]; then
        error "No restore sources available."
        exit 1
    fi

    echo ""
    local selection
    read -rp "Restore from (1): " selection
    selection="${selection:-1}"

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#sources[@]} ]]; then
        error "Invalid selection."
        exit 1
    fi

    local source_info="${sources[$((selection - 1))]}"
    local source_type="${source_info%%|*}"
    local restore_path=""

    case "$source_type" in
    local)
        restore_path="${source_info#*|}"
        ;;
    remote)
        log "Pulling latest from remote..."
        cd "$local_path" || exit 1
        git pull origin HEAD || {
            error "Pull failed."
            exit 1
        }
        restore_path="$local_path"
        ;;
    drive)
        IFS='|' read -r _ device mountpoint <<<"$source_info"
        if [[ -z "$mountpoint" ]]; then
            mountpoint=$(mount_drive "$device")
        fi
        restore_path="$mountpoint/omarchy-backup"
        ;;
    esac

    # Check hostname
    local backup_host
    backup_host=$(get_metadata_field "$restore_path" "hostname")
    local current_host
    current_host=$(hostname)
    if [[ "$backup_host" != "unknown" ]] && [[ "$backup_host" != "$current_host" ]]; then
        echo ""
        log "WARNING: This backup is from '$backup_host', you're on '$current_host'."
        local host_confirm
        host_confirm=$(prompt "Continue anyway? (y/N): " "n")
        [[ ! "$host_confirm" =~ ^[yY]$ ]] && {
            echo "Aborted."
            exit 0
        }
    fi

    # Build exclude list from .restore-excludes
    # The file contains full paths like /home/user/.config/large-app
    # We need to convert them to paths relative to the backup's config/ dir
    local excludes=()
    if [[ -f "$restore_path/.restore-excludes" ]]; then
        log "Loading exclude list..."
        while IFS= read -r fullpath; do
            [[ -z "$fullpath" ]] && continue
            # Extract the relative path from $HOME/.config/
            local relpath="${fullpath#$HOME/.config/}"
            # If it didn't change, it might be a .git path inside a subdir
            if [[ "$relpath" == "$fullpath" ]]; then
                # Try to extract relative to .config for nested .git dirs
                relpath="${fullpath##*/.config/}"
            fi
            excludes+=(--exclude="$relpath")
            log "  Will preserve: $fullpath"
        done <"$restore_path/.restore-excludes"
    fi

    # Dry run preview
    log "Calculating changes (dry run)..."
    echo ""

    echo "=== Directories to be DELETED from ~/.config ==="
    rsync -nrv --delete "${excludes[@]}" "$restore_path/config/" "$HOME/.config/" 2>/dev/null |
        grep "^deleting " |
        grep -E "^deleting [^/]+/$" |
        head -20 ||
        echo "(none)"

    local delete_count
    delete_count=$(rsync -nrv --delete "${excludes[@]}" "$restore_path/config/" "$HOME/.config/" 2>/dev/null | grep -c "^deleting " || true)
    delete_count="${delete_count:-0}"
    [[ "$delete_count" -gt 20 ]] && echo "... and $((delete_count - 20)) more files"

    echo ""
    echo "=== Directories to be ADDED/UPDATED ==="
    rsync -nrv "${excludes[@]}" "$restore_path/config/" "$HOME/.config/" 2>/dev/null |
        grep -E "/$" |
        grep -v "^\./" |
        head -20 ||
        echo "(none)"

    local update_count
    update_count=$(rsync -nrv "${excludes[@]}" "$restore_path/config/" "$HOME/.config/" 2>/dev/null | grep -cv "^$\|^sending\|^total\|^\./$" || true)
    update_count="${update_count:-0}"
    [[ "$update_count" -gt 20 ]] && echo "... and approximately $((update_count - 20)) more files"

    echo ""
    read -rp "Proceed with restore? (y/N): " confirm
    [[ $confirm != [yY] ]] && {
        echo "Aborted."
        exit 0
    }

    # Restore configs
    log "Restoring ~/.config..."
    rsync -aq --delete "${excludes[@]}" "$restore_path/config/" "$HOME/.config/"

    log "Restoring local data..."
    rsync -aq --delete --exclude='.git' --delete-excluded "$restore_path/local_share/applications/" "$HOME/.local/share/applications/"
    [[ -d "$restore_path/bin" ]] && rsync -aq --delete --exclude='.git' --delete-excluded "$restore_path/bin/" "$HOME/.local/bin/"

    # Restore system configs
    if [[ -f "$restore_path/etc/pacman.conf" ]]; then
        log "Restoring /etc/pacman.conf..."
        sudo cp "$restore_path/etc/pacman.conf" /etc/pacman.conf
    fi
    if [[ -f "$restore_path/etc/hosts" ]]; then
        log "Restoring /etc/hosts..."
        sudo cp "$restore_path/etc/hosts" /etc/hosts
    fi

    # Restore dconf
    if [[ -f "$restore_path/dconf_settings.ini" ]] && command -v dconf &>/dev/null; then
        log "Loading dconf settings..."
        dconf load / <"$restore_path/dconf_settings.ini" || true
    fi

    # Reinstall packages
    echo ""
    local pkg_confirm
    pkg_confirm=$(prompt "Reinstall packages? (y/N): " "n")
    if [[ "$pkg_confirm" =~ ^[yY]$ ]]; then
        log "Installing repo packages..."
        sudo pacman -S --needed - <"$restore_path/packages/pkglist-repo.txt" || true

        if command -v yay &>/dev/null; then
            log "Installing AUR packages with yay..."
            yay -S --needed - <"$restore_path/packages/pkglist-aur.txt" || true
        elif command -v paru &>/dev/null; then
            log "Installing AUR packages with paru..."
            paru -S --needed - <"$restore_path/packages/pkglist-aur.txt" || true
        else
            log "No AUR helper found. Install AUR packages manually from:"
            log "  $restore_path/packages/pkglist-aur.txt"
        fi
    fi

    echo ""
    done_ "Restore complete. Reboot recommended."
}
