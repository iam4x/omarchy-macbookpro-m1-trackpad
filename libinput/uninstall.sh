#!/bin/bash
# Go back to the stock libinput package and remove the IgnorePkg pin.

set -euo pipefail

if [[ -t 0 ]]; then
  SUDO=sudo
else
  SUDO=pkexec
fi

$SUDO bash -c '
  sed -i -E "s/^(IgnorePkg *=.*)\blibinput\b/\1/; s/^IgnorePkg *= *$/#IgnorePkg   =/" /etc/pacman.conf
  pacman -S --noconfirm libinput
'

printf '\033[1;34m==>\033[0m %s\n' "Stock libinput restored. Log out and back in to load it."
