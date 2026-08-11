#!/bin/bash

set -e

echo "=========================================="
echo "\[ENTRYPOINT\] Started at $(date)"
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
# 🔥 Modal Configuration
# ============================================================
echo "=========================================="
echo "\[MODAL\] Checking Modal credentials..."
echo "=========================================="

MODAL_CLIENT_ENABLED=false
MODAL_PID=""

if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
  echo "\[MODAL\] ✅ MODAL_TOKEN_ID: ${MODAL_TOKEN_ID:0:10}..."
  echo "\[MODAL\] ✅ MODAL_TOKEN_SECRET: set (${#MODAL_TOKEN_SECRET} chars)"
  echo "\[MODAL\] ✅ MODAL_ENVIRONMENT: ${MODAL_ENVIRONMENT:-main}"
  
  # Create Modal config directory
  mkdir -p /root/.modal
  echo "\[MODAL\] ✅ Config directory ready: /root/.modal"
  
  # Export Modal environment variables explicitly
  export MODAL_TOKEN_ID
  export MODAL_TOKEN_SECRET
  export MODAL_ENVIRONMENT="${MODAL_ENVIRONMENT:-main}"
  echo "\[MODAL\] ✅ Modal environment variables exported"
  MODAL_CLIENT_ENABLED=true
else
  echo "\[MODAL\] ⚠️ Modal credentials not set!"
  echo "\[MODAL\] MODAL_TOKEN_ID: $([ -n "$MODAL_TOKEN_ID" ] && echo SET || echo MISSING)"
  echo "\[MODAL\] MODAL_TOKEN_SECRET: $([ -n "$MODAL_TOKEN_SECRET" ] && echo SET || echo MISSING)"
  echo "\[MODAL\] Hermes will not be able to use Modal sandboxes"
fi

echo "=========================================="

# ============================================================
# Directory Setup
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
HERMES_SOURCE="/app/hermes-agent"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"
mkdir -p "$HERMES_DIR/workspace"
mkdir -p "$HERMES_DIR/profiles"
mkdir -p "$HERMES_DIR/crons"
mkdir -p "$HERMES_DIR/cache"

echo "\[ENTRYPOINT\] HERMES_DIR: $HERMES_DIR"
echo "\[ENTRYPOINT\] HERMES_SOURCE: $HERMES_SOURCE"
echo "\[ENTRYPOINT\] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"
echo "\[ENTRYPOINT\] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"

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
# Git Initialization
# ============================================================
cd "$HERMES_DIR"
if [ ! -d ".git" ]; then
  echo "\[ENTRYPOINT\] Initializing new git repo..."
  git init -b main
fi

# ============================================================
# RESTORE EVERYTHING from GitHub
# ============================================================
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL"
  else
    git remote add origin "$REMOTE_URL"
  fi

  echo "\[ENTRYPOINT\] Fetching ALL data from GitHub..."
  if git fetch origin 2>&1; then
    echo "\[ENTRYPOINT\] ✅ Fetch successful"
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      # Save current state.db before reset (in case it has new data)
      if [ -f "$HERMES_DIR/state.db" ]; then
        CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
        if [ "$CURRENT_SIZE" -gt 1000 ]; then
          cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-reset.$(date +%s)" 2>/dev/null || true
          echo "\[ENTRYPOINT\] Saved current state.db as backup"
        fi
      fi
      
      echo "\[ENTRYPOINT\] Resetting to origin/main (FULL RESTORE)..."
      git reset --hard origin/main 2>&1 || true
      git clean -fd -e "state.db*" -e "*.pre-*" 2>&1 || true
      echo "\[ENTRYPOINT\] ✅ ALL DATA RESTORED from GitHub!"
      echo "\[ENTRYPOINT\] Current commit: $(git rev-parse --short HEAD)"
    else
      echo "\[ENTRYPOINT\] ⚠️ No remote branch - starting fresh"
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
      touch .keep
      git add -A
      git commit -m "Initial commit" 2>/dev/null || true
      git branch -M main
      git push -u origin main 2>&1 || true
    fi
  else
    echo "\[ENTRYPOINT\] ⚠️ Fetch failed - using local data"
  fi

  # Restore state.db from largest backup if current is small
  if [ -f "$HERMES_DIR/state.db" ]; then
    CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
    if [ "$CURRENT_SIZE" -lt 1000 ]; then
      LARGEST_BACKUP=$(ls -S "$HERMES_DIR"/state.db.bak.* 2>/dev/null | head -1)
      if [ -n "$LARGEST_BACKUP" ]; then
        BACKUP_SIZE=$(get_file_size "$LARGEST_BACKUP")
        if [ "$BACKUP_SIZE" -gt "$CURRENT_SIZE" ]; then
          cp "$LARGEST_BACKUP" "$HERMES_DIR/state.db"
          echo "\[ENTRYPOINT\] ✅ Restored state.db from $LARGEST_BACKUP"
        fi
      fi
    fi
  fi
else
  echo "\[ENTRYPOINT\] ❌ GITHUB_TOKEN or GITHUB_REPO NOT SET!"
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
  echo "\[ENTRYPOINT\] .gitignore created"
fi

# ============================================================
# 🔥 COPY ALL BUNDLED SKILLS (72 skills)
# Source: /app/hermes-agent/skills/
# ============================================================
echo "=========================================="
echo "\[SKILLS\] Copying ALL bundled skills..."
echo "\[SKILLS\] Source: $HERMES_SOURCE/skills/"
echo "=========================================="

if [ -d "$HERMES_SOURCE/skills" ]; then
  BEFORE_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
  
  # List bundled categories
  echo "\[SKILLS\] Bundled categories found:"
  ls -1 "$HERMES_SOURCE/skills/" 2>/dev/null | while read category; do
    if [ -d "$HERMES_SOURCE/skills/$category" ]; then
      echo "\[SKILLS\]   - $category"
      cp -r "$HERMES_SOURCE/skills/$category" "$HERMES_DIR/skills/" 2>/dev/null || true
    fi
  done
  
  AFTER_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
  NEW_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
  
  echo "\[SKILLS\] ✅ Bundled skills: $AFTER_COUNT total ($NEW_COUNT new)"
else
  echo "\[SKILLS\] ❌ ERROR: Bundled skills directory not found!"
  echo "\[SKILLS\] Listing $HERMES_SOURCE contents:"
  ls -la "$HERMES_SOURCE/" 2>/dev/null | head -20
fi

# ============================================================
# 🔥 COPY ALL OPTIONAL SKILLS (129 skills)
# Source: /app/hermes-agent/optional-skills/
# ============================================================
echo "=========================================="
echo "\[SKILLS\] Copying ALL optional skills..."
echo "\[SKILLS\] Source: $HERMES_SOURCE/optional-skills/"
echo "=========================================="

if [ -d "$HERMES_SOURCE/optional-skills" ]; then
  BEFORE_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
  
  # List optional categories
  echo "\[SKILLS\] Optional categories found:"
  ls -1 "$HERMES_SOURCE/optional-skills/" 2>/dev/null | while read category; do
    if [ -d "$HERMES_SOURCE/optional-skills/$category" ]; then
      echo "\[SKILLS\]   - $category"
      cp -r "$HERMES_SOURCE/optional-skills/$category" "$HERMES_DIR/skills/" 2>/dev/null || true
    fi
  done
  
  AFTER_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
  NEW_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
  
  echo "\[SKILLS\] ✅ Optional skills added: $NEW_COUNT new"
  echo "\[SKILLS\] ✅ Total skills now: $AFTER_COUNT"
else
  echo "\[SKILLS\] ⚠️ Optional skills directory not found at $HERMES_SOURCE/optional-skills"
  echo "\[SKILLS\] Listing $HERMES_SOURCE contents:"
  ls -la "$HERMES_SOURCE/" 2>/dev/null | head -20
fi

# ============================================================
# 🔥 COPY OLD WORKSPACE DATA if exists
# ============================================================
if [ -d "/root/workspace" ]; then
  echo "\[ENTRYPOINT\] Migrating old workspace to new location..."
  cp -r /root/workspace/* "$HERMES_DIR/workspace/" 2>/dev/null || true
  cp -r /root/workspace/.* "$HERMES_DIR/workspace/" 2>/dev/null || true
  echo "\[ENTRYPOINT\] ✅ Workspace migrated"
fi

# ============================================================
# 🔥🔥🔥 NEW: GENERATE config.yaml → Connect Hermes to OmniRoute
# ============================================================
echo "=========================================="
echo "\[CONFIG\] Generating config.yaml for OmniRoute..."
echo "\[CONFIG\] OMNIROUTE_URL: ${OMNIROUTE_URL:-NOT SET}"
echo "=========================================="

# Use OMNIROUTE_URL from env, fallback to Railway URL
OMNI_URL="${OMNIROUTE_URL:-https://omniroute-app-production-9940.up.railway.app}"
OMNI_API_URL="${OMNI_URL}/v1"

# API Key - Read from environment variable (fallback to hardcoded)
OMNI_API_KEY="${OMNIROUTE_API_KEY:-sk-7150f73b0efb9f5e-d0a99b-0c5675aa}"

# Generate config.yaml with Hermes-compatible format
cat > "$HERMES_DIR/config.yaml" <<EOF
# Hermes Agent Configuration - Connected to OmniRoute
# Generated by entrypoint.sh - DO NOT EDIT MANUALLY
providers:
  omniroute:
    api: ${OMNI_API_URL}
    api_key: ${OMNI_API_KEY}
    transport: chat_completions
    default_model: hermes-fast
    enabled: true
model:
  default: ${HERMES_WEBUI_DEFAULT_MODEL:-hermes-fast}
  provider: custom:omniroute
workspace: ${HERMES_DIR}/workspace
memory:
  enabled: true
  path: ${HERMES_DIR}/MEMORY.md
user:
  profile_path: ${HERMES_DIR}/USER.md
soul:
  path: ${HERMES_DIR}/SOUL.md
EOF

echo "\[CONFIG\] ✅ config.yaml written"
echo "\[CONFIG\] Provider: omniroute"
echo "\[CONFIG\] API: ${OMNI_API_URL}"
echo "\[CONFIG\] Model: ${HERMES_WEBUI_DEFAULT_MODEL:-hermes-fast}"
echo "\[CONFIG\] API Key: ***"

# ============================================================
# Final State Summary
# ============================================================
echo "=========================================="
echo "\[ENTRYPOINT\] Final state summary:"
echo "=========================================="

if [ -f "$HERMES_DIR/state.db" ]; then
  FINAL_SIZE=$(get_file_size "$HERMES_DIR/state.db")
  echo "\[ENTRYPOINT\] state.db: $FINAL_SIZE bytes"
fi

SKILL_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Total skills: $SKILL_COUNT"

# List all skill categories
echo "\[ENTRYPOINT\] Skill categories installed:"
ls -1 "$HERMES_DIR/skills/" 2>/dev/null | grep -v "^$" | sort

MEMORY_COUNT=$(ls "$HERMES_DIR"/MEMORY.md "$HERMES_DIR"/USER.md "$HERMES_DIR"/SOUL.md 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Core files (MEMORY/USER/SOUL): $MEMORY_COUNT"

WEBUI_FILES=$(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] WebUI files: $WEBUI_FILES"

WORKSPACE_FILES=$(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Workspace files: $WORKSPACE_FILES"

# Count all files that will be synced
TOTAL_FILES=$(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Total files to sync: $TOTAL_FILES"
echo "=========================================="

# ============================================================
# Start Background Sync
# ============================================================
echo "\[ENTRYPOINT\] Starting sync.sh in background..."
/app/sync.sh 2>&1 &
SYNC_PID=$!
echo "\[ENTRYPOINT\] Sync PID: $SYNC_PID"

sleep 2
if kill -0 $SYNC_PID 2>/dev/null; then
  echo "\[ENTRYPOINT\] ✅ sync.sh is running"
else
  echo "\[ENTRYPOINT\] ❌ sync.sh FAILED to start!"
fi

# ============================================================
# 🔥 START QWEN PROXY
# ============================================================
echo "=========================================="
echo "\[ENTRYPOINT\] Starting Qwen OAuth Proxy..."
echo "=========================================="

python3 /app/qwen-proxy.py 2>&1 &
PROXY_PID=$!
echo "\[ENTRYPOINT\] Qwen Proxy PID: $PROXY_PID"

sleep 3
if kill -0 $PROXY_PID 2>/dev/null; then
  echo "\[ENTRYPOINT\] ✅ Qwen Proxy is running on port 8080"
  echo "\[ENTRYPOINT\] ✅ Configure Hermes to use: http://localhost:8080/v1"
else
  echo "\[ENTRYPOINT\] ❌ Qwen Proxy FAILED to start!"
fi

# ============================================================
# 🔥🔥🔥 NEW: START MODAL CLIENT API SERVER
# ============================================================
if [ "$MODAL_CLIENT_ENABLED" = true ]; then
  echo "=========================================="
  echo "\[ENTRYPOINT\] Starting Modal Client API..."
  echo "=========================================="

  python3 /app/modal-client.py 2>&1 &
  MODAL_PID=$!
  echo "\[ENTRYPOINT\] Modal Client PID: $MODAL_PID"

  sleep 4
  if kill -0 $MODAL_PID 2>/dev/null; then
    echo "\[ENTRYPOINT\] ✅ Modal Client is running on port 8090"
    echo "\[ENTRYPOINT\] ✅ Hermes can create sandboxes via: http://localhost:8090"
    echo "\[ENTRYPOINT\] ✅ Supported languages: PHP, Python, Node, Go, Java, Rust, etc."
    echo "\[ENTRYPOINT\] ✅ Hermes can install ANY package via apt/pip/npm/composer"
  else
    echo "\[ENTRYPOINT\] ❌ Modal Client FAILED to start!"
    echo "\[ENTRYPOINT\] Hermes will continue without Modal support"
    MODAL_PID=""
  fi
  echo "=========================================="
fi

# ============================================================
# 🔥 Test Modal Connection (if credentials are set)
# ============================================================
if [ "$MODAL_CLIENT_ENABLED" = true ]; then
  echo "=========================================="
  echo "\[MODAL\] Verifying Modal SDK..."
  echo "=========================================="

  python3 << 'MODAL_TEST'
import os
import sys

try:
    import modal
    
    # Modal reads MODAL_TOKEN_ID and MODAL_TOKEN_SECRET from env
    token_id = os.environ.get('MODAL_TOKEN_ID', '')
    token_secret = os.environ.get('MODAL_TOKEN_SECRET', '')
    environment = os.environ.get('MODAL_ENVIRONMENT', 'main')
    
    if not token_id or not token_secret:
        print("\[MODAL\] ❌ Modal tokens not found in environment")
        sys.exit(1)
    
    print(f"\[MODAL\] Token ID: {token_id[:10]}...")
    print(f"\[MODAL\] Environment: {environment}")
    
    # Try to connect
    client = modal.Client.from_env()
    print("\[MODAL\] ✅ Client created successfully")
    print("\[MODAL\] ✅ Modal integration ready!")
    print("\[MODAL\] Hermes can now create sandboxes for:")
    print("\[MODAL\]   - PHP/Laravel projects")
    print("\[MODAL\]   - Python scripts and ML tasks")
    print("\[MODAL\]   - Node.js applications (React, Vue, Express)")
    print("\[MODAL\]   - Go/Java/Rust projects")
    print("\[MODAL\]   - Any language installable via apt/pip/npm")
    
except ImportError:
    print("\[MODAL\] ❌ Modal SDK not installed!")
    print("\[MODAL\] Run: pip install modal>=0.73.0")
    sys.exit(1)
except Exception as e:
    print(f"\[MODAL\] ⚠️ Modal verification failed: {e}")
    print("\[MODAL\] Modal Client will handle connection at runtime")
MODAL_TEST

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

# Export Modal Client URL for Hermes to use
export MODAL_CLIENT_URL="http://localhost:8090"

echo "\[ENTRYPOINT\] HERMES_HOME: $HERMES_HOME"
echo "\[ENTRYPOINT\] HERMES_WEBUI_STATE_DIR: $HERMES_WEBUI_STATE_DIR"
echo "\[ENTRYPOINT\] HERMES_WORKSPACE: $HERMES_WORKSPACE"
echo "\[ENTRYPOINT\] HERMES_WEBUI_HOST: $HERMES_WEBUI_HOST"
echo "\[ENTRYPOINT\] HERMES_WEBUI_PORT: $HERMES_WEBUI_PORT"
echo "\[ENTRYPOINT\] MODAL_CLIENT_URL: $MODAL_CLIENT_URL"

# ============================================================
# Graceful Shutdown Handler
# ============================================================
cleanup() {
  echo ""
  echo "=========================================="
  echo "\[ENTRYPOINT\] Shutting down - forcing final sync..."
  echo "=========================================="

  # Kill all background processes
  if [ -n "$SYNC_PID" ]; then
    kill $SYNC_PID 2>/dev/null || true
    wait $SYNC_PID 2>/dev/null || true
  fi
  if [ -n "$PROXY_PID" ]; then
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
  fi
  if [ -n "$MODAL_PID" ]; then
    kill $MODAL_PID 2>/dev/null || true
    wait $MODAL_PID 2>/dev/null || true
  fi

  # Final sync to GitHub
  cd "$HERMES_DIR"
  if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
    echo "\[ENTRYPOINT\] Committing final changes (ALL data)..."
    git add -A
    git commit -m "sync: final shutdown @ $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null || true
    git push --force origin main 2>&1 || true
    echo "\[ENTRYPOINT\] ✅ Final sync completed"
  fi
  exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# ============================================================
# Start WebUI
# ============================================================
echo "=========================================="
echo "\[ENTRYPOINT\] Starting Hermes WebUI..."
echo "=========================================="

# 🔥 FIXED: WebUI is cloned to /app/webui (not /app/hermes-webui)
cd /app/webui || exit 1

# Verify server.py exists
if [ ! -f "server.py" ]; then
  echo "\[ENTRYPOINT\] ❌ server.py not found in /app/webui!"
  echo "\[ENTRYPOINT\] Listing contents:"
  ls -la /app/webui/ | head -20
  exit 1
fi

echo "\[ENTRYPOINT\] ✅ Found server.py in /app/webui"
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
