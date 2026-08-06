#!/bin/bash

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
SYNC_INTERVAL="${SYNC_INTERVAL:-30}"
MAX_BACKUPS=3  # حداکثر 3 بکاپ نگه می‌دارد

echo "=========================================="
echo "[SYNC] Started at $(date)"
echo "[SYNC] Interval: ${SYNC_INTERVAL}s"
echo "[SYNC] GitHub Repo: ${GITHUB_REPO:-NOT SET}"
echo "[SYNC] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"
echo "=========================================="

cd "$HERMES_DIR" || exit 1

counter=0
while true; do
    sleep "$SYNC_INTERVAL"
    counter=$((counter + 1))
    
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            echo "[SYNC #$counter] Changes detected. Committing..."
            
            # Cleanup old backups (keep only MAX_BACKUPS)
            BACKUP_COUNT=$(ls -1 state.db.bak.* 2>/dev/null | wc -l)
            if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
                echo "[SYNC #$counter] Cleaning up old backups (keeping $MAX_BACKUPS)..."
                ls -1t state.db.bak.* | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
            fi
            
            git add -A
            git commit -m "sync #$counter @ $(date '+%H:%M:%S')" >/dev/null 2>&1
            
            echo "[SYNC #$counter] Force pushing to ${GITHUB_REPO}..."
            PUSH_OUTPUT=$(git push --force origin main 2>&1)
            PUSH_STATUS=$?
            
            if [ $PUSH_STATUS -eq 0 ]; then
                echo "[SYNC #$counter] ✅ Force pushed to GitHub"
            else
                echo "[SYNC #$counter] ❌ Push FAILED (code: $PUSH_STATUS)"
                echo "[SYNC #$counter] === ERROR DETAILS ==="
                echo "$PUSH_OUTPUT"
                echo "======================="
            fi
        else
            echo "[SYNC #$counter] ✓ No changes"
        fi
    else
        echo "[SYNC #$counter] ⚠️ Token or Repo missing!"
    fi
done
