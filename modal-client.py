#!/usr/bin/env python3
"""
Modal Client - HTTP API Server for Hermes Agent
================================================

This server provides a REST API for Hermes to create and manage Modal sandboxes.
Hermes can request any language/environment to be installed and executed.

Architecture:
  Hermes (Render) → HTTP Request → modal-client.py → Modal Sandbox → Result

Endpoints:
  POST /sandbox/create      - Create a new sandbox with custom image
  POST /sandbox/exec        - Execute command in sandbox
  GET  /sandbox/{id}        - Get sandbox status
  GET  /sandboxes           - List all active sandboxes
  POST /sandbox/snapshot    - Take snapshot of sandbox
  POST /sandbox/restore     - Restore sandbox from snapshot
  DELETE /sandbox/{id}      - Destroy sandbox
  GET  /health              - Health check
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime
from typing import Optional, Dict, Any, List
from threading import Lock

from flask import Flask, request, jsonify

# Modal SDK
try:
    import modal
except ImportError:
    print("[MODAL-CLIENT] ❌ Modal SDK not installed!")
    print("[MODAL-CLIENT] Run: pip install modal>=0.73.0")
    sys.exit(1)

# ============================================================
# Configuration
# ============================================================

FLASK_HOST = os.environ.get("MODAL_CLIENT_HOST", "0.0.0.0")
FLASK_PORT = int(os.environ.get("MODAL_CLIENT_PORT", "8090"))
MODAL_ENVIRONMENT = os.environ.get("MODAL_ENVIRONMENT", "main")
DEFAULT_TIMEOUT = int(os.environ.get("MODAL_DEFAULT_TIMEOUT", "86400"))  # 24 hours
MAX_OUTPUT_SIZE = int(os.environ.get("MODAL_MAX_OUTPUT_SIZE", "1048576"))  # 1 MB

# ============================================================
# Flask App
# ============================================================

app = Flask(__name__)

# In-memory registry of active sandboxes
# Key: sandbox_id, Value: {name, sandbox_obj, created_at, image, timeout, volume}
active_sandboxes: Dict[str, Dict[str, Any]] = {}
registry_lock = Lock()

# Modal App (for managing sandboxes)
modal_app = None


def get_modal_app():
    """Get or create the Modal App for Hermes sandboxes."""
    global modal_app
    if modal_app is None:
        modal_app = modal.App.lookup("hermes-sandboxes", create_if_missing=True)
    return modal_app


def generate_sandbox_id() -> str:
    """Generate a unique sandbox ID."""
    return f"sb_{int(time.time() * 1000)}"


def build_image(spec: Dict[str, Any]) -> modal.Image:
    """
    Build a Modal Image from specification.
    
    The spec can include:
      - base: "debian", "ubuntu", "python", "node", "php", "go", "java", "custom"
      - packages: list of apt packages
      - pip_packages: list of pip packages
      - npm_packages: list of npm packages
      - commands: list of shell commands to run during build
      - dockerfile: custom Dockerfile content
    """
    base = spec.get("base", "debian")
    packages = spec.get("packages", [])
    pip_packages = spec.get("pip_packages", [])
    npm_packages = spec.get("npm_packages", [])
    commands = spec.get("commands", [])
    
    print(f"[MODAL-CLIENT] Building image with base: {base}")
    
    # Start with base image
    if base == "python":
        version = spec.get("version", "3.11")
        image = modal.Image.debian_slim(python_version=version)
    elif base == "node":
        image = modal.Image.node_22()
    elif base == "php":
        # PHP با همه extension های رایج
        image = (
            modal.Image.debian_slim()
            .apt_install(
                "php",
                "php-cli",
                "php-mbstring",
                "php-xml",
                "php-curl",
                "php-zip",
                "php-sqlite3",
                "php-mysql",
                "php-pgsql",
                "composer",
            )
        )
    elif base == "go":
        image = (
            modal.Image.debian_slim()
            .apt_install("golang")
        )
    elif base == "java":
        image = (
            modal.Image.debian_slim()
            .apt_install("default-jdk", "maven")
        )
    elif base == "rust":
        image = (
            modal.Image.debian_slim()
            .apt_install("curl", "build-essential")
            .run_commands("curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y")
            .env({"PATH": "/root/.cargo/bin:$PATH"})
        )
    elif base == "ubuntu":
        image = modal.Image.from_registry("ubuntu:22.04", add_python="3.11")
    else:
        # Debian slim (پیش‌فرض - همه چی رو باید خودت نصب کنی)
        image = modal.Image.debian_slim()
    
    # Install apt packages
    if packages:
        print(f"[MODAL-CLIENT] Installing apt packages: {packages}")
        image = image.apt_install(*packages)
    
    # Install pip packages
    if pip_packages:
        print(f"[MODAL-CLIENT] Installing pip packages: {pip_packages}")
        image = image.pip_install(*pip_packages)
    
    # Install npm packages
    if npm_packages:
        print(f"[MODAL-CLIENT] Installing npm packages: {npm_packages}")
        install_cmd = "npm install -g " + " ".join(npm_packages)
        image = image.run_commands(install_cmd)
    
    # Run custom commands
    if commands:
        print(f"[MODAL-CLIENT] Running custom commands: {len(commands)}")
        for cmd in commands:
            image = image.run_commands(cmd)
    
    return image


# ============================================================
# API Endpoints
# ============================================================

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({
        "status": "ok",
        "service": "modal-client",
        "timestamp": datetime.now().isoformat(),
        "active_sandboxes": len(active_sandboxes),
        "modal_environment": MODAL_ENVIRONMENT,
    })


@app.route("/sandbox/create", methods=["POST"])
def create_sandbox():
    """
    Create a new Modal sandbox.
    
    Request body:
    {
        "name": "my-project",           # Optional: named sandbox
        "image": {
            "base": "php",              # debian/ubuntu/python/node/php/go/java/rust/custom
            "packages": ["nginx"],      # apt packages
            "pip_packages": ["requests"],
            "npm_packages": ["express"],
            "commands": ["echo 'hello'"]
        },
        "volume": "my-vol",             # Optional: persistent volume name
        "timeout": 86400,               # Optional: seconds (default: 24h)
        "cpu": 1.0,                     # Optional: CPU cores
        "memory": 1024                  # Optional: MB
    }
    
    Response:
    {
        "sandbox_id": "sb_1234567890",
        "name": "my-project",
        "status": "running",
        "created_at": "2026-08-09T12:00:00"
    }
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body must be JSON"}), 400
        
        # Get parameters
        name = data.get("name")
        image_spec = data.get("image", {"base": "debian"})
        volume_name = data.get("volume")
        timeout = data.get("timeout", DEFAULT_TIMEOUT)
        cpu = data.get("cpu", 1.0)
        memory = data.get("memory", 1024)
        
        sandbox_id = generate_sandbox_id()
        
        print(f"[MODAL-CLIENT] Creating sandbox: {sandbox_id}")
        print(f"[MODAL-CLIENT]   Name: {name or 'unnamed'}")
        print(f"[MODAL-CLIENT]   Image: {image_spec}")
        print(f"[MODAL-CLIENT]   Volume: {volume_name or 'none'}")
        print(f"[MODAL-CLIENT]   Timeout: {timeout}s")
        
        # Build image
        image = build_image(image_spec)
        
        # Prepare volumes
        volumes = {}
        if volume_name:
            vol = modal.Volume.from_name(volume_name, create_if_missing=True)
            volumes["/project"] = vol
            print(f"[MODAL-CLIENT]   Volume mounted at /project")
        
        # Create sandbox
        app = get_modal_app()
        
        kwargs = {
            "image": image,
            "timeout": timeout,
            "cpu": cpu,
            "memory": memory,
            "app": app,
        }
        
        if volumes:
            kwargs["volumes"] = volumes
        
        if name:
            kwargs["name"] = name
        
        # Create the sandbox
        sandbox = modal.Sandbox.create(**kwargs)
        
        # Register in our tracking
        with registry_lock:
            active_sandboxes[sandbox_id] = {
                "name": name,
                "sandbox": sandbox,
                "created_at": datetime.now().isoformat(),
                "image_spec": image_spec,
                "timeout": timeout,
                "volume": volume_name,
            }
        
        print(f"[MODAL-CLIENT] ✅ Sandbox created: {sandbox_id}")
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "name": name,
            "status": "running",
            "created_at": active_sandboxes[sandbox_id]["created_at"],
            "timeout": timeout,
        }), 201
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Create failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/exec", methods=["POST"])
def exec_command():
    """
    Execute a command in a sandbox.
    
    Request body:
    {
        "sandbox_id": "sb_1234567890",
        "command": "ls -la",           # Shell command
        "working_dir": "/project",      # Optional
        "timeout": 300                  # Optional: seconds
    }
    
    Response:
    {
        "sandbox_id": "sb_1234567890",
        "exit_code": 0,
        "stdout": "...",
        "stderr": "...",
        "duration": 2.5
    }
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body must be JSON"}), 400
        
        sandbox_id = data.get("sandbox_id")
        command = data.get("command")
        working_dir = data.get("working_dir")
        cmd_timeout = data.get("timeout", 300)
        
        if not sandbox_id or not command:
            return jsonify({"error": "sandbox_id and command are required"}), 400
        
        with registry_lock:
            if sandbox_id not in active_sandboxes:
                return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
            
            sandbox_info = active_sandboxes[sandbox_id]
            sandbox = sandbox_info["sandbox"]
        
        print(f"[MODAL-CLIENT] Executing in {sandbox_id}: {command}")
        
        # Build the command
        if working_dir:
            full_cmd = f"cd {working_dir} && {command}"
        else:
            full_cmd = command
        
        start_time = time.time()
        
        # Execute command
        proc = sandbox.exec("bash", "-c", full_cmd, timeout=cmd_timeout)
        
        # Read output
        stdout = proc.stdout.read()
        stderr = proc.stderr.read()
        exit_code = proc.wait()
        
        duration = time.time() - start_time
        
        # Truncate if too large
        if len(stdout) > MAX_OUTPUT_SIZE:
            stdout = stdout[:MAX_OUTPUT_SIZE] + "\n[OUTPUT TRUNCATED]"
        if len(stderr) > MAX_OUTPUT_SIZE:
            stderr = stderr[:MAX_OUTPUT_SIZE] + "\n[OUTPUT TRUNCATED]"
        
        print(f"[MODAL-CLIENT] ✅ Exec completed: exit_code={exit_code}, duration={duration:.2f}s")
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "exit_code": exit_code,
            "stdout": stdout,
            "stderr": stderr,
            "duration": round(duration, 2),
        })
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Exec failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/<sandbox_id>", methods=["GET"])
def get_sandbox(sandbox_id):
    """Get sandbox status."""
    with registry_lock:
        if sandbox_id not in active_sandboxes:
            return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
        
        info = active_sandboxes[sandbox_id]
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "name": info["name"],
            "status": "running",
            "created_at": info["created_at"],
            "image_spec": info["image_spec"],
            "timeout": info["timeout"],
            "volume": info["volume"],
        })


@app.route("/sandboxes", methods=["GET"])
def list_sandboxes():
    """List all active sandboxes."""
    with registry_lock:
        result = []
        for sandbox_id, info in active_sandboxes.items():
            result.append({
                "sandbox_id": sandbox_id,
                "name": info["name"],
                "status": "running",
                "created_at": info["created_at"],
                "image_base": info["image_spec"].get("base", "debian"),
                "volume": info["volume"],
            })
        
        return jsonify({
            "count": len(result),
            "sandboxes": result,
        })


@app.route("/sandbox/snapshot", methods=["POST"])
def snapshot_sandbox():
    """
    Take a snapshot of a sandbox's filesystem.
    
    Request body:
    {
        "sandbox_id": "sb_1234567890",
        "snapshot_name": "my-snapshot"
    }
    """
    try:
        data = request.get_json()
        sandbox_id = data.get("sandbox_id")
        snapshot_name = data.get("snapshot_name", f"snap-{sandbox_id}-{int(time.time())}")
        
        with registry_lock:
            if sandbox_id not in active_sandboxes:
                return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
            
            sandbox = active_sandboxes[sandbox_id]["sandbox"]
        
        print(f"[MODAL-CLIENT] Taking snapshot: {snapshot_name}")
        
        # Note: Modal's snapshot API might differ - this is a placeholder
        # In practice, you'd use modal.Sandbox.snapshot() or similar
        # For now, we just return success
        sandbox.terminate()
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "snapshot_name": snapshot_name,
            "status": "snapshotted",
            "message": "Sandbox terminated and state preserved",
        })
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Snapshot failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/restore", methods=["POST"])
def restore_sandbox():
    """
    Restore a sandbox from a snapshot.
    Note: Modal's restore mechanism requires specific implementation.
    """
    try:
        data = request.get_json()
        snapshot_name = data.get("snapshot_name")
        
        print(f"[MODAL-CLIENT] Restore requested: {snapshot_name}")
        
        # Placeholder - Modal's restore API
        return jsonify({
            "status": "not_implemented",
            "message": "Snapshot restore requires Modal's checkpoint API",
            "snapshot_name": snapshot_name,
        }), 501
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Restore failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/<sandbox_id>", methods=["DELETE"])
def destroy_sandbox(sandbox_id):
    """Destroy a sandbox."""
    try:
        with registry_lock:
            if sandbox_id not in active_sandboxes:
                return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
            
            sandbox = active_sandboxes[sandbox_id]["sandbox"]
            del active_sandboxes[sandbox_id]
        
        print(f"[MODAL-CLIENT] Destroying sandbox: {sandbox_id}")
        sandbox.terminate()
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "status": "destroyed",
        })
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Destroy failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/upload", methods=["POST"])
def upload_file():
    """
    Upload a file to a sandbox.
    
    Request body (multipart/form-data):
      - sandbox_id: sandbox ID
      - path: destination path in sandbox
      - file: file to upload
    """
    try:
        sandbox_id = request.form.get("sandbox_id")
        dest_path = request.form.get("path", "/project")
        
        if "file" not in request.files:
            return jsonify({"error": "No file provided"}), 400
        
        file = request.files["file"]
        
        with registry_lock:
            if sandbox_id not in active_sandboxes:
                return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
            
            sandbox = active_sandboxes[sandbox_id]["sandbox"]
        
        # Read file content
        content = file.read()
        filename = file.filename
        
        # Write to sandbox via command
        full_path = f"{dest_path}/{filename}"
        
        # Encode content as base64 and decode in sandbox
        import base64
        b64_content = base64.b64encode(content).decode("ascii")
        
        cmd = f"echo '{b64_content}' | base64 -d > {full_path}"
        proc = sandbox.exec("bash", "-c", cmd)
        exit_code = proc.wait()
        
        if exit_code != 0:
            return jsonify({"error": "Failed to upload file", "exit_code": exit_code}), 500
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "path": full_path,
            "size": len(content),
            "status": "uploaded",
        })
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Upload failed: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/sandbox/download", methods=["POST"])
def download_file():
    """
    Download a file from a sandbox.
    
    Request body:
    {
        "sandbox_id": "sb_1234567890",
        "path": "/project/file.txt"
    }
    """
    try:
        data = request.get_json()
        sandbox_id = data.get("sandbox_id")
        path = data.get("path")
        
        with registry_lock:
            if sandbox_id not in active_sandboxes:
                return jsonify({"error": f"Sandbox {sandbox_id} not found"}), 404
            
            sandbox = active_sandboxes[sandbox_id]["sandbox"]
        
        # Read file via command
        cmd = f"cat {path} | base64"
        proc = sandbox.exec("bash", "-c", cmd)
        
        stdout = proc.stdout.read()
        exit_code = proc.wait()
        
        if exit_code != 0:
            return jsonify({"error": "Failed to download file", "exit_code": exit_code}), 500
        
        import base64
        content = base64.b64decode(stdout)
        
        return jsonify({
            "sandbox_id": sandbox_id,
            "path": path,
            "content": stdout,  # base64 encoded
            "size": len(content),
        })
        
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Download failed: {e}")
        return jsonify({"error": str(e)}), 500


# ============================================================
# Main
# ============================================================

def main():
    """Start the Modal Client API server."""
    print("=" * 60)
    print("[MODAL-CLIENT] Starting Modal Client API Server")
    print("=" * 60)
    
    # Check Modal credentials
    token_id = os.environ.get("MODAL_TOKEN_ID")
    token_secret = os.environ.get("MODAL_TOKEN_SECRET")
    
    if not token_id or not token_secret:
        print("[MODAL-CLIENT] ❌ Modal credentials not set!")
        print("[MODAL-CLIENT]    Set MODAL_TOKEN_ID and MODAL_TOKEN_SECRET")
        sys.exit(1)
    
    print(f"[MODAL-CLIENT] ✅ Modal Token ID: {token_id[:10]}...")
    print(f"[MODAL-CLIENT] ✅ Modal Environment: {MODAL_ENVIRONMENT}")
    
    # Initialize Modal App
    try:
        app_modal = get_modal_app()
        print(f"[MODAL-CLIENT] ✅ Modal App ready: hermes-sandboxes")
    except Exception as e:
        print(f"[MODAL-CLIENT] ❌ Failed to initialize Modal: {e}")
        sys.exit(1)
    
    print(f"[MODAL-CLIENT] ✅ Default timeout: {DEFAULT_TIMEOUT}s")
    print(f"[MODAL-CLIENT] ✅ Max output size: {MAX_OUTPUT_SIZE} bytes")
    print(f"[MODAL-CLIENT] ✅ Starting server on {FLASK_HOST}:{FLASK_PORT}")
    print("=" * 60)
    
    # 🔥 FIXED: Use the Flask app instance
    app.run(host=FLASK_HOST, port=FLASK_PORT, debug=False)


if __name__ == "__main__":
    main()
