#!/usr/bin/env python3
"""TMDb "Trending" row for the home screen. Standard library only.

  python3 tmdb.py   writes the trending row (films and series of the week) into ~/.cache/tv-project/content.json

Needs "tmdb": {"apiKey": "<v3 API key>"} in ~/.config/tv-project/secrets.json (see trakt.py).
The API response is cached in ~/.cache/tv-project/tmdb-trending.json and reused for 6 hours; posters (w500) are
cached in ~/.cache/tv-project/images/. Without a key, or offline without a cache, content.json is left alone,
so the last row (or the placeholder row) stays.
"""
import json
import sys
import time

from trakt import CACHE, TMDB_API, TMDB_IMAGES, colors, download, fetch_json, secrets, update_content

MAX_AGE = 6 * 3600
MAX_ITEMS = 20
RAW = CACHE / "tmdb-trending.json"


def api_key():
    try:
        return secrets().get("tmdb", {}).get("apiKey")
    except (OSError, ValueError):
        return None


def results():
    """Trending results: the cache while it is fresh, else the API (cache refreshed), else a stale cache; or None."""
    fresh = RAW.exists() and time.time() - RAW.stat().st_mtime < MAX_AGE
    if not fresh and api_key():
        data = fetch_json("%s/3/trending/all/week?api_key=%s" % (TMDB_API, api_key()))
        if data and isinstance(data.get("results"), list):
            CACHE.mkdir(parents=True, exist_ok=True)
            tmp = RAW.with_suffix(".tmp")
            tmp.write_text(json.dumps(data))
            tmp.replace(RAW)
    try:
        return json.loads(RAW.read_text())["results"]
    except (OSError, ValueError, KeyError):
        return None


def trending(results):
    """Poster tiles (films and series with a poster), in TMDb's order."""
    items = []
    for r in results:
        kind = r.get("media_type")
        if kind not in ("movie", "tv") or not r.get("poster_path"):
            continue
        year = (r.get("release_date") or r.get("first_air_date") or "")[:4]
        item = {
            "id": "tmdb-%s-%d" % (kind, r["id"]),
            "title": r.get("title") or r.get("name") or "",
            "meta": ("Film" if kind == "movie" else "Series") + (" · " + year if year else ""),
            "colors": colors("%s-%d" % (kind, r["id"])),
        }
        image = download(TMDB_IMAGES + "/t/p/w500" + r["poster_path"], "tmdb-%s-%d-poster.jpg" % (kind, r["id"]))
        if image:
            item["image"] = image
        items.append(item)
        if len(items) == MAX_ITEMS:
            break
    return items


def main():
    data = results()
    if data is None:
        print("tmdb: no API key and no cached trending list; keeping content.json", file=sys.stderr)
        return
    items = trending(data)
    if items:
        print(f"tmdb: wrote {update_content({'trending': items})}")


if __name__ == "__main__":
    main()
