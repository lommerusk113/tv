#!/usr/bin/env python3
"""Loads and unloads the KWin scripts in kwin/ (window tricks for the home screen). Standard library only.

  python3 kwin_script.py load <name>     load and run kwin/<name>.js under the plugin name tv-<name> (stays active,
                                         e.g. hide-moonlight keeps hiding new Moonlight windows)
  python3 kwin_script.py unload <name>   stop it again
  python3 kwin_script.py once <name>     load, run and unload (e.g. show-moonlight)
"""
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
QDBUS = shutil.which("qdbus6") or shutil.which("qdbus") or "qdbus"


def call(*args):
    return subprocess.run([QDBUS, "org.kde.KWin", *args], capture_output=True, text=True, timeout=10).stdout.strip()


def unload(name):
    call("/Scripting", "org.kde.kwin.Scripting.unloadScript", "tv-" + name)


def load(name):
    unload(name)  # a stale copy would keep the old behaviour
    script_id = call("/Scripting", "org.kde.kwin.Scripting.loadScript", str(HERE / "kwin" / (name + ".js")), "tv-" + name)
    if not script_id.lstrip("-").isdigit() or int(script_id) < 0:
        sys.exit("kwin_script: could not load %s (%s)" % (name, script_id or "no answer"))
    call("/Scripting/Script" + script_id, "org.kde.kwin.Script.run")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("load", "unload", "once"):
        sys.exit(__doc__)
    cmd, name = sys.argv[1:]
    if cmd == "unload":
        unload(name)
    else:
        load(name)
        if cmd == "once":
            time.sleep(0.3)
            unload(name)


if __name__ == "__main__":
    main()
