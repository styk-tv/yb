#!/bin/bash
# Bar style: standard — full-width dark bar, workspace badge, name, path + action icons
# Palette: Black #020d06, Sea Green #2b9272, Grays #a8baac/#a2b1a9/#a0ada3
# Args: $1=display_index $2=label $3=path $4=prefix $5=--items-only (skip global bar config)
BAR_HEIGHT=52
if [ "$1" = "--height" ]; then echo "$BAR_HEIGHT"; exit 0; fi
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}
WPATH=${3:-""}
P=${4:-"YB"}
ITEMS_ONLY=${5:-""}
PLUGIN_DIR="$HOME/.config/styk-tv/yb/sketchybar/plugins"

# Generate Nerd Font icon characters (bash 3.2 doesn't support \u escapes)
ICON_CODE=$(python3 -c "print('\ue7a8',end='')")
ICON_TERM=$(python3 -c "print('\uf120',end='')")
ICON_FOLDER=$(python3 -c "print('\uf07c',end='')")
ICON_CLOSE=$(python3 -c "print('\uf00d',end='')")

# Global bar config — only on first workspace (skip if --items-only)
if [ "$ITEMS_ONLY" != "--items-only" ]; then
    sketchybar --bar \
        position=top \
        height=52 \
        display=all \
        topmost=off \
        drawing=on \
        blur_radius=0 \
        color=0x00000000 \
        corner_radius=0 \
        margin=0 \
        padding_left=0 \
        padding_right=0 \
        hidden=off

    sketchybar --default \
        label.color=0xffffffff \
        icon.color=0xffa8baac
fi

# ═══════════════════════════════════════════
# LEFT: workspace info
# ═══════════════════════════════════════════

# [YB] badge with Sea Green accent pill
sketchybar --add item ${P}_badge left &>/dev/null
sketchybar --set ${P}_badge \
    icon="" \
    label="YB" \
    label.font="Hack Nerd Font:Bold:15.0" \
    label.color=0xff020d06 \
    label.padding_left=8 \
    label.padding_right=8 \
    label.y_offset=1 \
    background.drawing=on \
    background.color=0xff2b9272 \
    background.corner_radius=8 \
    background.height=32 \
    script="" \
    updates=off

# Workspace name — bright white
sketchybar --add item ${P}_label left &>/dev/null
sketchybar --set ${P}_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:18.0" \
    label.color=0xffffffff \
    label.padding_left=12 \
    label.y_offset=1 \
    script="" \
    updates=off

# Workspace path — Sea Green tint, dimmed
sketchybar --add item ${P}_path left &>/dev/null
sketchybar --set ${P}_path \
    icon="" \
    label="$WPATH" \
    label.font="Hack Nerd Font:Regular:14.0" \
    label.color=0xaa2b9272 \
    label.padding_left=8 \
    label.y_offset=1 \
    script="" \
    updates=off

# ═══════════════════════════════════════════
# RIGHT: action icons with hover effect
# ═══════════════════════════════════════════

# Close workspace (rightmost)
sketchybar --add item ${P}_close right &>/dev/null
sketchybar --set ${P}_close \
    label="" \
    icon="$ICON_CLOSE" \
    icon.font="Hack Nerd Font:Regular:20.0" \
    icon.color=0xbba0ada3 \
    icon.padding_left=12 \
    icon.padding_right=12 \
    icon.y_offset=1 \
    background.drawing=off \
    script="$PLUGIN_DIR/action_close.sh" \
    --subscribe ${P}_close mouse.entered mouse.exited mouse.clicked

# Open folder in Finder
sketchybar --add item ${P}_folder right &>/dev/null
sketchybar --set ${P}_folder \
    label="" \
    icon="$ICON_FOLDER" \
    icon.font="Hack Nerd Font:Regular:20.0" \
    icon.color=0xbba0ada3 \
    icon.padding_left=12 \
    icon.padding_right=12 \
    icon.y_offset=1 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_folder mouse.entered mouse.exited

# Focus Terminal
sketchybar --add item ${P}_term right &>/dev/null
sketchybar --set ${P}_term \
    label="" \
    icon="$ICON_TERM" \
    icon.font="Hack Nerd Font:Regular:20.0" \
    icon.color=0xcc2b9272 \
    icon.padding_left=12 \
    icon.padding_right=12 \
    icon.y_offset=1 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_term mouse.entered mouse.exited

# Focus VS Code
sketchybar --add item ${P}_code right &>/dev/null
sketchybar --set ${P}_code \
    label="" \
    icon="$ICON_CODE" \
    icon.font="Hack Nerd Font:Regular:20.0" \
    icon.color=0xcc2b9272 \
    icon.padding_left=12 \
    icon.padding_right=12 \
    icon.y_offset=1 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_code mouse.entered mouse.exited

# Dark background bracket — spans all items, visible only on this workspace's space
sketchybar --add bracket ${P}_bg ${P}_badge ${P}_label ${P}_path ${P}_code ${P}_term ${P}_folder ${P}_close &>/dev/null
sketchybar --set ${P}_bg \
    background.drawing=on \
    background.color=0xff020d06 \
    background.height=52 \
    background.corner_radius=0

sketchybar --update
