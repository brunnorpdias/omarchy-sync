#!/bin/bash
# secrets.sh - SSH key backup with age encryption

backup_secrets() {
    local target="$1"

    # Check if age is installed
    if ! command -v age &>/dev/null; then
        warn "age not installed - skipping SSH key backup"
        return 0
    fi

    # Get encryption public key from config
    local pubkey
    pubkey=$(get_encryption_public_key)

    if [[ -z "$pubkey" ]]; then
        warn "No encryption key configured - skipping SSH key backup"
        warn "Run 'omarchy-sync --config' to set up encryption"
        return 0
    fi

    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        log "No ~/.ssh directory - skipping SSH key backup"
        return 0
    fi

    log "Encrypting SSH keys..."
    mkdir -p "$target/secrets"

    # Create tarball and encrypt with age native public key
    if tar -czf - -C "$HOME" .ssh 2>/dev/null | \
       age -r "$pubkey" > "$target/secrets/ssh.tar.age" 2>/dev/null; then
        log "SSH keys encrypted successfully"
    else
        warn "Failed to encrypt SSH keys"
        return 1
    fi
}

restore_secrets() {
    local source="$1"
    local encrypted_file="$source/secrets/ssh.tar.age"

    # Check if encrypted backup exists
    if [[ ! -f "$encrypted_file" ]]; then
        return 0
    fi

    # Check if age is installed
    if ! command -v age &>/dev/null; then
        warn "age not installed - cannot restore SSH keys"
        warn "Install with: sudo pacman -S age"
        return 0
    fi

    echo ""
    log "Restoring encrypted SSH keys..."
    echo ""
    echo "Enter the path to your age private key file"
    echo "(the key shown during --init setup)"
    echo ""

    local privkey_path
    read -rp "Private key path: " privkey_path
    privkey_path="${privkey_path/#\~/$HOME}"

    if [[ ! -f "$privkey_path" ]]; then
        error "Private key file not found: $privkey_path"
        error "Cannot restore SSH keys without private key"
        return 1
    fi

    # Decrypt and extract
    if age -d -i "$privkey_path" "$encrypted_file" 2>/dev/null | \
       tar -xzf - -C "$HOME" 2>/dev/null; then

        # Set correct permissions
        chmod 700 "$HOME/.ssh"
        find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
        find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \;

        log "SSH keys restored successfully"
    else
        error "Failed to decrypt SSH keys"
        error "Check that you provided the correct private key"
        return 1
    fi
}
