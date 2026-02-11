#!/bin/bash
# FILE: runners/split.sh
# Opens VS Code + Terminal for a workspace and tiles them side-by-side on a target display
#
# Usage:
#   ./runners/split.sh --display 4 --path ~/git_ckp/mermaid
#   ./runners/split.sh --display 4 --path ~/project --cmd "npm run dev" --gap 12 --pad 12,12,12,12

DISPLAY_ID=""
WORK_PATH=""
CMD=""
GAP=0
PAD_T=0
PAD_B=0
PAD_L=0
PAD_R=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --cmd)     CMD="$2"; shift 2 ;;
        --gap)     GAP="$2"; shift 2 ;;
        --pad)     IFS=',' read -r PAD_T PAD_B PAD_L PAD_R <<< "$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

WORK_PATH=$(echo "$WORK_PATH" | sed "s|~|$HOME|")
FOLDER_NAME=$(basename "$WORK_PATH")

if [ -z "$DISPLAY_ID" ] || [ -z "$WORK_PATH" ]; then
    echo "Usage: split.sh --display <id> --path <workspace> [--cmd <command>] [--gap N] [--pad T,B,L,R]"
    exit 1
fi

echo "[split] display=$DISPLAY_ID path=$WORK_PATH folder=$FOLDER_NAME"

# --- 1. SNAPSHOT window titles before opening ---
EXISTING_TERM_IDS=$(osascript -l JavaScript -e '
var se = Application("System Events");
var p = se.processes.byName("Terminal");
if (p.exists()) {
    var ids = [];
    for (var i = 0; i < p.windows.length; i++) { ids.push(p.windows[i].title()); }
    ids.join("|||");
} else { ""; }' 2>/dev/null)
echo "[snap]  existing terminals: ${EXISTING_TERM_IDS:-(none)}"

# --- 2. OPEN APPS ---
echo "[open]  Visual Studio Code → $WORK_PATH"
open -na "Visual Studio Code" --args "$WORK_PATH"

if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    TERM_CMD="cd $WORK_PATH && clear && $CMD"
else
    TERM_CMD="cd $WORK_PATH && clear"
fi
echo "[open]  Terminal → $TERM_CMD"
osascript -e "tell application \"Terminal\" to do script \"$TERM_CMD\""

# --- 3. WAIT for new windows ---
echo "[wait]  looking for new windows (folder=$FOLDER_NAME)..."
sleep 3

# Poll for Code window with folder name in title (VS Code may take a few seconds to load)
FOUND_CODE="no"
for i in $(seq 1 15); do
    FOUND_CODE=$(osascript -l JavaScript -e "var fn = '$FOLDER_NAME';" -e '
var dashSep = " \u2014 "; // VS Code em dash separator
var se = Application("System Events");
var p = se.processes.byName("Code");
if (!p.exists()) { "no"; }
else {
    var found = "no";
    for (var i = 0; i < p.windows.length; i++) {
        var t = p.windows[i].title();
        if (t === fn || t.endsWith(dashSep + fn)) { found = "yes"; break; }
    }
    found;
}' 2>/dev/null)
    if [ "$FOUND_CODE" = "yes" ]; then
        echo "[wait]  Code window '$FOLDER_NAME' found (after ${i}s)"
        break
    fi
    sleep 1
done
[ "$FOUND_CODE" != "yes" ] && echo "[warn]  Code window '$FOLDER_NAME' not found in title after 15s"

# --- 4. POSITION on target display ---
# Match BOTH windows by title containing folder name
RESULT=$(osascript -l JavaScript \
    -e "var targetDID = $DISPLAY_ID, gap = $GAP, padT = $PAD_T, padB = $PAD_B, padL = $PAD_L, padR = $PAD_R;" \
    -e "var folderName = '$FOLDER_NAME';" \
    -e "var existingTerms = '$EXISTING_TERM_IDS';" \
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
    var halfW = Math.floor((usableW - gap) / 2);
    var se = Application("System Events");
    var results = [];

    // --- Code: match by exact workspace folder name in title ---
    var dashSep = " \u2014 "; // VS Code em dash separator
    var codeProc = se.processes.byName("Code");
    var codeWin = null;
    if (codeProc.exists()) {
        for (var i = 0; i < codeProc.windows.length; i++) {
            var t = codeProc.windows[i].title();
            if (t === folderName || t.endsWith(dashSep + folderName)) {
                codeWin = codeProc.windows[i];
                break;
            }
        }
    }
    if (codeWin) {
        codeWin.position = [x0, y0];
        codeWin.size = [halfW, usableH];
        results.push("Code [" + codeWin.title() + "] " + x0 + "," + y0 + " " + halfW + "x" + usableH);
    } else {
        results.push("Code (no match for " + folderName + ")");
    }

    // --- Terminal: find the NEW window (not in the snapshot) ---
    var oldTitles = existingTerms.split("|||");
    var termProc = se.processes.byName("Terminal");
    var termWin = null;
    if (termProc.exists()) {
        for (var i = 0; i < termProc.windows.length; i++) {
            var t = termProc.windows[i].title();
            // New window: either has folder name in title, or was not in the snapshot
            if (t.indexOf(folderName) !== -1) {
                termWin = termProc.windows[i];
                break;
            }
        }
        // Fallback: find any window title not in the old snapshot
        if (!termWin) {
            for (var i = 0; i < termProc.windows.length; i++) {
                var t = termProc.windows[i].title();
                if (oldTitles.indexOf(t) === -1) {
                    termWin = termProc.windows[i];
                    break;
                }
            }
        }
    }
    if (termWin) {
        var x2 = x0 + halfW + gap;
        var w2 = usableW - halfW - gap;
        termWin.position = [x2, y0];
        termWin.size = [w2, usableH];
        results.push("Terminal [" + termWin.title() + "] " + x2 + "," + y0 + " " + w2 + "x" + usableH);
    } else {
        results.push("Terminal (no new window found)");
    }
    results.join("\n");
}' 2>/dev/null)

echo "[tile]  $RESULT"
echo "[done]  split ready"
