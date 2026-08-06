#!/bin/bash

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
SYNC_INTERVAL="${SYNC_INTERVAL:-30}"

# 🔥 لاگ به stdout (نه فایل) تا در Render Logs دیده شود
echo "=========================================="
echo "[SYNC] Started at $(date)"
echo "[SYNC] Interval: ${SYNC_INTERVAL}s"
echo "[SYNC] GitHub Repo: ${GITHUB_REPO:-NOT SET}"
echo "[SYNC] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"
echo "=========================================="

cd "$HERMES_DIR" || { echo "[SYNC] ERROR: Cannot cd to $HERMES_DIR"; exit 1; }

counter=0
while true; do
    sleep "$SYNC_INTERVAL"
    counter=$((counter + 1))
    
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            echo "[SYNC #$counter] Changes detected. Committing..."
            git add -A
            git commit -m "sync #$counter @ $(date '+%H:%M:%S')" >/dev/null 2>&1
            
            if timeout 60 git push origin main >/dev/null 2>&1; then
                echo "[SYNC #$counter] ✅ Pushed to GitHub"
            else
                echo "[SYNC #$counter] ❌ Push FAILED"
            fi
        else
            echo "[SYNC #$counter] ✓ No changes"
        fi
    else
        echo "[SYNC #$counter] ⚠️ GITHUB_TOKEN or GITHUB_REPO missing!"
        sleep 60
    fi
done
