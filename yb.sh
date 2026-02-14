#!/bin/bash
# FILE: yb.sh
# Usage: yb <instance_name | layout_name> [display_id] [--debug]
#
# Generic workspace orchestrator. Application-specific logic lives in
# lib/app/*.sh handlers — this file contains zero app-specific code.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD=$(pwd)
source "$REPO_ROOT/lib/common.sh"

# --- Debug mode ---
YB_DEBUG=0
for _a in "$@"; do [ "$_a" = "--debug" ] && YB_DEBUG=1; done
# Strip --debug from args so it doesn't interfere with target parsing
_ARGS=()
for _a in "$@"; do [ "$_a" != "--debug" ] && _ARGS+=("$_a"); done
set -- "${_ARGS[@]}"

if [ "$YB_DEBUG" -eq 1 ]; then
    YB_DEBUG_DIR="$REPO_ROOT/log/debug"
    mkdir -p "$YB_DEBUG_DIR"
    # Session ID: timestamp used for all dumps in this run
    YB_DEBUG_SESSION=$(python3 -c "import datetime; print(datetime.datetime.now().strftime('%Y-%m-%d_%H-%M-%S.%f')[:23])")
    YB_DEBUG_SEQ=0
    yb_debug() {
        local step="$1" note="${2:-}"
        YB_DEBUG_SEQ=$((YB_DEBUG_SEQ + 1))
        local seq=$(printf "%02d" "$YB_DEBUG_SEQ")
        local ts=$(python3 -c "import datetime; print(datetime.datetime.now().strftime('%H:%M:%S.%f')[:12])")
        local file="$YB_DEBUG_DIR/${YB_DEBUG_SESSION}_${LABEL:-YB}_${seq}_${step}.json"

        # Probe sketchybar state (lightweight: 1 bar query + 1 item query)
        local _sbar_running=false
        pgrep -q sketchybar && _sbar_running=true
        local _sbar_height="dead"
        local _sbar_badge_space="missing"
        if [ "$_sbar_running" = "true" ]; then
            _sbar_height=$(sketchybar --query bar 2>/dev/null | jq -r '.height // "error"' 2>/dev/null || echo "error")
            # Probe badge item as representative (associated_space_mask is a bitmask: 2^N = space N)
            if [ -n "${LABEL:-}" ]; then
                local _mask=$(sketchybar --query "${LABEL}_badge" 2>/dev/null | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
                if [ -n "$_mask" ] && [ "$_mask" -gt 0 ] 2>/dev/null; then
                    local _b=$_mask _n=0
                    while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
                    _sbar_badge_space="$_n"
                fi
            fi
        fi

        {
            echo "{"
            echo "  \"timestamp\": \"$ts\","
            echo "  \"label\": \"${LABEL:-}\","
            echo "  \"step\": \"$step\","
            echo "  \"note\": \"$note\","
            echo "  \"space_idx\": \"${SPACE_IDX:-}\","
            echo "  \"display\": \"${DISPLAY:-}\","
            echo "  \"primary_wid\": \"${PRIMARY_WID:-}\","
            echo "  \"secondary_wid\": \"${SECONDARY_WID:-}\","
            echo "  \"sketchybar\": {"
            echo "    \"running\": $_sbar_running,"
            echo "    \"bar_height\": \"$_sbar_height\","
            echo "    \"badge_space\": \"$_sbar_badge_space\""
            echo "  },"
            echo "  \"windows\": $(yabai -m query --windows 2>/dev/null || echo '[]'),"
            echo "  \"spaces\": $(yabai -m query --spaces 2>/dev/null || echo '[]')"
            echo "}"
        } > "$file"
        yb_log "debug[$seq]: $step → $file"
    }
    yb_log "DEBUG MODE ON — session=$YB_DEBUG_SESSION dir=$YB_DEBUG_DIR"
else
    yb_debug() { :; }
fi

# --- 0. NO ARGS: SHOW STATUS ---
if [ -z "$1" ]; then
    echo "yb - workspace orchestrator"
    echo ""
    echo "Usage: yb <target> [display_id] [--debug]"
    echo "       yb init <layout> [display_id]"
    echo "       yb -d <space_label>"
    echo ""
    echo "  cd ~/my-project && yb init claudedev 3"
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
    BAR_HEIGHT=$(yb_bar_height "$BAR_STYLE")

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
    PADDING="$L_PAD_T,$L_PAD_B,$L_PAD_L,$L_PAD_R"
    BAR_HEIGHT=$(yb_bar_height "$BAR_STYLE")
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
yb_log "config: bar=$BAR_STYLE bar_h=$BAR_HEIGHT gap=$GAP pad=$PADDING"
yb_debug "config" "resolved target=$TARGET primary=$PRIMARY_APP secondary=$SECONDARY_APP"

# --- 2. CHECK FOR EXISTING WORKSPACE ---
_HAS_WORKSPACE=0
if type "app_${PRIMARY_APP}_is_open" &>/dev/null; then
    "app_${PRIMARY_APP}_is_open" "$WORK_PATH" && _HAS_WORKSPACE=1
fi
yb_log "workspace check: open=$_HAS_WORKSPACE"
yb_debug "workspace-check" "open=$_HAS_WORKSPACE"

if [ "$_HAS_WORKSPACE" -eq 1 ]; then
    echo "[switch] Workspace '$FOLDER_NAME' is open — locating window"

    SWITCH_RESULT="none"
    if type "app_${PRIMARY_APP}_locate" &>/dev/null; then
        SWITCH_RESULT=$("app_${PRIMARY_APP}_locate" "$WORK_PATH")
    fi
    yb_log "locate result: $SWITCH_RESULT"
    yb_debug "switch-locate" "result=$SWITCH_RESULT"

    # If JXA locate failed, try yabai directly — it can see windows on all spaces
    # without focusing the app (which would pollute the current space with a new window)
    if [[ "$SWITCH_RESULT" != found:* ]]; then
        yb_log "locate: JXA can't see window — trying yabai"
        _RETRY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
        if [ -n "$_RETRY_WID" ]; then
            _W_DISP_IDX=$(yabai -m query --windows --window "$_RETRY_WID" 2>/dev/null | jq -r '.display')
            _W_DID=$(yabai -m query --displays | jq -r --argjson di "$_W_DISP_IDX" \
                '.[] | select(.index == $di) | .id')
            SWITCH_RESULT="found:$_W_DID"
            yb_log "locate retry (yabai): wid=$_RETRY_WID display=$_W_DID"
        else
            yb_log "locate retry: not found via yabai either"
        fi
    fi

    if [[ "$SWITCH_RESULT" == found:* ]]; then
        FOUND_DISPLAY="${SWITCH_RESULT#found:}"

        if [ "$FOUND_DISPLAY" != "$DISPLAY" ]; then
            # --- Display migration: close old workspace, rebuild on new ---
            yb_log "switch: migrating display $FOUND_DISPLAY → $DISPLAY"
            "app_${PRIMARY_APP}_close" "$WORK_PATH"
            [ "$SECONDARY_APP" != "none" ] && "app_${SECONDARY_APP}_close" "$WORK_PATH"

            for suffix in badge label path code term folder close; do
                sketchybar --remove "${LABEL}_${suffix}" 2>/dev/null
            done
            sleep 1
            yb_log "switch: old workspace closed — rebuilding on display $DISPLAY"
            # Fall through to fresh creation below
        else
            # --- Same display: check if space is shared before refreshing ---
            SPACE_IDX=$(yb_visible_space "$DISPLAY")
            _SPACE_WINS=$(yabai -m query --windows --space "$SPACE_IDX" 2>/dev/null | jq '[.[] | select(.["is-sticky"] == false and .["is-floating"] == false)] | length')
            _MAX_WINS=2
            [ "$MODE" = "solo" ] && _MAX_WINS=1

            if [ "$_SPACE_WINS" -gt "$_MAX_WINS" ]; then
                # Space is shared with another workspace — close our stale window and rebuild
                yb_log "switch: space=$SPACE_IDX has $_SPACE_WINS windows (shared) — closing stale + rebuilding"
                "app_${PRIMARY_APP}_close" "$WORK_PATH"
                [ "$SECONDARY_APP" != "none" ] && "app_${SECONDARY_APP}_close" "$WORK_PATH"
                sleep 0.5
                # Fall through to CREATE NEW WORKSPACE
            else
                yb_log "switch: window on display $FOUND_DISPLAY space=$SPACE_IDX ($_SPACE_WINS wins) — refreshing"

                IFS=',' read -r _PT _PB _PL _PR <<< "$PADDING"
                yb_space_bsp "$SPACE_IDX" "$GAP" "$_PT" "$_PB" "$_PL" "$_PR" "$BAR_HEIGHT"

                # Switch to target space — must be active before opening/focusing apps
                yb_log "switch: focusing space=$SPACE_IDX on display=$DISPLAY"
                yabai -m space --focus "$SPACE_IDX" 2>/dev/null
                sleep 0.3
                yb_debug "switch-bsp" "space=$SPACE_IDX BSP configured + focused"

                # Bar: check if namespaced items already exist; rebind only
                yb_log "switch: checking namespace ${LABEL}_* items..."
                _NS_FOUND=0
                _NS_MISSING=0
                for _suffix in badge label path code term folder close; do
                    _item="${LABEL}_${_suffix}"
                    _qr=$(sketchybar --query "$_item" 2>&1 | head -1)
                    if [ -n "$_qr" ] && [[ "$_qr" != *"not found"* ]]; then
                        _NS_FOUND=$((_NS_FOUND + 1))
                    else
                        _NS_MISSING=$((_NS_MISSING + 1))
                        yb_log "switch: namespace item MISSING: $_item"
                    fi
                done
                yb_log "switch: namespace check: found=$_NS_FOUND missing=$_NS_MISSING"

                if [ "$_NS_MISSING" -eq 0 ]; then
                    yb_log "switch: all ${LABEL}_* items exist — rebinding to space=$SPACE_IDX"
                    for _suffix in badge label path code term folder close; do
                        sketchybar --set "${LABEL}_${_suffix}" associated_space="$SPACE_IDX" 2>/dev/null
                    done
                    sketchybar --update 2>/dev/null
                else
                    yb_log "switch: ${_NS_MISSING} items missing — creating full bar"
                    "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH" --space "$SPACE_IDX"
                fi
                yb_debug "switch-bar" "bar handled for space=$SPACE_IDX"

                # Find + focus primary app
                PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH" "$SPACE_IDX")
                yb_log "switch: primary $PRIMARY_APP wid=${PRIMARY_WID:-none} on space=$SPACE_IDX"
                if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
                    yb_log "switch: focusing $PRIMARY_APP"
                    "app_${PRIMARY_APP}_focus" "$WORK_PATH"
                fi
                yb_debug "switch-focus" "primary $PRIMARY_APP wid=${PRIMARY_WID:-none}"

                # Ensure secondary app is on this space
                SECONDARY_WID=""
                if [ "$SECONDARY_APP" != "none" ] && [ -n "$SPACE_IDX" ]; then
                    SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$SPACE_IDX")
                    if [ -n "$SECONDARY_WID" ]; then
                        yb_log "switch: secondary $SECONDARY_APP wid=$SECONDARY_WID on space=$SPACE_IDX"
                    else
                        SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH")
                        if [ -n "$SECONDARY_WID" ]; then
                            yb_log "switch: moving secondary wid=$SECONDARY_WID → space=$SPACE_IDX"
                            yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
                        else
                            yb_log "switch: secondary $SECONDARY_APP not found — opening"
                            YB_LAST_OPENED_WID=""
                            "app_${SECONDARY_APP}_open" "$WORK_PATH" "$CMD"
                            if [ -n "$YB_LAST_OPENED_WID" ]; then
                                SECONDARY_WID="$YB_LAST_OPENED_WID"
                                yb_log "switch: new secondary wid=$SECONDARY_WID"
                                _SS=$(yb_window_space "$SECONDARY_WID")
                                [ "$_SS" != "$SPACE_IDX" ] && yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
                            fi
                        fi
                    fi
                fi
                yb_debug "switch-secondary" "secondary=$SECONDARY_APP wid=${SECONDARY_WID:-none}"

                # Check window order: primary should be left, secondary right
                if [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ]; then
                    _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
                    _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
                    yb_log "switch: order check primary.x=${_PX} secondary.x=${_SX}"
                    if [ "${_PX%.*}" -gt "${_SX%.*}" ] 2>/dev/null; then
                        yb_log "switch: swapping — primary was on right"
                        yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
                    else
                        yb_log "switch: order correct (primary left, secondary right)"
                    fi
                fi

                yb_debug "switch-done" "workspace switched"

                # Run debug analysis if in debug mode
                if [ "$YB_DEBUG" -eq 1 ]; then
                    echo ""
                    "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
                fi

                echo ""
                echo "=== Switched: $LABEL ==="
                exit 0
            fi
        fi
    else
        yb_log "switch: WARN window still not found after focus — creating new"
    fi
fi

# --- 3. CREATE NEW WORKSPACE ---

# Step 1: Create virtual desktop + configure BSP
yb_debug "pre-create" "about to create desktop"
yb_log "step1: creating desktop on display=$DISPLAY"
"$REPO_ROOT/runners/space.sh" --create --display "$DISPLAY"

# Get space index — verify it's actually empty (plist can be stale after yabai moves)
SPACE_IDX=$(yb_visible_space "$DISPLAY")
if [ -n "$SPACE_IDX" ]; then
    _WIN_COUNT=$(yabai -m query --windows --space "$SPACE_IDX" 2>/dev/null | jq '[.[] | select(.["is-sticky"] == false)] | length')
    if [ "$_WIN_COUNT" -gt 0 ]; then
        yb_log "step1: space=$SPACE_IDX has $_WIN_COUNT windows — creating fresh space"
        yabai -m space --create 2>/dev/null
        # Focus the new space (last on this display)
        _NEW_SPACE=$(yabai -m query --spaces | jq -r --argjson di "$(yabai -m query --displays | jq -r --argjson did "$DISPLAY" '.[] | select(.id == $did) | .index')" \
            '[.[] | select(.display == $di)] | sort_by(.index) | last | .index')
        if [ -n "$_NEW_SPACE" ] && [ "$_NEW_SPACE" != "$SPACE_IDX" ]; then
            yabai -m space --focus "$_NEW_SPACE" 2>/dev/null
            SPACE_IDX="$_NEW_SPACE"
            yb_log "step1: created + focused space=$SPACE_IDX"
        else
            yb_log "step1: WARN could not create fresh space, using $SPACE_IDX"
        fi
    else
        yb_log "step1: space=$SPACE_IDX is empty — using it"
    fi
    IFS=',' read -r _PT _PB _PL _PR <<< "$PADDING"
    yb_space_bsp "$SPACE_IDX" "$GAP" "$_PT" "$_PB" "$_PL" "$_PR" "$BAR_HEIGHT"
else
    yb_log "WARN: could not determine space index on display $DISPLAY"
fi

yb_debug "post-space" "space=$SPACE_IDX created + BSP configured"

# Step 1a: Rebind stale bar items for other workspaces (space creation may have shifted indices)
yb_rebind_stale_items "$LABEL"

# Step 1b: Configure bar (before windows — establishes namespace)
yb_log "step1b: bar style=$BAR_STYLE display=$DISPLAY space=$SPACE_IDX"
"$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH" --space "$SPACE_IDX"

yb_debug "post-bar" "bar configured for space=$SPACE_IDX"

# Step 2: Open apps via handlers
yb_log "step2: opening $PRIMARY_APP + $SECONDARY_APP"
"app_${PRIMARY_APP}_open" "$WORK_PATH"

SECONDARY_WID=""
if [ "$SECONDARY_APP" != "none" ]; then
    YB_LAST_OPENED_WID=""
    "app_${SECONDARY_APP}_open" "$WORK_PATH" "$CMD"
    if [ -n "$YB_LAST_OPENED_WID" ]; then
        SECONDARY_WID="$YB_LAST_OPENED_WID"
        yb_log "step2: secondary captured wid=$SECONDARY_WID"
        # Move immediately to target space (don't wait for step 4b)
        if [ -n "$SPACE_IDX" ]; then
            _SS=$(yb_window_space "$SECONDARY_WID")
            if [ "$_SS" != "$SPACE_IDX" ]; then
                yb_log "step2: moving secondary wid=$SECONDARY_WID from space=$_SS → space=$SPACE_IDX"
                yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
            fi
        fi
    else
        yb_log "step2: secondary wid not captured (will poll)"
    fi
fi

# Step 3: Wait for primary window
yb_log "step3: polling for primary $PRIMARY_APP window..."
sleep 3

PRIMARY_WID=""
for i in $(seq 1 15); do
    PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
    if [ -n "$PRIMARY_WID" ]; then
        yb_log "step3: primary wid=$PRIMARY_WID found (poll $i)"
        break
    fi
    if [ "$i" = "5" ] && type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        yb_log "step3: retrying primary open..."
        "app_${PRIMARY_APP}_focus" "$WORK_PATH" 2>/dev/null
    fi
    sleep 1
done
[ -z "$PRIMARY_WID" ] && yb_log "step3: WARN primary window not found after 15s"
yb_debug "post-poll" "primary=$PRIMARY_WID"

# Step 4: Find secondary window (fallback if not captured during open)
if [ "$SECONDARY_APP" != "none" ] && [ -z "$SECONDARY_WID" ]; then
    yb_log "step4: polling for secondary $SECONDARY_APP window..."

    for _poll in $(seq 1 5); do
        # Try 1: find on target space (where it should be)
        if [ -n "$SPACE_IDX" ]; then
            SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$SPACE_IDX")
            [ -n "$SECONDARY_WID" ] && { yb_log "step4: secondary wid=$SECONDARY_WID (space=$SPACE_IDX, poll $_poll)"; break; }
        fi

        # Try 2: find on primary's space (may differ if window landed there)
        _SPACE=""
        [ -n "$PRIMARY_WID" ] && _SPACE=$(yb_window_space "$PRIMARY_WID")
        if [ -n "$_SPACE" ] && [ "$_SPACE" != "$SPACE_IDX" ]; then
            SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$_SPACE")
            [ -n "$SECONDARY_WID" ] && { yb_log "step4: secondary wid=$SECONDARY_WID (primary_space=$_SPACE, poll $_poll)"; break; }
        fi

        # Try 3: find globally (any space — catches wrong-space landings)
        SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH")
        [ -n "$SECONDARY_WID" ] && { yb_log "step4: secondary wid=$SECONDARY_WID (global, poll $_poll)"; break; }

        sleep 1
    done

    [ -z "$SECONDARY_WID" ] && yb_log "step4: WARN secondary window not found after 5 polls"
else
    [ -n "$SECONDARY_WID" ] && yb_log "step4: secondary wid=$SECONDARY_WID (captured)"
fi

# Step 4b: Move windows to the correct space if they landed elsewhere
yb_log "step4b: ensuring windows on space=$SPACE_IDX"
if [ -n "$SPACE_IDX" ]; then
    if [ -n "$PRIMARY_WID" ]; then
        _P_SPACE=$(yb_window_space "$PRIMARY_WID")
        if [ "$_P_SPACE" != "$SPACE_IDX" ]; then
            yb_log "moving primary wid=$PRIMARY_WID from space=$_P_SPACE → space=$SPACE_IDX"
            yabai -m window "$PRIMARY_WID" --space "$SPACE_IDX" 2>/dev/null
            yb_log "move primary: exit=$?"
        else
            yb_log "primary wid=$PRIMARY_WID already on space=$SPACE_IDX"
        fi
    fi
    if [ -n "$SECONDARY_WID" ]; then
        _S_SPACE=$(yb_window_space "$SECONDARY_WID")
        if [ "$_S_SPACE" != "$SPACE_IDX" ]; then
            yb_log "moving secondary wid=$SECONDARY_WID from space=$_S_SPACE → space=$SPACE_IDX"
            yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
            yb_log "move secondary: exit=$?"
        else
            yb_log "secondary wid=$SECONDARY_WID already on space=$SPACE_IDX"
        fi
    fi
fi
yb_debug "post-move" "windows moved to space=$SPACE_IDX"

# Step 5: Layout
echo ""

case "$MODE" in
    tile|solo)
        yb_log "step5: layout=$MODE primary=$PRIMARY_WID secondary=$SECONDARY_WID"
        if [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ]; then
            _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
            _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
            yb_log "step5: primary.x=${_PX} secondary.x=${_SX}"
            if [ "${_PX%.*}" -gt "${_SX%.*}" ] 2>/dev/null; then
                yb_log "step5: swapping — primary was on right"
                yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
            else
                yb_log "step5: order correct (primary left, secondary right)"
            fi
        elif [ -n "$PRIMARY_WID" ]; then
            yb_log "step5: solo window — BSP fills space"
        else
            yb_log "step5: WARN no windows to layout"
        fi
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
yb_debug "post-layout" "layout=$MODE complete"

# Step 6: Post-setup (zoom, etc.)
if type "app_${PRIMARY_APP}_post_setup" &>/dev/null; then
    yb_log "step6: post-setup zoom=$ZOOM"
    "app_${PRIMARY_APP}_post_setup" "$ZOOM"
fi

yb_debug "done" "workspace ready"

# Run debug analysis if in debug mode
if [ "$YB_DEBUG" -eq 1 ]; then
    echo ""
    "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
fi

echo ""
echo "=== Ready: $LABEL ==="
