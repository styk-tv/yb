#!/bin/bash
# Bar style: none — hide sketchybar entirely
BAR_HEIGHT=0
if [ "$1" = "--height" ]; then echo "$BAR_HEIGHT"; exit 0; fi
sketchybar --bar hidden=on 2>/dev/null
