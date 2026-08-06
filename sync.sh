#!/bin/bash

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
SYNC_INTERVAL="${SYNC_INTERVAL:-180}"  # Default: 3 minutes

echo "Sync script started. Interval: ${SYNC_INTERVAL}s"

cd "$HERMES_DIR"

while true; do
    sleep "$SYNC_INTERVAL"
    
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        # Check if there are changes
        if [[ -n $(git status --porcelain) ]]; then
            echo "[$(date)] Changes detected. Committing and pushing..."
            git add -A
            git commit -m "Auto-sync: $(date '+%Y-%m-%d %H:%M:%S')"
            git push origin main
            echo "[$(date)] Sync completed."
        else
            echo "[$(date)] No changes to sync."
        fi
    else
        echo "[$(date)] GITHUB_TOKEN or GITHUB_REPO not set. Skipping sync."
        sleep 300
    fi
done
