#!/bin/bash
# config.sh - Configuration file management

config_exists() {
    [[ -f "$CONFIG_FILE" ]]
}

create_default_config() {
    mkdir -p "$CONFIG_DIR"
    cat <<EOF >"$CONFIG_FILE"
[local]
path = "$DEFAULT_LOCAL_PATH"

[remote]
url = ""

[settings]
size_limit_mb = 20

# Internal drives with permanent mount points
# Add entries like:
# [[internal_drives]]
# path = "/mnt/data"
# label = "Internal HDD"

[machine_specific]
# Additional configs to treat as machine-specific
# These are excluded when restoring to a different hostname
# Default blacklist includes: hypr/monitors.conf, monitors.xml, bluetooth, etc.
additional = []
EOF
}

get_config_value() {
    local key="$1"
    local default="${2:-}"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi

    # Escape regex metacharacters in key
    local escaped_key
    escaped_key=$(printf '%s' "$key" | sed 's/[.[\*^$()+?{|\\]/\\&/g')

    local value
    value=$(grep -E "^${escaped_key}\s*=" "$CONFIG_FILE" | head -1 | \
            sed 's/^[^=]*=\s*//' | \
            sed 's/^"\(.*\)"$/\1/' | \
            sed "s/^'\(.*\)'$/\1/" | \
            sed 's/#.*//' | \
            xargs)
    echo "${value:-$default}"
}

set_config_value() {
    local key="$1"
    local value="$2"

    # Escape special characters for sed
    local escaped_key escaped_value
    escaped_key=$(printf '%s' "$key" | sed 's/[&/\]/\\&/g')
    escaped_value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')

    if grep -qE "^$key\s*=" "$CONFIG_FILE"; then
        sed -i "s|^${escaped_key}\s*=.*|$key = \"$escaped_value\"|" "$CONFIG_FILE"
    else
        echo "$key = \"$value\"" >> "$CONFIG_FILE"
    fi
}

get_local_path() {
    get_config_value "path" "$DEFAULT_LOCAL_PATH"
}

get_remote_url() {
    get_config_value "url" ""
}

get_size_limit() {
    get_config_value "size_limit_mb" "20"
}

get_internal_drives() {
    # Returns lines of "path|label" with /omarchy-backup appended to path
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi
    awk '
        /^\[\[internal_drives\]\]/ { in_drive=1; path=""; label=""; next }
        in_drive && /^path\s*=/ { gsub(/^path\s*=\s*["'\''"]?|["'\''"]?\s*$/, ""); path=$0 }
        in_drive && /^label\s*=/ { gsub(/^label\s*=\s*["'\''"]?|["'\''"]?\s*$/, ""); label=$0 }
        in_drive && /^\[/ { if (path != "") { gsub(/\/+$/, "", path); print path "/omarchy-backup|" label } in_drive=0 }
        END { if (in_drive && path != "") { gsub(/\/+$/, "", path); print path "/omarchy-backup|" label } }
    ' "$CONFIG_FILE"
}

# Machine-specific configs (excluded from cross-machine restore)
# These would cause issues when restoring desktop backup on laptop or vice versa
MACHINE_SPECIFIC_CONFIGS=(
    # Hyprland (Critical)
    "hypr/monitors.conf"
    "hypr/input.conf"
    "hypr/*.bak.*"
    "hypr/hyprland.conf.bak.*"
    "hypr/input.conf.bak.*"

    # Display & GPU
    "monitors.xml"
    "monitors.xml~"
    "nvidia-settings-rc"
    "amdgpu*"
    "xfce4/xfconf/xfce-perchannel-xml/displays.xml"
    "kwinoutputconfig.json"
    "kscreen"

    # Audio hardware
    "pulse/default.pa"
    "pulse/*-default-sink"
    "pulse/*-default-source"
    "pipewire/media-session.d"
    "wireplumber/main.lua.d"

    # Input devices
    "libinput-gestures.conf"
    "touchegg"
    "pointing-device"
    "kcminputrc"

    # Bluetooth & peripherals
    "bluetooth"
    "cups"
    "sane.d"

    # Hardware-specific
    "openrgb"
    "fancontrol"
    "tlp"
    "powertop"
    "auto-cpufreq"

    # Network hardware
    "NetworkManager/system-connections"
)

get_machine_specific_configs() {
    # Start with defaults
    local configs=("${MACHINE_SPECIFIC_CONFIGS[@]}")

    # Add user-configured items from config.toml
    if [[ -f "$CONFIG_FILE" ]]; then
        local in_section=false
        while IFS= read -r line; do
            # Check for section start
            if [[ "$line" =~ ^\[machine_specific\] ]]; then
                in_section=true
                continue
            fi
            # Check for new section (end of machine_specific)
            if [[ "$line" =~ ^\[.+\] ]]; then
                in_section=false
                continue
            fi
            # Parse additional items
            if $in_section && [[ "$line" =~ ^additional.*=.*\[(.*)\] ]]; then
                local items="${BASH_REMATCH[1]}"
                # Extract quoted strings
                while [[ "$items" =~ \"([^\"]+)\" ]]; do
                    configs+=("${BASH_REMATCH[1]}")
                    items="${items/${BASH_REMATCH[0]}/}"
                done
            fi
        done < "$CONFIG_FILE"
    fi

    printf '%s\n' "${configs[@]}"
}

create_machine_specific_list() {
    local target="$1"
    : > "$target/.machine-specific"

    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        # Find files/dirs matching pattern in backup
        # Handle glob patterns by using find with -name or -path
        # Store HOME-relative paths (e.g., .config/hypr/monitors.conf) for portability
        if [[ "$pattern" == *"/"* ]]; then
            # Path pattern - match full path
            find "$target/config" -path "*/$pattern" -print 2>/dev/null | \
                sed "s|^$target/config/|.config/|" >> "$target/.machine-specific"
        else
            # Name pattern - match filename
            find "$target/config" -name "$pattern" -print 2>/dev/null | \
                sed "s|^$target/config/|.config/|" >> "$target/.machine-specific"
        fi
    done < <(get_machine_specific_configs)

    # Log count for user awareness
    local count
    count=$(wc -l < "$target/.machine-specific" 2>/dev/null || echo 0)
    if [[ "$count" -gt 0 ]]; then
        log "Tagged $count machine-specific config(s)"
    fi
}
