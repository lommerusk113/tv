#!/usr/bin/env python3
"""Trakt "Up next" for the home screen. Standard library only.

  python3 trakt.py auth   one-time login: shows a code to enter at trakt.tv/activate, saves the token
  python3 trakt.py sync   writes the upNext row and the featured hero (recommendations) to
                          ~/.cache/tv-project/content.json (overrides data/placeholder.json)

Needs ~/.config/tv-project/secrets.json:
  {"trakt": {"clientId": "..."}, "tmdb": {"apiKey": "..."}, "fanart": {"apiKey": "...", "clientKey": "..."}}
(create an API app at https://trakt.tv/oauth/applications/new, redirect URI http://localhost: new apps only allow
localhost and get no client secret; the device-code login used here needs only the client id. "clientSecret" is
still sent when an older app has one.)
tmdb (v3 API key) is optional: backdrops, and the hero needs it. fanart (fanart.tv key, clientKey optional) is optional:
title logos in the hero. Images are cached in ~/.cache/tv-project/images/.
The token goes to ~/.config/tv-project/trakt-token.json (mode 600). Neither file is in the repo.
"""
import colorsys
import fcntl
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = os.environ.get("TRAKT_API", "https://api.trakt.tv")
TMDB_API = os.environ.get("TMDB_API", "https://api.themoviedb.org")
TMDB_IMAGES = os.environ.get("TMDB_IMAGES", "https://image.tmdb.org")
FANART_API = os.environ.get("FANART_API", "https://webservice.fanart.tv")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project"
TOKEN = CONFIG / "trakt-token.json"
MAX_ITEMS = 15


def secrets():
    return json.loads((CONFIG / "secrets.json").read_text())


def request(path, body=None, token=None):
    """Returns (status, parsed JSON or None)."""
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "tv-project/1.0",
        "trakt-api-version": "2",
        "trakt-api-key": secrets()["trakt"]["clientId"],
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            text = res.read()
            return res.status, json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        return e.code, None


def fetch_json(url):
    """Parsed JSON from a third-party API (TMDb, fanart.tv); None on any failure, which only costs artwork."""
    try:
        with urllib.request.urlopen(url, timeout=20) as res:
            return json.loads(res.read())
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"trakt: {url.split('?')[0]}: {e}", file=sys.stderr)
        return None


def download(url, name):
    """file:// URL of ~/.cache/tv-project/images/<name>, downloaded from url once; None on failure."""
    path = CACHE / "images" / name
    if not path.exists():
        try:
            with urllib.request.urlopen(url, timeout=30) as res:
                data = res.read()
        except (urllib.error.URLError, OSError) as e:
            print(f"trakt: {url}: {e}", file=sys.stderr)
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
    return path.as_uri()


def tmdb_show(show):
    """TMDb details of a Trakt show; None without a TMDb key or id."""
    key = secrets().get("tmdb", {}).get("apiKey")
    tmdb_id = show["ids"].get("tmdb")
    return fetch_json("%s/3/tv/%d?api_key=%s" % (TMDB_API, tmdb_id, key)) if key and tmdb_id else None


def backdrop(show):
    """file:// URL of the show's TMDb backdrop (w780, for tiles); the API is only asked until it is cached."""
    name = "tmdb-tv-%s.jpg" % show["ids"].get("tmdb")
    if (CACHE / "images" / name).exists():
        return (CACHE / "images" / name).as_uri()
    details = tmdb_show(show)
    if not details or not details.get("backdrop_path"):
        return None
    return download(TMDB_IMAGES + "/t/p/w780" + details["backdrop_path"], name)


def logo(show):
    """file:// URL of the show's fanart.tv HD logo (else clear logo), English or textless first, most liked."""
    keys = secrets().get("fanart", {})
    tvdb_id = show["ids"].get("tvdb")
    if not keys.get("apiKey") or not tvdb_id:
        return None
    name = "fanart-tv-%d-logo.png" % tvdb_id
    if (CACHE / "images" / name).exists():
        return (CACHE / "images" / name).as_uri()
    query = "api_key=" + keys["apiKey"] + ("&client_key=" + keys["clientKey"] if keys.get("clientKey") else "")
    data = fetch_json("%s/v3/tv/%d?%s" % (FANART_API, tvdb_id, query)) or {}
    logos = data.get("hdtvlogo") or data.get("clearlogo") or []
    logos = [l for l in logos if l.get("lang") in ("en", "00", "")] or logos
    if not logos:
        return None
    return download(max(logos, key=lambda l: int(l.get("likes") or 0))["url"], name)


def featured(recommendations, limit=5):
    """Hero items: recommended shows with a TMDb backdrop (w1280), genre/seasons line, overview, fanart.tv logo."""
    items = []
    for show in recommendations:
        details = tmdb_show(show)
        image = details and details.get("backdrop_path") and download(
            TMDB_IMAGES + "/t/p/w1280" + details["backdrop_path"], "tmdb-tv-%d-w1280.jpg" % show["ids"]["tmdb"])
        if not image:
            continue
        seasons = details.get("number_of_seasons")
        meta = ["Series"] + [g["name"] for g in details.get("genres", [])[:1]]
        if seasons:
            meta.append("%d season%s" % (seasons, "" if seasons == 1 else "s"))
        item = {
            "id": "trakt-show-%d" % show["ids"]["trakt"],
            "title": show["title"],
            "meta": " · ".join(meta),
            "description": details.get("overview") or "",
            "colors": colors(show["ids"]["slug"]),
            "image": image,
        }
        show_logo = logo(show)
        if show_logo:
            item["logo"] = show_logo
        items.append(item)
        if len(items) == limit:
            break
    return items


def save_token(token):
    CONFIG.mkdir(parents=True, exist_ok=True)
    TOKEN.touch(mode=0o600)
    TOKEN.write_text(json.dumps(token))


def auth():
    s = secrets()["trakt"]
    status, code = request("/oauth/device/code", {"client_id": s["clientId"]})
    if status != 200:
        sys.exit(f"trakt: device code request failed ({status})")
    print(f"Go to {code['verification_url']} and enter: {code['user_code']}", flush=True)

    interval = code["interval"]
    deadline = time.time() + code["expires_in"]
    while time.time() < deadline:
        time.sleep(interval)
        status, token = request("/oauth/device/token", with_secret(s, {
            "code": code["device_code"], "client_id": s["clientId"],
        }))
        if status == 200:
            save_token(token)
            print(f"trakt: logged in, token saved to {TOKEN}")
            return
        if status == 429:
            interval += 1
        elif status != 400:  # 400 = still waiting for the user
            sys.exit(f"trakt: login failed ({status}: 404 invalid, 409 used, 410 expired, 418 denied)")
    sys.exit("trakt: code expired, run auth again")


def with_secret(s, body):
    """Adds client_secret for older Trakt apps; apps created since 2026 are PKCE-only and get no secret."""
    if s.get("clientSecret"):
        body["client_secret"] = s["clientSecret"]
    return body


def access_token():
    """The saved access token, refreshed when it expires within a day."""
    if not TOKEN.exists():
        sys.exit("trakt: not logged in, run: python3 trakt.py auth")
    token = json.loads(TOKEN.read_text())
    if token["created_at"] + token["expires_in"] - time.time() > 86400:
        return token["access_token"]

    s = secrets()["trakt"]
    status, fresh = request("/oauth/token", with_secret(s, {
        "refresh_token": token["refresh_token"], "client_id": s["clientId"],
        "redirect_uri": s.get("redirectUri", "http://localhost"), "grant_type": "refresh_token",
    }))
    if status != 200:
        sys.exit(f"trakt: token refresh failed ({status}), run: python3 trakt.py auth")
    save_token(fresh)
    return fresh["access_token"]


def update_content(updates):
    """Merges updates into ~/.cache/tv-project/content.json; each script (trakt.py, tmdb.py) owns its own keys.

    Locked, because the home screen runs the scripts at the same time, and atomic, so it never reads half a file.
    """
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / "content.json"
    with open(CACHE / "content.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            content = json.loads(out.read_text())
        except (OSError, ValueError):
            content = {}
        content.update(updates)
        tmp = out.with_suffix(".tmp")
        tmp.write_text(json.dumps(content, ensure_ascii=False, indent=1))
        tmp.replace(out)
    return out


def colors(seed):
    """Stable placeholder gradient [base, dark, highlight] per show, until there is artwork."""
    hue = int(hashlib.md5(seed.encode()).hexdigest()[:4], 16) / 0xFFFF

    def hex_color(h, lightness, saturation):
        r, g, b = colorsys.hls_to_rgb(h % 1, lightness, saturation)
        return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))

    return [hex_color(hue, 0.4, 0.6), hex_color(hue + 0.05, 0.14, 0.6), hex_color(hue - 0.04, 0.68, 0.9)]


def tile(show, episode, progress=None, image=None):
    item = {
        "id": "trakt-episode-%d" % episode["ids"]["trakt"],
        "title": show["title"],
        "subtitle": "S%d E%d" % (episode["season"], episode["number"])
                    + (" · " + episode["title"] if episode.get("title") else ""),
        "colors": colors(show["ids"]["slug"]),
    }
    if progress is not None:
        item["progress"] = round(progress / 100, 3)
    if image:
        item["image"] = image
    return item


def up_next(playback, watched, next_episodes, hidden, image_for=lambda show: None):
    """Paused episodes first (newest first), then the next episode of each recently watched show.

    playback: /sync/playback/episodes, watched: /sync/watched/shows (newest first),
    next_episodes: show trakt id -> next_episode from /shows/{id}/progress/watched (None when caught up),
    hidden: show trakt ids hidden from progress or dropped, image_for: show -> image URL or None.
    """
    items, seen = [], set()
    for p in sorted(playback, key=lambda p: p["paused_at"], reverse=True):
        show_id = p["show"]["ids"]["trakt"]
        if show_id not in seen and show_id not in hidden:
            seen.add(show_id)
            items.append(tile(p["show"], p["episode"], p["progress"], image_for(p["show"])))
    for w in watched:
        show_id = w["show"]["ids"]["trakt"]
        episode = next_episodes.get(show_id)
        if show_id not in seen and show_id not in hidden and episode:
            seen.add(show_id)
            items.append(tile(w["show"], episode, image=image_for(w["show"])))
            if len(items) == MAX_ITEMS:
                break
    return items[:MAX_ITEMS]


def sync():
    token = access_token()

    def get(path):
        status, data = request(path, token=token)
        if status != 200:
            sys.exit(f"trakt: GET {path} failed ({status})")
        return data

    hidden = {h["show"]["ids"]["trakt"]
              for section in ("progress_watched", "dropped")
              for h in get(f"/users/hidden/{section}?type=show&limit=1000")}
    playback = get("/sync/playback/episodes")
    watched = [w for w in get("/sync/watched/shows?extended=noseasons")
               if w["show"]["ids"]["trakt"] not in hidden][:MAX_ITEMS * 2]
    # ponytail: one progress request per recent show (~30), fine for Trakt's 1000 GET / 5 min limit
    next_episodes = {w["show"]["ids"]["trakt"]: get("/shows/%d/progress/watched" % w["show"]["ids"]["trakt"])["next_episode"]
                     for w in watched}

    out = update_content({
        "upNext": up_next(playback, watched, next_episodes, hidden, backdrop),
        # Empty (no TMDb key) hides the hero rather than showing the made-up placeholder shows.
        "featured": featured(get("/recommendations/shows?limit=10")),
    })
    print(f"trakt: wrote {out}")


if __name__ == "__main__":
    commands = {"auth": auth, "sync": sync}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]]()
