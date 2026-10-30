#!/usr/bin/env python3
"""Media helpers for the home screen. Standard library only (uses gdbus and flatpak).

  python3 media.py pause             pause every media player that is playing (MPRIS: Jellyfin Desktop, VacuumTube,
                                     Chrome/RiksTV), so switching apps does not leave the old one playing
  python3 media.py leave [app id]    pause (except the given app, the one being opened), close Moonlight (ends the
                                     stream; the game keeps running on the host), then send Jellyfin back to its start page (unless it is the given app,
                                     the one being opened), so it starts from there next time
  python3 media.py youtube-home      a running VacuumTube goes to YouTube's start page (and comes to the front: a
                                     link always raises VacuumTube, so this is done when opening it, not when leaving)
  python3 media.py youtube-history   open the YouTube account's watch history (newest first) to pick from
  python3 media.py youtube-watch <id>  play that YouTube video in VacuumTube (tiles of the "New from your channels" row)
  python3 media.py youtube <query>   open YouTube's search results for the query in VacuumTube (started if needed)
  python3 media.py status            {"playing": bool, "player": identity, "position": seconds | null} of the player
                                     that is playing (the sleep timer's "Still watching?" check)
"""
import json
import re
import subprocess
import sys
import urllib.parse

MPRIS = "org.mpris.MediaPlayer2."
YOUTUBE_FLATPAK = "rocks.shy.VacuumTube"
# The deeplink YouTube's TV app (leanback) understands for a search; tested with VacuumTube 2026-10.
YOUTUBE_SEARCH = "https://www.youtube.com/tv?launch=search&vq={}"
YOUTUBE_HOME = "https://www.youtube.com/tv"
YOUTUBE_HISTORY = "https://www.youtube.com/tv?c=FEhistory"
YOUTUBE_WATCH = "https://www.youtube.com/watch?v={}"
HERE = __import__("pathlib").Path(__file__).resolve().parent


def gdbus(dest, method, *args):
    return subprocess.run(["gdbus", "call", "--session", "--dest", dest, "--object-path",
                           "/org/freedesktop/DBus" if dest == "org.freedesktop.DBus" else "/org/mpris/MediaPlayer2",
                           "--method", method, *args], capture_output=True, text=True, timeout=5)


def players():
    names = gdbus("org.freedesktop.DBus", "org.freedesktop.DBus.ListNames").stdout
    return re.findall(r"'(" + re.escape(MPRIS) + r"[^']+)'", names)


# The app being opened keeps playing (it may just have been started on purpose, e.g. a Jellyfin tile or a trailer).
# Matched by the player's MPRIS Identity: VacuumTube's bus name is a generic "chromium.instanceN" (so is Chrome's).
IDENTITY_OF_APP = {"jellyfin": "Jellyfin", "youtube": "VacuumTube"}


def identity(player):
    out = gdbus(player, "org.freedesktop.DBus.Properties.Get", "org.mpris.MediaPlayer2", "Identity").stdout
    m = re.search(r"'([^']*)'", out)
    return m.group(1) if m else ""


def pause(keep=None):
    for player in players():
        if keep in IDENTITY_OF_APP and identity(player) == IDENTITY_OF_APP[keep]:
            continue
        status = gdbus(player, "org.freedesktop.DBus.Properties.Get", "org.mpris.MediaPlayer2.Player", "PlaybackStatus")
        if "Playing" in status.stdout:
            gdbus(player, "org.mpris.MediaPlayer2.Player.Pause")
            print("paused", player[len(MPRIS):])


def status():
    for player in players():
        state = gdbus(player, "org.freedesktop.DBus.Properties.Get", "org.mpris.MediaPlayer2.Player", "PlaybackStatus")
        if "Playing" not in state.stdout:
            continue
        pos = gdbus(player, "org.freedesktop.DBus.Properties.Get", "org.mpris.MediaPlayer2.Player", "Position").stdout
        m = re.search(r"(-?\d+)", pos)
        return {"playing": True, "player": identity(player), "position": int(m.group(1)) / 1e6 if m else None}
    return {"playing": False, "player": "", "position": None}


def running(flatpak_id):
    res = subprocess.run(["flatpak", "ps", "--columns=application"], capture_output=True, text=True, timeout=10)
    return flatpak_id in res.stdout.split()


MOONLIGHT_FLATPAK = "com.moonlight_stream.Moonlight"


def leave(keep=None):
    pause(keep)
    # Moonlight: leaving it is done playing: the app on the host is quit too (moonlight.py stop).
    if keep != "moonlight" and running(MOONLIGHT_FLATPAK):
        # End the stream now, quit the app on the host (Wolf stops e.g. the Steam container) a little later.
        subprocess.run([sys.executable, str(HERE / "moonlight.py"), "stop"], capture_output=True, timeout=30)
    if keep != "jellyfin":
        subprocess.run([sys.executable, str(HERE / "jellyfin.py"), "home"], timeout=60)


def youtube_home():
    if running(YOUTUBE_FLATPAK):  # never start VacuumTube just to reset it
        subprocess.run(["flatpak", "run", YOUTUBE_FLATPAK, "--deeplink", YOUTUBE_HOME],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)


def youtube(query=None, video=None):
    pause()
    if video:
        url = YOUTUBE_WATCH.format(urllib.parse.quote(video))
    else:
        url = YOUTUBE_SEARCH.format(urllib.parse.quote(query)) if query else YOUTUBE_HISTORY
    # A running VacuumTube gets the link from the new process (single instance) and that process exits.
    subprocess.Popen(["flatpak", "run", YOUTUBE_FLATPAK, "--fullscreen", "--deeplink", url],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def main():
    if sys.argv[1:2] == ["pause"] and len(sys.argv) == 2:
        pause()
    elif sys.argv[1:2] == ["leave"] and len(sys.argv) <= 3:
        leave(sys.argv[2] if len(sys.argv) == 3 else None)
    elif sys.argv[1:] == ["status"]:
        print(json.dumps(status()))
    elif sys.argv[1:] == ["youtube-home"]:
        youtube_home()
    elif sys.argv[1:2] == ["youtube-watch"] and len(sys.argv) == 3:
        youtube(video=sys.argv[2])
    elif sys.argv[1:] == ["youtube-history"]:
        youtube()
    elif sys.argv[1:2] == ["youtube"] and len(sys.argv) > 2:
        youtube(" ".join(sys.argv[2:]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
