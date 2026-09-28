#!/bin/bash
set -e

COMPOSE_CMD="docker compose"

echo "========================================="
echo "  Gullify Update Script"
echo "========================================="
echo ""

# Step 1: Pull latest code
echo "[1/3] Pulling latest code from Git..."
git pull
echo ""

# Step 2: Choose build mode
echo "[2/3] Choose how to rebuild the Docker image:"
echo ""
echo "  1) Quick rebuild (default)"
echo "     Uses Docker cache. Fast (~30s). ffmpeg and the Python packages"
echo "     stay at their cached version; yt-dlp is refreshed on every start."
echo "     Use this for code-only updates (PHP, JS, CSS)."
echo ""
echo "  2) Full rebuild (no cache)"
echo "     Rebuilds everything from scratch. Slower (~3-5 min), but"
echo "     updates ALL dependencies to their latest version:"
echo "     ytmusicapi, ffmpeg, PHP extensions, Composer packages."
echo "     Use this after a long time without updating."
echo ""
echo "  3) Skip rebuild"
echo "     Only restart the container with the existing image."
echo "     Use this if you only changed config files or .env,"
echo "     or to pick up a new yt-dlp when downloads are failing."
echo ""

read -rp "Choice [1/2/3] (default: 1): " choice
echo ""

# Step 3: Apply
case "$choice" in
    2)
        echo "[3/3] Full rebuild (no cache)..."
        $COMPOSE_CMD down
        $COMPOSE_CMD build --no-cache
        $COMPOSE_CMD up -d
        ;;
    3)
        echo "[3/3] Restarting container..."
        $COMPOSE_CMD down
        $COMPOSE_CMD up -d
        ;;
    *)
        echo "[3/3] Quick rebuild..."
        $COMPOSE_CMD down
        $COMPOSE_CMD build --build-arg CACHEBUST="$(date +%s)"
        $COMPOSE_CMD up -d
        ;;
esac

echo ""
echo "========================================="
echo "  Gullify is up to date!"
echo "========================================="
