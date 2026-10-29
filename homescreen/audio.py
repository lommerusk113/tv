#!/usr/bin/env python3
"""Sound output follows the TV: the default sink is an HDMI output with something plugged in, else the speaker.

  python3 audio.py auto     switch if needed, print {"sink": <description>, "changed": bool}
  python3 audio.py status   only print the sink it would use

WirePlumber keeps the last chosen default (the laptop speaker) even after the TV is plugged in, so the home screen
runs `auto` on activation and every few seconds (HomeScreen.qml). The laptop has three HDMI/DP sinks (HDMI1-3); the
one with an "available" port is the TV. Streams that are playing are moved along. Standard library only.
"""
import json
import subprocess
import sys


def pactl(*args):
    return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=10).stdout


def sinks():
    """[{name, description, hdmi, available}] from `pactl -f json list sinks`."""
    out = []
    for s in json.loads(pactl("-f", "json", "list", "sinks") or "[]"):
        port = next((p for p in s.get("ports", []) if p.get("name") == s.get("active_port")), {})
        out.append({"name": s["name"], "description": s.get("description", s["name"]),
                    "hdmi": port.get("type") == "HDMI" or "HDMI" in s["name"],
                    "available": port.get("availability") != "not available"})
    return out


def wanted(all_sinks):
    tv = [s for s in all_sinks if s["hdmi"] and s["available"]]
    return (tv or [s for s in all_sinks if not s["hdmi"]] or all_sinks or [None])[0]


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("auto", "status"):
        sys.exit(__doc__)
    target = wanted(sinks())
    if not target:
        sys.exit("audio: no sinks")
    changed = False
    if sys.argv[1] == "auto" and pactl("get-default-sink").strip() != target["name"]:
        pactl("set-default-sink", target["name"])
        for line in pactl("list", "short", "sink-inputs").splitlines():
            pactl("move-sink-input", line.split()[0], target["name"])
        changed = True
    print(json.dumps({"sink": target["description"], "changed": changed}))


if __name__ == "__main__":
    main()
