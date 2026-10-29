#!/usr/bin/env python3
"""Where the TV is, for the weather (the laptop has no GPS). Standard library only.

  python3 location.py          when "Use my location" is on and the position is older than a day (or missing):
                               look it up again (the home screen runs this before weather.py)
  python3 location.py now      look it up now
  python3 location.py on|off   the Settings switch (on = look it up now)
  python3 location.py status   {"auto", "accuracy" (m), "source" (wifi|ip), "updated"} as JSON

Lookup: BeaconDB (https://beacondb.net, open Wi-Fi location service; the user chose it 2026-10-29): the BSSIDs of the
Wi-Fi networks around (nmcli scan) plus considerIp, so it falls back to an IP-based position (~25 km) while it does
not know the networks. Result in secrets.json "location": {lat, lon, auto, accuracy, source, updated}.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
SECRETS = CONFIG / "secrets.json"
API = os.environ.get("BEACONDB_URL", "https://api.beacondb.net/v1/geolocate")
MAX_AGE = 86400


def load():
    try:
        return json.loads(SECRETS.read_text())
    except (OSError, ValueError):
        return {}


def save(data):
    CONFIG.mkdir(parents=True, exist_ok=True)
    tmp = SECRETS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.chmod(tmp, 0o600)
    tmp.replace(SECRETS)


def access_points():
    res = subprocess.run(["nmcli", "-t", "-f", "BSSID,SIGNAL", "device", "wifi", "list", "--rescan", "yes"],
                         capture_output=True, text=True, timeout=40)
    aps = []
    for line in res.stdout.splitlines():
        parts = re.split(r"(?<!\\):", line)
        if len(parts) >= 2 and parts[0]:
            # nmcli gives 0-100 %; the API wants dBm (roughly -100 .. -50)
            aps.append({"macAddress": parts[0].replace("\\:", ":"), "signalStrength": -100 + int(parts[1] or 0) // 2})
    return aps


def locate():
    body = {"considerIp": True, "wifiAccessPoints": access_points()}
    req = urllib.request.Request(API, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "tv-project/1.0"})
    with urllib.request.urlopen(req, timeout=20) as res:
        answer = json.load(res)
    data = load()
    data["location"] = {"lat": round(answer["location"]["lat"], 4), "lon": round(answer["location"]["lng"], 4),
                        "auto": True, "accuracy": round(answer.get("accuracy") or 0),
                        "source": "ip" if answer.get("fallback") == "ipf" else "wifi", "updated": int(time.time())}
    save(data)
    return status()


def status():
    loc = load().get("location") or {}
    return {"auto": bool(loc.get("auto")), "accuracy": loc.get("accuracy"), "source": loc.get("source"),
            "updated": loc.get("updated"), "set": "lat" in loc}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd == "status":
            out = status()
        elif cmd in ("now", "on"):
            out = locate()
        elif cmd == "off":
            data = load()
            data.pop("location", None)  # off = no position stored any more (the weather disappears)
            save(data)
            out = status()
        elif cmd == "":
            loc = load().get("location") or {}
            if loc.get("auto") and time.time() - loc.get("updated", 0) > MAX_AGE:
                locate()
            return
        else:
            sys.exit(__doc__)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"error": "location lookup failed: %s" % e}))
        sys.exit(1)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
