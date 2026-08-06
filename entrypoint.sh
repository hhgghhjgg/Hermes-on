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

# ============================================================
# Directory Setup - EVERYTHING under /data/.hermes
# ============================================================
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
HERMES_SOURCE="/app/hermes-agent"

# Create ALL necessary directories
mkdir -p "$HERMES_DIR"
mkdir -p "$HERMES_DIR/webui/sessions"
mkdir -p "$HERMES_DIR/skills"
mkdir -p "$HERMES_DIR/plans"
mkdir -p "$HERMES_DIR/workspace"  # 🔥 Workspace here now!
mkdir -p "$HERMES_DIR/profiles"
mkdir -p "$HERMES_DIR/crons"
mkdir -p "$HERMES_DIR/cache"

echo "[ENTRYPOINT] HERMES_DIR: $HERMES_DIR"
echo "[ENTRYPOINT] WORKSPACE: $HERMES_DIR/workspace"
echo "[ENTRYPOINT] GITHUB_REPO: ${GITHUB_REPO:-NOT SET}"
echo "[ENTRYPOINT] Token set: $([ -n "$GITHUB_TOKEN" ] && echo YES || echo NO)"

# Portable file size function
get_file_size() {
    if [ -f "$1" ]; then
        stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Git Initialization
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
            # Save current state before reset
            if [ -f "$HERMES_DIR/state.db" ]; then
                CURRENT_SIZE=$(get_file_size "$HERMES_DIR/state.db")
                if [ "$CURRENT_SIZE" -gt 1000 ]; then
                    cp "$HERMES_DIR/state.db" "$HERMES_DIR/state.db.pre-reset.$(date +%s)" 2>/dev/null || true
                fi
            fi
            
            echo "[ENTRYPOINT] Resetting to origin/main (FULL RESTORE)..."
            git reset --hard origin/main 2>&1 || true
            git clean -fd -e "state.db*" -e "*.pre-*" 2>&1 || true
            
            echo "[ENTRYPOINT] ✅ ALL DATA RESTORED from GitHub!"
            echo "[ENTRYPOINT] Current commit: $(git rev-parse --short HEAD)"
        else
            echo "[ENTRYPOINT] ⚠️ No remote branch - starting fresh"
            
            # Create .gitignore with MINIMAL exclusions
            cat > .gitignore <<'EOF'
# Security (DO NOT sync secrets)
*.key
*.pem
.env
.env.*

# Python cache
__pycache__/
*.pyc
*.pyo
*.pyd

# Temporary files
*.tmp
*.log
*.journal
state.db-journal
state.db-wal

# Node
node_modules/
.DS_Store

# Backup files (auto-cleaned)
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
    
    # Restore state.db from largest backup
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

# Create .gitignore if missing
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
# 🔥 COPY OLD WORKSPACE DATA if exists
# ============================================================
if [ -d "/root/workspace" ]; then
    echo "[ENTRYPOINT] Migrating old workspace to new location..."
    cp -r /root/workspace/* "$HERMES_DIR/workspace/" 2>/dev/null || true
    cp -r /root/workspace/.* "$HERMES_DIR/workspace/" 2>/dev/null || true
    echo "[ENTRYPOINT] ✅ Workspace migrated"
fi

# ============================================================
# COPY ALL BUNDLED SKILLS from Hermes Source
# ============================================================
echo "=========================================="
echo "[SKILLS] Copying ALL bundled skills from source..."
echo "=========================================="

if [ -d "$HERMES_SOURCE/skills" ]; then
    mkdir -p "$HERMES_DIR/skills"
    
    BEFORE_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
    
    cp -r "$HERMES_SOURCE/skills/"* "$HERMES_DIR/skills/" 2>/dev/null || true
    
    AFTER_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
    NEW_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
    
    echo "[SKILLS] ✅ Copied ALL bundled skills: $AFTER_COUNT total ($NEW_COUNT new)"
else
    echo "[SKILLS] ⚠️ Source skills directory not found"
fi

# ============================================================
# INSTALL ALL OPTIONAL SKILLS from Skills Hub
# ============================================================
install_all_optional_skills() {
    SKILLS_FILE="/app/skills.txt"
    
    if [ ! -f "$SKILLS_FILE" ]; then
        echo "[SKILLS] ⚠️ skills.txt not found"
        return
    fi
    
    echo "=========================================="
    echo "[SKILLS] Installing ALL optional skills from Hub..."
    echo "=========================================="
    
    HERMES_VENV="/app/hermes-agent/.venv"
    if [ -f "$HERMES_VENV/bin/activate" ]; then
        source "$HERMES_VENV/bin/activate"
    fi
    
    export HERMES_HOME="$HERMES_DIR"
    
    INSTALLED=0
    SKIPPED=0
    FAILED=0
    TOTAL_ATTEMPTED=0
    
    while IFS= read -r skill; do
        [[ -z "$skill" || "$skill" =~ ^[[:space:]]*# ]] && continue
        skill=$(echo "$skill" | xargs)
        
        TOTAL_ATTEMPTED=$((TOTAL_ATTEMPTED + 1))
        
        if [ -d "$HERMES_DIR/skills/$skill" ] || [ -f "$HERMES_DIR/skills/$skill/SKILL.md" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        
        echo "[SKILLS #$TOTAL_ATTEMPTED] Installing: $skill"
        
        if timeout 30 hermes skill install "$skill" 2>/dev/null; then
            INSTALLED=$((INSTALLED + 1))
        else
            FAILED=$((FAILED + 1))
            echo "[SKILLS #$TOTAL_ATTEMPTED] ⚠️ Failed: $skill (continuing...)"
        fi
    done < "$SKILLS_FILE"
    
    echo "=========================================="
    echo "[SKILLS] Installation Summary:"
    echo "[SKILLS]   Total attempted: $TOTAL_ATTEMPTED"
    echo "[SKILLS]   Installed: $INSTALLED"
    echo "[SKILLS]   Skipped: $SKIPPED"
    echo "[SKILLS]   Failed: $FAILED"
    echo "=========================================="
}

install_all_optional_skills

# ============================================================
# Final State Summary
# ============================================================
echo "=========================================="
echo "[ENTRYPOINT] Final state summary:"
echo "=========================================="

if [ -f "$HERMES_DIR/state.db" ]; then
    FINAL_SIZE=$(get_file_size "$HERMES_DIR/state.db")
    echo "[ENTRYPOINT] state.db size: $FINAL_SIZE bytes"
fi

SKILL_COUNT=$(find "$HERMES_DIR/skills" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Total skills installed: $SKILL_COUNT"

MEMORY_COUNT=$(ls "$HERMES_DIR"/MEMORY.md "$HERMES_DIR"/USER.md "$HERMES_DIR"/SOUL.md 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Core files (MEMORY/USER/SOUL): $MEMORY_COUNT"

WEBUI_FILES=$(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] WebUI files: $WEBUI_FILES"

WORKSPACE_FILES=$(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)
echo "[ENTRYPOINT] Workspace files: $WORKSPACE_FILES"

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
# 🔥 Set Environment Variables - ALL paths to /data/.hermes
# ============================================================
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"

# 🔥 CRITICAL: Redirect workspace to /data/.hermes/workspace
export HERMES_WORKSPACE="$HERMES_DIR/workspace"
export HERMES_WEBUI_DEFAULT_WORKSPACE="$HERMES_DIR/workspace"

echo "[ENTRYPOINT] HERMES_HOME: $HERMES_HOME"
echo "[ENTRYPOINT] HERMES_WEBUI_STATE_DIR: $HERMES_WEBUI_STATE_DIR"
echo "[ENTRYPOINT] HERMES_WORKSPACE: $HERMES_WORKSPACE"

# Graceful Shutdown Handler
cleanup() {
    echo ""
    echo "[ENTRYPOINT] Shutting down - forcing final sync..."
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

# Start WebUI
echo "=========================================="
echo "[ENTRYPOINT] Starting Hermes WebUI..."
echo "=========================================="

cd /app/hermes-webui
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
