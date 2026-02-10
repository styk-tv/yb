#!/bin/bash
# Bar style: minimal — thin bar, label only, no blur
# Args: $1=display_index $2=space_label
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}

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

sketchybar --add item space_label left &>/dev/null
sketchybar --set space_label \
    icon="" \
    label="$LABEL" \
    label.font="Hack Nerd Font:Bold:12.0"

sketchybar --update
