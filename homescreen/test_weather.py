#!/usr/bin/env python3
"""Runs weather.py against a local mock of api.met.no. Usage: python3 test_weather.py"""
import json
import os
import subprocess
import sys
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)


def step(hours, temperature, symbol):
    return {"time": (now + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "data": {"instant": {"details": {"air_temperature": temperature}},
                     "next_1_hours": {"summary": {"symbol_code": symbol}}}}


FORECAST = {"properties": {"timeseries": [step(-1, 5.0, "rain"), step(0, 9.4, "clearsky_day"), step(1, 11.0, "fog")]}}
requests = []
expires = {"value": now - timedelta(minutes=1)}  # already expired: weather.py may ask again


class MockMet(BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append((self.path, self.headers.get("If-Modified-Since"), self.headers.get("User-Agent")))
        if self.path.endswith(".svg"):
            self.send_response(200)
            self.end_headers()
            return self.wfile.write(b"<svg/>")
        not_modified = self.headers.get("If-Modified-Since") == "Wed, 28 Oct 2026 08:00:00 GMT"
        self.send_response(304 if not_modified else 200)
        self.send_header("Expires", format_datetime(expires["value"], usegmt=True))
        self.send_header("Last-Modified", "Wed, 28 Oct 2026 08:00:00 GMT")
        self.end_headers()
        if not not_modified:
            self.wfile.write(json.dumps(FORECAST).encode())

    def log_message(self, *args):
        pass


def main():
    server = HTTPServer(("127.0.0.1", 0), MockMet)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home = Path(tempfile.mkdtemp())
    (home / "config/tv-project").mkdir(parents=True)
    (home / "config/tv-project/secrets.json").write_text(json.dumps({"location": {"lat": 59.913868, "lon": 10.752245}}))
    api = "http://127.0.0.1:%d" % server.server_port
    env = dict(os.environ, MET_API=api, MET_ICONS=api + "/icons", XDG_CONFIG_HOME=str(home / "config"),
               XDG_CACHE_HOME=str(home / "cache"))
    out = home / "cache/tv-project/weather.json"

    def run():
        res = subprocess.run([sys.executable, str(Path(__file__).with_name("weather.py"))], env=env,
                             capture_output=True, text=True, timeout=30)
        assert res.returncode == 0, res.stderr

    run()
    weather = json.loads(out.read_text())
    assert (weather["temperature"], weather["symbol"]) == (9, "clearsky_day"), weather  # current hour, not the first
    assert weather["icon"] == (home / "cache/tv-project/weather-icons/clearsky_day.svg").as_uri()
    assert requests[0][0] == "/weatherapi/locationforecast/2.0/compact?lat=59.9139&lon=10.7522"
    assert requests[0][2].startswith("tv-project/") and requests[0][1] is None

    requests.clear()
    run()  # expired: asks again with If-Modified-Since, gets 304, keeps the data, no icon download
    assert [r[1] for r in requests] == ["Wed, 28 Oct 2026 08:00:00 GMT"], requests
    assert json.loads(out.read_text())["temperature"] == 9

    expires["value"] = now + timedelta(hours=1)
    run()  # stores the new Expires
    requests.clear()
    run()  # not expired yet: no request at all
    assert requests == [], requests
    print("ok")


if __name__ == "__main__":
    main()
