#!/usr/bin/env python3
"""Jellyfin for the home screen: its rows and banner, and playing things (tiles, voice). Standard library only.

  python3 jellyfin.py               writes into ~/.cache/tv-project/content.json: jellyfinResume (Continue watching),
                                    jellyfinNextUp (next episode of each series) and jellyfinFeatured (the banner:
                                    newest unwatched films and series, with backdrop and logo). Tiles carry
                                    "action": "jellyfin_play_id:<item id>", so OK starts them (resuming)
  python3 jellyfin.py play-id <id>  plays the item (a series: its next-up episode) in Jellyfin Desktop here
  python3 jellyfin.py playing       what plays on another device of this user ({"ok", "title"}), without touching it
  python3 jellyfin.py pull          "move to TV": stops what this user is watching on another device (phone, browser)
                                    and continues it here from the same position. Prints {"ok", "title"} like play.
  python3 jellyfin.py home          sends Jellyfin Desktop on this computer to its start page (when leaving the app)
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
FEATURED = 6
IMAGE_TYPES = "Primary,Backdrop,Thumb,Logo"
PLAY_WAIT = float(os.environ.get("JELLYFIN_PLAY_WAIT", "40"))  # seconds for Jellyfin Desktop to start and connect
START_WAIT = float(os.environ.get("JELLYFIN_START_WAIT", "10"))  # seconds for the video to start after PlayNow
DESKTOP_CLIENTS = ("jellyfin desktop", "jellyfin media player")
MIN_MATCH = 0.6   # below this a search hit is not what was asked for
GOOD_MATCH = 0.85  # stop searching more terms once a hit is this close
STOP_WORDS = {"the", "and", "of", "a", "an", "on", "in", "to", "for", "with", "og", "en", "et", "av", "på", "med", "til"}
TICKS_PER_MINUTE = 600_000_000
TICKS_PER_SECOND = 10_000_000


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
    query = urllib.parse.urlencode({"limit": MAX_ITEMS, "mediaTypes": "Video", "enableImageTypes": IMAGE_TYPES})
    data = get(conf, "/UserItems/Resume?userId=%s&%s" % (uid, query))  # Jellyfin 10.9+
    if data is None:
        data = get(conf, "/Users/%s/Items/Resume?%s" % (uid, query))  # older servers
    return (data or {}).get("Items", [])


def next_up(conf, uid):
    query = urllib.parse.urlencode({"userId": uid, "limit": MAX_ITEMS, "enableImageTypes": IMAGE_TYPES,
                                    "fields": "UserData", "enableResumable": "false"})
    return (get(conf, "/Shows/NextUp?" + query) or {}).get("Items", [])


def newest(conf, uid):
    """Newest unwatched films and series (for the banner), newest first."""
    query = urllib.parse.urlencode({"userId": uid, "includeItemTypes": "Movie,Series", "recursive": "true",
                                    "sortBy": "DateCreated", "sortOrder": "Descending", "filters": "IsUnplayed",
                                    "limit": 30, "enableImageTypes": IMAGE_TYPES,
                                    "fields": "Overview,Genres,ChildCount,UserData"})
    return (get(conf, "/Items?" + query) or {}).get("Items", [])


def image_url(conf, item_id, kind, tag, width):
    return "%s/Items/%s/Images/%s?tag=%s&maxWidth=%d&quality=90" % (conf["url"].rstrip("/"), item_id, kind, tag, width)


def featured(conf, items):
    """Banner entries: items with a backdrop (w1280), "Film/Series · genre · year/seasons", overview, logo if any;
    at most one per franchise (the first two words before a colon)."""
    out, franchises = [], set()
    for item in items:
        backdrops = item.get("BackdropImageTags") or []
        # One per franchise, so a box set added at once does not fill the banner ("Resident Evil: Retribution").
        franchise = " ".join(words(item.get("Name", "").split(":")[0]).split()[:2])
        if not backdrops or franchise in franchises:
            continue
        franchises.add(franchise)
        image = download(image_url(conf, item["Id"], "Backdrop/0", backdrops[0], 1280),
                         "jellyfin-%s-backdrop1280-%s.jpg" % (item["Id"], backdrops[0]))
        if not image:
            continue
        meta = ["Series" if item.get("Type") == "Series" else "Film"] + (item.get("Genres") or [])[:1]
        if item.get("Type") == "Series" and item.get("ChildCount"):
            meta.append("%d season%s" % (item["ChildCount"], "" if item["ChildCount"] == 1 else "s"))
        elif item.get("ProductionYear"):
            meta.append(str(item["ProductionYear"]))
        entry = {
            "id": "jellyfin-" + item["Id"],
            "title": item.get("Name", ""),
            "meta": " · ".join(meta),
            "description": item.get("Overview") or "",
            "colors": colors(item["Id"]),
            "image": image,
            "action": "jellyfin_play_id:" + item["Id"],
        }
        logo_tag = (item.get("ImageTags") or {}).get("Logo")
        logo = logo_tag and download(image_url(conf, item["Id"], "Logo", logo_tag, 800),
                                     "jellyfin-%s-logo-%s.png" % (item["Id"], logo_tag))
        if logo:
            entry["logo"] = logo
        out.append(entry)
        if len(out) == FEATURED:
            break
    return out


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
        parts.append(("%d min left" if user.get("PlaybackPositionTicks") else "%d min") % left)
    out = {
        "id": "jellyfin-" + item["Id"],
        "title": title,
        "subtitle": " · ".join(p for p in parts if p),
        "colors": colors(item.get("SeriesId") or item["Id"]),
        "app": "jellyfin",
        "action": "jellyfin_play_id:" + item["Id"],
    }
    if user.get("PlayedPercentage") is not None:
        out["progress"] = round(user["PlayedPercentage"] / 100, 3)
    art = artwork(item)
    if art:
        image_id, kind, tag = art
        image = download(image_url(conf, image_id, kind, tag, 780),
                         "jellyfin-%s-%s-%s.jpg" % (image_id, kind.split("/")[0].lower(), tag))
        if image:
            out["image"] = image
    return out


def words(text):
    """Lower case, apostrophes dropped ("man's" -> "mans"), other punctuation -> spaces."""
    return " ".join(re.sub(r"[^\w\s]", " ", re.sub(r"['\u2019]", "", text.lower())).split())


def compact(text):
    return words(text).replace(" ", "")


def match_score(query, name):
    """How well a spoken title matches an item name, ignoring spaces and apostrophes (whisper writes "deadman's chest").
    1.0 exact; 0.95 when the query is part of the name ("dead mans chest" in "Pirates of the Caribbean: Dead Man's
    Chest"); otherwise the best fuzzy match against the whole name or a same-length part of it ("kung fu hustling")."""
    q, n = compact(query), compact(name)
    if not q or not n:
        return 0
    if q == n:
        return 1.0
    if q in n:
        return 0.95
    whole = difflib.SequenceMatcher(None, q, n).ratio()
    parts = max(difflib.SequenceMatcher(None, q, n[i:i + len(q)]).ratio() for i in range(max(1, len(n) - len(q) + 1)))
    return max(whole, 0.9 * parts)


def pick(items, query):
    """The search hit to play: the closest title; among equally close ones (e.g. three Lord of the Rings films) the one
    in progress, then the first unwatched, then the oldest."""
    scored = [(match_score(query, i.get("Name", "")), i) for i in items
              if i.get("Type") in ("Movie", "Series", "Episode", "Video")]
    scored = [(s, i) for s, i in scored if s >= MIN_MATCH]
    if not scored:
        return None
    best = max(s for s, _ in scored)
    close = [i for s, i in scored if s >= best - 0.05]

    def order(item):
        user = item.get("UserData") or {}
        return (not user.get("PlaybackPositionTicks"), bool(user.get("Played")), item.get("Type") == "Episode",
                item.get("ProductionYear") or 9999)

    return min(close, key=order)


def search_terms(query):
    """The spoken title, then (Jellyfin only finds exact text) its longest words, then their first letters
    ("hustling" -> "hustl" finds "Hustle")."""
    ws = sorted({w for w in words(query).split() if len(w) >= 3 and w not in STOP_WORDS}, key=len, reverse=True)[:4]
    terms = [query, words(query)] + ws + [w[:5] for w in ws if len(w) > 6]
    return list(dict.fromkeys(t for t in terms if t))


def find(conf, uid, query):
    """Search with search_terms() until something matches well; the best of everything found."""
    found = {}
    for term in search_terms(query):
        search = urllib.parse.urlencode({"userId": uid, "searchTerm": term, "recursive": "true", "limit": 25,
                                         "includeItemTypes": "Movie,Series,Episode,Video", "fields": "UserData"})
        for item in (get(conf, "/Items?" + search) or {}).get("Items") or []:
            found.setdefault(item["Id"], item)
        best = pick(list(found.values()), query)
        if best and match_score(query, best.get("Name", "")) >= GOOD_MATCH:
            return best
    return pick(list(found.values()), query)


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
        item = find(conf, uid, query)
        if not item:
            return {"ok": False, "error": "nothing called \"%s\"" % query}
        return start(conf, uid, item)
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": "%s: %s" % (conf["url"], e)}
    except SystemExit as e:  # user_id(): ambiguous or unknown user
        return {"ok": False, "error": str(e)}


def play_id(item_id):
    conf = settings()
    if not conf:
        return {"ok": False, "error": "no \"jellyfin\" url/apiKey in secrets.json"}
    try:
        uid = user_id(conf)
        query = urllib.parse.urlencode({"userId": uid, "fields": "UserData"})
        item = get(conf, "/Items/%s?%s" % (urllib.parse.quote(item_id), query))
        if not item:
            return {"ok": False, "error": "no item %s" % item_id}
        return start(conf, uid, item)
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": "%s: %s" % (conf["url"], e)}
    except SystemExit as e:
        return {"ok": False, "error": str(e)}


def start(conf, uid, item):
    """Plays the item (a series: its next-up episode, a started video: from its position) on this computer's
    Jellyfin Desktop, waiting for it to connect. Returns the {"ok", "title"} result."""
    target, position = playable(conf, uid, item)
    if not target:
        return {"ok": False, "error": "no episodes in \"%s\"" % item.get("Name")}
    session = wait_for_desktop(conf, uid)
    if not session:
        return {"ok": False, "error": "Jellyfin Desktop is not connected to the server"}
    command = urllib.parse.urlencode({"playCommand": "PlayNow", "itemIds": target["Id"], "startPositionTicks": position})
    get(conf, "/Sessions/%s/Playing?%s" % (session["Id"], command), method="POST")
    # Return once it plays, so the home screen raises Jellyfin straight into the video (not its start page first).
    deadline = time.monotonic() + START_WAIT
    while time.monotonic() < deadline:
        now = next((s for s in get(conf, "/Sessions?" + urllib.parse.urlencode({"controllableByUserId": uid})) or []
                    if s.get("Id") == session["Id"]), {})
        # NowPlayingItem is set as soon as the command arrives; wait until the position moves (the video runs).
        if ((now.get("NowPlayingItem") or {}).get("Id") == target["Id"]
                and ((now.get("PlayState") or {}).get("PositionTicks") or 0) >= position + TICKS_PER_SECOND):
            break
        time.sleep(0.4)
    title = item.get("Name", "")
    if target is not item:
        title += " S%s E%s" % (target.get("ParentIndexNumber", "?"), target.get("IndexNumber", "?"))
    return {"ok": True, "title": title}


def wait_for_desktop(conf, uid):
    deadline = time.monotonic() + PLAY_WAIT
    while not (session := desktop_session(conf, uid)):
        if time.monotonic() > deadline:
            return None
        time.sleep(2)
    return session


def elsewhere(conf, uid, here):
    """The most recent session of this user, other than here, that is playing something; or None."""
    sessions = get(conf, "/Sessions?" + urllib.parse.urlencode({"controllableByUserId": uid})) or []
    playing = [s for s in sessions if s.get("NowPlayingItem") and (not here or s["Id"] != here["Id"])]
    return max(playing, key=lambda s: s.get("LastActivityDate") or "") if playing else None


def item_title(item):
    if item.get("Type") == "Episode":
        return "%s S%s E%s" % (item.get("SeriesName", ""), item.get("ParentIndexNumber", "?"), item.get("IndexNumber", "?"))
    return item.get("Name", "")


def playing():
    conf = settings()
    if not conf:
        return {"ok": False, "error": "no \"jellyfin\" url/apiKey in secrets.json"}
    try:
        uid = user_id(conf)
        source = elsewhere(conf, uid, desktop_session(conf, uid))
    except (urllib.error.URLError, OSError, ValueError, SystemExit) as e:
        return {"ok": False, "error": str(e)}
    if not source:
        return {"ok": False, "error": "nothing is playing on another device"}
    return {"ok": True, "title": item_title(source["NowPlayingItem"]), "from": source.get("DeviceName", "")}


def pull():
    conf = settings()
    if not conf:
        return {"ok": False, "error": "no \"jellyfin\" url/apiKey in secrets.json"}
    try:
        uid = user_id(conf)
        here = desktop_session(conf, uid)
        source = elsewhere(conf, uid, here)
        if not source:
            return {"ok": False, "error": "nothing is playing on another device"}
        item, position = source["NowPlayingItem"], (source.get("PlayState") or {}).get("PositionTicks") or 0
        # Stop (not pause) on the other device: it saves the position and leaves the player there.
        get(conf, "/Sessions/%s/Playing/Stop" % source["Id"], method="POST")
        target = here or wait_for_desktop(conf, uid)
        if not target:
            return {"ok": False, "error": "Jellyfin Desktop is not connected to the server"}
        command = urllib.parse.urlencode({"playCommand": "PlayNow", "itemIds": item["Id"], "startPositionTicks": position})
        get(conf, "/Sessions/%s/Playing?%s" % (target["Id"], command), method="POST")
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": "%s: %s" % (conf["url"], e)}
    except SystemExit as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "title": item_title(item), "from": source.get("DeviceName", "")}


def home():
    """GoHome remote command to this computer's Jellyfin Desktop; quietly nothing when it is not running."""
    conf = settings()
    if not conf:
        return
    try:
        session = desktop_session(conf, user_id(conf))
        if session:
            get(conf, "/Sessions/%s/Command/GoHome" % session["Id"], method="POST")
    except (urllib.error.URLError, OSError, ValueError, SystemExit) as e:
        print(f"jellyfin: home: {e}", file=sys.stderr)


def main():
    if sys.argv[1:] == ["home"]:
        return home()
    if sys.argv[1:] in (["pull"], ["playing"]):
        print(json.dumps((pull if sys.argv[1] == "pull" else playing)(), ensure_ascii=False))
        return
    if len(sys.argv) == 3 and sys.argv[1] == "play-id":
        print(json.dumps(play_id(sys.argv[2]), ensure_ascii=False))
        return
    if len(sys.argv) > 2 and sys.argv[1] == "play":
        print(json.dumps(play(" ".join(sys.argv[2:])), ensure_ascii=False))
        return
    conf = settings()
    if not conf:
        print("jellyfin: no \"jellyfin\" url/apiKey in secrets.json; keeping content.json", file=sys.stderr)
        return
    try:
        uid = user_id(conf)
        rows = {
            "jellyfinResume": [tile(conf, i) for i in resume_items(conf, uid)],
            "jellyfinNextUp": [tile(conf, i) for i in next_up(conf, uid)],
            "jellyfinFeatured": featured(conf, newest(conf, uid)),
        }
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"jellyfin: {conf['url']}: {e}; keeping content.json", file=sys.stderr)
        return
    print(f"jellyfin: wrote {update_content(rows)}")


if __name__ == "__main__":
    main()
