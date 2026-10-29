#!/usr/bin/env python3
""""Recommended for you" row: Trakt's personal recommendations that are on the Jellyfin server. Standard library only.

  python3 recommend.py   writes into ~/.cache/tv-project/content.json homeFeatured (the banner: Trakt's top picks
                         alternating with the newest unwatched titles) and traktRecommended: films and series in
                         Trakt's order (alternating), matched to Jellyfin by tmdb/imdb/tvdb id, finished and started ones left out;
                         tiles look and play like the other Jellyfin tiles (OK starts it)

Needs the Trakt login (trakt.py auth) and Jellyfin settings. Trakt's answer is cached for MAX_AGE in
~/.cache/tv-project/trakt-recommendations.json (stale cache when Trakt is down). Without either, content.json is left alone.
"""
import json
import sys
import time
import urllib.error
import urllib.parse

import jellyfin
import trakt
from trakt import CACHE, update_content

RAW = CACHE / "trakt-recommendations.json"
MAX_AGE = 6 * 3600
MAX_ITEMS = 20
HERO_ITEMS = 8
FETCH = 100  # per kind; only those on the server are kept


def recommendations():
    """{"movies": [...], "shows": [...]} from Trakt, cached."""
    try:
        cache = json.loads(RAW.read_text())
    except (OSError, ValueError):
        cache = {}
    if "--force" not in sys.argv and time.time() - cache.get("time", 0) < MAX_AGE and cache.get("movies") is not None:
        return cache
    token = trakt.access_token()  # exits with a message when not logged in
    fresh = {"time": time.time()}
    for kind in ("movies", "shows"):
        status, data = trakt.request("/recommendations/%s?limit=%d&ignore_collected=false&ignore_watchlisted=false"
                                     % (kind, FETCH), token=token)
        if status != 200 or not isinstance(data, list):
            print(f"recommend: trakt {kind}: HTTP {status}; using the last list", file=sys.stderr)
            return cache
        fresh[kind] = data
    RAW.parent.mkdir(parents=True, exist_ok=True)
    RAW.write_text(json.dumps(fresh))
    return fresh


def interleave(a, b):
    out = []
    for i in range(max(len(a), len(b))):
        out += a[i:i + 1] + b[i:i + 1]
    return out


def matches(recs, library):
    """Library items for the recommendations, in their order; finished ones and duplicates left out."""
    by_id = {}
    for item in library:
        for key, value in (item.get("ProviderIds") or {}).items():
            by_id.setdefault((key.lower(), str(value)), item)
    out, seen = [], set()
    for rec in recs:
        ids = rec.get("ids") or {}
        item = next((by_id[(k, str(ids[k]))] for k in ("tmdb", "imdb", "tvdb") if ids.get(k) and (k, str(ids[k])) in by_id),
                    None)
        user = (item or {}).get("UserData") or {}
        # Finished ones, and started ones (they are in Continue watching), are left out.
        if item and item["Id"] not in seen and not user.get("Played") and not user.get("PlaybackPositionTicks"):
            seen.add(item["Id"])
            out.append(item)
    return out


def main():
    conf = jellyfin.settings()
    if not conf:
        print("recommend: no Jellyfin settings; keeping content.json", file=sys.stderr)
        return
    recs = recommendations()
    if not recs.get("movies") and not recs.get("shows"):
        print("recommend: no Trakt recommendations yet; keeping content.json", file=sys.stderr)
        return
    try:
        uid = jellyfin.user_id(conf)
        query = urllib.parse.urlencode({"userId": uid, "includeItemTypes": "Movie,Series", "recursive": "true",
                                        "fields": "ProviderIds,UserData,Overview,Genres,ChildCount",
                                        "enableImageTypes": jellyfin.IMAGE_TYPES})
        library = (jellyfin.get(conf, "/Items?" + query) or {}).get("Items", [])
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"recommend: {conf['url']}: {e}; keeping content.json", file=sys.stderr)
        return
    items = matches(interleave(recs.get("movies") or [], recs.get("shows") or []), library)[:MAX_ITEMS]
    tiles = []
    for item in items:
        tile = jellyfin.tile(conf, item)
        tile["subtitle"] = " · ".join(p for p in ("Series" if item.get("Type") == "Series" else "Film",
                                                  str(item["ProductionYear"]) if item.get("ProductionYear") else "") if p)
        tiles.append(tile)
    # Banner: Trakt's top picks alternating with the newest unwatched titles (jellyfin.py's banner), no repeats.
    try:
        newest = jellyfin.featured(conf, jellyfin.newest(conf, uid))
    except (urllib.error.URLError, OSError, ValueError):
        newest = []
    hero, seen = [], set()
    for entry in interleave(jellyfin.featured(conf, items), newest):
        if entry["id"] not in seen:
            seen.add(entry["id"])
            hero.append(entry)
    print(f"recommend: {len(tiles)} on the server; wrote "
          f"{update_content({'traktRecommended': tiles, 'homeFeatured': hero[:HERO_ITEMS]})}")


if __name__ == "__main__":
    main()
