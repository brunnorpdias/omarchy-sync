# New Machine Setup Guide

This guide walks you through restoring your Omarchy system backup to a new machine.

## Prerequisites

1. **Install age** for SSH key decryption:
   ```bash
   sudo pacman -S age
   ```

2. **Have your 1Password SSH agent running** (if using 1Password for SSH keys)
   - Or have access to your SSH private key

3. **Install git**:
   ```bash
   sudo pacman -S git
   ```

## Steps

### 1. Get omarchy-sync

**Option A: Clone from remote**
```bash
git clone https://github.com/YOUR_USERNAME/omarchy-sync.git
cd omarchy-sync
```

**Option B: Copy from USB/drive**
```bash
cp -r /mnt/usb/omarchy-sync ~/
cd ~/omarchy-sync
```

### 2. Initialize with existing backup

```bash
./omarchy-sync.sh --init
```

When prompted, select **"Clone from existing backup remote"** and enter your backup repository URL.

### 3. Restore your backup

```bash
./omarchy-sync.sh --restore
```

**Component Selection:**
You'll see a menu to select which components to restore:

```
Select components to restore:
  1. [x] Configs (~/.config)
  2. [ ] Packages (repo + AUR)
  3. [x] Local bin (~/.local/bin)
  4. [x] System files (pacman.conf, hosts)
  5. [x] Desktop settings (dconf)
  6. [x] Shell configs (.zshrc, etc.)
  7. [ ] SSH keys (encrypted)
```

- Toggle options with numbers 1-7
- Press `a` for all, `n` for none
- Press Enter to confirm

**Recommended order:**
1. First restore without packages and SSH keys (default)
2. Reboot
3. Then restore packages separately if needed

### 4. SSH Key Restoration

If you selected SSH keys (option 7), you'll need to authenticate:

**With 1Password:**
- The SSH agent will prompt for authentication
- Approve the decryption request in 1Password

**Without 1Password:**
- You'll be prompted to provide your SSH private key passphrase

### 5. Reboot

After restore completes:

```bash
sudo reboot
```

## What Gets Restored

| Component | Description |
|-----------|-------------|
| Configs | ~/.config directory (excluding machine-specific) |
| Packages | Package lists (reinstalls via pacman/yay) |
| Local bin | ~/.local/bin scripts |
| System files | /etc/pacman.conf, /etc/hosts |
| Desktop | dconf/GNOME settings |
| Shell | .zshrc, .bashrc, .profile |
| SSH keys | Decrypted from age-encrypted archive |

## Machine-Specific Configs

These configs are **NOT restored** when restoring to a different machine:

- **Hyprland**: Monitor layouts (monitors.conf), input settings
- **Display**: GPU configs, display arrangements
- **Audio**: Device-specific audio settings
- **Bluetooth**: Paired devices (different hardware)
- **Input**: Touchpad gestures (laptop vs desktop)
- **Power**: TLP/powertop settings (laptop-specific)

After restore, you'll need to configure these manually for your new hardware.

## Troubleshooting

### "age not installed - cannot restore SSH keys"

Install age:
```bash
sudo pacman -S age
```

### "No SSH private key found"

The restore expects `~/.ssh/id_ed25519` or `~/.ssh/id_rsa` to exist.

Manual decrypt:
```bash
age -d -i YOUR_PRIVATE_KEY path/to/backup/secrets/ssh.tar.age | tar -xf -
```

### Cross-machine restore warning

If you see:
```
WARNING: This backup is from 'desktop', you're on 'laptop'.
Machine-specific configs will be excluded automatically.
```

This is expected. Hardware-specific configs are automatically skipped.

### Packages fail to install

Some packages may have been removed from repositories:
```bash
# Check the error log
cat /tmp/pacman.log

# Install available packages manually
sudo pacman -S --needed pkg1 pkg2 pkg3
```

### Hyprland doesn't start

You'll need to create a new `monitors.conf` for your hardware:
```bash
# Auto-detect monitors
hyprctl monitors > ~/.config/hypr/monitors.conf
```

Edit to match your preferred layout.

## Post-Restore Checklist

- [ ] Reboot system
- [ ] Login and verify desktop loads
- [ ] Check shell config (open new terminal)
- [ ] Configure monitor layout (if Hyprland)
- [ ] Pair Bluetooth devices
- [ ] Set up audio devices
- [ ] Test SSH keys: `ssh -T git@github.com`
- [ ] Run backup to include new machine-specific configs
