#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PID_FILE="$DIR/server.pid"

TARGET_PID=""

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        TARGET_PID="$PID"
    fi
fi

# Fallback: search for running pumpkin process in this workspace
if [ -z "$TARGET_PID" ]; then
    TARGET_PID=$(pgrep -f "^$DIR/pumpkin" || pgrep -f "^\./pumpkin" || pgrep -x "pumpkin" || true)
fi

if [ -z "$TARGET_PID" ]; then
    echo "Pumpkin server is not running."
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping Pumpkin server (PID $TARGET_PID)..."
kill -TERM "$TARGET_PID" 2>/dev/null || true

# Wait up to 10 seconds for graceful shutdown
TIMEOUT=10
while kill -0 "$TARGET_PID" 2>/dev/null && [ "$TIMEOUT" -gt 0 ]; do
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if kill -0 "$TARGET_PID" 2>/dev/null; then
    echo "Server did not shut down gracefully in time. Force stopping (SIGKILL)..."
    kill -KILL "$TARGET_PID" 2>/dev/null || true
    sleep 1
fi

rm -f "$PID_FILE"
echo "Pumpkin server stopped successfully."
