#!/usr/bin/env python3
"""System settings for the Settings panel: Wi-Fi (nmcli), Bluetooth (bluetoothctl), display (kscreen-doctor).
Standard library only. Every command prints one JSON object; {"error": "..."} (exit 1) when it fails.

  python3 system.py wifi                       {"enabled", "networks": [{ssid, signal, secure, connected, known}]}
  python3 system.py wifi-rescan                the same after a fresh scan (takes a few seconds)
  python3 system.py wifi-power on|off
  python3 system.py wifi-connect <ssid> [password]   known or open networks need no password
  python3 system.py wifi-disconnect
  python3 system.py bt                         {"powered", "devices": [{mac, name, paired, connected}]} (paired only)
  python3 system.py bt-scan [seconds]          the same plus nearby unpaired devices (scans 8 s by default)
  python3 system.py bt-power on|off
  python3 system.py bt-connect|bt-disconnect|bt-pair|bt-forget <mac>   bt-pair also trusts and connects
  python3 system.py display                    {"outputs": [{id, name, enabled, mode, modes: [{id, label}], scale}]}
  python3 system.py location [status|on|off]   weather location switch (location.py)
  python3 system.py display-set <output> mode <mode id> | scale <factor> | enable | disable
"""
import json
import re
from pathlib import Path
import subprocess
import sys

MAC = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$", re.I)


class Failed(Exception):
    pass


def run(*args, timeout=30, check=True):
    res = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and res.returncode != 0:
        raise Failed((res.stderr or res.stdout).strip().splitlines()[-1] if (res.stderr or res.stdout).strip()
                     else "%s failed" % args[0])
    return res.stdout


def nmcli_fields(line):
    """Split one `nmcli -t` line on unescaped colons."""
    return [f.replace("\\:", ":") for f in re.split(r"(?<!\\):", line)]


# --- Wi-Fi ---------------------------------------------------------------------------------------------------------

def wifi(rescan=False):
    enabled = run("nmcli", "-t", "-f", "WIFI", "general").strip() == "enabled"
    known = {nmcli_fields(l)[0] for l in run("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show").splitlines()
             if l.endswith(":802-11-wireless")}
    networks = {}
    if enabled:
        out = run("nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                  "--rescan", "yes" if rescan else "auto", timeout=40)
        for line in out.splitlines():
            in_use, ssid, signal, security = (nmcli_fields(line) + [""] * 4)[:4]
            if not ssid:
                continue
            net = {"ssid": ssid, "signal": int(signal or 0), "secure": security not in ("", "--"),
                   "connected": in_use == "*", "known": ssid in known}
            old = networks.get(ssid)  # one entry per name (several access points)
            if not old or net["connected"] or (not old["connected"] and net["signal"] > old["signal"]):
                networks[ssid] = net
    ordered = sorted(networks.values(), key=lambda n: (not n["connected"], not n["known"], -n["signal"]))
    return {"enabled": enabled, "networks": ordered}


def wifi_connect(ssid, password=None):
    known = {nmcli_fields(l)[0] for l in run("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show").splitlines()
             if l.endswith(":802-11-wireless")}
    if ssid in known and not password:
        run("nmcli", "connection", "up", "id", ssid, timeout=60)
    else:
        args = ["nmcli", "device", "wifi", "connect", ssid] + (["password", password] if password else [])
        run(*args, timeout=60)
    return wifi()


def wifi_disconnect():
    for line in run("nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device").splitlines():
        device, kind, state = (nmcli_fields(line) + [""] * 3)[:3]
        if kind == "wifi" and state == "connected":
            run("nmcli", "device", "disconnect", device)
    return wifi()


# --- Bluetooth -----------------------------------------------------------------------------------------------------

def bt_devices(which=None):
    args = ["bluetoothctl", "devices"] + ([which] if which else [])
    out = {}
    for line in run(*args).splitlines():
        m = re.match(r"Device (\S+) (.*)", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def bt(scan_seconds=0):
    powered = "Powered: yes" in run("bluetoothctl", "show")
    if powered and scan_seconds:
        run("bluetoothctl", "--timeout", str(scan_seconds), "scan", "on", timeout=scan_seconds + 15, check=False)
    paired, connected = bt_devices("Paired"), bt_devices("Connected")
    devices = [{"mac": mac, "name": name, "paired": True, "connected": mac in connected}
               for mac, name in paired.items()]
    if scan_seconds:
        # Nearby devices with a real name (unnamed ones show their address, which means nothing on a TV).
        devices += [{"mac": mac, "name": name, "paired": False, "connected": False}
                    for mac, name in bt_devices().items()
                    if mac not in paired and name.replace("-", ":").upper() != mac.upper()]
    devices.sort(key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))
    return {"powered": powered, "devices": devices}


def bt_action(action, mac):
    if not MAC.match(mac):
        raise Failed("not a Bluetooth address: " + mac)
    if action == "pair":
        run("bluetoothctl", "--timeout", "25", "pair", mac, timeout=40)
        run("bluetoothctl", "trust", mac)
        run("bluetoothctl", "--timeout", "15", "connect", mac, timeout=30, check=False)
    elif action == "forget":
        run("bluetoothctl", "remove", mac)
    else:
        run("bluetoothctl", "--timeout", "15", action, mac, timeout=30)
    return bt()


# --- Display -------------------------------------------------------------------------------------------------------

def display():
    data = json.loads(run("kscreen-doctor", "-j"))
    outputs = []
    for o in data.get("outputs", []):
        if not o.get("connected"):
            continue
        modes, seen = [], set()
        for m in sorted(o.get("modes", []), key=lambda m: (-m["size"]["width"] * m["size"]["height"],
                                                           -m["refreshRate"])):
            label = "%dx%d @ %d Hz" % (m["size"]["width"], m["size"]["height"], round(m["refreshRate"]))
            if label not in seen:  # several modes can round to the same label
                seen.add(label)
                modes.append({"id": m["id"], "label": label})
        current = next((m for m in o.get("modes", []) if m["id"] == o.get("currentModeId")), None)
        outputs.append({
            "id": o["id"], "name": o.get("name", ""), "type": o.get("type", ""), "enabled": o.get("enabled", False),
            "mode": o.get("currentModeId"),
            "modeLabel": "%dx%d @ %d Hz" % (current["size"]["width"], current["size"]["height"],
                                            round(current["refreshRate"])) if current else "",
            "modes": modes, "scale": o.get("scale", 1),
        })
    return {"outputs": outputs}


def display_set(output, what, value=None):
    if not re.match(r"^[\w-]+$", output):
        raise Failed("bad output name")
    if what == "mode" and re.match(r"^\w+$", value or ""):
        run("kscreen-doctor", "output.%s.mode.%s" % (output, value))
    elif what == "scale" and re.match(r"^\d+(\.\d+)?$", value or "") and 0.5 <= float(value) <= 3:
        run("kscreen-doctor", "output.%s.scale.%s" % (output, value))
    elif what in ("enable", "disable"):
        enabled = [o for o in display()["outputs"] if o["enabled"]]
        if what == "disable" and len(enabled) <= 1:
            raise Failed("the last screen stays on")
        run("kscreen-doctor", "output.%s.%s" % (output, what))
    else:
        raise Failed("bad display setting")
    return display()


def location(cmd):
    """Settings' "Use my location" switch: location.py status|on|off (JSON)."""
    if cmd not in ("status", "on", "off"):
        raise Failed("status, on or off")
    res = subprocess.run([sys.executable, str(Path(__file__).with_name("location.py")), cmd], capture_output=True,
                         text=True, timeout=90)
    out = json.loads(res.stdout or "{}")
    if res.returncode != 0 or "error" in out:
        raise Failed(out.get("error") or res.stderr.strip()[-200:] or "location lookup failed")
    return out


def power(command, args, status):
    if args[:1] not in (["on"], ["off"]):
        raise Failed("on or off")
    run(*command, args[0])
    return status()


def batteries():
    """Battery-powered devices UPower knows (Bluetooth remotes, game controllers...): [{name, percent, kind}]."""
    out = []
    for path in run("upower", "-e", check=False).split():
        if any(skip in path for skip in ("battery_BAT", "line_power", "DisplayDevice")):
            continue
        info = run("upower", "-i", path, check=False)
        fields = dict(re.findall(r"^\s+([\w -]+):\s+(.*)$", info, re.M))
        kind = next((line.strip() for line in info.splitlines() if line.startswith("  ") and ":" not in line), "")
        percent = re.match(r"(\d+)", fields.get("percentage", ""))
        if percent:
            out.append({"name": fields.get("model") or fields.get("serial") or kind, "percent": int(percent.group(1)),
                        "kind": kind})
    return out


def controllers():
    """Connected game controllers (input devices with a joystick handler) with their battery when UPower knows it,
    plus every battery-powered device (the remote too): {"controllers": [{name, percent}], "batteries": [...]}."""
    try:
        devices = Path("/proc/bus/input/devices").read_text()
    except OSError:
        devices = ""
    names = []
    for block in devices.split("\n\n"):
        name = re.search(r'^N: Name="(.*)"', block, re.M)
        if name and re.search(r"^H: Handlers=.*\bjs\d+", block, re.M) and name.group(1) not in names:
            names.append(name.group(1))
    power = batteries()
    pads = []
    for name in names:
        hit = next((b for b in power if b["kind"] == "gaming-input" and (b["name"] in name or name in b["name"])),
                   next((b for b in power if b["kind"] == "gaming-input"), None))
        pads.append({"name": name, "percent": hit["percent"] if hit else None})
    return {"controllers": pads, "batteries": power}


def main():
    cmd, args = (sys.argv[1] if len(sys.argv) > 1 else ""), sys.argv[2:]
    commands = {
        "wifi": lambda: wifi(),
        "wifi-rescan": lambda: wifi(rescan=True),
        "wifi-power": lambda: power(["nmcli", "radio", "wifi"], args, wifi),
        "wifi-connect": lambda: wifi_connect(args[0], args[1] if len(args) > 1 else None),
        "wifi-disconnect": wifi_disconnect,
        "bt": lambda: bt(),
        "bt-scan": lambda: bt(int(args[0]) if args else 8),
        "bt-power": lambda: power(["bluetoothctl", "power"], args, bt),
        "bt-connect": lambda: bt_action("connect", args[0]),
        "bt-disconnect": lambda: bt_action("disconnect", args[0]),
        "bt-pair": lambda: bt_action("pair", args[0]),
        "bt-forget": lambda: bt_action("forget", args[0]),
        "display": display,
        "controllers": controllers,
        "location": lambda: location(args[0] if args else "status"),
        "display-set": lambda: display_set(args[0], args[1], args[2] if len(args) > 2 else None),
    }
    if cmd not in commands:
        sys.exit(__doc__)
    try:
        print(json.dumps(commands[cmd](), ensure_ascii=False))
    except (Failed, IndexError, ValueError, subprocess.TimeoutExpired, OSError) as e:
        print(json.dumps({"error": str(e) or type(e).__name__}))
        sys.exit(1)


if __name__ == "__main__":
    main()
