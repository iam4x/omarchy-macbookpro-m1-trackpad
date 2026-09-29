-- macOS trackpad feel for Hyprland on Apple Silicon MacBooks (Asahi).
--
-- Uses Apple's own parametric acceleration curves (HIDAccelCurves and
-- HIDScrollAccelCurves from the AppleMultitouchTrackpad personality),
-- evaluated exactly as IOHIDFamily's IOHIDParametricAcceleration does, then
-- converted to libinput custom-profile units so the cursor covers the same
-- physical screen distance as it would on macOS.
--
-- Machine-specific values live in macos-trackpad-settings.lua, written by
-- install.sh. Edit that file to tune; Hyprland reloads on save.
--
-- https://github.com/iam4x/omarchy-macbookpro-m1-trackpad

local ok, settings = pcall(require, "hypr.macos-trackpad-settings")
if not ok then
  settings = {}
end

local macos = {
  -- Trackpad device name as listed by `hyprctl devices`.
  device = "apple-spi-trackpad",
  -- System Settings > Trackpad > Tracking speed notch:
  -- 0, 0.125, 0.5, 0.6875, 0.875, 1 (macOS default), 1.5, 2, 2.5, 3.
  -- Values between notches are interpolated like macOS does.
  tracking_speed = 0.875,
  -- Trackpad scrolling speed, same notch scale.
  scroll_speed = 1.0,
  -- Trackpad resolution reported by the kernel (EVIOCGABS ABS_X), units/mm.
  trackpad_units_per_mm = 98,
  -- Internal panel: native width in px and physical width in mm.
  panel_width_px = 3024,
  panel_width_mm = 302,
  -- macOS default "Looks like" scale for this panel (2 on 14"/16" MBP).
  macos_scale = 2.0,
  -- Hyprland monitor scale in use.
  hyprland_scale = 4 / 3,
  -- foot [scrollback] multiplier, or false to leave foot alone.
  foot_multiplier = 7,
  -- Window classes of Chromium-based apps (browsers, their web apps, Electron
  -- apps). Chromium multiplies Wayland touchpad scroll by 12 (value / 10 * 120),
  -- so these get 1/12 to scroll 1:1. Set to false to leave them alone.
  chromium_classes = "^(chromium|brave-browser|google-chrome.*|vivaldi.*|helium.*|thorium.*|chrome-.*|brave-.*)$",
  -- Extra scroll multiplier for those apps, on top of the 1/12, tuned by feel
  -- against macOS (1 = theoretical 1:1).
  chromium_scroll_factor = 0.75,
}
for k, v in pairs(settings) do
  macos[k] = v
end

-- Apple's curve tables:
-- { HIDAccelIndex, GainLinear, GainParabolic, GainCubic, TangentSpeedLinear, TangentSpeedParabolicRoot }
local pointer_curves = {
  { 0.0, 1.00, 0.00, 0.00, 7.4, 21 },
  { 0.125, 0.99, 0.50, 0.08, 7.3, 20 },
  { 0.5, 0.98, 0.66, 0.10, 7.2, 19 },
  { 0.6875, 0.96, 0.83, 0.12, 7.1, 18 },
  { 0.875, 0.94, 1.00, 0.15, 7.0, 17 },
  { 1.0, 0.92, 1.15, 0.18, 7.0, 16 },
  { 1.5, 0.89, 1.30, 0.21, 7.0, 15 },
  { 2.0, 0.86, 1.45, 0.24, 7.0, 14 },
  { 2.5, 0.83, 1.66, 0.28, 7.0, 13 },
  { 3.0, 1.00, 1.88, 0.36, 7.0, 12 },
}
local scroll_curves = {
  { 0.0, 1.00, 0.0, 0, 6.0, 12 },
  { 0.125, 0.95, 0.6, 0, 6.2, 12 },
  { 0.5, 0.90, 0.9, 0, 6.4, 12 },
  { 0.6875, 0.85, 1.2, 0, 6.6, 12 },
  { 0.875, 0.80, 1.4, 0, 6.8, 12 },
  { 1.0, 0.75, 1.6, 0, 7.0, 12 },
  { 1.5, 0.70, 1.8, 0, 7.2, 12 },
  { 2.0, 0.65, 2.0, 0, 7.4, 12 },
  { 2.5, 0.60, 2.2, 0, 7.6, 12 },
  { 3.0, 0.55, 2.4, 0, 7.8, 12 },
}

-- Interpolate between the two bracketing curves like CreateWithParameters.
local function apple_curve(curves, index)
  local lo, hi = curves[1], curves[1]
  for _, c in ipairs(curves) do
    if index >= c[1] then lo = c end
  end
  for _, c in ipairs(curves) do
    if c[1] > lo[1] then
      hi = c
      break
    end
  end
  local r = (hi[1] > lo[1]) and (index - lo[1]) / (hi[1] - lo[1]) or 0
  local c = {}
  for i = 2, 6 do
    c[i] = lo[i] + (hi[i] - lo[i]) * r
  end
  local lin, par, cub, t1, t2 = c[2], c[3], c[4], c[5], c[6]

  -- Segment 1 polynomial, segment 2 tangent line, segment 3 square root,
  -- matching IOHIDParametricAcceleration::multiplier (including its (g*x)^n).
  local function f1(x) return lin * x + (par * x) ^ 2 + (cub * x) ^ 3 end
  local m0 = lin + 2 * t1 * par ^ 2 + 3 * t1 ^ 2 * cub ^ 3
  local b0 = f1(t1) - m0 * t1
  local y1 = m0 * t2 + b0
  local m1 = 2 * y1 * m0
  local b1 = y1 ^ 2 - m1 * t2

  return function(x)
    if x <= t1 then return f1(x), lin end
    if x <= t2 then return m0 * x + b0, lin end
    return math.sqrt(m1 * x + b1), lin
  end
end

-- libinput custom curves: 64 points max, uniform step in device units/ms.
local STEP, NPOINTS = 0.6, 64
local units_per_inch = macos.trackpad_units_per_mm * 25.4
local points_to_px = macos.macos_scale / macos.hyprland_scale
local px_per_inch_screen = macos.panel_width_px / macos.hyprland_scale / (macos.panel_width_mm / 25.4)

local function libinput_points(fn)
  local pts = {}
  for i = 0, NPOINTS - 1 do
    local speed_in = i * STEP -- device units per ms
    local inch_per_s = speed_in * 1000 / units_per_inch
    pts[#pts + 1] = string.format("%.4f", fn(inch_per_s))
  end
  return string.format("%.2f ", STEP) .. table.concat(pts, " ")
end

-- Pointer: macOS moves 96 * f(v) points/s for a finger speed of v inches/s
-- (kCursorScale 96/67 at the 67 Hz standardized frame rate).
local pointer_fn = apple_curve(pointer_curves, macos.tracking_speed)
local pointer_points = libinput_points(function(v)
  return 96 * pointer_fn(v) * points_to_px / 1000 -- logical px per ms
end)

-- Scroll: at slow speed, content moves exactly as far as the fingers do on
-- screen (direct manipulation), then Apple's scroll curve adds acceleration.
-- 0.743 converts finger in/s to IOHIDScrollAccelerator's standardized speed.
local scroll_fn = apple_curve(scroll_curves, macos.scroll_speed)
local scroll_points = libinput_points(function(v)
  if v == 0 then return 0 end
  local x = 0.743 * v
  local y, lin = scroll_fn(x)
  local gain = y / (lin * x)
  return v * px_per_inch_screen * gain / 1000 -- scroll px per ms
end)

hl.device({
  name = macos.device,
  accel_profile = "custom " .. pointer_points,
  scroll_points = scroll_points,
  -- The curve already produces final pixels; do not scale again.
  scroll_factor = 1.0,
})

-- foot scrolls touchpad pixels / cell height * multiplier, in buffer pixels.
-- 1:1 content tracking needs an effective multiplier equal to the scale.
if macos.chromium_classes then
  o.window(macos.chromium_classes, { scroll_touchpad = macos.chromium_scroll_factor / 12 })
end

if macos.foot_multiplier then
  o.window("foot", { scroll_touchpad = macos.hyprland_scale / macos.foot_multiplier })
end
