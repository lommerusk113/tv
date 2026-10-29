#!/usr/bin/env python3
"""Runs jellyfin.py against a local mock of a Jellyfin server. Usage: python3 test_jellyfin.py [--keep DIR]

--keep DIR leaves the fake XDG config/cache in DIR, to look at the row in the prototype:
  XDG_CACHE_HOME=DIR/cache python3 run.py
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

from test_tmdb import png

TICKS = 600_000_000  # one minute
ITEMS = [
    {"Id": "ep1", "Type": "Episode", "Name": "The Ice", "SeriesName": "Northern Lights", "SeriesId": "s1",
     "ParentIndexNumber": 2, "IndexNumber": 5, "RunTimeTicks": 50 * TICKS,
     "UserData": {"PlaybackPositionTicks": 20 * TICKS, "PlayedPercentage": 40.0},
     "ImageTags": {"Primary": "p1"}, "ParentThumbItemId": "s1", "ParentThumbImageTag": "t1"},
    {"Id": "mv1", "Type": "Movie", "Name": "Midnight Run", "ProductionYear": 2026, "RunTimeTicks": 110 * TICKS,
     "UserData": {"PlaybackPositionTicks": 100 * TICKS, "PlayedPercentage": 90.9},
     "ImageTags": {"Primary": "p2"}, "BackdropImageTags": ["b2"]},
    {"Id": "mv2", "Type": "Movie", "Name": "No Art", "UserData": {}},
]
NEWEST = [
    {"Id": "re1", "Type": "Movie", "Name": "Resident Evil: Retribution", "ProductionYear": 2012, "Genres": ["Action"],
     "Overview": "Alice again.", "BackdropImageTags": ["rb1"], "ImageTags": {"Logo": "rl1"}},
    {"Id": "re2", "Type": "Movie", "Name": "Resident Evil: Afterlife", "BackdropImageTags": ["rb2"]},
    {"Id": "nb", "Type": "Series", "Name": "Nobel", "ChildCount": 1, "Genres": ["Drama"], "BackdropImageTags": ["nb1"]},
    {"Id": "nobd", "Type": "Movie", "Name": "No Backdrop"},
]
FILES = {
    "/Items/s1/Images/Thumb?tag=t1&maxWidth=780&quality=90": png(160, 90, (60, 170, 160), (10, 40, 40)),
    "/Items/mv1/Images/Backdrop/0?tag=b2&maxWidth=780&quality=90": png(160, 90, (200, 40, 80), (40, 10, 30)),
    "/Items/re1/Images/Backdrop/0?tag=rb1&maxWidth=1280&quality=90": png(160, 90, (90, 20, 20), (10, 0, 0)),
    "/Items/re1/Images/Logo?tag=rl1&maxWidth=800&quality=90": png(80, 30, (255, 255, 255), (200, 200, 200)),
    "/Items/nb/Images/Backdrop/0?tag=nb1&maxWidth=1280&quality=90": png(160, 90, (20, 60, 90), (0, 10, 20)),
    "/Items/nb/Images/Primary?tag=np1&maxWidth=500&quality=90": png(60, 90, (20, 60, 90), (0, 10, 20)),
}
SEARCH = [
    {"Id": "lotr2", "Type": "Movie", "Name": "The Lord of the Rings: The Two Towers", "ProductionYear": 2002, "UserData": {}},
    {"Id": "lotr1", "Type": "Movie", "Name": "The Lord of the Rings: The Fellowship of the Ring", "ProductionYear": 2001,
     "UserData": {"PlaybackPositionTicks": 30 * TICKS}},
    {"Id": "lotr3", "Type": "Movie", "Name": "The Lord of the Rings: The Return of the King", "ProductionYear": 2003,
     "UserData": {"Played": True}},
    {"Id": "bb", "Type": "Series", "Name": "Breaking Bad", "UserData": {}},
    {"Id": "bbe", "Type": "Episode", "Name": "Breaking Bad Habits", "UserData": {}},
    {"Id": "potc2", "Type": "Movie", "Name": "Pirates of the Caribbean: Dead Man's Chest", "UserData": {}},
    {"Id": "kfh", "Type": "Movie", "Name": "Kung Fu Hustle", "UserData": {}},
]
NEXT_UP = {"bb": [{"Id": "bb-s2e3", "Type": "Episode", "Name": "Bit by a Dead Bee", "ParentIndexNumber": 2, "IndexNumber": 3,
                   "UserData": {}}]}
state = {"new_api": True, "down": False, "requests": [], "sessions": [], "posts": []}


class Mock(BaseHTTPRequestHandler):
    def do_GET(self):
        state["requests"].append(self.path)
        if state["down"]:
            return self.send_error(503)
        if not self.path.startswith("/Items/"):
            assert 'Token="jk"' in self.headers.get("Authorization", ""), self.headers
        if self.path == "/Users":
            body = json.dumps([{"Name": "Joakim", "Id": "u1"}, {"Name": "Guest", "Id": "u2"}]).encode()
        elif self.path.startswith("/UserItems/Resume?userId=u1&") and state["new_api"]:
            body = json.dumps({"Items": ITEMS}).encode()
        elif self.path.startswith("/Users/u1/Items/Resume?") and not state["new_api"]:
            body = json.dumps({"Items": ITEMS[:1]}).encode()
        elif self.path.startswith("/Items?userId=u1&searchTerm="):
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)["searchTerm"][0].lower()
            # Like Jellyfin: the exact text must appear in the name (so "deadmans chest" finds nothing by itself).
            body = json.dumps({"Items": [i for i in SEARCH if query in i["Name"].lower()]}).encode()
        elif self.path.startswith("/Shows/NextUp?"):
            series = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("seriesId", [None])[0]
            body = json.dumps({"Items": NEXT_UP.get(series, []) if series else NEXT_UP["bb"]}).encode()
        elif self.path.startswith("/Items?userId=u1&includeItemTypes=Movie%2CSeries&"):
            body = json.dumps({"Items": NEWEST}).encode()
        elif self.path.startswith("/Items/Latest?userId=u1&"):
            body = json.dumps([{"Id": "nb", "Type": "Series", "Name": "Nobel", "ProductionYear": 2016,
                                "ImageTags": {"Primary": "np1"}},
                               {"Id": "re1", "Type": "Movie", "Name": "Resident Evil: Retribution"},
                               {"Id": "x1", "Type": "Season", "Name": "Season 1"}]).encode()
        elif self.path.startswith("/Items/lotr1?userId=u1"):
            body = json.dumps(SEARCH[1]).encode()
        elif self.path.startswith("/Sessions?controllableByUserId=u1"):
            body = json.dumps(state["sessions"]).encode()
        elif self.path in FILES:
            body = FILES[self.path]
        else:
            return self.send_error(404)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        assert 'Token="jk"' in self.headers.get("Authorization", ""), self.headers
        state["posts"].append(self.path)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


def main():
    keep = sys.argv[sys.argv.index("--keep") + 1] if "--keep" in sys.argv else None
    server = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home = Path(keep or tempfile.mkdtemp())
    # The mock never reports the video as playing, so do not wait for it.
    env = dict(os.environ, XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"), JELLYFIN_START_WAIT="0")
    cache, config = home / "cache/tv-project", home / "config/tv-project"

    def run(*args):
        res = subprocess.run([sys.executable, str(Path(__file__).with_name("jellyfin.py")), *args], env=env,
                             capture_output=True, text=True, timeout=60)
        return res

    def play(title):
        res = run("play", *title.split())
        assert res.returncode == 0, res.stderr
        return json.loads(res.stdout)

    # Not configured: nothing written.
    assert run().returncode == 0 and not (cache / "content.json").exists()

    config.mkdir(parents=True, exist_ok=True)
    secrets = {"jellyfin": {"url": "http://127.0.0.1:%d/" % server.server_port, "apiKey": "jk"}}
    # Two users and no "user": a clear error, nothing written.
    (config / "secrets.json").write_text(json.dumps(secrets))
    res = run()
    assert res.returncode != 0 and "Joakim, Guest" in res.stderr, res.stderr
    assert not (cache / "content.json").exists()

    secrets["jellyfin"]["user"] = "joakim"
    (config / "secrets.json").write_text(json.dumps(secrets))
    cache.mkdir(parents=True, exist_ok=True)
    (cache / "content.json").write_text(json.dumps({"upNext": [{"id": "kept"}]}))
    assert run().returncode == 0
    content = json.loads((cache / "content.json").read_text())
    assert content["upNext"] == [{"id": "kept"}]
    items = content["jellyfinResume"]
    images = cache / "images"
    assert items[0] == {"id": "jellyfin-ep1", "title": "Northern Lights", "subtitle": "S2 E5 · The Ice · 30 min left",
                        "colors": items[0]["colors"], "app": "jellyfin", "action": "jellyfin_play_id:ep1", "progress": 0.4,
                        "image": (images / "jellyfin-s1-thumb-t1.jpg").as_uri()}, items[0]
    assert items[1]["subtitle"] == "2026 · 10 min left" and items[1]["progress"] == 0.909
    assert items[1]["image"] == (images / "jellyfin-mv1-backdrop-b2.jpg").as_uri()
    assert items[2]["title"] == "No Art" and "image" not in items[2] and "progress" not in items[2]
    # Up next: the next episode of each series; banner: newest with a backdrop, one per franchise, logo when there is one.
    assert [i["action"] for i in content["jellyfinNextUp"]] == ["jellyfin_play_id:bb-s2e3"]
    # Continue watching = started (ep1, mv1, mv2) then next episodes of other series (bb); one per series.
    import jellyfin
    assert [jellyfin.episode_label(i) for i in ({"ParentIndexNumber": 2, "IndexNumber": 5}, {"IndexNumber": 19}, {})] == ["S2 E5", "E19", ""]
    two = [{"Id": "e1", "SeriesId": "S"}, {"Id": "e2", "SeriesId": "S"}, {"Id": "m"}]
    assert [i["Id"] for i in jellyfin.continue_watching(two, [{"Id": "e3", "SeriesId": "S"}, {"Id": "x", "SeriesId": "T"}])] == ["e1", "m", "x"]
    assert [i["id"] for i in content["jellyfinContinue"]] == ["jellyfin-ep1", "jellyfin-mv1", "jellyfin-mv2", "jellyfin-bb-s2e3"]
    hero = content["jellyfinFeatured"]
    assert [h["title"] for h in hero] == ["Resident Evil: Retribution", "Nobel"], hero
    assert hero[0]["meta"] == "Film · Action · 2012" and hero[0]["description"] == "Alice again."
    assert hero[0]["image"] == (images / "jellyfin-re1-backdrop1280-rb1.jpg").as_uri() and "logo" in hero[0]
    assert hero[1]["meta"] == "Series · Drama · 1 season" and "logo" not in hero[1]
    assert hero[1]["action"] == "jellyfin_play_id:nb"
    # Recently added: posters for films and series only.
    latest = content["jellyfinLatest"]
    assert [(i["title"], i["meta"]) for i in latest] == [("Nobel", "Series · 2016"), ("Resident Evil: Retribution", "Film")]
    assert latest[0]["image"].endswith("jellyfin-nb-poster-np1.jpg") and "image" not in latest[1]
    assert latest[0]["action"] == "jellyfin_play_id:nb"

    # Older server (no /UserItems/Resume): falls back to /Users/{id}/Items/Resume.
    state["new_api"] = False
    assert run().returncode == 0
    assert [i["id"] for i in json.loads((cache / "content.json").read_text())["jellyfinResume"]] == ["jellyfin-ep1"]

    # Play by title. No Jellyfin Desktop connected: gives up after PLAY_WAIT (shortened via the env).
    env["JELLYFIN_PLAY_WAIT"] = "1"
    out = play("lord of the rings")
    assert out == {"ok": False, "error": "Jellyfin Desktop is not connected to the server"}, out
    state["sessions"] = [
        {"Id": "phone", "Client": "Jellyfin Android", "DeviceName": "Pixel", "LastActivityDate": "2026-10-28T23:00:00Z"},
        {"Id": "other", "Client": "Jellyfin Desktop", "DeviceName": "office-pc", "LastActivityDate": "2026-10-28T23:10:00Z"},
        {"Id": "here", "Client": "Jellyfin Desktop", "DeviceName": socket.gethostname(), "LastActivityDate": "2026-10-28T22:00:00Z"},
    ]
    # Three close matches: the one in progress wins and resumes.
    assert play("lord of the rings") == {"ok": True, "title": "The Lord of the Rings: The Fellowship of the Ring"}
    assert state["posts"][-1] == "/Sessions/here/Playing?playCommand=PlayNow&itemIds=lotr1&startPositionTicks=%d" % (30 * TICKS)
    # A series plays its next-up episode from the start.
    assert play("breaking bad") == {"ok": True, "title": "Breaking Bad S2 E3"}
    assert state["posts"][-1] == "/Sessions/here/Playing?playCommand=PlayNow&itemIds=bb-s2e3&startPositionTicks=0"
    # Misheard titles (whisper): found through single words and fuzzy matching.
    assert play("deadmans chest") == {"ok": True, "title": "Pirates of the Caribbean: Dead Man's Chest"}
    assert play("kung fu hustling") == {"ok": True, "title": "Kung Fu Hustle"}
    # Move to TV: the phone's episode stops there and continues here at the same position.
    res = run("pull")
    assert json.loads(res.stdout) == {"ok": False, "error": "nothing is playing on another device"}, res.stdout
    state["sessions"].append({"Id": "phone2", "Client": "Jellyfin Android", "DeviceName": "Pixel",
                              "LastActivityDate": "2026-10-28T23:20:00Z", "PlayState": {"PositionTicks": 12 * TICKS},
                              "NowPlayingItem": {"Id": "ep9", "Type": "Episode", "Name": "Pilot", "SeriesName": "Northern Lights",
                                                 "ParentIndexNumber": 1, "IndexNumber": 1}})
    res = run("playing")
    assert json.loads(res.stdout) == {"ok": True, "title": "Northern Lights S1 E1", "from": "Pixel"}, res.stdout
    assert len(state["posts"]) == 4  # playing only looks
    res = run("pull")
    assert json.loads(res.stdout) == {"ok": True, "title": "Northern Lights S1 E1", "from": "Pixel"}, res.stdout
    assert state["posts"][-2:] == ["/Sessions/phone2/Playing/Stop",
                                   "/Sessions/here/Playing?playCommand=PlayNow&itemIds=ep9&startPositionTicks=%d" % (12 * TICKS)]
    state["sessions"].pop()
    # A tile: play by id (resumes the started film).
    res = run("play-id", "lotr1")
    assert json.loads(res.stdout) == {"ok": True, "title": "The Lord of the Rings: The Fellowship of the Ring"}, res.stdout
    assert state["posts"][-1] == "/Sessions/here/Playing?playCommand=PlayNow&itemIds=lotr1&startPositionTicks=%d" % (30 * TICKS)
    # find: what play would start, without starting it.
    posts = len(state["posts"])
    res = run("find", "lord", "of", "the", "rings")
    assert json.loads(res.stdout) == {"ok": True, "id": "lotr1", "title": "The Lord of the Rings: The Fellowship of the Ring"}
    assert json.loads(run("find", "zzz").stdout)["ok"] is False and len(state["posts"]) == posts
    out = play("zzz qqq")
    assert out["ok"] is False and "nothing called" in out["error"], out
    assert len(state["posts"]) == 7

    # Server down: the last row stays.
    before = (cache / "content.json").read_text()
    state["down"] = True
    res = run()
    assert res.returncode == 0 and "keeping content.json" in res.stderr, res.stderr
    assert (cache / "content.json").read_text() == before

    server.shutdown()
    print("ok" + (f" (kept {home})" if keep else ""))


if __name__ == "__main__":
    main()
