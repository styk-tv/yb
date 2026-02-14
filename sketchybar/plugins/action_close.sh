#!/bin/bash
# Close workspace: hover effect + click to destroy
# Closes primary + secondary app windows, removes namespaced bar items
# Item names are prefixed with workspace label (e.g., PUFF_close, ONTOSYS_close)

_CLOSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$_CLOSE_ROOT/lib/common.sh"
source "$_CLOSE_ROOT/lib/app/code.sh"
source "$_CLOSE_ROOT/lib/app/iterm.sh"
source "$_CLOSE_ROOT/lib/app/terminal.sh"

# Extract prefix from item name: PUFF_close → PUFF
PREFIX="${NAME%_close}"

case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff1e1e1e \
            background.drawing=on \
            background.color=0xddff6666 \
            background.corner_radius=8 \
            background.height=36
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0x99ffffff \
            background.drawing=off
        ;;
    mouse.clicked)
        # Get workspace path from namespaced path item
        WPATH=$(sketchybar --query "${PREFIX}_path" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('label', {}).get('value', ''))
except: pass" 2>/dev/null)
        FOLDER=$(basename "$WPATH")
        FULL_PATH=$(echo "$WPATH" | sed "s|~|$HOME|")

        if [ -z "$FOLDER" ] || [ "$FOLDER" = "." ]; then
            exit 0
        fi

        # Spinner animation while closing
        _SPINNER_CHARS=(◐ ◓ ◑ ◒)
        _spin_close() {
            local i=0
            while true; do
                sketchybar --set "$NAME" icon="${_SPINNER_CHARS[$((i % 4))]}" icon.color=0xffff6666 2>/dev/null
                sleep 0.15
                i=$((i + 1))
            done
        }
        _spin_close &
        _SPINNER_PID=$!

        # Close all known app types (no-op if window doesn't exist)
        app_code_close "$FULL_PATH"
        app_iterm_close "$FULL_PATH"
        app_terminal_close "$FULL_PATH"

        # Stop spinner
        kill $_SPINNER_PID 2>/dev/null
        wait $_SPINNER_PID 2>/dev/null

        # Remove all namespaced bar items
        for suffix in badge label path code term folder close; do
            sketchybar --remove "${PREFIX}_${suffix}" 2>/dev/null
        done
        ;;
esac
