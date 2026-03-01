#!/bin/bash
# Process download queue - runs inside Docker container
# Called by cron or manually

LOCK_DIR="/tmp/download_queue.lock"
QUEUE_DIR="/app/data/downloads"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Implement a locking mechanism
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Queue processor is already running. Exiting."
    exit 1
fi

# Ensure lock is removed on exit
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

echo "Queue processor started at $(date)"
echo "Scanning for jobs in $QUEUE_DIR"

# Find all queued downloads
for json_file in "$QUEUE_DIR"/dl_*.json; do
    [ -f "$json_file" ] || continue

    # Check if status is "queued"
    if grep -q '"status"[[:space:]]*:[[:space:]]*"queued"' "$json_file"; then
        echo "Found queued job: $json_file"
        # Atomically update status to "downloading" to prevent race conditions
        sed -i 's/"status"[[:space:]]*:[[:space:]]*"queued"/"status": "downloading"/' "$json_file"

        # Pass JSON file path directly to PHP worker
        nohup php "$SCRIPT_DIR/download-worker.php" "$json_file" > /dev/null 2>&1 &
        disown

        # Only process one at a time to avoid overload
        break
    fi
done
echo "Queue processor finished at $(date)"
