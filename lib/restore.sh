#!/bin/bash
# restore.sh - Restore functionality

restore_browser_data() {
    local source="$1"

    [[ ! -d "$source/browser" ]] && return 0

    for browser_dir in "$source/browser"/*; do
        [[ ! -d "$browser_dir" ]] && continue

        local browser_name
        browser_name=$(basename "$browser_dir")
        local target_dir="$HOME/.config/$browser_name/Default"

        if [[ ! -d "$target_dir" ]]; then
            warn "Browser profile not found: $target_dir - skipping"
            continue
        fi

        log "Restoring $browser_name data..."

        # Restore portable files
        for item in "Bookmarks" "Preferences" "History"; do
            if [[ -f "$browser_dir/$item" ]]; then
                [[ -f "$target_dir/$item" ]] && mv "$target_dir/$item" "$target_dir/$item.backup"
                cp "$browser_dir/$item" "$target_dir/"
            fi
        done

        # Restore extension settings
        for dir in "Local Extension Settings" "Sync Extension Settings" "Managed Extension Settings"; do
            [[ -d "$browser_dir/$dir" ]] && \
                rsync -aq "$browser_dir/$dir/" "$target_dir/$dir/"
        done

        # Show extension list for user to reinstall
        if [[ -f "$browser_dir/extensions.txt" ]]; then
            echo ""
            log "Extensions to reinstall (click to open Chrome Web Store):"
            grep "|" "$browser_dir/extensions.txt" | while IFS='|' read -r name id version; do
                name=$(echo "$name" | xargs)  # trim whitespace
                id=$(echo "$id" | xargs)
                version=$(echo "$version" | xargs)
                local url="https://chromewebstore.google.com/detail/$id"
                # OSC 8 hyperlink: \e]8;;URL\e\\TEXT\e]8;;\e\\
                echo -e "  - \e]8;;${url}\e\\${name} (v${version})\e]8;;\e\\"
            done
        fi
    done
}

# Component selection for restore
select_restore_components() {
    # Components: 1=configs, 2=packages, 3=local_bin, 4=system, 5=dconf, 6=shell, 7=ssh, 8=browser
    local -A selected=([1]=1 [3]=1 [4]=1 [5]=1 [6]=1 [8]=1)  # Default: all except packages and SSH
    local -a labels=(
        "Configs (~/.config)"
        "Packages (repo + AUR)"
        "Local bin (~/.local/bin)"
        "System files (pacman.conf, hosts)"
        "Desktop settings (dconf)"
        "Shell configs (.zshrc, etc.)"
        "SSH keys (encrypted)"
        "Browser data (Chrome/Chromium)"
    )

    display_components() {
        echo ""
        log "Select components to restore:"
        for i in {1..8}; do
            local mark=" "
            [[ -n "${selected[$i]:-}" ]] && mark="x"
            echo "  $i. [$mark] ${labels[$((i-1))]}"
        done
        echo ""
        echo "Toggle with numbers (1-8), 'a' for all, 'n' for none, Enter to confirm"
    }

    display_components

    while true; do
        read -rp "Toggle: " choice
        case "$choice" in
            [1-8])
                if [[ -n "${selected[$choice]:-}" ]]; then
                    unset "selected[$choice]"
                else
                    selected[$choice]=1
                fi
                display_components
                ;;
            a)
                for i in {1..8}; do selected[$i]=1; done
                display_components
                ;;
            n)
                selected=()
                display_components
                ;;
            "")
                break
                ;;
        esac
    done

    # Return selected indices
    echo "${!selected[*]}"
}

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
    local is_cross_machine=false
    if [[ "$backup_host" != "unknown" ]] && [[ "$backup_host" != "$current_host" ]]; then
        is_cross_machine=true
        echo ""
        log "WARNING: This backup is from '$backup_host', you're on '$current_host'."
        log "Machine-specific configs will be excluded automatically."
        local host_confirm
        host_confirm=$(prompt "Continue anyway? (y/N): " "n")
        [[ ! "$host_confirm" =~ ^[yY]$ ]] && {
            echo "Aborted."
            exit 0
        }
    fi

    # Component selection
    local components
    components=$(select_restore_components)
    if [[ -z "$components" ]]; then
        echo "No components selected. Aborted."
        exit 0
    fi

    # Build exclude list from .restore-excludes
    # The file contains HOME-relative paths like .config/chromium
    local excludes=()
    if [[ -f "$restore_path/.restore-excludes" ]]; then
        log "Loading exclude list..."
        while IFS= read -r relpath; do
            [[ -z "$relpath" ]] && continue
            # Paths are HOME-relative (e.g., .config/chromium)
            # For rsync excludes, we need path relative to config/ (e.g., chromium)
            local config_relpath="${relpath#.config/}"
            excludes+=(--exclude="$config_relpath")
            log "  Will preserve: ~/$relpath"
        done <"$restore_path/.restore-excludes"
    fi

    # Add machine-specific exclusions for cross-machine restore
    if [[ "$is_cross_machine" == true ]] && [[ -f "$restore_path/.machine-specific" ]]; then
        log "Excluding machine-specific configs..."
        while IFS= read -r relpath; do
            [[ -z "$relpath" ]] && continue
            # Paths are HOME-relative (e.g., .config/hypr/monitors.conf)
            # For rsync excludes, we need path relative to config/ (e.g., hypr/monitors.conf)
            local config_relpath="${relpath#.config/}"
            excludes+=(--exclude="$config_relpath")
            log "  Excluding: ~/$relpath"
        done < "$restore_path/.machine-specific"
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

    # Component 1: Restore configs (~/.config)
    if [[ "$components" == *1* ]]; then
        log "Restoring ~/.config..."
        mkdir -p "$HOME/.config"
        rsync -aq --delete "${excludes[@]}" "$restore_path/config/" "$HOME/.config/"

        log "Restoring local data..."
        mkdir -p "$HOME/.local/share/applications"
        rsync -aq --delete --exclude='.git' --delete-excluded "$restore_path/local_share/applications/" "$HOME/.local/share/applications/"
    fi

    # Component 3: Restore local bin
    if [[ "$components" == *3* ]] && [[ -d "$restore_path/bin" ]]; then
        log "Restoring ~/.local/bin..."
        mkdir -p "$HOME/.local/bin"
        rsync -aq --delete --exclude='.git' --delete-excluded "$restore_path/bin/" "$HOME/.local/bin/"
    fi

    # Component 4: Restore system configs
    if [[ "$components" == *4* ]]; then
        if [[ -f "$restore_path/etc/pacman.conf" ]]; then
            log "Restoring /etc/pacman.conf..."
            sudo cp "$restore_path/etc/pacman.conf" /etc/pacman.conf
        fi
        if [[ -f "$restore_path/etc/hosts" ]]; then
            log "Restoring /etc/hosts..."
            sudo cp "$restore_path/etc/hosts" /etc/hosts
        fi
    fi

    # Component 5: Restore dconf
    if [[ "$components" == *5* ]]; then
        if [[ -f "$restore_path/dconf_settings.ini" ]] && command -v dconf &>/dev/null; then
            log "Loading dconf settings..."
            dconf load / <"$restore_path/dconf_settings.ini" || true
        fi
    fi

    # Component 6: Restore shell configs
    if [[ "$components" == *6* ]] && [[ -d "$restore_path/shell" ]]; then
        log "Restoring shell configs..."
        for rc in "$restore_path/shell/"*; do
            [[ -f "$rc" ]] && cp "$rc" "$HOME/"
        done
    fi

    # Component 7: Restore SSH keys (encrypted)
    if [[ "$components" == *7* ]]; then
        restore_secrets "$restore_path"
    fi

    # Component 8: Restore browser data (Chrome/Chromium)
    if [[ "$components" == *8* ]]; then
        restore_browser_data "$restore_path"
    fi

    # Component 2: Reinstall packages
    if [[ "$components" == *2* ]]; then
        echo ""
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
    notify "Restore Complete" "Restored from $restore_path"
}
