# ============================================================
# Hermes Agent - Docker Image with Modal Sandbox Support
# ============================================================
# 🔥 FIX: WebUI now runs on port 8080 (Render's default port)
# 🔥 Qwen Proxy is DISABLED (replaced with dummy script)
# ============================================================

FROM python:3.11-slim

# ------------------------------------------------------------
# Environment variables
# HERMES_WEBUI_PORT=8080: WebUI on Render's default port
# QWEN_PROXY_PORT=8081: Qwen Proxy (disabled anyway)
# ------------------------------------------------------------
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    MODAL_ENVIRONMENT=main \
    HERMES_WEBUI_PORT=8080 \
    HERMES_WEBUI_HOST=0.0.0.0

# ------------------------------------------------------------
# System dependencies
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
# ------------------------------------------------------------
RUN git clone https://github.com/NousResearch/hermes-agent.git /app/hermes-agent \
    && git clone https://github.com/nesquena/hermes-webui.git /app/webui

# ------------------------------------------------------------
# Install hermes-agent
# ------------------------------------------------------------
WORKDIR /app/hermes-agent
RUN pip install --no-cache-dir -e .

# ------------------------------------------------------------
# Install hermes-webui dependencies
# ------------------------------------------------------------
WORKDIR /app/webui
RUN pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------
# Install required packages
# ------------------------------------------------------------
WORKDIR /app
RUN pip install --no-cache-dir \
    "flask>=3.0.0" \
    "requests>=2.31.0" \
    "modal>=0.73.0"

# ------------------------------------------------------------
# Copy operational scripts
# ------------------------------------------------------------
COPY sync.sh /app/sync.sh
COPY entrypoint.sh /app/entrypoint.sh
COPY modal-client.py /app/modal-client.py

RUN chmod +x /app/sync.sh /app/entrypoint.sh

# ------------------------------------------------------------
# 🔥 QWEN PROXY IS DEPRECATED - Create dummy script
# This replaces qwen-proxy.py with a script that does nothing
# so it doesn't conflict with WebUI on port 8080
# ------------------------------------------------------------
RUN printf '#!/usr/bin/env python3\nimport time\nprint("[QWEN] Deprecated - doing nothing")\nwhile True: time.sleep(3600)\n' > /app/qwen-proxy.py

# ------------------------------------------------------------
# Modal SDK config directory
# ------------------------------------------------------------
RUN mkdir -p /root/.modal

# ------------------------------------------------------------
# Workspace directory
# ------------------------------------------------------------
RUN mkdir -p /workspace
WORKDIR /workspace

# ------------------------------------------------------------
# 🔥 ONLY EXPOSE PORT 8080 (WebUI)
# 8081 and 8090 are internal, not exposed
# ------------------------------------------------------------
EXPOSE 8080

# ------------------------------------------------------------
# Health check
# ------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------
ENTRYPOINT ["/app/entrypoint.sh"]
