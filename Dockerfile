# ============================================================
# Hermes Agent - Docker Image with FULL MCP Support + 20 Languages
# ============================================================
# Languages: Python, Node, PHP, Ruby, Go, Rust, Java, C/C++,
#            Perl, Lua, Deno, Bun, Elixir, Kotlin, Scala, Zig,
#            PowerShell, R (optional), Julia (optional), Swift (optional)
# ============================================================

FROM python:3.11-slim

# ------------------------------------------------------------
# Environment variables
# ------------------------------------------------------------
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    MODAL_ENVIRONMENT=main \
    HERMES_WEBUI_PORT=8080 \
    HERMES_WEBUI_HOST=0.0.0.0 \
    PATH="/root/.local/bin:/root/.cargo/bin:/usr/local/go/bin:$PATH" \
    GO_VERSION=1.22.5 \
    RUST_VERSION=1.78.0 \
    ZIG_VERSION=0.12.0

# ------------------------------------------------------------
# System dependencies (base tools)
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    unzip \
    ca-certificates \
    gnupg \
    ripgrep \
    procps \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 1: Python 3.11 (from base image)
# ============================================================
# Already installed via python:3.11-slim

# ============================================================
# 🔥 LANGUAGE 2: Node.js 20 LTS
# ============================================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 3: PHP 8.2 CLI
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-cli \
    php-curl \
    php-mbstring \
    php-xml \
    php-zip \
    php-sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 4: Ruby
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    ruby-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 5: Go (binary install - lightweight)
# ============================================================
RUN wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# ============================================================
# 🔥 LANGUAGE 6: Rust (rustup minimal)
# ============================================================
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
    && /root/.cargo/bin/rustup default stable \
    && /root/.cargo/bin/rustup component add rustfmt clippy

# ============================================================
# 🔥 LANGUAGE 7: Java 17 JRE Headless
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 8: C/C++ Compilers
# ============================================================
# Already included in build-essential

# ============================================================
# 🔥 LANGUAGE 9: Perl
# ============================================================
# Already included in Debian base (perl package)

# ============================================================
# 🔥 LANGUAGE 10: Lua 5.4
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    lua5.4 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 11: Deno
# ============================================================
RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh \
    && ln -s /root/.deno/bin/deno /usr/local/bin/deno

# ============================================================
# 🔥 LANGUAGE 12: Bun
# ============================================================
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun \
    && ln -s /root/.bun/bin/bunx /usr/local/bin/bunx

# ============================================================
# 🔥 LANGUAGE 13: Elixir (with Erlang)
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    elixir \
    erlang-base \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 14: Kotlin (via snap-less install)
# ============================================================
RUN wget -q https://github.com/JetBrains/kotlin/releases/download/v2.0.0/kotlin-compiler-2.0.0.zip -O /tmp/kotlin.zip \
    && unzip -q /tmp/kotlin.zip -d /opt \
    && ln -s /opt/kotlinc/bin/kotlin /usr/local/bin/kotlin \
    && ln -s /opt/kotlinc/bin/kotlinc /usr/local/bin/kotlinc \
    && rm /tmp/kotlin.zip

# ============================================================
# 🔥 LANGUAGE 15: Scala (via coursier - lightweight)
# ============================================================
RUN curl -fL https://github.com/coursier/coursier/releases/download/v2.1.10/cs-x86_64-pc-linux.gz | gzip -d > /usr/local/bin/cs \
    && chmod +x /usr/local/bin/cs \
    && /usr/local/bin/cs setup --yes --apps scala,scalac

# ============================================================
# 🔥 LANGUAGE 16: Zig (binary install)
# ============================================================
RUN wget -q https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz -O /tmp/zig.tar.xz \
    && tar -xf /tmp/zig.tar.xz -C /opt \
    && mv /opt/zig-linux-x86_64-${ZIG_VERSION} /opt/zig \
    && ln -s /opt/zig/zig /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

# ============================================================
# 🔥 LANGUAGE 17: PowerShell
# ============================================================
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/microsoft-debian-bookworm-prod bookworm main" > /etc/apt/sources.list.d/microsoft.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 18: R (base only, no packages)
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base-core \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# 🔥 LANGUAGE 19: Julia (binary install)
# ============================================================
RUN wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.4-linux-x86_64.tar.gz -O /tmp/julia.tar.gz \
    && tar -C /opt -xzf /tmp/julia.tar.gz \
    && ln -s /opt/julia-1.10.4/bin/julia /usr/local/bin/julia \
    && rm /tmp/julia.tar.gz

# ============================================================
# 🔥 LANGUAGE 20: Swift (optional - skip if too heavy)
# ============================================================
# SKIP: Swift is too large (~700MB), use only if needed
# RUN curl -fsSL https://download.swift.org/swift-5.10-release/ubuntu2204/swift-5.10-RELEASE/swift-5.10-RELEASE-ubuntu22.04.tar.gz -o /tmp/swift.tar.gz \
#     && tar -C /opt -xzf /tmp/swift.tar.gz \
#     && rm /tmp/swift.tar.gz

# ============================================================
# 🔥 INSTALL uv (for uvx Python MCP servers)
# ============================================================
RUN pip install --no-cache-dir uv

# ============================================================
# 🔥 PRE-WARM common MCP packages
# ============================================================
RUN npm install -g --silent \
    @modelcontextprotocol/server-fetch \
    @modelcontextprotocol/server-filesystem \
    @modelcontextprotocol/server-memory \
    @modelcontextprotocol/server-git \
    @modelcontextprotocol/server-postgres \
    @modelcontextprotocol/server-sqlite \
    @modelcontextprotocol/server-github \
    @modelcontextprotocol/server-brave-search \
    @modelcontextprotocol/server-sequentialthinking \
    @playwright/mcp@latest \
    || echo "[WARN] Some MCP pre-warm failed, will install on first use"

# Pre-warm Playwright browsers (critical for playwright MCP)
RUN npx -y playwright install chromium --with-deps \
    || echo "[WARN] Playwright browsers pre-warm failed"

# Pre-warm Python MCPs via uv cache
RUN uv tool install mcp-server-git || true \
    && uv tool install mcp-server-time || true \
    && uv tool install ruff-mcp || true

# ============================================================
# Verify all installations
# ============================================================
RUN echo "========================================" \
    && echo "=== Language Verification ===" \
    && echo "========================================" \
    && python3 --version \
    && node --version \
    && npm --version \
    && npx --version \
    && php --version | head -1 \
    && ruby --version | head -1 \
    && go version \
    && /root/.cargo/bin/rustc --version \
    && java -version 2>&1 | head -1 \
    && gcc --version | head -1 \
    && perl --version | head -2 | tail -1 \
    && lua5.4 -v \
    && deno --version | head -1 \
    && bun --version \
    && elixir --version | head -1 \
    && kotlin -version \
    && scala -version 2>&1 | head -1 \
    && zig version \
    && pwsh --version \
    && R --version | head -1 \
    && julia --version \
    && echo "========================================" \
    && echo "=== All 19 Languages Ready ===" \
    && echo "========================================"

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
# QWEN PROXY IS DEPRECATED - Create dummy script
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
# EXPOSE PORT 8080 (WebUI only)
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
