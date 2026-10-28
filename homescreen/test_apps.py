#!/usr/bin/env python3
"""Runs apps.py against a fake Flatpak exports directory. Usage: python3 test_apps.py"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    home = Path(tempfile.mkdtemp())
    exports = home / "exports"
    (exports / "applications").mkdir(parents=True)
    (exports / "icons/hicolor/scalable/apps").mkdir(parents=True)
    (exports / "icons/hicolor/scalable/apps/org.example.Zed.svg").write_text("<svg/>")
    entries = {
        "org.example.Zed.desktop": "Name=Zed\nIcon=org.example.Zed\n",
        "org.example.alpha.desktop": "Name=alpha\nIcon=missing\n",
        "org.example.Hidden.desktop": "Name=Hidden\nNoDisplay=true\n",
        "org.jellyfin.JellyfinDesktop.desktop": "Name=Jellyfin Desktop\n",  # pinned in apps.json
    }
    for name, body in entries.items():
        (exports / "applications" / name).write_text("[Desktop Entry]\nType=Application\n" + body)
    env = dict(os.environ, FLATPAK_SYSTEM_EXPORTS=str(exports), XDG_DATA_HOME=str(home / "data"),
               XDG_CACHE_HOME=str(home / "cache"))
    res = subprocess.run([sys.executable, str(Path(__file__).with_name("apps.py"))], env=env, capture_output=True,
                         text=True, timeout=30)
    assert res.returncode == 0, res.stderr
    items = json.loads((home / "cache/tv-project/content.json").read_text())["installedApps"]
    assert [i["name"] for i in items] == ["alpha", "Zed"], items  # sorted, hidden and pinned left out
    assert "image" not in items[0] and items[1]["image"].endswith("org.example.Zed.svg")
    assert items[1]["action"] == "launch_desktop:org.example.Zed.desktop"
    print("ok")


if __name__ == "__main__":
    main()
