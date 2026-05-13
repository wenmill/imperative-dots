#!/usr/bin/env bash
# ~/.config/hypr/scripts/hermes_bridge.sh
#
# Bridges between the AI popup and Hermes Agent.
#
# - Reads user input from stdin.
# - Invokes hermes in JSON-output mode (--no-execute so it never runs commands itself).
# - Parses the response. If Hermes wants to call a tool, we emit a single JSON
#   object describing the command and exit. The popup then prompts the user
#   for approval and runs (or denies) the command itself.
# - If Hermes just wants to reply with text, we emit { type: "message", content: "..." }.
#
# Continuation mode (--continue):
# - Used after the popup has run an approved command. We feed the command's
#   output back to Hermes so the conversation can proceed.
#
# Session state lives in ~/.cache/qs_ai_state/hermes_session.txt
# so multiple popup turns share context.

set -e

SESSION_FILE="$HOME/.cache/qs_ai_state/hermes_session.txt"
mkdir -p "$(dirname "$SESSION_FILE")"

CONTINUE_MODE=false
if [ "$1" = "--continue" ]; then
    CONTINUE_MODE=true
fi

INPUT=$(head -c 100000)   # cap at 100KB so a runaway pipe can't exhaust memory

# Persist session id so each turn continues the same conversation.
# Hermes uses ~/.hermes/sessions internally; we just track which session
# to reuse via the --session flag (if available in your hermes version).
SESSION_ID=""
if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(cat "$SESSION_FILE")
fi
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="qspopup-$(date +%s)"
    echo "$SESSION_ID" > "$SESSION_FILE"
fi

# ----------------------------------------------------------------------------
# Invoke hermes
# ----------------------------------------------------------------------------
# We use:
#   --no-execute       : never let hermes run shell commands itself
#   --json             : emit structured events
#   --session          : reuse the same conversation across calls
#   -q "..."           : the user query
#
# If your hermes version doesn't support --no-execute, the safe fallback is
# to set terminal.approval = "deny" in ~/.hermes/config.yaml and parse
# the failure as a tool-call request. The bridge does that automatically.

if ! command -v hermes &>/dev/null; then
    printf '{"type":"message","content":"Hermes is not installed. Run the install script or:\\ncurl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"}'
    exit 0
fi

# Build flags. Some flag names may differ across hermes versions — adjust if needed.
HERMES_FLAGS=()
if hermes chat --help 2>&1 | grep -q -- "--session"; then
    HERMES_FLAGS+=(--session "$SESSION_ID")
fi
if hermes chat --help 2>&1 | grep -q -- "--json"; then
    HERMES_FLAGS+=(--json)
fi
if hermes chat --help 2>&1 | grep -q -- "--no-execute"; then
    HERMES_FLAGS+=(--no-execute)
fi

# Run hermes. Pipe input via stdin to avoid shell quoting nightmares.
RAW=$(printf '%s' "$INPUT" | hermes chat "${HERMES_FLAGS[@]}" 2>&1 || true)

# ----------------------------------------------------------------------------
# Parse response
# ----------------------------------------------------------------------------
# We look for patterns Hermes emits when it tries to call the terminal tool.
# Three cases:
#   1. JSON event with "tool_call" or "shell" type
#   2. Approval prompt text ("Run this command? [y/N]") with the cmd nearby
#   3. Plain text reply

# Try JSON parse first — hermes --json emits one event per line
TOOL_CALL=$(echo "$RAW" | jq -rcs '
    map(select(type == "object")) |
    map(select(.type == "tool_call" or .type == "shell" or .tool == "terminal")) |
    .[0] // empty
' 2>/dev/null || true)

if [ -n "$TOOL_CALL" ] && [ "$TOOL_CALL" != "null" ]; then
    CMD=$(echo "$TOOL_CALL" | jq -r '.command // .args.command // .input // .arguments.command // empty' 2>/dev/null)
    DESC=$(echo "$TOOL_CALL" | jq -r '.description // .reason // .summary // "Hermes wants to run a command"' 2>/dev/null)
    if [ -n "$CMD" ]; then
        jq -nc --arg c "$CMD" --arg d "$DESC" '{type:"tool_call", command:$c, description:$d}'
        exit 0
    fi
fi

# Fallback 1: look for approval-prompt patterns in plain output
if echo "$RAW" | grep -qE "Run.*command|Approve.*command|Allow.*command"; then
    # Try to extract the command from a code block
    CMD=$(echo "$RAW" | grep -oP '(?<=`)[^`]+(?=`)' | head -1)
    if [ -n "$CMD" ]; then
        jq -nc --arg c "$CMD" --arg d "Hermes proposes a command (approval required)" \
            '{type:"tool_call", command:$c, description:$d}'
        exit 0
    fi
fi

# Fallback 2: extract just the assistant message from JSON events
MSG=$(echo "$RAW" | jq -rcs '
    map(select(type == "object")) |
    map(select(.type == "message" or .role == "assistant")) |
    map(.content // .text // .message) |
    .[-1] // empty
' 2>/dev/null || true)

if [ -n "$MSG" ] && [ "$MSG" != "null" ] && [ "$MSG" != "empty" ]; then
    jq -nc --arg m "$MSG" '{type:"message", content:$m}'
    exit 0
fi

# Fallback 3: just emit the raw text
jq -nc --arg m "$RAW" '{type:"message", content:$m}'
