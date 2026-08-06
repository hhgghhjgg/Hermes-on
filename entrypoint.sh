#!/bin/bash
set -e

echo "=========================================="
echo " Hermes + WebUI Docker Entrypoint"
echo "=========================================="

# Set Git credentials (required for commits)
git config --global user.email "hermes-bot@example.com"
git config --global user.name "Hermes Bot"

# Define data directory
DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"

# Create data directory if not exists
mkdir -p "$HERMES_DIR"

# Initialize git repository in data directory if not exists
if [ ! -d "$HERMES_DIR/.git" ]; then
    echo "Initializing git repository in $HERMES_DIR..."
    cd "$HERMES_DIR"
    git init
else
    echo "Git repository already exists in $HERMES_DIR."
    cd "$HERMES_DIR"
fi

# Create a .gitignore to avoid committing sensitive/temp files
cat > "$HERMES_DIR/.gitignore" <<'EOF'
# Ignore sensitive files
*.key
*.pem
*.env

# Ignore cache
__pycache__/
*.pyc
*.pyo

# Ignore temporary files
*.tmp
*.temp
*.log

# Ignore large binary files (optional)
*.zip
*.tar.gz
EOF

# Add .gitignore to git
cd "$HERMES_DIR"
git add .gitignore 2>/dev/null || true
git commit -m "Add .gitignore" 2>/dev/null || true

# Pull latest data from GitHub if token is provided
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "Configuring GitHub remote..."
    # GITHUB_REPO should be like: username/repo-name
    REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
    
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
    fi
    
    echo "Pulling latest data from GitHub..."
    if git pull origin main --allow-unrelated-histories 2>/dev/null; then
        echo "Data pulled successfully from GitHub."
    else
        echo "No remote data found or pull failed. Starting fresh."
        # Create initial commit if remote is empty
        touch "$HERMES_DIR/.keep"
        git add .
        git commit -m "Initial commit from Docker entrypoint" 2>/dev/null || true
        git push -u origin main 2>/dev/null || true
    fi
else
    echo "WARNING: GITHUB_TOKEN or GITHUB_REPO not set. Data will NOT be persisted to GitHub!"
fi

echo "=========================================="
echo " Starting background sync script..."
echo "=========================================="

# Start sync script in background
/app/sync.sh &

echo "=========================================="
echo " Starting Hermes WebUI..."
echo "=========================================="

# Set environment variables for WebUI
export HERMES_HOME="$HERMES_DIR"
export HERMES_WEBUI_STATE_DIR="$HERMES_DIR/webui"
export HERMES_WEBUI_AGENT_DIR="/app/hermes-agent"
export HERMES_WEBUI_HOST="${HERMES_WEBUI_HOST:-0.0.0.0}"
export HERMES_WEBUI_PORT="${HERMES_WEBUI_PORT:-8787}"

# Change to WebUI directory and start server
cd /app/hermes-webui

# Use server.py directly
exec python server.py
