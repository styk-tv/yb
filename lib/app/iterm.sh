#!/bin/bash
# FILE: lib/app/iterm.sh
# Application handler: iTerm2 (shared / engine-neutral)
#
# Provides: app_iterm_open, app_iterm_snapshot, app_iterm_find_new
#
# Engine overrides (sourced after this file):
#   iterm.yabai.sh → app_iterm_find, app_iterm_close
#   iterm.jxa.sh   → app_iterm_find, app_iterm_close
#
# Requires: lib/common.sh sourced first

# Open iTerm2 with a new window and run command.
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

    # Launch iTerm if not running (activate only on cold start)
    if ! pgrep -q iTerm 2>/dev/null; then
        open -a iTerm
        sleep 2
    fi

    osascript \
        -e "set cmd to \"$iterm_cmd\"" \
        -e 'tell application "iTerm"' \
        -e '    set newWindow to (create window with default profile)' \
        -e '    delay 0.5' \
        -e '    tell current session of newWindow' \
        -e '        write text cmd' \
        -e '    end tell' \
        -e 'end tell' 2>/dev/null
    yb_log "iTerm2 window created + command: $iterm_cmd"

    # Capture the new window by diffing against pre-snapshot
    YB_LAST_OPENED_WID=""
    sleep 0.3
    YB_LAST_OPENED_WID=$(yb_find_new_wid "iTerm2" "$_pre_wids")
    [ -n "$YB_LAST_OPENED_WID" ] && yb_log "iTerm2 captured wid=$YB_LAST_OPENED_WID (snapshot delta)"
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
