#!/usr/bin/env bash
# Jellyfin Desktop picture and sound: deinterlacing (old TV recordings are interlaced: comb lines on edges).
# --upscale also adds FSRCNNX x2 8-0-4-1, a small neural-network upscaler as an mpv shader, + ewa_lanczossharp:
# tried 2026-10-29 and taken out again (no visible gain on the user's SD episodes, playback felt laggier).
# Sound: the TV takes stereo PCM only (its HDMI ELD: LPCM 2 ch, AC-3/DTS 5.1), so 5.1 films are mixed down. mpv's default
# mix (centre -3 dB, then scaled down so nothing clips) put dialogue 7.6 dB under the same sound in a stereo file and
# 3 dB under the music/effects in front (measured with a 5.1 test tone). Centre +3 dB / surrounds -6 dB instead: speech
# +4.3 dB and 3 dB over the front, still without clipping. Only touches the mix-down; stereo files are unchanged.
# Sets "video.deinterlace" and "other.other_conf" (extra mpv options, one per line) in the default profile's
# jellyfin-desktop.conf; closes Jellyfin first (it rewrites the file on exit). --remove undoes everything.
set -euo pipefail
app=~/.var/app/org.jellyfin.JellyfinDesktop
shader_dir=$app/data/shaders
shader=$shader_dir/FSRCNNX_x2_8-0-4-1.glsl
url=https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl
sha=e800dbc5c1c95185cc82216c597724533ff5f2880179f256eef600f03e8dc2ae
profile=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['defaultProfile'])" \
    "$app/data/jellyfin-desktop/profiles.json")
conf=$app/data/jellyfin-desktop/profiles/$profile/jellyfin-desktop.conf

if [ "${1:-}" = "--upscale" ] && ! echo "$sha  $shader" | sha256sum -c --quiet 2>/dev/null; then
    mkdir -p "$shader_dir"
    curl -sSL -m 120 -o "$shader.part" "$url"
    echo "$sha  $shader.part" | sha256sum -c --quiet
    mv "$shader.part" "$shader"
fi

flatpak kill org.jellyfin.JellyfinDesktop 2>/dev/null && sleep 2 || true
python3 - "$conf" "$shader" "${1:-}" <<'EOF'
import json, sys
path, shader, mode = sys.argv[1:]
c = json.load(open(path))
s = c.get("sections", c)
s["video"]["deinterlace"] = mode != "--remove"
options = [] if mode == "--remove" else ["audio-swresample-o=center_mix_level=1.414,surround_mix_level=0.5"]
if mode == "--upscale":
    options += ["glsl-shaders=" + shader, "scale=ewa_lanczossharp", "cscale=ewa_lanczossharp"]
s["other"]["other_conf"] = "\n".join(options)
json.dump(c, open(path, "w"), indent=4)
print("deinterlace:", s["video"]["deinterlace"], "| mpv options:", s["other"]["other_conf"].replace("\n", "; ") or "none")
EOF
