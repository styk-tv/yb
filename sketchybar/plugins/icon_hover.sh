#!/bin/bash
# Hover effect for right-side icons
# On mouse enter: white square background, dark icon
# On mouse exit: no background, white icon
case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff1e1e1e \
            background.drawing=on \
            background.color=0xdd98c379 \
            background.corner_radius=8 \
            background.height=36
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0x99ffffff \
            background.drawing=off
        ;;
esac
