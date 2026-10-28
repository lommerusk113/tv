#!/usr/bin/env python3
"""Global remote buttons (config/remote.json): shortcuts that work inside apps too, handed to the home screen.

  python3 remote.py install          write one hidden .desktop file per button to ~/.local/share/applications with
                                     X-KDE-Shortcuts, so Plasma's global shortcuts run `remote.py send <action>`
  python3 remote.py uninstall        remove them again
  python3 remote.py send <action>    pass the action to the home screen; without one, launch apps directly
  python3 remote.py wait             (home screen) block until an action is sent, print it, exit

The home screen (bigscreen/HomeScreen.qml) keeps one `wait` running and reruns it after every action. Actions travel
through the FIFO ~/.cache/tv-project/remote.fifo. Standard library only.
"""
import json
import os
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIFO = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/remote.fifo"
APPS_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applications"
PREFIX = "tv-remote-"


def ensure_fifo():
    FIFO.parent.mkdir(parents=True, exist_ok=True)
    if not FIFO.exists():
        os.mkfifo(FIFO, 0o600)


def send(action):
    ensure_fifo()
    try:
        fd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)
    except OSError:  # ENXIO: nobody waiting, so the home screen is not running
        return fallback(action)
    with os.fdopen(fd, "w") as f:
        f.write(action + "\n")


def fallback(action):
    """Without the home screen (e.g. the normal Plasma desktop) only app launches make sense."""
    if action.startswith("launch:"):
        apps = json.loads((HERE / "config/apps.json").read_text())
        app = next((a for a in apps if a["id"] == action[7:]), None)
        if app and app.get("desktopId"):
            subprocess.Popen(["gtk-launch", app["desktopId"].removesuffix(".desktop")], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif action == "tv_power":
        subprocess.run([sys.executable, str(HERE / "tvpower.py"), "toggle"])
    elif action == "tv_input":
        subprocess.run([sys.executable, str(HERE / "tvpower.py"), "on"])


def wait():
    ensure_fifo()
    # Non-blocking open, so we can notice the home screen going away (orphaned: parent becomes 1) and quit.
    fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
    parent = os.getppid()
    try:
        while os.getppid() == parent:
            ready, _, _ = select.select([fd], [], [], 5)
            if not ready:
                continue
            data = os.read(fd, 4096).decode()
            if data.strip():
                print(data.split()[0])
                return
    finally:
        os.close(fd)


def install():
    conf = json.loads((HERE / "config/remote.json").read_text())["global"]
    # Remove first and let Plasma notice, otherwise it keeps the old key of a button whose key changed.
    uninstall()
    rebuild_menu()
    APPS_DIR.mkdir(parents=True, exist_ok=True)
    for key, entry in conf.items():
        name = PREFIX + "".join(c if c.isalnum() else "-" for c in entry["button"].lower()).strip("-") + ".desktop"
        (APPS_DIR / name).write_text(
            "[Desktop Entry]\nType=Application\n"
            f"Name=TV remote: {entry['button']}\n"
            f"Exec=python3 \"{HERE / 'remote.py'}\" send {entry['action']}\n"
            "NoDisplay=true\n"
            f"X-KDE-Shortcuts={key}\n")
        print(f"{entry['button']}: {key} -> {entry['action']}")
    rebuild_menu()


def rebuild_menu():
    """Plasma's global shortcuts pick up .desktop changes when the menu cache is rebuilt."""
    if shutil.which("kbuildsycoca6"):
        subprocess.run(["kbuildsycoca6"], capture_output=True)
        time.sleep(1)


def uninstall():
    for f in APPS_DIR.glob(PREFIX + "*.desktop"):
        f.unlink()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "send" and len(sys.argv) == 3:
        send(sys.argv[2])
    elif cmd in ("wait", "install", "uninstall") and len(sys.argv) == 2:
        {"wait": wait, "install": install, "uninstall": uninstall}[cmd]()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
