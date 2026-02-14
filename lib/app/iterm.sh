#!/bin/bash
# FILE: lib/app/iterm.sh
# Application handler: iTerm2
#
# Provides: app_iterm_open, app_iterm_find, app_iterm_close,
#           app_iterm_snapshot, app_iterm_find_new
#
# Requires: lib/common.sh sourced first (yb_log, yb_yabai_ok, etc.)

# Open iTerm2 with a new window and run command.
# Uses the proven method: activate → delay → create window → delay → write text
# $1=work_path $2=cmd (optional)
app_iterm_open() {
    local work_path="$1" cmd="${2:-}"
    local iterm_cmd
    if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        iterm_cmd="cd $work_path && $cmd"
    else
        iterm_cmd="cd $work_path && clear"
    fi

    yb_log "opening iTerm2 → $work_path"

    # Snapshot existing iTerm2 windows BEFORE creating the new one
    local _pre_wids
    _pre_wids=$(yb_snapshot_wids "iTerm2")

    osascript \
        -e "set cmd to \"$iterm_cmd\"" \
        -e 'tell application "iTerm"' \
        -e '    activate' \
        -e '    delay 1' \
        -e '    create window with default profile' \
        -e '    delay 1' \
        -e '    tell current session of current window' \
        -e '        write text cmd' \
        -e '    end tell' \
        -e 'end tell' 2>/dev/null
    yb_log "iTerm2 window created + command: $iterm_cmd"

    # Capture the new window by diffing against pre-snapshot (works regardless of focus/space)
    YB_LAST_OPENED_WID=""
    sleep 0.3
    YB_LAST_OPENED_WID=$(yb_find_new_wid "iTerm2" "$_pre_wids")
    if [ -n "$YB_LAST_OPENED_WID" ]; then
        yb_log "iTerm2 captured wid=$YB_LAST_OPENED_WID (snapshot delta)"
    else
        # Fallback: try focused window query
        YB_LAST_OPENED_WID=$(yabai -m query --windows --window 2>/dev/null | jq -r 'select(.app == "iTerm2") | .id // empty')
        [ -n "$YB_LAST_OPENED_WID" ] && yb_log "iTerm2 captured wid=$YB_LAST_OPENED_WID (focused fallback)"
    fi
}

# Find iTerm2 window. Optionally filter by yabai space index.
# $1=work_path $2=space_index (optional)
app_iterm_find() {
    local work_path="$1" hint_space="${2:-}"

    if yb_yabai_ok; then
        if [ -n "$hint_space" ]; then
            yabai -m query --windows | jq -r --argjson sp "$hint_space" \
                '.[] | select(.app == "iTerm2") | select(.space == $sp) | .id' | head -1
        else
            # Global search: match by session.path via AppleScript,
            # then resolve to yabai wid via window position
            local _match_pos
            _match_pos=$(osascript \
                -e "set targetPath to \"$work_path\"" \
                -e 'tell application "iTerm"' \
                -e '    repeat with w in windows' \
                -e '        try' \
                -e '            tell current session of w' \
                -e '                set p to (variable named "session.path")' \
                -e '                if p ends with "/" then set p to text 1 thru -2 of p' \
                -e '                if p is equal to targetPath then' \
                -e '                    set wpos to position of w' \
                -e '                    return ((item 1 of wpos) as text) & "," & ((item 2 of wpos) as text)' \
                -e '                end if' \
                -e '            end tell' \
                -e '        end try' \
                -e '    end repeat' \
                -e '    return ""' \
                -e 'end tell' 2>/dev/null)
            if [ -n "$_match_pos" ]; then
                IFS=',' read -r _mx _my <<< "$_match_pos"
                yabai -m query --windows | jq -r \
                    --argjson mx "${_mx}" --argjson my "${_my}" \
                    '.[] | select(.app == "iTerm2") |
                     select((.frame.x | floor) == ($mx | floor) and (.frame.y | floor) == ($my | floor)) |
                     .id' | head -1
            fi
        fi
    else
        # JXA fallback: match by session.path
        local as_id
        as_id=$(osascript \
            -e "set targetPath to \"$work_path\"" \
            -e 'tell application "iTerm"' \
            -e '    repeat with w in windows' \
            -e '        try' \
            -e '            tell current session of w' \
            -e '                set p to (variable named "session.path")' \
            -e '                if p ends with "/" then set p to text 1 thru -2 of p' \
            -e '                if p is equal to targetPath then' \
            -e '                    return id of w' \
            -e '                end if' \
            -e '            end tell' \
            -e '        end try' \
            -e '    end repeat' \
            -e '    return ""' \
            -e 'end tell' 2>/dev/null)
        [ -n "$as_id" ] && echo "jxa:iTerm2:$as_id"
    fi
}

# Close iTerm2 window for a workspace.
# $1=work_path
app_iterm_close() {
    local work_path="$1"
    osascript \
        -e "set targetPath to \"$work_path\"" \
        -e 'tell application "iTerm"' \
        -e '    repeat with w in windows' \
        -e '        try' \
        -e '            tell current session of w' \
        -e '                set p to (variable named "session.path")' \
        -e '                if p ends with "/" then set p to text 1 thru -2 of p' \
        -e '                if p is equal to targetPath then' \
        -e '                    close w' \
        -e '                    exit repeat' \
        -e '                end if' \
        -e '            end tell' \
        -e '        end try' \
        -e '    end repeat' \
        -e 'end tell' 2>/dev/null
}

# Snapshot existing iTerm2 windows for delta tracking.
app_iterm_snapshot() {
    yb_snapshot_wids "iTerm2"
}

# Find new iTerm2 window since snapshot.
# $1=snapshot
app_iterm_find_new() {
    yb_find_new_wid "iTerm2" "$1"
}
