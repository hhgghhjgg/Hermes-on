# Use official Python 3.11 slim image
FROM python:3.11-slim

# Prevent Python from writing .pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Hermes Agent
RUN git clone https://github.com/NousResearch/hermes-agent.git /app/hermes-agent && \
    cd /app/hermes-agent && \
    pip install --no-cache-dir -e .

# Install Hermes WebUI
RUN git clone https://github.com/nesquena/hermes-webui.git /app/hermes-webui && \
    cd /app/hermes-webui && \
    pip install --no-cache-dir -r requirements.txt

# Copy our scripts
COPY entrypoint.sh /app/entrypoint.sh
COPY sync.sh /app/sync.sh

# Make scripts executable
RUN chmod +x /app/entrypoint.sh /app/sync.sh

# Create data directory
RUN mkdir -p /data

# Set environment variables for Hermes
ENV HERMES_HOME=/data/.hermes
ENV HERMES_WEBUI_STATE_DIR=/data/.hermes/webui
ENV HERMES_WEBUI_AGENT_DIR=/app/hermes-agent
ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787

# Expose port
EXPOSE 8787

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
