#!/bin/bash
# dag-sync — Local git-sync simulator
# Watches SRC_DIR and rsyncs any change to DEST_DIR immediately,
# with a periodic fallback every SYNC_INTERVAL seconds.

set -euo pipefail

SRC="${SRC_DIR:-/dags-source}"
DEST="${DEST_DIR:-/dags-dest}"
INTERVAL="${SYNC_INTERVAL:-10}"

echo "[dag-sync] Starting — src=${SRC}  dest=${DEST}  interval=${INTERVAL}s"

# Create dest if it doesn't exist
mkdir -p "${DEST}"

# Initial sync on startup
echo "[dag-sync] Initial sync..."
rsync -av --delete "${SRC}/" "${DEST}/"
echo "[dag-sync] Initial sync complete. $(ls "${DEST}" | wc -l | tr -d ' ') file(s) in ${DEST}"

# Run two parallel loops:
# 1. Event-driven: react immediately on inotify events
# 2. Polling:      catch any missed events every INTERVAL seconds

do_sync() {
    local changed_file="${1:-}"
    echo "[dag-sync] Syncing${changed_file:+ (triggered by: ${changed_file})}..."
    rsync -av --delete "${SRC}/" "${DEST}/"
    echo "[dag-sync] Sync done. $(ls "${DEST}" | wc -l | tr -d ' ') file(s)"
}

# Background polling loop
(
    while true; do
        sleep "${INTERVAL}"
        do_sync "poll"
    done
) &
POLL_PID=$!

# Foreground inotify watch loop
inotifywait -m -r -e create,modify,delete,moved_to,moved_from "${SRC}" \
    --format '%f' 2>/dev/null | \
while read -r changed; do
    do_sync "${changed}"
done

# If inotifywait exits (shouldn't normally), kill polling loop
kill "${POLL_PID}" 2>/dev/null || true
