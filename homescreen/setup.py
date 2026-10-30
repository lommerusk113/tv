#!/usr/bin/env python3
"""First-time setup in the terminal: connects the services this home screen can use and switches their tiles on.

  python3 homescreen/setup.py          go through every service (Enter skips one; run it again any time)
  python3 homescreen/setup.py status   only show what is set up

Everything is saved outside the repo: keys in ~/.config/tv-project/secrets.json (mode 600), tile changes in
~/.config/tv-project/apps.json, YouTube channels in youtube.json (tvconfig.py). Each answer is tested before it is
saved. Nothing here needs sudo. Standard library only.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import tvconfig

HERE = Path(__file__).resolve().parent
SECRETS = tvconfig.USER / "secrets.json"
FLATPAKS = {"jellyfin": "org.jellyfin.JellyfinDesktop", "youtube": "rocks.shy.VacuumTube",
            "moonlight": "com.moonlight_stream.Moonlight", "chrome": "com.google.Chrome"}


def secrets():
    try:
        return json.loads(SECRETS.read_text())
    except (OSError, ValueError):
        return {}


def save_secret(key, value):
    data = secrets()
    data[key] = value
    SECRETS.parent.mkdir(parents=True, exist_ok=True)
    tmp = SECRETS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(SECRETS)


def show_tile(app_id, shown=True):
    tvconfig.update_user("apps", [{"id": app_id, "hidden": not shown}])


def ask(question, default=""):
    try:
        answer = input(f"{question}{f' [{default}]' if default else ''}: ").strip()
    except EOFError:
        answer = ""
    return answer or default


def confirm(question, default=False):
    answer = ask(question + (" (Y/n)" if default else " (y/N)")).lower()
    return answer.startswith("y") if answer else default


def get_json(url, headers=None, timeout=8):
    req = urllib.request.Request(url, headers={"Accept": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read() or b"null")


def flatpak_installed(app):
    return shutil.which("flatpak") is not None and subprocess.run(
        ["flatpak", "info", app], capture_output=True).returncode == 0


def step(title):
    print(f"\n== {title}")


def apps():
    step("Apps")
    for app_id, flatpak in FLATPAKS.items():
        ok = flatpak_installed(flatpak)
        print(f"  {'✓' if ok else '✗'} {flatpak}" + ("" if ok else f"   install: flatpak install flathub {flatpak}"))
        if app_id in ("jellyfin", "youtube", "moonlight"):
            show_tile(app_id, ok)
    if flatpak_installed(FLATPAKS["chrome"]) and confirm("Show the RiksTV tile (Norwegian TV, needs a RiksTV account)?"):
        show_tile("rikstv")


def jellyfin():
    step("Jellyfin (your media server: Continue watching, Recently added, voice \"play …\")")
    old = secrets().get("jellyfin", {})
    url = ask("Server address, e.g. http://192.168.1.10:8096 (Enter skips)", old.get("url", "")).rstrip("/")
    if not url:
        return
    key = ask("API key (Jellyfin Dashboard -> API Keys -> +)", old.get("apiKey", ""))
    try:
        users = get_json(url + "/Users", {"X-Emby-Token": key})
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"  ✗ could not use that server/key: {e}")
        return
    names = [u["Name"] for u in users]
    user = names[0] if len(names) == 1 else ask(f"Which user ({', '.join(names)})", old.get("user", names[0]))
    save_secret("jellyfin", {"url": url, "apiKey": key, "user": user})
    print(f"  ✓ Jellyfin connected as {user}")


def jellyseerr():
    step("Jellyseerr / Overseerr (request films and series: the Jellyseerr page, \"Get more\", voice \"download …\")")
    old = secrets().get("jellyseerr", {})
    url = ask("Address, e.g. http://192.168.1.10:5055 (Enter skips)", old.get("url", "")).rstrip("/")
    if not url:
        return
    key = ask("API key (Jellyseerr Settings -> General -> API Key)", old.get("apiKey", ""))
    try:
        me = get_json(url + "/api/v1/auth/me", {"X-Api-Key": key})
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"  ✗ could not use that address/key: {e}")
        return
    save_secret("jellyseerr", {"url": url, "apiKey": key})
    show_tile("jellyseerr")
    print(f"  ✓ Jellyseerr connected (requests are made as {me.get('displayName') or me.get('email') or 'the key owner'})")


def trakt():
    step("Trakt (recommendations, the banner, Up next)")
    old = secrets().get("trakt", {})
    print("  Create an API app at https://trakt.tv/oauth/applications/new (redirect URI: http://localhost).")
    client = ask("Client ID (Enter skips)", old.get("clientId", ""))
    if not client:
        return
    save_secret("trakt", {**old, "clientId": client})
    subprocess.run([sys.executable, str(HERE / "trakt.py"), "auth"])  # shows a code for trakt.tv/activate


def openai():
    step("AI voice commands (OpenAI; optional: without it voice uses simple rules + local whisper)")
    old = secrets().get("openai", {})
    key = ask("OpenAI API key (Enter skips)", old.get("apiKey", ""))
    if not key:
        return
    try:
        get_json("https://api.openai.com/v1/models", {"Authorization": "Bearer " + key})
    except (urllib.error.URLError, OSError, ValueError) as e:
        print(f"  ✗ that key did not work: {e}")
        return
    save_secret("openai", {"apiKey": key})
    print("  ✓ AI voice on (gpt-5-mini; change models in ~/.config/tv-project/voice.json \"agent\")")


def tv():
    step("LG TV on/off (webOS 3+, on the same network; Wake-on-LAN must be on in the TV's settings)")
    if not confirm("Look for an LG TV on the network?", default=bool(secrets().get("tv"))):
        return
    sys.path.insert(0, str(HERE))
    import tvpower
    ip = tvpower.discover() or ask("None answered. Its IP address (Enter skips)")
    if not ip:
        return
    neigh = subprocess.run(["ip", "neigh", "show", ip], capture_output=True, text=True).stdout.split()
    mac = neigh[neigh.index("lladdr") + 1] if "lladdr" in neigh else ask("Its MAC address (TV network settings)")
    hdmi = ask("Which HDMI input is this computer on (1-4)", "1")
    save_secret("tv", {"ip": ip, "mac": mac, "input": "HDMI_" + hdmi.strip()})
    print(f"  TV at {ip}. Accept the prompt on the TV now…")
    subprocess.run([sys.executable, str(HERE / "tvpower.py"), "pair"])


def moonlight():
    step("Game streaming (Moonlight to a PC running Sunshine, Apollo or Wolf)")
    if not flatpak_installed(FLATPAKS["moonlight"]):
        print("  Moonlight is not installed (see Apps above); skipped.")
        return
    conf = tvconfig.load("moonlight")
    host = ask("The gaming PC's name or IP (Enter skips)", conf.get("host", ""))
    if not host:
        return
    if host != conf.get("host"):
        pin = ask("A 4-digit PIN to pair with (enter it on the host: Sunshine web UI -> PIN)", "1234")
        res = subprocess.run([sys.executable, str(HERE / "moonlight.py"), "pair", host, pin])
        if res.returncode != 0:
            return
    tile = ask("App the Moonlight tile starts (Sunshine: Desktop, Wolf: Wolf UI)", conf.get("tileApp", "Desktop"))
    tvconfig.update_user("moonlight", {"host": host, "tileApp": tile})
    if confirm("Show a Steam tile (starts the host's \"Steam\" app directly)?"):
        show_tile("steam")


def youtube():
    step("YouTube channels (a \"New from your channels\" row)")
    print("  Channel ids start with UC (youtube.com/@name -> About -> Share -> Copy channel ID).")
    ids = ask("Channel ids, separated by spaces (Enter skips)")
    if not ids:
        return
    channels = [{"name": i, "id": i} for i in ids.split() if i.startswith("UC")]
    tvconfig.update_user("youtube", {"channels": channels})
    print(f"  ✓ {len(channels)} channel(s); names come from YouTube on the next refresh")


def status():
    s = secrets()
    shown = [a["id"] for a in tvconfig.load("apps")]
    print("Tiles shown: " + ", ".join(shown))
    for name, ok in [("Jellyfin", "jellyfin" in s), ("Jellyseerr", "jellyseerr" in s), ("Trakt", "trakt" in s),
                     ("AI voice (OpenAI)", "openai" in s), ("LG TV", "tv" in s),
                     ("Game streaming", bool(tvconfig.load("moonlight").get("host"))),
                     ("YouTube channels", bool(tvconfig.load("youtube").get("channels")))]:
        print(f"  {'✓' if ok else '·'} {name}")


def main():
    if sys.argv[1:] == ["status"]:
        status()
        return
    if sys.argv[1:]:
        sys.exit(__doc__)
    print("TV home screen setup. Press Enter to skip anything you don't use; run this again any time.")
    for part in (apps, jellyfin, jellyseerr, trakt, openai, tv, moonlight, youtube):
        try:
            part()
        except KeyboardInterrupt:
            print("\n  (skipped)")
    print()
    status()
    print("\nRestart the home screen to see the changes (log out and in, or see README: Install).")


if __name__ == "__main__":
    main()
