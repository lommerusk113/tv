#!/usr/bin/env bash
# Container only: install the home screen into Bigscreen (scripts/install-bigscreen.sh, user dir inside the container)
# and run it as the containment in plasmoidviewer, under Xvfb + openbox. Then use key.sh / shot.sh as usual.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! pgrep -x Xvfb >/dev/null; then
    Xvfb "${DISPLAY:-:99}" -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
    sleep 1
fi
if ! pgrep -x openbox >/dev/null; then
    (openbox >/tmp/openbox.log 2>&1 &)
    sleep 1
fi
[ -f /tmp/dbus.env ] || dbus-launch --sh-syntax > /tmp/dbus.env
. /tmp/dbus.env
scripts/install-bigscreen.sh
pkill -x plasmoidviewer || true
export QT_LOGGING_RULES="qml.debug=true;js.debug=true" QT_FORCE_STDERR_LOGGING=1
# The analog clock is only there because plasmoidviewer requires an applet.
(plasmoidviewer -c org.kde.bigscreen.homescreen -a org.kde.plasma.analogclock -s 1920x1080 >/tmp/homescreen.log 2>&1 &)
for _ in $(seq 1 100); do
    grep -q "New Containment" /tmp/homescreen.log 2>/dev/null && break
    sleep 0.2
done
sleep 2
# Focus the viewer so key.sh input reaches the home screen.
xdotool windowactivate --sync "$(xdotool search --sync --onlyvisible --class plasmoidviewer | tail -1)"
echo "running (log: /tmp/homescreen.log)"
