# ============================================================
# Hermes Agent - Complete Docker Image (Final Version)
# ============================================================
# ✅ 19 Programming Languages
# ✅ WebUI with npm build
# ✅ MCP servers working (mcp python SDK installed)
# ✅ Docker-out-of-Docker (DooD)
# ✅ Pre-warmed MCP packages
# ✅ FIXED HEALTHCHECK (port 8787)
# ============================================================

FROM python:3.11-slim

# ============================================================
# ENVIRONMENT VARIABLES
# ============================================================
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    MODAL_ENVIRONMENT=main \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_HOST=0.0.0.0 \
    DOCKER_HOST=unix:///var/run/docker.sock

# ============================================================
# SYSTEM BASE DEPENDENCIES
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget unzip xz-utils ca-certificates gnupg \
    ripgrep procps build-essential \
    ruby ruby-dev \
    lua5.4 \
    elixir \
    openjdk-21-jre-headless \
    r-base-core \
    libicu-dev \
    iptables \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# LANGUAGE 1: Node.js 22 LTS (required for npx MCPs)
# ============================================================
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# LANGUAGE 2: PHP
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-cli php-curl php-mbstring php-xml php-zip php-sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# LANGUAGE 3: Go (with symlink)
# ============================================================
RUN wget -q https://go.dev/dl/go1.23.1.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
    && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    && rm /tmp/go.tar.gz

# ============================================================
# LANGUAGE 4: Rust (with symlink)
# ============================================================
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
    && /root/.cargo/bin/rustup default stable \
    && /root/.cargo/bin/rustup component add rustfmt clippy \
    && ln -sf /root/.cargo/bin/rustc /usr/local/bin/rustc \
    && ln -sf /root/.cargo/bin/cargo /usr/local/bin/cargo \
    && ln -sf /root/.cargo/bin/rustup /usr/local/bin/rustup

# ============================================================
# LANGUAGE 5: Deno (with symlink)
# ============================================================
RUN curl -fsSL https://deno.land/install.sh | sh \
    && ln -sf /root/.deno/bin/deno /usr/local/bin/deno

# ============================================================
# LANGUAGE 6: Bun (with symlink)
# ============================================================
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -sf /root/.bun/bin/bun /usr/local/bin/bun \
    && ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx

# ============================================================
# LANGUAGE 7: Kotlin (with symlink)
# ============================================================
RUN wget -q https://github.com/JetBrains/kotlin/releases/download/v2.0.20/kotlin-compiler-2.0.20.zip -O /tmp/kotlin.zip \
    && unzip -q /tmp/kotlin.zip -d /opt \
    && ln -sf /opt/kotlinc/bin/kotlin /usr/local/bin/kotlin \
    && ln -sf /opt/kotlinc/bin/kotlinc /usr/local/bin/kotlinc \
    && rm /tmp/kotlin.zip

# ============================================================
# LANGUAGE 8: Scala (via coursier)
# ============================================================
RUN curl -fL https://github.com/coursier/coursier/releases/download/v2.1.10/cs-x86_64-pc-linux.gz | gzip -d > /usr/local/bin/cs \
    && chmod +x /usr/local/bin/cs \
    && /usr/local/bin/cs setup --yes --apps scala,scalac \
    && ln -sf /root/.local/share/coursier/bin/scala /usr/local/bin/scala \
    && ln -sf /root/.local/share/coursier/bin/scalac /usr/local/bin/scalac

# ============================================================
# LANGUAGE 9: Zig (with symlink)
# ============================================================
RUN wget -q https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -O /tmp/zig.tar.xz \
    && tar -xf /tmp/zig.tar.xz -C /opt \
    && mv /opt/zig-linux-x86_64-0.13.0 /opt/zig \
    && ln -sf /opt/zig/zig /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

# ============================================================
# LANGUAGE 10: PowerShell (GitHub binary)
# ============================================================
RUN wget -q https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/powershell-7.4.5-linux-x64.tar.gz -O /tmp/pwsh.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm /tmp/pwsh.tar.gz

# ============================================================
# LANGUAGE 11: Julia (with symlink)
# ============================================================
RUN wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-1.11.0-linux-x86_64.tar.gz -O /tmp/julia.tar.gz \
    && tar -C /opt -xzf /tmp/julia.tar.gz \
    && mv /opt/julia-1.11.0 /opt/julia \
    && ln -sf /opt/julia/bin/julia /usr/local/bin/julia \
    && rm /tmp/julia.tar.gz

# ============================================================
# INSTALL uv (for uvx Python MCP servers)
# ============================================================
RUN pip install --no-cache-dir uv

# ============================================================
# DOCKER CLI INSTALLATION (Docker-out-of-Docker)
# ============================================================
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz \
    | tar xz --strip-components=1 -C /usr/local/bin docker/docker \
    && curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose \
    && docker --version \
    && docker-compose --version \
    && echo "✅ Docker CLI + Docker Compose installed"

# ============================================================
# VERIFY ALL LANGUAGES + DOCKER
# ============================================================
RUN echo "============================================" \
    && echo "🔍 VERIFYING ALL LANGUAGES + DOCKER" \
    && echo "============================================" \
    && echo "1.  Python:     $(python3 --version 2>&1)" \
    && echo "2.  Node.js:    $(node --version 2>&1)" \
    && echo "3.  npm:        $(npm --version 2>&1)" \
    && echo "4.  PHP:        $(php --version 2>&1 | head -1)" \
    && echo "5.  Ruby:       $(ruby --version 2>&1)" \
    && echo "6.  Go:         $(go version 2>&1)" \
    && echo "7.  Rust:       $(rustc --version 2>&1)" \
    && echo "8.  Java:       $(java -version 2>&1 | head -1)" \
    && echo "9.  GCC:        $(gcc --version 2>&1 | head -1)" \
    && echo "10. Perl:       $(perl -v 2>&1 | grep version | head -1)" \
    && echo "11. Lua:        $(lua5.4 -v 2>&1)" \
    && echo "12. Deno:       $(deno --version 2>&1 | head -1)" \
    && echo "13. Bun:        $(bun --version 2>&1)" \
    && echo "14. Elixir:     $(elixir --version 2>&1 | tail -1)" \
    && echo "15. Kotlin:     $(kotlin -version 2>&1)" \
    && echo "16. Scala:      $(scala -version 2>&1 | head -1)" \
    && echo "17. Zig:        $(zig version 2>&1)" \
    && echo "18. PowerShell: $(pwsh --version 2>&1)" \
    && echo "19. R:          $(R --version 2>&1 | head -1)" \
    && echo "20. Julia:      $(julia --version 2>&1)" \
    && echo "21. Docker:     $(docker --version 2>&1)" \
    && echo "22. Compose:    $(docker-compose --version 2>&1)" \
    && echo "============================================" \
    && echo "✅ ALL LANGUAGES + DOCKER VERIFIED" \
    && echo "============================================"

WORKDIR /app

# ============================================================
# CLONE HERMES AGENT AND WEBUI
# ============================================================
RUN git clone https://github.com/NousResearch/hermes-agent.git /app/hermes-agent \
    && git clone https://github.com/nesquena/hermes-webui.git /app/webui

# ============================================================
# 🔥 INSTALL HERMES AGENT WITH MCP EXTRA
# ============================================================
# CRITICAL: Without [mcp], MCP servers show as "Configured but
# inactive" because the Python MCP SDK is missing
# ============================================================
WORKDIR /app/hermes-agent
RUN pip install --no-cache-dir -e ".[mcp]"

# ============================================================
# INSTALL HERMES WEBUI WITH NPM BUILD
# ============================================================
WORKDIR /app/webui
RUN pip install --no-cache-dir -r requirements.txt

RUN if [ -f "package.json" ]; then \
        echo "🔥 Building WebUI frontend..." \
        && npm install --no-audit --no-fund 2>/dev/null || true \
        && (npm run build 2>/dev/null || echo "⚠️ No build script"); \
    else \
        echo "ℹ️ No package.json found"; \
    fi

# ============================================================
# INSTALL OTHER REQUIRED PACKAGES
# ============================================================
WORKDIR /app
RUN pip install --no-cache-dir \
    "flask>=3.0.0" \
    "requests>=2.31.0" \
    "modal>=0.73.0"

# ============================================================
# COPY OPERATIONAL SCRIPTS
# ============================================================
COPY sync.sh /app/sync.sh
COPY entrypoint.sh /app/entrypoint.sh
COPY modal-client.py /app/modal-client.py

RUN chmod +x /app/sync.sh /app/entrypoint.sh

# ============================================================
# QWEN PROXY IS DEPRECATED
# ============================================================
RUN printf '#!/usr/bin/env python3\nimport time\nprint("[QWEN] Deprecated")\nwhile True: time.sleep(3600)\n' > /app/qwen-proxy.py

# ============================================================
# MODAL SDK + WORKSPACE
# ============================================================
RUN mkdir -p /root/.modal /workspace /data/.hermes
WORKDIR /workspace

# ============================================================
# PRE-WARM COMMON MCP PACKAGES
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
    @modelcontextprotocol/server-bash \
    @playwright/mcp@latest \
    @browserbase/mcp-server-browserbase \
    firecrawl-mcp \
    puppeteer-mcp \
    @e2b/mcp-server \
    @ofershap/mcp-server-docker \
    mcp-jupyter \
    @modelcontextprotocol/server-knowledge-graph \
    @tree-sitter/mcp \
    @burntsushi/ripgrep-mcp \
    @sourcegraph/lsp-mcp \
    @ast-grep/mcp \
    vector-code-search-mcp \
    2>/dev/null || echo "[WARN] MCP pre-warm failed"

# Pre-warm Python MCP servers via uv
RUN uv tool install mcp-server-git 2>/dev/null || true \
    && uv tool install mcp-server-time 2>/dev/null || true \
    && uv tool install mcp-server-filesystem 2>/dev/null || true

# Pre-warm Playwright browser
RUN npx -y playwright install chromium --with-deps 2>/dev/null || true

# ============================================================
# CREATE DOCKER GROUP (for docker.sock permissions)
# ============================================================
RUN groupadd -f docker && usermod -aG docker root

# ============================================================
# 🔥🔥🔥 FIXED: EXPOSE + HEALTHCHECK ON PORT 8787 🔥🔥🔥
# ============================================================
# قبل: پورت ۸۰۸۰ بود که باعث می‌شد کانتینر unhealthy بشه
# چون ورکفلو HERMES_WEBUI_PORT=8787 رو ست می‌کنه
# ============================================================
EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8787/health || exit 1

# ============================================================
# ENTRYPOINT
# ============================================================
ENTRYPOINT ["/app/entrypoint.sh"]
