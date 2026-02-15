#!/bin/bash
# FILE: lib/app/iterm.yabai.sh
# Engine: yabai (BSP tiling)
# Overrides: app_iterm_find, app_iterm_close

# Find iTerm2 window. Optionally filter by yabai space index.
# $1=work_path $2=space_index (optional)
app_iterm_find() {
    local work_path="$1" hint_space="${2:-}"
    local folder
    folder=$(basename "$work_path")

    if [ -n "$hint_space" ]; then
        yabai -m query --windows | jq -r --argjson sp "$hint_space" \
            '.[] | select(.app == "iTerm2") | select(.space == $sp) | .id' | head -1
    else
        # Global search: match by title containing folder name (cwd in prompt)
        yabai -m query --windows | jq -r --arg fn "$folder" \
            '.[] | select(.app == "iTerm2") | select(.title | contains($fn)) | .id' | head -1
    fi
}

# Close iTerm2 window for a workspace.
# $1=work_path $2=space_index (required — close by space ownership)
app_iterm_close() {
    local work_path="$1" hint_space="${2:-}"
    local wid
    if [ -n "$hint_space" ]; then
        wid=$(yabai -m query --windows | jq -r --argjson sp "$hint_space" \
            '.[] | select(.app == "iTerm2") | select(.space == $sp) | .id' | head -1)
    else
        local folder
        folder=$(basename "$work_path")
        wid=$(yabai -m query --windows | jq -r --arg fn "$folder" \
            '.[] | select(.app == "iTerm2") | select(.title | contains($fn)) | .id' | head -1)
    fi
    [ -n "$wid" ] && yabai -m window "$wid" --close 2>/dev/null
}
