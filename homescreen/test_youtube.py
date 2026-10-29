#!/usr/bin/env python3
"""Runs youtube.py against a local mock of YouTube's channel /videos pages. Usage: python3 test_youtube.py"""
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import youtube
from test_tmdb import png


def lockup(video_id, title, age_label, duration=None, kind="LOCKUP_CONTENT_TYPE_VIDEO"):
    badges = [{"thumbnailBadgeViewModel": {"text": duration}}] if duration else []
    return {"lockupViewModel": {
        "contentId": video_id, "contentType": kind,
        "contentImage": {"thumbnailViewModel": {"overlays": [{"thumbnailBottomOverlayViewModel": {"badges": badges}}]}},
        "metadata": {"lockupMetadataViewModel": {"title": {"content": title}, "metadata": {"contentMetadataViewModel": {
            "metadataRows": [{"metadataParts": [{"text": {"content": "1.1M"}, "accessibilityLabel": "1.1 million views"},
                                                {"text": {"content": "x"}, "accessibilityLabel": age_label}]}]}}}},
    }}


def page(*lockups):
    data = {"contents": {"tabs": [{"richGridRenderer": {"contents": [{"richItemRenderer": {"content": l}} for l in lockups]}}]}}
    return ("<html><script>var ytInitialData = %s;</script></html>" % json.dumps(data)).encode()


PAGES = {
    "/channel/UCaaaaaaaaaaaaaaaaaaaaaa/videos": page(
        lockup("aaaaaaaaaa1", "Fresh one", "5 hours ago", "12:03"),
        lockup("aaaaaaaaaa2", "Older", "2 days ago", "1:02:03"),
        lockup("aaaaaaaaaa3", "Coming soon", "Scheduled for 11/1/26"),
        lockup("shortshort1", "A short", "1 hour ago", kind="LOCKUP_CONTENT_TYPE_PLAYLIST")),
    "/channel/UCbbbbbbbbbbbbbbbbbbbbbb/videos": page(lockup("bbbbbbbbbb1", "Middle", "1 day ago", "9:12")),
}
state = {"down": False}


class Mock(BaseHTTPRequestHandler):
    def do_GET(self):
        if state["down"]:
            return self.send_error(503)
        if self.path in PAGES:
            body = PAGES[self.path]
        elif self.path.startswith("/vi/") and self.path.endswith("/mqdefault.jpg"):
            body = png(32, 18, (200, 0, 0), (40, 0, 0))
        else:
            return self.send_error(404)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    assert youtube.age_seconds("Streamed 3 days ago") == 3 * 86400 and youtube.age_seconds("Scheduled") is None
    assert youtube.ago(5 * 3600) == "5h ago" and youtube.ago(40) == "just now"

    server = HTTPServer(("127.0.0.1", 0), Mock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home = Path(tempfile.mkdtemp())
    config = home / "conf"
    url = "http://127.0.0.1:%d" % server.server_port
    # VacuumTube's debug port pointed at nothing: recommendations/history unavailable, like VacuumTube not running.
    env = dict(os.environ, XDG_CACHE_HOME=str(home / "cache"), XDG_CONFIG_HOME=str(config), YOUTUBE_URL=url,
               YOUTUBE_THUMBNAILS=url, VACUUMTUBE_DEBUG_PORT="1")
    content = home / "cache/tv-project/content.json"

    # The real config lists other channels; point a copy of the script's directory at test channels instead.
    test_dir = home / "app"
    (test_dir / "config").mkdir(parents=True)
    for f in ("youtube.py", "trakt.py", "youtube_tv.py", "youtube_tv.js"):
        (test_dir / f).write_text(Path(__file__).with_name(f).read_text())
    (test_dir / "config/youtube.json").write_text(json.dumps({"perChannel": 6, "maxItems": 20, "channels": [
        {"name": "Alpha", "id": "UCaaaaaaaaaaaaaaaaaaaaaa"}, {"name": "Beta", "id": "UCbbbbbbbbbbbbbbbbbbbbbb"}]}))
    script = test_dir / "youtube.py"

    def run_test(*args):
        res = subprocess.run([sys.executable, str(script), *args], env=env, capture_output=True, text=True, timeout=60)
        assert res.returncode == 0, res.stderr
        return res

    run_test()
    items = json.loads(content.read_text())["youtubeChannels"]
    # Newest first across channels; upcoming and non-video entries left out.
    assert [i["id"] for i in items] == ["youtube-aaaaaaaaaa1", "youtube-bbbbbbbbbb1", "youtube-aaaaaaaaaa2"], items
    assert items[0]["subtitle"] == "Alpha · 5h ago · 12:03" and items[0]["action"] == "youtube_watch:aaaaaaaaaa1"
    assert items[0]["image"].endswith("youtube-aaaaaaaaaa1.jpg") and "progress" not in items[0]
    assert "youtubeRecommended" not in json.loads(content.read_text())

    # With history/recommendations cached (as youtube_tv.py would have fetched them): progress bars and the row.
    (home / "cache/tv-project/youtube-tv.json").write_text(json.dumps({"time": 9e12, "history": [
        {"id": "bbbbbbbbbb1", "title": "Middle", "channel": "Beta", "watched": 0.5},
        {"id": "aaaaaaaaaa2", "title": "Older", "channel": "Alpha", "watched": 1}], "recommended": [
        {"id": "rrrrrrrrrr1", "title": "Picked for you", "channel": "Gamma", "watched": 0}]}))
    run_test()
    data = json.loads(content.read_text())
    # The finished one (aaaaaaaaaa2) is gone, the started one has its progress.
    assert [(i["id"], i.get("progress")) for i in data["youtubeChannels"]] == [
        ("youtube-aaaaaaaaaa1", None), ("youtube-bbbbbbbbbb1", 0.5)], data["youtubeChannels"]
    assert data["youtubeRecommended"][0]["subtitle"] == "Gamma"
    assert data["youtubeRecommended"][0]["action"] == "youtube_watch:rrrrrrrrrr1"

    # Within MAX_AGE the cache is used (YouTube down does not matter); --force with YouTube down keeps the last videos.
    state["down"] = True
    run_test()
    res = run_test("--force")
    assert "Alpha" in res.stderr
    assert [i["id"] for i in json.loads(content.read_text())["youtubeChannels"]][0] == "youtube-aaaaaaaaaa1"
    server.shutdown()
    print("ok")


if __name__ == "__main__":
    main()
