#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

PID_FILE="$DIR/server.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Pumpkin server is already running with PID $PID."
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

echo "Starting Pumpkin Server (Minecraft 26.2)..."
./pumpkin &
PID=$!
echo "$PID" > "$PID_FILE"

# Clean up on exit or signal
cleanup() {
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping Pumpkin server (PID $PID)..."
        kill -TERM "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
}
trap cleanup INT TERM EXIT

wait "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
