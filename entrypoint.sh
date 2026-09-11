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
# 🚫 DISABLE GITHUB SYNC
# ============================================================
export GITHUB_SYNC_DISABLED=true
echo "[ENTRYPOINT] 🚫 GitHub sync DISABLED (using B2 storage)"

# ============================================================
# Modal Configuration (optional)
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
# 📦 DATA PRE-LOADED BY WORKFLOW (from B2)
# ============================================================
echo "=========================================="
echo "[DATA] Checking pre-loaded data..."
echo "=========================================="

if [ -f "$HERMES_DIR/config.yaml" ]; then
  echo "[DATA] ✅ Found pre-loaded config.yaml"
  echo "[DATA] ✅ Data was restored from B2 by the workflow"
else
  echo "[DATA] ⚠️ No config.yaml found - starting fresh"
fi

echo "=========================================="

# ============================================================
# 🔥 SMART PROVIDER CONFIGURATION
# ============================================================
echo "=========================================="
echo "[CONFIG] Configuring providers smartly..."
echo "=========================================="

python3 << 'CONFIG_OVERRIDE_SCRIPT'
import yaml
import os
import urllib.request
import json
import sys

config_path = '/data/.hermes/config.yaml'

# Load existing config
if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f) or {}
    print(f"[CONFIG] ✅ Loaded existing config.yaml")
else:
    config = {}
    print(f"[CONFIG] ⚠️ No config.yaml, creating new")

# ============================================================
# CHECK IF LOCAL 9ROUTER IS RUNNING
# ============================================================
LOCAL_ROUTER_URL = "http://localhost:20128/v1"
LOCAL_ROUTER_HEALTH = "http://localhost:20128/"
REMOTE_ROUTER_URL = "https://9router-production-d138.up.railway.app/v1"
REMOTE_ROUTER_KEY = "sk-d042a2942b66660e-wjdw1y-30603948"

def check_url(url, timeout=5):
    """Check if URL is accessible"""
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status == 200
    except Exception as e:
        return False

def get_models_from_router(base_url, api_key=None):
    """Get list of models from router"""
    try:
        url = f"{base_url}/models"
        req = urllib.request.Request(url)
        if api_key:
            req.add_header('Authorization', f'Bearer {api_key}')
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())
            models = data.get('data', [])
            return [m.get('id') for m in models if m.get('id')]
    except Exception as e:
        print(f"[CONFIG] ⚠️ Failed to get models: {e}")
        return []

# Check local 9Router first
LOCAL_ROUTER_AVAILABLE = check_url(LOCAL_ROUTER_HEALTH)

if LOCAL_ROUTER_AVAILABLE:
    print(f"[CONFIG] ✅ Local 9Router detected at {LOCAL_ROUTER_URL}")
    
    # Get models from local router
    models = get_models_from_router(LOCAL_ROUTER_URL)
    print(f"[CONFIG] 📋 Found {len(models)} models from local 9Router")
    
    if models:
        print(f"[CONFIG] Models: {', '.join(models[:10])}{'...' if len(models) > 10 else ''}")
    
    # Configure providers with local 9Router
    config['providers'] = {
        '9router': {
            'base_url': LOCAL_ROUTER_URL,
            'api_key': 'sk-local-9router',
            'description': 'Local 9Router instance'
        }
    }
    
    # Set default model
    default_model = models[0] if models else 'hermes-fast'
    config['model'] = {
        'default': default_model,
        'provider': 'custom:9router',
        'base_url': LOCAL_ROUTER_URL,
        'api_key': 'sk-local-9router'
    }
    
    print(f"[CONFIG] ✅ Using local 9Router with model: {default_model}")
    
else:
    print(f"[CONFIG] ⚠️ Local 9Router not available, using remote...")
    
    # Check remote 9Router
    REMOTE_ROUTER_AVAILABLE = check_url(REMOTE_ROUTER_URL.replace('/v1', ''))
    
    if REMOTE_ROUTER_AVAILABLE:
        print(f"[CONFIG] ✅ Remote 9Router detected at {REMOTE_ROUTER_URL}")
        
        # Get models from remote router
        models = get_models_from_router(REMOTE_ROUTER_URL, REMOTE_ROUTER_KEY)
        print(f"[CONFIG] 📋 Found {len(models)} models from remote 9Router")
        
        # Configure providers with remote 9Router
        config['providers'] = {
            '9router': {
                'base_url': REMOTE_ROUTER_URL,
                'api_key': REMOTE_ROUTER_KEY,
                'description': 'Remote 9Router instance'
            }
        }
        
        # Set default model
        default_model = models[0] if models else 'hermes-fast'
        config['model'] = {
            'default': default_model,
            'provider': 'custom:9router',
            'base_url': REMOTE_ROUTER_URL,
            'api_key': REMOTE_ROUTER_KEY
        }
        
        print(f"[CONFIG] ✅ Using remote 9Router with model: {default_model}")
    else:
        print(f"[CONFIG] ❌ No 9Router available, using default config")
        
        # Keep existing config or set minimal default
        if 'providers' not in config:
            config['providers'] = {}
        if 'model' not in config:
            config['model'] = {
                'default': 'hermes-fast',
                'provider': 'custom:9router',
                'base_url': REMOTE_ROUTER_URL,
                'api_key': REMOTE_ROUTER_KEY
            }

# ============================================================
# ADD ADDITIONAL PROVIDERS IF CONFIGURED
# ============================================================
# Check for OpenRouter
if os.environ.get('OPENROUTER_API_KEY'):
    config['providers']['openrouter'] = {
        'base_url': 'https://openrouter.ai/api/v1',
        'api_key': os.environ['OPENROUTER_API_KEY'],
        'description': 'OpenRouter'
    }
    print(f"[CONFIG] ✅ Added OpenRouter provider")

# Check for OpenAI
if os.environ.get('OPENAI_API_KEY'):
    config['providers']['openai'] = {
        'base_url': 'https://api.openai.com/v1',
        'api_key': os.environ['OPENAI_API_KEY'],
        'description': 'OpenAI'
    }
    print(f"[CONFIG] ✅ Added OpenAI provider")

# Check for Anthropic
if os.environ.get('ANTHROPIC_API_KEY'):
    config['providers']['anthropic'] = {
        'base_url': 'https://api.anthropic.com/v1',
        'api_key': os.environ['ANTHROPIC_API_KEY'],
        'description': 'Anthropic'
    }
    print(f"[CONFIG] ✅ Added Anthropic provider")

# Check for Gemini
if os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY'):
    gemini_key = os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
    config['providers']['gemini'] = {
        'base_url': 'https://generativelanguage.googleapis.com/v1beta',
        'api_key': gemini_key,
        'description': 'Google Gemini'
    }
    print(f"[CONFIG] ✅ Added Gemini provider")

# ============================================================
# KEEP EXISTING SETTINGS
# ============================================================
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

# ============================================================
# SAVE CONFIG
# ============================================================
with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f"[CONFIG] ✅ config.yaml updated")
print(f"[CONFIG] ✅ Providers configured: {', '.join(config.get('providers', {}).keys())}")
print(f"[CONFIG] ✅ Default model: {config.get('model', {}).get('default', 'unknown')}")
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
# Graceful Shutdown Handler
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
  echo "[ENTRYPOINT] ℹ️ Data will be saved to B2 by the workflow"
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

python server.py 2>&1 | \
  grep -v "agent session listing skipped" | \
  grep -v "Token from GITHUB_TOKEN is not supported" | \
  grep -v "Slow WebUI request" | \
  grep -v "live provider-catalog rebuild exceeded"
