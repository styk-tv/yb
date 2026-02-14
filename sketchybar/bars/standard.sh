#!/bin/bash
# Bar style: standard — full-width dark bar, workspace badge, name, path + action icons
# Fills the full 52px top padding with no gap. Colors match dark editor/terminal theme.
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
        display=$DISPLAY \
        topmost=on \
        blur_radius=0 \
        color=0xff111111 \
        corner_radius=0 \
        margin=0 \
        padding_left=16 \
        padding_right=16 \
        hidden=off

    sketchybar --default \
        label.color=0xffffffff \
        icon.color=0xffffffff
fi

# ═══════════════════════════════════════════
# LEFT: workspace info
# ═══════════════════════════════════════════

# [YB] badge with green accent pill
sketchybar --add item ${P}_badge left &>/dev/null
sketchybar --set ${P}_badge \
    icon="" \
    label="YB" \
    label.font="Hack Nerd Font:Bold:14.0" \
    label.color=0xff1e1e1e \
    label.padding_left=8 \
    label.padding_right=8 \
    background.drawing=on \
    background.color=0xdd98c379 \
    background.corner_radius=8 \
    background.height=30 \
    script="" \
    updates=off

# Workspace name
sketchybar --add item ${P}_label left &>/dev/null
sketchybar --set ${P}_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:16.0" \
    label.color=0xffffffff \
    label.padding_left=12 \
    script="" \
    updates=off

# Workspace path (dimmer)
sketchybar --add item ${P}_path left &>/dev/null
sketchybar --set ${P}_path \
    icon="" \
    label="$WPATH" \
    label.font="Hack Nerd Font:Regular:13.0" \
    label.color=0x66ffffff \
    label.padding_left=8 \
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
    icon.font="Hack Nerd Font:Regular:18.0" \
    icon.color=0x99ffffff \
    icon.padding_left=10 \
    icon.padding_right=10 \
    background.drawing=off \
    script="$PLUGIN_DIR/action_close.sh" \
    --subscribe ${P}_close mouse.entered mouse.exited mouse.clicked

# Open folder in Finder
sketchybar --add item ${P}_folder right &>/dev/null
sketchybar --set ${P}_folder \
    label="" \
    icon="$ICON_FOLDER" \
    icon.font="Hack Nerd Font:Regular:18.0" \
    icon.color=0xffe5c07b \
    icon.padding_left=10 \
    icon.padding_right=10 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_folder mouse.entered mouse.exited

# Focus Terminal
sketchybar --add item ${P}_term right &>/dev/null
sketchybar --set ${P}_term \
    label="" \
    icon="$ICON_TERM" \
    icon.font="Hack Nerd Font:Regular:18.0" \
    icon.color=0x99ffffff \
    icon.padding_left=10 \
    icon.padding_right=10 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_term mouse.entered mouse.exited

# Focus VS Code
sketchybar --add item ${P}_code right &>/dev/null
sketchybar --set ${P}_code \
    label="" \
    icon="$ICON_CODE" \
    icon.font="Hack Nerd Font:Regular:18.0" \
    icon.color=0x99ffffff \
    icon.padding_left=10 \
    icon.padding_right=10 \
    background.drawing=off \
    script="$PLUGIN_DIR/icon_hover.sh" \
    --subscribe ${P}_code mouse.entered mouse.exited

sketchybar --update
