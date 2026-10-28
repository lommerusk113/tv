#!/usr/bin/env bash
# Container only: stop the prototype and Xvfb.
pkill -f '^python3 run\.py' || true
pkill -x plasmoidviewer || true
pkill -x openbox || true
pkill -x x11vnc || true
pkill -x Xvfb || true
while pgrep -x Xvfb >/dev/null; do sleep 0.2; done
