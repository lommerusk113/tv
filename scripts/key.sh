#!/usr/bin/env bash
# Container only: send X11 key names to the home screen, e.g. scripts/key.sh Right Right Down Return Escape
# Prototype (no window manager): focuses the prototype window first.
# Bigscreen test (scripts/bigscreen-start.sh runs openbox): openbox already focused plasmoidviewer, keys go there.
set -euo pipefail
if ! pgrep -x openbox >/dev/null; then
    xdotool windowfocus --sync "$(xdotool search --name "TV Home Screen" | head -1)"
fi
for k in "$@"; do
    xdotool key "$k"
    sleep "${KEY_DELAY:-0.5}"
done
