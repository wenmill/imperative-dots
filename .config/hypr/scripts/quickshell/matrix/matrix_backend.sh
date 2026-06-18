#!/usr/bin/env bash
# Matrix backend for the QML popup, fully via matrix-commander (E2EE, one device).
# The QML calls these actions; each prints/normalizes JSON the QML can parse, or
# runs the live listener that streams decrypted messages to a file the QML tails.
#
# Actions:
#   status            -> {"loggedin":bool,"verified":bool,"user":"@u:hs"}
#   rooms             -> [{"id","name","topic"}...]            (joined rooms)
#   history <roomId> <n>  -> [{"id","sender","body","msgtype","ts"}...] newest..oldest
#   listen            -> runs forever; appends each incoming msg (JSON line) to events file
#   send <roomId> <text(base64)>  -> sends (encrypted); echoes ok/err
#   stop-listen       -> kills the listener
set -uo pipefail

MC=matrix-commander
SDIR="$HOME/.cache/qs_matrix"
EVENTS="$SDIR/events.jsonl"        # live incoming messages, one JSON per line
mkdir -p "$SDIR"; chmod 700 "$SDIR"

have_mc() { command -v "$MC" >/dev/null 2>&1; }

case "${1:-status}" in
  status)
    if ! have_mc; then echo '{"loggedin":false,"verified":false,"user":"","mc":false}'; exit 0; fi
    U="$($MC --whoami 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$U" ]; then
      printf '{"loggedin":true,"verified":true,"user":%s,"mc":true}\n' "$(printf '%s' "$U" | jq -Rs .)"
    else
      echo '{"loggedin":false,"verified":false,"user":"","mc":true}'
    fi
    ;;

  rooms)
    # Joined rooms + their display names. --joined-rooms gives ids; --get-room-info
    # gives name/topic. We merge them into a compact array.
    IDS="$($MC --joined-rooms 2>/dev/null | tr ' ' '\n' | grep '^!' )"
    printf '['
    first=1
    while IFS= read -r rid; do
      [ -z "$rid" ] && continue
      INFO="$($MC --room-get-info "$rid" --output json 2>/dev/null | head -1)"
      NAME="$(printf '%s' "$INFO" | jq -r '.display_name // .name // empty' 2>/dev/null)"
      TOPIC="$(printf '%s' "$INFO" | jq -r '.topic // empty' 2>/dev/null)"
      [ -z "$NAME" ] && NAME="$rid"
      [ $first -eq 0 ] && printf ','
      first=0
      printf '{"id":%s,"name":%s,"topic":%s}' \
        "$(printf '%s' "$rid" | jq -Rs .)" \
        "$(printf '%s' "$NAME" | jq -Rs .)" \
        "$(printf '%s' "$TOPIC" | jq -Rs .)"
    done <<< "$IDS"
    printf ']\n'
    ;;

  history)
    RID="$2"; N="${3:-50}"
    # Tail the last N messages of one room as JSON, normalize to the QML shape.
    $MC --listen tail --tail "$N" --listen-self --room "$RID" --output json 2>/dev/null \
      | jq -c 'select(.source.content.msgtype != null) | {
          id: (.source.event_id // ""),
          sender: (.source.sender // ""),
          body: (.source.content.body // ""),
          msgtype: (.source.content.msgtype // "m.text"),
          ts: (.source.origin_server_ts // 0)
        }' 2>/dev/null | jq -s '.'
    ;;

  listen)
    # Stream incoming decrypted messages forever; append normalized JSON lines.
    : > "$EVENTS"
    exec $MC --listen forever --listen-self --output json 2>/dev/null \
      | stdbuf -oL jq -c --unbuffered 'select(.source.content.msgtype != null) | {
          room: (.room // .source.room_id // ""),
          id: (.source.event_id // ""),
          sender: (.source.sender // ""),
          body: (.source.content.body // ""),
          msgtype: (.source.content.msgtype // "m.text"),
          ts: (.source.origin_server_ts // 0)
        }' 2>/dev/null >> "$EVENTS"
    ;;

  send)
    RID="$2"; TXT="$(printf '%s' "$3" | base64 -d 2>/dev/null)"
    $MC -m "$TXT" --room "$RID" >/dev/null 2>&1 && echo ok || echo err
    ;;

  stop-listen)
    pkill -f "matrix-commander --listen forever" 2>/dev/null; echo stopped
    ;;
esac
