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
git config --global advice.detachedHead false

# ============================================================
# Directory Setup
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/workspace"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"

cd "$HERMES_DIR"
if [ ! -d ".git" ]; then
  git init -b main
fi

# ============================================================
# 🔥 RESTORE FROM GITHUB (این بخش حیاتی است!)
# ============================================================
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL"
  else
    git remote add origin "$REMOTE_URL"
  fi

  echo "[ENTRYPOINT] Fetching ALL data from GitHub..."
  if git fetch origin 2>&1; then
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      echo "[ENTRYPOINT] Restoring from origin/main..."
      git reset --hard origin/main 2>&1 || true
      git clean -fd -e "state.db*" -e "config.yaml" 2>&1 || true
      echo "[ENTRYPOINT] ✅ ALL DATA RESTORED from GitHub!"
      echo "[ENTRYPOINT] Current commit: $(git rev-parse --short HEAD)"
    else
      echo "[ENTRYPOINT] ⚠️ No remote branch"
    fi
  else
    echo "[ENTRYPOINT] ⚠️ Fetch failed"
  fi
else
  echo "[ENTRYPOINT] ❌ GITHUB_TOKEN or GITHUB_REPO NOT SET!"
fi

# ============================================================
# Create .gitignore if missing
# ============================================================
if [ ! -f ".gitignore" ]; then
  cat > .gitignore <<'EOF'
*.key
*.pem
.env
.env.*
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
*.pre-reset.*
state.db.bak.*
EOF
fi

# ============================================================
# Start Background Sync
# ============================================================
if [ -f "/app/sync.sh" ]; then
  echo "[ENTRYPOINT] Starting sync.sh..."
  /app/sync.sh 2>&1 &
  SYNC_PID=$!
  sleep 2
  if kill -0 $SYNC_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ sync.sh running (PID: $SYNC_PID)"
  fi
fi

# ============================================================
# Start Qwen Proxy
# ============================================================
if [ -f "/app/qwen-proxy.py" ]; then
  echo "[ENTRYPOINT] Starting Qwen Proxy..."
  python3 /app/qwen-proxy.py 2>&1 &
  PROXY_PID=$!
  sleep 3
  if kill -0 $PROXY_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ Qwen Proxy running (PID: $PROXY_PID)"
  fi
fi

# ============================================================
# Start Modal Client
# ============================================================
if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
  if [ -f "/app/modal-client.py" ]; then
    echo "[ENTRYPOINT] Starting Modal Client..."
    python3 /app/modal-client.py 2>&1 &
    MODAL_PID=$!
    sleep 4
    if kill -0 $MODAL_PID 2>/dev/null; then
      echo "[ENTRYPOINT] ✅ Modal Client running (PID: $MODAL_PID)"
    fi
  fi
fi

# ============================================================
# Set Environment Variables
# ============================================================
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"
export HERMES_WORKSPACE="$HERMES_DIR/workspace"

# ============================================================
# Graceful Shutdown
# ============================================================
cleanup() {
  echo "[ENTRYPOINT] Shutting down - forcing final sync..."
  
  [ -n "$SYNC_PID" ] && kill $SYNC_PID 2>/dev/null || true
  [ -n "$PROXY_PID" ] && kill $PROXY_PID 2>/dev/null || true
  [ -n "$MODAL_PID" ] && kill $MODAL_PID 2>/dev/null || true

  cd "$HERMES_DIR"
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    echo "[ENTRYPOINT] Committing final changes..."
    git add -A
    git commit -m "sync: final shutdown @ $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null || true
    git push --force origin main 2>&1 || true
    echo "[ENTRYPOINT] ✅ Final sync completed"
  fi
  
  exit 0
}

trap cleanup SIGTERM SIGINT

# ============================================================
# Start WebUI
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

cd /app/webui || exit 1

if [ ! -f "server.py" ]; then
  echo "[ENTRYPOINT] ❌ server.py not found!"
  exit 1
fi

exec python server.py 2>&1
