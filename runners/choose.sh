#!/bin/bash
# FILE: runners/choose.sh
# Quick-launch workspace picker via choose-gui
# Reads instances, presents fuzzy picker, launches selected workspace
#
# Usage:
#   ./runners/choose.sh              # pick and launch
#   ./runners/choose.sh --display 3  # override display for this launch

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Optional display override
_DISPLAY_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) _DISPLAY_OVERRIDE="$2"; shift 2 ;;
        *)         shift ;;
    esac
done

# Build picker items: "instance_name  path  display:N"
_ITEMS=""
for f in "$REPO_ROOT"/instances/*.yaml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .yaml)
    path=$(yq -r '.path // ""' "$f")
    display=$(yq -r '.display // ""' "$f")
    folder=$(basename "$path")
    [ -z "$path" ] || [ "$path" = "null" ] && continue
    _ITEMS+="${name}  ${folder}  display:${display}"$'\n'
done

# Present picker — Sea Green accent, Black selector background
SELECTED=$(printf '%s' "$_ITEMS" | choose -c 2b9272 -b 020d06 -p "workspace")

[ -z "$SELECTED" ] && exit 0

# Extract instance name (first word)
INSTANCE=$(echo "$SELECTED" | awk '{print $1}')

# Resolve display: override > instance default
if [ -n "$_DISPLAY_OVERRIDE" ]; then
    DISPLAY_ARG="$_DISPLAY_OVERRIDE"
else
    DISPLAY_ARG=$(yq -r '.display // ""' "$REPO_ROOT/instances/${INSTANCE}.yaml")
fi

# Launch
exec "$REPO_ROOT/yb.sh" "$INSTANCE" "$DISPLAY_ARG"
