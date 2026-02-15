#!/bin/bash
# FILE: lib/state.sh
# State manifest — persistent workspace ownership tracking.
# Sourced from lib/common.sh. Requires: jq, YB_ROOT.

YB_STATE_DIR="$YB_ROOT/state"
YB_STATE_FILE="$YB_STATE_DIR/manifest.json"

# Update sketchybar bar display to cover only displays with active workspaces.
# 0 workspaces → hidden, 1 display → display=N, 2+ displays → display=all.
# Called automatically by yb_state_set, yb_state_remove, yb_state_clear.
yb_bar_update_display() {
    pgrep -q sketchybar 2>/dev/null || return 0
    local _display
    _display=$(python3 -c "
import json, subprocess, os
sf = '$YB_STATE_FILE'
result = 'all'
if not os.path.exists(sf):
    result = 'hidden'
else:
    try:
        with open(sf) as f:
            m = json.load(f)
        ws = m.get('workspaces', {})
        if not ws:
            result = 'hidden'
        else:
            sraw = subprocess.check_output(['yabai', '-m', 'query', '--spaces'], stderr=subprocess.DEVNULL)
            spaces = json.loads(sraw)
            s2d = {s['index']: s['display'] for s in spaces}
            displays = set()
            for w in ws.values():
                si = w.get('space_idx')
                if si in s2d:
                    displays.add(s2d[si])
            if not displays:
                result = 'hidden'
            elif len(displays) == 1:
                result = str(list(displays)[0])
            else:
                result = 'all'
    except Exception:
        result = 'all'
print(result)
" 2>/dev/null)
    if [ "$_display" = "hidden" ]; then
        sketchybar --bar drawing=off 2>/dev/null
    else
        sketchybar --bar drawing=on display="$_display" 2>/dev/null
    fi
}

# Read full manifest. Returns {} if missing.
yb_state_read() {
    if [ -f "$YB_STATE_FILE" ]; then
        cat "$YB_STATE_FILE"
    else
        echo '{}'
    fi
}

# Read one workspace entry. $1=LABEL → prints JSON object or empty
yb_state_get() {
    local label="$1"
    if [ -f "$YB_STATE_FILE" ]; then
        jq -r --arg l "$label" '.workspaces[$l] // empty' "$YB_STATE_FILE" 2>/dev/null
    fi
}

# Write/update one workspace entry. $1=LABEL $2=json
# Atomic: write tmp, mv.
yb_state_set() {
    local label="$1" json="$2"
    mkdir -p "$YB_STATE_DIR"
    local current
    current=$(yb_state_read)
    local tmp="$YB_STATE_FILE.tmp.$$"
    echo "$current" | jq --arg l "$label" --argjson v "$json" \
        '.version = 1 | .workspaces[$l] = $v' > "$tmp" && mv "$tmp" "$YB_STATE_FILE"
    yb_bar_update_display
}

# Remove one workspace entry. $1=LABEL
yb_state_remove() {
    local label="$1"
    [ -f "$YB_STATE_FILE" ] || return 0
    local tmp="$YB_STATE_FILE.tmp.$$"
    jq --arg l "$label" 'del(.workspaces[$l])' "$YB_STATE_FILE" > "$tmp" && mv "$tmp" "$YB_STATE_FILE"
    yb_bar_update_display
}

# Delete manifest (used by yb down).
yb_state_clear() {
    rm -f "$YB_STATE_FILE"
    yb_bar_update_display
}

# Validate a workspace entry against live state.
# $1=LABEL
# Sets _SV_RESULT to one of: intact, no_state, space_gone, primary_dead,
#   secondary_dead, primary_drifted, secondary_drifted, order_wrong, bar_missing, bar_stale
# Also sets: _SV_SPACE_IDX, _SV_PRIMARY_WID, _SV_SECONDARY_WID (for caller use)
# IMPORTANT: Call directly (not in a subshell) so variables propagate to caller.
yb_state_validate() {
    local label="$1"
    local entry
    entry=$(yb_state_get "$label")

    # Reset exports
    _SV_RESULT=""
    _SV_SPACE_IDX=""
    _SV_PRIMARY_WID=""
    _SV_SECONDARY_WID=""

    # 1. No entry → no_state
    if [ -z "$entry" ]; then
        _SV_RESULT="no_state"
        return 0
    fi

    local s_uuid s_idx s_pwid s_papp s_swid s_sapp s_mode
    s_uuid=$(echo "$entry" | jq -r '.space_uuid // ""')
    s_idx=$(echo "$entry" | jq -r '.space_idx // 0')
    s_pwid=$(echo "$entry" | jq -r '.primary.wid // 0')
    s_papp=$(echo "$entry" | jq -r '.primary.app // ""')
    s_swid=$(echo "$entry" | jq -r '.secondary.wid // 0')
    s_sapp=$(echo "$entry" | jq -r '.secondary.app // ""')
    s_mode=$(echo "$entry" | jq -r '.mode // "tile"')

    # 2. Resolve space_uuid → current index
    local current_idx=""
    if [ -n "$s_uuid" ] && [ "$s_uuid" != "null" ]; then
        current_idx=$(yabai -m query --spaces 2>/dev/null | jq -r --arg uuid "$s_uuid" \
            '.[] | select(.uuid == $uuid) | .index' 2>/dev/null)
    fi
    if [ -z "$current_idx" ]; then
        _SV_RESULT="space_gone"
        return 0
    fi

    # Update stored index if it changed (space renumbering)
    if [ "$current_idx" != "$s_idx" ]; then
        yb_log "state: space index shifted $s_idx → $current_idx (uuid=$s_uuid)"
        local tmp_entry
        tmp_entry=$(echo "$entry" | jq --argjson si "$current_idx" '.space_idx = $si')
        yb_state_set "$label" "$tmp_entry"
        s_idx="$current_idx"
    fi

    # Set for caller
    _SV_SPACE_IDX="$s_idx"

    # 3. Validate primary WID
    if [ "$s_pwid" -gt 0 ] 2>/dev/null; then
        local p_info
        p_info=$(yabai -m query --windows --window "$s_pwid" 2>/dev/null)
        if [ -z "$p_info" ] || [ "$p_info" = "null" ]; then
            _SV_PRIMARY_WID=""
            _SV_SECONDARY_WID="$s_swid"
            _SV_RESULT="primary_dead"
            return 0
        fi
        local p_app p_space
        p_app=$(echo "$p_info" | jq -r '.app // ""')
        p_space=$(echo "$p_info" | jq -r '.space // 0')
        if [ "$p_space" != "$s_idx" ]; then
            _SV_PRIMARY_WID="$s_pwid"
            _SV_SECONDARY_WID="$s_swid"
            _SV_RESULT="primary_drifted"
            return 0
        fi
        _SV_PRIMARY_WID="$s_pwid"
    else
        _SV_PRIMARY_WID=""
    fi

    # 4. Validate secondary WID (if tile mode)
    _SV_SECONDARY_WID=""
    if [ "$s_mode" = "tile" ] && [ "$s_swid" -gt 0 ] 2>/dev/null; then
        local s_info
        s_info=$(yabai -m query --windows --window "$s_swid" 2>/dev/null)
        if [ -z "$s_info" ] || [ "$s_info" = "null" ]; then
            _SV_SECONDARY_WID=""
            _SV_RESULT="secondary_dead"
            return 0
        fi
        local sec_space
        sec_space=$(echo "$s_info" | jq -r '.space // 0')
        if [ "$sec_space" != "$s_idx" ]; then
            _SV_SECONDARY_WID="$s_swid"
            _SV_RESULT="secondary_drifted"
            return 0
        fi
        _SV_SECONDARY_WID="$s_swid"
    fi

    # 5. Check order (tile): primary.frame.x < secondary.frame.x
    if [ "$s_mode" = "tile" ] && [ -n "$_SV_PRIMARY_WID" ] && [ -n "$_SV_SECONDARY_WID" ]; then
        local px sx
        px=$(yabai -m query --windows --window "$_SV_PRIMARY_WID" 2>/dev/null | jq -r '.frame.x // 99999')
        sx=$(yabai -m query --windows --window "$_SV_SECONDARY_WID" 2>/dev/null | jq -r '.frame.x // 0')
        if [ "${px%.*}" -gt "${sx%.*}" ] 2>/dev/null; then
            _SV_RESULT="order_wrong"
            return 0
        fi
    fi

    # 6. Check bar
    local bar_qr
    bar_qr=$(sketchybar --query "${label}_badge" 2>&1 | head -1)
    if [ -z "$bar_qr" ] || [[ "$bar_qr" == *"not found"* ]]; then
        _SV_RESULT="bar_missing"
        return 0
    fi
    # Check bar bound to correct space
    local bar_mask bar_space=""
    bar_mask=$(echo "$bar_qr" | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
    if [ -n "$bar_mask" ] && [ "$bar_mask" -gt 0 ] 2>/dev/null; then
        local _b=$bar_mask _n=0
        while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
        bar_space="$_n"
    fi
    if [ -n "$bar_space" ] && [ "$bar_space" != "$s_idx" ]; then
        _SV_RESULT="bar_stale"
        return 0
    fi

    # 7. All pass
    _SV_RESULT="intact"
    return 0
}

# Build state JSON from current variables (helper for CREATE/REPAIR write).
# Uses shell vars: TARGET, DISPLAY, SPACE_IDX, PRIMARY_APP_NAME (or PRIMARY_APP),
#   PRIMARY_WID, SECONDARY_APP_NAME (or SECONDARY_APP), SECONDARY_WID, MODE, BAR_STYLE, WORK_PATH
yb_state_build_json() {
    local space_uuid
    space_uuid=$(yabai -m query --spaces 2>/dev/null | jq -r --argjson si "${SPACE_IDX:-0}" \
        '.[] | select(.index == $si) | .uuid' 2>/dev/null)

    local _papp="${PRIMARY_APP_NAME:-${PRIMARY_APP:-}}"
    local _sapp="${SECONDARY_APP_NAME:-${SECONDARY_APP:-}}"

    jq -n \
        --arg inst "${TARGET:-}" \
        --argjson disp "${DISPLAY:-0}" \
        --argjson si "${SPACE_IDX:-0}" \
        --arg uuid "${space_uuid:-}" \
        --arg papp "$_papp" \
        --argjson pwid "${PRIMARY_WID:-0}" \
        --arg sapp "$_sapp" \
        --argjson swid "${SECONDARY_WID:-0}" \
        --arg mode "${MODE:-tile}" \
        --arg bar "${BAR_STYLE:-none}" \
        --arg wp "${WORK_PATH:-}" \
        '{instance:$inst, display:$disp, space_idx:$si, space_uuid:$uuid,
          primary:{app:$papp,wid:$pwid}, secondary:{app:$sapp,wid:$swid},
          mode:$mode, bar_style:$bar, work_path:$wp}'
}
