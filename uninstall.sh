#!/bin/bash
# Remove the macOS trackpad feel and restore Omarchy's defaults for the trackpad.

set -euo pipefail

HYPR_DIR="$HOME/.config/hypr"
INPUT_LUA="$HYPR_DIR/input.lua"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ -f $INPUT_LUA ]] && grep -q '>>> macos-trackpad >>>' "$INPUT_LUA"; then
  sed -i '/^$/N;/\n-- >>> macos-trackpad >>>/!P;D' "$INPUT_LUA"
  sed -i '/-- >>> macos-trackpad >>>/,/-- <<< macos-trackpad <<</d' "$INPUT_LUA"
  info "Removed the hook from $INPUT_LUA"
fi

rm -f "$HYPR_DIR/macos-trackpad.lua" "$HYPR_DIR/macos-trackpad-settings.lua"
info "Removed macos-trackpad.lua and macos-trackpad-settings.lua"

for flags in "$HOME"/.config/{chromium,brave,chrome,google-chrome,helium,vivaldi,thorium}-flags.conf; do
  [[ -f $flags ]] && grep -q WaylandUnscaledTouchpadScrolling "$flags" || continue
  sed -i -e 's|,WaylandUnscaledTouchpadScrolling:scroll_scaling_factor/1\.0||' \
    -e '/^--enable-features=WaylandUnscaledTouchpadScrolling:scroll_scaling_factor\/1\.0$/d' "$flags"
  info "Removed unscaled touchpad scrolling from $flags (restart the browser)"
done

hyprctl reload >/dev/null 2>&1 || true
info "Done."
