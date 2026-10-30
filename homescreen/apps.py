#!/usr/bin/env python3
""""More apps" row: every installed Flatpak app that is not already in config/apps.json. Standard library only.

  python3 apps.py order <id>,<id>,...   saves the order of the "Your apps" row (hold OK on an app tile to move it) in
                                        ~/.config/tv-project/app-order.json; TvHome.qml sorts apps.json by it

  python3 apps.py   writes the installedApps key into ~/.cache/tv-project/content.json; OK on a tile starts the app
                    (action "launch_desktop:<desktop id>"), so apps installed from the App Store show up by themselves

Reads the exported .desktop files (system and user Flatpak installations); skips NoDisplay/Hidden entries.
Icons: the app's exported hicolor icon (SVG, else the largest PNG).
"""
import configparser
import json
import os
from pathlib import Path

from trakt import colors, update_content
import tvconfig

HERE = Path(__file__).resolve().parent
EXPORTS = [Path(os.environ.get("FLATPAK_SYSTEM_EXPORTS", "/var/lib/flatpak/exports/share")),
           Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "flatpak/exports/share"]
ICON_DIRS = ["scalable", "512x512", "256x256", "192x192", "128x128", "96x96", "64x64"]


def icon_path(name):
    if os.path.isabs(name):
        return name if os.path.exists(name) else None
    for base in EXPORTS:
        for size in ICON_DIRS:
            for ext in (".svg", ".png"):
                p = base / "icons/hicolor" / size / "apps" / (name + ext)
                if p.exists():
                    return str(p)
    return None


def installed():
    """[(desktop id, name, icon path or None)] sorted by name."""
    found = {}
    for base in EXPORTS:
        for f in sorted((base / "applications").glob("*.desktop")):
            entry = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                entry.read(f, encoding="utf-8")
                d = entry["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            if d.get("NoDisplay", "false").lower() == "true" or d.get("Hidden", "false").lower() == "true":
                continue
            if d.get("Type", "Application") != "Application" or not d.get("Name"):
                continue
            found.setdefault(f.name, (f.name, d["Name"], icon_path(d.get("Icon", ""))))
    return sorted(found.values(), key=lambda a: a[1].lower())


def save_order(ids):
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
    config.mkdir(parents=True, exist_ok=True)
    tmp = config / "app-order.json.tmp"
    tmp.write_text(json.dumps([i for i in ids if i]))
    tmp.replace(config / "app-order.json")


def main():
    import sys
    if sys.argv[1:2] == ["order"] and len(sys.argv) == 3:
        save_order(sys.argv[2].split(","))
        return
    pinned = {a.get("desktopId") for a in tvconfig.load("apps", with_hidden=True)}
    items = []
    for desktop_id, name, icon in installed():
        if desktop_id in pinned:
            continue
        item = {"id": "app-" + desktop_id, "name": name, "colors": colors(desktop_id)[:2],
                "action": "launch_desktop:" + desktop_id}
        if icon:
            item["image"] = Path(icon).as_uri()
            item["imageScale"] = 0.45
        items.append(item)
    print(f"apps: wrote {update_content({'installedApps': items})}")


if __name__ == "__main__":
    main()
