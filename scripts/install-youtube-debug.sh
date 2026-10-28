#!/usr/bin/env bash
# Opens VacuumTube's Chrome DevTools port (127.0.0.1:9231 only) so homescreen/youtube_tv.py can read the account's
# recommendations and watch history through the running app. Takes effect when VacuumTube next starts.
# Undo: remove the line from flags.txt.
set -euo pipefail
flags="$HOME/.var/app/rocks.shy.VacuumTube/config/VacuumTube/flags.txt"
mkdir -p "$(dirname "$flags")"
grep -qx -- "--remote-debugging-port=9231" "$flags" 2>/dev/null || echo "--remote-debugging-port=9231" >> "$flags"
echo "VacuumTube debug port enabled in $flags (restart VacuumTube)"
