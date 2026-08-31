#!/bin/bash
# ============================================================
# sync.sh - Release-based sync (v2)
# ============================================================
# این اسکریپت دیگه به صورت خودکار اجرا نمیشه!
# سینک خودکار توسط ورکفلو GitHub Actions انجام میشه.
# این اسکریپت فقط برای استفاده دستی هست.
# ============================================================

set -e

echo "=========================================="
echo "[SYNC v2] Started at $(date)"
echo "=========================================="

# ============================================================
# Check if sync is disabled
# ============================================================
if [ "$GITHUB_SYNC_DISABLED" = "true" ]; then
  echo "[SYNC v2] 🚫 Sync is DISABLED (GITHUB_SYNC_DISABLED=true)"
  echo "[SYNC v2] ℹ️  Automatic sync is handled by the GitHub workflow"
  echo "[SYNC v2] ℹ️  Data is saved to GitHub Release every 30 minutes"
  echo "[SYNC v2] ✅ Exiting without action"
  exit 0
fi

# ============================================================
# Configuration
# ============================================================
DATA_REPO="${DATA_REPO:-hhgghhjgg/Hermes-pre}"
HERMES_DIR="/data/.hermes"
RELEASE_NAME="manual-$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="/tmp/hermes-data-$RELEASE_NAME.tar.gz"

echo "[SYNC v2] Data repo:    $DATA_REPO"
echo "[SYNC v2] Hermes dir:   $HERMES_DIR"
echo "[SYNC v2] Release name: $RELEASE_NAME"
echo "=========================================="

# ============================================================
# Check prerequisites
# ============================================================
if ! command -v gh &> /dev/null; then
  echo "[SYNC v2] ❌ ERROR: 'gh' (GitHub CLI) is not installed!"
  echo "[SYNC v2] ℹ️  This script is meant to run inside GitHub Actions"
  echo "[SYNC v2] ℹ️  For manual sync, run it from the workflow instead"
  exit 1
fi

if ! command -v tar &> /dev/null; then
  echo "[SYNC v2] ❌ ERROR: 'tar' is not installed!"
  exit 1
fi

if [ ! -d "$HERMES_DIR" ]; then
  echo "[SYNC v2] ❌ ERROR: Hermes directory not found: $HERMES_DIR"
  exit 1
fi

echo "[SYNC v2] ✅ Prerequisites check passed"

# ============================================================
# Create archive
# ============================================================
echo ""
echo "[SYNC v2] 📦 Creating archive..."

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

echo "[SYNC v2] ✅ Archive created: $ARCHIVE_SIZE"
echo "[SYNC v2] ✅ Files included: $FILE_COUNT"

# ============================================================
# Create GitHub Release
# ============================================================
echo ""
echo "[SYNC v2] 🚀 Creating GitHub Release..."

if gh release create "$RELEASE_NAME" \
  "$ARCHIVE_PATH" \
  --repo "$DATA_REPO" \
  --title "Manual Backup $(date '+%Y-%m-%d %H:%M:%S')" \
  --notes "Manual sync - $FILE_COUNT files"; then
  
  echo "[SYNC v2] ✅ Release created successfully"
  echo "[SYNC v2] 🔗 https://github.com/$DATA_REPO/releases/tag/$RELEASE_NAME"
else
  echo "[SYNC v2] ❌ ERROR: Failed to create release"
  echo "[SYNC v2] ℹ️  Check your GitHub token and permissions"
  rm -f "$ARCHIVE_PATH"
  exit 1
fi

# ============================================================
# Cleanup local archive
# ============================================================
rm -f "$ARCHIVE_PATH"

# ============================================================
# Keep only last 5 releases
# ============================================================
echo ""
echo "[SYNC v2] 🧹 Cleaning up old releases..."

OLD_RELEASES=$(gh release list --repo "$DATA_REPO" --limit 100 --json tagName -q '.[5:] | .[].tagName' 2>/dev/null || true)

if [ -n "$OLD_RELEASES" ]; then
  for old in $OLD_RELEASES; do
    echo "  Deleting: $old"
    gh release delete "$old" --repo "$DATA_REPO" --yes --cleanup-tag 2>/dev/null || true
  done
else
  echo "[SYNC v2] ℹ️  No old releases to cleanup"
fi

echo ""
echo "=========================================="
echo "[SYNC v2] ✅ Sync completed successfully!"
echo "=========================================="
