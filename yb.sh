#!/bin/bash
# FILE: yb.sh
# Usage: yb <instance_name | layout_name> [display_id]
#
# Generic workspace orchestrator. Application-specific logic lives in
# lib/app/*.sh handlers — this file contains zero app-specific code.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD=$(pwd)
source "$REPO_ROOT/lib/common.sh"

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
        layout=$(yq -r '.layout // .type // ""' "$f")
        terminal=$(yq -r '.terminal // ""' "$f")
        mode=$(yq -r '.mode // ""' "$f")
        display=$(yq -r '.display // "—"' "$f")
        bar=$(yq -r '.bar // ""' "$f")
        path=$(yq -r '.path // "—"' "$f")
        # Resolve from layout if instance references one
        if [ -n "$layout" ] && [ "$layout" != "null" ]; then
            lf="$REPO_ROOT/layouts/$layout.yaml"
            [ -f "$lf" ] && {
                [ -z "$terminal" ] || [ "$terminal" = "null" ] && terminal=$(yq -r '.terminal // "iterm"' "$lf")
                [ -z "$mode" ] || [ "$mode" = "null" ] && mode=$(yq -r '.mode // "tile"' "$lf")
                [ -z "$bar" ] || [ "$bar" = "null" ] && bar=$(yq -r '.bar // "none"' "$lf")
            }
            label="$terminal/$mode ($layout)"
        else
            label="$terminal/$mode"
        fi
        [ -z "$bar" ] || [ "$bar" = "null" ] && bar="—"
        printf "  %-8s %-24s display=%-4s bar=%-10s %s\n" "$name" "$label" "$display" "$bar" "$path"
    done
    echo ""

    # --- Layouts ---
    echo "Layouts:"
    for f in "$REPO_ROOT"/layouts/*.yaml; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .yaml)
        lterminal=$(yq -r '.terminal // "iterm"' "$f")
        lmode=$(yq -r '.mode // "tile"' "$f")
        lbar=$(yq -r '.bar // "none"' "$f")
        lcmd=$(yq -r '.cmd // "—"' "$f")
        printf "  %-12s terminal=%-10s mode=%-10s bar=%-10s cmd=%s\n" "$name" "$lterminal" "$lmode" "$lbar" "$lcmd"
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
DEFAULT_DISPLAY=4

# --- 0a. ENSURE SERVICES ARE RUNNING ---
ensure_services() {
    local changed=0
    if ! pgrep -q yabai 2>/dev/null; then
        echo "[services] yabai not running — starting..."
        yabai --start-service 2>/dev/null
        changed=1
    fi
    if ! pgrep -q sketchybar 2>/dev/null; then
        echo "[services] sketchybar not running — starting..."
        brew services start sketchybar 2>/dev/null
        changed=1
    fi
    if [ "$changed" -eq 1 ]; then
        sleep 2
        if ! pgrep -q yabai 2>/dev/null; then
            echo "[services] WARN: yabai failed to start — check Accessibility permissions"
        fi
        if ! pgrep -q sketchybar 2>/dev/null; then
            echo "[services] WARN: sketchybar failed to start"
        fi
    fi
}
ensure_services

# --- 0b. DESTROY MODE ---
if [ "$1" == "-d" ]; then
    echo "Destroying Workspace: $2"
    yabai -m space "$2" --destroy
    exit 0
fi

# --- 0c. INIT MODE ---
if [ "$1" == "init" ]; then
    INIT_LAYOUT="$2"
    INIT_DISPLAY="${3:-$DEFAULT_DISPLAY}"

    if [ -z "$INIT_LAYOUT" ]; then
        echo "Usage: yb init <layout> [display_id]"
        echo ""
        echo "Creates an instance for the current directory."
        echo ""
        echo "Layouts:"
        for f in "$REPO_ROOT"/layouts/*.yaml; do
            [ -f "$f" ] || continue
            name=$(basename "$f" .yaml)
            lterminal=$(yq -r '.terminal // "iterm"' "$f")
            lmode=$(yq -r '.mode // "tile"' "$f")
            lcmd=$(yq -r '.cmd // "—"' "$f")
            printf "  %-12s terminal=%-10s mode=%-10s cmd=%s\n" "$name" "$lterminal" "$lmode" "$lcmd"
        done
        exit 1
    fi

    INIT_LAYOUT_FILE="$REPO_ROOT/layouts/$INIT_LAYOUT.yaml"
    if [ ! -f "$INIT_LAYOUT_FILE" ]; then
        echo "Layout '$INIT_LAYOUT' not found"
        exit 1
    fi

    FOLDER_NAME=$(basename "$CWD")
    INSTANCE_PATH="$REPO_ROOT/instances/$FOLDER_NAME.yaml"
    DISPLAY_PATH=$(echo "$CWD" | sed "s|$HOME|~|")

    if [ -f "$INSTANCE_PATH" ]; then
        echo "Instance '$FOLDER_NAME' already exists at $INSTANCE_PATH"
        exit 1
    fi

    cat > "$INSTANCE_PATH" << EOF
# $FOLDER_NAME
layout: $INIT_LAYOUT
path: $DISPLAY_PATH
display: $INIT_DISPLAY
EOF

    echo "Created instance: $INSTANCE_PATH"
    echo ""
    cat "$INSTANCE_PATH"
    echo ""
    echo "Launch with: yb $FOLDER_NAME"
    exit 0
fi

# --- 1. RESOLVE TARGET ---
INSTANCE_FILE="$REPO_ROOT/instances/$TARGET.yaml"
LAYOUT_FILE="$REPO_ROOT/layouts/$TARGET.yaml"

if [ -f "$INSTANCE_FILE" ]; then
    # --- Read instance fields ---
    WORK_PATH=$(yq -r '.path // "."' "$INSTANCE_FILE" | sed "s|~|$HOME|")
    DISPLAY=$(yq -r ".display // $DEFAULT_DISPLAY" "$INSTANCE_FILE")
    [ -n "$2" ] && DISPLAY="$2"  # CLI override

    # Resolve layout reference (layout: or legacy type:)
    LAYOUT_REF=$(yq -r '.layout // .type // ""' "$INSTANCE_FILE")

    # Read instance-level overrides
    TERMINAL=$(yq -r '.terminal // ""' "$INSTANCE_FILE")
    MODE=$(yq -r '.mode // ""' "$INSTANCE_FILE")
    CMD=$(yq -r '.cmd // ""' "$INSTANCE_FILE")
    BAR_STYLE=$(yq -r '.bar // ""' "$INSTANCE_FILE")
    ZOOM=$(yq -r '.zoom // ""' "$INSTANCE_FILE")
    GAP=$(yq -r '.gap // ""' "$INSTANCE_FILE")
    PADDING=$(yq -r '.padding // ""' "$INSTANCE_FILE")

    # Backward compat: runner: field → terminal + mode
    LEGACY_RUNNER=$(yq -r '.runner // ""' "$INSTANCE_FILE")
    if [ -n "$LEGACY_RUNNER" ] && [ "$LEGACY_RUNNER" != "null" ]; then
        case "$LEGACY_RUNNER" in
            split)       [ -z "$TERMINAL" ] || [ "$TERMINAL" = "null" ] && TERMINAL="iterm"
                         [ -z "$MODE" ] || [ "$MODE" = "null" ] && MODE="tile" ;;
            iterm.v003)  [ -z "$TERMINAL" ] || [ "$TERMINAL" = "null" ] && TERMINAL="iterm"
                         [ -z "$MODE" ] || [ "$MODE" = "null" ] && MODE="tile" ;;
            solo)        [ -z "$TERMINAL" ] || [ "$TERMINAL" = "null" ] && TERMINAL="none"
                         [ -z "$MODE" ] || [ "$MODE" = "null" ] && MODE="solo" ;;
        esac
    fi

    # Resolve from layout YAML if referenced
    if [ -n "$LAYOUT_REF" ] && [ "$LAYOUT_REF" != "null" ]; then
        LAYOUT_YAML="$REPO_ROOT/layouts/$LAYOUT_REF.yaml"
        if [ ! -f "$LAYOUT_YAML" ]; then
            echo "Layout '$LAYOUT_REF' not found at $LAYOUT_YAML"
            exit 1
        fi
        [ -z "$TERMINAL" ] || [ "$TERMINAL" = "null" ] && TERMINAL=$(yq -r '.terminal // "iterm"' "$LAYOUT_YAML")
        [ -z "$MODE" ] || [ "$MODE" = "null" ] && MODE=$(yq -r '.mode // "tile"' "$LAYOUT_YAML")
        [ -z "$CMD" ] || [ "$CMD" = "null" ] && CMD=$(yq -r '.cmd // ""' "$LAYOUT_YAML")
        [ -z "$BAR_STYLE" ] || [ "$BAR_STYLE" = "null" ] && BAR_STYLE=$(yq -r '.bar // "none"' "$LAYOUT_YAML")
        [ -z "$ZOOM" ] || [ "$ZOOM" = "null" ] && ZOOM=$(yq -r '.zoom // 0' "$LAYOUT_YAML")

        # Layout padding (from layout YAML's layout: block)
        if [ -z "$GAP" ] || [ "$GAP" = "null" ]; then
            GAP=$(yq -r '.layout.gap // 0' "$LAYOUT_YAML")
        fi
        if [ -z "$PADDING" ] || [ "$PADDING" = "null" ]; then
            L_PAD_T=$(yq -r '.layout.padding_top // 0' "$LAYOUT_YAML")
            L_PAD_B=$(yq -r '.layout.padding_bottom // 0' "$LAYOUT_YAML")
            L_PAD_L=$(yq -r '.layout.padding_left // 0' "$LAYOUT_YAML")
            L_PAD_R=$(yq -r '.layout.padding_right // 0' "$LAYOUT_YAML")
            # Add bar height to top padding
            if [ "$BAR_STYLE" = "standard" ]; then
                L_PAD_T=$((L_PAD_T + 52))
            elif [ "$BAR_STYLE" = "minimal" ]; then
                L_PAD_T=$((L_PAD_T + 34))
            fi
            PADDING="$L_PAD_T,$L_PAD_B,$L_PAD_L,$L_PAD_R"
        fi
    fi

    # Defaults
    [ -z "$TERMINAL" ] || [ "$TERMINAL" = "null" ] && TERMINAL="iterm"
    [ -z "$MODE" ] || [ "$MODE" = "null" ] && MODE="tile"
    [ -z "$BAR_STYLE" ] || [ "$BAR_STYLE" = "null" ] && BAR_STYLE="none"
    [ -z "$ZOOM" ] || [ "$ZOOM" = "null" ] && ZOOM=0
    [ -z "$GAP" ] || [ "$GAP" = "null" ] && GAP=0
    [ -z "$PADDING" ] || [ "$PADDING" = "null" ] && PADDING="0,0,0,0"
    [ -z "$CMD" ] || [ "$CMD" = "null" ] && CMD=""

elif [ -f "$LAYOUT_FILE" ]; then
    # Direct layout reference (e.g., yb standard)
    WORK_PATH="$CWD"
    DISPLAY="${2:-$DEFAULT_DISPLAY}"
    TERMINAL=$(yq -r '.terminal // "iterm"' "$LAYOUT_FILE")
    MODE=$(yq -r '.mode // "tile"' "$LAYOUT_FILE")
    CMD=$(yq -r '.cmd // ""' "$LAYOUT_FILE")
    BAR_STYLE=$(yq -r '.bar // "none"' "$LAYOUT_FILE")
    ZOOM=$(yq -r '.zoom // 0' "$LAYOUT_FILE")
    GAP=$(yq -r '.layout.gap // 0' "$LAYOUT_FILE")
    L_PAD_T=$(yq -r '.layout.padding_top // 0' "$LAYOUT_FILE")
    L_PAD_B=$(yq -r '.layout.padding_bottom // 0' "$LAYOUT_FILE")
    L_PAD_L=$(yq -r '.layout.padding_left // 0' "$LAYOUT_FILE")
    L_PAD_R=$(yq -r '.layout.padding_right // 0' "$LAYOUT_FILE")
    if [ "$BAR_STYLE" = "standard" ]; then
        L_PAD_T=$((L_PAD_T + 52))
    elif [ "$BAR_STYLE" = "minimal" ]; then
        L_PAD_T=$((L_PAD_T + 34))
    fi
    PADDING="$L_PAD_T,$L_PAD_B,$L_PAD_L,$L_PAD_R"
else
    echo "Unknown target: $TARGET"
    exit 1
fi

FOLDER_NAME=$(basename "$WORK_PATH")
LABEL=$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')

# --- LOAD APPLICATION HANDLERS ---
# Primary app defaults to "code"; layouts can override with editor: field
PRIMARY_APP="code"
_RESOLVE_YAML="${LAYOUT_YAML:-$LAYOUT_FILE}"
if [ -n "$_RESOLVE_YAML" ] && [ -f "$_RESOLVE_YAML" ]; then
    _editor=$(yq -r '.editor // "code"' "$_RESOLVE_YAML")
    [ -n "$_editor" ] && [ "$_editor" != "null" ] && PRIMARY_APP="$_editor"
fi
SECONDARY_APP="$TERMINAL"

PRIMARY_HANDLER="$REPO_ROOT/lib/app/${PRIMARY_APP}.sh"
if [ ! -f "$PRIMARY_HANDLER" ]; then
    echo "Unknown primary app handler: $PRIMARY_APP (missing $PRIMARY_HANDLER)"
    exit 1
fi
source "$PRIMARY_HANDLER"

if [ "$SECONDARY_APP" != "none" ]; then
    SECONDARY_HANDLER="$REPO_ROOT/lib/app/${SECONDARY_APP}.sh"
    if [ ! -f "$SECONDARY_HANDLER" ]; then
        echo "Unknown secondary app handler: $SECONDARY_APP (missing $SECONDARY_HANDLER)"
        exit 1
    fi
    source "$SECONDARY_HANDLER"
fi

echo "=== yb: $TARGET → $PRIMARY_APP+$SECONDARY_APP/$MODE on display $DISPLAY ==="

# --- 2. CHECK FOR EXISTING WORKSPACE ---
_HAS_WORKSPACE=0
if type "app_${PRIMARY_APP}_is_open" &>/dev/null; then
    "app_${PRIMARY_APP}_is_open" "$WORK_PATH" && _HAS_WORKSPACE=1
fi

if [ "$_HAS_WORKSPACE" -eq 1 ]; then
    echo "[switch] Workspace '$FOLDER_NAME' is open — locating window"

    SWITCH_RESULT="none"
    if type "app_${PRIMARY_APP}_locate" &>/dev/null; then
        SWITCH_RESULT=$("app_${PRIMARY_APP}_locate" "$WORK_PATH")
    fi

    if [[ "$SWITCH_RESULT" == found:* ]]; then
        FOUND_DISPLAY="${SWITCH_RESULT#found:}"

        if [ "$FOUND_DISPLAY" != "$DISPLAY" ]; then
            # --- Display migration: close old workspace, rebuild on new ---
            echo "[switch] Migrating display $FOUND_DISPLAY → $DISPLAY"
            "app_${PRIMARY_APP}_close" "$WORK_PATH"
            [ "$SECONDARY_APP" != "none" ] && "app_${SECONDARY_APP}_close" "$WORK_PATH"

            # Remove bar items
            for item in yb_badge space_label space_path action_code action_term action_folder action_close; do
                sketchybar --remove "$item" 2>/dev/null
            done
            sketchybar --bar hidden=on 2>/dev/null
            sleep 1
            echo "[switch] Old workspace closed — rebuilding on display $DISPLAY"
            # Fall through to fresh creation below
        else
            # --- Same display: re-tile + refresh bar ---
            echo "[switch] Window on display $FOUND_DISPLAY — refreshing"
            yabai -m space --layout float 2>/dev/null

            if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
                "app_${PRIMARY_APP}_focus" "$WORK_PATH"
            fi
            sleep 1

            # Find windows for layout
            PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
            SECONDARY_WID=""
            if [ "$SECONDARY_APP" != "none" ]; then
                _SPACE=""
                [ -n "$PRIMARY_WID" ] && _SPACE=$(yb_window_space "$PRIMARY_WID")
                SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$_SPACE")
            fi

            echo ""
            IFS=',' read -r _PT _PB _PL _PR <<< "$PADDING"
            yb_layout_tile "$DISPLAY" "$GAP" "$_PT" "$_PB" "$_PL" "$_PR" "$PRIMARY_WID" "$SECONDARY_WID"

            echo ""
            "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH"

            echo ""
            echo "=== Switched: $LABEL ==="
            exit 0
        fi
    else
        echo "[switch] Workspace open but window not found — creating new"
    fi
fi

# --- 3. CREATE NEW WORKSPACE ---

# Step 1: Create virtual desktop + set float mode
"$REPO_ROOT/runners/space.sh" --create --display "$DISPLAY"
yabai -m space --layout float 2>/dev/null

# Step 2: Open apps via handlers
echo ""
"app_${PRIMARY_APP}_open" "$WORK_PATH"

SECONDARY_SNAP=""
SECONDARY_WID=""
if [ "$SECONDARY_APP" != "none" ]; then
    # Snapshot before opening for delta tracking
    if type "app_${SECONDARY_APP}_snapshot" &>/dev/null; then
        SECONDARY_SNAP=$("app_${SECONDARY_APP}_snapshot")
        yb_log "secondary snapshot: ${SECONDARY_SNAP:-none}"
    fi
    "app_${SECONDARY_APP}_open" "$WORK_PATH" "$CMD"
fi

# Step 3: Wait for primary window
yb_log "waiting for windows..."
sleep 3

PRIMARY_WID=""
for i in $(seq 1 15); do
    PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
    if [ -n "$PRIMARY_WID" ]; then
        yb_log "primary window found (poll $i)"
        break
    fi
    if [ "$i" = "5" ] && type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        yb_log "retrying primary open..."
        "app_${PRIMARY_APP}_focus" "$WORK_PATH" 2>/dev/null
    fi
    sleep 1
done
[ -z "$PRIMARY_WID" ] && yb_log "WARN: primary window not found after 15s"

# Step 4: Find secondary window by snapshot delta
if [ "$SECONDARY_APP" != "none" ]; then
    # Method 1: snapshot delta (most reliable — space-independent)
    if [ -n "$SECONDARY_SNAP" ] && type "app_${SECONDARY_APP}_find_new" &>/dev/null; then
        for i in $(seq 1 10); do
            SECONDARY_WID=$("app_${SECONDARY_APP}_find_new" "$SECONDARY_SNAP")
            [ -n "$SECONDARY_WID" ] && break
            sleep 0.5
        done
        [ -n "$SECONDARY_WID" ] && yb_log "secondary wid=$SECONDARY_WID (delta)"
    fi

    # Method 2: find on same space as primary
    if [ -z "$SECONDARY_WID" ]; then
        _SPACE=""
        [ -n "$PRIMARY_WID" ] && _SPACE=$(yb_window_space "$PRIMARY_WID")
        if [ -n "$_SPACE" ]; then
            SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$_SPACE")
            [ -n "$SECONDARY_WID" ] && yb_log "secondary wid=$SECONDARY_WID (space=$_SPACE)"
        fi
    fi

    # Method 3: find any window (no space filter)
    if [ -z "$SECONDARY_WID" ]; then
        SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH")
        [ -n "$SECONDARY_WID" ] && yb_log "secondary wid=$SECONDARY_WID (any)"
    fi

    if [ -z "$SECONDARY_WID" ]; then
        # Diagnostic: show what yabai sees
        if type "app_${SECONDARY_APP}_snapshot" &>/dev/null; then
            _CURRENT=$("app_${SECONDARY_APP}_snapshot")
            yb_log "WARN: secondary not found — snap=[$SECONDARY_SNAP] now=[$_CURRENT]"
        else
            yb_log "WARN: secondary window not found"
        fi
    fi
fi

# Step 5: Layout
echo ""
IFS=',' read -r _PT _PB _PL _PR <<< "$PADDING"

case "$MODE" in
    tile)
        yb_layout_tile "$DISPLAY" "$GAP" "$_PT" "$_PB" "$_PL" "$_PR" "$PRIMARY_WID" "$SECONDARY_WID"
        ;;
    solo)
        yb_layout_solo "$DISPLAY" "$_PT" "$_PB" "$_PL" "$_PR" "$PRIMARY_WID"
        ;;
    splitview)
        yb_log "splitview: tiling primary left..."
        if type "app_${PRIMARY_APP}_tile_left" &>/dev/null; then
            "app_${PRIMARY_APP}_tile_left"
        fi
        # Click on right side of target display to pick secondary window
        osascript -l JavaScript \
            -e "var targetDID = $DISPLAY;" \
            -e '
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
var screens = $.NSScreen.screens;
var primaryH = 0;
for (var i = 0; i < screens.count; i++) {
    var f = screens.objectAtIndex(i).frame;
    if (f.origin.x === 0 && f.origin.y === 0) { primaryH = f.size.height; break; }
}
for (var i = 0; i < screens.count; i++) {
    var s = screens.objectAtIndex(i);
    var did = ObjC.unwrap(s.deviceDescription.objectForKey("NSScreenNumber"));
    if (did == targetDID) {
        var f = s.frame;
        var cgX = f.origin.x + f.size.width * 0.75;
        var cgY = (primaryH - f.origin.y - f.size.height) + f.size.height * 0.5;
        var point = $.CGPointMake(cgX, cgY);
        var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, point, $.kCGMouseButtonLeft);
        var up   = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp,   point, $.kCGMouseButtonLeft);
        $.CGEventPost($.kCGHIDEventTap, down);
        delay(0.1);
        $.CGEventPost($.kCGHIDEventTap, up);
        break;
    }
}' 2>/dev/null
        ;;
    *)
        echo "[yb] Unknown mode: $MODE"
        exit 1
        ;;
esac

# Step 6: Configure bar
echo ""
"$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH"

# Step 7: Post-setup (zoom, etc.)
if type "app_${PRIMARY_APP}_post_setup" &>/dev/null; then
    "app_${PRIMARY_APP}_post_setup" "$ZOOM"
fi

echo ""
echo "=== Ready: $LABEL ==="
