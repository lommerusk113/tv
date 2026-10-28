#!/usr/bin/env bash
# Opens Jellyfin Desktop's DevTools port (127.0.0.1:9232 only) with a per-user Flatpak override, so
# homescreen/jellyfin_back.py can make Back on Jellyfin's start page return to the TV home screen.
# Takes effect when Jellyfin next starts. Undo: flatpak override --user --unset-env=QTWEBENGINE_REMOTE_DEBUGGING org.jellyfin.JellyfinDesktop
set -euo pipefail
flatpak override --user --env=QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:9232 org.jellyfin.JellyfinDesktop
echo "Jellyfin Desktop debug port enabled (restart Jellyfin)"
