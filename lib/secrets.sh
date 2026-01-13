#!/bin/bash
# secrets.sh - SSH key backup and restoration

backup_secrets() {
    local target="$1"

    local ssh_dir="$HOME/.ssh"
    if [[ ! -d "$ssh_dir" ]]; then
        log "No ~/.ssh directory - skipping SSH key backup"
        return 0
    fi

    log "Backing up SSH keys..."
    mkdir -p "$target/secrets"

    # Create compressed tarball of SSH keys
    # Protection: backed up to git (SSH transport encrypted) + directory chmod 700
    if tar -czf "$target/secrets/ssh.tar.gz" -C "$HOME" .ssh 2>/dev/null; then
        log "SSH keys backed up successfully"
    else
        warn "Failed to backup SSH keys"
        return 1
    fi
}

restore_secrets() {
    local source="$1"
    local backup_file="$source/secrets/ssh.tar.gz"

    # Check if backup exists
    if [[ ! -f "$backup_file" ]]; then
        return 0
    fi

    echo ""
    log "Restoring SSH keys..."
    echo ""
    echo "This will restore your SSH keys to ~/.ssh"
    local confirm_restore
    confirm_restore=$(prompt "Continue with restore? (Y/n): " "y")

    if [[ ! "$confirm_restore" =~ ^[yY]$ ]]; then
        log "SSH key restore cancelled"
        return 0
    fi

    echo ""

    # Extract SSH keys
    if tar -xzf "$backup_file" -C "$HOME" 2>/dev/null; then
        # Set correct permissions
        chmod 700 "$HOME/.ssh"
        find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
        find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \;

        log "SSH keys restored successfully"
    else
        error "Failed to restore SSH keys"
        return 1
    fi
}
