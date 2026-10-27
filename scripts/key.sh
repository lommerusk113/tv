#!/usr/bin/env bash
# Container only: send X11 key names to the prototype, e.g. scripts/key.sh Right Right Down Return Escape
set -euo pipefail
win=$(xdotool search --name "TV Home Screen" | head -1)
xdotool windowfocus --sync "$win"
for k in "$@"; do
    xdotool key --window "$win" "$k"
    sleep "${KEY_DELAY:-0.5}"
done
