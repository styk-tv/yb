#!/bin/bash
# FILE: lib/app/code.sh
# Application handler: Visual Studio Code (shared / engine-neutral)
#
# Provides: app_code_open, app_code_is_open, app_code_focus,
#           app_code_post_setup, app_code_snapshot, app_code_find_new
#
# Engine overrides (sourced after this file):
#   code.yabai.sh → app_code_find, app_code_close
#   code.jxa.sh   → app_code_find, app_code_close, app_code_locate, app_code_tile_left
#
# Requires: lib/common.sh sourced first

# Open VS Code with a workspace path.
# $1=work_path
app_code_open() {
    local work_path="$1"
    yb_log "opening VS Code → $work_path"
    open -na "Visual Studio Code" --args "$work_path"
}

# Check if VS Code has this workspace open. Returns 0 if open, 1 if not.
# Delegates to app_code_find (defined by engine override).
# $1=work_path
app_code_is_open() {
    local work_path="$1"
    local wid
    wid=$(app_code_find "$work_path")
    [ -n "$wid" ]
}

# Focus/activate an existing VS Code window.
# $1=work_path
app_code_focus() {
    local work_path="$1"
    open -a "Visual Studio Code" "$work_path"
}

# Post-setup: apply zoom level.
# $1=zoom_level (0 = no zoom)
app_code_post_setup() {
    local zoom="${1:-0}"
    if [ "$zoom" != "null" ] && [ "$zoom" -gt 0 ] 2>/dev/null; then
        yb_log "zoom +$zoom"
        sleep 0.5
        osascript -e "tell application \"System Events\" to tell process \"Code\"" \
                  -e "repeat $zoom times" \
                  -e "keystroke \"=\" using {command down}" \
                  -e "end repeat" \
                  -e "end tell"
    fi
}

# Snapshot existing VS Code windows for delta tracking.
app_code_snapshot() {
    yb_snapshot_wids "Code"
}

# Find new VS Code window since snapshot.
# $1=snapshot
app_code_find_new() {
    yb_find_new_wid "Code" "$1"
}
