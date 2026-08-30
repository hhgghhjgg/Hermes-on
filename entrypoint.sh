#!/bin/bash

set -e

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
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
echo "[ENTRYPOINT] B2_BUCKET: ${B2_BUCKET_NAME:-NOT SET}"
echo "[ENTRYPOINT] B2_KEY_ID set: $([ -n "$B2_APPLICATION_KEY_ID" ] && echo YES || echo NO)"

# ============================================================
# Modal Configuration
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
# Install and Configure rclone for Backblaze B2
# ============================================================
echo "=========================================="
echo "[B2] Installing and configuring rclone..."
echo "=========================================="

# نصب rclone اگه نیست
if ! command -v rclone &> /dev/null; then
  echo "[B2] Installing rclone..."
  curl -s https://rclone.org/install.sh | bash
  echo "[B2] ✅ rclone installed: $(rclone --version | head -1)"
else
  echo "[B2] ✅ rclone already installed: $(rclone --version | head -1)"
fi

# پیکربندی rclone
if [ -n "$B2_APPLICATION_KEY_ID" ] && [ -n "$B2_APPLICATION_KEY" ]; then
  echo "[B2] Configuring rclone..."
  mkdir -p /root/.config/rclone
  
  cat > /root/.config/rclone/rclone.conf << EOF
[b2]
type = b2
account = ${B2_APPLICATION_KEY_ID}
key = ${B2_APPLICATION_KEY}
EOF
  
  chmod 600 /root/.config/rclone/rclone.conf
  echo "[B2] ✅ rclone configured for B2"
  
  # تست اتصال
  if rclone lsd "b2:${B2_BUCKET_NAME}" --max-depth 1 > /dev/null 2>&1; then
    echo "[B2] ✅ B2 connection successful"
    B2_ENABLED=true
  else
    echo "[B2] ⚠️ B2 connection failed - will start without backup"
    B2_ENABLED=false
  fi
else
  echo "[B2] ⚠️ B2 credentials not set - no backup will be performed"
  B2_ENABLED=false
fi

echo "=========================================="

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
# RESTORE from Backblaze B2
# ============================================================
echo "=========================================="
echo "[B2] Restoring data from Backblaze B2..."
echo "=========================================="

cd "$HERMES_DIR"

if [ "$B2_ENABLED" = true ]; then
  echo "[B2] Checking B2 bucket contents..."
  
  # بررسی اینکه آیا چیزی تو B2 هست
  B2_FILE_COUNT=$(rclone size "b2:${B2_BUCKET_NAME}" --json 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0")
  
  if [ "$B2_FILE_COUNT" -gt 0 ]; then
    echo "[B2] Found $B2_FILE_COUNT files in B2 bucket"
    
    # Backup state.db فعلی اگه وجود داره
    if [ -f "$HERMES_DIR/state.db" ]; then
      CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
      if [ "$CURRENT_SIZE" -gt 1000 ]; then
        BACKUP_FILE="$HERMES_DIR/state.db.pre-restore.$(date +%s)"
        cp "$HERMES_DIR/state.db" "$BACKUP_FILE" 2>/dev/null || true
        echo "[B2] Saved current state.db as backup: $BACKUP_FILE"
      fi
    fi
    
    # Restore از B2
    echo "[B2] Restoring from B2..."
    rclone sync "b2:${B2_BUCKET_NAME}" "$HERMES_DIR" \
      --transfers=4 \
      --checkers=8 \
      --exclude="*.tmp" \
      --exclude="*.log" \
      --exclude="node_modules/**" \
      --exclude="__pycache__/**" \
      --exclude="*.pyc" \
      --retries=3 \
      --progress \
      2>&1 | tail -10
    
    if [ $? -eq 0 ]; then
      echo "[B2] ✅ ALL DATA RESTORED from Backblaze B2!"
    else
      echo "[B2] ⚠️ Restore had errors - check B2 logs"
    fi
  else
    echo "[B2] B2 bucket is empty - starting fresh"
  fi
else
  echo "[B2] ⚠️ B2 not configured - starting fresh"
fi

echo "=========================================="

# ============================================================
# 🔥🔥🔥 OVERRIDE config.yaml with 9router
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

# ============================================================
# Override providers and model sections with 9router
# ============================================================
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
# Start Background Sync (B2 instead of Git)
# ============================================================
if [ "$B2_ENABLED" = true ]; then
  echo "[ENTRYPOINT] Starting sync.sh (B2) in background..."
  /app/sync.sh 2>&1 &
  SYNC_PID=$!
  echo "[ENTRYPOINT] Sync PID: $SYNC_PID"

  sleep 2
  if kill -0 $SYNC_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ sync.sh (B2) is running"
  else
    echo "[ENTRYPOINT] ❌ sync.sh FAILED to start!"
  fi
else
  echo "[ENTRYPOINT] ⚠️ B2 not configured - skipping sync.sh"
  SYNC_PID=""
fi

# ============================================================
# Start Modal Client API Server
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
# Graceful Shutdown Handler
# ============================================================
cleanup() {
  echo ""
  echo "=========================================="
  echo "[ENTRYPOINT] Shutting down - forcing final B2 sync..."
  echo "=========================================="

  # Stop sync process
  if [ -n "$SYNC_PID" ]; then
    kill $SYNC_PID 2>/dev/null || true
    wait $SYNC_PID 2>/dev/null || true
  fi
  
  # Stop modal client
  if [ -n "$MODAL_PID" ]; then
    kill $MODAL_PID 2>/dev/null || true
    wait $MODAL_PID 2>/dev/null || true
  fi

  # Final B2 sync
  if [ "$B2_ENABLED" = true ]; then
    echo "[ENTRYPOINT] Final B2 sync..."
    rclone sync "$HERMES_DIR" "b2:${B2_BUCKET_NAME}" \
      --transfers=4 \
      --checkers=8 \
      --exclude="*.tmp" \
      --exclude="*.log" \
      --exclude="node_modules/**" \
      --exclude="__pycache__/**" \
      --exclude="*.pyc" \
      --retries=3 \
      2>&1 | tail -5
    
    if [ $? -eq 0 ]; then
      echo "[ENTRYPOINT] ✅ Final B2 sync completed"
    else
      echo "[ENTRYPOINT] ⚠️ Final B2 sync had errors"
    fi
  else
    echo "[ENTRYPOINT] ⚠️ B2 not configured - skipping final sync"
  fi
  
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
