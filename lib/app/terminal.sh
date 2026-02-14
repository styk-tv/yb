#!/bin/bash
# FILE: lib/app/terminal.sh
# Application handler: Terminal.app
#
# Provides: app_terminal_open, app_terminal_find, app_terminal_close,
#           app_terminal_snapshot, app_terminal_find_new
#
# Requires: lib/common.sh sourced first (yb_log, yb_yabai_ok, etc.)

# Open Terminal.app with a command.
# $1=work_path $2=cmd (optional)
app_terminal_open() {
    local work_path="$1" cmd="${2:-}"
    yb_log "opening Terminal.app → $work_path"
    if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
        osascript -e "tell application \"Terminal\" to do script \"cd $work_path && $cmd\""
    else
        osascript -e "tell application \"Terminal\" to do script \"cd $work_path && clear\""
    fi

    # Capture the new window's yabai ID (Terminal is focused after do script)
    YB_LAST_OPENED_WID=""
    sleep 0.3
    YB_LAST_OPENED_WID=$(yabai -m query --windows --window 2>/dev/null | jq -r 'select(.app == "Terminal") | .id // empty')
    [ -n "$YB_LAST_OPENED_WID" ] && yb_log "Terminal captured wid=$YB_LAST_OPENED_WID"
}

# Find Terminal.app window by folder name in title. Prints wid or empty.
# $1=work_path $2=space_index (optional)
app_terminal_find() {
    local work_path="$1" hint_space="${2:-}"
    local folder
    folder=$(basename "$work_path")

    if yb_yabai_ok; then
        if [ -n "$hint_space" ]; then
            yabai -m query --windows | jq -r --arg fn "$folder" --argjson sp "$hint_space" \
                '.[] | select(.app == "Terminal") | select(.space == $sp) | select(.title | contains($fn)) | .id' | head -1
        else
            yabai -m query --windows | jq -r --arg fn "$folder" \
                '.[] | select(.app == "Terminal") | select(.title | contains($fn)) | .id' | head -1
        fi
    else
        local found
        found=$(osascript -l JavaScript -e "var fn = '$folder';" -e '
var se = Application("System Events");
var p = se.processes.byName("Terminal");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        if (p.windows[i].title().indexOf(fn) !== -1) { "found"; break; }
    }
}' 2>/dev/null)
        [ "$found" = "found" ] && echo "jxa:Terminal:$folder"
    fi
}

# Close Terminal.app window by folder name.
# $1=work_path
app_terminal_close() {
    local work_path="$1"
    local folder
    folder=$(basename "$work_path")
    osascript -l JavaScript -e "var fn = '$folder';" -e '
var se = Application("System Events");
var p = se.processes.byName("Terminal");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        if (p.windows[i].title().indexOf(fn) !== -1) {
            Application("Terminal").windows[i].close();
            break;
        }
    }
}' 2>/dev/null
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
