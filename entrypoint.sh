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
HERMES_SOURCE="/app/hermes-agent"

mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"
mkdir -p "$HERMES_DIR/workspace"
mkdir -p "$HERMES_DIR/profiles"
mkdir -p "$HERMES_DIR/crons"
mkdir -p "$HERMES_DIR/cache"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] HERMES_SOURCE: $HERMES_SOURCE"
echo "[ENTRYPOINT] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"
echo "[ENTRYPOINT] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"
echo "[ENTRYPOINT] OMNIROUTE_URL: ${OMNIROUTE_URL:-NOT SET}"

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
    echo "[ENTRYPOINT] Initializing new git repo..."
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
    
    echo "[ENTRYPOINT] Fetching ALL data from GitHub..."
    
    if git fetch origin 2>&1; then
        echo "[ENTRYPOINT] ✅ Fetch successful"
        
        if git rev-parse --verify origin/main >/dev/null 2>&1; then
            # Save current state.db before reset (in case it has new data)
            if [ -f "$HERMES_DIR/state.db" ]; then
                CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
                if [ "$CURRENT_SIZE" -gt 1000 ]; then
                    cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-reset.$(date +%s)" 2>/dev/null || true
                    echo "[ENTRYPOINT] Saved current state.db as backup"
                fi
            fi
            
            echo "[ENTRYPOINT] Resetting to origin/main (FULL RESTORE)..."
            git reset --hard origin/main 2>&1 || true
            git clean -fd -e "state.db*" -e "*.pre-*" 2>&1 || true
            
            echo "[ENTRYPOINT] ✅ ALL DATA RESTORED from GitHub!"
            echo "[ENTRYPOINT] Current commit: $(git rev-parse --short HEAD)"
        else
            echo "[ENTRYPOINT] ⚠️ No remote branch - starting fresh"
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
        echo "[ENTRYPOINT] ⚠️ Fetch failed - using local data"
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
                    echo "[ENTRYPOINT] ✅ Restored state.db from $LARGEST_BACKUP"
                fi
            fi
        fi
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
    echo "[ENTRYPOINT] .gitignore created"
fi

# ============================================================
# 🔥 COPY ALL BUNDLED SKILLS (72 skills)
# Source: /app/hermes-agent/skills/
# ============================================================
echo "=========================================="
echo "[SKILLS] Copying ALL bundled skills..."
echo "[SKILLS] Source: $HERMES_SOURCE/skills/"
echo "=========================================="

if [ -d "$HERMES_SOURCE/skills" ]; then
    BEFORE_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
    
    # List bundled categories
    echo "[SKILLS] Bundled categories found:"
    ls -1 "$HERMES_SOURCE/skills/" 2>/dev/null | while read category; do
        if [ -d "$HERMES_SOURCE/skills/$category" ]; then
            echo "[SKILLS]   - $category"
            cp -r "$HERMES_SOURCE/skills/$category" "$HERMES_DIR/skills/" 2>/dev/null || true
        fi
    done
    
    AFTER_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
    NEW_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
    
    echo "[SKILLS] ✅ Bundled skills: $AFTER_COUNT total ($NEW_COUNT new)"
else
    echo "[SKILLS] ❌ ERROR: Bundled skills directory not found!"
    echo "[SKILLS] Listing $HERMES_SOURCE contents:"
    ls -la "$HERMES_SOURCE/" 2>/dev/null | head -20
fi

# ============================================================
# 🔥 COPY ALL OPTIONAL SKILLS (129 skills)
# Source: /app/hermes-agent/optional-skills/
# ============================================================
echo "=========================================="
echo "[SKILLS] Copying ALL optional skills..."
echo "[SKILLS] Source: $HERMES_SOURCE/optional-skills/"
echo "=========================================="

if [ -d "$HERMES_SOURCE/optional-skills" ]; then
    BEFORE_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
    
    # List optional categories
    echo "[SKILLS] Optional categories found:"
    ls -1 "$HERMES_SOURCE/optional-skills/" 2>/dev/null | while read category; do
        if [ -d "$HERMES_SOURCE/optional-skills/$category" ]; then
            echo "[SKILLS]   - $category"
            cp -r "$HERMES_SOURCE/optional-skills/$category" "$HERMES_DIR/skills/" 2>/dev/null || true
        fi
    done
    
    AFTER_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 3 -name "SKILL.md" 2>/dev/null | wc -l)
    NEW_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
    
    echo "[SKILLS] ✅ Optional skills added: $NEW_COUNT new"
    echo "[SKILLS] ✅ Total skills now: $AFTER_COUNT"
else
    echo "[SKILLS] ⚠️ Optional skills directory not found at $HERMES_SOURCE/optional-skills"
    echo "[SKILLS] Listing $HERMES_SOURCE contents:"
    ls -la "$HERMES_SOURCE/" 2>/dev/null | head -20
fi

# ============================================================
# 🔥 COPY OLD WORKSPACE DATA if exists
# ============================================================
if [ -d "/root/workspace" ]; then
    echo "[ENTRYPOINT] Migrating old workspace to new location..."
    cp -r /root/workspace/* "$HERMES_DIR/workspace/" 2>/dev/null || true
    cp -r /root/workspace/.* "$HERMES_DIR/workspace/" 2>/dev/null || true
    echo "[ENTRYPOINT] ✅ Workspace migrated"
fi

# ============================================================
# 🔥 GENERATE config.yaml → Connect Hermes to OmniRoute
# ============================================================
echo "=========================================="
echo "[CONFIG] Generating config.yaml for OmniRoute..."
echo "[CONFIG] OMNIROUTE_URL: ${OMNIROUTE_URL}"
echo "=========================================="

# Use OMNIROUTE_URL from env, fallback to default
OMNI_URL="${OMNIROUTE_URL:-https://omniroute-app.onrender.com}"
OMNI_API_URL="${OMNI_URL}/v1"

cat > "$HERMES_DIR/config.yaml" <<EOF
# ============================================================
# Hermes Agent Configuration
# Generated by entrypoint.sh - DO NOT EDIT MANUALLY
# Changes will be overwritten on restart!
# ============================================================

# Provider configuration - OmniRoute as the AI gateway
providers:
  omniroute:
    api: ${OMNI_API_URL}
    transport: chat_completions
    default_model: auto
    enabled: true

# Model configuration
model:
  default: ${HERMES_WEBUI_DEFAULT_MODEL:-auto}
  provider: custom:omniroute

# Workspace configuration
workspace: ${HERMES_DIR}/workspace

# Memory configuration
memory:
  enabled: true
  path: ${HERMES_DIR}/MEMORY.md

# User profile
user:
  profile_path: ${HERMES_DIR}/USER.md

# Soul/personality
soul:
  path: ${HERMES_DIR}/SOUL.md
EOF

echo "[CONFIG] ✅ config.yaml written"
echo "[CONFIG]   Provider: omniroute"
echo "[CONFIG]   API: ${OMNI_API_URL}"
echo "[CONFIG]   Model: ${HERMES_WEBUI_DEFAULT_MODEL:-auto}"

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

# List all skill categories
echo "[ENTRYPOINT] Skill categories installed:"
ls -1 "$HERMES_DIR/skills/" 2>/dev/null | grep -v "^$" | sort

MEMORY_COUNT=$(ls "$HERMES_DIR"/MEMORY.md "$HERMES_DIR"/USER.md "$HERMES_DIR"/SOUL.md 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Core files (MEMORY/USER/SOUL): $MEMORY_COUNT"

WEBUI_FILES=$(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] WebUI files: $WEBUI_FILES"

WORKSPACE_FILES=$(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Workspace files: $WORKSPACE_FILES"

# Count all files that will be synced
TOTAL_FILES=$(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Total files to sync: $TOTAL_FILES"

echo "=========================================="

# ============================================================
# Start Background Sync
# ============================================================
echo "[ENTRYPOINT] Starting sync.sh in background..."
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
# Set Environment Variables
# ============================================================
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"
export HERMES_WORKSPACE="$HERMES_DIR/workspace"
export HERMES_WEBUI_DEFAULT_WORKSPACE="$HERMES_DIR/workspace"

echo "[ENTRYPOINT] HERMES_HOME: $HERMES_HOME"
echo "[ENTRYPOINT] HERMES_WEBUI_STATE_DIR: $HERMES_WEBUI_STATE_DIR"
echo "[ENTRYPOINT] HERMES_WORKSPACE: $HERMES_WORKSPACE"
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
        echo "[ENTRYPOINT] Committing final changes (ALL data)..."
        git add -A
        git commit -m "sync: final shutdown @ $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null || true
        git push --force origin main 2>&1 || true
        echo "[ENTRYPOINT] ✅ Final sync completed"
    fi
    
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# ============================================================
# Start WebUI
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "[ENTRYPOINT] WebUI will use OmniRoute at: ${OMNI_API_URL}"
echo "=========================================="

cd /app/hermes-webui
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
