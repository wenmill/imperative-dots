#!/usr/bin/env bash
# System maintenance helper for the battery popup "update" button.
# SAFE BY DESIGN:
#   - Read-only checks (check/orphans/audit) need NO root and touch nothing.
#   - Destructive actions (update/clean/remove-orphans) open a visible kitty
#     terminal running sudo, so you type your password and watch/confirm.
#   - Results are written to ~/.cache/qs_sysmaintain.json for the popup to read.
set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
OUT="$CACHE/qs_sysmaintain.json"
mkdir -p "$CACHE"

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'; }

write_status() {
    # $1=phase $2=updates_count $3=orphans_count $4=vuln_count $5=detail
    local detail_json; detail_json=$(printf '%s' "${5:-}" | json_escape)
    cat > "$OUT" <<EOF
{"phase":"$1","updates":${2:-0},"orphans":${3:-0},"vulns":${4:-0},"detail":${detail_json},"ts":$(date +%s)}
EOF
}

# Launch kitty as a FLOATING window docked over the popup, using Hyprland inline
# window rules so it floats reliably without needing any hyprland.conf edits.
# Args: $1 = window title, $2 = script to run inside kitty.
launch_floating_kitty() {
    local title="$1" runscript="$2"
    if command -v hyprctl >/dev/null 2>&1; then
        # Compute a top-right position from the FOCUSED monitor's real dimensions,
        # so it lands correctly on any resolution (3440x1440 etc.) with no guessing.
        local mon mw mh side kx ky margin=20 topgap=70
        mon=$(hyprctl monitors -j 2>/dev/null)
        mw=$(printf '%s' "$mon" | python3 -c 'import json,sys; m=[x for x in json.load(sys.stdin) if x.get("focused")]; print(m[0]["width"] if m else 1920)' 2>/dev/null || echo 1920)
        mh=$(printf '%s' "$mon" | python3 -c 'import json,sys; m=[x for x in json.load(sys.stdin) if x.get("focused")]; print(m[0]["height"] if m else 1080)' 2>/dev/null || echo 1080)
        side=$(( mh * 55 / 100 ))   # square: side = 55% of screen height
        kx=$(( mw - side - margin ))  # hug the right edge
        ky=$topgap                  # a little down from the top
        local rules="[float;size ${side} ${side};move ${kx} ${ky}]"
        hyprctl dispatch exec "$rules kitty --class qs-sysmaintain --title '$title' -e bash $runscript" >/dev/null 2>&1
        # Focus the terminal as soon as it appears (so you can type the sudo password)
        # WITHOUT closing the battery popup — the popup is a layer-shell surface, so
        # focusing a normal window doesn't dismiss it.
        ( for _ in 1 2 3 4 5 6 7 8 9 10; do
              if hyprctl clients -j 2>/dev/null | grep -q 'qs-sysmaintain'; then
                  hyprctl dispatch focuswindow "class:^(qs-sysmaintain)$" >/dev/null 2>&1
                  break
              fi
              sleep 0.15
          done ) &
    else
        kitty --class qs-sysmaintain --title "$title" -e bash "$runscript" &
    fi
}

case "${1:-check}" in
    check)
        # ---- READ-ONLY preview. No root, no DB modification. ----
        # checkupdates (pacman-contrib) uses a temp DB copy — never touches the real one.
        if command -v checkupdates >/dev/null 2>&1; then
            UPD="$(checkupdates 2>/dev/null)"
        else
            UPD=""; MISSING_CU=1
        fi
        UPD_N=$(printf '%s' "$UPD" | grep -c . )
        ORPH="$(pacman -Qdtq 2>/dev/null)"
        ORPH_N=$(printf '%s' "$ORPH" | grep -c . )
        if command -v arch-audit >/dev/null 2>&1; then
            VULN="$(arch-audit -q --upgradable 2>/dev/null)"
            VULN_N=$(printf '%s' "$VULN" | grep -c . )
        else
            VULN=""; VULN_N=0
        fi
        DETAIL=""
        [ -n "$UPD" ]  && DETAIL+="── Updates ($UPD_N) ──"$'\n'"$UPD"$'\n\n'
        [ -n "$ORPH" ] && DETAIL+="── Orphans ($ORPH_N) ──"$'\n'"$ORPH"$'\n\n'
        if [ "$VULN_N" -gt 0 ]; then DETAIL+="── Vulnerable ($VULN_N) ──"$'\n'"$VULN"$'\n'
        elif command -v arch-audit >/dev/null 2>&1; then DETAIL+="── Security ──"$'\n'"No known vulnerabilities."$'\n'
        else DETAIL+="── Security ──"$'\n'"arch-audit not installed."$'\n'; fi
        [ -z "$DETAIL" ] && DETAIL="System is fully up to date. Nothing to do."
        [ -n "${MISSING_CU:-}" ] && DETAIL="── Note ──"$'\n'"checkupdates not found — install pacman-contrib."$'\n\n'"$DETAIL"
        write_status "ready" "$UPD_N" "$ORPH_N" "$VULN_N" "$DETAIL"
        ;;

    update)
        # ---- Full upgrade in a floating terminal docked over the popup. ----
        write_status "running" 0 0 0 "Update running in terminal…"
        cat > /tmp/qs_sysmaintain_run.sh <<'INNER'
#!/usr/bin/env bash
echo "=== System Update (pacman -Syu) ==="
sudo pacman -Syu
echo; echo "=== Cleaning package cache (keep last 3) ==="
sudo paccache -r
echo; echo "Done. Press enter to close."; read
INNER
        chmod +x /tmp/qs_sysmaintain_run.sh
        launch_floating_kitty "System Update" /tmp/qs_sysmaintain_run.sh
        ;;

    clean)
        write_status "running" 0 0 0 "Cache clean running in terminal…"
        cat > /tmp/qs_sysmaintain_run.sh <<'INNER'
#!/usr/bin/env bash
echo "=== paccache -r (keep last 3 versions) ==="
sudo paccache -r
echo; echo "Done. Press enter to close."; read
INNER
        chmod +x /tmp/qs_sysmaintain_run.sh
        launch_floating_kitty "Clean Package Cache" /tmp/qs_sysmaintain_run.sh
        ;;

    orphans)
        # Remove orphans — explicit, floating, visible. Lists them first.
        write_status "running" 0 0 0 "Orphan removal running in terminal…"
        cat > /tmp/qs_sysmaintain_run.sh <<'INNER'
#!/usr/bin/env bash
ORPH=$(pacman -Qdtq)
if [ -z "$ORPH" ]; then echo "No orphaned packages."; else
  echo "Orphaned packages to remove:"; echo "$ORPH"; echo
  sudo pacman -Rns $ORPH
fi
echo; echo "Done. Press enter to close."; read
INNER
        chmod +x /tmp/qs_sysmaintain_run.sh
        launch_floating_kitty "Remove Orphans" /tmp/qs_sysmaintain_run.sh
        ;;
esac
