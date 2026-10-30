#!/usr/bin/env bash
# One command for a new machine: checks what is missing, installs the home screen into Plasma Bigscreen and runs the
# setup (homescreen/setup.py). Safe to run again; asks before anything that needs a password or downloads apps.
# Usage: scripts/install.sh           install / update
#        scripts/install.sh --check   only report what is there and what is missing (changes nothing)
# Needs: Plasma 6.7 with Plasma Bigscreen (Bazzite / Fedora Atomic KDE: see README), flatpak, python3.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
check=false
[ "${1:-}" = --check ] && check=true
venv=${XDG_DATA_HOME:-$HOME/.local/share}/tv-project/venv
flatpaks=(org.jellyfin.JellyfinDesktop rocks.shy.VacuumTube com.moonlight_stream.Moonlight com.google.Chrome)

ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
no() { printf '  \033[33m✗\033[0m %s\n' "$*"; }
ask() { local a; read -r -p "$1 (y/N) " a || true; [[ ${a,,} == y* ]]; }
have_flatpak() { flatpak info "$1" >/dev/null 2>&1; }

echo "== Plasma Bigscreen"
if [ -f /usr/share/wayland-sessions/plasma-bigscreen-wayland.desktop ]; then
    ok "installed ($(rpm -q --qf '%{VERSION}' plasma-bigscreen 2>/dev/null || echo '?'))"
else
    no "missing. On Bazzite / Fedora Atomic: rpm-ostree install plasma-bigscreen plasma-bigscreen-wayland plasma-nano, then reboot"
    $check || exit 1
fi

echo "== Apps (Flatpak)"
missing=()
for app in "${flatpaks[@]}"; do
    if have_flatpak "$app"; then ok "$app"; else no "$app"; missing+=("$app"); fi
done
if ! $check && [ ${#missing[@]} -gt 0 ] && ask "Install the missing apps from Flathub (${missing[*]}) for this user?"; then
    flatpak install --user -y flathub "${missing[@]}"
fi

echo "== Python helpers (venv: websockets for the app helpers, bscpylgtv for LG TVs)"
if [ -x "$venv/bin/python" ] && "$venv/bin/python" -c "import websockets, bscpylgtv" 2>/dev/null; then
    ok "$venv"
elif $check; then
    no "$venv (made by this script)"
else
    [ -x "$venv/bin/python" ] || python3 -m venv "$venv"
    "$venv/bin/pip" install -q --disable-pip-version-check "bscpylgtv==0.5.5" websockets
    ok "$venv"
fi

if $check; then
    echo "== Settings"
    python3 "$repo/homescreen/setup.py" status
    exit 0
fi

echo "== Home screen"
"$repo/scripts/install-bigscreen.sh"
python3 "$repo/homescreen/remote.py" install  # remote buttons that work inside apps (config/remote.json)
# DevTools ports on 127.0.0.1 only: Back on Jellyfin's start page, the on-screen keyboard, YouTube rows
have_flatpak org.jellyfin.JellyfinDesktop && "$repo/scripts/install-jellyfin-debug.sh"
have_flatpak rocks.shy.VacuumTube && "$repo/scripts/install-youtube-debug.sh"

echo "== Optional"
if ask "Strong RemoteG20 remote: remap its buttons (needs your password once)?"; then
    "$repo/scripts/install-remote-keys.sh"
fi
if ask "Start straight into the TV home screen at power-on (automatic login; needs your password once)?"; then
    "$repo/scripts/install-autologin.sh"
fi
if command -v brew >/dev/null && ask "Offline speech-to-text for voice commands (whisper.cpp from Homebrew, ~150 MB)?"; then
    "$repo/scripts/install-voice.sh"
fi

echo "== Services"
python3 "$repo/homescreen/setup.py"

cat <<EOF

Done. Log out and pick "Plasma Bigscreen" at the login screen (or try it now: plasma-bigscreen-swap-session).
Change settings later: python3 homescreen/setup.py, or edit ~/.config/tv-project/*.json (see README).
EOF
