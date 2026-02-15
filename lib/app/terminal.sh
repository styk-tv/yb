#!/bin/bash
# FILE: lib/app/terminal.sh
# Application handler: Terminal.app (shared / engine-neutral)
#
# Provides: app_terminal_open, app_terminal_snapshot, app_terminal_find_new
#
# Engine overrides (sourced after this file):
#   terminal.yabai.sh → app_terminal_find, app_terminal_close
#   terminal.jxa.sh   → app_terminal_find, app_terminal_close
#
# Requires: lib/common.sh sourced first

# Open Terminal.app with a command.
# $1=work_path $2=cmd (optional)
app_terminal_open() {
    local work_path="$1" cmd="${2:-}"
    yb_log "opening Terminal.app → $work_path"

    # Snapshot existing Terminal windows BEFORE creating the new one
    local _pre_wids
    _pre_wids=$(yb_snapshot_wids "Terminal")

    if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        osascript -e "tell application \"Terminal\" to do script \"cd $work_path && $cmd\""
    else
        osascript -e "tell application \"Terminal\" to do script \"cd $work_path && clear\""
    fi

    # Capture the new window by diffing against pre-snapshot
    YB_LAST_OPENED_WID=""
    sleep 0.3
    YB_LAST_OPENED_WID=$(yb_find_new_wid "Terminal" "$_pre_wids")
    [ -n "$YB_LAST_OPENED_WID" ] && yb_log "Terminal captured wid=$YB_LAST_OPENED_WID (snapshot delta)"
}

# Snapshot existing Terminal windows for delta tracking.
app_terminal_snapshot() {
    yb_snapshot_wids "Terminal"
}

# Find new Terminal window since snapshot.
# $1=snapshot
app_terminal_find_new() {
    yb_find_new_wid "Terminal" "$1"
}
