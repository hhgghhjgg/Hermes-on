#!/bin/bash
# ============================================================
# Qwen OAuth Token Extractor
# این اسکریپت را روی کامپیوتر لوکال خودت اجرا کن (نه روی Render)
# بعد توکن‌ها را در .env یا Environment Variables کپی کن
# ============================================================

set -e

echo "=========================================="
echo "Qwen OAuth Token Extractor"
echo "=========================================="
echo ""
echo "⚠️  این اسکریپت را روی کامپیوتر لوکال خودت اجرا کن!"
echo "⚠️  NOT on Render - you need a browser to authenticate"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed!"
    echo "Please install Node.js first: https://nodejs.org/"
    exit 1
fi

echo "✅ Node.js version: $(node --version)"
echo ""

# Check if Qwen CLI exists
if command -v qwen &> /dev/null; then
    echo "✅ Qwen CLI found"
    QWEN_PATH=$(which qwen)
    echo "   Path: $QWEN_PATH"
else
    echo "📦 Qwen CLI not found. Installing..."
    echo ""
    
    # Try npm install
    if command -v npm &> /dev/null; then
        echo "Installing via npm..."
        npm install -g @qwen-code/qwen-code
        
        if command -v qwen &> /dev/null; then
            echo "✅ Qwen CLI installed successfully"
        else
            echo "❌ Installation failed"
            exit 1
        fi
    else
        echo "❌ npm not found. Please install Node.js first."
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "Starting Qwen OAuth Authentication"
echo "=========================================="
echo ""
echo "📝 Instructions:"
echo "1. Your browser will open automatically"
echo "2. Log in with your Qwen.ai account (free account works)"
echo "3. Approve the authorization request"
echo "4. Come back here when it's done"
echo ""
echo "Press ENTER to start..."
read

# Run interactive auth
echo ""
echo "🔄 Running Qwen auth..."
echo ""

qwen auth qwen-oauth

# Wait a moment for file to be written
sleep 3

echo ""
echo "=========================================="
echo "Token Extraction"
echo "=========================================="
echo ""

# Extract tokens from primary location
OAUTH_FILE="$HOME/.qwen/oauth_creds.json"
if [ -f "$OAUTH_FILE" ]; then
    echo "✅ Tokens found at: $OAUTH_FILE"
    echo ""
    
    # Extract using Python
    echo "=========================================="
    echo "📋 COPY THESE VALUES TO YOUR .env FILE:"
    echo "=========================================="
    echo ""
    
    python3 << 'PYEOF'
import json
import sys

oauth_file = "/home/user/.qwen/oauth_creds.json"
try:
    # Try to find the actual path
    import os
    from pathlib import Path
    oauth_file = str(Path.home() / ".qwen" / "oauth_creds.json")
    
    with open(oauth_file, 'r') as f:
        data = json.load(f)
    
    access_token = data.get('access_token', '')
    refresh_token = data.get('refresh_token', '')
    resource_url = data.get('resource_url', 'portal.qwen.ai')
    
    print("QWEN_ACCESS_TOKEN=" + access_token)
    print("QWEN_REFRESH_TOKEN=" + refresh_token)
    print("QWEN_RESOURCE_URL=" + resource_url)
    print("")
    print("# Add these to your .env file or Render Environment Variables")
    
except Exception as e:
    print(f"Error reading tokens: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    
    echo ""
    echo "=========================================="
    echo "✅ SUCCESS!"
    echo "=========================================="
    echo ""
    echo "Now:"
    echo "1. Copy the 3 lines above"
    echo "2. Paste them into your .env file"
    echo "3. Or add them to Render Environment Variables"
    echo "4. Restart your Render service"
    echo ""
    
else
    echo "❌ Token file not found at: $OAUTH_FILE"
    echo ""
    echo "Trying alternative locations..."
    echo ""
    
    # Try alternative location (OpenCode format)
    ALT_FILE="$HOME/.local/share/opencode/qwen-refresh.json"
    if [ -f "$ALT_FILE" ]; then
        echo "✅ Found alternative token file: $ALT_FILE"
        echo ""
        cat "$ALT_FILE"
    else
        echo "❌ No token files found"
        echo ""
        echo "Possible locations checked:"
        echo "  - $OAUTH_FILE"
        echo "  - $ALT_FILE"
        echo ""
        echo "Please check if authentication completed successfully"
    fi
fi

echo ""
echo "=========================================="
echo "Troubleshooting"
echo "=========================================="
echo ""
echo "If you see errors:"
echo "1. Make sure you approved the authorization in your browser"
echo "2. Try running: qwen auth qwen-oauth"
echo "3. Check your internet connection"
echo ""
echo "For manual token extraction:"
echo "  Visit: https://chat.qwen.ai"
echo "  Log in and check browser DevTools > Network tab"
echo "  Look for oauth/token requests"
echo ""
