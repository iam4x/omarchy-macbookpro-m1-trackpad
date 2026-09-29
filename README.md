# macOS trackpad feel for Omarchy on Apple Silicon MacBooks

Makes the built-in trackpad on an Asahi-powered MacBook running [Omarchy](https://omarchy.org)
move and scroll like it does on macOS — using **Apple's own acceleration curves**,
not a hand-tuned approximation.

- **Pointer:** Apple's parametric acceleration (`HIDAccelCurves`), evaluated exactly like
  macOS's `IOHIDParametricAcceleration`, scaled so the cursor covers the same physical
  distance on screen as it would on macOS.
- **Scrolling:** content tracks your fingers 1:1 at slow speed, with Apple's scroll
  acceleration curve (`HIDScrollAccelCurves`) on faster swipes.
- **Browsers:** Chromium-based browsers (and their web apps) multiply Wayland touchpad
  scroll by 12×; a Hyprland window rule cancels it, so they scroll 1:1 and keep their
  built-in momentum.
- **foot:** touchpad scrolling in the terminal matches 1:1 without changing the mouse wheel.
- **Sliders like macOS:** tune with the same notch values as macOS's *Tracking speed*.

## Install

```bash
git clone https://github.com/iam4x/omarchy-macbookpro-m1-trackpad
cd omarchy-macbookpro-m1-trackpad
./install.sh
```

The installer detects everything machine-specific and asks for your password once, to
read the trackpad's resolution from the kernel.

It installs:

| File | What |
|---|---|
| `~/.config/hypr/macos-trackpad.lua` | The curve logic |
| `~/.config/hypr/macos-trackpad-settings.lua` | Detected values and your tuning |
| `~/.config/hypr/input.lua` | A `require` hook at the end (backed up first) |

Re-running `./install.sh` is safe: it refreshes detected values (for example after
changing your monitor scale) and keeps your speed tuning.

Options: `--tracking-speed N`, `--scroll-speed N`, `--units-per-mm N` (skip the
root read), `--no-browsers`, `--no-foot`.

## Tune

Edit `~/.config/hypr/macos-trackpad-settings.lua`; Hyprland reloads on save.

```lua
-- macOS notch scale: 0, 0.125, 0.5, 0.6875, 0.875, 1 (default), 1.5, 2, 2.5, 3
tracking_speed = 0.875,
scroll_speed = 1.0,
```

Values between notches work too (for example `0.8`): the curves are interpolated the same
way macOS does. `0.875` (one notch below the macOS default) felt closest to macOS on a
14" M1 Pro.

`chromium_scroll_factor` (default `0.75`) is an extra multiplier for Chromium-based apps
only. In theory it should be `1`, but on a 14" M1 Pro at Hyprland scale 4/3, Brave
still ran ahead of the fingers at `1`. Terminals like foot don't use it.

## Uninstall

```bash
./uninstall.sh
```

## How it works

macOS converts finger speed `v` (inches/s) into pointer speed `96·f(v)` points/s, where
`f` is a three-segment curve (polynomial, then tangent line, then square root) whose
gains come from the trackpad driver's `HIDAccelCurves` table, indexed by the tracking
speed slider. This project:

1. Evaluates `f` with Apple's constants and formula (including its `(g·x)ⁿ` quirk).
2. Converts libinput's input speed (trackpad units/ms) to inches/s using the trackpad
   resolution reported by the kernel (`EVIOCGABS`).
3. Converts macOS points to Hyprland logical pixels using macOS's default *Looks like*
   scale for your panel and your Hyprland scale, so physical cursor travel matches.
4. Samples the result into a 64-point libinput custom acceleration profile
   (`accel_profile = "custom …"`), with a matching `scroll_points` curve.

Chromium computes touchpad scroll as `value / 10 * 120`, so the module adds a
`scroll_touchpad = 1/12` window rule for Chromium-based window classes. Electron apps have
the same multiplier: add their classes to `chromium_classes` in the settings file if they
scroll too fast.

The installer also disables leftover files in `~/.local/state/omarchy/toggles/hypr/` that
set this trackpad: they load after `input.lua` and would silently override it.

## Caveats

- Tested on a 14" MacBook Pro (M1 Pro, 2021). Other Apple Silicon MacBooks should work.
  The panel table covers 13" (M1 and M2+), 14", 15" and 16" models.
- Four assumptions: the pointer is exact to Apple's algorithm, but it assumes the built-in
  trackpad uses the same curves as the Magic Trackpad; Apple's 67 Hz standard frame rate;
  a macOS default of tracking speed `1`; and macOS's default display scaling.
- Scroll units can't be converted exactly from macOS, so slow scrolling is set to track
  your fingers 1:1 and only Apple's scroll curve shape is used.
- Momentum after lifting your fingers is per app: Chromium and GTK4 have it; foot doesn't.

## Sources

- [Apple IOHIDFamily](https://github.com/apple-oss-distributions/IOHIDFamily):
  `IOHIDAccelerationAlgorithm.cpp`, `IOHIDAcceleration.cpp`, `IOHIDPointerScrollFilter.cpp`
- [VoodooI2C Info.plist](https://github.com/VoodooI2C/VoodooI2C): Apple's multitouch
  `HIDAccelCurves` and `HIDScrollAccelCurves` tables
- [libinput pointer acceleration](https://wayland.freedesktop.org/libinput/doc/latest/pointer-acceleration.html)
  and `src/filter-custom.c`
- Chromium `ui/ozone/platform/wayland/host/wayland_pointer.cc`: touchpad axis scaling
- [Asahi Linux hid-magicmouse](https://github.com/AsahiLinux/linux): trackpad dimensions
