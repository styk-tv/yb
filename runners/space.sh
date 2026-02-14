#!/bin/bash
# FILE: runners/space.sh
# Create/list virtual desktops (Spaces) via Mission Control
# Works with SIP enabled — no yabai scripting addition needed
#
# Usage:
#   ./runners/space.sh --list
#   ./runners/space.sh --create --display 3

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ACTION=""
DISPLAY_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    ACTION="list"; shift ;;
        --create)  ACTION="create"; shift ;;
        --display) DISPLAY_ID="$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

if [ -z "$ACTION" ]; then
    echo "Usage:"
    echo "  space.sh --list                     List all spaces per display"
    echo "  space.sh --create --display <id>    Create new space on display"
    exit 1
fi

# --- LIST: Show all spaces per display ---
if [ "$ACTION" = "list" ]; then
    python3 -c "
import subprocess, plistlib, json

# Get display names
sp = json.loads(subprocess.check_output(['system_profiler', 'SPDisplaysDataType', '-json'], stderr=subprocess.DEVNULL))
display_info = {}
for gpu in sp.get('SPDisplaysDataType', []):
    for d in gpu.get('spdisplays_ndrvs', []):
        display_info[d.get('_spdisplays_displayID')] = {
            'name': d.get('_name', '?'),
            'res': d.get('_spdisplays_pixels', '?')
        }

# Get spaces data
raw = subprocess.check_output(['defaults', 'export', 'com.apple.spaces', '-'], stderr=subprocess.DEVNULL)
data = plistlib.loads(raw)
monitors = data.get('SpacesDisplayConfiguration', {}).get('Management Data', {}).get('Monitors', [])

# Map monitors to display IDs (order: Main first, then by UUID)
# We'll show what we know
did_list = sorted(display_info.keys(), key=lambda x: int(x))

for i, m in enumerate(monitors):
    disp_id = m.get('Display Identifier', '?')
    current = m.get('Current Space', {}).get('ManagedSpaceID', '?')
    spaces = m.get('Spaces', [])

    # Try to match to a display ID
    if disp_id == 'Main':
        label = 'Main'
    else:
        label = disp_id[:12] + '...'

    desktops = sum(1 for s in spaces if s.get('type', -1) == 0)
    fullscreens = sum(1 for s in spaces if s.get('type', -1) == 4)

    print(f'Monitor {i+1} ({label}):  {desktops} desktop(s), {fullscreens} fullscreen')
    desk_num = 0
    for s in spaces:
        sid = s.get('ManagedSpaceID', '?')
        stype = s.get('type', -1)
        uuid_short = s.get('uuid', '?')[:8]
        marker = ' *' if sid == current else ''
        if stype == 0:
            desk_num += 1
            print(f'    Desktop {desk_num}  (space {sid}){marker}')
        elif stype == 4:
            # Get tile app names if available
            tiles = s.get('TileLayoutManager', {}).get('TileSpaces', [])
            apps = [t.get('appName', '?') for t in tiles if 'appName' in t]
            app_str = ' + '.join(apps) if apps else 'fullscreen'
            print(f'    [{app_str}]  (space {sid}){marker}')
    print()
"
    exit 0
fi

# --- CREATE: New space on target display ---
if [ -z "$DISPLAY_ID" ]; then
    echo "Usage: space.sh --create --display <id>"
    exit 1
fi

# Helper: focus target display (move mouse to center, click)
focus_display() {
    osascript -l JavaScript \
        -e "var targetDID = $DISPLAY_ID;" \
        -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
var screens = $.NSScreen.screens;
var primaryH = 0;
for (var i = 0; i < screens.count; i++) {
    var f = screens.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
}
var tf = null;
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var did = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
    if (did == targetDID) { tf = s.frame; break; }
}
if (tf) {
    var cx = tf.origin.x + tf.size.width / 2;
    var cy = primaryH - tf.origin.y - tf.size.height + tf.size.height / 2;
    var point = $.CGPointMake(cx, cy);
    var moveEvt = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, point, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, moveEvt);
    delay(0.1);
    var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, point, $.kCGMouseButtonLeft);
    var up   = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp, point, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, down);
    delay(0.05);
    $.CGEventPost($.kCGHIDEventTap, up);
    "focused";
}' 2>/dev/null
}

# Step 0: Check for empty desktop on target display to reuse
# Get display UUID, match to plist monitor, find empty desktops
DISP_UUID=$(osascript -l JavaScript \
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

EMPTY_DELTA=$(python3 -c "
import subprocess, plistlib, json
from collections import Counter

target_uuid = '$DISP_UUID'

raw = subprocess.check_output(['defaults', 'export', 'com.apple.spaces', '-'], stderr=subprocess.DEVNULL)
data = plistlib.loads(raw)
mgmt = data['SpacesDisplayConfiguration']['Management Data']
monitors = mgmt['Monitors']
space_props = {sp['name']: sp.get('windows', []) for sp in data['SpacesDisplayConfiguration'].get('Space Properties', [])}

# Get live window IDs from yabai (plist can have stale IDs from closed windows)
live_wids = None
try:
    yabai_wins = json.loads(subprocess.check_output(['yabai', '-m', 'query', '--windows'], stderr=subprocess.DEVNULL))
    live_wids = {w['id'] for w in yabai_wins}
except:
    pass  # yabai unavailable — trust plist as-is

# Find monitor: match by UUID or 'Main' (primary display)
target_mon = None
for m in monitors:
    ident = m.get('Display Identifier', '')
    if ident == target_uuid:
        target_mon = m
        break
    if ident == 'Main':
        # Main is the primary display — check if target_uuid has no other match
        main_mon = m

if not target_mon:
    # If UUID didn't match any monitor, it's the primary display (plist uses 'Main')
    target_mon = main_mon if 'main_mon' in dir() else None

if not target_mon:
    print('none')
    exit(0)

desktops = [s for s in target_mon.get('Spaces', []) if s.get('type', -1) == 0]
current_sid = target_mon.get('Current Space', {}).get('ManagedSpaceID', -1)

# Count window appearances across desktops on this monitor
# Filter to live windows only (removes stale IDs from closed windows)
all_wids = []
desk_wids = {}
for d in desktops:
    wids = set(space_props.get(d['uuid'], []))
    if live_wids is not None:
        wids = wids & live_wids
    desk_wids[d['uuid']] = wids
    all_wids.extend(wids)
wid_counts = Counter(all_wids)
shared = {w for w, c in wid_counts.items() if c > 1}

# Find first empty desktop (no unique/app windows)
current_idx = -1
for i, d in enumerate(desktops):
    if d['ManagedSpaceID'] == current_sid:
        current_idx = i

for i, d in enumerate(desktops):
    unique = desk_wids.get(d['uuid'], set()) - shared
    if len(unique) == 0:
        delta = i - current_idx
        print(f'{delta}')
        exit(0)

print('none')
" 2>/dev/null)

if [ "$EMPTY_DELTA" != "none" ] && [ -n "$EMPTY_DELTA" ]; then
    echo "[space] Found empty desktop on display $DISPLAY_ID (delta=$EMPTY_DELTA) — reusing"

    # Focus the display
    focus_display
    sleep 0.3

    # Navigate to empty desktop
    if [ "$EMPTY_DELTA" -gt 0 ] 2>/dev/null; then
        echo "[space] Pressing ctrl+right $EMPTY_DELTA times..."
        for i in $(seq 1 $EMPTY_DELTA); do
            osascript -e 'tell application "System Events" to key code 124 using control down'
            sleep 0.4
        done
    elif [ "$EMPTY_DELTA" -lt 0 ] 2>/dev/null; then
        ABS_DELTA=$(( -EMPTY_DELTA ))
        echo "[space] Pressing ctrl+left $ABS_DELTA times..."
        for i in $(seq 1 $ABS_DELTA); do
            osascript -e 'tell application "System Events" to key code 123 using control down'
            sleep 0.4
        done
    fi
    # delta=0 means current desktop is already empty

    echo "[space] OK — reusing empty desktop"
    exit 0
fi

# No empty desktop — create a new one via Mission Control
echo "[space] No empty desktop on display $DISPLAY_ID — creating new"

# Snapshot space count before
BEFORE=$(python3 -c "
import subprocess, plistlib
raw = subprocess.check_output(['defaults', 'export', 'com.apple.spaces', '-'], stderr=subprocess.DEVNULL)
data = plistlib.loads(raw)
monitors = data.get('SpacesDisplayConfiguration', {}).get('Management Data', {}).get('Monitors', [])
total = sum(len(m.get('Spaces', [])) for m in monitors)
print(total)
" 2>/dev/null)

# Step 1: Open Mission Control
echo "[space] Opening Mission Control..."
osascript -e 'tell application "System Events" to key code 126 using control down'
sleep 1.5

# Step 2: Hover to reveal "+" then click
echo "[space] Hovering to reveal '+' then clicking..."
osascript -l JavaScript \
    -e "var targetDID = $DISPLAY_ID;" \
    -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
var screens = $.NSScreen.screens;
var primaryH = 0;
for (var i = 0; i < screens.count; i++) {
    var f = screens.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
}
var tf = null;
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var did = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
    if (did == targetDID) { tf = s.frame; break; }
}
if (!tf) { "error: display " + targetDID + " not found"; }
else {
    var dispLeft = tf.origin.x;
    var dispTop  = primaryH - tf.origin.y - tf.size.height;
    var dispW    = tf.size.width;

    var hoverX = dispLeft + dispW - 60;
    var hoverY = dispTop + 10;
    var clickX = dispLeft + dispW - 30;
    var clickY = dispTop + 10;

    var movePoint = $.CGPointMake(hoverX, hoverY);
    var moveEvt = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, movePoint, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, moveEvt);
    delay(0.8);

    var plusPoint = $.CGPointMake(clickX, clickY);
    var moveEvt2 = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, plusPoint, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, moveEvt2);
    delay(0.5);

    var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, plusPoint, $.kCGMouseButtonLeft);
    var up   = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp,   plusPoint, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, down);
    delay(0.1);
    $.CGEventPost($.kCGHIDEventTap, up);

    "hover=" + Math.floor(hoverX) + "," + Math.floor(hoverY) + " click=" + Math.floor(clickX) + "," + Math.floor(clickY);
}' 2>/dev/null

sleep 1

# Step 3: Close Mission Control
echo "[space] Closing Mission Control..."
osascript -e 'tell application "System Events" to key code 53'
sleep 0.5

# Step 4: Focus display and navigate to new (rightmost) space
echo "[space] Switching to new space on display $DISPLAY_ID..."
focus_display
sleep 0.3

echo "[space] Navigating to rightmost space (ctrl+right)..."
osascript -e 'tell application "System Events"
    repeat 5 times
        key code 124 using control down
        delay 0.3
    end repeat
end tell'
sleep 0.3

# Step 5: Verify
AFTER=$(python3 -c "
import subprocess, plistlib
raw = subprocess.check_output(['defaults', 'export', 'com.apple.spaces', '-'], stderr=subprocess.DEVNULL)
data = plistlib.loads(raw)
monitors = data.get('SpacesDisplayConfiguration', {}).get('Management Data', {}).get('Monitors', [])
total = sum(len(m.get('Spaces', [])) for m in monitors)
print(total)
" 2>/dev/null)

if [ "$AFTER" -gt "$BEFORE" ] 2>/dev/null; then
    echo "[space] OK — space created (before=$BEFORE after=$AFTER)"
else
    echo "[space] WARN — space count unchanged (before=$BEFORE after=$AFTER), click may have missed"
fi
