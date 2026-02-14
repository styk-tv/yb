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
