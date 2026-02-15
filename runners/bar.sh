#!/bin/bash
# FILE: runners/bar.sh
# Configure sketchybar for a workspace
#
# Creates namespaced items per workspace (e.g., PUFF_badge, ONTOSYS_label).
# First workspace on a display configures the global bar (--bar settings).
# Subsequent workspaces only add items (--items-only) to avoid flashing.
#
# Usage:
#   ./runners/bar.sh --display 3 --style standard --label "MM" --path ~/git_ckp/mermaid --space 5
#   ./runners/bar.sh --style none

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Logging (matches yb_log format) ---
_bar_ts() {
    python3 -c "import datetime; print(datetime.datetime.now().strftime('%H:%M:%S.%f')[:12], end='')"
}
bar_log() {
    echo "[bar][$(_bar_ts)] $*" >&2
}

# --- Parse args ---
DISPLAY_ID=""
STYLE=""
LABEL="WORKSPACE"
WORK_PATH=""
SPACE_IDX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --style)   STYLE="$2"; shift 2 ;;
        --label)   LABEL="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --space)   SPACE_IDX="$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

if [ -z "$STYLE" ]; then
    echo "Usage: bar.sh --style <standard|minimal|none> [--display <id>] [--label <text>] [--path <dir>] [--space <idx>]"
    exit 1
fi

# Validate SPACE_IDX is numeric (defense against stdout contamination)
if [ -n "$SPACE_IDX" ] && ! [[ "$SPACE_IDX" =~ ^[0-9]+$ ]]; then
    bar_log "ERROR: SPACE_IDX not numeric: '$SPACE_IDX' — clearing"
    SPACE_IDX=""
fi

bar_log "start: style=$STYLE display_id=$DISPLAY_ID space=$SPACE_IDX label=$LABEL"

# Shorten path for display (replace $HOME with ~)
DISPLAY_PATH=$(echo "$WORK_PATH" | sed "s|$HOME|~|")

# Validate DISPLAY_PATH is not contaminated with log text
if [[ "$DISPLAY_PATH" == *"[bar]"* ]] || [[ "$DISPLAY_PATH" == *"workspace check"* ]]; then
    bar_log "ERROR: DISPLAY_PATH contaminated: '$DISPLAY_PATH' — stripping to basename"
    DISPLAY_PATH="~/${DISPLAY_PATH##*/}"
fi

# Style "none" — just hide the bar
if [ "$STYLE" = "none" ]; then
    sketchybar --bar hidden=on 2>/dev/null
    bar_log "hidden (style=none)"
    exit 0
fi

BAR_SCRIPT="$REPO_ROOT/sketchybar/bars/$STYLE.sh"
if [ ! -f "$BAR_SCRIPT" ]; then
    bar_log "ERROR: style '$STYLE' not found at $BAR_SCRIPT"
    exit 1
fi

# --- Resolve display index (CGDirectDisplayID → yabai/sketchybar index) ---
SBAR_DISPLAY=1
if [ -n "$DISPLAY_ID" ] && yabai -m query --displays >/dev/null 2>&1; then
    _IDX=$(yabai -m query --displays | jq -r --argjson did "$DISPLAY_ID" \
        '.[] | select(.id == $did) | .index')
    if [ -n "$_IDX" ]; then
        SBAR_DISPLAY="$_IDX"
        bar_log "display: id=$DISPLAY_ID → index=$SBAR_DISPLAY"
    else
        bar_log "WARN: display id=$DISPLAY_ID not found in yabai, defaulting to 1"
    fi
else
    bar_log "display: no display_id or yabai unavailable, defaulting to 1"
fi

# --- Start sketchybar if not running ---
if ! pgrep -q sketchybar 2>/dev/null; then
    bar_log "starting sketchybar..."
    brew services start sketchybar 2>/dev/null
    sleep 1
    bar_log "sketchybar started"
fi

# --- Namespace prefix (from label) ---
PREFIX="$LABEL"

# --- Determine if another workspace already configured the bar ---
# Check for existing YB namespace items (not just hidden state — default bar is unhidden but unconfigured)
ITEMS_ONLY=""
_HAS_YB_ITEMS=$(sketchybar --query bar 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    items = d.get('items', [])
    yb = [i for i in items if '_badge' in i]
    print('yes' if yb else 'no')
except: print('no')" 2>/dev/null)

if [ "$_HAS_YB_ITEMS" = "yes" ]; then
    ITEMS_ONLY="--items-only"
    bar_log "bar already visible — items-only mode (no global reconfig)"
else
    bar_log "no YB items — full config mode"
fi

# --- Create items via style script ---
bar_log "creating ${PREFIX}_* items (style=$STYLE display=$SBAR_DISPLAY items_only=$ITEMS_ONLY)"
"$BAR_SCRIPT" "$SBAR_DISPLAY" "$LABEL" "$DISPLAY_PATH" "$PREFIX" "$ITEMS_ONLY"
bar_log "items created"

# --- Resolve space index (if not provided via --space) ---
if [ -z "$SPACE_IDX" ] && [ -n "$DISPLAY_ID" ] && yabai -m query --windows >/dev/null 2>&1; then
    bar_log "resolving space from display_id=$DISPLAY_ID"
    YABAI_DISP_IDX=$(yabai -m query --displays | jq -r --argjson did "$DISPLAY_ID" \
        '.[] | select(.id == $did) | .index')
    if [ -n "$YABAI_DISP_IDX" ]; then
        SPACE_IDX=$(yabai -m query --spaces | jq -r --argjson di "$YABAI_DISP_IDX" \
            '.[] | select(.display == $di and .["is-visible"] == true) | .index')
        bar_log "resolved space=$SPACE_IDX (display index=$YABAI_DISP_IDX)"
    else
        bar_log "WARN: could not resolve display index"
    fi
fi

# --- Bind items to the workspace space ---
if [ -n "$SPACE_IDX" ] && [ "$SPACE_IDX" -gt 0 ] 2>/dev/null; then
    bar_log "binding ${PREFIX}_* items to space=$SPACE_IDX"
    for suffix in badge label path code term folder close bg; do
        sketchybar --set "${PREFIX}_${suffix}" associated_space=$SPACE_IDX 2>/dev/null
    done
    sketchybar --update 2>/dev/null
    bar_log "items bound to space=$SPACE_IDX"
else
    bar_log "WARN: no valid space index — items not bound"
fi

bar_log "done"
