#!/usr/bin/env python3
"""
Qwen OAuth Proxy - OpenAI Compatible Endpoint for Hermes
This proxy forwards requests to Qwen with proper OAuth headers
"""

import json
import os
import time
from pathlib import Path
from flask import Flask, request, jsonify, Response
import requests
import threading

app = Flask(__name__)

# Qwen OAuth constants
TOKEN_URL = "https://chat.qwen.ai/api/v1/oauth2/token"
CLIENT_ID = "f0304373b74a44d2b584a3fb70ca9e56"

# Token cache
token_cache = {
    "access_token": None,
    "refresh_token": None,
    "expires_at": 0,
    "base_url": "https://portal.qwen.ai/v1",
    "resource_url": "portal.qwen.ai"
}

def load_tokens():
    """Load tokens from environment variables or Qwen CLI storage"""
    # First try environment variables
    access_token = os.environ.get("QWEN_ACCESS_TOKEN")
    refresh_token = os.environ.get("QWEN_REFRESH_TOKEN")
    resource_url = os.environ.get("QWEN_RESOURCE_URL", "portal.qwen.ai")
    
    if access_token and refresh_token:
        token_cache["access_token"] = access_token
        token_cache["refresh_token"] = refresh_token
        token_cache["resource_url"] = resource_url
        token_cache["base_url"] = f"https://{resource_url}/v1"
        token_cache["expires_at"] = time.time() + 3600  # Assume 1 hour validity
        print(f"✅ Loaded tokens from environment variables")
        print(f"✅ Base URL: {token_cache['base_url']}")
        return True
    
    # Fallback: try Qwen CLI storage
    oauth_file = Path.home() / ".qwen" / "oauth_creds.json"
    if oauth_file.exists():
        try:
            with open(oauth_file) as f:
                data = json.load(f)
                token_cache["access_token"] = data.get("access_token")
                token_cache["refresh_token"] = data.get("refresh_token")
                token_cache["expires_at"] = time.time() + data.get("expires_in", 3600)
                if "resource_url" in data:
                    token_cache["resource_url"] = data["resource_url"]
                    token_cache["base_url"] = f"https://{data['resource_url']}/v1"
                print(f"✅ Loaded tokens from {oauth_file}")
                print(f"✅ Base URL: {token_cache['base_url']}")
                return True
        except Exception as e:
            print(f"❌ Error loading tokens from {oauth_file}: {e}")
    
    # Try alternative location
    alt_file = Path.home() / ".local" / "share" / "opencode" / "qwen-refresh.json"
    if alt_file.exists():
        try:
            with open(alt_file) as f:
                data = json.load(f)
                token_cache["refresh_token"] = data.get("refresh_token")
                print(f"✅ Loaded refresh token from {alt_file}")
                if refresh_token():
                    return True
        except Exception as e:
            print(f"❌ Error loading tokens from {alt_file}: {e}")
    
    return False

def refresh_token():
    """Refresh the access token using refresh token"""
    if not token_cache["refresh_token"]:
        print("❌ No refresh token available")
        return False
    
    try:
        print("🔄 Refreshing token...")
        response = requests.post(
            TOKEN_URL,
            data={
                "grant_type": "refresh_token",
                "client_id": CLIENT_ID,
                "refresh_token": token_cache["refresh_token"]
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=30
        )
        
        if response.ok:
            data = response.json()
            token_cache["access_token"] = data["access_token"]
            if "refresh_token" in data:
                token_cache["refresh_token"] = data["refresh_token"]
            token_cache["expires_at"] = time.time() + data.get("expires_in", 3600)
            if "resource_url" in data:
                token_cache["resource_url"] = data["resource_url"]
                token_cache["base_url"] = f"https://{data['resource_url']}/v1"
            print(f"✅ Token refreshed successfully")
            print(f"✅ Base URL: {token_cache['base_url']}")
            return True
        else:
            print(f"❌ Token refresh failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"❌ Token refresh error: {e}")
    
    return False

def get_valid_token():
    """Get a valid access token, refreshing if needed"""
    # Check if token is expired or about to expire (within 60 seconds)
    if not token_cache["access_token"] or time.time() >= token_cache["expires_at"] - 60:
        if not refresh_token():
            # Try loading from file again
            if not load_tokens():
                return None
    return token_cache["access_token"]

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """OpenAI-compatible chat completions endpoint"""
    token = get_valid_token()
    if not token:
        return jsonify({"error": "No valid token available. Please set QWEN_ACCESS_TOKEN and QWEN_REFRESH_TOKEN in environment."}), 401
    
    # Forward to Qwen
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-DashScope-AuthType": "qwen-oauth",
        "X-DashScope-CacheControl": "enable",
        "X-DashScope-UserAgent": "QwenCode/0.11.1 (linux; x64)",
        "User-Agent": "QwenCode/0.11.1 (linux; x64)"
    }
    
    target_url = f"{token_cache['base_url']}/chat/completions"
    
    try:
        # Check if streaming is requested
        stream = request.json.get("stream", False)
        
        response = requests.post(
            target_url,
            json=request.json,
            headers=headers,
            stream=stream,
            timeout=300
        )
        
        # Handle token expiration
        if response.status_code == 401:
            print("⚠️ Token expired, refreshing...")
            if refresh_token():
                token = token_cache["access_token"]
                headers["Authorization"] = f"Bearer {token}"
                response = requests.post(
                    target_url,
                    json=request.json,
                    headers=headers,
                    stream=stream,
                    timeout=300
                )
        
        if stream:
            # Return streaming response
            return Response(
                response.iter_content(chunk_size=1024),
                status=response.status_code,
                content_type=response.headers.get('content-type', 'text/event-stream')
            )
        else:
            # Return regular response
            return Response(
                response.content,
                status=response.status_code,
                content_type=response.headers.get('content-type', 'application/json')
            )
            
    except Exception as e:
        print(f"❌ Request error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/v1/models', methods=['GET'])
def list_models():
    """List available models"""
    return jsonify({
        "object": "list",
        "data": [
            {
                "id": "qwen3-coder-plus",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen"
            },
            {
                "id": "qwen-plus",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen"
            },
            {
                "id": "qwen-max",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen"
            }
        ]
    })

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        "status": "ok",
        "has_token": token_cache["access_token"] is not None,
        "has_refresh_token": token_cache["refresh_token"] is not None,
        "base_url": token_cache["base_url"],
        "expires_in": max(0, int(token_cache["expires_at"] - time.time()))
    })

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        "message": "Qwen OAuth Proxy for Hermes Agent",
        "version": "1.0.0",
        "endpoints": {
            "/v1/chat/completions": "OpenAI-compatible chat API",
            "/v1/models": "List available models",
            "/health": "Health check"
        }
    })

if __name__ == '__main__':
    print("=" * 60)
    print("Qwen OAuth Proxy Starting...")
    print("=" * 60)
    
    proxy_port = int(os.environ.get("QWEN_PROXY_PORT", 8080))
    
    if load_tokens():
        print(f"✅ Proxy ready on port {proxy_port}")
        print(f"✅ Forwarding to: {token_cache['base_url']}")
    else:
        print("⚠️  No tokens found!")
        print("⚠️  Please set QWEN_ACCESS_TOKEN and QWEN_REFRESH_TOKEN in environment")
        print("⚠️  Or run auth-extract.sh on your local machine first")
    
    app.run(host='0.0.0.0', port=proxy_port, debug=False)
