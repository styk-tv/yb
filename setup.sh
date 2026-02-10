#!/bin/bash
# FILE: setup.sh
# Usage: ./setup.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up Styk-TV/YB Environment..."

# 1. Check Dependencies
if ! command -v brew &> /dev/null; then
    echo "Homebrew is required!"
    exit 1
fi

echo "Installing Dependencies..."
brew install yq jq
brew install koekeishiya/formulae/yabai
brew install koekeishiya/formulae/skhd
brew tap felixkratz/formulae
brew install sketchybar

# 2. Link Configurations
echo "Linking Configs..."

# Yabai
ln -sf "$REPO_DIR/yabai/config.yabairc" "$HOME/.yabairc"

# SketchyBar
mkdir -p "$HOME/.config/sketchybar"
ln -sf "$REPO_DIR/sketchybar/sketchybarrc" "$HOME/.config/sketchybar/sketchybarrc"

# 3. Restart Services
echo "Restarting Services..."
yabai --restart-service
brew services restart sketchybar

echo "Setup Complete."
echo "Add this alias to your ~/.zshrc:"
echo "   alias yb='$REPO_DIR/yb.sh'"
