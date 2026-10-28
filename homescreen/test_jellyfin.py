#!/usr/bin/env python3
"""Runs jellyfin.py against a local mock of a Jellyfin server. Usage: python3 test_jellyfin.py [--keep DIR]

--keep DIR leaves the fake XDG config/cache in DIR, to look at the row in the prototype:
  XDG_CACHE_HOME=DIR/cache python3 run.py
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
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
FILES = {
    "/Items/s1/Images/Thumb?tag=t1&maxWidth=780&quality=90": png(160, 90, (60, 170, 160), (10, 40, 40)),
    "/Items/mv1/Images/Backdrop/0?tag=b2&maxWidth=780&quality=90": png(160, 90, (200, 40, 80), (40, 10, 30)),
}
state = {"new_api": True, "down": False, "requests": []}


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
        elif self.path in FILES:
            body = FILES[self.path]
        else:
            return self.send_error(404)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    keep = sys.argv[sys.argv.index("--keep") + 1] if "--keep" in sys.argv else None
    server = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home = Path(keep or tempfile.mkdtemp())
    env = dict(os.environ, XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"))
    cache, config = home / "cache/tv-project", home / "config/tv-project"

    def run():
        res = subprocess.run([sys.executable, str(Path(__file__).with_name("jellyfin.py"))], env=env,
                             capture_output=True, text=True, timeout=60)
        return res

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
                        "colors": items[0]["colors"], "app": "jellyfin", "progress": 0.4,
                        "image": (images / "jellyfin-s1-thumb-t1.jpg").as_uri()}, items[0]
    assert items[1]["subtitle"] == "2026 · 10 min left" and items[1]["progress"] == 0.909
    assert items[1]["image"] == (images / "jellyfin-mv1-backdrop-b2.jpg").as_uri()
    assert items[2]["title"] == "No Art" and "image" not in items[2] and "progress" not in items[2]

    # Older server (no /UserItems/Resume): falls back to /Users/{id}/Items/Resume.
    state["new_api"] = False
    assert run().returncode == 0
    assert [i["id"] for i in json.loads((cache / "content.json").read_text())["jellyfinResume"]] == ["jellyfin-ep1"]

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
