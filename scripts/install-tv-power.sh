#!/usr/bin/env bash
# Host: installs the TV power control (homescreen/tvpower.py), all in the user's home:
#   - bscpylgtv in the venv ~/.local/share/tv-project/venv
#   - tv-sleep.service (systemd user unit): TV off before the laptop sleeps, on after it wakes
# Usage: scripts/install-tv-power.sh            install / update
#        scripts/install-tv-power.sh --remove   stop and remove the service and the venv
# Then: add "tv" to ~/.config/tv-project/secrets.json, run `python3 homescreen/tvpower.py pair`,
# and `systemctl --user restart tv-sleep` (the watcher exits while there are no "tv" settings).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
venv=${XDG_DATA_HOME:-$HOME/.local/share}/tv-project/venv
unit=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tv-sleep.service

if [ "${1:-}" = --remove ]; then
    systemctl --user disable --now tv-sleep.service 2>/dev/null || true
    rm -f "$unit"
    systemctl --user daemon-reload
    rm -rf "$venv"
    echo "removed"
    exit 0
fi

[ -x "$venv/bin/python" ] || python3 -m venv "$venv"
"$venv/bin/pip" install -q --disable-pip-version-check "bscpylgtv==0.5.5"

mkdir -p "$(dirname "$unit")"
cat > "$unit" <<UNIT
[Unit]
Description=TV off before the laptop sleeps, on after it wakes (tv-project)

[Service]
# The delay lock makes logind wait (max InhibitDelayMaxSec, 5 s) so "off" reaches the TV before the network goes down.
ExecStart=/usr/bin/systemd-inhibit --what=sleep --mode=delay --who=tv-project --why="Turn the TV off" /usr/bin/python3 $repo/homescreen/tvpower.py watch-sleep
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now tv-sleep.service
echo "installed: $venv, $unit"
