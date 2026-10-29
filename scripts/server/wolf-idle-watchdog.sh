#!/usr/bin/env bash
# Runs on the game server (every minute, wolf-idle-watchdog.timer). Uses no Wolf API: "a stream is active" = the
# NVIDIA video encoder has a session (Wolf encodes with nvh264enc/nvh265enc only while streaming).
#  - no stream for GAME_IDLE_MIN and a game runs in a Wolf Steam container: close the game (Steam stays open)
#  - no stream for STEAM_IDLE_MIN: stop Wolf's Steam containers
# State: /run/wolf-idle-watchdog/last-stream (time of the last minute with a stream). Log: journalctl -t wolf-idle.
set -euo pipefail
GAME_IDLE_MIN=${GAME_IDLE_MIN:-10}
STEAM_IDLE_MIN=${STEAM_IDLE_MIN:-2880}   # 48 h
STATE=/run/wolf-idle-watchdog
mkdir -p "$STATE"
now=$(date +%s)
log() { logger -t wolf-idle "$*"; }

sessions=$(nvidia-smi --query-gpu=encoder.stats.sessionCount --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
if [ "${sessions:-0}" -gt 0 ]; then
    echo "$now" > "$STATE/last-stream"
    exit 0
fi
[ -f "$STATE/last-stream" ] || echo "$now" > "$STATE/last-stream"   # first run (or after a reboot): start counting
idle_min=$(( (now - $(cat "$STATE/last-stream")) / 60 ))

for c in $(docker ps --format '{{.Names}}' | grep -E '^WolfSteam_' || true); do
    if [ "$idle_min" -ge "$STEAM_IDLE_MIN" ]; then
        log "no stream for ${idle_min} min: stopping $c"
        docker stop -t 30 "$c" >/dev/null
        continue
    fi
    # A Steam game runs under Steam's "reaper" with SteamLaunch AppId=<id>; ending it is what Steam's Stop does.
    if [ "$idle_min" -ge "$GAME_IDLE_MIN" ] && docker exec "$c" pgrep -f 'SteamLaunch AppId=' >/dev/null 2>&1; then
        games=$(docker exec "$c" pgrep -af 'SteamLaunch AppId=' | grep -oE 'AppId=[0-9]+' | sort -u | tr '\n' ' ')
        log "no stream for ${idle_min} min: closing ${games}in $c (Steam stays open)"
        docker exec "$c" pkill -TERM -f 'SteamLaunch AppId=' || true
        sleep 20
        docker exec "$c" pkill -KILL -f 'SteamLaunch AppId=' 2>/dev/null || true
    fi
done
