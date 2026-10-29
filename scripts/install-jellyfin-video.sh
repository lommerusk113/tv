#!/usr/bin/env bash
# Jellyfin Desktop picture quality: deinterlacing (old TV recordings are interlaced: comb lines on edges) and
# FSRCNNX x2 8-0-4-1, a small neural-network upscaler as an mpv shader (only used when the video is smaller than the
# screen). Sets "video.deinterlace" and "other.other_conf" (extra mpv options, one per line) in the default profile's
# jellyfin-desktop.conf; closes Jellyfin first (it rewrites the file on exit). --remove undoes both.
set -euo pipefail
app=~/.var/app/org.jellyfin.JellyfinDesktop
shader_dir=$app/data/shaders
shader=$shader_dir/FSRCNNX_x2_8-0-4-1.glsl
url=https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl
sha=e800dbc5c1c95185cc82216c597724533ff5f2880179f256eef600f03e8dc2ae
profile=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['defaultProfile'])" \
    "$app/data/jellyfin-desktop/profiles.json")
conf=$app/data/jellyfin-desktop/profiles/$profile/jellyfin-desktop.conf

if [ "${1:-}" != "--remove" ] && ! echo "$sha  $shader" | sha256sum -c --quiet 2>/dev/null; then
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
if mode == "--remove":
    s["video"]["deinterlace"] = False
    s["other"]["other_conf"] = ""
else:
    s["video"]["deinterlace"] = True
    s["other"]["other_conf"] = "\n".join(["glsl-shaders=" + shader, "scale=ewa_lanczossharp", "cscale=ewa_lanczossharp"])
json.dump(c, open(path, "w"), indent=4)
print("deinterlace:", s["video"]["deinterlace"], "| mpv options:", s["other"]["other_conf"].replace("\n", "; ") or "none")
EOF
