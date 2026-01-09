#!/bin/bash
# drives.sh - Drive detection, mounting, and unmounting

get_safe_drives() {
    # Returns lines of: device|size|fstype|mountpoint|label|status
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / | sed 's/\[.*\]//')

    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL -p -n -r 2>/dev/null | while read -r name size fstype mountpoint label; do
        # Skip if empty name or not a partition
        [[ -z "$name" ]] && continue
        [[ ! "$name" =~ [0-9]$ ]] && continue # Skip whole disks, only partitions

        # Unescape lsblk -r output (converts \x20 to spaces, etc.)
        mountpoint=$(printf '%b' "$mountpoint")
        label=$(printf '%b' "$label")

        # Skip system partitions
        [[ "$name" == "$root_dev" ]] && continue
        [[ "$mountpoint" =~ ^/(boot|home|var|usr|etc)?$ ]] && continue

        # Skip unsafe filesystems
        [[ "$fstype" == "ntfs" ]] && continue
        [[ "$fstype" == "swap" ]] && continue
        [[ "$fstype" == "crypto_LUKS" ]] && continue
        [[ -z "$fstype" ]] && continue

        # Skip EFI/system partitions by label
        local label_lower="${label,,}"
        [[ "$label_lower" =~ (efi|system|recovery|boot|reserved) ]] && continue

        # Determine mount status
        local status="not mounted"
        [[ -n "$mountpoint" ]] && status="mounted"

        echo "$name|$size|$fstype|$mountpoint|$label|$status"
    done
}

display_available_drives() {
    local drives
    drives=$(get_safe_drives)

    if [[ -z "$drives" ]]; then
        log "No external drives available."
        return 1
    fi

    echo ""
    log "Available drives for backup:"
    local i=1
    echo "$drives" | while IFS='|' read -r name size fstype mountpoint label status; do
        local display_label="${label:-unnamed}"
        local mount_info=""
        if [[ "$status" == "mounted" ]]; then
            mount_info="[mounted at $mountpoint]"
        else
            mount_info="[not mounted]"
        fi
        echo "    $i. $display_label ($size, $fstype) - $name $mount_info"
        ((i++))
    done
    echo ""
    return 0
}

select_drive() {
    local drives
    drives=$(get_safe_drives)

    if [[ -z "$drives" ]]; then
        return 1
    fi

    local count
    count=$(echo "$drives" | wc -l)

    local selection
    read -rp "Select drive (0 to skip): " selection

    if [[ "$selection" == "0" ]] || [[ -z "$selection" ]]; then
        return 1
    fi

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt "$count" ]]; then
        error "Invalid selection."
        return 1
    fi

    echo "$drives" | sed -n "${selection}p"
}

mount_drive() {
    local device="$1"
    local current_mount
    current_mount=$(lsblk -n -o MOUNTPOINT "$device" 2>/dev/null | head -1)

    if [[ -n "$current_mount" ]]; then
        echo "$current_mount"
        return 0
    fi

    log "Mounting $device..."
    udisksctl mount -b "$device" --no-user-interaction 2>/dev/null | grep -oP "at \K.*" || {
        error "Failed to mount $device"
        return 1
    }
}

unmount_drive() {
    local device="$1"
    log "Unmounting $device..."
    udisksctl unmount -b "$device" --no-user-interaction 2>/dev/null || true
}
