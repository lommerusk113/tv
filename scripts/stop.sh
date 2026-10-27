#!/usr/bin/env bash
# Container only: stop the prototype and Xvfb.
pkill -f '^python3 run\.py' || true
pkill -x Xvfb || true
