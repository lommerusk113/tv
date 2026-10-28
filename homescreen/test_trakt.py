#!/usr/bin/env python3
"""Runs trakt.py auth + sync against a local mock of the Trakt API. Usage: python3 test_trakt.py"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def show(trakt_id, title):
    return {"title": title, "ids": {"trakt": trakt_id, "slug": title.lower().replace(" ", "-")}}


def episode(trakt_id, season, number, title):
    return {"season": season, "number": number, "title": title, "ids": {"trakt": trakt_id}}


GET = {
    "/users/hidden/progress_watched?type=show&limit=1000": [{"type": "show", "show": show(4, "Hidden Show")}],
    "/users/hidden/dropped?type=show&limit=1000": [],
    "/sync/playback/episodes": [
        {"progress": 40.0, "paused_at": "2026-10-01T20:00:00.000Z", "episode": episode(101, 1, 3, "Old Pause"),
         "show": show(1, "Harbour Street")},
        {"progress": 65.5, "paused_at": "2026-10-20T20:00:00.000Z", "episode": episode(201, 2, 5, "The Ice"),
         "show": show(2, "Northern Lights")},
    ],
    "/sync/watched/shows?extended=noseasons": [
        {"show": show(2, "Northern Lights")},  # also paused: must appear once, as the paused episode
        {"show": show(3, "Kitchen Nights")},
        {"show": show(4, "Hidden Show")},
        {"show": show(5, "Finished Show")},
        {"show": show(1, "Harbour Street")},
    ],
    "/shows/1/progress/watched": {"next_episode": episode(102, 1, 4, "Next")},
    "/shows/2/progress/watched": {"next_episode": episode(202, 2, 6, "After Ice")},
    "/shows/3/progress/watched": {"next_episode": episode(301, 4, 2, None)},
    "/shows/5/progress/watched": {"next_episode": None},
}
polls = []


class MockTrakt(BaseHTTPRequestHandler):
    def reply(self, status, body=None):
        self.send_response(status)
        self.end_headers()
        if body is not None:
            self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        assert self.headers["trakt-api-key"] == "cid" and self.headers["trakt-api-version"] == "2"
        if self.headers["Authorization"] != "Bearer fresh-token":
            return self.reply(401)
        self.reply(200, GET[self.path]) if self.path in GET else self.reply(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/oauth/device/code":
            self.reply(200, {"device_code": "dev", "user_code": "ABCD1234", "verification_url": "https://trakt.tv/activate",
                             "expires_in": 30, "interval": 1})
        elif self.path == "/oauth/device/token":
            polls.append(body)
            # pending once, then an already expired token, so sync has to refresh it
            self.reply(400) if len(polls) == 1 else self.reply(200, {
                "access_token": "old-token", "refresh_token": "refresh", "expires_in": 86400, "created_at": int(time.time()) - 86400})
        elif self.path == "/oauth/token":
            assert body["grant_type"] == "refresh_token" and body["refresh_token"] == "refresh"
            self.reply(200, {"access_token": "fresh-token", "refresh_token": "refresh2", "expires_in": 7776000,
                             "created_at": int(time.time())})
        else:
            self.reply(404)

    def log_message(self, *args):
        pass


def main():
    server = HTTPServer(("127.0.0.1", 0), MockTrakt)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home = Path(tempfile.mkdtemp())
    (home / "config/tv-project").mkdir(parents=True)
    (home / "config/tv-project/secrets.json").write_text(json.dumps({"trakt": {"clientId": "cid", "clientSecret": "secret"}}))
    env = dict(os.environ, TRAKT_API="http://127.0.0.1:%d" % server.server_port,
               XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"))
    script = Path(__file__).with_name("trakt.py")

    def run(cmd):
        res = subprocess.run([sys.executable, str(script), cmd], env=env, capture_output=True, text=True, timeout=30)
        assert res.returncode == 0, res.stderr
        return res.stdout

    assert "ABCD1234" in run("auth")
    assert polls[-1] == {"code": "dev", "client_id": "cid", "client_secret": "secret"}
    assert oct((home / "config/tv-project/trakt-token.json").stat().st_mode & 0o777) == "0o600"

    run("sync")
    items = json.loads((home / "cache/tv-project/content.json").read_text())["upNext"]
    assert [i["title"] for i in items] == ["Northern Lights", "Harbour Street", "Kitchen Nights"], items
    assert items[0]["subtitle"] == "S2 E5 · The Ice" and items[0]["progress"] == 0.655
    assert items[1]["subtitle"] == "S1 E3 · Old Pause"
    assert items[2]["subtitle"] == "S4 E2" and "progress" not in items[2]
    assert all(len(i["colors"]) == 3 and i["id"].startswith("trakt-episode-") for i in items)
    assert json.loads((home / "config/tv-project/trakt-token.json").read_text())["access_token"] == "fresh-token"
    print("ok")


if __name__ == "__main__":
    main()
