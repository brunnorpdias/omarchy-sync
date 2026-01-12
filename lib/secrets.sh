#!/bin/bash
# secrets.sh - SSH key backup with age encryption

backup_secrets() {
    local target="$1"

    if ! command -v age &>/dev/null; then
        warn "age not installed - skipping SSH key backup"
        return 0
    fi

    local ssh_dir="$HOME/.ssh"
    [[ ! -d "$ssh_dir" ]] && return 0

    # Find SSH public key for encryption
    local pubkey=""
    for key in "$ssh_dir"/id_*.pub; do
        [[ -f "$key" ]] && { pubkey="$key"; break; }
    done

    if [[ -z "$pubkey" ]]; then
        warn "No SSH public key found - skipping SSH key backup"
        return 0
    fi

    log "Encrypting SSH keys..."
    mkdir -p "$target/secrets"

    # Create tarball excluding non-essential files
    if tar -C "$HOME" -cf - \
        --exclude='*.sock' \
        --exclude='agent.*' \
        --exclude='known_hosts*' \
        .ssh/ 2>/dev/null | age -R "$pubkey" > "$target/secrets/ssh.tar.age" 2>/dev/null; then
        log "SSH keys encrypted successfully"
    else
        warn "Failed to encrypt SSH keys"
        rm -f "$target/secrets/ssh.tar.age"
    fi
}

restore_secrets() {
    local source="$1"

    [[ ! -f "$source/secrets/ssh.tar.age" ]] && return 0

    if ! command -v age &>/dev/null; then
        error "age not installed - cannot restore SSH keys"
        return 1
    fi

    # Find SSH private key for decryption
    local privkey=""
    for key in "$HOME/.ssh"/id_ed25519 "$HOME/.ssh"/id_rsa; do
        [[ -f "$key" ]] && { privkey="$key"; break; }
    done

    # If not found, prompt user for key path
    if [[ -z "$privkey" ]]; then
        echo ""
        log "No SSH private key found at default locations (~/.ssh/id_ed25519, ~/.ssh/id_rsa)"
        read -rp "Enter path to SSH private key (or press Enter to skip): " privkey

        if [[ -z "$privkey" ]]; then
            warn "Skipping SSH key restore"
            warn "Manual: age -d -i YOUR_KEY $source/secrets/ssh.tar.age | tar -C ~ -xf -"
            return 0
        fi

        if [[ ! -f "$privkey" ]]; then
            error "Key file not found: $privkey"
            return 1
        fi
    fi

    log "Decrypting SSH keys using $privkey..."
    # age will use SSH agent (1Password) for decryption if available
    if age -d -i "$privkey" "$source/secrets/ssh.tar.age" 2>/dev/null | tar -C "$HOME" -xf - 2>/dev/null; then
        log "SSH keys restored successfully"
        # Ensure correct permissions
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh"/id_* 2>/dev/null || true
        chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
    else
        error "Failed to decrypt SSH keys"
        error "You may need to manually decrypt with 1Password or your SSH key"
        return 1
    fi
}
