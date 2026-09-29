#!/bin/bash
# Build and install libinput with the custom-acceleration restart patch, and pin
# it with IgnorePkg so a system update doesn't silently bring the bug back.
#
# Without the patch, the first pointer movement after the trackpad has been idle
# for over a second is accelerated like a fast flick. Re-run this after
# libinput updates (`pacman -Qu` lists them as ignored) to rebuild on the new
# version.

set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ -t 0 ]]; then
  SUDO=sudo
else
  SUDO=pkexec
fi

# Build the version currently in the repositories, as pkgrel <repo>.1.
read -r version < <(pacman -Si libinput 2>/dev/null | sed -n 's/^Version *: //p' | head -1)
pkgver=${version%-*}
pkgrel=${version##*-}.1
info "Building libinput $pkgver-$pkgrel"

missing=()
for pkg in base-devel git meson; do
  pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
done
if ((${#missing[@]})); then
  info "Installing build dependencies: ${missing[*]}"
  $SUDO pacman -S --needed --noconfirm --asdeps "${missing[@]}"
fi

# The upstream tag is signed by the libinput maintainer.
gpg --quiet --import "$DIR"/keys/pgp/*.asc

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cp "$DIR/PKGBUILD" "$DIR/libinput-custom-accel-restart.patch" "$build/"
sed -i -e "s/^pkgver=.*/pkgver=$pkgver/" -e "s/^pkgrel=.*/pkgrel=$pkgrel/" "$build/PKGBUILD"

(cd "$build" && makepkg --force --cleanbuild --nocheck)

package=$(ls "$build"/libinput-"$pkgver"-"$pkgrel"-*.pkg.tar.*)
info "Installing $(basename "$package")"

# One privileged step: install the package and pin it.
$SUDO bash -c '
  pacman -U --noconfirm "$1"
  if ! grep -qE "^IgnorePkg *=.*\blibinput\b" /etc/pacman.conf; then
    if grep -qE "^IgnorePkg *=" /etc/pacman.conf; then
      sed -i "s/^\(IgnorePkg *=.*\)$/\1 libinput/" /etc/pacman.conf
    else
      sed -i "s/^#IgnorePkg *=.*$/IgnorePkg = libinput/" /etc/pacman.conf
    fi
  fi
' _ "$package"

grep -qE '^IgnorePkg *=.*\blibinput\b' /etc/pacman.conf &&
  info "Pinned libinput in /etc/pacman.conf (IgnorePkg)"

info "Done. Log out and back in so Hyprland loads the patched libinput."
