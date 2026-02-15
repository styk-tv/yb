#!/bin/bash
# Close workspace: hover effect + click to destroy
# Closes primary + secondary app windows, removes namespaced bar items
# Item names are prefixed with workspace label (e.g., PUFF_close, ONTOSYS_close)

_CLOSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$_CLOSE_ROOT/lib/common.sh"

# Determine engine and load app handlers (shared + engine override)
_ENGINE="jxa"
yb_yabai_ok && _ENGINE="yabai"
for _app in code iterm terminal; do
    source "$_CLOSE_ROOT/lib/app/${_app}.sh"
    [ -f "$_CLOSE_ROOT/lib/app/${_app}.${_ENGINE}.sh" ] && source "$_CLOSE_ROOT/lib/app/${_app}.${_ENGINE}.sh"
done

# Extract prefix from item name: PUFF_close → PUFF
PREFIX="${NAME%_close}"

case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff020d06 \
            background.drawing=on \
            background.color=0xddff6666 \
            background.corner_radius=8 \
            background.height=36
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0xbba0ada3 \
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

        # Resolve space index BEFORE closing (from badge item bitmask)
        _SPACE_IDX=""
        _MASK=$(sketchybar --query "${PREFIX}_badge" 2>/dev/null | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
        if [ -n "$_MASK" ] && [ "$_MASK" -gt 0 ] 2>/dev/null; then
            _b=$_MASK _n=0
            while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
            _SPACE_IDX="$_n"
        fi

        # Close ALL non-sticky windows on this managed space (by space ownership, not text search)
        if [ -n "$_SPACE_IDX" ] && yabai -m query --windows >/dev/null 2>&1; then
            _WIDS=$(yabai -m query --windows | jq -r --argjson sp "$_SPACE_IDX" \
                '.[] | select(.space == $sp) | select(.["is-sticky"] == false) | .id')
            for _wid in $_WIDS; do
                yabai -m window "$_wid" --close 2>/dev/null
            done
        fi

        # Stop spinner
        kill $_SPINNER_PID 2>/dev/null
        wait $_SPINNER_PID 2>/dev/null

        # Remove all namespaced bar items
        for suffix in badge label path code term folder close; do
            sketchybar --remove "${PREFIX}_${suffix}" 2>/dev/null
        done

        # Space left as empty — will be reused on next launch
        ;;
esac
