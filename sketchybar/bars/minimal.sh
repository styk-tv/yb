#!/bin/bash
# Bar style: minimal — thin bar, name and path, no blur
# Args: $1=display_index $2=label $3=path
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}
WPATH=${3:-""}

sketchybar --bar \
    position=top \
    height=24 \
    display=$DISPLAY \
    blur_radius=0 \
    color=0x66000000 \
    corner_radius=0 \
    margin=0 \
    padding_left=8 \
    padding_right=8 \
    hidden=off

sketchybar --default \
    label.color=0xffffffff

# --- Left: workspace name ---
sketchybar --add item space_label left &>/dev/null
sketchybar --set space_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:12.0" \
    label.color=0xffffffff \
    script="" \
    updates=off

# --- Left: workspace path (dimmer) ---
sketchybar --add item space_path left &>/dev/null
sketchybar --set space_path \
    icon="" \
    label="$WPATH" \
    label.font="Hack Nerd Font:Regular:10.0" \
    label.color=0x88ffffff \
    label.padding_left=6 \
    script="" \
    updates=off

sketchybar --update
