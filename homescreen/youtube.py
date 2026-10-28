#!/usr/bin/env python3
"""YouTube "New from your channels" row for the home screen. Standard library only, no API key.

  python3 youtube.py   writes the youtubeChannels key (newest videos of the channels in config/youtube.json, newest
                       first) into ~/.cache/tv-project/content.json; OK on a tile plays it in VacuumTube

YouTube switched off its channel RSS feeds, so this reads the channel's /videos page (the ytInitialData JSON in it).
That can break when YouTube changes the page; the official alternative is the YouTube Data API (needs a key).
Results are cached in ~/.cache/tv-project/youtube-channels.json for MAX_AGE; thumbnails in ~/.cache/tv-project/images/.
When a channel cannot be read, its videos from the last run are kept.
"""
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

from trakt import CACHE, colors, download, update_content

HERE = Path(__file__).resolve().parent
YOUTUBE = os.environ.get("YOUTUBE_URL", "https://www.youtube.com")
THUMBNAILS = os.environ.get("YOUTUBE_THUMBNAILS", "https://i.ytimg.com")
RAW = CACHE / "youtube-channels.json"
MAX_AGE = 30 * 60
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
    "Accept-Language": "en-US,en",
    "Cookie": "CONSENT=YES+1; SOCS=CAI",  # skip the EU consent page
}
UNITS = {"second": 1, "minute": 60, "hour": 3600, "day": 86400, "week": 7 * 86400, "month": 30 * 86400,
         "year": 365 * 86400}


def age_seconds(label):
    """Seconds from an accessibility label like "9 hours ago" or "Streamed 2 days ago"; None if there is none."""
    m = re.search(r"(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago", label or "")
    return int(m.group(1)) * UNITS[m.group(2)] if m else None


def find(obj, key):
    """Every value stored under key anywhere in a parsed JSON tree, in document order."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key:
                yield v
            yield from find(v, key)
    elif isinstance(obj, list):
        for v in obj:
            yield from find(v, key)


def parse_videos(html):
    """[{id, title, age (seconds), duration, views}] from a channel /videos page."""
    m = re.search(r"var ytInitialData\s*=\s*(\{.*?\});\s*</script>", html, re.S)
    if not m:
        return []
    videos = []
    for lockup in find(json.loads(m.group(1)), "lockupViewModel"):
        if lockup.get("contentType") != "LOCKUP_CONTENT_TYPE_VIDEO" or not lockup.get("contentId"):
            continue
        meta = lockup.get("metadata", {}).get("lockupMetadataViewModel", {})
        parts = [p for row in find(meta, "metadataRows") for r in row for p in r.get("metadataParts", [])]
        age = next((a for a in (age_seconds(p.get("accessibilityLabel")) for p in parts) if a is not None), None)
        if age is None:  # upcoming or live: nothing to watch yet
            continue
        badges = [b.get("text") for b in find(lockup.get("contentImage", {}), "thumbnailBadgeViewModel")]
        videos.append({
            "id": lockup["contentId"],
            "title": meta.get("title", {}).get("content", ""),
            "age": age,
            "duration": next((b for b in badges if b and re.fullmatch(r"\d+(:\d\d)+", b)), None),
            "views": next((p["text"]["content"] for p in parts if "view" in (p.get("accessibilityLabel") or "")), None),
        })
    return videos


def fetch_channel(channel_id):
    req = urllib.request.Request("%s/channel/%s/videos" % (YOUTUBE, channel_id), headers=HEADERS)
    with urllib.request.urlopen(req, timeout=20) as res:
        return parse_videos(res.read().decode("utf-8", "replace"))


def ago(seconds):
    for unit, size in (("y", UNITS["year"]), ("mo", UNITS["month"]), ("w", UNITS["week"]), ("d", UNITS["day"]),
                       ("h", UNITS["hour"]), ("min", UNITS["minute"])):
        if seconds >= size:
            return "%d%s ago" % (seconds // size, unit)
    return "just now"


def tile(channel, video, now):
    age = video["age"] + int(now - video["fetched"])
    out = {
        "id": "youtube-" + video["id"],
        "title": video["title"],
        "subtitle": " · ".join(p for p in (channel, ago(age), video.get("duration")) if p),
        "colors": colors(video["id"]),
        "action": "youtube_watch:" + video["id"],
    }
    image = download("%s/vi/%s/mqdefault.jpg" % (THUMBNAILS, video["id"]), "youtube-%s.jpg" % video["id"])
    if image:
        out["image"] = image
    return out


def main():
    conf = json.loads((HERE / "config/youtube.json").read_text())
    try:
        cache = json.loads(RAW.read_text())
    except (OSError, ValueError):
        cache = {}
    now = time.time()
    if "--force" not in sys.argv and now - cache.get("time", 0) < MAX_AGE and cache.get("channels"):
        channels = cache["channels"]
    else:
        channels = {}
        for channel in conf["channels"]:
            try:
                videos = fetch_channel(channel["id"])[:conf.get("perChannel", 6)]
                for v in videos:
                    v["fetched"] = now
            except (OSError, ValueError) as e:
                print(f"youtube: {channel['name']}: {e}", file=sys.stderr)
                videos = []
            channels[channel["id"]] = videos or cache.get("channels", {}).get(channel["id"], [])
        RAW.parent.mkdir(parents=True, exist_ok=True)
        RAW.write_text(json.dumps({"time": now, "channels": channels}))
    names = {c["id"]: c["name"] for c in conf["channels"]}
    entries = [(v["age"] + now - v["fetched"], names.get(cid, ""), v) for cid, vs in channels.items() for v in vs]
    entries.sort(key=lambda e: e[0])
    items = [tile(name, v, now) for _, name, v in entries[:conf.get("maxItems", 20)]]
    if not items:
        print("youtube: no videos; keeping content.json", file=sys.stderr)
        return
    print(f"youtube: wrote {update_content({'youtubeChannels': items})}")


if __name__ == "__main__":
    main()
