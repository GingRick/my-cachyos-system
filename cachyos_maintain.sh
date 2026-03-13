#!/bin/bash

# CachyOS Maintenance Automator
# This script tracks the last time maintenance tasks were run
# and only executes them if they are due based on the recommended schedule.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/cachyos_maintenance.state"

# Ensure state directory exists
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# Load previous state (timestamps)
source "$STATE_FILE" 2>/dev/null

CURRENT_TIME=$(date +%s)
DAY_IN_SEC=$((24 * 60 * 60))

# Defaults if not set (0 means it will run immediately the first time)
LAST_WEEKLY=${LAST_WEEKLY:-0}
LAST_MONTHLY=${LAST_MONTHLY:-0}
LAST_BIANNUAL=${LAST_BIANNUAL:-0}

save_state() {
    echo "LAST_WEEKLY=$LAST_WEEKLY" > "$STATE_FILE"
    echo "LAST_MONTHLY=$LAST_MONTHLY" >> "$STATE_FILE"
    echo "LAST_BIANNUAL=$LAST_BIANNUAL" >> "$STATE_FILE"
}

echo "Starting CachyOS Maintenance Check..."
echo "State file: $STATE_FILE"
echo ""

# --- PRE-MAINTENANCE SNAPSHOT BACKUP ---
echo "========================================="
echo " Creating Snapshot Backup for Git..."
echo "========================================="

# Get the latest pre/post/timeline snapshot (excluding the very current state if possible)
# 'snapper ls' outputs columns: # | Type | Pre # | Date | User | Cleanup | Description | Userdata
LATEST_SNAP=$(sudo snapper ls | grep -E 'single|pre|post' | tail -n 1 | awk '{print $1}')

if [ -z "$LATEST_SNAP" ]; then
    echo "⚠️  No suitable snapper snapshots found to backup."
else
    SNAP_DIR="/.snapshots/$LATEST_SNAP/snapshot"
    # We must use sudo to check if the directory exists because /.snapshots is restricted to root
    if ! sudo test -d "$SNAP_DIR"; then
         echo "⚠️  Snapshot directory $SNAP_DIR not found. Skipping backup."
    else
         echo "Found latest snapshot: #$LATEST_SNAP"
         
         # Determine repo path relative to this script
         REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
         BACKUP_ARCHIVE="$REPO_DIR/backups/snapshot_backup.tar.zst"
         SNAPSHOT_INFO="$REPO_DIR/backups/snapshot_info.txt"

         echo "Generating snapshot details..."
         # Generate info using host tools pointing to the snapshot DB to avoid chroot read-only and missing mount errors
         sudo bash -c "
            echo '--- Snapshot $LATEST_SNAP Details ---' > '$SNAPSHOT_INFO'
            echo 'Date: \$(date)' >> '$SNAPSHOT_INFO'
            echo 'Kernel: \$(uname -r)' >> '$SNAPSHOT_INFO'
            echo 'Installed Packages Count: \$(pacman -Qq -b \"$SNAP_DIR/var/lib/pacman\" 2>/dev/null | wc -l)' >> '$SNAPSHOT_INFO'
         "
         sudo chown "$USER:$USER" "$SNAPSHOT_INFO"
         
         # Note: A full root filesystem tarball will be HUGE (often 10-30GB+ compressed). 
         # GitHub has a strict 100MB file limit per file, and a soft ~1GB repo limit.
         # Pushing a full root backup to a standard git repo will fail.
         # We will create an informational backup of /etc and /var/lib/pacman/local (installed package list)
         # which is highly useful for restoration and fits comfortably in git.
         
         echo "Creating compressed archive of critical system state (/etc, pacman db)..."
         # We omit root/.config because it might not exist and causes tar to fail
         sudo tar -I "zstd -1" -cpf "$BACKUP_ARCHIVE" -C "$SNAP_DIR" etc var/lib/pacman/local
         sudo chown "$USER:$USER" "$BACKUP_ARCHIVE"
         
         echo "Committing and pushing to Git..."
         cd "$REPO_DIR" || exit 1
         git add backups/snapshot_backup.tar.zst backups/snapshot_info.txt
         
         # Only commit if there are changes
         if git diff --staged --quiet; then
             echo "No changes in snapshot state to commit."
         else
             git commit -m "chore(backup): System state snapshot #$LATEST_SNAP

$(cat backups/snapshot_info.txt | head -n 4)"
             git push
             echo "✅ Snapshot backup pushed to repository."
         fi
    fi
fi
echo ""

# --- WEEKLY TASKS (Every 7 days) ---
if (( CURRENT_TIME - LAST_WEEKLY > 7 * DAY_IN_SEC )); then
    echo "========================================="
    echo " Running WEEKLY Maintenance Tasks..."
    echo "========================================="
    
    echo -e "\n[1/2] Updating System..."
    if command -v paru &> /dev/null; then
        paru -Syu
    elif command -v yay &> /dev/null; then
        yay -Syu
    else
        sudo pacman -Syu
    fi

    echo -e "\n[2/2] Checking for orphaned packages..."
    ORPHANS=$(pacman -Qtdq)
    if [ -n "$ORPHANS" ]; then
        echo "Found orphaned packages:"
        echo "$ORPHANS"
        read -p "Do you want to remove them? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo pacman -Rns $ORPHANS
        fi
    else
        echo "No orphaned packages found."
    fi

    LAST_WEEKLY=$CURRENT_TIME
    save_state
    echo -e "\n✅ Weekly tasks completed.\n"
else
    DAYS_LEFT=$(( 7 - (CURRENT_TIME - LAST_WEEKLY) / DAY_IN_SEC ))
    echo "✅ Weekly tasks are up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- MONTHLY TASKS (Every 30 days) ---
if (( CURRENT_TIME - LAST_MONTHLY > 30 * DAY_IN_SEC )); then
    echo "========================================="
    echo " Running MONTHLY Maintenance Tasks..."
    echo "========================================="
    
    echo -e "\n[1/3] Cleaning Package Cache..."
    if command -v paccache &> /dev/null; then
        sudo paccache -r
        sudo paccache -ruk0
    else
        echo "paccache not found. To automatically clean caches, please install pacman-contrib:"
        echo "sudo pacman -S pacman-contrib"
    fi
    
    if command -v paru &> /dev/null; then
        paru -Sc --noconfirm
    elif command -v yay &> /dev/null; then
        yay -Sc --noconfirm
    fi

    echo -e "\n[2/3] Vacuuming Journald Logs..."
    sudo journalctl --vacuum-time=2weeks

    echo -e "\n[3/3] Checking for .pacnew and .pacsave files..."
    PACNEW_FILES=$(sudo find /etc -type f -name "*.pacnew" -o -name "*.pacsave" 2>/dev/null)
    if [ -n "$PACNEW_FILES" ]; then
        echo -e "\n⚠️ Found unmerged configuration files:"
        echo "$PACNEW_FILES"
        read -p "Do you want to run pacdiff now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if command -v pacdiff &> /dev/null; then
                sudo pacdiff
            else
                echo "pacdiff not found. Please install pacman-contrib."
            fi
        fi
    else
        echo "No .pacnew or .pacsave files found."
    fi

    LAST_MONTHLY=$CURRENT_TIME
    save_state
    echo -e "\n✅ Monthly tasks completed.\n"
else
    DAYS_LEFT=$(( 30 - (CURRENT_TIME - LAST_MONTHLY) / DAY_IN_SEC ))
    echo "✅ Monthly tasks are up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- BI-ANNUAL TASKS (Every 180 days) ---
if (( CURRENT_TIME - LAST_BIANNUAL > 180 * DAY_IN_SEC )); then
    echo "========================================="
    echo " Running BI-ANNUAL Maintenance Tasks..."
    echo "========================================="

    echo -e "\n[1/2] Updating CachyOS Mirrors..."
    if command -v cachyos-rate-mirrors &> /dev/null; then
        sudo cachyos-rate-mirrors
    else
        echo "cachyos-rate-mirrors not found, skipping..."
    fi

    echo -e "\n[2/2] Checking BTRFS filesystem for /..."
    FSTYPE=$(df -T / | awk 'NR==2 {print $2}')
    if [ "$FSTYPE" = "btrfs" ]; then
        echo "Starting BTRFS Scrub on /..."
        sudo btrfs scrub start /
        echo "You can check the status in the background with: sudo btrfs scrub status /"
    else
        echo "Root filesystem is not BTRFS ($FSTYPE). Skipping scrub."
    fi

    LAST_BIANNUAL=$CURRENT_TIME
    save_state
    echo -e "\n✅ Bi-Annual tasks completed.\n"
else
    DAYS_LEFT=$(( 180 - (CURRENT_TIME - LAST_BIANNUAL) / DAY_IN_SEC ))
    echo "✅ Bi-Annual tasks are up to date. (Next run in ~$DAYS_LEFT days)"
fi

echo "========================================="
echo "🎉 Maintenance Check Complete!"
echo "========================================="
