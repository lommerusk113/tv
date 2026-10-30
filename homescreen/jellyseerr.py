#!/usr/bin/env python3
""""Get more" row and requests through Jellyseerr/Overseerr. Standard library only.

  python3 jellyseerr.py                      writes the traktMissing key into ~/.cache/tv-project/content.json:
                                             Trakt picks NOT on the server (recommend.py's trakt-missing.json) with
                                             Jellyseerr's poster, year and status; OK asks "Request X?"
  python3 jellyseerr.py request movie|tv <tmdb id>   requests it (series: all seasons); prints {"ok", "status"}
  python3 jellyseerr.py search <title>       films/series matching a title (voice: "play X" when X is not on the server,
                                             "download X"): {"ok", "query", "results": [{kind, tmdb, title, year,
                                             image, status, label, overview}]}, best first, max SEARCH_ITEMS
  python3 jellyseerr.py open                 the Jellyseerr website full screen (the "Jellyseerr" app tile,
                                             desktop/tv-jellyseerr.desktop): Chrome kiosk with its own profile

Settings in ~/.config/tv-project/secrets.json: "jellyseerr": {"url": "http://...:5055", "apiKey": "..."} (Settings ->
General -> API Key). Requests are made as the API key's user (admin = approved at once, then Sonarr/Radarr).
Details are cached for a day in ~/.cache/tv-project/jellyseerr-details.json (status for an hour).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from trakt import CACHE, colors, download, secrets, update_content

MISSING = CACHE / "trakt-missing.json"
DETAILS = CACHE / "jellyseerr-details.json"
TMDB_IMAGES = "https://image.tmdb.org/t/p/w342"
MAX_ITEMS = 20
SEARCH_ITEMS = 6
STATUS_AGE = 3600
DETAILS_AGE = 86400
# Jellyseerr media status: 1 unknown, 2 pending, 3 processing, 4 partially available, 5 available, 6 blacklisted
LABEL = {2: "Requested", 3: "Downloading", 4: "Partly on the server", 5: "On the server"}


def settings():
    try:
        conf = secrets().get("jellyseerr") or {}
    except (OSError, ValueError):
        return None
    return conf if conf.get("url") and conf.get("apiKey") else None


def api(conf, path, body=None):
    req = urllib.request.Request(conf["url"].rstrip("/") + "/api/v1" + path, method="POST" if body is not None else "GET",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"X-Api-Key": conf["apiKey"], "Content-Type": "application/json",
                                          "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as res:
        text = res.read()
        return json.loads(text) if text else None


def details(conf, kind, tmdb, cache):
    """{title, year, poster, status} for a title, from the cache when fresh enough."""
    key = "%s:%s" % (kind, tmdb)
    old = cache.get(key)
    now = time.time()
    if old and "trailer" in old and now - old["fetched"] < DETAILS_AGE and now - old.get("checked", 0) < STATUS_AGE:
        return old
    d = api(conf, "/%s/%s" % (kind, tmdb))
    date = d.get("releaseDate") or d.get("firstAirDate") or ""
    cache[key] = {"title": d.get("title") or d.get("name") or "", "year": date[:4], "poster": d.get("posterPath"),
                  "status": (d.get("mediaInfo") or {}).get("status") or 1, "fetched": now, "checked": now,
                  "trailer": trailer(d), "overview": (d.get("overview") or "")[:400]}
    return cache[key]


def trailer(d):
    """YouTube id of the title's trailer (TMDb related videos): a Trailer, else a Teaser, else any clip; or None."""
    videos = [v for v in d.get("relatedVideos") or [] if v.get("site") == "YouTube" and v.get("key")]
    for kind in ("Trailer", "Teaser", None):
        hit = next((v["key"] for v in videos if kind is None or v.get("type") == kind), None)
        if hit:
            return hit
    return None


def tile(kind, tmdb, info):
    status = LABEL.get(info["status"])
    out = {
        "id": "seerr-%s-%s" % (kind, tmdb),
        "title": info["title"],
        "meta": " · ".join(p for p in ("Series" if kind == "tv" else "Film", info["year"], status) if p),
        "colors": colors("%s%s" % (kind, tmdb)),
        "action": "request:%s:%s:%s" % (kind, tmdb, info["title"]),
        "overview": info.get("overview") or "",
    }
    if info.get("trailer"):
        out["trailer"] = info["trailer"]  # RequestDialog's "Trailer" button (youtube_watch)
    if info.get("poster"):
        image = download(TMDB_IMAGES + info["poster"], "tmdb-%s-%s-w342.jpg" % (kind, tmdb))
        if image:
            out["image"] = image
    return out


def build(conf):
    try:
        missing = json.loads(MISSING.read_text())
    except (OSError, ValueError):
        print("jellyseerr: no trakt-missing.json yet (run recommend.py); keeping content.json", file=sys.stderr)
        return
    try:
        cache = json.loads(DETAILS.read_text())
    except (OSError, ValueError):
        cache = {}
    tiles = []
    for rec in missing:
        try:
            info = details(conf, rec["type"], rec["tmdb"], cache)
        except (urllib.error.URLError, OSError, ValueError) as e:
            print(f"jellyseerr: {rec['title']}: {e}", file=sys.stderr)
            continue
        if info["status"] in (5, 6):  # already there (recommend.py will show it) or blacklisted
            continue
        tiles.append(tile(rec["type"], rec["tmdb"], info))
        if len(tiles) == MAX_ITEMS:
            break
    DETAILS.write_text(json.dumps(cache))
    if tiles:
        print(f"jellyseerr: wrote {update_content({'traktMissing': tiles})}")


def request(conf, kind, tmdb):
    body = {"mediaType": kind, "mediaId": int(tmdb)}
    if kind == "tv":
        body["seasons"] = "all"
    try:
        res = api(conf, "/request", body) or {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:200]
        return {"ok": False, "error": "HTTP %d %s" % (e.code, detail)}
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": str(e)}
    # Mark it at once, so the row shows "Requested" without waiting an hour.
    try:
        cache = json.loads(DETAILS.read_text())
        key = "%s:%s" % (kind, tmdb)
        if key in cache:
            cache[key]["status"] = max(cache[key]["status"], 2)
            DETAILS.write_text(json.dumps(cache))
    except (OSError, ValueError):
        pass
    return {"ok": True, "status": res.get("status")}


def search(conf, query):
    try:
        # Jellyseerr wants spaces as %20, not "+" (it rejects the query otherwise).
        res = api(conf, "/search?query=%s&page=1" % urllib.parse.quote(query, safe=""))
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": str(e)}
    out = []
    for r in res.get("results") or []:
        if r.get("mediaType") not in ("movie", "tv") or not r.get("posterPath"):
            continue
        status = (r.get("mediaInfo") or {}).get("status") or 1
        date = r.get("releaseDate") or r.get("firstAirDate") or ""
        out.append({"kind": r["mediaType"], "tmdb": r["id"], "title": r.get("title") or r.get("name") or "",
                    "year": date[:4], "status": status, "label": LABEL.get(status, ""),
                    "overview": (r.get("overview") or "")[:300],
                    "image": download(TMDB_IMAGES + r["posterPath"], "tmdb-%s-%s-w342.jpg" % (r["mediaType"], r["id"])),
                    "colors": colors("%s-%s" % (r["mediaType"], r["id"]))})
        if len(out) == SEARCH_ITEMS:
            break
    return {"ok": True, "query": query, "results": out}


def open_site(conf):
    """Replace this process with Chrome in kiosk mode on the Jellyseerr site. Its own profile (--user-data-dir) makes
    it a separate Chrome from RiksTV's, so --class sticks (Bigscreen raises it by that) and the login is remembered;
    spatial navigation lets the remote's arrows move between buttons, Back is the browser's back."""
    profile = Path.home() / ".var/app/com.google.Chrome/data/tv-jellyseerr"
    profile.mkdir(parents=True, exist_ok=True)
    os.execvp("flatpak", ["flatpak", "run", "com.google.Chrome", "--class=tv-jellyseerr", f"--user-data-dir={profile}",
                          "--enable-spatial-navigation", "--no-first-run", "--kiosk", conf["url"].rstrip("/") + "/"])


def main():
    conf = settings()
    if not conf:
        print("jellyseerr: no \"jellyseerr\" url/apiKey in secrets.json", file=sys.stderr)
        return
    if sys.argv[1:] == ["open"]:
        open_site(conf)
    if len(sys.argv) == 4 and sys.argv[1] == "request" and sys.argv[2] in ("movie", "tv") and sys.argv[3].isdigit():
        print(json.dumps(request(conf, sys.argv[2], sys.argv[3])))
        return
    if len(sys.argv) >= 3 and sys.argv[1] == "search":
        print(json.dumps(search(conf, " ".join(sys.argv[2:])), ensure_ascii=False))
        return
    if len(sys.argv) > 1:
        sys.exit(__doc__)
    build(conf)


if __name__ == "__main__":
    main()
