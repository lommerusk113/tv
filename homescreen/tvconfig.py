#!/usr/bin/env python3
"""Settings: the defaults in homescreen/config/<name>.json, with your own changes from ~/.config/tv-project/<name>.json
on top (that folder is never in git, so a `git pull` keeps them). TvHome.qml merges the same way (mergeConfig).

  python3 tvconfig.py show <name>    print the merged settings (e.g. apps, voice, moonlight)

How a user file changes the defaults:
- objects merge key by key (nested objects too), so {"agent": {"enabled": false}} in voice.json changes one setting;
- apps.json is a list of apps matched by "id": an entry changes that app's fields, a new id adds an app, and
  "hidden": true leaves an app out (also how optional apps such as Steam and RiksTV are switched on: "hidden": false);
- any other list replaces the default list (e.g. youtube.json "channels").
Standard library only.
"""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
USER = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"


def merge(default, user):
    if isinstance(default, dict) and isinstance(user, dict):
        out = dict(default)
        for key, value in user.items():
            out[key] = merge(default[key], value) if key in default else value
        return out
    if isinstance(default, list) and isinstance(user, list) and all(isinstance(a, dict) and "id" in a
                                                                    for a in default + user):
        out = [dict(a) for a in default]
        for app in user:
            hit = next((a for a in out if a["id"] == app["id"]), None)
            if hit:
                hit.update(app)
            else:
                out.append(dict(app))
        return out
    return user


def user_file(name):
    return USER / (name + ".json")


def load(name, with_hidden=False):
    """The merged settings of config/<name>.json; apps marked "hidden" are left out unless with_hidden."""
    data = json.loads((HERE / "config" / (name + ".json")).read_text())
    try:
        data = merge(data, json.loads(user_file(name).read_text()))
    except FileNotFoundError:
        pass
    except ValueError as e:
        print(f"tvconfig: {user_file(name)} ignored: {e}", file=sys.stderr)
    if isinstance(data, list) and not with_hidden:
        data = [a for a in data if not (isinstance(a, dict) and a.get("hidden"))]
    return data


def update_user(name, changes):
    """Merge changes into ~/.config/tv-project/<name>.json (created if missing), atomically."""
    path = user_file(name)
    try:
        current = json.loads(path.read_text())
    except (OSError, ValueError):
        current = [] if isinstance(changes, list) else {}
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(merge(current, changes), indent=2, ensure_ascii=False) + "\n")
    tmp.replace(path)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "show":
        sys.exit(__doc__)
    print(json.dumps(load(sys.argv[2]), indent=2, ensure_ascii=False))
