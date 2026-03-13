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

### How to use:

1. Clone the repository to your system.
2. Ensure the script is executable: `chmod +x cachyos_maintain.sh`
3. Run the script:
   ```bash
   ./cachyos_maintain.sh
   ```

*Note: The script tracks its execution state in `~/.local/state/cachyos_maintenance.state` to ensure tasks are only run when due (Weekly, Monthly, Bi-annually).*
