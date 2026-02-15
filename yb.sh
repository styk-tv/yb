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
    echo "       yb down"
    echo "       yb -d <space_label>"
    echo ""
    echo "  cd ~/my-project && yb init claudedev 3"
    echo ""

    # --- Services ---
    YABAI_STATUS="off"; pgrep -q yabai 2>/dev/null && YABAI_STATUS="on"
    SBAR_STATUS="off"; pgrep -q sketchybar 2>/dev/null && SBAR_STATUS="on"
    SKHD_STATUS="off"; pgrep -q skhd 2>/dev/null && SKHD_STATUS="on"
    SIP_STATUS=$(csrutil status 2>/dev/null | grep -o "enabled\|disabled" || echo "unknown")
    printf "  yabai %-8s  sketchybar %-8s  skhd %-8s  sip %s\n" "$YABAI_STATUS" "$SBAR_STATUS" "$SKHD_STATUS" "$SIP_STATUS"
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
    echo ""

    # --- Live Workspaces (from state manifest) ---
    _MANIFEST=$(yb_state_read)
    _WS_KEYS=$(echo "$_MANIFEST" | jq -r '.workspaces // {} | keys[]' 2>/dev/null)
    if [ -n "$_WS_KEYS" ]; then
        echo "Live Workspaces:"
        for _wk in $_WS_KEYS; do
            _we=$(echo "$_MANIFEST" | jq -r --arg l "$_wk" '.workspaces[$l]')
            _ws_sp=$(echo "$_we" | jq -r '.space_idx // "?"')
            _ws_disp=$(echo "$_we" | jq -r '.display // "?"')
            _ws_pwid=$(echo "$_we" | jq -r '.primary.wid // 0')
            _ws_papp=$(echo "$_we" | jq -r '.primary.app // "?"')
            _ws_swid=$(echo "$_we" | jq -r '.secondary.wid // 0')
            _ws_sapp=$(echo "$_we" | jq -r '.secondary.app // "?"')
            _ws_mode=$(echo "$_we" | jq -r '.mode // "?"')

            # Quick liveness check: primary wid still exists?
            _ws_status="?"
            if yabai -m query --windows --window "$_ws_pwid" >/dev/null 2>&1; then
                _ws_status="alive"
            else
                _ws_status="stale"
            fi

            if [ "$_ws_mode" = "tile" ] && [ "$_ws_swid" -gt 0 ] 2>/dev/null; then
                printf "  %-10s space=%-3s display=%-3s %s(%s)+%s(%s)  %s\n" \
                    "$_wk" "$_ws_sp" "$_ws_disp" "$_ws_papp" "$_ws_pwid" "$_ws_sapp" "$_ws_swid" "$_ws_status"
            else
                printf "  %-10s space=%-3s display=%-3s %s(%s)  %s\n" \
                    "$_wk" "$_ws_sp" "$_ws_disp" "$_ws_papp" "$_ws_pwid" "$_ws_status"
            fi
        done
        echo ""
    fi

    exit 0
fi

TARGET=$1
DEFAULT_DISPLAY=4

# --- 0a. DOWN MODE: close YB-managed workspaces + shut down services ---
if [ "$1" == "down" ]; then
    echo "[yb] Shutting down..."

    # Step 1: Collect YB-managed space indices from bar badges BEFORE removing items
    _YB_SPACES=""
    for _inst in "$REPO_ROOT"/instances/*.yaml; do
        [ -f "$_inst" ] || continue
        _name=$(basename "$_inst" .yaml)
        _LABEL=$(echo "$_name" | tr '[:lower:]' '[:upper:]')

        _MASK=$(sketchybar --query "${_LABEL}_badge" 2>/dev/null | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
        if [ -n "$_MASK" ] && [ "$_MASK" -gt 0 ] 2>/dev/null; then
            _b=$_MASK _n=0
            while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
            _YB_SPACES="$_YB_SPACES $_n"
            echo "  $_LABEL: space $_n"
        fi
    done

    # Step 2: Close ONLY windows on YB-managed spaces (not other windows)
    _CLOSED=0
    if yabai -m query --windows >/dev/null 2>&1; then
        for _sp in $_YB_SPACES; do
            _SP_WIDS=$(yabai -m query --windows | jq -r --argjson sp "$_sp" \
                '.[] | select(.space == $sp and .["is-sticky"] == false) | .id')
            for _wid in $_SP_WIDS; do
                yabai -m window "$_wid" --close 2>/dev/null && _CLOSED=$((_CLOSED + 1))
            done
        done
    fi
    echo "  Closed $_CLOSED windows on YB spaces"

    # Step 2b: Clear state manifest
    yb_state_clear
    echo "  State manifest cleared"

    # Step 3: Remove all bar items
    for _inst in "$REPO_ROOT"/instances/*.yaml; do
        [ -f "$_inst" ] || continue
        _name=$(basename "$_inst" .yaml)
        _LABEL=$(echo "$_name" | tr '[:lower:]' '[:upper:]')
        for _suffix in badge label path code term folder close; do
            sketchybar --remove "${_LABEL}_${_suffix}" 2>/dev/null
        done
    done
    echo "  Bar items removed"

    # Step 4: Stop services (spaces left as empties — reused on next launch)
    yabai --stop-service 2>/dev/null
    echo "  yabai stopped"
    brew services stop sketchybar 2>/dev/null
    echo "  sketchybar stopped"
    skhd --stop-service 2>/dev/null
    echo "  skhd stopped"

    echo "[yb] All services down. Launch any workspace to wake up."
    exit 0
fi

# --- 0b. Reserved ---

# --- 0c. ENSURE SERVICES ARE RUNNING ---
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

# --- 0d. INIT MODE ---
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

# Determine engine: yabai or jxa
YB_ENGINE="jxa"
yb_yabai_ok && YB_ENGINE="yabai"

# Source app handlers: shared first, then engine override
_yb_load_handler() {
    local app="$1"
    local base="$REPO_ROOT/lib/app/${app}.sh"
    local engine="$REPO_ROOT/lib/app/${app}.${YB_ENGINE}.sh"
    if [ ! -f "$base" ]; then
        echo "Unknown app handler: $app (missing $base)"
        exit 1
    fi
    source "$base"
    if [ -f "$engine" ]; then
        source "$engine"
    fi
}

_yb_load_handler "$PRIMARY_APP"
[ "$SECONDARY_APP" != "none" ] && _yb_load_handler "$SECONDARY_APP"
yb_log "engine: $YB_ENGINE"

echo "=== yb: $TARGET → $PRIMARY_APP+$SECONDARY_APP/$MODE on display $DISPLAY ==="
yb_log "config: bar=$BAR_STYLE bar_h=$BAR_HEIGHT gap=$GAP pad=$PADDING"
yb_debug "config" "resolved target=$TARGET primary=$PRIMARY_APP secondary=$SECONDARY_APP"

# --- 1b. STATE VALIDATION (fast path — before any discovery) ---
# Call directly (not in subshell) so _SV_SPACE_IDX/_SV_PRIMARY_WID/_SV_SECONDARY_WID propagate
yb_state_validate "$LABEL"
_STATE_RESULT="$_SV_RESULT"
yb_log "state: validate=$_STATE_RESULT"
yb_debug "state-validate" "result=$_STATE_RESULT"

if [ "$_STATE_RESULT" = "intact" ]; then
    # === STATE FAST PATH: workspace fully intact — focus only, ZERO discovery ===
    yb_log "state: intact on space=$_SV_SPACE_IDX — focus only"
    SPACE_IDX="$_SV_SPACE_IDX"
    PRIMARY_WID="$_SV_PRIMARY_WID"
    SECONDARY_WID="$_SV_SECONDARY_WID"
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.2
    if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        "app_${PRIMARY_APP}_focus" "$WORK_PATH"
    fi
    yb_debug "switch-done" "state intact — focused"
    if [ "$YB_DEBUG" -eq 1 ]; then
        echo ""
        "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
    fi
    echo ""
    echo "=== Switched: $LABEL ==="
    exit 0
fi

if [ "$_STATE_RESULT" = "space_gone" ]; then
    yb_log "state: space gone — removing stale entry, will CREATE"
    yb_state_remove "$LABEL"
fi

if [ "$_STATE_RESULT" = "order_wrong" ]; then
    SPACE_IDX="$_SV_SPACE_IDX"
    PRIMARY_WID="$_SV_PRIMARY_WID"
    SECONDARY_WID="$_SV_SECONDARY_WID"
    yb_log "state: order wrong — swapping windows"
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.2
    yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
    if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        "app_${PRIMARY_APP}_focus" "$WORK_PATH"
    fi
    yb_debug "switch-done" "state order_wrong — swapped"
    if [ "$YB_DEBUG" -eq 1 ]; then
        echo ""
        "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
    fi
    echo ""
    echo "=== Switched: $LABEL ==="
    exit 0
fi

if [ "$_STATE_RESULT" = "bar_missing" ]; then
    SPACE_IDX="$_SV_SPACE_IDX"
    PRIMARY_WID="$_SV_PRIMARY_WID"
    SECONDARY_WID="$_SV_SECONDARY_WID"
    yb_log "state: bar missing — creating"
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.2
    "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH" --space "$SPACE_IDX"
    if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        "app_${PRIMARY_APP}_focus" "$WORK_PATH"
    fi
    yb_state_set "$LABEL" "$(yb_state_build_json)"
    yb_debug "switch-done" "state bar_missing — created bar"
    if [ "$YB_DEBUG" -eq 1 ]; then
        echo ""
        "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
    fi
    echo ""
    echo "=== Switched: $LABEL ==="
    exit 0
fi

if [ "$_STATE_RESULT" = "bar_stale" ]; then
    SPACE_IDX="$_SV_SPACE_IDX"
    PRIMARY_WID="$_SV_PRIMARY_WID"
    SECONDARY_WID="$_SV_SECONDARY_WID"
    yb_log "state: bar stale — rebinding to space=$SPACE_IDX"
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.2
    for _suffix in badge label path code term folder close; do
        sketchybar --set "${LABEL}_${_suffix}" associated_space="$SPACE_IDX" 2>/dev/null
    done
    sketchybar --update 2>/dev/null
    if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        "app_${PRIMARY_APP}_focus" "$WORK_PATH"
    fi
    yb_debug "switch-done" "state bar_stale — rebound"
    if [ "$YB_DEBUG" -eq 1 ]; then
        echo ""
        "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
    fi
    echo ""
    echo "=== Switched: $LABEL ==="
    exit 0
fi

if [ "$_STATE_RESULT" = "primary_drifted" ] || [ "$_STATE_RESULT" = "secondary_drifted" ]; then
    SPACE_IDX="$_SV_SPACE_IDX"
    PRIMARY_WID="$_SV_PRIMARY_WID"
    SECONDARY_WID="$_SV_SECONDARY_WID"
    yb_log "state: $_STATE_RESULT — moving window back to space=$SPACE_IDX"
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.2
    if [ "$_STATE_RESULT" = "primary_drifted" ] && [ -n "$PRIMARY_WID" ]; then
        yabai -m window "$PRIMARY_WID" --space "$SPACE_IDX" 2>/dev/null
    fi
    if [ "$_STATE_RESULT" = "secondary_drifted" ] && [ -n "$SECONDARY_WID" ]; then
        yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
    fi
    sleep 0.3
    if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
        "app_${PRIMARY_APP}_focus" "$WORK_PATH"
    fi
    yb_state_set "$LABEL" "$(yb_state_build_json)"
    yb_debug "switch-done" "state $_STATE_RESULT — moved back"
    if [ "$YB_DEBUG" -eq 1 ]; then
        echo ""
        "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
    fi
    echo ""
    echo "=== Switched: $LABEL ==="
    exit 0
fi

# For primary_dead / secondary_dead: fall through to existing SWITCH REPAIR logic
# which already handles reopening missing windows. State will be updated at end of repair.
if [ "$_STATE_RESULT" = "primary_dead" ] || [ "$_STATE_RESULT" = "secondary_dead" ]; then
    yb_log "state: $_STATE_RESULT — falling through to REPAIR"
    # Pre-populate SPACE_IDX from state so repair knows where to work
    SPACE_IDX="$_SV_SPACE_IDX"
fi

# --- 2. CHECK FOR EXISTING WORKSPACE ---
_HAS_WORKSPACE=0
if type "app_${PRIMARY_APP}_is_open" &>/dev/null; then
    "app_${PRIMARY_APP}_is_open" "$WORK_PATH" && _HAS_WORKSPACE=1
fi

# If state says a window is dead, force into switch path for repair
if [ "$_STATE_RESULT" = "primary_dead" ] || [ "$_STATE_RESULT" = "secondary_dead" ]; then
    _HAS_WORKSPACE=1
fi

yb_log "workspace check: open=$_HAS_WORKSPACE"
yb_debug "workspace-check" "open=$_HAS_WORKSPACE"

if [ "$_HAS_WORKSPACE" -eq 1 ]; then
    echo "[switch] Workspace '$FOLDER_NAME' is open — locating window"

    SWITCH_RESULT="none"
    if yb_yabai_ok; then
        # Yabai mode (tile/solo): query window directly — no JXA coordinate mapping
        _FOUND_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
        if [ -n "$_FOUND_WID" ]; then
            _W_DISP_IDX=$(yabai -m query --windows --window "$_FOUND_WID" 2>/dev/null | jq -r '.display')
            _W_DID=$(yabai -m query --displays | jq -r --argjson di "$_W_DISP_IDX" \
                '.[] | select(.index == $di) | .id')
            SWITCH_RESULT="found:$_W_DID"
            yb_log "locate (yabai): wid=$_FOUND_WID display=$_W_DID"
        else
            yb_log "locate (yabai): window not found"
        fi
    elif type "app_${PRIMARY_APP}_locate" &>/dev/null; then
        # JXA mode (splitview): coordinate-based locate
        SWITCH_RESULT=$("app_${PRIMARY_APP}_locate" "$WORK_PATH")
        yb_log "locate (jxa): $SWITCH_RESULT"
    fi
    yb_debug "switch-locate" "result=$SWITCH_RESULT"

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
            # --- Same display: get workspace's actual space (not just visible space) ---
            _FOUND_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
            if [ -n "$_FOUND_WID" ]; then
                SPACE_IDX=$(yb_window_space "$_FOUND_WID")
                yb_log "switch: actual space=$SPACE_IDX (from primary wid=$_FOUND_WID)"
            else
                SPACE_IDX=$(yb_visible_space "$DISPLAY")
                yb_log "switch: visible space=$SPACE_IDX (fallback — primary wid not queryable)"
            fi
            # --- Check OUR windows on this space (ignore unrelated apps) ---
            PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH" "$SPACE_IDX")
            SECONDARY_WID=""
            [ "$SECONDARY_APP" != "none" ] && SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH" "$SPACE_IDX")

            _EXPECTED=1; [ "$MODE" = "tile" ] && _EXPECTED=2
            _HAVE=0
            [ -n "$PRIMARY_WID" ] && _HAVE=$((_HAVE + 1))
            [ "$MODE" = "tile" ] && [ -n "$SECONDARY_WID" ] && _HAVE=$((_HAVE + 1))

            # --- Intact check: all expected windows present + correct layout? ---
            _INTACT=1

            # Windows present?
            if [ "$_HAVE" -lt "$_EXPECTED" ]; then
                _INTACT=0
                yb_log "switch: missing windows (have=$_HAVE expected=$_EXPECTED)"
            fi

            # Order check (tile mode): primary should be left of secondary
            if [ "$_INTACT" -eq 1 ] && [ "$MODE" = "tile" ] && [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ]; then
                _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
                _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
                if [ "${_PX%.*}" -gt "${_SX%.*}" ] 2>/dev/null; then
                    _INTACT=0
                    yb_log "switch: wrong order (primary.x=${_PX} > secondary.x=${_SX})"
                fi
            fi

            # Bar items check
            if [ "$_INTACT" -eq 1 ]; then
                _BAR_QR=$(sketchybar --query "${LABEL}_badge" 2>&1 | head -1)
                if [ -z "$_BAR_QR" ] || [[ "$_BAR_QR" == *"not found"* ]]; then
                    _INTACT=0
                    yb_log "switch: bar items missing"
                fi
            fi

            if [ "$_INTACT" -eq 1 ]; then
                # === FAST PATH: workspace fully intact — focus only, zero layout changes ===
                yb_log "switch: workspace intact on space=$SPACE_IDX — focus only"
                yb_focus_space "$SPACE_IDX" "$DISPLAY"
                sleep 0.2
                if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
                    "app_${PRIMARY_APP}_focus" "$WORK_PATH"
                fi
                for _suffix in badge label path code term folder close; do
                    sketchybar --set "${LABEL}_${_suffix}" associated_space="$SPACE_IDX" 2>/dev/null
                done
                # Write state (captures WIDs for subsequent state-fast-path)
                yb_state_set "$LABEL" "$(yb_state_build_json)"
                yb_debug "switch-done" "workspace intact — focused"
                if [ "$YB_DEBUG" -eq 1 ]; then
                    echo ""
                    "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
                fi
                echo ""
                echo "=== Switched: $LABEL ==="
                exit 0
            fi

            # === REPAIR PATH: fix in-place — never close existing, never fall through to CREATE ===
            yb_log "switch: repairing in-place on space=$SPACE_IDX (have=$_HAVE expected=$_EXPECTED)"

            IFS=',' read -r _PT _PB _PL _PR <<< "$PADDING"
            yb_space_bsp "$SPACE_IDX" "$GAP" "$_PT" "$_PB" "$_PL" "$_PR" "$BAR_HEIGHT"
            yb_focus_space "$SPACE_IDX" "$DISPLAY"
            sleep 0.3
            yb_debug "switch-bsp" "space=$SPACE_IDX BSP configured + focused"

            # Ensure primary on this space
            if [ -z "$PRIMARY_WID" ]; then
                PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
                if [ -n "$PRIMARY_WID" ]; then
                    _ps=$(yb_window_space "$PRIMARY_WID")
                    if [ "$_ps" != "$SPACE_IDX" ]; then
                        yb_log "switch: moving primary wid=$PRIMARY_WID → space=$SPACE_IDX"
                        yabai -m window "$PRIMARY_WID" --space "$SPACE_IDX" 2>/dev/null
                    fi
                else
                    yb_log "switch: primary not found — opening $PRIMARY_APP"
                    "app_${PRIMARY_APP}_open" "$WORK_PATH"
                    sleep 3
                    for _i in $(seq 1 10); do
                        PRIMARY_WID=$("app_${PRIMARY_APP}_find" "$WORK_PATH")
                        [ -n "$PRIMARY_WID" ] && break
                        sleep 1
                    done
                    if [ -n "$PRIMARY_WID" ]; then
                        _ps=$(yb_window_space "$PRIMARY_WID")
                        [ "$_ps" != "$SPACE_IDX" ] && yabai -m window "$PRIMARY_WID" --space "$SPACE_IDX" 2>/dev/null
                        yb_log "switch: primary wid=$PRIMARY_WID opened"
                    fi
                fi
            fi
            if type "app_${PRIMARY_APP}_focus" &>/dev/null; then
                "app_${PRIMARY_APP}_focus" "$WORK_PATH"
            fi
            yb_debug "switch-primary" "primary=$PRIMARY_APP wid=${PRIMARY_WID:-none}"

            # Ensure secondary on this space
            if [ "$SECONDARY_APP" != "none" ] && [ -z "$SECONDARY_WID" ]; then
                SECONDARY_WID=$("app_${SECONDARY_APP}_find" "$WORK_PATH")
                if [ -n "$SECONDARY_WID" ]; then
                    _ss=$(yb_window_space "$SECONDARY_WID")
                    if [ "$_ss" != "$SPACE_IDX" ]; then
                        yb_log "switch: moving secondary wid=$SECONDARY_WID → space=$SPACE_IDX"
                        yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
                    fi
                else
                    yb_log "switch: secondary not found — opening $SECONDARY_APP"
                    YB_LAST_OPENED_WID=""
                    "app_${SECONDARY_APP}_open" "$WORK_PATH" "$CMD"
                    if [ -n "$YB_LAST_OPENED_WID" ]; then
                        SECONDARY_WID="$YB_LAST_OPENED_WID"
                        _ss=$(yb_window_space "$SECONDARY_WID")
                        [ "$_ss" != "$SPACE_IDX" ] && yabai -m window "$SECONDARY_WID" --space "$SPACE_IDX" 2>/dev/null
                        yb_log "switch: secondary wid=$SECONDARY_WID opened"
                    fi
                fi
            fi
            yb_debug "switch-secondary" "secondary=$SECONDARY_APP wid=${SECONDARY_WID:-none}"

            # Bar
            _BAR_QR=$(sketchybar --query "${LABEL}_badge" 2>&1 | head -1)
            if [ -z "$_BAR_QR" ] || [[ "$_BAR_QR" == *"not found"* ]]; then
                yb_log "switch: creating bar items"
                "$REPO_ROOT/runners/bar.sh" --display "$DISPLAY" --style "$BAR_STYLE" --label "$LABEL" --path "$WORK_PATH" --space "$SPACE_IDX"
            else
                yb_log "switch: rebinding bar to space=$SPACE_IDX"
                for _suffix in badge label path code term folder close; do
                    sketchybar --set "${LABEL}_${_suffix}" associated_space="$SPACE_IDX" 2>/dev/null
                done
                sketchybar --update 2>/dev/null
            fi
            yb_debug "switch-bar" "bar handled for space=$SPACE_IDX"

            # Fix window order: primary left, secondary right
            if [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ]; then
                _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
                _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
                yb_log "switch: order check primary.x=${_PX} secondary.x=${_SX}"
                if [ "${_PX%.*}" -gt "${_SX%.*}" ] 2>/dev/null; then
                    yb_log "switch: swapping — primary was on right"
                    yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
                fi
            fi

            # Write state after repair
            yb_state_set "$LABEL" "$(yb_state_build_json)"
            yb_log "state: written after repair"

            yb_debug "switch-done" "workspace repaired"
            if [ "$YB_DEBUG" -eq 1 ]; then
                echo ""
                "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
            fi
            echo ""
            echo "=== Switched: $LABEL ==="
            exit 0
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

# Get space index — verify it's actually empty via live yabai data
SPACE_IDX=$(yb_visible_space "$DISPLAY")
if [ -n "$SPACE_IDX" ]; then
    _WIN_COUNT=$(yabai -m query --windows --space "$SPACE_IDX" 2>/dev/null | jq '[.[] | select(.["is-sticky"] == false)] | length')
    if [ "$_WIN_COUNT" -gt 0 ]; then
        # Plist was stale — search for an actually-empty space on this display
        yb_log "step1: space=$SPACE_IDX has $_WIN_COUNT windows — searching for empty space"
        _DISP_IDX=$(yabai -m query --displays | jq -r --argjson did "$DISPLAY" '.[] | select(.id == $did) | .index')
        _EMPTY=$(yabai -m query --spaces | jq -r --argjson di "$_DISP_IDX" '
            [.[] | select(.display == $di)] | sort_by(.index) | .[] |
            select((.windows | length) == 0) | .index' 2>/dev/null | head -1)
        if [ -n "$_EMPTY" ]; then
            yb_focus_space "$_EMPTY" "$DISPLAY"
            SPACE_IDX="$_EMPTY"
            yb_log "step1: found empty space=$SPACE_IDX on display"
        else
            yb_log "step1: no empty spaces on display — using space=$SPACE_IDX"
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
# Focus target space first — ensures apps land here, not on a previously-focused space
if [ -n "$SPACE_IDX" ]; then
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    sleep 0.3
fi
yb_log "step2: opening $PRIMARY_APP + $SECONDARY_APP on space=$SPACE_IDX"
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

# Step 5: Layout — focus target space so BSP can tile, then verify order
echo ""

# BSP only tiles on the focused/visible space — refocus after moves
if [ -n "$SPACE_IDX" ]; then
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
    yb_log "step5: focused space=$SPACE_IDX for BSP"
fi

case "$MODE" in
    tile|solo)
        yb_log "step5: layout=$MODE primary=$PRIMARY_WID secondary=$SECONDARY_WID"
        if [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ]; then
            # Poll until BSP tiles (positions become different) — max 3s
            _PXI=0; _SXI=0
            for _bsp_poll in $(seq 1 10); do
                _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
                _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
                _PXI="${_PX%.*}"; _SXI="${_SX%.*}"
                if [ "$_PXI" != "$_SXI" ] 2>/dev/null; then
                    yb_log "step5: BSP settled after poll $_bsp_poll — primary.x=${_PX} secondary.x=${_SX}"
                    break
                fi
                yb_log "step5: BSP pending (poll $_bsp_poll) — primary.x=${_PX} secondary.x=${_SX}"
                sleep 0.3
            done

            if [ "$_PXI" -gt "$_SXI" ] 2>/dev/null; then
                yb_log "step5: swapping — primary was on right"
                yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
            elif [ "$_PXI" -eq "$_SXI" ] 2>/dev/null; then
                # BSP still hasn't tiled — force it by inserting into west position
                yb_log "step5: BSP stuck — forcing layout with warp"
                yabai -m window "$PRIMARY_WID" --warp "$SECONDARY_WID" 2>/dev/null
                sleep 0.5
                # Re-query after warp
                _PX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
                _SX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
                yb_log "step5: after warp primary.x=${_PX} secondary.x=${_SX}"
                if [ "${_PX%.*}" -gt "${_SX%.*}" ] 2>/dev/null; then
                    yb_log "step5: swapping after warp"
                    yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
                fi
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

# Final focus: ensure user is viewing this workspace (focus may have drifted during window moves)
if [ -n "$SPACE_IDX" ]; then
    yb_focus_space "$SPACE_IDX" "$DISPLAY"
fi

# Final order check: zoom/focus may have caused yabai to re-tile
if [ -n "$PRIMARY_WID" ] && [ -n "$SECONDARY_WID" ] && [ "$MODE" = "tile" ]; then
    _FPX=$(yabai -m query --windows --window "$PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
    _FSX=$(yabai -m query --windows --window "$SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
    if [ "${_FPX%.*}" -gt "${_FSX%.*}" ] 2>/dev/null; then
        yb_log "final: order reversed — swapping (primary.x=${_FPX} > secondary.x=${_FSX})"
        yabai -m window "$PRIMARY_WID" --swap "$SECONDARY_WID" 2>/dev/null
    fi
fi

# Write state manifest after successful CREATE
yb_state_set "$LABEL" "$(yb_state_build_json)"
yb_log "state: written after CREATE"

yb_debug "done" "workspace ready"

# Run debug analysis if in debug mode
if [ "$YB_DEBUG" -eq 1 ]; then
    echo ""
    "$REPO_ROOT/runners/analysis.sh" "$YB_DEBUG_SESSION"
fi

echo ""
echo "=== Ready: $LABEL ==="
