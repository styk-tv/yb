#!/bin/bash
# FILE: runners/tile.sh
# Repositions existing VS Code + Terminal windows on a target display
#
# Used by the switch path to re-tile windows with correct padding.
# Does NOT open new windows — only moves/resizes existing ones.
#
# Usage:
#   ./runners/tile.sh --display 3 --path ~/git_ckp/mermaid --gap 0 --pad 52,0,0,0

DISPLAY_ID=""
WORK_PATH=""
GAP=0
PAD_T=0
PAD_B=0
PAD_L=0
PAD_R=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --gap)     GAP="$2"; shift 2 ;;
        --pad)     IFS=',' read -r PAD_T PAD_B PAD_L PAD_R <<< "$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

WORK_PATH=$(echo "$WORK_PATH" | sed "s|~|$HOME|")
FOLDER_NAME=$(basename "$WORK_PATH")

if [ -z "$DISPLAY_ID" ] || [ -z "$WORK_PATH" ]; then
    echo "Usage: tile.sh --display <id> --path <workspace> [--gap N] [--pad T,B,L,R]"
    exit 1
fi

echo "[tile]  display=$DISPLAY_ID folder=$FOLDER_NAME gap=$GAP pad=$PAD_T,$PAD_B,$PAD_L,$PAD_R"

RESULT=$(osascript -l JavaScript \
    -e "var targetDID = $DISPLAY_ID, gap = $GAP, padT = $PAD_T, padB = $PAD_B, padL = $PAD_L, padR = $PAD_R;" \
    -e "var folderName = '$FOLDER_NAME';" \
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

    // --- Code: match by exact workspace folder name ---
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

    // --- Terminal: find window with folder name in title ---
    var termProc = se.processes.byName("Terminal");
    var termWin = null;
    if (termProc.exists()) {
        for (var i = 0; i < termProc.windows.length; i++) {
            var t = termProc.windows[i].title();
            if (t.indexOf(folderName) !== -1) {
                termWin = termProc.windows[i];
                break;
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
        results.push("Terminal (no window for " + folderName + ")");
    }
    results.join("\n");
}' 2>/dev/null)

echo "[tile]  $RESULT"
