#!/usr/bin/env python3
"""Moonlight game streaming for the home screen (Sunshine/Apollo hosts). Standard library only.

  python3 moonlight.py                 writes the moonlightApps key ("Games" row: the host's apps) into
                                       ~/.cache/tv-project/content.json; nothing without a paired host
  python3 moonlight.py stream [app] [--wait]   streams the app (default: config tileApp), fullscreen; --wait returns
                                       once the picture arrives (Moonlight's output goes to ~/.cache/tv-project/moonlight.log)
  python3 moonlight.py pair <host> <pin>   pairs once: type the PIN on Sunshine's web page (https://<host>:47990, PIN);
                                       on success the host is saved in ~/.config/tv-project/moonlight.json
  python3 moonlight.py stop            Home: closes Moonlight now and quits the app on the host after
                                       keepRunningMinutes (config; at least 10 s); a new start in between cancels that
  python3 moonlight.py wake            mouse wiggle into the stream (wakes Steam's screensaver; done after a start)
  python3 moonlight.py status          {"ok", "reachable", "running" (app name or ""), "profile", "profiles"}: the Steam
                                       tile's badge and Settings (a paired HTTPS serverinfo, with Moonlight's own
                                       client certificate, so the host tells which app runs)
  python3 moonlight.py profile <name>  stream quality from now on (config "profiles": options added to "options"),
                                       saved in ~/.config/tv-project/moonlight.json
  python3 moonlight.py quit            ends the stream on this computer (Ctrl+Alt+Shift+Q via ydotool, the remote's
                                       exit button); the game keeps running on the PC

Moonlight is the Flatpak com.moonlight_stream.Moonlight (CLI: list/stream/pair/quit).
"""
import json
import os
import re
import ssl
import subprocess
import tempfile
import urllib.request
import uuid
import sys
import time
from pathlib import Path

from trakt import colors, update_content
import tvconfig

HERE = Path(__file__).resolve().parent
MOONLIGHT = ["flatpak", "run", "com.moonlight_stream.Moonlight"]
PENDING_STOP = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/moonlight-stop.pid"
STOP_DELAY = 10  # minimum seconds between ending the stream and quitting the app (sooner hung Wolf)
WAITER = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/moonlight-wait.pid"
LOG = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/moonlight.log"
WAIT_SECONDS = 120  # Wolf starts the app's container first: Steam takes 15-40 s
YDOTOOL_SOCKET = "/run/user/%d/.ydotool_socket" % os.getuid()
KEYS = {"ctrl": 29, "alt": 56, "shift": 42, "q": 16}


def config():
    return tvconfig.load("moonlight")


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
    cancel_pending_stop()
    # The quality profile comes after "options": Moonlight takes the last value of an option given twice.
    command = (MOONLIGHT + ["stream", conf["host"], app or conf.get("tileApp", "Desktop")] + conf.get("options", [])
               + conf.get("profiles", {}).get(conf.get("profile", ""), []))

    def launch():
        with open(LOG, "w") as log:
            return subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)

    proc = launch()
    if not wait:
        return
    WAITER.write_text(str(os.getpid()))
    deadline, retried = time.monotonic() + WAIT_SECONDS, False
    while time.monotonic() < deadline:
        text = LOG.read_text(errors="replace")
        if "Received first video packet" in text:
            # A fresh start (Wolf: /launch, not /resume) still shows the app booting/updating inside the stream (Steam's
            # update window): keep the loading screen up a little longer (config bootSeconds per app).
            boot = conf.get("bootSeconds", {}).get(app or conf.get("tileApp", ""), 0)
            if boot and "/launch?" in text:
                time.sleep(boot)
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
    tvconfig.update_user("moonlight", {"host": host})  # ~/.config/tv-project/moonlight.json
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


def cancel_waiter():
    """Ends a `stream --wait` that is still waiting (pid in WAITER), so its retry does not start Moonlight again."""
    try:
        pid = int(WAITER.read_text())
        if pid != os.getpid():
            os.kill(pid, 15)
    except (OSError, ValueError):
        pass
    WAITER.unlink(missing_ok=True)


def wake():
    """A tiny mouse wiggle into the stream: Steam's idle screensaver ignores keys (the remote) but wakes on the mouse."""
    env = dict(os.environ, YDOTOOL_SOCKET=YDOTOOL_SOCKET)
    for dx, dy in ((12, 8), (-12, -8)):
        subprocess.run(["ydotool", "mousemove", "--", str(dx), str(dy)], env=env, capture_output=True, timeout=10)
        time.sleep(0.15)


def stop():
    """Home: end the stream now, and quit the app on the host (Wolf stops its container, e.g. Steam; unsaved game
    progress is lost) STOP_DELAY seconds later, in a detached `stop-later` process. Quitting in the same instant as
    the stream drops hung Wolf (2026-10-29: HTTPS API dead until restart); with the stream already gone it works.
    A new start within the delay cancels the pending quit (stream() -> cancel_pending_stop)."""
    cancel_waiter()  # a start still waiting for its picture must not retry once Moonlight is gone
    subprocess.run(["flatpak", "kill", "com.moonlight_stream.Moonlight"], capture_output=True, timeout=15)
    if config().get("host") and config().get("keepRunningMinutes", 0) >= 0:  # < 0: the server's watchdog decides
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "stop-later"], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


def stop_later():
    PENDING_STOP.write_text(str(os.getpid()))
    # Keep the app warm for a while: coming back within keepRunningMinutes is a resume (~2 s instead of ~45 s).
    time.sleep(max(STOP_DELAY, 60 * config().get("keepRunningMinutes", 0)))
    if PENDING_STOP.exists() and PENDING_STOP.read_text() == str(os.getpid()):
        PENDING_STOP.unlink(missing_ok=True)
        subprocess.run(MOONLIGHT + ["quit", config()["host"]], capture_output=True, timeout=90)


def cancel_pending_stop():
    """A new stream start: the app must keep running, so drop a quit that is still waiting."""
    try:
        pid = int(PENDING_STOP.read_text())
        os.kill(pid, 15)
    except (OSError, ValueError):
        pass
    PENDING_STOP.unlink(missing_ok=True)


MOONLIGHT_CONF = (Path.home() / ".var/app/com.moonlight_stream.Moonlight/config/Moonlight Game Streaming Project"
                  / "Moonlight.conf")


def moonlight_settings():
    """Moonlight's client certificate, key, unique id and the host's app ids -> names, from its Qt settings file."""
    text = MOONLIGHT_CONF.read_text()

    def pem(key):
        m = re.search(r'^%s="?@ByteArray\((.*?)\)"?$' % key, text, re.M)
        return m.group(1).replace("\\n", "\n").encode() if m else None
    apps = {}
    for num, value in re.findall(r"^\d+\\apps\\(\d+)\\id=(\d+)$", text, re.M):
        name = re.search(r"^\d+\\apps\\%s\\name=(.*)$" % num, text, re.M)
        apps[value] = name.group(1) if name else value
    unique = re.search(r"^uniqueid=(\w+)$", text, re.M)
    return pem("certificate"), pem("key"), unique.group(1) if unique else "0123456789ABCDEF", apps


def serverinfo(host, timeout=4):
    """The host's serverinfo XML over paired HTTPS (state and currentgame are only real there); plain HTTP when
    Moonlight's certificate cannot be read. The key is written to a private temporary file for ssl and deleted."""
    query = "?uniqueid=%s&uuid=%s"
    try:
        cert, key, unique, apps = moonlight_settings()
    except OSError:
        cert = key = None
        unique, apps = "0123456789ABCDEF", {}
    if cert and key:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE  # the host's certificate is self-signed (Moonlight pins it itself)
        with tempfile.NamedTemporaryFile("wb", dir=os.environ.get("XDG_RUNTIME_DIR"), suffix=".pem") as f:
            os.chmod(f.name, 0o600)
            f.write(cert + b"\n" + key)
            f.flush()
            context.load_cert_chain(f.name)
        url = "https://%s:47984/serverinfo" % host + query % (unique, uuid.uuid4())
        with urllib.request.urlopen(url, timeout=timeout, context=context) as res:
            return res.read().decode(errors="replace"), apps
    with urllib.request.urlopen("http://%s:47989/serverinfo" % host + query % (unique, uuid.uuid4()),
                                timeout=timeout) as res:
        return res.read().decode(errors="replace"), apps


def status():
    conf = config()
    out = {"ok": bool(conf.get("host")), "reachable": False, "running": "", "profile": conf.get("profile", ""),
           "profiles": list(conf.get("profiles", {}))}
    if not conf.get("host"):
        return out
    try:
        xml, apps = serverinfo(conf["host"])
    except (OSError, ssl.SSLError, ValueError):
        return out
    out["reachable"] = True
    game = re.search(r"<currentgame>(\d+)</currentgame>", xml)
    if game and game.group(1) != "0":
        out["running"] = apps.get(game.group(1), "a game")
    return out


def set_profile(name):
    if name not in config().get("profiles", {}):
        return {"ok": False, "error": "no stream profile called %s" % name}
    tvconfig.update_user("moonlight", {"profile": name})
    return {"ok": True, "profile": name}


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
    if args == ["stop"]:
        return stop()
    if args == ["stop-later"]:
        return stop_later()
    if args == ["cancel"]:
        cancel_waiter()
        return subprocess.run(["flatpak", "kill", "com.moonlight_stream.Moonlight"], capture_output=True, timeout=15)
    if args == ["wake"]:
        return wake()
    if args == ["status"]:
        return print(json.dumps(status(), ensure_ascii=False))
    if args[:1] == ["profile"] and len(args) >= 2:
        return print(json.dumps(set_profile(" ".join(args[1:])), ensure_ascii=False))
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
