#!/usr/bin/env python3
"""Jellyfin for the home screen: the "Continue watching" row, and playing a title by name (voice). Standard library only.

  python3 jellyfin.py               writes the jellyfinResume key (the user's resumable videos) into
                                    ~/.cache/tv-project/content.json
  python3 jellyfin.py play <title>  finds the title on the server and plays it in Jellyfin Desktop on this computer
                                    (remote control through the server, like casting from the phone). A series plays
                                    its next-up episode; a started video resumes. Prints {"ok", "title"} or
                                    {"ok": false, "error"}. Waits up to PLAY_WAIT seconds for Jellyfin Desktop to start.

Needs in ~/.config/tv-project/secrets.json:
  "jellyfin": {"url": "http://192.168.1.10:8096", "apiKey": "...", "user": "joakim"}
(apiKey: Jellyfin Dashboard -> API Keys; user: the Jellyfin user name, optional when the server has one user).
Artwork is cached in ~/.cache/tv-project/images/. Without settings, or when the server is unreachable,
content.json is left alone. Enter on a tile opens Jellyfin Desktop (the item's "app").
"""
import difflib
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from trakt import CACHE, colors, download, secrets, update_content

MAX_ITEMS = 15
PLAY_WAIT = float(os.environ.get("JELLYFIN_PLAY_WAIT", "40"))  # seconds for Jellyfin Desktop to start and connect
DESKTOP_CLIENTS = ("jellyfin desktop", "jellyfin media player")
TICKS_PER_MINUTE = 600_000_000


def settings():
    try:
        conf = secrets().get("jellyfin") or {}
    except (OSError, ValueError):
        return None
    return conf if conf.get("url") and conf.get("apiKey") else None


def get(conf, path, method="GET"):
    """Parsed JSON, or None on 404 or an empty answer; other failures raise (the caller keeps the old row)."""
    req = urllib.request.Request(conf["url"].rstrip("/") + path, method=method, data=b"" if method == "POST" else None, headers={
        "Authorization": 'MediaBrowser Client="tv-project", Device="tv", DeviceId="tv-project", Version="1.0", '
                         'Token="%s"' % conf["apiKey"],
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            body = res.read()
            return json.loads(body) if body else None
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


def words(text):
    return " ".join(re.sub(r"[^\w\s]", " ", text.lower()).split())


def pick(items, query):
    """The search hit to play: the closest title; among equally close ones (e.g. three Lord of the Rings films) the one
    in progress, then the first unwatched, then the oldest."""
    query = words(query)

    def score(item):
        name = words(item.get("Name", ""))
        ratio = difflib.SequenceMatcher(None, query, name).ratio()
        return max(ratio, 0.9 if name.startswith(query) or query in name else 0)

    scored = [(score(i), i) for i in items if i.get("Type") in ("Movie", "Series", "Episode", "Video")]
    scored = [(s, i) for s, i in scored if s >= 0.5]
    if not scored:
        return None
    best = max(s for s, _ in scored)
    close = [i for s, i in scored if s >= best - 0.05]

    def order(item):
        user = item.get("UserData") or {}
        return (not user.get("PlaybackPositionTicks"), bool(user.get("Played")), item.get("Type") == "Episode",
                item.get("ProductionYear") or 9999)

    return min(close, key=order)


def playable(conf, uid, item):
    """(item to play, start position in ticks): a series becomes its next-up episode (or its first one)."""
    if item.get("Type") == "Series":
        query = urllib.parse.urlencode({"userId": uid, "seriesId": item["Id"], "limit": 1, "fields": "UserData"})
        episodes = (get(conf, "/Shows/NextUp?" + query) or {}).get("Items") or []
        if not episodes:
            query = urllib.parse.urlencode({"userId": uid, "limit": 1, "fields": "UserData"})
            episodes = (get(conf, "/Shows/%s/Episodes?%s" % (item["Id"], query)) or {}).get("Items") or []
        if not episodes:
            return None, 0
        item = episodes[0]
    return item, (item.get("UserData") or {}).get("PlaybackPositionTicks") or 0


def desktop_session(conf, uid):
    """The Jellyfin Desktop session on this computer (by device name), else any Jellyfin Desktop session of the user."""
    sessions = get(conf, "/Sessions?" + urllib.parse.urlencode({"controllableByUserId": uid})) or []
    ours = [s for s in sessions if any(c in (s.get("Client") or "").lower() for c in DESKTOP_CLIENTS)
            and s.get("SupportsRemoteControl", True)]
    host = socket.gethostname().split(".")[0].lower()
    ours.sort(key=lambda s: s.get("LastActivityDate") or "", reverse=True)  # most recent first,
    ours.sort(key=lambda s: (s.get("DeviceName") or "").lower() != host)        # then this computer's first (stable)
    return ours[0] if ours else None


def play(query):
    conf = settings()
    if not conf:
        return {"ok": False, "error": "no \"jellyfin\" url/apiKey in secrets.json"}
    try:
        uid = user_id(conf)
        search = urllib.parse.urlencode({"userId": uid, "searchTerm": query, "recursive": "true", "limit": 25,
                                         "includeItemTypes": "Movie,Series,Episode,Video", "fields": "UserData"})
        item = pick((get(conf, "/Items?" + search) or {}).get("Items") or [], query)
        if not item:
            return {"ok": False, "error": "nothing called \"%s\"" % query}
        target, position = playable(conf, uid, item)
        if not target:
            return {"ok": False, "error": "no episodes in \"%s\"" % item.get("Name")}
        deadline = time.monotonic() + PLAY_WAIT
        while not (session := desktop_session(conf, uid)):
            if time.monotonic() > deadline:
                return {"ok": False, "error": "Jellyfin Desktop is not connected to the server"}
            time.sleep(2)
        command = urllib.parse.urlencode({"playCommand": "PlayNow", "itemIds": target["Id"], "startPositionTicks": position})
        get(conf, "/Sessions/%s/Playing?%s" % (session["Id"], command), method="POST")
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": "%s: %s" % (conf["url"], e)}
    except SystemExit as e:  # user_id(): ambiguous or unknown user
        return {"ok": False, "error": str(e)}
    title = item.get("Name", "")
    if target is not item:
        title += " S%s E%s" % (target.get("ParentIndexNumber", "?"), target.get("IndexNumber", "?"))
    return {"ok": True, "title": title}


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "play":
        print(json.dumps(play(" ".join(sys.argv[2:])), ensure_ascii=False))
        return
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
