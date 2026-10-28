#!/usr/bin/env python3
"""Trakt "Up next" for the home screen. Standard library only.

  python3 trakt.py auth   one-time login: shows a code to enter at trakt.tv/activate, saves the token
  python3 trakt.py sync   writes the upNext row to ~/.cache/tv-project/content.json (overrides data/placeholder.json)

Needs ~/.config/tv-project/secrets.json: {"trakt": {"clientId": "...", "clientSecret": "..."}}
(create an API app at https://trakt.tv/oauth/applications, redirect URI urn:ietf:wg:oauth:2.0:oob).
The token goes to ~/.config/tv-project/trakt-token.json (mode 600). Neither file is in the repo.
"""
import colorsys
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = os.environ.get("TRAKT_API", "https://api.trakt.tv")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project"
TOKEN = CONFIG / "trakt-token.json"
MAX_ITEMS = 15


def secrets():
    return json.loads((CONFIG / "secrets.json").read_text())["trakt"]


def request(path, body=None, token=None):
    """Returns (status, parsed JSON or None)."""
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "tv-project/1.0",
        "trakt-api-version": "2",
        "trakt-api-key": secrets()["clientId"],
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


def save_token(token):
    CONFIG.mkdir(parents=True, exist_ok=True)
    TOKEN.touch(mode=0o600)
    TOKEN.write_text(json.dumps(token))


def auth():
    s = secrets()
    status, code = request("/oauth/device/code", {"client_id": s["clientId"]})
    if status != 200:
        sys.exit(f"trakt: device code request failed ({status})")
    print(f"Go to {code['verification_url']} and enter: {code['user_code']}", flush=True)

    interval = code["interval"]
    deadline = time.time() + code["expires_in"]
    while time.time() < deadline:
        time.sleep(interval)
        status, token = request("/oauth/device/token", {
            "code": code["device_code"], "client_id": s["clientId"], "client_secret": s["clientSecret"],
        })
        if status == 200:
            save_token(token)
            print(f"trakt: logged in, token saved to {TOKEN}")
            return
        if status == 429:
            interval += 1
        elif status != 400:  # 400 = still waiting for the user
            sys.exit(f"trakt: login failed ({status}: 404 invalid, 409 used, 410 expired, 418 denied)")
    sys.exit("trakt: code expired, run auth again")


def access_token():
    """The saved access token, refreshed when it expires within a day."""
    if not TOKEN.exists():
        sys.exit("trakt: not logged in, run: python3 trakt.py auth")
    token = json.loads(TOKEN.read_text())
    if token["created_at"] + token["expires_in"] - time.time() > 86400:
        return token["access_token"]

    s = secrets()
    status, fresh = request("/oauth/token", {
        "refresh_token": token["refresh_token"], "client_id": s["clientId"], "client_secret": s["clientSecret"],
        "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token",
    })
    if status != 200:
        sys.exit(f"trakt: token refresh failed ({status}), run: python3 trakt.py auth")
    save_token(fresh)
    return fresh["access_token"]


def colors(seed):
    """Stable placeholder gradient [base, dark, highlight] per show, until there is artwork."""
    hue = int(hashlib.md5(seed.encode()).hexdigest()[:4], 16) / 0xFFFF

    def hex_color(h, lightness, saturation):
        r, g, b = colorsys.hls_to_rgb(h % 1, lightness, saturation)
        return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))

    return [hex_color(hue, 0.4, 0.6), hex_color(hue + 0.05, 0.14, 0.6), hex_color(hue - 0.04, 0.68, 0.9)]


def tile(show, episode, progress=None):
    item = {
        "id": "trakt-episode-%d" % episode["ids"]["trakt"],
        "title": show["title"],
        "subtitle": "S%d E%d" % (episode["season"], episode["number"])
                    + (" · " + episode["title"] if episode.get("title") else ""),
        "colors": colors(show["ids"]["slug"]),
    }
    if progress is not None:
        item["progress"] = round(progress / 100, 3)
    return item


def up_next(playback, watched, next_episodes, hidden):
    """Paused episodes first (newest first), then the next episode of each recently watched show.

    playback: /sync/playback/episodes, watched: /sync/watched/shows (newest first),
    next_episodes: show trakt id -> next_episode from /shows/{id}/progress/watched (None when caught up),
    hidden: show trakt ids hidden from progress or dropped.
    """
    items, seen = [], set()
    for p in sorted(playback, key=lambda p: p["paused_at"], reverse=True):
        show_id = p["show"]["ids"]["trakt"]
        if show_id not in seen and show_id not in hidden:
            seen.add(show_id)
            items.append(tile(p["show"], p["episode"], p["progress"]))
    for w in watched:
        show_id = w["show"]["ids"]["trakt"]
        episode = next_episodes.get(show_id)
        if show_id not in seen and show_id not in hidden and episode:
            seen.add(show_id)
            items.append(tile(w["show"], episode))
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

    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / "content.json"
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps({"upNext": up_next(playback, watched, next_episodes, hidden)}, ensure_ascii=False, indent=1))
    tmp.replace(out)  # atomic, so the home screen never reads half a file
    print(f"trakt: wrote {out}")


if __name__ == "__main__":
    commands = {"auth": auth, "sync": sync}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]]()
