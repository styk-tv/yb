#!/bin/bash
# Hover effect for right-side icons
# On mouse enter: white square background, dark icon
# On mouse exit: no background, white icon
case "$SENDER" in
    mouse.entered)
        sketchybar --set "$NAME" \
            icon.color=0xff020d06 \
            background.drawing=on \
            background.color=0xff2b9272 \
            background.corner_radius=8 \
            background.height=36
        ;;
    mouse.exited)
        sketchybar --set "$NAME" \
            icon.color=0xcc2b9272 \
            background.drawing=off
        ;;
esac
