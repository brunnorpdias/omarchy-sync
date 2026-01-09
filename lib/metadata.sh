#!/bin/bash
# metadata.sh - Backup metadata management

write_metadata() {
    local target="$1"
    cat <<EOF >"$target/.backup-meta"
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$USER"
}
EOF
}

read_metadata() {
    local target="$1"
    if [[ -f "$target/.backup-meta" ]]; then
        cat "$target/.backup-meta"
    else
        echo "{}"
    fi
}

get_metadata_field() {
    local target="$1"
    local field="$2"
    local meta
    meta=$(read_metadata "$target")
    echo "$meta" | grep -oP "\"$field\":\s*\"\K[^\"]*" || echo "unknown"
}
