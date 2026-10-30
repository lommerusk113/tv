#!/usr/bin/env python3
""""Get more" row and requests through Jellyseerr/Overseerr. Standard library only.

  python3 jellyseerr.py                      writes the traktMissing key into ~/.cache/tv-project/content.json:
                                             Trakt picks NOT on the server (recommend.py's trakt-missing.json) with
                                             Jellyseerr's poster, year and status; OK asks "Request X?"
  python3 jellyseerr.py request movie|tv <tmdb id>   requests it (series: all seasons); prints {"ok", "status"}
  python3 jellyseerr.py search <title>       films/series matching a title (voice: "play X" when X is not on the server,
                                             "download X"): {"ok", "query", "results": [{kind, tmdb, title, year,
                                             image, status, label, overview}]}, best first, max SEARCH_ITEMS
  python3 jellyseerr.py browse               the Jellyseerr page (SeerrPage.qml): {"ok", "rows": [{id, title, items}]} -
                                             trending, popular films/series, upcoming, your requests; tiles like
                                             search's (poster = TMDb URL, loaded by QML; kind, tmdb, status, label)
  python3 jellyseerr.py details movie|tv <tmdb>   {"ok", "trailer", "overview", "status"} (RequestDialog, lazily)
  python3 jellyseerr.py search --all <title> up to BROWSE_ITEMS results instead of SEARCH_ITEMS
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
BROWSE_ITEMS = 20
BROWSE_ROWS = [("trending", "Trending", "/discover/trending"), ("movies", "Popular films", "/discover/movies"),
               ("tv", "Popular series", "/discover/tv"), ("upcomingMovies", "Coming soon: films",
               "/discover/movies/upcoming"), ("upcomingTv", "Coming soon: series", "/discover/tv/upcoming")]
TMDB_POSTERS = "https://image.tmdb.org/t/p/w342"
TMDB_BACKDROPS = "https://image.tmdb.org/t/p/w1280"
STATUS_AGE = 3600
DETAILS_AGE = 86400
# Jellyseerr media status: 1 unknown, 2 pending, 3 processing, 4 partially available, 5 available, 6 blacklisted
LABEL = {2: "Requested", 3: "Downloading", 4: "Partly on the server", 5: "On the server"}
SHORT_LABEL = {2: "Requested", 3: "Downloading", 4: "✓ Partly there", 5: "✓ On your server"}


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
    if old and "backdrop" in old and now - old["fetched"] < DETAILS_AGE and now - old.get("checked", 0) < STATUS_AGE:
        return old
    d = api(conf, "/%s/%s" % (kind, tmdb))
    date = d.get("releaseDate") or d.get("firstAirDate") or ""
    cache[key] = {"title": d.get("title") or d.get("name") or "", "year": date[:4], "poster": d.get("posterPath"),
                  "status": (d.get("mediaInfo") or {}).get("status") or 1, "fetched": now, "checked": now,
                  "trailer": trailer(d), "overview": (d.get("overview") or "")[:400],
                  "backdrop": d.get("backdropPath") or ""}
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
    if info.get("backdrop"):
        out["backdrop"] = TMDB_BACKDROPS + info["backdrop"]  # the home screen's background (a URL: QML loads it)
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


def browse_tile(kind, tmdb, title, date, poster, status, overview="", wide=""):
    """A poster tile for SeerrPage / search: OK = request:<kind>:<tmdb>:<title> (RequestDialog)."""
    label = LABEL.get(status, "")
    return {"id": "seerr-%s-%s" % (kind, tmdb), "kind": kind, "tmdb": tmdb, "title": title, "year": date[:4],
            "status": status, "label": label,
            # under a poster there is room for about 20 characters: the status alone when it has one
            "meta": SHORT_LABEL.get(status) or " · ".join(p for p in ("Series" if kind == "tv" else "Film", date[:4]) if p),
            "overview": (overview or "")[:400], "image": TMDB_POSTERS + poster if poster else "",
            "colors": colors("%s-%s" % (kind, tmdb)), "action": "request:%s:%s:%s" % (kind, tmdb, title),
            "backdrop": TMDB_BACKDROPS + wide if wide else ""}


def result_tile(r):
    """Tile for a /search or /discover result; None for people and titles without a poster."""
    if r.get("mediaType") not in ("movie", "tv") or not r.get("posterPath"):
        return None
    return browse_tile(r["mediaType"], r["id"], r.get("title") or r.get("name") or "",
                       r.get("releaseDate") or r.get("firstAirDate") or "", r["posterPath"],
                       (r.get("mediaInfo") or {}).get("status") or 1, r.get("overview"), r.get("backdropPath"))


def browse(conf):
    rows = []
    for row_id, title, path in BROWSE_ROWS:
        try:
            res = api(conf, path + "?page=1")
        except (urllib.error.URLError, OSError, ValueError) as e:
            print(f"jellyseerr: {path}: {e}", file=sys.stderr)
            continue
        items = [t for t in map(result_tile, res.get("results") or []) if t][:BROWSE_ITEMS]
        if items:
            rows.append({"id": row_id, "title": title, "items": items})
    # Your requests, newest first (the request list has no titles: details() fills them in, cached a day).
    try:
        requests = api(conf, "/request?take=%d&skip=0&sort=added&filter=all" % BROWSE_ITEMS).get("results") or []
        cache = json.loads(DETAILS.read_text()) if DETAILS.exists() else {}
        items = []
        for req in requests:
            media = req.get("media") or {}
            kind, tmdb = media.get("mediaType"), media.get("tmdbId")
            if kind not in ("movie", "tv") or not tmdb:
                continue
            try:
                info = details(conf, kind, tmdb, cache)
            except (urllib.error.URLError, OSError, ValueError):
                continue
            status = media.get("status") or info["status"]
            tile = browse_tile(kind, tmdb, info["title"], info["year"], info.get("poster"), status, info.get("overview"),
                               info.get("backdrop"))
            tile["trailer"] = info.get("trailer") or ""
            items.append(tile)
        DETAILS.write_text(json.dumps(cache))
        if items:
            rows.insert(1, {"id": "requests", "title": "Your requests", "items": items})
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"jellyseerr: requests: {e}", file=sys.stderr)
    return {"ok": bool(rows), "rows": rows}


def details_of(conf, kind, tmdb):
    try:
        cache = json.loads(DETAILS.read_text()) if DETAILS.exists() else {}
        info = details(conf, kind, tmdb, cache)
        DETAILS.write_text(json.dumps(cache))
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "trailer": info.get("trailer") or "", "overview": info.get("overview") or "",
            "status": info["status"]}


def search(conf, query, limit=SEARCH_ITEMS):
    try:
        # Jellyseerr wants spaces as %20, not "+" (it rejects the query otherwise).
        res = api(conf, "/search?query=%s&page=1" % urllib.parse.quote(query, safe=""))
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"ok": False, "error": str(e)}
    out = [t for t in map(result_tile, res.get("results") or []) if t][:limit]
    return {"ok": True, "query": query, "results": out}


def quiet_chrome(path):
    """No "Save password?" bubble (the remote cannot reach it) and no "Restore pages?" after a kill. Only works while
    this Chrome is closed (it rewrites the file on exit), which is the case when open_site runs."""
    try:
        prefs = json.loads(path.read_text())
    except (OSError, ValueError):
        prefs = {}
    prefs["credentials_enable_service"] = False
    prefs.setdefault("profile", {}).update({"password_manager_enabled": False, "exit_type": "Normal"})
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tv-tmp")
    tmp.write_text(json.dumps(prefs))
    tmp.replace(path)


def open_site(conf):
    """Replace this process with Chrome in kiosk mode on the Jellyseerr site. Its own profile (--user-data-dir) makes
    it a separate Chrome from RiksTV's, so --class sticks (Bigscreen raises it by that) and the login is remembered;
    spatial navigation lets the remote's arrows move between buttons, Back is the browser's back. DevTools on
    127.0.0.1:9233 is for the on-screen keyboard (osk.py)."""
    profile = Path.home() / ".var/app/com.google.Chrome/data/tv-jellyseerr"
    profile.mkdir(parents=True, exist_ok=True)
    quiet_chrome(profile / "Default/Preferences")
    os.execvp("flatpak", ["flatpak", "run", "com.google.Chrome", "--class=tv-jellyseerr", f"--user-data-dir={profile}",
                          "--enable-spatial-navigation", "--no-first-run",
                          "--remote-debugging-port=9233", "--kiosk", conf["url"].rstrip("/") + "/"])


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
    if len(sys.argv) >= 4 and sys.argv[1:3] == ["search", "--all"]:
        print(json.dumps(search(conf, " ".join(sys.argv[3:]), BROWSE_ITEMS), ensure_ascii=False))
        return
    if len(sys.argv) >= 3 and sys.argv[1] == "search":
        print(json.dumps(search(conf, " ".join(sys.argv[2:])), ensure_ascii=False))
        return
    if sys.argv[1:] == ["browse"]:
        print(json.dumps(browse(conf), ensure_ascii=False))
        return
    if len(sys.argv) == 4 and sys.argv[1] == "details" and sys.argv[2] in ("movie", "tv") and sys.argv[3].isdigit():
        print(json.dumps(details_of(conf, sys.argv[2], sys.argv[3])))
        return
    if len(sys.argv) > 1:
        sys.exit(__doc__)
    build(conf)


if __name__ == "__main__":
    main()
