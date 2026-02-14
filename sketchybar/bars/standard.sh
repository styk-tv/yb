#!/bin/bash
# Bar style: standard — workspace badge, name, path + right-side action icons
# Args: $1=display_index $2=label $3=path
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}
WPATH=${3:-""}
PLUGIN_DIR="$HOME/.config/styk-tv/yb/sketchybar/plugins"

# Generate Nerd Font icon characters (bash 3.2 doesn't support \u escapes)
ICON_CODE=$(python3 -c "print('\ue7a8',end='')")
ICON_TERM=$(python3 -c "print('\uf120',end='')")
ICON_FOLDER=$(python3 -c "print('\uf07c',end='')")
ICON_CLOSE=$(python3 -c "print('\uf00d',end='')")

sketchybar --bar \
    position=top \
    height=32 \
    display=$DISPLAY \
    blur_radius=20 \
    color=0x44000000 \
    corner_radius=10 \
    margin=10 \
    padding_left=10 \
    padding_right=10 \
    hidden=off

sketchybar --default \
    label.color=0xffffffff \
    icon.color=0xffffffff

# ═══════════════════════════════════════════
# LEFT: workspace info
# ═══════════════════════════════════════════

# [YB] badge with background pill
sketchybar --add item yb_badge left &>/dev/null
sketchybar --set yb_badge \
    icon="" \
    label="YB" \
    label.font="Hack Nerd Font:Bold:11.0" \
    label.color=0xff000000 \
    label.padding_left=6 \
    label.padding_right=6 \
    background.drawing=on \
    background.color=0xddffffff \
    background.corner_radius=6 \
    background.height=20 \
    script="" \
    updates=off

# Workspace name
sketchybar --add item space_label left &>/dev/null
sketchybar --set space_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:13.0" \
    label.color=0xffffffff \
    label.padding_left=8 \
    script="" \
    updates=off

# Workspace path (dimmer)
sketchybar --add item space_path left &>/dev/null
sketchybar --set space_path \
    icon="" \
    label="$WPATH" \
    label.font="Hack Nerd Font:Regular:11.0" \
    label.color=0x99ffffff \
    label.padding_left=6 \
    script="" \
    updates=off

# ═══════════════════════════════════════════
# RIGHT: action icons with hover effect
# ═══════════════════════════════════════════

# Close workspace (rightmost)
sketchybar --add item action_close right &>/dev/null
sketchybar --set action_close \
    label="" \
    icon="$ICON_CLOSE" \
    icon.font="Hack Nerd Font:Regular:14.0" \
    icon.color=0xccffffff \
    icon.padding_left=6 \
    icon.padding_right=6 \
    background.drawing=off \
    script="$PLUGIN_DIR/action_close.sh" \
    --subscribe action_close mouse.entered mouse.exited mouse.clicked

# Open folder in Finder
sketchybar --add item action_folder right &>/dev/null
sketchybar --set action_folder \
    label="" \
    icon="$ICON_FOLDER" \
    icon.font="Hack Nerd Font:Regular:14.0" \
    icon.color=0xccffffff \
    icon.padding_left=6 \
    icon.padding_right=6 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe action_folder mouse.entered mouse.exited

# Focus Terminal
sketchybar --add item action_term right &>/dev/null
sketchybar --set action_term \
    label="" \
    icon="$ICON_TERM" \
    icon.font="Hack Nerd Font:Regular:14.0" \
    icon.color=0xccffffff \
    icon.padding_left=6 \
    icon.padding_right=6 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe action_term mouse.entered mouse.exited

# Focus VS Code
sketchybar --add item action_code right &>/dev/null
sketchybar --set action_code \
    label="" \
    icon="$ICON_CODE" \
    icon.font="Hack Nerd Font:Regular:14.0" \
    icon.color=0xccffffff \
    icon.padding_left=6 \
    icon.padding_right=6 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe action_code mouse.entered mouse.exited

sketchybar --update
