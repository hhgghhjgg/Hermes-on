#!/bin/bash
set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "=========================================="

# Git Configuration
git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"
git config --global init.defaultBranch main
git config --global pull.rebase false

# Directory Setup
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"
echo "[ENTRYPOINT] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"

# Git Initialization & Remote Setup
cd "$HERMES_DIR"

if [ ! -d ".git" ]; then
    echo "[ENTRYPOINT] Initializing new git repo..."
    git init -b main
fi

# Function to get file size (portable)
get_file_size() {
    if [ -f "$1" ]; then
        stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to restore state.db from largest backup
restore_state_db() {
    echo "[ENTRYPOINT] Checking state.db integrity..."
    
    CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
    echo "[ENTRYPOINT] Current state.db size: $CURRENT_SIZE bytes"
    
    # Find largest backup file
    LARGEST_BACKUP=""
    LARGEST_SIZE=0
    
    for backup in "$HERMES_DIR"/state.db.bak.* ; do
        if [ -f "$backup" ]; then
            BACKUP_SIZE=$(get_file_size "$backup")
            if [ "$BACKUP_SIZE" -gt "$LARGEST_SIZE" ]; then
                LARGEST_SIZE=$BACKUP_SIZE
                LARGEST_BACKUP=$backup
            fi
        fi
    done
    
    # Decision: restore or keep?
    if [ -n "$LARGEST_BACKUP" ] && [ "$LARGEST_SIZE" -gt "$CURRENT_SIZE" ]; then
        echo "[ENTRYPOINT] 🎯 Found better backup: $LARGEST_BACKUP ($LARGEST_SIZE bytes)"
        echo "[ENTRYPOINT] Restoring state.db from backup..."
        
        # Backup current (just in case)
        if [ -f "$HERMES_DIR/state.db" ]; then
            cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-restore.$(date +%s)" 2>/dev/null || true
        fi
        
        # Restore from largest backup
        cp "$LARGEST_BACKUP" "$HERMES_DIR/state.db"
        echo "[ENTRYPOINT] ✅ state.db restored successfully!"
        
    elif [ "$CURRENT_SIZE" -lt 1000 ]; then
        echo "[ENTRYPOINT] ⚠️ state.db is too small but no backup available"
    else
        echo "[ENTRYPOINT] ✅ state.db looks good ($CURRENT_SIZE bytes)"
    fi
}

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
    
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
    fi
    
    # Fetch and Restore from GitHub
    echo "[ENTRYPOINT] =========================================="
    echo "[ENTRYPOINT] Fetching data from GitHub..."
    echo "[ENTRYPOINT] =========================================="
    
    if git fetch origin 2>&1; then
        echo "[ENTRYPOINT] ✅ Fetch successful"
        
        if git rev-parse --verify origin/main >/dev/null 2>&1; then
            echo "[ENTRYPOINT] origin/main found - restoring data..."
            
            # Save current state.db before reset (in case it has new data)
            if [ -f "$HERMES_DIR/state.db" ]; then
                CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
                if [ "$CURRENT_SIZE" -gt 1000 ]; then
                    cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-reset.$(date +%s)"
                    echo "[ENTRYPOINT] Saved current state.db as backup"
                fi
            fi
            
            # Force reset to remote state
            git reset --hard origin/main 2>&1 || true
            git clean -fd -e "state.db*" -e "*.pre-*" 2>&1 || true
            
            echo "[ENTRYPOINT] ✅ Data restored from GitHub!"
            echo "[ENTRYPOINT] Current commit: $(git rev-parse --short HEAD)"
            
        else
            echo "[ENTRYPOINT] ⚠️ No remote branch - starting fresh"
            cat > .gitignore <<'EOF'
*.key
*.pem
.env
__pycache__/
*.pyc
*.pyo
*.tmp
*.log
node_modules/
.DS_Store
EOF
            touch .keep
            git add -A
            git commit -m "Initial commit" 2>/dev/null || true
            git branch -M main
            git push -u origin main 2>&1 || true
        fi
    else
        echo "[ENTRYPOINT] ⚠️ Fetch failed - using local data"
    fi
    
    # 🔥 KEY STEP: Restore state.db from best backup
    restore_state_db
    
else
    echo "[ENTRYPOINT] ❌ GITHUB_TOKEN or GITHUB_REPO NOT SET!"
fi

# Create .gitignore if missing
if [ ! -f ".gitignore" ]; then
    cat > .gitignore <<'EOF'
*.key
*.pem
.env
__pycache__/
*.pyc
*.pyo
*.tmp
*.log
node_modules/
.DS_Store
state.db-journal
state.db-wal
EOF
    echo "[ENTRYPOINT] .gitignore created"
fi

# Verify state.db
if [ -f "$HERMES_DIR/state.db" ]; then
    FINAL_SIZE=$(get_file_size "$HERMES_DIR/state.db")
    echo "[ENTRYPOINT] Final state.db size: $FINAL_SIZE bytes"
    if [ "$FINAL_SIZE" -gt 1000 ]; then
        echo "[ENTRYPOINT] ✅ state.db is healthy"
    else
        echo "[ENTRYPOINT] ⚠️ state.db is small - may not have chats"
    fi
fi

# Start Background Sync
echo "=========================================="
echo "[ENTRYPOINT] Starting sync.sh in background..."
echo "=========================================="

/app/sync.sh 2>&1 &
SYNC_PID=$!
echo "[ENTRYPOINT] Sync PID: $SYNC_PID"

sleep 2
if kill -0 $SYNC_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ sync.sh is running"
else
    echo "[ENTRYPOINT] ❌ sync.sh FAILED to start!"
fi

# Set Environment Variables
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"

echo "[ENTRYPOINT] HERMES_HOME: $HERMES_HOME"
echo "[ENTRYPOINT] HERMES_WEBUI_STATE_DIR: $HERMES_WEBUI_STATE_DIR"
echo "[ENTRYPOINT] HERMES_WEBUI_HOST: $HERMES_WEBUI_HOST"
echo "[ENTRYPOINT] HERMES_WEBUI_PORT: $HERMES_WEBUI_PORT"

# Graceful Shutdown Handler
cleanup() {
    echo ""
    echo "=========================================="
    echo "[ENTRYPOINT] Shutting down - forcing final sync..."
    echo "=========================================="
    
    kill $SYNC_PID 2>/dev/null || true
    wait $SYNC_PID 2>/dev/null || true
    
    cd "$HERMES_DIR"
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        echo "[ENTRYPOINT] Committing final changes..."
        git add -A
        git commit -m "sync: final shutdown @ $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null || true
        echo "[ENTRYPOINT] Force pushing to GitHub..."
        git push --force origin main 2>&1 || true
        echo "[ENTRYPOINT] ✅ Final sync completed"
    else
        echo "[ENTRYPOINT] No changes to sync"
    fi
    
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# Start Hermes WebUI
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

cd /app/hermes-webui
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request"
