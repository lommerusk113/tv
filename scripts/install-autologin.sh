#!/usr/bin/env bash
# Automatic login into Plasma Bigscreen at power-on: installs scripts/login/tv-autologin.conf into
# /etc/plasmalogin.conf.d (pkexec asks for the password once). Takes effect at the next boot.
# Undo: sudo rm /etc/plasmalogin.conf.d/tv-autologin.conf
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/login/tv-autologin.conf"
[ -f /usr/share/wayland-sessions/plasma-bigscreen-wayland.desktop ] || { echo "Plasma Bigscreen session not installed" >&2; exit 1; }
pkexec install -m 0644 "$src" /etc/plasmalogin.conf.d/tv-autologin.conf
echo "autologin installed: $(grep -E '^(User|Session)=' /etc/plasmalogin.conf.d/tv-autologin.conf | tr '\n' ' ')"
