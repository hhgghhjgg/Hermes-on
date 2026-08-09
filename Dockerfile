# ============================================================
# Hermes Agent - Docker Image with Modal Sandbox Support
# ============================================================
# This image provides:
#   - Hermes Agent (core AI agent)
#   - Hermes WebUI (web interface from nesquena/hermes-webui)
#   - Qwen OAuth Proxy (port 8080)
#   - Modal Client API (port 8090)
#   - Git sync with Hermes-pre repository
# ============================================================

FROM python:3.11-slim

# ------------------------------------------------------------
# Environment variables
# PYTHONUNBUFFERED: real-time logs for Render
# PYTHONDONTWRITEBYTECODE: prevent .pyc files
# PIP_NO_CACHE_DIR: smaller image size
# MODAL_ENVIRONMENT: default Modal environment (main)
# ------------------------------------------------------------
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    MODAL_ENVIRONMENT=main

# ------------------------------------------------------------
# System dependencies
# git: required for sync.sh and FULL RESTORE from Hermes-pre
# curl/wget/unzip: general utilities
# ca-certificates: HTTPS support
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ------------------------------------------------------------
# Clone hermes-agent and hermes-webui
# NOTE: WebUI is now at nesquena/hermes-webui (not NousResearch)
# ------------------------------------------------------------
RUN git clone https://github.com/NousResearch/hermes-agent.git /app/hermes-agent \
    && git clone https://github.com/nesquena/hermes-webui.git /app/webui

# ------------------------------------------------------------
# Install hermes-agent (editable mode for development)
# ------------------------------------------------------------
WORKDIR /app/hermes-agent
RUN pip install --no-cache-dir -e .

# ------------------------------------------------------------
# Install hermes-webui dependencies
# ------------------------------------------------------------
WORKDIR /app/webui
RUN pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------
# Install Hermes-on requirements
# Includes:
#   - flask, requests (for qwen-proxy.py)
#   - modal>=0.73.0 (for modal-client.py)
# ------------------------------------------------------------
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# ------------------------------------------------------------
# Copy operational scripts
# sync.sh: background sync to Hermes-pre GitHub repo
# entrypoint.sh: startup script with FULL RESTORE
# qwen-proxy.py: OAuth proxy for Qwen models
# modal-client.py: Modal Sandbox API server
# ------------------------------------------------------------
COPY sync.sh /app/sync.sh
COPY entrypoint.sh /app/entrypoint.sh
COPY qwen-proxy.py /app/qwen-proxy.py
COPY modal-client.py /app/modal-client.py

RUN chmod +x /app/sync.sh /app/entrypoint.sh

# ------------------------------------------------------------
# Modal SDK config directory
# (Tokens are read from Environment Variables, no file needed)
# ------------------------------------------------------------
RUN mkdir -p /root/.modal

# ------------------------------------------------------------
# Workspace directory (where Hermes works)
# ------------------------------------------------------------
RUN mkdir -p /workspace
WORKDIR /workspace

# ------------------------------------------------------------
# Ports
# 8787: Hermes WebUI (main web interface)
# 8080: Qwen OAuth Proxy (API gateway for Qwen models)
# 8090: Modal Client API (internal use by Hermes)
#       Note: 8090 is internal only, not exposed to public
# ------------------------------------------------------------
EXPOSE 8787 8080

# ------------------------------------------------------------
# Health check (optional but recommended)
# ------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8787/ || exit 1

# ------------------------------------------------------------
# Entry point
# entrypoint.sh handles:
#   1. Git configuration
#   2. Modal configuration
#   3. FULL RESTORE from Hermes-pre
#   4. Skills installation (72 bundled + 129 optional)
#   5. config.yaml generation
#   6. Starting sync.sh, Qwen Proxy, Modal Client, WebUI
# ------------------------------------------------------------
ENTRYPOINT ["/app/entrypoint.sh"]
