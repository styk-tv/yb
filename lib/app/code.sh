#!/bin/bash
# FILE: lib/app/code.sh
# Application handler: Visual Studio Code
#
# Provides: app_code_open, app_code_find, app_code_close,
#           app_code_is_open, app_code_focus, app_code_locate,
#           app_code_tile_left, app_code_post_setup,
#           app_code_snapshot, app_code_find_new
#
# Requires: lib/common.sh sourced first (yb_log, yb_yabai_ok, yb_position, etc.)

# Open VS Code with a workspace path.
# $1=work_path
app_code_open() {
    local work_path="$1"
    yb_log "opening VS Code → $work_path"
    open -na "Visual Studio Code" --args "$work_path"
}

# Find VS Code window by workspace path. Prints yabai window ID or empty.
# $1=work_path $2=space_index (optional, filter by space)
app_code_find() {
    local work_path="$1" hint_space="${2:-}"
    local folder
    folder=$(basename "$work_path")

    if yb_yabai_ok; then
        if [ -n "$hint_space" ]; then
            yabai -m query --windows | jq -r --arg fn "$folder" --argjson sp "$hint_space" \
                '.[] | select(.app == "Code") | select(.space == $sp) | select(.title == $fn or (.title | endswith(" \u2014 " + $fn))) | .id' | head -1
        else
            yabai -m query --windows | jq -r --arg fn "$folder" \
                '.[] | select(.app == "Code") | select(.title == $fn or (.title | endswith(" \u2014 " + $fn))) | .id' | head -1
        fi
    else
        local found
        found=$(osascript -l JavaScript -e "var fn = '$folder';" -e '
var dashSep = " \u2014 ";
var se = Application("System Events");
var p = se.processes.byName("Code");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        var t = p.windows[i].title();
        if (t === fn || t.endsWith(dashSep + fn)) { "found"; break; }
    }
}' 2>/dev/null)
        [ "$found" = "found" ] && echo "jxa:Code:$folder"
    fi
}

# Close VS Code window for a workspace.
# $1=work_path
app_code_close() {
    local work_path="$1"
    local folder
    folder=$(basename "$work_path")
    osascript -l JavaScript -e "var fn = '$folder';" -e '
var dashSep = " \u2014 ";
var se = Application("System Events");
var p = se.processes.byName("Code");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        var t = p.windows[i].title();
        if (t === fn || t.endsWith(dashSep + fn)) {
            p.frontmost = true;
            p.windows[i].actions.byName("AXRaise").perform();
            delay(0.3);
            se.keystroke("w", {using: "command down"});
            break;
        }
    }
}' 2>/dev/null
}

# Check if VS Code has this workspace open. Returns 0 if open, 1 if not.
# Uses yabai window query (live) instead of code --status (stale after close).
# $1=work_path
app_code_is_open() {
    local work_path="$1"
    local wid
    wid=$(app_code_find "$work_path")
    [ -n "$wid" ]
}

# Focus/activate an existing VS Code window.
# $1=work_path
app_code_focus() {
    local work_path="$1"
    open -a "Visual Studio Code" "$work_path"
}

# Locate VS Code window — find it and return which display it's on.
# Prints "found:<display_id>" or "none". Also clicks to activate the display.
# $1=work_path
app_code_locate() {
    local work_path="$1"
    local folder
    folder=$(basename "$work_path")
    osascript -l JavaScript \
        -e "var folderName = '$folder';" \
        -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
var dashSep = " \u2014 ";
var se = Application("System Events");
var codeProc = se.processes.byName("Code");
if (!codeProc.exists()) { "none"; }
else {
    var targetWin = null;
    for (var i = 0; i < codeProc.windows.length; i++) {
        var t = codeProc.windows[i].title();
        if (t === folderName || t.endsWith(dashSep + folderName)) {
            targetWin = codeProc.windows[i];
            break;
        }
    }
    if (!targetWin) { "none"; }
    else {
        var pos = targetWin.position();
        var wx = pos[0], wy = pos[1];
        var screens = $.NSScreen.screens;
        var primaryH = 0;
        for (var i = 0; i < screens.count; i++) {
            var f = screens.objectAtIndex(i).frame;
            if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
        }
        var targetDID = -1, cx = 0, cy = 0;
        for (var i = 0; i < screens.count; i++) {
            var s = screens.objectAtIndex(i);
            var f = s.frame;
            var seY = primaryH - f.origin.y - f.size.height;
            if (wx >= f.origin.x && wx < f.origin.x + f.size.width &&
                wy >= seY && wy < seY + f.size.height) {
                targetDID = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
                cx = f.origin.x + f.size.width / 2;
                cy = primaryH - f.origin.y - f.size.height + f.size.height / 2;
                break;
            }
        }
        if (targetDID === -1) { "none"; }
        else {
            var point = $.CGPointMake(cx, cy);
            var moveEvt = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, point, $.kCGMouseButtonLeft);
            $.CGEventPost($.kCGHIDEventTap, moveEvt);
            delay(0.1);
            var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, point, $.kCGMouseButtonLeft);
            var up = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp, point, $.kCGMouseButtonLeft);
            $.CGEventPost($.kCGHIDEventTap, down);
            delay(0.05);
            $.CGEventPost($.kCGHIDEventTap, up);
            "found:" + targetDID;
        }
    }
}' 2>/dev/null
}

# Trigger macOS Split View — tile this app's window to the left.
app_code_tile_left() {
    osascript -e '
        tell application "System Events"
            tell process "Code"
                set frontmost to true
                delay 0.5
                click menu item "Tile Window to Left of Screen" of menu "Window" of menu bar 1
            end tell
            delay 2.0
        end tell
    '
}

# Post-setup: apply zoom level.
# $1=zoom_level (0 = no zoom)
app_code_post_setup() {
    local zoom="${1:-0}"
    if [ "$zoom" != "null" ] && [ "$zoom" -gt 0 ] 2>/dev/null; then
        yb_log "zoom +$zoom"
        sleep 0.5
        osascript -e "tell application \"System Events\" to tell process \"Code\"" \
                  -e "repeat $zoom times" \
                  -e "keystroke \"=\" using {command down}" \
                  -e "end repeat" \
                  -e "end tell"
    fi
}

# Snapshot existing VS Code windows for delta tracking.
app_code_snapshot() {
    yb_snapshot_wids "Code"
}

# Find new VS Code window since snapshot.
# $1=snapshot
app_code_find_new() {
    yb_find_new_wid "Code" "$1"
}
