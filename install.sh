#!/bin/bash
# Install the macOS trackpad feel into Omarchy's Hyprland config.
#
# Usage: ./install.sh [--tracking-speed N] [--scroll-speed N] [--units-per-mm N]
#                     [--no-browsers] [--no-foot]
#
# Safe to re-run: it refreshes detected values and keeps your speed tuning.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HYPR_DIR="$HOME/.config/hypr"
MODULE="$HYPR_DIR/macos-trackpad.lua"
SETTINGS="$HYPR_DIR/macos-trackpad-settings.lua"
INPUT_LUA="$HYPR_DIR/input.lua"
TOGGLES_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"
STAMP=$(date +%Y%m%d-%H%M%S)

tracking_speed=""
scroll_speed=""
units_per_mm=""
do_browsers=1
do_foot=1

while [[ $# -gt 0 ]]; do
  case $1 in
  --tracking-speed) tracking_speed=$2; shift 2 ;;
  --scroll-speed) scroll_speed=$2; shift 2 ;;
  --units-per-mm) units_per_mm=$2; shift 2 ;;
  --no-browsers) do_browsers=0; shift ;;
  --no-foot) do_foot=0; shift ;;
  -h | --help) sed -n 2,7p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

command -v hyprctl >/dev/null || { echo "hyprctl not found: run this inside a Hyprland session." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }
[[ -f $INPUT_LUA ]] || { echo "$INPUT_LUA not found: this expects Omarchy's Lua Hyprland config." >&2; exit 1; }

# --- Keep existing tuning -----------------------------------------------------

existing() {
  if [[ -f $SETTINGS ]]; then
    sed -n "s/^  $1 = \([0-9.]*\),.*/\1/p" "$SETTINGS" | head -1
  fi
}
tracking_speed=${tracking_speed:-$(existing tracking_speed)}
tracking_speed=${tracking_speed:-0.875}
scroll_speed=${scroll_speed:-$(existing scroll_speed)}
scroll_speed=${scroll_speed:-1.0}
chromium_scroll_factor=$(existing chromium_scroll_factor)
chromium_scroll_factor=${chromium_scroll_factor:-0.75}

# --- Detect the trackpad ------------------------------------------------------

device=$(hyprctl devices -j | python3 -c '
import json, sys
mice = [m["name"] for m in json.load(sys.stdin)["mice"]]
pads = [n for n in mice if "apple" in n and ("trackpad" in n or "touchpad" in n)]
print(pads[0] if pads else "")')
[[ -n $device ]] || { echo "No Apple trackpad found in 'hyprctl devices'." >&2; exit 1; }
info "Trackpad: $device"

if [[ -z $units_per_mm ]]; then
  event=""
  for name in /sys/class/input/event*/device/name; do
    if grep -qiE 'apple.*(trackpad|touchpad)' "$name"; then
      event=/dev/input/$(basename "$(dirname "$(dirname "$name")")")
      break
    fi
  done

  read_res='
import fcntl, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
print(struct.unpack("6i", fcntl.ioctl(fd, 0x80184540, bytes(24)))[5])'

  if [[ -n $event ]]; then
    if [[ -r $event ]]; then
      units_per_mm=$(python3 -c "$read_res" "$event" 2>/dev/null || true)
    elif [[ -t 0 ]]; then
      info "Reading the trackpad resolution from $event needs root:"
      units_per_mm=$(sudo python3 -c "$read_res" "$event" 2>/dev/null || true)
    else
      units_per_mm=$(pkexec python3 -c "$read_res" "$event" 2>/dev/null || true)
    fi
  fi

  if [[ -z $units_per_mm || $units_per_mm == 0 ]]; then
    warn "Could not read the trackpad resolution; assuming 98 units/mm (pass --units-per-mm to override)."
    units_per_mm=98
  fi
fi
info "Trackpad resolution: $units_per_mm units/mm"

# --- Detect the internal panel ------------------------------------------------

# macOS default "Looks like" width per Apple Silicon panel: the macOS scale is
# native / looks-like. 14"/16" MacBook Pro and 15" Air default to exactly 2x.
read -r panel_width_px panel_width_mm hyprland_scale macos_scale < <(hyprctl monitors -j | python3 -c '
import json, sys
mons = json.load(sys.stdin)
m = next((m for m in mons if m["name"].startswith("eDP")), mons[0])
looks_like = {
    (2560, 1600): 1440,  # 13" M1 MacBook Pro / Air
    (2560, 1664): 1470,  # 13" M2+ Air
}
w = looks_like.get((m["width"], m["height"]), m["width"] / 2)
print(m["width"], m["physicalWidth"], round(m["scale"], 6), round(m["width"] / w, 6))')

model=$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || echo unknown)
info "Machine: $model"
info "Panel: ${panel_width_px}px / ${panel_width_mm}mm wide, Hyprland scale $hyprland_scale, macOS scale $macos_scale"

# --- foot ---------------------------------------------------------------------

foot_multiplier=false
if ((do_foot)) && command -v foot >/dev/null; then
  foot_multiplier=$(awk -F= '
    /^\[/ { section = $0 }
    section == "[scrollback]" && $1 ~ /^[ \t]*multiplier[ \t]*$/ { gsub(/[ \t]/, "", $2); print $2; exit }
  ' "$HOME/.config/foot/foot.ini" 2>/dev/null || true)
  foot_multiplier=${foot_multiplier:-3.0}
  info "foot scrollback multiplier: $foot_multiplier"
fi

# --- Write the module and settings --------------------------------------------

cp "$REPO_DIR/macos-trackpad.lua" "$MODULE"

cat >"$SETTINGS" <<EOF
-- Machine settings for macos-trackpad.lua, written by install.sh on $STAMP.
-- $model
-- Tune tracking_speed / scroll_speed here; re-running install.sh keeps them.
return {
  device = "$device",
  -- macOS notch scale: 0, 0.125, 0.5, 0.6875, 0.875, 1 (default), 1.5, 2, 2.5, 3
  tracking_speed = $tracking_speed,
  scroll_speed = $scroll_speed,
  trackpad_units_per_mm = $units_per_mm,
  panel_width_px = $panel_width_px,
  panel_width_mm = $panel_width_mm,
  macos_scale = $macos_scale,
  hyprland_scale = $hyprland_scale,
  foot_multiplier = $foot_multiplier,
  -- Chromium-based apps only (browsers, web apps): multiplier on top of 1:1.
  chromium_scroll_factor = $chromium_scroll_factor,
$( ((do_browsers)) || echo "  chromium_classes = false,")
}
EOF
info "Wrote $MODULE and $SETTINGS"

if ! grep -q '>>> macos-trackpad >>>' "$INPUT_LUA"; then
  cp "$INPUT_LUA" "$INPUT_LUA.bak.macos-trackpad-$STAMP"
  cat >>"$INPUT_LUA" <<'EOF'

-- >>> macos-trackpad >>>
-- macOS trackpad feel: see macos-trackpad.lua and macos-trackpad-settings.lua.
require("hypr.macos-trackpad")
-- <<< macos-trackpad <<<
EOF
  info "Hooked into $INPUT_LUA (backup: input.lua.bak.macos-trackpad-$STAMP)"
fi

# --- Overrides that load after input.lua --------------------------------------

if [[ -d $TOGGLES_DIR ]]; then
  while IFS= read -r file; do
    mv "$file" "$file.disabled-$STAMP"
    warn "Disabled $file: it overrode the trackpad settings (renamed to .disabled-$STAMP)."
  done < <(grep -lF "\"$device\"" "$TOGGLES_DIR"/*.lua 2>/dev/null || true)
fi

# --- Chromium-based browsers --------------------------------------------------

# Chromium's scroll multiplier is cancelled by a window rule in the module.
# Earlier versions used the WaylandUnscaledTouchpadScrolling flag instead,
# which not every build honors; remove it so the two don't stack.
for flags in "$HOME"/.config/{chromium,brave,chrome,google-chrome,helium,vivaldi,thorium}-flags.conf; do
  [[ -f $flags ]] && grep -q WaylandUnscaledTouchpadScrolling "$flags" || continue
  sed -i -e 's|,WaylandUnscaledTouchpadScrolling:scroll_scaling_factor/1\.0||' \
    -e '/^--enable-features=WaylandUnscaledTouchpadScrolling:scroll_scaling_factor\/1\.0$/d' "$flags"
  info "Removed the old WaylandUnscaledTouchpadScrolling flag from $flags (restart the browser)"
done

# --- Apply --------------------------------------------------------------------

hyprctl reload >/dev/null
sleep 1
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  warn "Hyprland reported config errors:"
  echo "$errors" >&2
  exit 1
fi

info "Done. Tracking speed $tracking_speed, scroll speed $scroll_speed."
info "Tune them in $SETTINGS (Hyprland reloads on save)."
