#!/bin/bash
set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "=========================================="

# ============================================================
# Git Configuration (برای استفاده‌های احتمالی دیگه)
# ============================================================
git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global advice.detachedHead false

# ============================================================
# 🚫 DISABLE GITHUB SYNC
# Data is now managed by GitHub Release via the workflow.
# No git sync, no sync.sh, no git push.
# ============================================================
export GITHUB_SYNC_DISABLED=true
echo "[ENTRYPOINT] 🚫 GitHub sync DISABLED (using Release storage)"

# ============================================================
# Modal Configuration (اختیاری)
# ============================================================
echo "=========================================="
echo "[MODAL] Checking Modal credentials..."
echo "=========================================="

MODAL_CLIENT_ENABLED=false
MODAL_PID=""

if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
  echo "[MODAL] ✅ MODAL_TOKEN_ID: ${MODAL_TOKEN_ID:0:10}..."
  echo "[MODAL] ✅ MODAL_TOKEN_SECRET: set (${#MODAL_TOKEN_SECRET} chars)"
  echo "[MODAL] ✅ MODAL_ENVIRONMENT: ${MODAL_ENVIRONMENT:-main}"
  
  mkdir -p /root/.modal
  export MODAL_TOKEN_ID
  export MODAL_TOKEN_SECRET
  export MODAL_ENVIRONMENT="${MODAL_ENVIRONMENT:-main}"
  MODAL_CLIENT_ENABLED=true
else
  echo "[MODAL] ⚠️ Modal credentials not set!"
fi

echo "=========================================="

# ============================================================
# Directory Setup
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"
mkdir -p "$HERMES_DIR/workspace"
mkdir -p "$HERMES_DIR/profiles"
mkdir -p "$HERMES_DIR/crons"
mkdir -p "$HERMES_DIR/cache"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"

# ============================================================
# Portable file size function
# ============================================================
get_file_size() {
  if [ -f "$1" ]; then
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# ============================================================
# 📦 DATA PRE-LOADED BY WORKFLOW
# ============================================================
echo "=========================================="
echo "[DATA] Checking pre-loaded data..."
echo "=========================================="

if [ -f "$HERMES_DIR/config.yaml" ]; then
  echo "[DATA] ✅ Found pre-loaded config.yaml"
  echo "[DATA] ✅ Data was restored from GitHub Release by the workflow"
else
  echo "[DATA] ⚠️ No config.yaml found - starting fresh"
  echo "[DATA] ℹ️ A new config will be created by the CONFIG step"
fi

echo "=========================================="

# ============================================================
# 🔥 Override config.yaml with 9router
# ============================================================
echo "=========================================="
echo "[CONFIG] Overriding config.yaml with 9router..."
echo "=========================================="

python3 << 'CONFIG_OVERRIDE_SCRIPT'
import yaml
import os

config_path = '/data/.hermes/config.yaml'

# Load existing config (or create new)
if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f) or {}
    print(f"[CONFIG] ✅ Loaded existing config.yaml")
else:
    config = {}
    print(f"[CONFIG] ⚠️ No config.yaml, creating new")

# Override providers and model sections with 9router
config['providers'] = {
    '9router': {
        'base_url': 'https://9router-production-d138.up.railway.app/v1',
        'api_key': 'sk-d042a2942b66660e-wjdw1y-30603948'
    }
}

config['model'] = {
    'default': 'hermes-fast',
    'provider': 'custom:9router',
    'base_url': 'https://9router-production-d138.up.railway.app/v1',
    'api_key': 'sk-d042a2942b66660e-wjdw1y-30603948'
}

# Keep existing workspace, memory, user, soul if present
if 'workspace' not in config:
    config['workspace'] = '/data/.hermes/workspace'
if 'memory' not in config:
    config['memory'] = {
        'enabled': True,
        'path': '/data/.hermes/MEMORY.md'
    }
if 'user' not in config:
    config['user'] = {'profile_path': '/data/.hermes/USER.md'}
if 'soul' not in config:
    config['soul'] = {'path': '/data/.hermes/SOUL.md'}

# Save config
with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f"[CONFIG] ✅ config.yaml updated with 9router")
print(f"[CONFIG] ✅ Plugins/MCPs preserved (not touched)")
CONFIG_OVERRIDE_SCRIPT

echo "=========================================="

# ============================================================
# Final State Summary
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Final state summary:"
echo "=========================================="

if [ -f "$HERMES_DIR/state.db" ]; then
  FINAL_SIZE=$(get_file_size "$HERMES_DIR/state.db")
  echo "[ENTRYPOINT] state.db: $FINAL_SIZE bytes"
else
  echo "[ENTRYPOINT] state.db: not found (will be created)"
fi

SKILL_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Total skills: $SKILL_COUNT"

MEMORY_COUNT=$(ls "$HERMES_DIR"/MEMORY.md "$HERMES_DIR"/USER.md "$HERMES_DIR"/SOUL.md 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Core files (MEMORY/USER/SOUL): $MEMORY_COUNT"

WEBUI_FILES=$(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] WebUI files: $WEBUI_FILES"

WORKSPACE_FILES=$(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Workspace files: $WORKSPACE_FILES"

TOTAL_FILES=$(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Total files: $TOTAL_FILES"
echo "=========================================="

# ============================================================
# Start Modal Client API Server (if enabled)
# ============================================================
if [ "$MODAL_CLIENT_ENABLED" = true ]; then
  echo "=========================================="
  echo "[ENTRYPOINT] Starting Modal Client API..."
  echo "=========================================="

  python3 /app/modal-client.py 2>&1 &
  MODAL_PID=$!
  echo "[ENTRYPOINT] Modal Client PID: $MODAL_PID"

  sleep 4
  if kill -0 $MODAL_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ Modal Client is running on port 8090"
  else
    echo "[ENTRYPOINT] ❌ Modal Client FAILED to start!"
    MODAL_PID=""
  fi
  echo "=========================================="
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
export HERMES_WEBUI_DEFAULT_WORKSPACE="$HERMES_DIR/workspace"

export MODAL_CLIENT_URL="http://localhost:8090"

echo "[ENTRYPOINT] HERMES_HOME: $HERMES_HOME"
echo "[ENTRYPOINT] HERMES_WEBUI_HOST: $HERMES_WEBUI_HOST"
echo "[ENTRYPOINT] HERMES_WEBUI_PORT: $HERMES_WEBUI_PORT"

# ============================================================
# Graceful Shutdown Handler (simplified - no git sync)
# ============================================================
cleanup() {
  echo ""
  echo "=========================================="
  echo "[ENTRYPOINT] Shutting down..."
  echo "=========================================="

  if [ -n "$MODAL_PID" ]; then
    kill $MODAL_PID 2>/dev/null || true
    wait $MODAL_PID 2>/dev/null || true
  fi

  echo "[ENTRYPOINT] ✅ Cleanup completed"
  echo "[ENTRYPOINT] ℹ️ Data will be saved to Release by the workflow"
  exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# ============================================================
# Start WebUI
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

cd /app/webui || exit 1

if [ ! -f "server.py" ]; then
  echo "[ENTRYPOINT] ❌ server.py not found in /app/webui!"
  exit 1
fi

echo "[ENTRYPOINT] ✅ Found server.py in /app/webui"
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
