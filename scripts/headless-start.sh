#!/usr/bin/env bash
# Container only: start Xvfb (1920x1080) and the prototype in the background.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! pgrep -x Xvfb >/dev/null; then
    Xvfb "${DISPLAY:-:99}" -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
    sleep 1
fi
pkill -f '^python3 run\.py' || true
(cd homescreen && python3 run.py >/tmp/homescreen.log 2>&1 &)
for _ in $(seq 1 50); do
    xdotool search --name "TV Home Screen" >/dev/null 2>&1 && break
    sleep 0.2
done
sleep 1
echo "running (log: /tmp/homescreen.log)"
