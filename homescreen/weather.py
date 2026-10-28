#!/usr/bin/env python3
"""Current weather from MET Norway (Yr) for the top bar. Standard library only.

  python3 weather.py   writes ~/.cache/tv-project/weather.json: {"temperature", "symbol", "icon", ...}

Location from ~/.config/tv-project/secrets.json: {"location": {"lat": 59.91, "lon": 10.75}} (not in the repo).
Follows api.met.no's terms: identifying User-Agent, no request before the previous response's Expires,
If-Modified-Since. Icons: Yr's weather symbols (MIT, github.com/metno/weathericons), downloaded once per symbol.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

API = os.environ.get("MET_API", "https://api.met.no")
ICONS = os.environ.get("MET_ICONS", "https://raw.githubusercontent.com/metno/weathericons/main/weather/svg")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project"
OUT = CACHE / "weather.json"
USER_AGENT = "tv-project/1.0 https://github.com/lommerusk113/tv"


def now_entry(timeseries, now):
    """The forecast step for the current hour: the last one that has started, else the first."""
    started = [t for t in timeseries if datetime.fromisoformat(t["time"].replace("Z", "+00:00")) <= now]
    return (started or timeseries)[-1 if started else 0]


def icon(symbol):
    """file:// URL of the Yr SVG for a symbol code, downloaded once; None on failure."""
    path = CACHE / "weather-icons" / (symbol + ".svg")
    if not path.exists():
        try:
            with urllib.request.urlopen(f"{ICONS}/{symbol}.svg", timeout=20) as res:
                data = res.read()
        except (urllib.error.URLError, OSError) as e:
            print(f"weather: icon {symbol}: {e}", file=sys.stderr)
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return path.as_uri()


def main():
    location = json.loads((CONFIG / "secrets.json").read_text()).get("location")
    if not location:
        sys.exit('weather: no "location": {"lat", "lon"} in secrets.json')
    old = json.loads(OUT.read_text()) if OUT.exists() else {}
    now = datetime.now(timezone.utc)
    if old.get("expires") and parsedate_to_datetime(old["expires"]) > now:
        return  # MET asks clients not to ask again before Expires

    # MET wants at most 4 decimals (better caching on their side)
    url = "%s/weatherapi/locationforecast/2.0/compact?lat=%.4f&lon=%.4f" % (API, location["lat"], location["lon"])
    headers = {"User-Agent": USER_AGENT}
    if old.get("lastModified"):
        headers["If-Modified-Since"] = old["lastModified"]
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as res:
            forecast = json.loads(res.read())
            expires, last_modified = res.headers.get("Expires"), res.headers.get("Last-Modified")
    except urllib.error.HTTPError as e:
        if e.code != 304 or not old.get("timeseries"):
            sys.exit(f"weather: {e}")
        forecast = {"properties": {"timeseries": old["timeseries"]}}  # unchanged: re-pick the current hour
        expires, last_modified = e.headers.get("Expires"), old.get("lastModified")
    except (urllib.error.URLError, OSError, ValueError) as e:
        sys.exit(f"weather: {e}")

    timeseries = forecast["properties"]["timeseries"]
    entry = now_entry(timeseries, now)
    symbol = (entry["data"].get("next_1_hours") or entry["data"].get("next_6_hours") or {}).get("summary", {}).get("symbol_code")
    weather = {
        "temperature": round(entry["data"]["instant"]["details"]["air_temperature"]),
        "symbol": symbol,
        "icon": icon(symbol) if symbol else None,
        "time": entry["time"],
        "expires": expires,
        "lastModified": last_modified,
        "timeseries": timeseries[:48],  # kept for 304 responses; two days is plenty
    }
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text(json.dumps(weather))
    tmp.replace(OUT)
    print(f"weather: {weather['temperature']}° {symbol}")


if __name__ == "__main__":
    main()
