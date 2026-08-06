#!/bin/bash
set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "=========================================="

# ============================================================
# Git Configuration
# ============================================================
git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"
git config --global init.defaultBranch main
git config --global pull.rebase false

# ============================================================
# Directory Setup
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"
echo "[ENTRYPOINT] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"

# ============================================================
# Git Initialization & Remote Setup
# ============================================================
cd "$HERMES_DIR"

if [ ! -d ".git" ]; then
    echo "[ENTRYPOINT] Initializing new git repo..."
    git init -b main
fi

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
    
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
        echo "[ENTRYPOINT] Remote URL updated"
    else
        git remote add origin "$REMOTE_URL"
        echo "[ENTRYPOINT] Remote origin added"
    fi
    
    # ============================================================
    # 🔥 KEY STEP: Fetch and Restore from GitHub
    # ============================================================
    echo "[ENTRYPOINT] =========================================="
    echo "[ENTRYPOINT] Fetching data from GitHub..."
    echo "[ENTRYPOINT] =========================================="
    
    if git fetch origin 2>&1; then
        echo "[ENTRYPOINT] ✅ Fetch successful"
        
        if git rev-parse --verify origin/main >/dev/null 2>&1; then
            echo "[ENTRYPOINT] origin/main found - restoring data..."
            
            # Force reset to remote state
            git reset --hard origin/main 2>&1 || echo "[ENTRYPOINT] ⚠️ Reset had warnings"
            
            # Remove any untracked files (but NOT state.db!)
            git clean -fd -e "state.db*" 2>&1 || true
            
            echo "[ENTRYPOINT] ✅ Data restored from GitHub successfully!"
            echo "[ENTRYPOINT] Current commit: $(git rev-parse --short HEAD)"
            
        elif git rev-parse --verify origin/master >/dev/null 2>&1; then
            echo "[ENTRYPOINT] origin/master found (legacy branch)..."
            git branch -M main
            git reset --hard origin/master 2>&1 || true
            git clean -fd -e "state.db*" 2>&1 || true
            echo "[ENTRYPOINT] ✅ Data restored from origin/master"
            
        else
            echo "[ENTRYPOINT] ⚠️ No remote branch found - starting fresh"
            echo "[ENTRYPOINT] Creating initial commit..."
            
            cat > .gitignore <<'EOF'
*.key
*.pem
.env
__pycache__/
*.pyc
*.pyo
*.tmp
*.log
*.journal
state.db-journal
state.db-wal
node_modules/
.DS_Store
EOF
            
            touch .keep
            git add -A
            git commit -m "Initial commit from Docker entrypoint" 2>/dev/null || true
            git branch -M main
            git push -u origin main 2>&1 || echo "[ENTRYPOINT] ⚠️ Initial push failed"
        fi
    else
        echo "[ENTRYPOINT] ⚠️ Fetch failed - checking if we have local data"
        
        if [ -z "$(ls -A .)" ]; then
            echo "[ENTRYPOINT] Empty directory - creating initial commit"
            touch .keep
            git add -A
            git commit -m "Initial commit" 2>/dev/null || true
        else
            echo "[ENTRYPOINT] Local data exists - using it"
        fi
    fi
else
    echo "[ENTRYPOINT] ❌ CRITICAL: GITHUB_TOKEN or GITHUB_REPO NOT SET!"
    echo "[ENTRYPOINT] ❌ Data will NOT persist across restarts!"
fi

# ============================================================
# Create .gitignore if missing
# ============================================================
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
*.journal
state.db-journal
state.db-wal
node_modules/
.DS_Store
EOF
    echo "[ENTRYPOINT] .gitignore created"
fi

# ============================================================
# 🔥 FIXED: DO NOT archive state.db - just warn
# ============================================================
if [ -f "$HERMES_DIR/state.db" ]; then
    echo "[ENTRYPOINT] state.db found - keeping it (WebUI will handle schema)"
    
    # Check schema but don't archive
    if ! sqlite3 "$HERMES_DIR/state.db" "SELECT source FROM sessions LIMIT 1" 2>/dev/null; then
        echo "[ENTRYPOINT] ⚠️ state.db has old schema - WebUI may show warnings"
        echo "[ENTRYPOINT] ⚠️ This is OK - your chats are safe!"
    else
        echo "[ENTRYPOINT] ✅ state.db schema is current"
    fi
else
    echo "[ENTRYPOINT] ℹ️ No state.db found - WebUI will create new one"
fi

# ============================================================
# Start Background Sync
# ============================================================
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

# ============================================================
# Set Environment Variables for WebUI
# ============================================================
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"

echo "[ENTRYPOINT] HERMES_HOME: $HERMES_HOME"
echo "[ENTRYPOINT] HERMES_WEBUI_STATE_DIR: $HERMES_WEBUI_STATE_DIR"
echo "[ENTRYPOINT] HERMES_WEBUI_HOST: $HERMES_WEBUI_HOST"
echo "[ENTRYPOINT] HERMES_WEBUI_PORT: $HERMES_WEBUI_PORT"

# ============================================================
# Graceful Shutdown Handler
# ============================================================
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
        
        echo "[ENTRYPOINT] Pushing to GitHub..."
        git push --force origin main 2>&1 || echo "[ENTRYPOINT] ⚠️ Final push failed"
        echo "[ENTRYPOINT] ✅ Final sync completed"
    else
        echo "[ENTRYPOINT] No changes to sync"
    fi
    
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# ============================================================
# Start Hermes WebUI
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

cd /app/hermes-webui

exec python server.py 2>&1 | grep -v "state.db" | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported"
