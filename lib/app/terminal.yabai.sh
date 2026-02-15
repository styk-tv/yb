#!/bin/bash
# FILE: lib/app/terminal.yabai.sh
# Engine: yabai (BSP tiling)
# Overrides: app_terminal_find, app_terminal_close

# Find Terminal.app window by folder name in title via yabai.
# $1=work_path $2=space_index (optional)
app_terminal_find() {
    local work_path="$1" hint_space="${2:-}"
    local folder
    folder=$(basename "$work_path")

    if [ -n "$hint_space" ]; then
        yabai -m query --windows | jq -r --arg fn "$folder" --argjson sp "$hint_space" \
            '.[] | select(.app == "Terminal") | select(.space == $sp) | select(.title | contains($fn)) | .id' | head -1
    else
        yabai -m query --windows | jq -r --arg fn "$folder" \
            '.[] | select(.app == "Terminal") | select(.title | contains($fn)) | .id' | head -1
    fi
}

# Close Terminal.app window for a workspace.
# $1=work_path $2=space_index (required — close by space ownership)
app_terminal_close() {
    local work_path="$1" hint_space="${2:-}"
    local wid
    if [ -n "$hint_space" ]; then
        wid=$(yabai -m query --windows | jq -r --argjson sp "$hint_space" \
            '.[] | select(.app == "Terminal") | select(.space == $sp) | .id' | head -1)
    else
        local folder
        folder=$(basename "$work_path")
        wid=$(yabai -m query --windows | jq -r --arg fn "$folder" \
            '.[] | select(.app == "Terminal") | select(.title | contains($fn)) | .id' | head -1)
    fi
    [ -n "$wid" ] && yabai -m window "$wid" --close 2>/dev/null
}
