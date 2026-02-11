#!/bin/bash
# FILE: runners/bar.sh
# Configure sketchybar for a workspace
#
# Starts sketchybar if needed, then always applies the full style.
# --display takes CGDirectDisplayID; probes sketchybar to find the matching index.
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

# --- Probe: discover CGDirectDisplayID → sketchybar display index ---
# Sketchybar uses its own display numbering that doesn't match NSScreen order.
# We show the bar on all displays, add a probe item, read its bounding_rects
# (which have display-N keys with CG coordinates), then match those against
# NSScreen frames (converted to CG coords) to find the correct index.
SBAR_DISPLAY=1
if [ -n "$DISPLAY_ID" ]; then
    # Step 1: Get NSScreen frames in CG coordinates (did:cg_x:cg_y:w:h per line)
    NS_DATA=$(osascript -l JavaScript -e '
ObjC.import("AppKit");
var s = $.NSScreen.screens;
var primaryH = 0;
for (var i = 0; i < s.count; i++) {
    var f = s.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
}
var r = [];
for (var i = 0; i < s.count; i++) {
    var sc = s.objectAtIndex(i);
    var d = ObjC.unwrap(sc.deviceDescription.objectForKey("NSScreenNumber"));
    var f = sc.frame;
    var cgY = primaryH - f.origin.y - f.size.height;
    r.push(d + ":" + f.origin.x + ":" + cgY + ":" + f.size.width + ":" + f.size.height);
}
r.join("\n");' 2>/dev/null)

    # Step 2: Show bar on all displays and add a probe item
    sketchybar --bar display=all hidden=off 2>/dev/null
    sketchybar --add item _yb_probe left 2>/dev/null
    sketchybar --set _yb_probe label="." 2>/dev/null
    sketchybar --update 2>/dev/null
    sleep 0.3

    # Step 3: Query probe bounding_rects, match against screen CG rects
    SBAR_DISPLAY=$(sketchybar --query _yb_probe 2>/dev/null | python3 -c "
import json, sys

target_did = $DISPLAY_ID
item = json.load(sys.stdin)
rects = item.get('bounding_rects', {})

# Parse NSScreen data (already in CG coordinates)
screens = {}
for line in '''$NS_DATA'''.strip().split('\n'):
    parts = line.split(':')
    did = int(parts[0])
    x, y, w, h = float(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
    screens[did] = (x, y, x + w, y + h)

# Match each display-N bounding_rect point against screen CG rects
for key, rect in rects.items():
    if not key.startswith('display-'):
        continue
    sbar_idx = int(key.split('-')[1])
    ox, oy = rect['origin'][0], rect['origin'][1]
    for did, (x0, y0, x1, y1) in screens.items():
        if x0 <= ox < x1 and y0 <= oy < y1:
            if did == target_did:
                print(sbar_idx)
                sys.exit(0)
            break

print(1)
" 2>/dev/null)

    # Clean up probe
    sketchybar --remove _yb_probe 2>/dev/null
    [ -z "$SBAR_DISPLAY" ] && SBAR_DISPLAY=1
fi

echo "[bar]   style=$STYLE display=$DISPLAY_ID->sbar=$SBAR_DISPLAY label=$LABEL path=$DISPLAY_PATH"

# Always apply full style — bar scripts are idempotent
"$BAR_SCRIPT" "$SBAR_DISPLAY" "$LABEL" "$DISPLAY_PATH"

# --- Bind items to the current space on target display ---
# Items should only show on the YB-managed desktop, not all desktops.
if [ -n "$DISPLAY_ID" ]; then
    # Get display UUID
    DISPLAY_UUID=$(osascript -l JavaScript \
        -e "var targetDID = $DISPLAY_ID;" \
        -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
ObjC.import("CoreFoundation");
var screens = $.NSScreen.screens;
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var did = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
    if (did == targetDID) {
        var cfUUID = $.CGDisplayCreateUUIDFromDisplayID(did);
        var cfStr = $.CFUUIDCreateString($.kCFAllocatorDefault, cfUUID);
        var nsStr = ObjC.castRefToObject(cfStr);
        nsStr.js;
        break;
    }
}' 2>/dev/null)

    # Find current space's global index from spaces plist
    SPACE_IDX=$(python3 -c "
import plistlib, subprocess, sys

display_uuid = '$DISPLAY_UUID'
data = plistlib.loads(subprocess.check_output(
    ['defaults', 'export', 'com.apple.spaces', '-']))
monitors = data['SpacesDisplayConfiguration']['Management Data']['Monitors']

# Find monitor: match UUID prefix or fall back to 'Main' for primary display
target_mon = None
for mon in monitors:
    did = mon.get('Display Identifier', '')
    if did != 'Main' and display_uuid.upper().startswith(did.split('-')[0].upper()):
        target_mon = mon
        break
if not target_mon:
    for mon in monitors:
        if mon.get('Display Identifier') == 'Main':
            target_mon = mon
            break

if not target_mon:
    print(0)
    sys.exit(0)

current_uuid = target_mon['Current Space']['uuid']

# Count global space index across all monitors
idx = 1
for mon in monitors:
    for sp in mon['Spaces']:
        if sp['uuid'] == current_uuid:
            print(idx)
            sys.exit(0)
        idx += 1
print(0)
" 2>/dev/null)

    if [ -n "$SPACE_IDX" ] && [ "$SPACE_IDX" -gt 0 ] 2>/dev/null; then
        echo "[bar]   binding to space $SPACE_IDX"
        for item in yb_badge space_label space_path action_code action_term action_folder action_close; do
            sketchybar --set "$item" associated_space=$SPACE_IDX 2>/dev/null
        done
        sketchybar --update 2>/dev/null
    fi
fi

echo "[bar]   done"
