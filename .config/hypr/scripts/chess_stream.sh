#!/usr/bin/env bash
# ~/.config/hypr/scripts/quickshell/chess_stream.sh
#
# Streams Lichess game events to /tmp/qs_chess_event line by line.
# Token is read from $LICHESS_TOKEN env var (not argv) so it doesn't
# show up in `ps aux` to other processes on the machine.

set -u

if [ -z "${LICHESS_TOKEN:-}" ]; then
    echo "ERROR: LICHESS_TOKEN env var not set" >&2
    exit 1
fi

GAME_ID="${1:-}"
# Lichess game IDs are exactly 8 alphanumeric characters
if ! [[ "$GAME_ID" =~ ^[a-zA-Z0-9]{8}$ ]]; then
    echo "ERROR: invalid game ID: $GAME_ID" >&2
    exit 1
fi

EVENT_FILE="/tmp/qs_chess_event"

curl -s --no-buffer \
    -H "Authorization: Bearer $LICHESS_TOKEN" \
    "https://lichess.org/api/board/game/stream/$GAME_ID" 2>/dev/null \
| while IFS= read -r line; do
    [ -n "$line" ] && printf '%s\n' "$line" > "$EVENT_FILE"
done
