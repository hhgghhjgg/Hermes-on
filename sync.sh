#!/bin/bash

set -e

DATA_DIR="/data"
HERMES_DIR="$DATA_DIR/.hermes"
SYNC_INTERVAL="${SYNC_INTERVAL:-180}"
MAX_STATE_BACKUPS=5

echo "=========================================="
echo "[SYNC-B2] Started at $(date)"
echo "[SYNC-B2] Interval: ${SYNC_INTERVAL}s"
echo "[SYNC-B2] B2 Bucket: ${B2_BUCKET_NAME:-NOT SET}"
echo "[SYNC-B2] B2 Key ID set: $([ -n "$B2_APPLICATION_KEY_ID" ] && echo YES || echo NO)"
echo "[SYNC-B2] Scope: ALL Hermes data"
echo "[SYNC-B2]   - state.db (chats)"
echo "[SYNC-B2]   - webui/ (sessions, settings)"
echo "[SYNC-B2]   - skills/ (all skills)"
echo "[SYNC-B2]   - workspace/ (your projects)"
echo "[SYNC-B2]   - MEMORY.md, USER.md, SOUL.md"
echo "[SYNC-B2]   - config.yaml"
echo "[SYNC-B2]   - profiles/"
echo "[SYNC-B2]   - crons/"
echo "[SYNC-B2]   - plans/"
echo "[SYNC-B2]   - Everything else in /data/.hermes/"
echo "[SYNC-B2] Modal: state stored in Modal Volumes (not synced here)"
echo "=========================================="

# ============================================================
# بررسی credentials
# ============================================================
if [ -z "$B2_APPLICATION_KEY_ID" ] || [ -z "$B2_APPLICATION_KEY" ] || [ -z "$B2_BUCKET_NAME" ]; then
    echo "[SYNC-B2] ❌ B2 credentials not set!"
    echo "[SYNC-B2] Required: B2_APPLICATION_KEY_ID, B2_APPLICATION_KEY, B2_BUCKET_NAME"
    exit 1
fi

# ============================================================
# Configure rclone
# ============================================================
echo "[SYNC-B2] Configuring rclone..."
mkdir -p /root/.config/rclone

cat > /root/.config/rclone/rclone.conf << EOF
[b2]
type = b2
account = ${B2_APPLICATION_KEY_ID}
key = ${B2_APPLICATION_KEY}
EOF

chmod 600 /root/.config/rclone/rclone.conf

# بررسی نصب rclone
if ! command -v rclone &> /dev/null; then
    echo "[SYNC-B2] Installing rclone..."
    curl -s https://rclone.org/install.sh | bash
fi

echo "[SYNC-B2] ✅ rclone configured for B2"

# ============================================================
# تست اتصال به B2
# ============================================================
echo "[SYNC-B2] Testing B2 connection..."
if rclone lsd "b2:${B2_BUCKET_NAME}" --max-depth 1 > /dev/null 2>&1; then
    echo "[SYNC-B2] ✅ B2 connection successful"
else
    echo "[SYNC-B2] ❌ B2 connection failed!"
    exit 1
fi

cd "$HERMES_DIR" || exit 1

# ============================================================
# فایل exclude
# ============================================================
EXCLUDE_FILE="/tmp/b2-exclude.txt"
cat > "$EXCLUDE_FILE" << 'EOF'
*.tmp
*.log
*.journal
state.db-journal
state.db-wal
node_modules/**
__pycache__/**
*.pyc
*.pyo
.DS_Store
*.pre-reset.*
*.pre-restore.*
EOF

echo "[SYNC-B2] Exclude patterns saved to $EXCLUDE_FILE"

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
# شمارش فایل‌ها
# ============================================================
count_files() {
    find "$HERMES_DIR" -type f \
        -not -path '*/\.*' \
        -not -path '*/node_modules/*' \
        -not -path '*/__pycache__/*' \
        -not -name '*.tmp' \
        -not -name '*.log' \
        -not -name '*.journal' \
        -not -name '*.pyc' \
        -not -name '*.pyo' \
        2>/dev/null | wc -l
}

# ============================================================
# Helper function to check Modal Client health
# ============================================================
check_modal_client() {
    if [ -n "$MODAL_TOKEN_ID" ]; then
        MODAL_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/health 2>/dev/null || echo "000")
        if [ "$MODAL_HEALTH" = "200" ]; then
            echo "[SYNC-B2 #$counter] ✓ Modal Client healthy (port 8090)"
        else
            echo "[SYNC-B2 #$counter] ⚠️ Modal Client not responding (port 8090)"
        fi
    fi
}

# ============================================================
# مدیریت بکاپ‌های state.db
# ============================================================
manage_state_backups() {
    local BACKUP_COUNT=$(ls -1 "$HERMES_DIR"/state.db.bak.* 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt "$MAX_STATE_BACKUPS" ]; then
        echo "[SYNC-B2 #$counter] Cleaning up old state.db backups (keeping $MAX_STATE_BACKUPS)..."
        ls -1t "$HERMES_DIR"/state.db.bak.* | tail -n +$((MAX_STATE_BACKUPS + 1)) | xargs -r rm -f
    fi
}

# ============================================================
# Sync function
# ============================================================
do_sync() {
    local sync_num=$1
    local start_time=$(date +%s)
    
    echo "[SYNC-B2 #$sync_num] 🔄 Syncing to B2..."
    
    # شمارش فایل‌های محلی قبل از sync
    local LOCAL_COUNT=$(count_files)
    
    # اجرای sync
    rclone sync "$HERMES_DIR" "b2:${B2_BUCKET_NAME}" \
        --transfers=4 \
        --checkers=8 \
        --size-only \
        --retries=3 \
        --low-level-retries=10 \
        --max-duration=10m \
        --exclude-from="$EXCLUDE_FILE" \
        --stats=0 \
        2>&1
    
    local EXIT_CODE=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "[SYNC-B2 #$sync_num] ✅ Sync completed in ${duration}s"
        echo "[SYNC-B2 #$sync_num] 📊 Local files: $LOCAL_COUNT"
    else
        echo "[SYNC-B2 #$sync_num] ⚠️ Sync had errors (exit code: $EXIT_CODE) in ${duration}s"
    fi
    
    return $EXIT_CODE
}

# ============================================================
# شمارش فایل‌های B2
# ============================================================
count_b2_files() {
    rclone size "b2:${B2_BUCKET_NAME}" --json 2>/dev/null | grep -o '"count":[0-9]*' | cut -d: -f2 || echo "0"
}

# ============================================================
# Main sync loop
# ============================================================
counter=0

echo "[SYNC-B2] Entering main loop (interval: ${SYNC_INTERVAL}s)..."
echo "=========================================="

while true; do
    sleep "$SYNC_INTERVAL"
    counter=$((counter + 1))
    
    # Check Modal Client health every 10 syncs
    if [ $((counter % 10)) -eq 0 ]; then
        check_modal_client
    fi
    
    # مدیریت بکاپ‌های state.db
    manage_state_backups
    
    # Sync به B2
    do_sync $counter
    
    # هر ۱۰ sync یکبار، شمارش B2 فایل‌ها
    if [ $((counter % 10)) -eq 0 ]; then
        B2_COUNT=$(count_b2_files)
        LOCAL_COUNT=$(count_files)
        echo "[SYNC-B2 #$counter] 📊 Stats: Local=$LOCAL_COUNT, B2=$B2_COUNT"
    fi
done
