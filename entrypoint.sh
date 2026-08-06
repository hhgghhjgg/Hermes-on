#!/bin/bash
set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "=========================================="

git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"
git config --global init.defaultBranch main

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui"
mkdir -p "$HERMES_DIR/skills"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"

cd "$HERMES_DIR"

# 🔥 استراتژی جدید: همیشه از remote شروع کن
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "[ENTRYPOINT] Setting up GitHub remote..."
    REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
    
    # اگر git repo وجود ندارد، init کن
    if [ ! -d ".git" ]; then
        echo "[ENTRYPOINT] Initializing new git repo..."
        git init
    fi
    
    # remote را تنظیم کن
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
    fi
    
    # 🔥 مرحله حیاتی: fetch و reset به remote
    echo "[ENTRYPOINT] Fetching from GitHub..."
    if git fetch origin main 2>&1; then
        echo "[ENTRYPOINT] ✅ Fetch successful"
        
        # بررسی کن آیا remote branch وجود دارد
        if git rev-parse origin/main >/dev/null 2>&1; then
            echo "[ENTRYPOINT] Resetting to origin/main..."
            # 🔥 force reset به remote (همه تغییرات local را از بین می‌برد)
            git reset --hard origin/main 2>&1 || echo "[ENTRYPOINT] ⚠️ Reset warning"
            git clean -fd 2>&1 || true
            echo "[ENTRYPOINT] ✅ Data restored from GitHub"
        else
            echo "[ENTRYPOINT] ⚠️ No remote data - starting fresh"
            touch .keep
            git add .
            git commit -m "Initial commit" 2>/dev/null || true
        fi
    else
        echo "[ENTRYPOINT] ⚠️ Fetch failed - starting fresh"
        if [ ! -d ".git" ]; then
            git init
        fi
        touch .keep
        git add .
        git commit -m "Initial commit" 2>/dev/null || true
    fi
else
    echo "[ENTRYPOINT] ❌ GITHUB_TOKEN or GITHUB_REPO NOT SET!"
    echo "[ENTRYPOINT] Data will NOT persist!"
    if [ ! -d ".git" ]; then
        git init
    fi
fi

# Cleanup incompatible state.db
if [ -f "$HERMES_DIR/state.db" ]; then
    if ! sqlite3 "$HERMES_DIR/state.db" "SELECT source FROM sessions LIMIT 1" 2>/dev/null; then
        mv "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.bak.$(date +%s)"
        echo "[ENTRYPOINT] Archived incompatible state.db"
    fi
fi

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

echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"

cleanup() {
    echo ""
    echo "[ENTRYPOINT] Shutting down - forcing final sync..."
    kill $SYNC_PID 2>/dev/null || true
    cd "$HERMES_DIR"
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        git add -A
        git commit -m "sync: shutdown" 2>/dev/null || true
        git push --force origin main 2>&1 || true
        echo "[ENTRYPOINT] ✅ Final sync done"
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

cd /app/hermes-webui
exec python server.py 2>&1 | grep -v "state.db" | grep -v "agent session listing skipped"
