# omarchy-sync

Backup and restore tool for Arch Linux (Omarchy) systems.

## Features

- Backup `~/.config`, packages, shell configs, SSH keys, browser data
- Sync to local, cloud (git), internal drives, external drives
- Machine-specific config handling (auto-excluded on cross-machine restore)
- Encrypted SSH key backup (age + 1Password compatible)
- Chrome/Chromium portable data with extension list for reinstallation
- Selective component restore
- Backup verification with checksums
- Desktop notifications

## Installation

### Easiest: Run `--init` to setup and install

```bash
./omarchy-sync.sh --init
```

The `--init` command will:
- Create your backup directory
- Initialize git repository (for version tracking)
- Run your first backup
- Offer to install the script to `~/.local/bin/omarchy-sync` for easy access

### Manual installation

If you prefer to install separately:

```bash
./omarchy-sync.sh --install
```

This installs the script to `~/.local/bin/omarchy-sync`.

## Quick Start

```bash
omarchy-sync --init      # First-time setup
omarchy-sync --backup    # Create backup
omarchy-sync --restore   # Restore from backup
```

## Commands

| Command | Description |
|---------|-------------|
| `--init` | First-time setup or clone from existing remote (offers to install executable) |
| `--config` | View and modify settings |
| `--backup` | Backup to local, cloud, and/or external drives |
| `--restore` | Restore from local, cloud, or external drive |
| `--verify` | Verify backup integrity using checksums |
| `--status` | Show backup status across all locations |
| `--install` | Install to ~/.local/bin/omarchy-sync (called automatically by `--init`) |
| `--version` | Show version |
| `--help` | Show help |

## Options

| Option | Description |
|--------|-------------|
| `--test [DIR]` | Test mode with isolated environment |
| `--log [FILE]` | Enable logging to file |
| `--no-prompt` | Non-interactive mode (for cron/scripts) |

## Configuration

Config file: `~/.config/omarchy-sync/config.toml`

```toml
[local]
path = "~/.local/share/omarchy-sync/backup"

[remote]
url = "git@github.com:user/backup-repo.git"

[settings]
size_limit_mb = 20

[[internal_drives]]
path = "/mnt/data"
label = "Internal HDD"

[machine_specific]
additional = ["myapp/hardware-config"]
```

## What Gets Backed Up

- **~/.config** - Application configs (respects size limit)
- **Packages** - Repo and AUR package lists
- **~/.local/bin** - Local scripts
- **System files** - `/etc/pacman.conf`, `/etc/hosts`
- **Desktop settings** - dconf/GNOME settings
- **Shell configs** - `.zshrc`, `.bashrc`, `.profile`
- **Browser data** - Bookmarks, preferences, history, extension settings, extension list
- **SSH keys** - Encrypted with age (requires `age` package)

## Machine-Specific Configs

The following configs are automatically excluded when restoring to a different machine:

- **Hyprland**: `monitors.conf`, `input.conf`, `.bak.*` files
- **Display/GPU**: `monitors.xml`, `nvidia-settings-rc`, `kscreen`
- **Audio**: PulseAudio/PipeWire device configs
- **Input**: Touchpad gestures, keyboard settings
- **Bluetooth**: Paired devices
- **Hardware**: RGB lighting, fan control, power management

You can add custom exclusions in `config.toml`:

```toml
[machine_specific]
additional = ["myapp/hardware-config"]
```

## Filesystem Support & Symlinks

**Supported Filesystems:**

| Filesystem | Status | Symlink Handling |
|-----------|--------|------------------|
| ext4, btrfs, xfs, f2fs | ✅ Full Support | Symlinks preserved as symlinks |
| exFAT, FAT32, MSDOS | ✅ Supported | Symlinks converted to files, recreated on restore |
| NTFS | ❌ Not Supported | Rejected with error message |
| vfat | ❌ Not Supported | Rejected with error message (EFI/boot partitions) |

**Filesystem Transparency:**

omarchy-sync displays the filesystem type when backing up and restoring, so you always know where your data is going:

Backup example:
```
[*] Backing up to local (/home/user/.local/share/omarchy-sync/backup) [ext4]
[*] Syncing to internal drive: MyDrive (/mnt/hd/omarchy-backup) [exFAT]
[WARN] Target filesystem: exfat (does not support symlinks)
[WARN] Symlinks will be converted to regular files (reversible via .symlinks manifest)
[WARN] Backup size will be larger. Symlinks automatically recreated on restore.
```

Restore example:
```
Available restore sources:
  1. Local (/home/user/.local/share/omarchy-sync/backup) [ext4]
     Last backup: 2026-01-12, host: omarchy
  2. MyData (/mnt/hd/omarchy-backup) [exFAT]
     Last backup: 2026-01-12, host: omarchy
```

**Symlink Handling:**

omarchy-sync automatically detects the filesystem type and handles symlinks appropriately:

- **Native Linux filesystems (ext4, btrfs, xfs, f2fs):** Symlinks are preserved as symlinks during backup and restore
- **FAT variants (exFAT, FAT32, MSDOS):** Since these filesystems don't support symlinks, files they point to are copied instead. A `.symlinks` manifest records symlink information, and symlinks are automatically recreated during restore
- **Unsupported (NTFS, vfat):** Backups are rejected with an error message. Use exFAT instead for cross-platform USB drives
- **Cross-machine restore:** Symlinks pointing to broken locations are preserved as symlinks (not deleted), allowing manual fixing if needed

**Example:**

Your system has: `~/.local/bin/claude` → symlink to `~/.local/share/claude/versions/2.1.5`

- Backup to ext4: Symlink preserved
- Backup to exFAT: File copied (220MB), symlink info stored in `.symlinks` manifest
- Restore from exFAT: Symlink automatically recreated from manifest
- Backup to NTFS: Error - "NTFS is not supported (unreliable on Linux). Please use exFAT or a native Linux filesystem instead"

This ensures your system never receives corrupted 220MB binary files in place of symlinks, and you have clear visibility into potential limitations.

## SSH Key Encryption (v1.4.0+)

SSH keys are encrypted using **age** with **dedicated encryption keys** (not Git SSH keys).

### Setup

During `--init`, you'll be asked:

```
Generate new age encryption key? (Y/n):
```

- **Yes (recommended)**: System generates a new age key pair
  - Public key automatically saved in config
  - **Private key shown ONCE** - save it in your password manager (1Password, Bitwarden, etc.)
  - You'll need it when restoring

- **No (power users)**: Provide your existing age public key
  - Useful if you already have age keys

### Restore

During `--restore`, when SSH keys are in the backup:

```
Enter the path to your age private key file:
```

- Provide the path to your saved private key
- Or save the key to a temporary file and provide that path

### Why Dedicated Encryption Keys?

- **Security**: Separates authentication (Git SSH) from encryption
- **Best Practice**: Different keys for different purposes
- **Flexibility**: Can rotate encryption keys without affecting Git access
- **age Native**: Uses age's native key format (more efficient than SSH keys)

### BREAKING CHANGE: v1.4.0

**v1.4.0 is NOT backward compatible with v1.3.x backups!**

- Old backups encrypted with SSH keys cannot be restored with v1.4.0+
- If you have old backups using v1.3.x: Keep the v1.3.x binary to restore them
- After restoring, run `omarchy-sync --init` with v1.4.0 to set up dedicated encryption keys
- Create new backups with `--backup`

### Requirements

- Install `age`: `pacman -S age`
- Generate or import age encryption keys during `--init`

## New Machine Setup

See [docs/new-machine-setup.md](docs/new-machine-setup.md)

## Examples

```bash
# First-time setup
omarchy-sync --init

# Create backup
omarchy-sync --backup

# Restore from backup
omarchy-sync --restore

# Test in isolated environment
omarchy-sync --test --init

# Backup with logging
omarchy-sync --log --backup

# Backup without prompts (for cron)
omarchy-sync --no-prompt --backup

# Verify backup integrity
omarchy-sync --verify
```

## Cron Setup

Add to crontab for automatic daily backups:

```bash
# Edit crontab
crontab -e

# Add this line for daily backup at 2 AM
0 2 * * * /home/user/.local/bin/omarchy-sync --no-prompt --backup
```

## Security Considerations

**Always use a private repository** for your backup. Even though SSH keys are encrypted with `age`, other backed-up files may contain sensitive data:

- Browser extension settings may store API keys or tokens
- Shell configs (`.zshrc`, `.bashrc`) may contain environment variables with secrets
- Application preferences may contain authentication data

Recommendations:
- Use a **private** GitHub/GitLab repository
- Enable 2FA on your git hosting account
- Consider encrypting the entire repository for maximum security
- Review `.gitignore` to ensure sensitive files are excluded

## License

MIT
