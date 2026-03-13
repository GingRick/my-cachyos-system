#!/bin/bash

# CachyOS Maintenance Automator
# This script tracks the last time individual maintenance tasks were run
# and only executes them if they are due based on the recommended schedule.

# Determine repo path relative to this script
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

STATE_DIR="$REPO_DIR/.state"
STATE_FILE="$STATE_DIR/cachyos_maintenance.state"

# Ensure state directory exists
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# Load previous state (timestamps)
source "$STATE_FILE" 2>/dev/null

CURRENT_TIME=$(date +%s)
DAY_IN_SEC=$((24 * 60 * 60))

# Defaults if not set (0 means it will run immediately the first time)
LAST_SYSTEM_UPDATE=${LAST_SYSTEM_UPDATE:-0}
LAST_ORPHAN_CLEAN=${LAST_ORPHAN_CLEAN:-0}
LAST_CACHE_CLEAN=${LAST_CACHE_CLEAN:-0}
LAST_JOURNAL_CLEAN=${LAST_JOURNAL_CLEAN:-0}
LAST_PACNEW_MERGE=${LAST_PACNEW_MERGE:-0}
LAST_MIRROR_UPDATE=${LAST_MIRROR_UPDATE:-0}
LAST_BTRFS_SCRUB=${LAST_BTRFS_SCRUB:-0}

# Parse flags
FORCE_MODE=false
if [[ "$1" == "--force" ]]; then
    FORCE_MODE=true
    echo "⚠️  FORCE MODE ACTIVE: Bypassing time checks and running all tasks."
fi

save_state() {
    echo "LAST_SYSTEM_UPDATE=$LAST_SYSTEM_UPDATE" > "$STATE_FILE"
    echo "LAST_ORPHAN_CLEAN=$LAST_ORPHAN_CLEAN" >> "$STATE_FILE"
    echo "LAST_CACHE_CLEAN=$LAST_CACHE_CLEAN" >> "$STATE_FILE"
    echo "LAST_JOURNAL_CLEAN=$LAST_JOURNAL_CLEAN" >> "$STATE_FILE"
    echo "LAST_PACNEW_MERGE=$LAST_PACNEW_MERGE" >> "$STATE_FILE"
    echo "LAST_MIRROR_UPDATE=$LAST_MIRROR_UPDATE" >> "$STATE_FILE"
    echo "LAST_BTRFS_SCRUB=$LAST_BTRFS_SCRUB" >> "$STATE_FILE"
    
    # Auto-commit state file to git if running inside the repo
    cd "$REPO_DIR" || return
    if ! git diff --quiet "$STATE_FILE"; then
        git add "$STATE_FILE"
        git commit -m "chore(state): update maintenance timestamps" > /dev/null 2>&1
        git push > /dev/null 2>&1
        echo "✅ State successfully synced to remote repository."
    fi
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
         
         BACKUP_ARCHIVE="$REPO_DIR/backups/snapshot_backup.tar.zst"
         SNAPSHOT_INFO="$REPO_DIR/backups/snapshot_info.txt"

         echo "Generating snapshot details..."
         # Generate info using host tools pointing to the snapshot DB to avoid chroot read-only and missing mount errors
         # We must NOT use quotes around EOF so that command substitution happens during the creation of the file
         sudo bash -c "cat << EOF > '$SNAPSHOT_INFO'
--- Snapshot $LATEST_SNAP Details ---
Date: \$(date)
Kernel: \$(uname -r)
Installed Packages Count: \$(pacman -Qq -b \"$SNAP_DIR/var/lib/pacman\" 2>/dev/null | wc -l)
EOF"
         sudo chown "$USER:$USER" "$SNAPSHOT_INFO"
         
         echo "Creating compressed archive of critical system state (/etc, pacman db)..."
         # We omit root/.config because it might not exist and causes tar to fail
         sudo tar -I "zstd -1" -cpf "$BACKUP_ARCHIVE" -C "$SNAP_DIR" etc var/lib/pacman/local
         sudo chown "$USER:$USER" "$BACKUP_ARCHIVE"
         
         echo "Committing and pushing backup to Git..."
         cd "$REPO_DIR" || exit 1
         git add backups/snapshot_backup.tar.zst backups/snapshot_info.txt
         
         # Only commit if there are changes
         if git diff --staged --quiet; then
             echo "No changes in snapshot state to commit."
         else
             git commit -m "chore(backup): System state snapshot #$LATEST_SNAP

$(cat backups/snapshot_info.txt | head -n 4)" > /dev/null 2>&1
             git push > /dev/null 2>&1
             echo "✅ Snapshot backup pushed to repository."
         fi
    fi
fi
echo ""

echo "========================================="
echo " Maintenance Tasks"
echo "========================================="

STATE_CHANGED=false

# --- 1. SYSTEM UPDATE (Weekly) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_SYSTEM_UPDATE > 7 * DAY_IN_SEC )); then
    echo -e "\n[Task] Updating System..."
    if command -v paru &> /dev/null; then
        paru -Syu
    elif command -v yay &> /dev/null; then
        yay -Syu
    else
        sudo pacman -Syu
    fi
    # Only mark as done if the command succeeded
    if [ $? -eq 0 ]; then
        LAST_SYSTEM_UPDATE=$CURRENT_TIME
        STATE_CHANGED=true
        echo "✅ System Update complete."
    fi
else
    DAYS_LEFT=$(( 7 - (CURRENT_TIME - LAST_SYSTEM_UPDATE) / DAY_IN_SEC ))
    echo "⏭️ System Update is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 2. ORPHAN CLEANUP (Weekly) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_ORPHAN_CLEAN > 7 * DAY_IN_SEC )); then
    echo -e "\n[Task] Checking for orphaned packages..."
    ORPHANS=$(pacman -Qtdq)
    if [ -n "$ORPHANS" ]; then
        echo "Found orphaned packages:"
        echo "$ORPHANS"
        read -p "Do you want to remove them? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo pacman -Rns $ORPHANS
            if [ $? -eq 0 ]; then
                LAST_ORPHAN_CLEAN=$CURRENT_TIME
                STATE_CHANGED=true
                echo "✅ Orphans removed."
            fi
        else
            echo "⏸️ Skipping orphan removal (task remains pending)."
        fi
    else
        echo "✅ No orphaned packages found."
        LAST_ORPHAN_CLEAN=$CURRENT_TIME
        STATE_CHANGED=true
    fi
else
    DAYS_LEFT=$(( 7 - (CURRENT_TIME - LAST_ORPHAN_CLEAN) / DAY_IN_SEC ))
    echo "⏭️ Orphan Cleanup is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 3. CACHE CLEANUP (Monthly) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_CACHE_CLEAN > 30 * DAY_IN_SEC )); then
    echo -e "\n[Task] Cleaning Package Cache..."
    
    # Prompt the user for this action as it deletes files
    read -p "Do you want to clean pacman and AUR caches? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v paccache &> /dev/null; then
            sudo paccache -r
            sudo paccache -ruk0
        else
            echo "paccache not found. Please install pacman-contrib."
        fi
        
        if command -v paru &> /dev/null; then
            paru -Sc --noconfirm
        elif command -v yay &> /dev/null; then
            yay -Sc --noconfirm
        fi
        
        LAST_CACHE_CLEAN=$CURRENT_TIME
        STATE_CHANGED=true
        echo "✅ Cache cleaned."
    else
        echo "⏸️ Skipping cache cleanup (task remains pending)."
    fi
else
    DAYS_LEFT=$(( 30 - (CURRENT_TIME - LAST_CACHE_CLEAN) / DAY_IN_SEC ))
    echo "⏭️ Cache Cleanup is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 4. JOURNAL CLEANUP (Monthly) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_JOURNAL_CLEAN > 30 * DAY_IN_SEC )); then
    echo -e "\n[Task] Vacuuming Journald Logs..."
    sudo journalctl --vacuum-time=2weeks
    LAST_JOURNAL_CLEAN=$CURRENT_TIME
    STATE_CHANGED=true
    echo "✅ Journal logs vacuumed."
else
    DAYS_LEFT=$(( 30 - (CURRENT_TIME - LAST_JOURNAL_CLEAN) / DAY_IN_SEC ))
    echo "⏭️ Journal Cleanup is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 5. PACNEW MERGE (Monthly) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_PACNEW_MERGE > 30 * DAY_IN_SEC )); then
    echo -e "\n[Task] Checking for .pacnew and .pacsave files..."
    PACNEW_FILES=$(sudo find /etc -type f -name "*.pacnew" -o -name "*.pacsave" 2>/dev/null)
    if [ -n "$PACNEW_FILES" ]; then
        echo -e "\n⚠️ Found unmerged configuration files:"
        echo "$PACNEW_FILES"
        read -p "Do you want to run pacdiff now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if command -v pacdiff &> /dev/null; then
                sudo pacdiff
                # Assume if they ran pacdiff, they handled it
                LAST_PACNEW_MERGE=$CURRENT_TIME
                STATE_CHANGED=true
                echo "✅ Configs checked."
            else
                echo "pacdiff not found. Please install pacman-contrib."
            fi
        else
            echo "⏸️ Skipping pacnew merge (task remains pending)."
        fi
    else
        echo "✅ No .pacnew or .pacsave files found."
        LAST_PACNEW_MERGE=$CURRENT_TIME
        STATE_CHANGED=true
    fi
else
    DAYS_LEFT=$(( 30 - (CURRENT_TIME - LAST_PACNEW_MERGE) / DAY_IN_SEC ))
    echo "⏭️ Pacnew Merge is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 6. MIRROR UPDATE (Bi-Annual) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_MIRROR_UPDATE > 180 * DAY_IN_SEC )); then
    echo -e "\n[Task] Updating CachyOS Mirrors..."
    if command -v cachyos-rate-mirrors &> /dev/null; then
        sudo cachyos-rate-mirrors
        LAST_MIRROR_UPDATE=$CURRENT_TIME
        STATE_CHANGED=true
        echo "✅ Mirrors updated."
    else
        echo "cachyos-rate-mirrors not found, skipping..."
    fi
else
    DAYS_LEFT=$(( 180 - (CURRENT_TIME - LAST_MIRROR_UPDATE) / DAY_IN_SEC ))
    echo "⏭️ Mirror Update is up to date. (Next run in ~$DAYS_LEFT days)"
fi

# --- 7. BTRFS SCRUB (Bi-Annual) ---
if $FORCE_MODE || (( CURRENT_TIME - LAST_BTRFS_SCRUB > 180 * DAY_IN_SEC )); then
    echo -e "\n[Task] Checking BTRFS filesystem for /..."
    FSTYPE=$(df -T / | awk 'NR==2 {print $2}')
    if [ "$FSTYPE" = "btrfs" ]; then
        echo "Starting BTRFS Scrub on /..."
        sudo btrfs scrub start /
        echo "You can check the status in the background with: sudo btrfs scrub status /"
        LAST_BTRFS_SCRUB=$CURRENT_TIME
        STATE_CHANGED=true
        echo "✅ BTRFS Scrub started."
    else
        echo "Root filesystem is not BTRFS ($FSTYPE). Skipping scrub."
        # Mark as done so it doesn't keep checking non-btrfs systems
        LAST_BTRFS_SCRUB=$CURRENT_TIME
        STATE_CHANGED=true
    fi
else
    DAYS_LEFT=$(( 180 - (CURRENT_TIME - LAST_BTRFS_SCRUB) / DAY_IN_SEC ))
    echo "⏭️ BTRFS Scrub is up to date. (Next run in ~$DAYS_LEFT days)"
fi

if $STATE_CHANGED; then
    save_state
fi

echo -e "\n========================================="
echo "🎉 Maintenance Check Complete!"
echo "========================================="
