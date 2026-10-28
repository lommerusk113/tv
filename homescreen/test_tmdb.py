#!/usr/bin/env python3
"""Runs tmdb.py against a local mock of the TMDb API. Usage: python3 test_tmdb.py [--keep DIR]

--keep DIR leaves the fake XDG config/cache in DIR, to look at the row in the prototype:
  XDG_CACHE_HOME=DIR/cache python3 run.py
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def png(width, height, top, bottom):
    """A vertical gradient PNG, so the posters are real images the home screen can draw."""
    rows = b"".join(
        b"\x00" + bytes(round(t + (b - t) * y / (height - 1)) for t, b in zip(top, bottom)) * width
        for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


RESULTS = [
    {"media_type": "movie", "id": 11, "title": "Midnight Run", "release_date": "2026-09-12", "poster_path": "/a.png"},
    {"media_type": "tv", "id": 22, "name": "Glass Tower", "first_air_date": "2025-01-03", "poster_path": "/b.png"},
    {"media_type": "person", "id": 33, "name": "Some Actor", "profile_path": "/p.png"},
    {"media_type": "movie", "id": 44, "title": "No Poster", "release_date": "2026-01-01", "poster_path": None},
    {"media_type": "tv", "id": 55, "name": "Salt", "poster_path": "/c.png"},
]
FILES = {
    "/t/p/w500/a.png": png(100, 150, (200, 40, 80), (40, 10, 30)),
    "/t/p/w500/b.png": png(100, 150, (90, 140, 200), (20, 30, 60)),
    "/t/p/w500/c.png": png(100, 150, (60, 170, 160), (10, 40, 40)),
}
requests, offline = [], [False]


class Mock(BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        if offline[0]:
            return self.send_error(503)
        if self.path == "/3/trending/all/week?api_key=tk":
            body, kind = json.dumps({"page": 1, "results": RESULTS}).encode(), "application/json"
        elif self.path in FILES:
            body, kind = FILES[self.path], "image/png"
        else:
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    keep = sys.argv[sys.argv.index("--keep") + 1] if "--keep" in sys.argv else None
    server = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d" % server.server_port
    home = Path(keep or tempfile.mkdtemp())
    env = dict(os.environ, XDG_CONFIG_HOME=str(home / "config"), XDG_CACHE_HOME=str(home / "cache"),
               TMDB_API=url, TMDB_IMAGES=url)
    cache = home / "cache/tv-project"

    def run():
        res = subprocess.run([sys.executable, str(Path(__file__).with_name("tmdb.py"))], env=env,
                             capture_output=True, text=True, timeout=60)
        assert res.returncode == 0, res.stderr
        return res

    # No secrets.json: nothing is written, nothing is requested.
    assert "no API key" in run().stderr
    assert not (cache / "content.json").exists() and not requests

    # With a key: the trending row is merged into content.json next to trakt.py's keys.
    (home / "config/tv-project").mkdir(parents=True, exist_ok=True)
    (home / "config/tv-project/secrets.json").write_text(json.dumps({"tmdb": {"apiKey": "tk"}}))
    cache.mkdir(parents=True, exist_ok=True)
    (cache / "content.json").write_text(json.dumps({"upNext": [{"id": "kept"}]}))
    run()
    content = json.loads((cache / "content.json").read_text())
    assert content["upNext"] == [{"id": "kept"}], content
    items = content["trending"]
    assert [i["title"] for i in items] == ["Midnight Run", "Glass Tower", "Salt"], items
    assert [i["meta"] for i in items] == ["Film · 2026", "Series · 2025", "Series"], items
    assert [i["id"] for i in items] == ["tmdb-movie-11", "tmdb-tv-22", "tmdb-tv-55"], items
    poster = cache / "images/tmdb-movie-11-poster.jpg"
    assert items[0]["image"] == poster.as_uri() and poster.read_bytes() == FILES["/t/p/w500/a.png"]
    assert all(len(i["colors"]) == 3 for i in items)

    # Within 6 hours: the cached response and posters are reused, no requests at all.
    requests.clear()
    run()
    assert not requests, requests

    # Stale cache and TMDb down: the stale list is used, the row stays.
    old = time.time() - 7 * 3600
    os.utime(cache / "tmdb-trending.json", (old, old))
    offline[0] = True
    requests.clear()
    run()
    assert requests == ["/3/trending/all/week?api_key=tk"], requests
    assert json.loads((cache / "content.json").read_text())["trending"] == items

    server.shutdown()
    print("ok" + (f" (kept {home})" if keep else ""))


if __name__ == "__main__":
    main()
