#!/bin/bash
# ============================================================
# sync.sh - B2-based sync (v3 - Final)
# ============================================================
# ⚠️  این اسکریپت دیگه به صورت خودکار اجرا نمیشه!
# سینک خودکار توسط ورکفلو GitHub Actions انجام میشه.
# این اسکریپت فقط برای استفاده دستی هست.
# ============================================================

set -e

echo "=========================================="
echo "[SYNC v3] Started at $(date)"
echo "=========================================="

# ============================================================
# Check if sync is disabled
# ============================================================
if [ "$GITHUB_SYNC_DISABLED" = "true" ]; then
  echo "[SYNC v3] 🚫 Sync is DISABLED (GITHUB_SYNC_DISABLED=true)"
  echo "[SYNC v3] ℹ️  Automatic sync is handled by the GitHub workflow"
  echo "[SYNC v3] ℹ️  Data is saved to B2 every 10 minutes"
  echo "[SYNC v3] ✅ Exiting without action"
  exit 0
fi

# ============================================================
# Configuration
# ============================================================
B2_BUCKET="${B2_BUCKET_NAME:-}"
HERMES_DIR="/data/.hermes"
ARCHIVE_NAME="hermes-data.tar.gz"
ARCHIVE_PATH="/tmp/$ARCHIVE_NAME"

echo "[SYNC v3] B2 Bucket:    $B2_BUCKET"
echo "[SYNC v3] Hermes dir:   $HERMES_DIR"
echo "[SYNC v3] Archive name: $ARCHIVE_NAME"
echo "=========================================="

# ============================================================
# Check prerequisites
# ============================================================
if ! command -v rclone &> /dev/null; then
  echo "[SYNC v3] ❌ ERROR: 'rclone' is not installed!"
  echo "[SYNC v3] ℹ️  This script is meant to run inside GitHub Actions"
  echo "[SYNC v3] ℹ️  For manual sync, run it from the workflow instead"
  exit 1
fi

if ! command -v tar &> /dev/null; then
  echo "[SYNC v3] ❌ ERROR: 'tar' is not installed!"
  exit 1
fi

if [ ! -d "$HERMES_DIR" ]; then
  echo "[SYNC v3] ❌ ERROR: Hermes directory not found: $HERMES_DIR"
  exit 1
fi

if [ -z "$B2_BUCKET" ]; then
  echo "[SYNC v3] ❌ ERROR: B2_BUCKET_NAME is not set!"
  echo "[SYNC v3] ℹ️  Set B2_BUCKET_NAME environment variable"
  exit 1
fi

echo "[SYNC v3] ✅ Prerequisites check passed"

# ============================================================
# Create archive
# ============================================================
echo ""
echo "[SYNC v3] 📦 Creating archive..."

tar -czf "$ARCHIVE_PATH" \
  -C "$HERMES_DIR" \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='cache/*.log' \
  --exclude='webui/sessions/_run_journal' \
  . 2>/dev/null || true

ARCHIVE_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)
FILE_COUNT=$(find "$HERMES_DIR" -type f 2>/dev/null | wc -l)

echo "[SYNC v3] ✅ Archive created: $ARCHIVE_SIZE"
echo "[SYNC v3] ✅ Files included: $FILE_COUNT"

# ============================================================
# Upload to B2
# ============================================================
echo ""
echo "[SYNC v3] 🚀 Uploading to B2..."

if rclone copyto "$ARCHIVE_PATH" b2:$B2_BUCKET/$ARCHIVE_NAME; then
  echo "[SYNC v3] ✅ Upload successful"
  echo "[SYNC v3] 🔗 https://secure.backblaze.com/b2_buckets.htm"
else
  echo "[SYNC v3] ❌ ERROR: Upload failed"
  rm -f "$ARCHIVE_PATH"
  exit 1
fi

rm -f "$ARCHIVE_PATH"

echo ""
echo "=========================================="
echo "[SYNC v3] ✅ Sync completed successfully!"
echo "=========================================="
