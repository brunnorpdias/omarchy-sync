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
EOF
}

get_config_value() {
    local key="$1"
    local default="${2:-}"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi
    local value
    value=$(grep -E "^$key\s*=" "$CONFIG_FILE" | head -1 | sed 's/^[^=]*=\s*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${value:-$default}"
}

set_config_value() {
    local key="$1"
    local value="$2"
    if grep -qE "^$key\s*=" "$CONFIG_FILE"; then
        sed -i "s|^$key\s*=.*|$key = \"$value\"|" "$CONFIG_FILE"
    else
        echo "$key = \"$value\"" >>"$CONFIG_FILE"
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
        in_drive && /^\[/ { if (path != "") print path "/omarchy-backup|" label; in_drive=0 }
        END { if (in_drive && path != "") print path "/omarchy-backup|" label }
    ' "$CONFIG_FILE"
}
