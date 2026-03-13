# CachyOS / Arch Linux Maintenance Guide

Maintaining a rolling release distribution like CachyOS (based on Arch Linux) requires a proactive approach to ensure stability, performance, and a tidy system. While CachyOS provides many optimizations and GUI tools out of the box, understanding the underlying maintenance tasks is crucial.

Here is an exhaustive checklist to keep your CachyOS system in a great state.

## 1. System Updates
Staying up-to-date is vital for security and stability, but updates should be applied carefully.

*   **Regular Updates:** Update your system regularly (e.g., once a week). Avoid updating when you are in the middle of critical work.
    *   **CLI:** `sudo pacman -Syu` or use the AUR helper provided (often `paru` or `yay`): `paru -Syu`
    *   **GUI:** Use the CachyOS Hello app or Octopi.
*   **Read the News:** Before a major update, check the [CachyOS Discord/Forums](https://forum.cachyos.org/) or the [Arch Linux Homepage](https://archlinux.org/) for any manual intervention required.
*   **Reboot After Major Updates:** Always reboot after updating the kernel (`linux-cachyos`, etc.), `systemd`, `glibc`, or display drivers (NVIDIA/Mesa).

## 2. Package & Cache Management
Over time, your system will accumulate downloaded packages and orphaned dependencies that waste disk space.

*   **Clean the Package Cache:** Pacman keeps a cache of all downloaded packages.
    *   Keep the last 3 versions (safe for downgrading): `sudo paccache -r` (requires `pacman-contrib`)
    *   Keep only the currently installed version: `sudo paccache -rk1`
    *   Clear uninstalled packages: `sudo paccache -ruk0`
*   **Clean AUR Cache:** If using `paru` or `yay`, their caches also grow.
    *   `paru -Sc`
*   **Remove Orphaned Packages:** Orphans are dependencies that were installed for a package that has since been removed.
    *   List orphans: `pacman -Qtdq`
    *   Remove orphans and their configuration files: `sudo pacman -Rns $(pacman -Qtdq)`
    *   *Warning:* Always review the list before confirming the removal.

## 3. Configuration File Maintenance (.pacnew & .pacsave)
When a package updates its configuration file, `pacman` might save the new one as `.pacnew` (to preserve your edits) or save your old one as `.pacsave`.

*   **Find and Merge Configuration Changes:** Unmerged configs can cause services to fail after updates.
    *   Use `pacdiff` (requires `pacman-contrib`) to review and merge changes.
    *   Set the `DIFFPROG` environment variable to a visual diff tool for easier merging (e.g., `DIFFPROG=meld pacdiff`).

## 4. System Logs (Journald)
Systemd's journal collects logs from the kernel and services. It can grow to several gigabytes if not managed.

*   **Check Journal Size:** `journalctl --disk-usage`
*   **Vacuum (Clean) the Journal:**
    *   By time (keep last 2 weeks): `sudo journalctl --vacuum-time=2weeks`
    *   By size (keep max 100MB): `sudo journalctl --vacuum-size=100M`
*   **Persistent Limit:** Edit `/etc/systemd/journald.conf` and set `SystemMaxUse=100M` to limit it permanently.

## 5. Filesystem & Storage Health
CachyOS heavily optimizes for modern hardware, often defaulting to BTRFS and utilizing SSD features.

*   **TRIM for SSDs/NVMe:** Ensures longevity and performance of solid-state drives.
    *   Ensure the timer is enabled: `systemctl status fstrim.timer`
    *   If not enabled: `sudo systemctl enable --now fstrim.timer`
*   **BTRFS Maintenance (If applicable):** If you installed CachyOS with BTRFS, regular maintenance is recommended.
    *   **Scrub:** Checks for data integrity. `sudo btrfs scrub start /` (Check status with `sudo btrfs scrub status /`).
    *   **Balance:** Reallocates chunks to free up space. Only do this if BTRFS is reporting low space despite having free disk space.
    *   *Tip:* Consider installing and enabling `btrfsmaintenance` for automated scripts.

## 6. Backups and Snapshots
The most critical part of system stability is having a fallback when things go wrong.

*   **System Snapshots (BTRFS):** CachyOS usually integrates with `snapper` or `timeshift` if BTRFS is used.
    *   Ensure snapshots are being taken before and after package upgrades.
    *   Regularly clean up old snapshots so they don't consume all your disk space.
*   **Personal Data Backup:** Snapshots are *not* backups. Always back up your `/home` directory and critical files to an external drive or cloud storage using tools like `rsync`, `BorgBackup`, or `Restic`.

## 7. CachyOS Specific Optimizations
CachyOS includes custom repositories and kernels optimized for different CPU architectures.

*   **Mirrors:** Fast mirrors ensure quick updates.
    *   Use the CachyOS mirrorlist updater: `sudo cachyos-rate-mirrors`
*   **Kernel Choice:** CachyOS provides heavily optimized kernels (`linux-cachyos`, `linux-cachyos-sched-ext`, etc.). Stick to the one that matches your hardware and workflow best, and keep an LTS kernel (`linux-lts`) installed as a fallback in your bootloader.

## 8. General Health Checks
*   **Failed Services:** Check if any background services are failing to start.
    *   `systemctl --failed`
*   **High Priority Errors:** Check the journal for recent errors.
    *   `journalctl -p 3 -xb` (Shows errors from the current boot)

## Summary Routine
*   **Weekly:** Update system (`pacman -Syu`), check for orphans.
*   **Monthly:** Clean package cache, clear journal logs, check for `.pacnew` files.
*   **Bi-Annually:** Run BTRFS scrub (if applicable), review installed applications.
