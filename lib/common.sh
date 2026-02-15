#!/bin/bash
# FILE: lib/common.sh
# Shared library for YB — generic helpers only.
# Application-specific logic lives in lib/app/*.sh handlers.
# Source this at the top of any script that needs window/display helpers.

YB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YB_ROOT="$(dirname "$YB_LIB_DIR")"

# --- Logging ---

yb_ts() {
    python3 -c "import datetime; print(datetime.datetime.now().strftime('%H:%M:%S.%f')[:12], end='')"
}

yb_log() {
    echo "[$(yb_ts)] $*"
}

# --- Yabai ---

_YB_YABAI=""
yb_yabai_ok() {
    if [ -z "$_YB_YABAI" ]; then
        if yabai -m query --windows >/dev/null 2>&1; then
            _YB_YABAI="yes"
        else
            _YB_YABAI="no"
        fi
    fi
    [ "$_YB_YABAI" = "yes" ]
}

# --- Bar height ---

# Query a bar script for its padding reservation height.
# $1=style name (standard, minimal, none)
yb_bar_height() {
    local style="$1"
    local script="$YB_ROOT/sketchybar/bars/$style.sh"
    if [ "$style" = "none" ] || [ ! -f "$script" ]; then
        echo 0
    else
        "$script" --height
    fi
}

# --- BSP space configuration ---

# Get the visible space index on a display (by CGDirectDisplayID).
# $1=display_id → prints space index
yb_visible_space() {
    local did="$1"
    local disp_idx
    disp_idx=$(yabai -m query --displays | jq -r --argjson did "$did" \
        '.[] | select(.id == $did) | .index')
    [ -z "$disp_idx" ] && return 1
    yabai -m query --spaces | jq -r --argjson di "$disp_idx" \
        '.[] | select(.display == $di and .["is-visible"] == true) | .index'
}

# Configure a yabai space for BSP tiling.
# $1=space_index $2=gap $3=padT $4=padB $5=padL $6=padR $7=bar_height
yb_space_bsp() {
    local space="$1" gap="${2:-0}"
    local padT="${3:-0}" padB="${4:-0}" padL="${5:-0}" padR="${6:-0}"
    local bar_h="${7:-0}"
    local top=$((padT + bar_h))
    yb_log "space-bsp: space=$space gap=$gap pad=${top},$padB,$padL,$padR (bar=$bar_h)"

    # Ensure sketchybar is excluded from tiling
    yabai -m rule --add app="^sketchybar$" manage=off 2>/dev/null

    yabai -m config --space "$space" layout bsp
    yabai -m config --space "$space" top_padding "$top"
    yabai -m config --space "$space" bottom_padding "$padB"
    yabai -m config --space "$space" left_padding "$padL"
    yabai -m config --space "$space" right_padding "$padR"
    yabai -m config --space "$space" window_gap "$gap"

    # Verify
    local actual_top
    actual_top=$(yabai -m config --space "$space" top_padding 2>/dev/null)
    yb_log "space-bsp: verified top_padding=$actual_top"
}

# --- Bar item rebinding (after space creation may renumber indices) ---

# Rebind stale sketchybar items for other workspaces.
# Space creation can shift indices, breaking associated_space bindings.
# $1=current_label (skip self — we're about to bind this one fresh)
yb_rebind_stale_items() {
    local current_label="$1"
    local _inst_dir="$YB_ROOT/instances"
    [ -d "$_inst_dir" ] || return 0

    for _inst_file in "$_inst_dir"/*.yaml; do
        [ -f "$_inst_file" ] || continue
        local _inst_name=$(basename "$_inst_file" .yaml)
        local _inst_label=$(echo "$_inst_name" | tr '[:lower:]' '[:upper:]')
        [ "$_inst_label" = "$current_label" ] && continue

        # Check if this instance has bar items (fast: query badge item)
        local _badge_json=$(sketchybar --query "${_inst_label}_badge" 2>/dev/null)
        if [ -z "$_badge_json" ] || echo "$_badge_json" | grep -q "not found"; then
            continue  # no items for this instance
        fi

        # Get current associated_space from bitmask (2^N = space N)
        local _mask=$(echo "$_badge_json" | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
        local _bound_space=""
        if [ -n "$_mask" ] && [ "$_mask" -gt 0 ] 2>/dev/null; then
            local _b=$_mask _n=0
            while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
            _bound_space="$_n"
        fi

        # Find the instance's Code window via yabai (by title matching folder name)
        local _inst_path=$(yq -r '.path // ""' "$_inst_file" | sed "s|~|$HOME|")
        [ -z "$_inst_path" ] || [ "$_inst_path" = "null" ] && continue
        local _inst_folder=$(basename "$_inst_path")

        local _wid=$(yabai -m query --windows 2>/dev/null | jq -r --arg fn "$_inst_folder" \
            '.[] | select(.app == "Code") | select(.title == $fn or (.title | endswith(" \u2014 " + $fn))) | .id' | head -1)
        [ -z "$_wid" ] && continue

        local _actual_space=$(yabai -m query --windows --window "$_wid" 2>/dev/null | jq -r '.space')

        if [ -n "$_actual_space" ] && [ "$_actual_space" != "$_bound_space" ]; then
            yb_log "rebind: $_inst_label items space=$_bound_space → space=$_actual_space (index shifted)"
            for _sfx in badge label path code term folder close; do
                sketchybar --set "${_inst_label}_${_sfx}" associated_space="$_actual_space" 2>/dev/null
            done
            sketchybar --update 2>/dev/null
        fi
    done
}

# --- Space focus (keyboard navigation — works without scripting addition) ---

# Focus a display by moving mouse to center and clicking.
# $1=display_id (CGDirectDisplayID)
yb_focus_display() {
    local did="$1"
    osascript -l JavaScript \
        -e "var targetDID = $did;" \
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
        var cx = f.origin.x + f.size.width / 2;
        var cy = primaryH - f.origin.y - f.size.height + f.size.height / 2;
        var point = $.CGPointMake(cx, cy);
        var moveEvt = $.CGEventCreateMouseEvent($(), $.kCGEventMouseMoved, point, $.kCGMouseButtonLeft);
        $.CGEventPost($.kCGHIDEventTap, moveEvt);
        delay(0.1);
        var down = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseDown, point, $.kCGMouseButtonLeft);
        var up   = $.CGEventCreateMouseEvent($(), $.kCGEventLeftMouseUp, point, $.kCGMouseButtonLeft);
        $.CGEventPost($.kCGHIDEventTap, down);
        delay(0.05);
        $.CGEventPost($.kCGHIDEventTap, up);
        break;
    }
}' 2>/dev/null
}

# Focus a specific space on a display using keyboard navigation (ctrl+arrows).
# Works without yabai scripting addition.
# $1=target_space_index $2=display_id
yb_focus_space() {
    local target="$1" display_id="$2"

    # Check if already on target
    local visible
    visible=$(yb_visible_space "$display_id")
    [ "$visible" = "$target" ] && return 0

    # Focus the display first (mouse click)
    yb_focus_display "$display_id"
    sleep 0.2

    # Re-check after display focus
    visible=$(yb_visible_space "$display_id")
    [ "$visible" = "$target" ] && return 0

    # Get display's yabai index
    local disp_idx
    disp_idx=$(yabai -m query --displays | jq -r --argjson did "$display_id" \
        '.[] | select(.id == $did) | .index')
    [ -z "$disp_idx" ] && { yb_log "focus-space: display $display_id not found"; return 1; }

    # Get ordered space indices on this display
    local spaces_list
    spaces_list=$(yabai -m query --spaces | jq -r --argjson di "$disp_idx" \
        '[.[] | select(.display == $di)] | sort_by(.index) | .[].index')

    # Find positions of visible and target
    local vis_pos=-1 tgt_pos=-1 pos=0
    for sp in $spaces_list; do
        [ "$sp" = "$visible" ] && vis_pos=$pos
        [ "$sp" = "$target" ] && tgt_pos=$pos
        pos=$((pos + 1))
    done

    if [ "$vis_pos" -lt 0 ] || [ "$tgt_pos" -lt 0 ]; then
        yb_log "focus-space: WARN vis=$visible(pos=$vis_pos) tgt=$target(pos=$tgt_pos) not found"
        return 1
    fi

    local delta=$((tgt_pos - vis_pos))
    yb_log "focus-space: $visible → $target (delta=$delta)"

    if [ "$delta" -gt 0 ]; then
        for i in $(seq 1 $delta); do
            osascript -e 'tell application "System Events" to key code 124 using control down'
            sleep 0.4
        done
    elif [ "$delta" -lt 0 ]; then
        local abs=$(( -delta ))
        for i in $(seq 1 $abs); do
            osascript -e 'tell application "System Events" to key code 123 using control down'
            sleep 0.4
        done
    fi

    return 0
}

# --- Display geometry ---

# Returns X:Y:W:H in CG coordinates (top-left origin) for a CGDirectDisplayID.
yb_display_frame() {
    local did="$1"
    if yb_yabai_ok; then
        yabai -m query --displays | jq -r --argjson did "$did" \
            '.[] | select(.id == $did) | .frame | "\(.x | floor):\(.y | floor):\(.w | floor):\(.h | floor)"'
    else
        osascript -l JavaScript "$YB_LIB_DIR/display_frame.jxa" "$did" 2>/dev/null
    fi
}

# --- Tile geometry ---

# Computes left/right half tile coordinates from display frame + padding + gap.
# Exports: YB_X0 YB_Y0 YB_HW YB_UH YB_X2 YB_W2
yb_tile_geometry() {
    local frame="$1" gap="${2:-0}" padT="${3:-0}" padB="${4:-0}" padL="${5:-0}" padR="${6:-0}"
    IFS=':' read -r _dx _dy _dw _dh <<< "$frame"
    YB_X0=$((_dx + padL))
    YB_Y0=$((_dy + padT))
    local uw=$((_dw - padL - padR))
    YB_UH=$((_dh - padT - padB))
    YB_HW=$(( (uw - gap) / 2 ))
    YB_X2=$((YB_X0 + YB_HW + gap))
    YB_W2=$((uw - YB_HW - gap))
    export YB_X0 YB_Y0 YB_HW YB_UH YB_X2 YB_W2
}

# --- Window ID tracking ---

# Capture all yabai window IDs for an app. Returns space-separated sorted list.
yb_snapshot_wids() {
    local app="$1"
    yabai -m query --windows 2>/dev/null | jq -r --arg app "$app" \
        '.[] | select(.app == $app) | .id' | sort -n | tr '\n' ' '
}

# Find new window ID by comparing current windows to a snapshot.
# $1=app $2=snapshot (space-separated IDs from yb_snapshot_wids)
yb_find_new_wid() {
    local app="$1" snapshot="$2"
    local current
    current=$(yb_snapshot_wids "$app")
    comm -23 <(echo "$current" | tr ' ' '\n' | grep -v '^$' | sort -n) \
             <(echo "$snapshot" | tr ' ' '\n' | grep -v '^$' | sort -n) | head -1
}

# --- Window space ---

# Get the yabai space index for a window.
# $1=wid → prints space index
yb_window_space() {
    local wid="$1"
    yabai -m query --windows --window "$wid" 2>/dev/null | jq -r '.space'
}

# --- Window positioning ---

# Position a window at x,y with size w,h.
# $1=window_id (yabai ID or "jxa:App:match"), $2=x, $3=y, $4=w, $5=h
yb_position() {
    local wid="$1" x="$2" y="$3" w="$4" h="$5"

    if [[ "$wid" == jxa:* ]]; then
        # JXA fallback: parse "jxa:App:match"
        local app match
        IFS=':' read -r _ app match <<< "$wid"
        osascript -l JavaScript \
            -e "var app = '$app', match = '$match', x = $x, y = $y, w = $w, h = $h;" -e '
var se = Application("System Events");
var p = se.processes.byName(app);
if (p.exists()) {
    var dashSep = " \u2014 ";
    for (var i = 0; i < p.windows.length; i++) {
        var t = p.windows[i].title();
        var hit = (app === "Code") ? (t === match || t.endsWith(dashSep + match)) : (t.indexOf(match) !== -1);
        if (hit) {
            p.windows[i].position = [x, y];
            p.windows[i].size = [w, h];
            break;
        }
    }
}' 2>/dev/null
    else
        # Yabai: ensure floating, then move + resize
        local is_floating
        is_floating=$(yabai -m query --windows --window "$wid" 2>/dev/null | jq -r '.["is-floating"]')
        [ "$is_floating" != "true" ] && yabai -m window "$wid" --toggle float 2>/dev/null
        yabai -m window "$wid" --move "abs:${x}:${y}" 2>/dev/null
        yabai -m window "$wid" --resize "abs:${w}:${h}" 2>/dev/null
    fi
}

# --- Layout functions (generic — take window IDs, no app knowledge) ---

# Tile two windows (primary left, secondary right) on a display.
# $1=display_id $2=gap $3=padT $4=padB $5=padL $6=padR $7=primary_wid $8=secondary_wid
yb_layout_tile() {
    local display_id="$1" gap="${2:-0}"
    local padT="${3:-0}" padB="${4:-0}" padL="${5:-0}" padR="${6:-0}"
    local primary_wid="${7:-}" secondary_wid="${8:-}"

    yb_log "tile: display=$display_id gap=$gap pad=$padT,$padB,$padL,$padR"

    local frame
    frame=$(yb_display_frame "$display_id")
    if [ -z "$frame" ]; then
        yb_log "tile: ERROR display $display_id not found"
        return 1
    fi
    yb_tile_geometry "$frame" "$gap" "$padT" "$padB" "$padL" "$padR"
    yb_log "tile: left=${YB_X0},${YB_Y0} ${YB_HW}x${YB_UH}  right=${YB_X2},${YB_Y0} ${YB_W2}x${YB_UH}"

    if [ -n "$primary_wid" ]; then
        yb_position "$primary_wid" "$YB_X0" "$YB_Y0" "$YB_HW" "$YB_UH"
        yb_log "tile: primary wid=$primary_wid → ${YB_X0},${YB_Y0} ${YB_HW}x${YB_UH}"
    else
        yb_log "tile: primary (no window)"
    fi

    if [ -n "$secondary_wid" ]; then
        yb_position "$secondary_wid" "$YB_X2" "$YB_Y0" "$YB_W2" "$YB_UH"
        yb_log "tile: secondary wid=$secondary_wid → ${YB_X2},${YB_Y0} ${YB_W2}x${YB_UH}"
    else
        yb_log "tile: secondary (no window)"
    fi
}

# Position a single window fullscreen on a display.
# $1=display_id $2=padT $3=padB $4=padL $5=padR $6=primary_wid
yb_layout_solo() {
    local display_id="$1"
    local padT="${2:-0}" padB="${3:-0}" padL="${4:-0}" padR="${5:-0}"
    local primary_wid="${6:-}"

    yb_log "solo: display=$display_id pad=$padT,$padB,$padL,$padR"

    local frame
    frame=$(yb_display_frame "$display_id")
    if [ -z "$frame" ]; then
        yb_log "solo: ERROR display $display_id not found"
        return 1
    fi

    local dx dy dw dh
    IFS=':' read -r dx dy dw dh <<< "$frame"
    local x0=$((dx + padL)) y0=$((dy + padT))
    local uw=$((dw - padL - padR)) uh=$((dh - padT - padB))

    yb_log "solo: fullscreen=${x0},${y0} ${uw}x${uh}"

    if [ -n "$primary_wid" ]; then
        yb_position "$primary_wid" "$x0" "$y0" "$uw" "$uh"
        yb_log "solo: primary wid=$primary_wid → ${x0},${y0} ${uw}x${uh}"
    else
        yb_log "solo: primary (no window)"
    fi
}
