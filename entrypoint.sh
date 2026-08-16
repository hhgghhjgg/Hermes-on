#!/bin/bash

set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "[ENTRYPOINT] Minimal mode - no auto-config, no restore"
echo "=========================================="

# ============================================================
# Directory Setup (فقط ایجاد دایرکتوری‌های ضروری)
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/workspace"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"

# ============================================================
# Git Setup (فقط اگر token موجود باشد)
# ============================================================
git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

cd "$HERMES_DIR"
if [ ! -d ".git" ]; then
  git init -b main
fi

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$REMOTE_URL"
  else
    git remote set-url origin "$REMOTE_URL"
  fi
  echo "[ENTRYPOINT] Git remote configured"
fi

# ============================================================
# Start Background Sync (اختیاری)
# ============================================================
if [ -f "/app/sync.sh" ]; then
  echo "[ENTRYPOINT] Starting sync.sh in background..."
  /app/sync.sh 2>&1 &
  SYNC_PID=$!
  sleep 2
  if kill -0 $SYNC_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ sync.sh is running (PID: $SYNC_PID)"
  fi
fi

# ============================================================
# Start Qwen Proxy (اختیاری)
# ============================================================
if [ -f "/app/qwen-proxy.py" ]; then
  echo "[ENTRYPOINT] Starting Qwen Proxy..."
  python3 /app/qwen-proxy.py 2>&1 &
  PROXY_PID=$!
  sleep 3
  if kill -0 $PROXY_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ Qwen Proxy running on port 8080 (PID: $PROXY_PID)"
  fi
fi

# ============================================================
# Start Modal Client (فقط اگر credentials موجود باشد)
# ============================================================
if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
  if [ -f "/app/modal-client.py" ]; then
    echo "[ENTRYPOINT] Starting Modal Client..."
    python3 /app/modal-client.py 2>&1 &
    MODAL_PID=$!
    sleep 4
    if kill -0 $MODAL_PID 2>/dev/null; then
      echo "[ENTRYPOINT] ✅ Modal Client running on port 8090 (PID: $MODAL_PID)"
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
  echo "[ENTRYPOINT] Shutting down..."
  [ -n "$SYNC_PID" ] && kill $SYNC_PID 2>/dev/null || true
  [ -n "$PROXY_PID" ] && kill $PROXY_PID 2>/dev/null || true
  [ -n "$MODAL_PID" ] && kill $MODAL_PID 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

# ============================================================
# Start WebUI (اصلی‌ترین بخش)
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
