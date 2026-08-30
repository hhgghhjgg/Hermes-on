#!/bin/bash

echo "=========================================="
echo "[ENTRYPOINT] Started at $(date)"
echo "=========================================="

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

mkdir -p "$HERMES_DIR"/{webui/sessions,skills,plans,workspace,profiles,crons,cache}

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] B2_BUCKET: ${B2_BUCKET_NAME:-NOT SET}"
echo "[ENTRYPOINT] B2_KEY_ID set: $([ -n "$B2_APPLICATION_KEY_ID" ] && echo YES || echo NO)"

# ============================================================
# Modal (optional)
# ============================================================
echo "=========================================="
echo "[MODAL] Checking Modal credentials..."
echo "=========================================="

MODAL_CLIENT_ENABLED=false
MODAL_PID=""

if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
  echo "[MODAL] ✅ MODAL_TOKEN_ID: ${MODAL_TOKEN_ID:0:10}..."
  mkdir -p /root/.modal
  export MODAL_TOKEN_ID MODAL_TOKEN_SECRET MODAL_ENVIRONMENT="${MODAL_ENVIRONMENT:-main}"
  MODAL_CLIENT_ENABLED=true
else
  echo "[MODAL] ⚠️ Modal credentials not set - skipping"
fi

# ============================================================
# rclone setup
# ============================================================
echo "=========================================="
echo "[B2] Installing and configuring rclone..."
echo "=========================================="

if ! command -v rclone &> /dev/null; then
  echo "[B2] Installing rclone..."
  curl -s https://rclone.org/install.sh | bash || true
fi

echo "[B2] ✅ rclone version: $(rclone --version 2>/dev/null | head -1 || echo unknown)"

B2_ENABLED=false
if [ -n "$B2_APPLICATION_KEY_ID" ] && [ -n "$B2_APPLICATION_KEY" ] && [ -n "$B2_BUCKET_NAME" ]; then
  mkdir -p /root/.config/rclone
  cat > /root/.config/rclone/rclone.conf << EOF
[b2]
type = b2
account = ${B2_APPLICATION_KEY_ID}
key = ${B2_APPLICATION_KEY}
EOF
  chmod 600 /root/.config/rclone/rclone.conf
  echo "[B2] ✅ rclone configured"
  
  if rclone lsd "b2:${B2_BUCKET_NAME}" --max-depth 1 > /dev/null 2>&1; then
    echo "[B2] ✅ B2 connection successful"
    B2_ENABLED=true
  else
    echo "[B2] ⚠️ B2 connection failed"
  fi
fi

# ============================================================
# RESTORE from B2 (با error handling کامل)
# ============================================================
echo "=========================================="
echo "[B2] Restoring data from Backblaze B2..."
echo "=========================================="

cd "$HERMES_DIR" || exit 0

if [ "$B2_ENABLED" = true ]; then
  echo "[B2] Counting files in B2 bucket..."
  
  # شمارش بدون versioning (با --b2-versions=false)
  B2_FILE_COUNT=$(rclone size "b2:${B2_BUCKET_NAME}" --json 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0")
  echo "[B2] Found $B2_FILE_COUNT files in B2 bucket"
  
  if [ "$B2_FILE_COUNT" -gt 0 ] 2>/dev/null; then
    # Backup state.db فعلی
    if [ -f "$HERMES_DIR/state.db" ]; then
      cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-restore.$(date +%s)" 2>/dev/null || true
    fi
    
    echo "[B2] 🚀 Starting restore (this may take a few minutes for 3931 files)..."
    echo "[B2] Restoring to: $HERMES_DIR"
    
    # 🔥🔥🔥 مهم: || true اضافه شده تا حتی اگه fail شد هم ادامه بده
    rclone sync "b2:${B2_BUCKET_NAME}" "$HERMES_DIR" \
      --transfers=8 \
      --checkers=16 \
      --fast-list \
      --b2-versions=false \
      --exclude="*.tmp" \
      --exclude="*.log" \
      --exclude="node_modules/**" \
      --exclude="__pycache__/**" \
      --exclude="*.pyc" \
      --retries=3 \
      --low-level-retries=5 \
      --stats=30s \
      --stats-one-line \
      --progress \
      2>&1 | tail -30 || echo "[B2] ⚠️ Restore had warnings but continuing..."
    
    # Verify
    LOCAL_COUNT=$(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)
    LOCAL_SIZE=$(du -sh "$HERMES_DIR" 2>/dev/null | cut -f1)
    echo ""
    echo "[B2] ✅ Restore completed!"
    echo "[B2] 📊 Local files: $LOCAL_COUNT"
    echo "[B2] 💾 Local size: $LOCAL_SIZE"
  else
    echo "[B2] ⚠️ B2 bucket is empty - starting fresh"
  fi
else
  echo "[B2] ⚠️ B2 not configured - starting fresh"
fi

# ============================================================
# config.yaml override with 9router
# ============================================================
echo "=========================================="
echo "[CONFIG] Overriding config.yaml with 9router..."
echo "=========================================="

python3 << 'CONFIG_OVERRIDE_SCRIPT'
import yaml
import os

config_path = '/data/.hermes/config.yaml'

if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f) or {}
    print(f"[CONFIG] ✅ Loaded existing config.yaml")
else:
    config = {}
    print(f"[CONFIG] ⚠️ No config.yaml, creating new")

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

if 'workspace' not in config:
    config['workspace'] = '/data/.hermes/workspace'
if 'memory' not in config:
    config['memory'] = {'enabled': True, 'path': '/data/.hermes/MEMORY.md'}
if 'user' not in config:
    config['user'] = {'profile_path': '/data/.hermes/USER.md'}
if 'soul' not in config:
    config['soul'] = {'path': '/data/.hermes/SOUL.md'}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f"[CONFIG] ✅ config.yaml updated with 9router")
CONFIG_OVERRIDE_SCRIPT

# ============================================================
# Final Summary
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Final state summary:"
echo "=========================================="

if [ -f "$HERMES_DIR/state.db" ]; then
  echo "[ENTRYPOINT] state.db: $(stat -c%s "$HERMES_DIR/state.db" 2>/dev/null || stat -f%z "$HERMES_DIR/state.db" 2>/dev/null || echo 'unknown') bytes"
else
  echo "[ENTRYPOINT] state.db: NOT PRESENT"
fi

echo "[ENTRYPOINT] Skills: $(find "$HERMES_DIR/skills" -maxdepth 3 -name 'SKILL.md' 2>/dev/null | wc -l)"
echo "[ENTRYPOINT] WebUI files: $(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)"
echo "[ENTRYPOINT] Workspace files: $(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)"
echo "[ENTRYPOINT] Total files: $(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)"
echo "[ENTRYPOINT] Total size: $(du -sh "$HERMES_DIR" 2>/dev/null | cut -f1 || echo 'unknown')"
echo "=========================================="

# ============================================================
# Start background sync
# ============================================================
SYNC_PID=""
if [ "$B2_ENABLED" = true ]; then
  echo "[ENTRYPOINT] Starting sync.sh (B2) in background..."
  /app/sync.sh > /tmp/sync.log 2>&1 &
  SYNC_PID=$!
  sleep 2
  if kill -0 $SYNC_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ sync.sh (B2) is running (PID: $SYNC_PID)"
  else
    echo "[ENTRYPOINT] ⚠️ sync.sh failed to start"
  fi
fi

# ============================================================
# Start Modal client (optional)
# ============================================================
MODAL_PID=""
if [ "$MODAL_CLIENT_ENABLED" = true ]; then
  python3 /app/modal-client.py > /tmp/modal.log 2>&1 &
  MODAL_PID=$!
  sleep 4
  if kill -0 $MODAL_PID 2>/dev/null; then
    echo "[ENTRYPOINT] ✅ Modal Client running on port 8090"
  fi
fi

# ============================================================
# Environment variables
# ============================================================
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"
export HERMES_WORKSPACE="$HERMES_DIR/workspace"
export HERMES_WEBUI_DEFAULT_WORKSPACE="$HERMES_DIR/workspace"
export MODAL_CLIENT_URL="http://localhost:8090"

# ============================================================
# Graceful shutdown
# ============================================================
cleanup() {
  echo ""
  echo "[ENTRYPOINT] Shutting down..."
  [ -n "$SYNC_PID" ] && kill $SYNC_PID 2>/dev/null || true
  [ -n "$MODAL_PID" ] && kill $MODAL_PID 2>/dev/null || true
  
  if [ "$B2_ENABLED" = true ]; then
    echo "[ENTRYPOINT] Final B2 sync..."
    rclone sync "$HERMES_DIR" "b2:${B2_BUCKET_NAME}" \
      --transfers=4 \
      --checkers=8 \
      --b2-versions=false \
      --exclude="*.tmp" \
      --exclude="*.log" \
      --retries=2 \
      2>&1 | tail -5 || true
    echo "[ENTRYPOINT] ✅ Final sync attempted"
  fi
  exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# ============================================================
# Start WebUI
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] 🚀 Starting Hermes WebUI..."
echo "=========================================="

cd /app/webui || exit 1

if [ ! -f "server.py" ]; then
  echo "[ENTRYPOINT] ❌ server.py not found!"
  exit 1
fi

exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
