#!/bin/bash
# metadata.sh - Backup metadata management

compute_checksum() {
    local dir="$1"
    [[ ! -d "$dir" ]] && { echo ""; return; }
    find "$dir" -type f -exec sha256sum {} \; 2>/dev/null | \
        sort | sha256sum | cut -d' ' -f1
}

write_metadata() {
    local target="$1"

    # Compute checksums for each component
    local config_sum shell_sum packages_sum
    config_sum=$(compute_checksum "$target/config")
    shell_sum=$(compute_checksum "$target/shell")
    packages_sum=$(compute_checksum "$target/packages")

    cat <<EOF >"$target/.backup-meta"
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$USER",
  "checksums": {
    "config": "sha256:${config_sum:-none}",
    "shell": "sha256:${shell_sum:-none}",
    "packages": "sha256:${packages_sum:-none}"
  }
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
