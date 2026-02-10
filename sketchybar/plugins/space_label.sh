#!/bin/bash
LABEL=$(yabai -m query --spaces --space | jq -r '.label')
if [ "$LABEL" = "null" ] || [ -z "$LABEL" ]; then
    LABEL="Desktop $(yabai -m query --spaces --space | jq -r '.index')"
fi
sketchybar --set $NAME label="$LABEL"
