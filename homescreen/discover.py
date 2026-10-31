#!/usr/bin/env python3
"""More to find on the home screen, from Trakt. Standard library only.

  python3 discover.py          writes into ~/.cache/tv-project/content.json:
                               traktBecause + traktBecauseTitle  "Because you watched X": Trakt's related titles for
                                                                 the last film or series in your Trakt history
                               traktTrending                     what Trakt users watch this week (films and series)
                               traktCalendar                     "New episodes this week": your shows' episodes from
                                                                 yesterday to a week ahead (Trakt calendar)
  python3 discover.py --force  the same without the cache

Titles on the Jellyfin server play (OK), others ask "Request X?" through Jellyseerr (left out without Jellyseerr);
finished or started ones are left out of the first two. Episodes: on the server plays it, else the series' page in
Jellyfin, else a request. Needs the Trakt login (trakt.py auth) and Jellyfin settings; Trakt's answers are cached for
MAX_AGE in ~/.cache/tv-project/trakt-discover.json (the last one is used when Trakt is down).
"""
import datetime
import json
import sys
import time
import urllib.error
import urllib.parse

import jellyfin
import jellyseerr
import recommend
import trakt
from trakt import CACHE, update_content

RAW = CACHE / "trakt-discover.json"
MAX_AGE = 3600
MAX_ITEMS = 20
FETCH = 40  # per list; some are left out (finished, or not requestable)
CALENDAR_DAYS = 8  # yesterday + a week


def fetch():
    """Trakt's answers: {"last": history entry, "related": [...], "movies": [...], "shows": [...], "calendar": [...]}."""
    try:
        cache = json.loads(RAW.read_text())
    except (OSError, ValueError):
        cache = {}
    if "--force" not in sys.argv and time.time() - cache.get("time", 0) < MAX_AGE and "calendar" in cache:
        return cache
    token = trakt.access_token()  # exits with a message when not logged in

    def get(path):
        status, data = trakt.request(path, token=token)
        if status != 200 or not isinstance(data, list):
            raise OSError(f"trakt {path.split('?')[0]}: HTTP {status}")
        return data

    try:
        fresh = {"time": time.time()}
        # The last film or series (an episode counts for its series) you watched.
        fresh["last"] = next((h for h in get("/sync/history?limit=10") if h.get("type") in ("movie", "episode")), None)
        if fresh["last"]:
            kind = "movies" if fresh["last"]["type"] == "movie" else "shows"
            what = fresh["last"]["movie" if kind == "movies" else "show"]
            fresh["related"] = get("/%s/%d/related?limit=%d" % (kind, what["ids"]["trakt"], FETCH))
            for rec in fresh["related"]:
                rec["_kind"] = kind
        fresh["movies"] = [t["movie"] for t in get("/movies/trending?limit=%d" % FETCH)]
        fresh["shows"] = [t["show"] for t in get("/shows/trending?limit=%d" % FETCH)]
        for kind in ("movies", "shows"):
            for rec in fresh[kind]:
                rec["_kind"] = kind
        start = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
        fresh["calendar"] = get("/calendars/my/shows/%s/%d" % (start, CALENDAR_DAYS))
    except OSError as e:
        print(f"discover: {e}; using the last answers", file=sys.stderr)
        return cache
    RAW.parent.mkdir(parents=True, exist_ok=True)
    RAW.write_text(json.dumps(fresh))
    return fresh


def lookup(library):
    """(provider, id) -> library item."""
    by_id = {}
    for item in library:
        for key, value in (item.get("ProviderIds") or {}).items():
            by_id.setdefault((key.lower(), str(value)), item)
    return by_id


def find(by_id, ids):
    return next((by_id[(k, str(ids[k]))] for k in ("tmdb", "imdb", "tvdb") if ids.get(k) and (k, str(ids[k])) in by_id),
                None)


def mixed(conf, seerr, cache, recs, by_id):
    """Poster tiles: on the server -> plays (finished/started left out), else a Jellyseerr request tile."""
    tiles, seen = [], set()
    for rec in recs:
        ids = rec.get("ids") or {}
        item = find(by_id, ids)
        if item:
            user = item.get("UserData") or {}
            if item["Id"] in seen or user.get("Played") or user.get("PlaybackPositionTicks"):
                continue
            seen.add(item["Id"])
            tile = jellyfin.poster(conf, item)
            tile["meta"] += " · " + jellyseerr.SHORT_LABEL[5]  # tells it apart from the ones to request
            tiles.append(tile)
        elif seerr and ids.get("tmdb"):
            kind = "tv" if rec["_kind"] == "shows" else "movie"
            try:
                info = jellyseerr.details(seerr, kind, ids["tmdb"], cache)
            except (urllib.error.URLError, OSError, ValueError) as e:
                print(f"discover: {rec.get('title')}: {e}", file=sys.stderr)
                continue
            if info["status"] in (5, 6) or not info["title"]:  # there after all, or blacklisted
                continue
            tiles.append(jellyseerr.tile(kind, ids["tmdb"], info))
        if len(tiles) == MAX_ITEMS:
            break
    return tiles


def when(aired, today):
    """"Today", "Tomorrow", "Yesterday" or the weekday, local time."""
    day = datetime.datetime.fromisoformat(aired.replace("Z", "+00:00")).astimezone().date()
    return {0: "Today", 1: "Tomorrow", -1: "Yesterday"}.get((day - today).days, day.strftime("%a"))


def episodes(conf, uid, series_id, season, cache):
    key = (series_id, season)
    if key not in cache:
        query = urllib.parse.urlencode({"userId": uid, "season": season, "fields": "UserData"})
        cache[key] = (jellyfin.get(conf, "/Shows/%s/Episodes?%s" % (series_id, query)) or {}).get("Items", [])
    return cache[key]


def picture(conf, seerr, cache, show, series):
    """Wide picture for an episode tile: the series' Jellyfin backdrop, else Jellyseerr's (TMDb), else TMDb directly
    (trakt.backdrop, needs a TMDb key); None leaves the coloured placeholder."""
    if series:
        return jellyfin.backdrop(conf, series)
    tmdb = show["ids"].get("tmdb")
    if seerr and tmdb:
        try:
            info = jellyseerr.details(seerr, "tv", tmdb, cache)
        except (urllib.error.URLError, OSError, ValueError):
            info = {}
        if info.get("backdrop"):
            return trakt.download(jellyseerr.TMDB_BACKDROPS.replace("w1280", "w780") + info["backdrop"],
                                  "tmdb-tv-%s.jpg" % tmdb)
    return trakt.backdrop(show)


def calendar(conf, uid, entries, by_id, seerr, cache):
    """Landscape tiles for the calendar, in airing order: "S2 E5 · Tomorrow". Specials (season 0) left out."""
    today = datetime.date.today()
    tiles, seasons = [], {}
    for entry in sorted(entries, key=lambda e: e.get("first_aired") or ""):
        show, episode = entry["show"], entry["episode"]
        if not episode.get("season"):
            continue
        aired = when(entry["first_aired"], today) if entry.get("first_aired") else ""
        series = find(by_id, show.get("ids") or {})
        image = picture(conf, seerr, cache, show, series)
        tile = trakt.tile(show, episode, image=image)
        if image:
            tile["backdrop"] = image
        tile["id"] = "trakt-calendar-%d" % episode["ids"]["trakt"]
        tile["subtitle"] = " · ".join(p for p in ("S%d E%d" % (episode["season"], episode["number"]), aired,
                                                  episode.get("title")) if p)
        if series:
            hit = next((e for e in episodes(conf, uid, series["Id"], episode["season"], seasons)
                        if e.get("IndexNumber") == episode["number"] and e.get("LocationType") != "Virtual"), None)
            tile["app"] = "jellyfin"
            tile["action"] = "jellyfin_play_id:" + hit["Id"] if hit else "jellyfin_show:" + series["Id"]
            if hit:
                tile["subtitle"] += " · ✓ On your server"
        elif seerr and show["ids"].get("tmdb"):
            tile["action"] = "request:tv:%s:%s" % (show["ids"]["tmdb"], show["title"])
        tiles.append(tile)
        if len(tiles) == MAX_ITEMS:
            break
    return tiles


def main():
    conf = jellyfin.settings()
    if not conf:
        print("discover: no Jellyfin settings; keeping content.json", file=sys.stderr)
        return
    raw = fetch()
    if "calendar" not in raw:
        print("discover: nothing from Trakt yet; keeping content.json", file=sys.stderr)
        return
    try:
        uid = jellyfin.user_id(conf)
        by_id = lookup(recommend.library_items(conf, uid))
        seerr = jellyseerr.settings()
        try:
            cache = json.loads(jellyseerr.DETAILS.read_text())
        except (OSError, ValueError):
            cache = {}
        updates = {
            "traktBecause": mixed(conf, seerr, cache, raw.get("related") or [], by_id),
            "traktTrending": mixed(conf, seerr, cache, recommend.interleave(raw.get("movies") or [],
                                                                            raw.get("shows") or []), by_id),
            "traktCalendar": calendar(conf, uid, raw["calendar"], by_id, seerr, cache),
        }
        jellyseerr.DETAILS.write_text(json.dumps(cache))
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"discover: {e}; keeping content.json", file=sys.stderr)
        return
    last = raw.get("last") or {}
    watched = (last.get("movie") or last.get("show") or {}).get("title")
    updates["traktBecauseTitle"] = "Because you watched " + watched if watched else ""
    print("discover: " + ", ".join("%s %d" % (k, len(v)) for k, v in updates.items() if isinstance(v, list))
          + f"; wrote {update_content(updates)}")


if __name__ == "__main__":
    main()
