#!/usr/bin/env bash
# Build and manage the matrixd daemon (matrix-rust-sdk backend).
#   build  — compile the release binary (needs the Rust toolchain + libolm-free; uses vodozemac)
#   start  — launch the daemon if not running
#   stop   — stop it
#   status — is it running?
# The QML popup talks to the daemon over the Unix socket; this script just builds/runs it.
set -uo pipefail

DIR="$HOME/.config/hypr/scripts/quickshell/matrix/matrixd"
BIN="$DIR/target/release/matrixd"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/qs_matrixd.sock"

case "${1:-status}" in
  build)
    command -v cargo >/dev/null 2>&1 || { echo "Rust toolchain not found. Install: rustup (https://rustup.rs) or 'pacman -S rust'"; exit 1; }
    echo "Building matrixd (first build downloads many crates, can take several minutes)…"
    ( cd "$DIR" && cargo build --release ) && echo "Built: $BIN" || { echo "Build failed"; exit 1; }
    ;;
  start)
    if pgrep -f "$BIN" >/dev/null 2>&1; then echo "already running"; exit 0; fi
    [ -x "$BIN" ] || { echo "not built yet — run: $0 build"; exit 1; }
    setsid "$BIN" >"$HOME/.cache/qs_matrix/matrixd.log" 2>&1 &
    echo "started"
    ;;
  stop)
    pkill -f "$BIN" 2>/dev/null; rm -f "$SOCK"; echo "stopped"
    ;;
  status)
    if pgrep -f "$BIN" >/dev/null 2>&1; then echo "running"; else echo "stopped"; fi
    ;;
esac
