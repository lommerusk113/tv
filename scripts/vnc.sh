#!/usr/bin/env bash
# Container only: share the virtual screen over VNC, so you can watch and drive it with a real keyboard.
# Run the container with -p 127.0.0.1:5901:5900, start headless-start.sh or bigscreen-start.sh, then this,
# and open vnc://localhost:5901 (password: tv) in macOS Screen Sharing.
set -euo pipefail
mkdir -p ~/.vnc
x11vnc -storepasswd tv ~/.vnc/passwd >/dev/null
x11vnc -display "${DISPLAY:-:99}" -rfbauth ~/.vnc/passwd -forever -shared -bg -o /tmp/x11vnc.log >/dev/null
echo "VNC on port 5900 in the container (log: /tmp/x11vnc.log)"
