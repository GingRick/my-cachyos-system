# my-cachyos-system

This repository contains my automated maintenance procedures and verified stable system snapshots for CachyOS.

## System Maintenance Guide

For a detailed explanation of the maintenance tasks performed, see the exhaustive [CachyOS Maintenance Guide](cachyos_maintenance_guide.md).

## Automated Maintenance & Snapshot Backup

The `cachyos_maintain.sh` script automates essential system maintenance (updates, cleaning, BTRFS scrubs) based on recommended schedules.

Before any maintenance tasks are executed, the script performs a critical backup procedure:
1. It identifies the latest stable `snapper` system snapshot.
2. It generates a detailed description of the snapshot (including package counts, disk usage, and kernel version).
3. It creates a compressed archive (tarball) of the snapshot.
4. It commits the tarball and its description to this Git repository and pushes it to the remote.

This ensures that there is always a verifiable, stable fallback stored securely off-system *before* any potentially risky updates or maintenance are performed.

### Execution State & Granular Tracking
The script intelligently tracks the last execution time of every individual task (e.g., updates, orphan removal, cache cleaning). If you skip a prompt (by pressing 'N'), the script intentionally leaves that task marked as "pending" so it will prompt you again the next time it runs. 

The current state of your system's maintenance is saved directly within this repository in the `.state/cachyos_maintenance.state` file and is automatically committed after successful runs.

### How to use:

1. Clone the repository to your system.
2. Ensure the script is executable: `chmod +x cachyos_maintain.sh`
3. Run the script:
   ```bash
   ./cachyos_maintain.sh
   ```

**Force Mode:** To bypass all time schedules and forcefully run every maintenance check, use the `--force` flag:
```bash
./cachyos_maintain.sh --force
```

## System Recovery Procedure (Fresh Install)

If your system experiences a catastrophic failure requiring a fresh installation of CachyOS, you can use the archived state backed up in this repository (`backups/snapshot_backup.tar.zst`) to quickly restore your configurations and reinstall your software packages.

### 1. Install CachyOS
Perform a standard fresh installation of CachyOS using a live USB. Ensure you match your previous filesystem choices (e.g., BTRFS) if your restored `/etc/fstab` will depend on it.

### 2. Clone This Repository
Once booted into your fresh CachyOS installation, clone this repository:
```bash
git clone https://github.com/GingRick/my-cachyos-system.git
cd my-cachyos-system
```

### 3. Restore System Configurations
Extract the backed-up configurations (`/etc` and `/var/lib/pacman/local`) directly into the root directory. 
*⚠️ **Warning:** This will overwrite default configurations of the fresh install with your previous custom configurations.*

```bash
sudo tar -I "zstd" -xpf backups/snapshot_backup.tar.zst -C / etc var/lib/pacman/local
```

### 4. Reinstall Previous Packages
To seamlessly reinstall the exact list of packages you had previously, we will extract the old pacman database to a temporary directory, query it for your installed packages, and feed that list to your AUR helper.

First, extract the backed-up pacman local database:
```bash
mkdir -p /tmp/pacman-backup
tar -I "zstd" -xpf backups/snapshot_backup.tar.zst -C /tmp/pacman-backup var/lib/pacman/local
```

Next, generate a list of explicitly installed packages from the backup database:
```bash
pacman -Qqe -b /tmp/pacman-backup/var/lib/pacman > recovered_packages.txt
```

Finally, feed this list to `paru` (or `yay`/`pacman`) to download and install them:
```bash
paru -S --needed - < recovered_packages.txt
```

### 5. Finalize and Reboot
After all packages have finished installing:
1. Double-check for any mismatched configuration files by running `sudo pacdiff`.
2. Re-enable any custom systemd services you had running.
3. Reboot your system to apply all restored configurations and software.
