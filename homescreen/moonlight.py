#!/usr/bin/env python3
"""Moonlight game streaming for the home screen (Sunshine/Apollo hosts). Standard library only.

  python3 moonlight.py                 writes the moonlightApps key ("Games" row: the host's apps) into
                                       ~/.cache/tv-project/content.json; nothing without a paired host
  python3 moonlight.py stream [app]    streams the app (default: config tileApp) straight away, fullscreen
  python3 moonlight.py pair <host> <pin>   pairs once: type the PIN on Sunshine's web page (https://<host>:47990, PIN);
                                       on success the host is saved in config/moonlight.json
  python3 moonlight.py quit            ends the stream on this computer (Ctrl+Alt+Shift+Q via ydotool, the remote's
                                       exit button); the game keeps running on the PC

Moonlight is the Flatpak com.moonlight_stream.Moonlight (CLI: list/stream/pair/quit).
"""
import csv
import io
import json
import os
import subprocess
import sys
from pathlib import Path

from trakt import colors, update_content

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "config/moonlight.json"
MOONLIGHT = ["flatpak", "run", "com.moonlight_stream.Moonlight"]
YDOTOOL_SOCKET = "/run/user/%d/.ydotool_socket" % os.getuid()
KEYS = {"ctrl": 29, "alt": 56, "shift": 42, "q": 16}


def config():
    return json.loads(CONFIG.read_text())


def apps(host):
    """App names on the host, from `moonlight list --csv` (first column, header skipped)."""
    res = subprocess.run(MOONLIGHT + ["list", host, "--csv"], capture_output=True, text=True, timeout=60)
    if res.returncode != 0:
        raise RuntimeError((res.stderr.strip().splitlines() or ["moonlight list failed"])[-1])
    rows = list(csv.reader(io.StringIO(res.stdout)))
    return [r[0] for r in rows[1:] if r and r[0]]


def tile(name):
    return {"id": "moonlight-" + name, "title": name, "meta": "Game streaming", "colors": colors("moonlight" + name),
            "action": "moonlight_stream:" + name}


def stream(app=None):
    conf = config()
    if not conf.get("host"):
        sys.exit("moonlight: no host paired yet (moonlight.py pair <host> <pin>)")
    subprocess.Popen(MOONLIGHT + ["stream", conf["host"], app or conf.get("tileApp", "Desktop")] + conf.get("options", []),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def pair(host, pin):
    res = subprocess.run(MOONLIGHT + ["pair", host, "--pin", pin], capture_output=True, text=True, timeout=180)
    out = (res.stdout + res.stderr).strip()
    if res.returncode != 0:
        sys.exit("moonlight: pairing failed: " + (out.splitlines() or ["?"])[-1])
    conf = config()
    conf["host"] = host
    CONFIG.write_text(json.dumps(conf, indent=2, ensure_ascii=False) + "\n")
    print("moonlight: paired with", host)


def quit_stream():
    env = dict(os.environ, YDOTOOL_SOCKET=YDOTOOL_SOCKET)
    if not os.path.exists(YDOTOOL_SOCKET):
        subprocess.Popen(["ydotoold", "-p", YDOTOOL_SOCKET, "-P", "0600"], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        subprocess.run(["sleep", "0.5"])
    down = ["%d:1" % KEYS[k] for k in ("ctrl", "alt", "shift", "q")]
    up = ["%d:0" % KEYS[k] for k in ("q", "shift", "alt", "ctrl")]
    subprocess.run(["ydotool", "key", *down, *up], env=env, capture_output=True, timeout=10)


def main():
    args = sys.argv[1:]
    if args[:1] == ["stream"] and len(args) <= 2:
        return stream(args[1] if len(args) == 2 else None)
    if args[:1] == ["pair"] and len(args) == 3 and args[2].isdigit() and len(args[2]) == 4:
        return pair(args[1], args[2])
    if args == ["quit"]:
        return quit_stream()
    if args:
        sys.exit(__doc__)
    host = config().get("host")
    if not host:
        print("moonlight: no host paired yet; keeping content.json", file=sys.stderr)
        return
    try:
        names = apps(host)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
        print(f"moonlight: {host}: {e}; keeping content.json", file=sys.stderr)
        return
    print(f"moonlight: wrote {update_content({'moonlightApps': [tile(n) for n in names]})}")


if __name__ == "__main__":
    main()
