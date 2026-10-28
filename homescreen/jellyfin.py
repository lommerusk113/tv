#!/usr/bin/env python3
"""Jellyfin "Continue watching" row for the home screen. Standard library only.

  python3 jellyfin.py   writes the jellyfinResume key (the user's resumable videos) into ~/.cache/tv-project/content.json

Needs in ~/.config/tv-project/secrets.json:
  "jellyfin": {"url": "http://192.168.1.10:8096", "apiKey": "...", "user": "joakim"}
(apiKey: Jellyfin Dashboard -> API Keys; user: the Jellyfin user name, optional when the server has one user).
Artwork is cached in ~/.cache/tv-project/images/. Without settings, or when the server is unreachable,
content.json is left alone. Enter on a tile opens Jellyfin Desktop (the item's "app").
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

from trakt import CACHE, colors, download, secrets, update_content

MAX_ITEMS = 15
TICKS_PER_MINUTE = 600_000_000


def settings():
    try:
        conf = secrets().get("jellyfin") or {}
    except (OSError, ValueError):
        return None
    return conf if conf.get("url") and conf.get("apiKey") else None


def get(conf, path):
    """Parsed JSON, or None on 404; other failures raise (the caller keeps the old row)."""
    req = urllib.request.Request(conf["url"].rstrip("/") + path, headers={
        "Authorization": 'MediaBrowser Client="tv-project", Device="tv", DeviceId="tv-project", Version="1.0", '
                         'Token="%s"' % conf["apiKey"],
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def user_id(conf):
    users = get(conf, "/Users") or []
    wanted = (conf.get("user") or "").lower()
    matches = [u for u in users if u.get("Name", "").lower() == wanted] if wanted else users
    if len(matches) != 1:
        sys.exit("jellyfin: set \"user\" in secrets.json to one of: " + ", ".join(u.get("Name", "?") for u in users))
    return matches[0]["Id"]


def resume_items(conf, uid):
    query = urllib.parse.urlencode({"limit": MAX_ITEMS, "mediaTypes": "Video", "enableImageTypes": "Primary,Backdrop,Thumb"})
    data = get(conf, "/UserItems/Resume?userId=%s&%s" % (uid, query))  # Jellyfin 10.9+
    if data is None:
        data = get(conf, "/Users/%s/Items/Resume?%s" % (uid, query))  # older servers
    return (data or {}).get("Items", [])


def artwork(item):
    """(item id, image type, tag) of the best 16:9 picture: thumb, backdrop, the series' thumb/backdrop, else primary."""
    tags = item.get("ImageTags") or {}
    candidates = [
        (item["Id"], "Thumb", tags.get("Thumb")),
        (item.get("ParentThumbItemId"), "Thumb", item.get("ParentThumbImageTag")),
        (item["Id"], "Backdrop/0", (item.get("BackdropImageTags") or [None])[0]),
        (item.get("ParentBackdropItemId"), "Backdrop/0", (item.get("ParentBackdropImageTags") or [None])[0]),
        (item["Id"], "Primary", tags.get("Primary")),
    ]
    return next(((i, kind, tag) for i, kind, tag in candidates if i and tag), None)


def tile(conf, item):
    user = item.get("UserData") or {}
    left = max(0, (item.get("RunTimeTicks") or 0) - (user.get("PlaybackPositionTicks") or 0)) // TICKS_PER_MINUTE
    if item.get("Type") == "Episode":
        title = item.get("SeriesName") or item.get("Name", "")
        parts = ["S%s E%s" % (item.get("ParentIndexNumber", "?"), item.get("IndexNumber", "?")), item.get("Name")]
    else:
        title = item.get("Name", "")
        parts = [str(item["ProductionYear"]) if item.get("ProductionYear") else None]
    if left:
        parts.append("%d min left" % left)
    out = {
        "id": "jellyfin-" + item["Id"],
        "title": title,
        "subtitle": " · ".join(p for p in parts if p),
        "colors": colors(item.get("SeriesId") or item["Id"]),
        "app": "jellyfin",
    }
    if user.get("PlayedPercentage") is not None:
        out["progress"] = round(user["PlayedPercentage"] / 100, 3)
    art = artwork(item)
    if art:
        image_id, kind, tag = art
        image = download("%s/Items/%s/Images/%s?tag=%s&maxWidth=780&quality=90" % (conf["url"].rstrip("/"), image_id, kind, tag),
                         "jellyfin-%s-%s-%s.jpg" % (image_id, kind.split("/")[0].lower(), tag))
        if image:
            out["image"] = image
    return out


def main():
    conf = settings()
    if not conf:
        print("jellyfin: no \"jellyfin\" url/apiKey in secrets.json; keeping content.json", file=sys.stderr)
        return
    try:
        items = [tile(conf, i) for i in resume_items(conf, user_id(conf))]
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"jellyfin: {conf['url']}: {e}; keeping content.json", file=sys.stderr)
        return
    print(f"jellyfin: wrote {update_content({'jellyfinResume': items})}")


if __name__ == "__main__":
    main()
