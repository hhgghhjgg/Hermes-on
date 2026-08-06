#!/bin/bash

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
SYNC_INTERVAL="${SYNC_INTERVAL:-30}"
MAX_BACKUPS=3

echo "=========================================="
echo "[SYNC] Started at $(date)"
echo "[SYNC] Interval: ${SYNC_INTERVAL}s"
echo "[SYNC] GitHub Repo: ${GITHUB_REPO:-NOT SET}"
echo "[SYNC] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"
echo "[SYNC] Scope: ALL Hermes data"
echo "[SYNC]   - state.db (chats)"
echo "[SYNC]   - webui/ (sessions, settings)"
echo "[SYNC]   - skills/ (all 200+ skills)"
echo "[SYNC]   - workspace/ (your projects)"
echo "[SYNC]   - MEMORY.md, USER.md, SOUL.md"
echo "[SYNC]   - config.yaml"
echo "[SYNC]   - profiles/"
echo "[SYNC]   - crons/"
echo "[SYNC]   - plans/"
echo "[SYNC]   - Everything else in /data/.hermes/"
echo "=========================================="

cd "$HERMES_DIR" || exit 1

counter=0
while true; do
    sleep "$SYNC_INTERVAL"
    counter=$((counter + 1))
    
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            echo "[SYNC #$counter] 🔄 Changes detected. Committing ALL data..."
            
            # Cleanup old backups
            BACKUP_COUNT=$(ls -1 state.db.bak.* 2>/dev/null | wc -l)
            if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
                echo "[SYNC #$counter] Cleaning up old backups (keeping $MAX_BACKUPS)..."
                ls -1t state.db.bak.* | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
            fi
            
            # Add ALL changes
            git add -A
            
            # Count files
            FILES_COUNT=$(git status --porcelain 2>/dev/null | wc -l)
            
            git commit -m "sync #$counter @ $(date '+%H:%M:%S') - $FILES_COUNT files" >/dev/null 2>&1
            
            echo "[SYNC #$counter] Force pushing to ${GITHUB_REPO} ($FILES_COUNT files)..."
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
