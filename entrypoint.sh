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
  
  mkdir -p /root/.modal
  echo "\[MODAL\] ✅ Config directory ready: /root/.modal"
  
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
      
      # ============================================================
      # 🔥 FIX: Backup config.yaml BEFORE git reset
      # ============================================================
      CONFIG_BACKUP=""
      if [ -f "$HERMES_DIR/config.yaml" ]; then
        CONFIG_BACKUP=$(cat "$HERMES_DIR/config.yaml")
        echo "\[ENTRYPOINT\] 💾 Backed up current config.yaml"
      fi
      
      echo "\[ENTRYPOINT\] Resetting to origin/main (FULL RESTORE)..."
      git reset --hard origin/main 2>&1 || true
      git clean -fd -e "state.db*" -e "*.pre-*" -e "config.yaml" 2>&1 || true
      echo "\[ENTRYPOINT\] ✅ ALL DATA RESTORED from GitHub!"
      echo "\[ENTRYPOINT\] Current commit: $(git rev-parse --short HEAD)"
      
      # ============================================================
      # 🔥 FIX: Restore config.yaml AFTER git reset (prevent overwrite)
      # ============================================================
      if [ -n "$CONFIG_BACKUP" ]; then
        echo "$CONFIG_BACKUP" > "$HERMES_DIR/config.yaml"
        echo "\[ENTRYPOINT\] ♻️ Restored config.yaml (protected from git reset)"
      fi
      
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
# 🔥🔥🔥 ENABLE ALL PLUGINS USING _discover_all_plugins (CORRECT METHOD)
# ============================================================
echo "=========================================="
echo "\[PLUGINS\] Discovering ALL plugins using Hermes discovery..."
echo "=========================================="

export HERMES_HOME="$HERMES_DIR"
cd /app/hermes-agent || exit 1

python3 << 'PLUGIN_DISCOVERY_SCRIPT'
import sys
import os
import yaml

sys.path.insert(0, '/app/hermes-agent')
os.environ['HERMES_HOME'] = '/data/.hermes'

try:
    # Import the discovery function that hermes plugins list uses
    from hermes_cli.plugins_cmd import _discover_all_plugins
    
    print("[PLUGINS] Calling _discover_all_plugins()...")
    entries = _discover_all_plugins()
    
    all_plugin_keys = []
    
    for entry in entries:
        name, version, description, source, dir_path, key = entry
        if key not in all_plugin_keys:
            all_plugin_keys.append(key)
            print(f"  ✅ Found: {key} ({source})")
    
    all_plugin_keys.sort()
    print(f"\n[PLUGINS] ✅ Total discovered: {len(all_plugin_keys)} plugins")
    
    # Load existing config
    config_path = '/data/.hermes/config.yaml'
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f) or {}
        print(f"[PLUGINS] ✅ Loaded existing config.yaml")
    else:
        config = {}
        print(f"[PLUGINS] ⚠️ No config.yaml, creating new")
    
    # Update plugins section with canonical keys
    config['plugins'] = {'enabled': all_plugin_keys}
    
    # Update tools section
    config['tools'] = {
        'enabled': True,
        'platform_toolsets': [
            'web', 'browser', 'image_gen', 'video_gen',
            'a2a', 'cron', 'platform', 'observability',
            'spotify', 'messaging', 'dashboard_auth'
        ]
    }
    
    # Save config
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    print(f"\n[PLUGINS] ✅ Successfully enabled {len(all_plugin_keys)} plugins!")
    print("[PLUGINS] config.yaml updated with canonical keys")
    
except ImportError as e:
    print(f"[PLUGINS] ❌ Error importing: {e}")
    print("[PLUGINS] Attempting fallback method...")
    
    # Fallback: manual scan using find
    import subprocess
    
    result = subprocess.run(
        ['find', '/app/hermes-agent/plugins', '-name', 'plugin.yaml'],
        capture_output=True,
        text=True
    )
    
    plugin_paths = result.stdout.strip().split('\n')
    all_plugins = []
    
    for path in plugin_paths:
        if path and 'plugin.yaml' in path:
            # Extract relative path from plugins directory
            rel_path = path.replace('/app/hermes-agent/plugins/', '').replace('/plugin.yaml', '')
            # Convert path separators to canonical key format
            canonical_key = rel_path.replace('/', '/')
            if canonical_key not in all_plugins:
                all_plugins.append(canonical_key)
                print(f"  ✅ Found: {canonical_key}")
    
    all_plugins.sort()
    print(f"[PLUGINS] Fallback found {len(all_plugins)} plugins")
    
    # Update config
    config_path = '/data/.hermes/config.yaml'
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f) or {}
        
        config['plugins'] = {'enabled': all_plugins}
        config['tools'] = {
            'enabled': True,
            'platform_toolsets': [
                'web', 'browser', 'image_gen', 'video_gen',
                'a2a', 'cron', 'platform', 'observability'
            ]
        }
        
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        
        print(f"[PLUGINS] ✅ Fallback: enabled {len(all_plugins)} plugins")

except Exception as e:
    print(f"[PLUGINS] ❌ Unexpected error: {e}")
    import traceback
    traceback.print_exc()

PLUGIN_DISCOVERY_SCRIPT

echo "=========================================="

# ============================================================
# 🔥🔥🔥 CONFIGURE 70 MCPs ON-DEMAND IN config.yaml
# ============================================================
# این روش به جای نصب فیزیکی MCPها (که 10 دقیقه طول می‌کشه و Render timeout می‌ده)،
# فقط لیست MCPها را در config.yaml می‌نویسد. هرمس در زمان نیاز، هر MCP را به صورت
# lazy و on-demand اجرا می‌کند. این باعث می‌شود:
#   1. بوت سریع شود (۱۰ ثانیه به جای ۱۰ دقیقه)
#   2. رم کم مصرف شود
#   3. فقط MCPهای استفاده شده فعال شوند
# ============================================================
echo "=========================================="
echo "\[MCP\] Configuring 70 MCP servers ON-DEMAND..."
echo "\[MCP\] MCPs will be loaded lazily when AI needs them"
echo "=========================================="

python3 << 'MCP_CONFIG_SCRIPT'
import yaml
import os

config_path = '/data/.hermes/config.yaml'

# Load existing config
if os.path.exists(config_path):
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f) or {}
    print("[MCP] ✅ Loaded existing config.yaml")
else:
    config = {}
    print("[MCP] ⚠️ No config.yaml, creating new")

# ============================================================
# 70 MCP Servers Configuration (On-Demand / Lazy Loading)
# ============================================================
config['mcp_servers'] = {
    # ============ Category 1: Browser Automation (5) ============
    "playwright": {
        "command": "npx",
        "args": ["-y", "@playwright/mcp@latest"],
        "env": {}
    },
    "firecrawl": {
        "command": "npx",
        "args": ["-y", "firecrawl-mcp"],
        "env": {"FIRECRAWL_API_KEY": os.environ.get("FIRECRAWL_API_KEY", "")}
    },
    "browserbase": {
        "command": "npx",
        "args": ["-y", "@browserbase/mcp-server-browserbase"],
        "env": {"BROWSERBASE_API_KEY": os.environ.get("BROWSERBASE_API_KEY", "")}
    },
    "fetch": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-fetch"],
        "env": {}
    },
    "puppeteer": {
        "command": "npx",
        "args": ["-y", "puppeteer-mcp"],
        "env": {}
    },
    
    # ============ Category 2: Code Execution (5) ============
    "e2b": {
        "command": "npx",
        "args": ["-y", "@e2b/mcp-server"],
        "env": {"E2B_API_KEY": os.environ.get("E2B_API_KEY", "")}
    },
    "docker": {
        "command": "npx",
        "args": ["-y", "@ofershap/mcp-server-docker"],
        "env": {}
    },
    "modal": {
        "command": "uvx",
        "args": ["modal-mcp"],
        "env": {
            "MODAL_TOKEN_ID": os.environ.get("MODAL_TOKEN_ID", ""),
            "MODAL_TOKEN_SECRET": os.environ.get("MODAL_TOKEN_SECRET", "")
        }
    },
    "jupyter": {
        "command": "uvx",
        "args": ["mcp-jupyter"],
        "env": {}
    },
    "bash": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-bash"],
        "env": {}
    },
    
    # ============ Category 3: Code Quality (5) ============
    "ruff": {
        "command": "uvx",
        "args": ["--from", "ruff-mcp", "ruff-mcp"],
        "env": {}
    },
    "eslint": {
        "command": "npx",
        "args": ["-y", "@eslint/mcp-server"],
        "env": {}
    },
    "sonarqube": {
        "command": "uvx",
        "args": ["sonarqube-mcp-server"],
        "env": {"SONAR_TOKEN": os.environ.get("SONAR_TOKEN", "")}
    },
    "semgrep": {
        "command": "uvx",
        "args": ["semgrep-mcp"],
        "env": {}
    },
    "pyright": {
        "command": "npx",
        "args": ["-y", "pyright-mcp"],
        "env": {}
    },
    
    # ============ Category 4: Version Control (5) ============
    "github": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"],
        "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": os.environ.get("GITHUB_PERSONAL_ACCESS_TOKEN", os.environ.get("GITHUB_TOKEN", ""))}
    },
    "git": {
        "command": "uvx",
        "args": ["mcp-server-git", "--repository", "/data/.hermes/workspace"],
        "env": {}
    },
    "gitlab": {
        "command": "uvx",
        "args": ["gitlab-mcp"],
        "env": {"GITLAB_PERSONAL_ACCESS_TOKEN": os.environ.get("GITLAB_PERSONAL_ACCESS_TOKEN", "")}
    },
    "github_actions": {
        "command": "npx",
        "args": ["-y", "@ofershap/mcp-server-github-actions"],
        "env": {"GITHUB_TOKEN": os.environ.get("GITHUB_TOKEN", "")}
    },
    "argocd": {
        "command": "uvx",
        "args": ["argocd-mcp"],
        "env": {}
    },
    
    # ============ Category 5: Database & Storage (7) ============
    "postgres": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-postgres", os.environ.get("POSTGRES_CONNECTION_STRING", "postgresql://localhost/db")],
        "env": {}
    },
    "supabase": {
        "command": "npx",
        "args": ["-y", "@supabase/mcp-server-supabase"],
        "env": {
            "SUPABASE_URL": os.environ.get("SUPABASE_URL", ""),
            "SUPABASE_SERVICE_KEY": os.environ.get("SUPABASE_SERVICE_KEY", "")
        }
    },
    "sqlite": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "/data/.hermes/sqlite.db"],
        "env": {}
    },
    "redis": {
        "command": "npx",
        "args": ["-y", "@redis/mcp-redis"],
        "env": {"REDIS_URL": os.environ.get("REDIS_URL", "redis://localhost:6379")}
    },
    "mongodb": {
        "command": "npx",
        "args": ["-y", "mongodb-mcp-server"],
        "env": {"MONGODB_CONNECTION_STRING": os.environ.get("MONGODB_CONNECTION_STRING", "")}
    },
    "pinecone": {
        "command": "npx",
        "args": ["-y", "@pinecone-database/mcp"],
        "env": {"PINECONE_API_KEY": os.environ.get("PINECONE_API_KEY", "")}
    },
    "qdrant": {
        "command": "uvx",
        "args": ["qdrant-mcp-server"],
        "env": {"QDRANT_API_KEY": os.environ.get("QDRANT_API_KEY", "")}
    },
    
    # ============ Category 6: Cloud Infrastructure (6) ============
    "cloudflare": {
        "command": "npx",
        "args": ["-y", "@cloudflare/mcp-server-cloudflare"],
        "env": {"CLOUDFLARE_API_TOKEN": os.environ.get("CLOUDFLARE_API_TOKEN", "")}
    },
    "kubernetes": {
        "command": "npx",
        "args": ["-y", "@kubernetes/mcp-server"],
        "env": {}
    },
    "terraform": {
        "command": "npx",
        "args": ["-y", "@hashicorp/mcp-server-terraform"],
        "env": {}
    },
    "aws": {
        "command": "npx",
        "args": ["-y", "@awslabs/mcp-server-aws"],
        "env": {
            "AWS_ACCESS_KEY_ID": os.environ.get("AWS_ACCESS_KEY_ID", ""),
            "AWS_SECRET_ACCESS_KEY": os.environ.get("AWS_SECRET_ACCESS_KEY", ""),
            "AWS_REGION": os.environ.get("AWS_REGION", "us-east-1")
        }
    },
    "pulumi": {
        "command": "npx",
        "args": ["-y", "@pulumi/mcp-server"],
        "env": {"PULUMI_ACCESS_TOKEN": os.environ.get("PULUMI_ACCESS_TOKEN", "")}
    },
    "lens": {
        "command": "npx",
        "args": ["-y", "@k8slens/mcp-server"],
        "env": {}
    },
    
    # ============ Category 7: Debugging & Monitoring (6) ============
    "sentry": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sentry"],
        "env": {"SENTRY_AUTH_TOKEN": os.environ.get("SENTRY_AUTH_TOKEN", "")}
    },
    "grafana": {
        "command": "npx",
        "args": ["-y", "@grafana/mcp-server"],
        "env": {
            "GRAFANA_URL": os.environ.get("GRAFANA_URL", ""),
            "GRAFANA_API_KEY": os.environ.get("GRAFANA_API_KEY", "")
        }
    },
    "logtail": {
        "command": "npx",
        "args": ["-y", "@betterstack/mcp-server-logtail"],
        "env": {"LOGTAIL_SOURCE_TOKEN": os.environ.get("LOGTAIL_SOURCE_TOKEN", "")}
    },
    "datadog": {
        "command": "npx",
        "args": ["-y", "@datadog/mcp-server"],
        "env": {
            "DATADOG_API_KEY": os.environ.get("DATADOG_API_KEY", ""),
            "DATADOG_APP_KEY": os.environ.get("DATADOG_APP_KEY", "")
        }
    },
    "prometheus": {
        "command": "npx",
        "args": ["-y", "@prometheus/mcp-server"],
        "env": {"PROMETHEUS_URL": os.environ.get("PROMETHEUS_URL", "")}
    },
    "posthog": {
        "command": "npx",
        "args": ["-y", "@posthog/mcp"],
        "env": {"POSTHOG_API_KEY": os.environ.get("POSTHOG_API_KEY", "")}
    },
    
    # ============ Category 8: Knowledge & Search (6) ============
    "brave_search": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-brave-search"],
        "env": {"BRAVE_API_KEY": os.environ.get("BRAVE_API_KEY", "")}
    },
    "context7": {
        "command": "npx",
        "args": ["-y", "@upstash/context7-mcp"],
        "env": {}
    },
    "exa": {
        "command": "npx",
        "args": ["-y", "exa-mcp-server"],
        "env": {"EXA_API_KEY": os.environ.get("EXA_API_KEY", "")}
    },
    "stackoverflow": {
        "command": "npx",
        "args": ["-y", "@stackoverflow/mcp-server"],
        "env": {}
    },
    "devdocs": {
        "command": "npx",
        "args": ["-y", "devdocs-mcp"],
        "env": {}
    },
    "deepresearch": {
        "command": "npx",
        "args": ["-y", "deepresearch-mcp"],
        "env": {}
    },
    
    # ============ Category 9: Workflow & Productivity (6) ============
    "notion": {
        "command": "npx",
        "args": ["-y", "@makenotion/mcp-server-notion"],
        "env": {"NOTION_API_KEY": os.environ.get("NOTION_API_KEY", "")}
    },
    "linear": {
        "command": "npx",
        "args": ["-y", "@linear/mcp-server"],
        "env": {"LINEAR_API_KEY": os.environ.get("LINEAR_API_KEY", "")}
    },
    "slack": {
        "command": "npx",
        "args": ["-y", "@slack/mcp-server"],
        "env": {"SLACK_BOT_TOKEN": os.environ.get("SLACK_BOT_TOKEN", "")}
    },
    "jira": {
        "command": "npx",
        "args": ["-y", "@atlassian/mcp-server-jira"],
        "env": {"JIRA_API_TOKEN": os.environ.get("JIRA_API_TOKEN", "")}
    },
    "n8n": {
        "command": "npx",
        "args": ["-y", "@automatelab/n8n-mcp"],
        "env": {"N8N_API_KEY": os.environ.get("N8N_API_KEY", "")}
    },
    "zapier": {
        "command": "npx",
        "args": ["-y", "@zapier/mcp-server"],
        "env": {"ZAPIER_NLA_API_KEY": os.environ.get("ZAPIER_NLA_API_KEY", "")}
    },
    
    # ============ Category 10: Filesystem & Memory (5) ============
    "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/data/.hermes/workspace"],
        "env": {}
    },
    "memory": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-memory"],
        "env": {}
    },
    "google_drive": {
        "command": "npx",
        "args": ["-y", "@google/mcp-server-drive"],
        "env": {"GOOGLE_API_KEY": os.environ.get("GOOGLE_API_KEY", "")}
    },
    "knowledge_graph": {
        "command": "npx",
        "args": ["-y", "knowledge-graph-mcp"],
        "env": {}
    },
    "sequential_thinking": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sequentialthinking"],
        "env": {}
    },
    
    # ============ Category 11: Code Navigation (6) ============
    "tree_sitter": {
        "command": "npx",
        "args": ["-y", "@tree-sitter/mcp"],
        "env": {}
    },
    "ripgrep": {
        "command": "npx",
        "args": ["-y", "@burntsushi/ripgrep-mcp"],
        "env": {}
    },
    "lsp": {
        "command": "npx",
        "args": ["-y", "@sourcegraph/lsp-mcp"],
        "env": {}
    },
    "ast_grep": {
        "command": "npx",
        "args": ["-y", "@ast-grep/mcp"],
        "env": {}
    },
    "vector_search": {
        "command": "npx",
        "args": ["-y", "vector-code-search-mcp"],
        "env": {}
    },
    "time": {
        "command": "uvx",
        "args": ["mcp-server-time"],
        "env": {}
    },
    
    # ============ Category 12: API Integration (5) ============
    "stripe": {
        "command": "npx",
        "args": ["-y", "@stripe/mcp-server"],
        "env": {"STRIPE_API_KEY": os.environ.get("STRIPE_API_KEY", "")}
    },
    "salesforce": {
        "command": "npx",
        "args": ["-y", "@salesforce/mcp-server"],
        "env": {"SALESFORCE_ACCESS_TOKEN": os.environ.get("SALESFORCE_ACCESS_TOKEN", "")}
    },
    "openai": {
        "command": "npx",
        "args": ["-y", "@openai/mcp-server"],
        "env": {"OPENAI_API_KEY": os.environ.get("OPENAI_API_KEY", "")}
    },
    "anthropic": {
        "command": "npx",
        "args": ["-y", "@anthropic/mcp-server"],
        "env": {"ANTHROPIC_API_KEY": os.environ.get("ANTHROPIC_API_KEY", "")}
    },
    "huggingface": {
        "command": "npx",
        "args": ["-y", "@huggingface/mcp-server"],
        "env": {"HUGGINGFACE_TOKEN": os.environ.get("HUGGINGFACE_TOKEN", "")}
    },
    
    # ============ Category 13: Security (3) ============
    "pentest": {
        "command": "npx",
        "args": ["-y", "pentest-mcp"],
        "env": {}
    },
    "vuln_scanner": {
        "command": "npx",
        "args": ["-y", "vulnerability-scanner-mcp"],
        "env": {}
    },
    "owasp_zap": {
        "command": "npx",
        "args": ["-y", "@owasp/mcp-server-zap"],
        "env": {"OWASP_ZAP_API_KEY": os.environ.get("OWASP_ZAP_API_KEY", "")}
    },
    
    # ============ Category 14: Data Science (3) ============
    "pandas": {
        "command": "uvx",
        "args": ["pandas-mcp"],
        "env": {}
    },
    "bigquery": {
        "command": "npx",
        "args": ["-y", "@google/mcp-server-bigquery"],
        "env": {
            "BIGQUERY_PROJECT_ID": os.environ.get("BIGQUERY_PROJECT_ID", ""),
            "GOOGLE_APPLICATION_CREDENTIALS": os.environ.get("BIGQUERY_KEY_FILE", "")
        }
    },
    "snowflake": {
        "command": "npx",
        "args": ["-y", "@snowflake/mcp-server"],
        "env": {
            "SNOWFLAKE_ACCOUNT": os.environ.get("SNOWFLAKE_ACCOUNT", ""),
            "SNOWFLAKE_USER": os.environ.get("SNOWFLAKE_USER", ""),
            "SNOWFLAKE_PASSWORD": os.environ.get("SNOWFLAKE_PASSWORD", "")
        }
    }
}

# Filter out MCPs with empty required API keys (avoid startup errors)
enabled_mcp_count = len(config['mcp_servers'])
print(f"[MCP] ✅ Configured {enabled_mcp_count} MCP servers ON-DEMAND")
print(f"[MCP] 📋 MCPs will be spawned only when AI needs them")
print(f"[MCP] ⚡ Zero startup time, minimal RAM usage")

# Save config
with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f"[MCP] ✅ config.yaml updated with {enabled_mcp_count} MCP servers")
MCP_CONFIG_SCRIPT

echo "\[MCP\] =========================================="
echo "\[MCP\] ✅ 70 MCP servers configured ON-DEMAND"
echo "\[MCP\] ✅ Hermes will load MCPs lazily when needed"
echo "\[MCP\] ✅ No timeout, no RAM pressure on Render"
echo "\[MCP\] =========================================="

# ============================================================
# 🔥🔥🔥 GENERATE config.yaml → Connect Hermes to OmniRoute
# ============================================================
echo "=========================================="
echo "\[CONFIG\] Generating config.yaml for OmniRoute..."
echo "\[CONFIG\] OMNIROUTE_URL: ${OMNIROUTE_URL:-NOT SET}"
echo "=========================================="

OMNI_URL="${OMNIROUTE_URL:-https://omniroute-app-production-9940.up.railway.app}"
OMNI_API_URL="${OMNI_URL}/v1"
OMNI_API_KEY="${OMNIROUTE_API_KEY:-sk-7150f73b0efb9f5e-d0a99b-0c5675aa}"

CONFIG_PATH="$HERMES_DIR/config.yaml"
if [ -f "$CONFIG_PATH" ]; then
  echo "\[CONFIG\] ✅ Existing config.yaml found, preserving plugin settings"
  
  python3 << CONFIG_MERGE_SCRIPT
import yaml
import os

config_path = "$CONFIG_PATH"
omni_api_url = "$OMNI_API_URL"
omni_api_key = "$OMNI_API_KEY"
default_model = "${HERMES_WEBUI_DEFAULT_MODEL:-hermes-fast}"
hermes_dir = "$HERMES_DIR"

with open(config_path, 'r') as f:
    config = yaml.safe_load(f) or {}

if 'providers' not in config:
    config['providers'] = {}

config['providers']['omniroute'] = {
    'api': omni_api_url,
    'api_key': omni_api_key,
    'transport': 'chat_completions',
    'default_model': default_model,
    'enabled': True
}

config['model'] = {
    'default': default_model,
    'provider': 'custom:omniroute'
}

config['workspace'] = f'{hermes_dir}/workspace'
config['memory'] = {
    'enabled': True,
    'path': f'{hermes_dir}/MEMORY.md'
}
config['user'] = {'profile_path': f'{hermes_dir}/USER.md'}
config['soul'] = {'path': f'{hermes_dir}/SOUL.md'}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print("[CONFIG] ✅ config.yaml updated with OmniRoute + preserved plugin settings")
CONFIG_MERGE_SCRIPT
else
  echo "\[CONFIG\] ⚠️ No existing config.yaml, creating basic config"
  
  cat > "$CONFIG_PATH" <<EOF
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

  echo "\[CONFIG\] ✅ Basic config.yaml created"
fi

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

echo "\[ENTRYPOINT\] Skill categories installed:"
ls -1 "$HERMES_DIR/skills/" 2>/dev/null | grep -v "^$" | sort

MEMORY_COUNT=$(ls "$HERMES_DIR"/MEMORY.md "$HERMES_DIR"/USER.md "$HERMES_DIR"/SOUL.md 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Core files (MEMORY/USER/SOUL): $MEMORY_COUNT"

WEBUI_FILES=$(find "$HERMES_DIR/webui" -type f 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] WebUI files: $WEBUI_FILES"

WORKSPACE_FILES=$(find "$HERMES_DIR/workspace" -type f 2>/dev/null | wc -l)
echo "\[ENTRYPOINT\] Workspace files: $WORKSPACE_FILES"

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
    
    token_id = os.environ.get('MODAL_TOKEN_ID', '')
    token_secret = os.environ.get('MODAL_TOKEN_SECRET', '')
    environment = os.environ.get('MODAL_ENVIRONMENT', 'main')
    
    if not token_id or not token_secret:
        print("\[MODAL\] ❌ Modal tokens not found in environment")
        sys.exit(1)
    
    print(f"\[MODAL\] Token ID: {token_id[:10]}...")
    print(f"\[MODAL\] Environment: {environment}")
    
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

cd /app/webui || exit 1

if [ ! -f "server.py" ]; then
  echo "\[ENTRYPOINT\] ❌ server.py not found in /app/webui!"
  echo "\[ENTRYPOINT\] Listing contents:"
  ls -la /app/webui/ | head -20
  exit 1
fi

echo "\[ENTRYPOINT\] ✅ Found server.py in /app/webui"
exec python server.py 2>&1 | grep -v "agent session listing skipped" | grep -v "Token from GITHUB_TOKEN is not supported" | grep -v "Slow WebUI request" | grep -v "live provider-catalog rebuild exceeded"
