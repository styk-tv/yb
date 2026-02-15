#!/bin/bash
# FILE: lib/app/code.yabai.sh
# Engine: yabai (BSP tiling)
# Overrides: app_code_find, app_code_close

# Find VS Code window by workspace path. Prints yabai window ID or empty.
# $1=work_path $2=space_index (optional, filter by space)
app_code_find() {
    local work_path="$1" hint_space="${2:-}"
    local folder
    folder=$(basename "$work_path")

    if [ -n "$hint_space" ]; then
        yabai -m query --windows | jq -r --arg fn "$folder" --argjson sp "$hint_space" \
            '.[] | select(.app == "Code") | select(.space == $sp) | select(.title == $fn or (.title | endswith(" \u2014 " + $fn))) | .id' | head -1
    else
        yabai -m query --windows | jq -r --arg fn "$folder" \
            '.[] | select(.app == "Code") | select(.title == $fn or (.title | endswith(" \u2014 " + $fn))) | .id' | head -1
    fi
}

# Close VS Code window for a workspace.
# $1=work_path
app_code_close() {
    local work_path="$1"
    local wid
    wid=$(app_code_find "$work_path")
    [ -n "$wid" ] && yabai -m window "$wid" --close 2>/dev/null
}
