#!/bin/bash
# Hover effect for right-side icons
# On mouse enter: white square background, dark icon
# On mouse exit: no background, white icon
case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff000000 \
            background.drawing=on \
            background.color=0xddffffff \
            background.corner_radius=6 \
            background.height=22
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0xccffffff \
            background.drawing=off
        ;;
esac
