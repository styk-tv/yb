#!/bin/bash
# FILE: runners/bar.sh
# Configure sketchybar for a workspace
#
# Starts sketchybar if needed, then always applies the full style.
# --display takes CGDirectDisplayID (matches sketchybar display index).
#
# Usage:
#   ./runners/bar.sh --display 3 --style standard --label "MM" --path ~/git_ckp/mermaid
#   ./runners/bar.sh --style none

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DISPLAY_ID=""
STYLE=""
LABEL="WORKSPACE"
WORK_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --style)   STYLE="$2"; shift 2 ;;
        --label)   LABEL="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

if [ -z "$STYLE" ]; then
    echo "Usage: bar.sh --style <standard|minimal|none> [--display <id>] [--label <text>] [--path <dir>]"
    exit 1
fi

# Shorten path for display (replace $HOME with ~)
DISPLAY_PATH=$(echo "$WORK_PATH" | sed "s|$HOME|~|")

# Style "none" — just hide the bar
if [ "$STYLE" = "none" ]; then
    sketchybar --bar hidden=on 2>/dev/null
    echo "[bar]   hidden"
    exit 0
fi

BAR_SCRIPT="$REPO_ROOT/sketchybar/bars/$STYLE.sh"
if [ ! -f "$BAR_SCRIPT" ]; then
    echo "[bar]   error: style '$STYLE' not found at $BAR_SCRIPT"
    exit 1
fi

# Start sketchybar if not running
if ! pgrep -q sketchybar 2>/dev/null; then
    echo "[bar]   starting sketchybar..."
    brew services start sketchybar 2>/dev/null
    sleep 1
fi

# Use display=all — associated_space binding controls which display shows items
SBAR_DISPLAY="all"

echo "[bar]   style=$STYLE display=$SBAR_DISPLAY label=$LABEL path=$DISPLAY_PATH"

# Always apply full style — bar scripts are idempotent
"$BAR_SCRIPT" "$SBAR_DISPLAY" "$LABEL" "$DISPLAY_PATH"

# Verify items exist — if sketchybar restarted or lost state, retry once
VERIFY=$(sketchybar --query yb_badge 2>&1 | head -1)
if [ -z "$VERIFY" ] || [[ "$VERIFY" == *"not found"* ]]; then
    echo "[bar]   items missing — restarting sketchybar..."
    brew services restart sketchybar 2>/dev/null
    sleep 2
    "$BAR_SCRIPT" "$SBAR_DISPLAY" "$LABEL" "$DISPLAY_PATH"
fi

# --- Bind items to the current space on target display ---
# Items should only show on the YB-managed desktop, not all desktops.
if [ -n "$DISPLAY_ID" ] && yabai -m query --windows >/dev/null 2>&1; then
    # Use yabai to find the visible space on the target display
    YABAI_DISP_IDX=$(yabai -m query --displays | jq -r --argjson did "$DISPLAY_ID" \
        '.[] | select(.id == $did) | .index')

    if [ -n "$YABAI_DISP_IDX" ]; then
        SPACE_IDX=$(yabai -m query --spaces | jq -r --argjson di "$YABAI_DISP_IDX" \
            '.[] | select(.display == $di and .["is-visible"] == true) | .index')
    fi

    if [ -n "$SPACE_IDX" ] && [ "$SPACE_IDX" -gt 0 ] 2>/dev/null; then
        echo "[bar]   binding to space $SPACE_IDX"
        for item in yb_badge space_label space_path action_code action_term action_folder action_close; do
            sketchybar --set "$item" associated_space=$SPACE_IDX 2>/dev/null
        done
        sketchybar --update 2>/dev/null
    fi
fi

echo "[bar]   done"
