#!/bin/bash
# Bar style: minimal — thin bar, name and path, no blur
# Reserves 34px (24px bar + 10px breathing room below)
# Args: $1=display_index $2=label $3=path $4=prefix $5=--items-only
BAR_HEIGHT=34
if [ "$1" = "--height" ]; then echo "$BAR_HEIGHT"; exit 0; fi
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}
WPATH=${3:-""}
P=${4:-"YB"}
ITEMS_ONLY=${5:-""}

# Global bar config — only on first workspace
if [ "$ITEMS_ONLY" != "--items-only" ]; then
    sketchybar --bar \
        position=top \
        height=24 \
        display=$DISPLAY \
        topmost=on \
        blur_radius=0 \
        color=0x66000000 \
        corner_radius=0 \
        margin=0 \
        padding_left=8 \
        padding_right=8 \
        hidden=off

    sketchybar --default \
        label.color=0xffffffff
fi

# --- Left: workspace name ---
sketchybar --add item ${P}_label left &>/dev/null
sketchybar --set ${P}_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:12.0" \
    label.color=0xffffffff \
    script="" \
    updates=off

# --- Left: workspace path (dimmer) ---
sketchybar --add item ${P}_path left &>/dev/null
sketchybar --set ${P}_path \
    icon="" \
    label="$WPATH" \
    label.font="Hack Nerd Font:Regular:10.0" \
    label.color=0x88ffffff \
    label.padding_left=6 \
    script="" \
    updates=off

sketchybar --update
