#!/bin/bash
# Close workspace: hover effect + click to destroy
# Closes primary + secondary app windows, removes bar items

_CLOSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$_CLOSE_ROOT/lib/common.sh"
source "$_CLOSE_ROOT/lib/app/code.sh"
source "$_CLOSE_ROOT/lib/app/iterm.sh"
source "$_CLOSE_ROOT/lib/app/terminal.sh"

case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff000000 \
            background.drawing=on \
            background.color=0xddff6666 \
            background.corner_radius=6 \
            background.height=22
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0xccffffff \
            background.drawing=off
        ;;
    mouse.clicked)
        # Get workspace path from space_path label
        WPATH=$(sketchybar --query space_path 2>/dev/null | python3 -c "
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

        # Close all known app types (no-op if window doesn't exist)
        app_code_close "$FULL_PATH"
        app_iterm_close "$FULL_PATH"
        app_terminal_close "$FULL_PATH"

        # Remove all bar items
        for item in yb_badge space_label space_path action_code action_term action_folder action_close; do
            sketchybar --remove "$item" 2>/dev/null
        done
        sketchybar --bar hidden=on 2>/dev/null
        ;;
esac
