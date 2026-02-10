#!/bin/bash
# Bar style: standard — visible bar with workspace label
# Args: $1=display_index $2=space_label
DISPLAY=${1:-1}
LABEL=${2:-"WORKSPACE"}
PLUGIN_DIR="$HOME/.config/styk-tv/yb/sketchybar/plugins"

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

sketchybar --add item space_label left &>/dev/null
sketchybar --set space_label \
    icon="YB" \
    label="$LABEL" \
    script="$PLUGIN_DIR/space_label.sh"

sketchybar --update
