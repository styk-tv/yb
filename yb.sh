#!/bin/bash
# FILE: yb.sh
# Usage: yb <instance_name | type_name> [display_id]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD=$(pwd)

# --- 0. NO ARGS: SHOW STATUS ---
if [ -z "$1" ]; then
    echo "yb - workspace orchestrator"
    echo ""
    echo "Usage: yb <target> [display_id]"
    echo "       yb -d <space_label>"
    echo ""

    # --- Services ---
    YABAI_STATUS="off"; pgrep -q yabai 2>/dev/null && YABAI_STATUS="on"
    SBAR_STATUS="off"; pgrep -q sketchybar 2>/dev/null && SBAR_STATUS="on"
    SIP_STATUS=$(csrutil status 2>/dev/null | grep -o "enabled\|disabled" || echo "unknown")
    printf "  yabai %-8s  sketchybar %-8s  sip %s\n" "$YABAI_STATUS" "$SBAR_STATUS" "$SIP_STATUS"
    echo ""

    # --- Instances ---
    echo "Instances:"
    for f in "$REPO_ROOT"/instances/*.yaml; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .yaml)
        runner=$(yq -r '.runner // .type // "—"' "$f")
        display=$(yq -r '.display // "—"' "$f")
        bar=$(yq -r '.bar // "—"' "$f")
        path=$(yq -r '.path // "—"' "$f")
        printf "  %-8s %-8s display=%-4s bar=%-10s %s\n" "$name" "$runner" "$display" "$bar" "$path"
    done
    echo ""

    # --- Types ---
    echo "Types:"
    for f in "$REPO_ROOT"/types/*.yaml; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .yaml)
        tmode=$(yq -r '.mode // "tile"' "$f")
        tbar=$(yq -r '.bar // "none"' "$f")
        gap=$(yq -r '.layout.gap // 0' "$f")
        printf "  %-12s mode=%-10s bar=%-10s gap=%s\n" "$name" "$tmode" "$tbar" "$gap"
    done
    echo ""

    # --- Runners ---
    echo "Runners:"
    for f in "$REPO_ROOT"/runners/*.sh; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .sh)
        desc=$(sed -n '3s/^# *//p' "$f")
        printf "  %-12s %s\n" "$name" "$desc"
    done
    echo ""

    # --- Displays ---
    echo "Displays:"
    ACTIVE_DID=$(osascript -l JavaScript -e '
ObjC.import("AppKit");
var se = Application("System Events");
var fp = se.processes.whose({frontmost: true})[0];
var pos = fp.windows[0].position();
var sx = pos[0], sy = pos[1];
var screens = $.NSScreen.screens;
var primaryH = 0;
for (var i = 0; i < screens.count; i++) {
    var f = screens.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
}
var ny = primaryH - sy;
var result = -1;
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var f = s.frame;
    if (sx >= f.origin.x && sx < f.origin.x + f.size.width &&
        ny >= f.origin.y && ny < f.origin.y + f.size.height) {
        result = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
        break;
    }
}
result;' 2>/dev/null)
    system_profiler SPDisplaysDataType -json 2>/dev/null | \
    jq -r '.SPDisplaysDataType[].spdisplays_ndrvs[]? | [._spdisplays_displayID, ._name, ._spdisplays_pixels] | @tsv' | \
    while IFS=$'\t' read -r did dname pixels; do
        marker=""
        [ "$did" = "$ACTIVE_DID" ] && marker=" *"
        printf "  %-4s %-20s %s%s\n" "$did" "$dname" "$pixels" "$marker"
    done
    exit 0
fi

TARGET=$1
MONITOR=${2:-4} # Display ID (default: 4 / LC49G95T)

# --- 0b. DESTROY MODE ---
if [ "$1" == "-d" ]; then
    echo "Destroying Workspace: $2"
    yabai -m space "$2" --destroy
    exit 0
fi

# --- 1. RESOLVE TARGET ---
INSTANCE_FILE="$REPO_ROOT/instances/$TARGET.yaml"
TYPE_FILE="$REPO_ROOT/types/$TARGET.yaml"

# --- NEW PATH: Instance with runner ---
if [ -f "$INSTANCE_FILE" ]; then
    RUNNER=$(yq -r '.runner // ""' "$INSTANCE_FILE")

    if [ -n "$RUNNER" ] && [ "$RUNNER" != "null" ]; then
        # New-style instance — dispatch to runners
        WORK_PATH=$(yq -r '.path // "."' "$INSTANCE_FILE" | sed "s|~|$HOME|")
        DISPLAY=$(yq -r ".display // $MONITOR" "$INSTANCE_FILE")
        [ -n "$2" ] && DISPLAY="$2"  # CLI override
        BAR_STYLE=$(yq -r '.bar // "none"' "$INSTANCE_FILE")
        GAP=$(yq -r '.gap // 0' "$INSTANCE_FILE")
        PADDING=$(yq -r '.padding // "0,0,0,0"' "$INSTANCE_FILE")
        CMD=$(yq -r '.cmd // ""' "$INSTANCE_FILE")
        ZOOM=$(yq -r '.zoom // 0' "$INSTANCE_FILE")
        FOLDER_NAME=$(basename "$WORK_PATH")
        LABEL=$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')

        echo "=== yb: $TARGET → $RUNNER on display $DISPLAY ==="

        # Step 0: Check if workspace already exists — switch to it instead of creating
        # Use VS Code CLI to check for exact workspace folder match
        HAS_WORKSPACE=$(code --status 2>&1 | grep -c "Folder ($FOLDER_NAME):")

        if [ "$HAS_WORKSPACE" -gt 0 ]; then
            echo "[switch] Workspace '$FOLDER_NAME' is open — locating window"

            # Find the window using precise VS Code title matching:
            #   title === folderName  OR  title ends with " — folderName"
            # Then determine which display it's on and focus that display
            SWITCH_RESULT=$(osascript -l JavaScript \
                -e "var folderName = '$FOLDER_NAME';" \
                -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");

var dashSep = " \u2014 "; // VS Code uses em dash
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

        var targetDID = -1;
        var cx = 0, cy = 0;
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
            // Move mouse to display center and click to focus
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
}' 2>/dev/null)

            if [[ "$SWITCH_RESULT" == found:* ]]; then
                FOUND_DISPLAY="${SWITCH_RESULT#found:}"
                echo "[switch] Window on display $FOUND_DISPLAY — activating"
                open -a "Visual Studio Code" "$WORK_PATH"
                sleep 1

                # Re-tile windows with correct padding for bar
                echo ""
                TILE_ARGS="--display $DISPLAY --path $WORK_PATH"
                [ "$GAP" != "0" ] && TILE_ARGS="$TILE_ARGS --gap $GAP"
                [ "$PADDING" != "0,0,0,0" ] && TILE_ARGS="$TILE_ARGS --pad $PADDING"
                "$REPO_ROOT/runners/tile.sh" $TILE_ARGS

                # Update bar label
                echo ""
                "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH"

                echo ""
                echo "=== Switched: $LABEL ==="
                exit 0
            else
                echo "[switch] Workspace open but window not found — creating new"
            fi
        fi

        # Step 1: Create new virtual desktop
        echo ""
        "$REPO_ROOT/runners/space.sh" --create --display "$DISPLAY"

        # Step 2: Launch + position apps
        echo ""
        RUNNER_SCRIPT="$REPO_ROOT/runners/$RUNNER.sh"
        if [ ! -f "$RUNNER_SCRIPT" ]; then
            echo "Runner '$RUNNER' not found at $RUNNER_SCRIPT"
            exit 1
        fi
        RUNNER_ARGS="--display $DISPLAY --path $WORK_PATH"
        [ -n "$CMD" ] && [ "$CMD" != "null" ] && RUNNER_ARGS="$RUNNER_ARGS --cmd $CMD"
        [ "$GAP" != "0" ] && RUNNER_ARGS="$RUNNER_ARGS --gap $GAP"
        [ "$PADDING" != "0,0,0,0" ] && RUNNER_ARGS="$RUNNER_ARGS --pad $PADDING"
        "$RUNNER_SCRIPT" $RUNNER_ARGS

        # Step 3: Configure bar
        echo ""
        "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH"

        # Step 4: Zoom
        if [ "$ZOOM" != "null" ] && [ "$ZOOM" -gt 0 ] 2>/dev/null; then
            echo ""
            echo "[zoom]  +$ZOOM"
            sleep 0.5
            osascript -e "tell application \"System Events\" to tell process \"Code\"" \
                      -e "repeat $ZOOM times" \
                      -e "keystroke \"=\" using {command down}" \
                      -e "end repeat" \
                      -e "end tell"
        fi

        echo ""
        echo "=== Ready: $LABEL ==="
        exit 0
    fi

    # Old-style instance (has type: field) — fall through to legacy path
    TYPE_NAME=$(yq '.type' "$INSTANCE_FILE")
    WORK_PATH=$(yq '.path' "$INSTANCE_FILE" | sed "s|~|$HOME|")
    CMD=$(yq '.cmd' "$INSTANCE_FILE")
    ZOOM=$(yq '.zoom' "$INSTANCE_FILE")
    [ "$WORK_PATH" == "null" ] && WORK_PATH="$CWD"

elif [ -f "$TYPE_FILE" ]; then
    TYPE_NAME=$TARGET
    WORK_PATH="$CWD"
    CMD=""
    ZOOM=0

else
    echo "Unknown target: $TARGET"
    exit 1
fi

# Load Layout Rules from the Type Definition
ACTUAL_TYPE_FILE="$REPO_ROOT/types/$TYPE_NAME.yaml"
if [ ! -f "$ACTUAL_TYPE_FILE" ]; then
    echo "Layout Type '$TYPE_NAME' not found!"
    exit 1
fi

# --- 2. READ LAYOUT + MODE ---
MODE=$(yq -r '.mode // "tile"' "$ACTUAL_TYPE_FILE")
BAR=$(yq -r '.bar // "none"' "$ACTUAL_TYPE_FILE")
GAP=$(yq '.layout.gap' "$ACTUAL_TYPE_FILE")
PAD_T=$(yq '.layout.padding_top' "$ACTUAL_TYPE_FILE")
PAD_B=$(yq '.layout.padding_bottom' "$ACTUAL_TYPE_FILE")
PAD_L=$(yq '.layout.padding_left' "$ACTUAL_TYPE_FILE")
PAD_R=$(yq '.layout.padding_right' "$ACTUAL_TYPE_FILE")

FOLDER_NAME=$(basename "$WORK_PATH")
SPACE_LABEL="$(echo "$TYPE_NAME" | tr '[:lower:]' '[:upper:]')-$FOLDER_NAME"

# --- 3. LAUNCH CONTENT ---
echo "Spawning $SPACE_LABEL [$MODE] on Monitor $MONITOR..."

open -na "Visual Studio Code" --args "$WORK_PATH"

if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    TERM_CMD="cd $WORK_PATH && clear && $CMD"
else
    TERM_CMD="cd $WORK_PATH && clear"
fi

# Launch Terminal.app
osascript -e "tell application \"Terminal\" to do script \"$TERM_CMD\""
osascript -e 'tell application "Terminal" to activate'
TERM_PROC="Terminal"

sleep 2

# --- 4. TILE WINDOWS ---
case "$MODE" in
bsp)
    # --- YABAI BSP ---
    if ! yabai -m query --displays &>/dev/null; then
        echo "Mode 'bsp' requires yabai. Falling back to 'tile'."
        MODE="tile"
    else
        if ! yabai -m query --spaces | jq -e ".[] | select(.label == \"$SPACE_LABEL\")" > /dev/null 2>&1; then
            yabai -m display --focus "$MONITOR"
            yabai -m space --create
            sleep 0.2
            NEW_ID=$(yabai -m query --spaces --display "$MONITOR" | jq '.[-1].index')
            yabai -m space "$NEW_ID" --label "$SPACE_LABEL"
        fi
        yabai -m config --space "$SPACE_LABEL" window_gap "$GAP"
        yabai -m config --space "$SPACE_LABEL" top_padding "$PAD_T"
        yabai -m config --space "$SPACE_LABEL" bottom_padding "$PAD_B"
        yabai -m config --space "$SPACE_LABEL" left_padding "$PAD_L"
        yabai -m config --space "$SPACE_LABEL" right_padding "$PAD_R"
        yabai -m window --app "Code" --space "$SPACE_LABEL"
        yabai -m window --app "$TERM_PROC" --space "$SPACE_LABEL"
        yabai -m window --app "Code" --ratio 0.5
    fi
    ;;
splitview)
    # --- NATIVE SPLIT VIEW (creates a fullscreen Space) ---
    # 1. Move both windows to target display via coordinate positioning
    # 2. Tile Code left — triggers Split View picker
    # 3. Click terminal window to join right tile

    # First move both windows to the target display so split view happens there
    osascript -l JavaScript \
        -e "var targetDID = $MONITOR; var termProc = '$TERM_PROC';" \
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
if (tf) {
    var sx = tf.origin.x;
    var sy = primaryH - tf.origin.y - tf.size.height;
    var sw = tf.size.width;
    var sh = tf.size.height;
    var cx = sx + Math.floor(sw / 4);
    var cy = sy + 50;
    var se = Application("System Events");
    var codeProc = se.processes.byName("Code");
    if (codeProc.exists() && codeProc.windows.length > 0) {
        codeProc.windows[0].position = [cx, cy];
        codeProc.windows[0].size = [Math.floor(sw / 2), Math.floor(sh / 2)];
    }
    var tProc = se.processes.byName(termProc);
    if (tProc.exists() && tProc.windows.length > 0) {
        tProc.windows[0].position = [cx + 50, cy + 50];
        tProc.windows[0].size = [Math.floor(sw / 2), Math.floor(sh / 2)];
    }
}
"done";' 2>/dev/null

    sleep 1

    # Now trigger Split View on the target display
    osascript -e "set termProc to \"$TERM_PROC\"" -e '
        tell application "System Events"
            -- Ensure both windows exist
            repeat 10 times
                if (count of windows of process "Code") > 0 and (count of windows of process termProc) > 0 then
                    exit repeat
                end if
                delay 0.5
            end repeat

            -- Tile VS Code to left (creates fullscreen Space + picker)
            tell process "Code"
                set frontmost to true
                delay 0.5
                click menu item "Tile Window to Left of Screen" of menu "Window" of menu bar 1
            end tell

            -- Wait for picker to appear
            delay 2.0
        end tell
    '

    # Click the Terminal window thumbnail in the split view picker
    # Uses CG mouse click at the center of the right half of target display
    osascript -l JavaScript \
        -e "var targetDID = $MONITOR;" \
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
    // Convert NSScreen coords (bottom-left origin) to CG coords (top-left origin)
    var cgX = tf.origin.x + tf.size.width * 0.75;
    var cgY = (primaryH - tf.origin.y - tf.size.height) + tf.size.height * 0.5;
    var point = $.CGPointMake(cgX, cgY);
    var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, point, $.kCGMouseButtonLeft);
    var up   = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp,   point, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, down);
    delay(0.1);
    $.CGEventPost($.kCGHIDEventTap, up);
}
"done";' 2>/dev/null
    ;;
esac

# Fallback / explicit tile mode (runs after bsp fallback too)
if [ "$MODE" = "tile" ]; then
    # --- COORDINATE TILE (no new Space, sketchybar stays visible) ---
    osascript -l JavaScript \
        -e "var targetDID = $MONITOR, gap = $GAP, padT = $PAD_T, padB = $PAD_B, padL = $PAD_L, padR = $PAD_R; var termProc = '$TERM_PROC';" \
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
var codeProc = se.processes.byName("Code");
if (codeProc.exists()) {
    var w = codeProc.windows[0];
    w.position = [x0, y0];
    w.size = [halfW, usableH];
}
var tProc = se.processes.byName(termProc);
if (tProc.exists()) {
    var w = tProc.windows[0];
    w.position = [x0 + halfW + gap, y0];
    w.size = [usableW - halfW - gap, usableH];
}
"done";' 2>/dev/null
fi

# --- 5. BAR ---
echo ""
"$REPO_ROOT/runners/bar.sh" --display "$MONITOR" --style "$BAR" --label "$SPACE_LABEL" --path "$WORK_PATH"

# --- 6. ZOOM ---
if [ "$ZOOM" != "null" ] && [ "$ZOOM" -gt 0 ] 2>/dev/null; then
    osascript -e "tell application \"System Events\" to tell process \"Code\"" \
              -e "repeat $ZOOM times" \
              -e "keystroke \"=\" using {command down}" \
              -e "end repeat" \
              -e "end tell"
fi

echo "Ready: $SPACE_LABEL"
