#!/usr/bin/env python3
"""Moonlight game streaming for the home screen (Sunshine/Apollo hosts). Standard library only.

  python3 moonlight.py                 writes the moonlightApps key ("Games" row: the host's apps) into
                                       ~/.cache/tv-project/content.json; nothing without a paired host
  python3 moonlight.py stream [app] [--wait]   streams the app (default: config tileApp), fullscreen; --wait returns
                                       once the picture arrives (Moonlight's output goes to ~/.cache/tv-project/moonlight.log)
  python3 moonlight.py pair <host> <pin>   pairs once: type the PIN on Sunshine's web page (https://<host>:47990, PIN);
                                       on success the host is saved in config/moonlight.json
  python3 moonlight.py quit            ends the stream on this computer (Ctrl+Alt+Shift+Q via ydotool, the remote's
                                       exit button); the game keeps running on the PC

Moonlight is the Flatpak com.moonlight_stream.Moonlight (CLI: list/stream/pair/quit).
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from trakt import colors, update_content

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "config/moonlight.json"
MOONLIGHT = ["flatpak", "run", "com.moonlight_stream.Moonlight"]
LOG = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/moonlight.log"
WAIT_SECONDS = 120  # Wolf starts the app's container first: Steam takes 15-40 s
YDOTOOL_SOCKET = "/run/user/%d/.ydotool_socket" % os.getuid()
KEYS = {"ctrl": 29, "alt": 56, "shift": 42, "q": 16}


def config():
    return json.loads(CONFIG.read_text())


def apps(host):
    """App names on the host, one per line from `moonlight list` (its --csv mode hangs against Wolf)."""
    res = subprocess.run(MOONLIGHT + ["list", host], capture_output=True, text=True, timeout=180)  # Wolf is slow
    if res.returncode != 0:
        raise RuntimeError((res.stderr.strip().splitlines() or ["moonlight list failed"])[-1])
    return [line.strip() for line in res.stdout.splitlines() if line.strip()]


def tile(name):
    return {"id": "moonlight-" + name, "title": name, "meta": "Game streaming", "colors": colors("moonlight" + name),
            "action": "moonlight_stream:" + name}


def stream(app=None, wait=False):
    """Starts the stream. With wait: returns once the first video arrives (exit 0, prints "ready"), or exits 1 with
    the reason (no picture within WAIT_SECONDS, Moonlight quit, connection error); the home screen keeps its loading
    screen up meanwhile (Moonlight's own windows are hidden by kwin/hide-moonlight.js)."""
    conf = config()
    if not conf.get("host"):
        sys.exit("moonlight: no host paired yet (moonlight.py pair <host> <pin>)")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    command = MOONLIGHT + ["stream", conf["host"], app or conf.get("tileApp", "Desktop")] + conf.get("options", [])

    def launch():
        with open(LOG, "w") as log:
            return subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)

    proc = launch()
    if not wait:
        return
    deadline, retried = time.monotonic() + WAIT_SECONDS, False
    while time.monotonic() < deadline:
        text = LOG.read_text(errors="replace")
        if "Received first video packet" in text:
            print("ready")
            return
        failed = next((l for l in text.splitlines() if "Connection terminated" in l or "Starting RTSP handshake failed" in l), None)
        if failed or proc.poll() is not None:
            # Right after a stream ended, Wolf may still be tearing the old session down: the resume gets no picture
            # (-100). One more try a few seconds later usually works.
            if not retried:
                retried = True
                subprocess.run(["flatpak", "kill", "com.moonlight_stream.Moonlight"], capture_output=True, timeout=15)
                time.sleep(5)
                proc = launch()
                continue
            sys.exit("moonlight: could not start the stream" + (" (%s)" % failed.split(" - ")[-1] if failed else ""))
        time.sleep(0.3)
    sys.exit("moonlight: no picture from %s after %d s" % (conf["host"], WAIT_SECONDS))


def pair(host, pin):
    res = subprocess.run(MOONLIGHT + ["pair", host, "--pin", pin], capture_output=True, text=True, timeout=600)  # time to find Wolf's link and type the PIN
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
    wait = "--wait" in args
    args = [a for a in args if a != "--wait"]
    if args[:1] == ["stream"] and len(args) <= 2:
        return stream(args[1] if len(args) == 2 else None, wait)
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
