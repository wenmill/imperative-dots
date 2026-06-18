#!/usr/bin/env bash
# Matrix device verification helper, driven by the QML Matrix popup.
#
# WHAT THIS DOES
#   Runs `matrix-commander --verify emoji` (real E2EE via matrix-nio + libolm).
#   matrix-commander waits for your OTHER device (Element on your phone) to start
#   a verification, then prints the SAS emojis. We capture those emojis to a file
#   the QML reads, and we feed the user's Yes/No back into matrix-commander's stdin
#   through a FIFO. This makes the interactive CLI flow drivable from the GUI.
#
# IMPORTANT
#   This verifies the *matrix-commander* device, not the QML REST client (they are
#   separate devices on your account; the QML one has no crypto). After this, the
#   matrix-commander device shows a green shield in Element.
#
# FILES (under ~/.cache/qs_matrix/verify/)
#   emoji.txt   — the emoji line matrix-commander printed (QML displays this)
#   status.txt  — one of: starting | waiting | emojis | done | failed
#   answer.fifo — QML writes "yes" or "no" here to confirm/reject
#   log.txt     — full matrix-commander output for debugging
set -uo pipefail

MC_STORE="$HOME/.config/matrix-commander"     # matrix-commander's creds+crypto store
VDIR="$HOME/.cache/qs_matrix/verify"
mkdir -p "$VDIR"; chmod 700 "$VDIR"
EMOJI="$VDIR/emoji.txt"; STATUS="$VDIR/status.txt"
FIFO="$VDIR/answer.fifo"; LOG="$VDIR/log.txt"

set_status() { printf '%s' "$1" > "$STATUS"; }

case "${1:-verify}" in
    check)
        # Report whether matrix-commander is installed + logged in.
        if ! command -v matrix-commander >/dev/null 2>&1; then echo "notinstalled"; exit 0; fi
        if [ -f "$MC_STORE/credentials.json" ]; then echo "loggedin"; else echo "needlogin"; fi
        ;;

    login)
        # Non-interactive login. Args: homeserver user password device-name
        # (Password login; matrix-commander stores creds + sets up the crypto store.)
        HS="$2"; USER="$3"; PASS="$4"; DEV="${5:-quickshell-cli}"
        matrix-commander --login password \
            --homeserver "$HS" --user-login "$USER" --password "$PASS" \
            --device "$DEV" --room-default "" >"$LOG" 2>&1 \
            && echo "ok" || { echo "failed"; tail -3 "$LOG"; }
        ;;

    verify)
        # Interactive emoji verification, GUI-driven.
        rm -f "$EMOJI" "$FIFO"; mkfifo "$FIFO"
        set_status "starting"; : > "$EMOJI"
        # Run matrix-commander reading Yes/No from the FIFO; tee everything to LOG and
        # parse stdout line-by-line to surface the emojis + prompts to the QML.
        (
            # Keep the FIFO open for writing so matrix-commander's stdin doesn't EOF
            # before the user answers.
            exec 3<>"$FIFO"
            matrix-commander --verify emoji <&3 2>&1 | while IFS= read -r line; do
                printf '%s\n' "$line" >> "$LOG"
                # matrix-commander prints the emoji set after the peer starts verify.
                # Lines with the emoji glyphs + names follow a recognizable pattern;
                # capture the block and expose it.
                case "$line" in
                    *"waiting for"*|*"Waiting for"*|*"ready and waiting"*)
                        set_status "waiting" ;;
                    *"Emoji"*|*"emoji"*)
                        set_status "emojis" ;;
                esac
                # Heuristic: emoji verification lines contain non-ASCII glyphs.
                if printf '%s' "$line" | grep -qP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]'; then
                    printf '%s\n' "$line" >> "$EMOJI"
                    set_status "emojis"
                fi
                # When matrix-commander asks to confirm, the QML's Yes/No has already
                # been (or will be) written to the FIFO by the user pressing a button.
                case "$line" in
                    *"Match"*|*"match?"*|*"yes/no"*|*"(Y/n)"*)
                        set_status "emojis" ;;
                    *"verified"*|*"Verified"*|*"success"*|*"Success"*)
                        set_status "done" ;;
                    *"cancel"*|*"Cancel"*|*"fail"*|*"Fail"*|*"timeout"*|*"Timeout"*)
                        set_status "failed" ;;
                esac
            done
            exec 3>&-
        ) &
        echo $! > "$VDIR/verify.pid"
        echo "started"
        ;;

    answer)
        # QML writes the user's decision: $2 = yes|no
        ANS="${2:-no}"
        if [ -p "$FIFO" ]; then
            if [ "$ANS" = "yes" ]; then printf 'Yes\n' > "$FIFO"; else printf 'No\n' > "$FIFO"; fi
            echo "sent $ANS"
        else
            echo "no-fifo"
        fi
        ;;

    cancel)
        [ -f "$VDIR/verify.pid" ] && kill "$(cat "$VDIR/verify.pid")" 2>/dev/null
        pkill -f "matrix-commander --verify" 2>/dev/null
        set_status "failed"; rm -f "$FIFO"
        echo "cancelled"
        ;;
esac
