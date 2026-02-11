#!/bin/bash
# FILE: runners/solo.sh
# Opens a single app for a workspace and positions it fullscreen on a target display
#
# Usage:
#   ./runners/solo.sh --display 3 --path ~/git_ckp/mermaid
#   ./runners/solo.sh --display 3 --path ~/project --app "Visual Studio Code" --pad 0,0,0,0

DISPLAY_ID=""
WORK_PATH=""
APP_NAME="Visual Studio Code"
APP_PROC="Code"
PAD_T=0
PAD_B=0
PAD_L=0
PAD_R=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --app)     APP_NAME="$2"; shift 2 ;;
        --proc)    APP_PROC="$2"; shift 2 ;;
        --pad)     IFS=',' read -r PAD_T PAD_B PAD_L PAD_R <<< "$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

WORK_PATH=$(echo "$WORK_PATH" | sed "s|~|$HOME|")

if [ -z "$DISPLAY_ID" ] || [ -z "$WORK_PATH" ]; then
    echo "Usage: solo.sh --display <id> --path <workspace> [--app <name>] [--proc <process>] [--pad T,B,L,R]"
    exit 1
fi

echo "[solo]  display=$DISPLAY_ID path=$WORK_PATH app=$APP_NAME"

# --- 1. OPEN APP ---
echo "[open]  $APP_NAME → $WORK_PATH"
open -na "$APP_NAME" --args "$WORK_PATH"

# --- 2. WAIT FOR WINDOW ---
echo "[wait]  polling for window..."
for i in $(seq 1 20); do
    WIN=$(osascript -e "tell application \"System Events\" to return count of windows of process \"$APP_PROC\"" 2>/dev/null)
    if [ "$WIN" -gt 0 ] 2>/dev/null; then
        echo "[wait]  $APP_PROC=$WIN (ready after ${i}00ms)"
        break
    fi
    sleep 0.5
done

# --- 3. POSITION ON TARGET DISPLAY ---
RESULT=$(osascript -l JavaScript \
    -e "var targetDID = $DISPLAY_ID, padT = $PAD_T, padB = $PAD_B, padL = $PAD_L, padR = $PAD_R;" \
    -e "var appProc = '$APP_PROC';" \
    -e '
ObjC.import("AppKit");
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
    var sx = tf.origin.x;
    var sy = primaryH - tf.origin.y - tf.size.height;
    var sw = tf.size.width;
    var sh = tf.size.height;
    var x0 = sx + padL;
    var y0 = sy + padT;
    var usableW = sw - padL - padR;
    var usableH = sh - padT - padB;
    var se = Application("System Events");
    var p = se.processes.byName(appProc);
    if (p.exists() && p.windows.length > 0) {
        p.windows[0].position = [x0, y0];
        p.windows[0].size = [usableW, usableH];
        appProc + " " + x0 + "," + y0 + " " + usableW + "x" + usableH;
    } else {
        appProc + " (no window)";
    }
}' 2>/dev/null)

echo "[tile]  $RESULT"
echo "[done]  solo ready"
