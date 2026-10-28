#!/usr/bin/env python3
"""Turns the LG TV on and off: Wake-on-LAN + bscpylgtv (the webOS API on the local network).

  python3 tvpower.py on            wake the TV, then switch it to the laptop's HDMI input
  python3 tvpower.py off           turn the TV off
  python3 tvpower.py toggle        off if the TV is on, otherwise on (the remote's power button)
  python3 tvpower.py pair          first connection: accept the prompt on the TV; the client key is saved
  python3 tvpower.py status        print the TV's power state
  python3 tvpower.py watch-sleep   for tv-sleep.service: TV off before the laptop sleeps, on after it wakes

Settings in ~/.config/tv-project/secrets.json:
  "tv": {"ip": "192.168.1.50", "mac": "aa:bb:cc:dd:ee:ff", "input": "HDMI_1"}   (input defaults to HDMI_1)
The client key is kept in ~/.config/tv-project/lgtv-keys.sqlite (not in the repo). bscpylgtv is installed in the
venv ~/.local/share/tv-project/venv (scripts/install-tv-power.sh); the script reruns itself there when needed.
Without "tv" settings every command does nothing and exits 0.
"""
import asyncio
import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
KEYS = CONFIG / "lgtv-keys.sqlite"
VENV_PYTHON = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "tv-project/venv/bin/python"
WOL_PORT = int(os.environ.get("TV_WOL_PORT", "9"))
BOOT_WAIT = float(os.environ.get("TV_BOOT_WAIT", "40"))  # seconds the TV gets to come up after the magic packet


def settings():
    try:
        tv = json.loads((CONFIG / "secrets.json").read_text()).get("tv") or {}
    except (OSError, ValueError):
        return None
    return tv if tv.get("ip") else None


def magic_packet(mac):
    digits = re.sub(r"[^0-9a-fA-F]", "", mac)
    if len(digits) != 12:
        raise ValueError(f"bad MAC address: {mac!r}")
    return b"\xff" * 6 + bytes.fromhex(digits) * 16


def wake(tv):
    """Magic packet to the broadcast address and to the TV's own IP (works when the router keeps its ARP entry)."""
    if not tv.get("mac"):
        return
    packet = magic_packet(tv["mac"])
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for target in ("255.255.255.255", tv["ip"]):
            try:
                s.sendto(packet, (target, WOL_PORT))
            except OSError as e:
                print(f"tvpower: wake {target}: {e}", file=sys.stderr)


def use_venv():
    """Rerun this script with the venv's Python when bscpylgtv is not importable here."""
    try:
        import bscpylgtv  # noqa: F401
    except ImportError:
        # Not resolve(): the venv's python is a symlink to the system one. The env var stops a loop.
        if VENV_PYTHON.exists() and not os.environ.get("TVPOWER_IN_VENV"):
            os.environ["TVPOWER_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), __file__, *sys.argv[1:]])
        sys.exit(f"tvpower: bscpylgtv is not installed (run scripts/install-tv-power.sh)")


async def connect(tv, attempts=1):
    from bscpylgtv import WebOsClient
    client = await WebOsClient.create(tv["ip"], key_file_path=str(KEYS))
    for attempt in range(attempts):
        try:
            await client.connect()
            return client
        except Exception as e:  # bscpylgtv raises plain OSErrors, timeouts and websocket errors
            if attempt == attempts - 1:
                raise SystemExit(f"tvpower: cannot reach the TV at {tv['ip']}: {e}")
            await asyncio.sleep(2)


async def on(tv):
    wake(tv)
    deadline = time.monotonic() + BOOT_WAIT
    while True:  # the TV ignores the API for a while after waking; keep waking it until it answers
        try:
            client = await connect(tv)
            break
        except SystemExit:
            if time.monotonic() > deadline:
                raise
            wake(tv)
            await asyncio.sleep(2)
    try:
        await client.set_input(tv.get("input", "HDMI_1"))
    finally:
        await client.disconnect()


async def off(tv):
    client = await connect(tv, attempts=2)
    try:
        await client.power_off()
    finally:
        await client.disconnect()


async def toggle(tv):
    try:
        client = await connect(tv)
    except SystemExit:  # not answering: off (or still booting), so wake it
        return await on(tv)
    try:
        state = (await client.get_power_state()).get("state")
    finally:
        await client.disconnect()
    # "Active" is on; standby states ("Active Standby", "Suspend", "Screen Off") count as off.
    await (off(tv) if state == "Active" else on(tv))


async def pair(tv):
    print("tvpower: accept the connection request on the TV screen")
    client = await connect(tv, attempts=3)
    await client.disconnect()
    os.chmod(KEYS, 0o600)
    print(f"tvpower: paired, key saved in {KEYS}")


async def status(tv):
    client = await connect(tv, attempts=2)
    try:
        print(json.dumps(await client.get_power_state()))
    finally:
        await client.disconnect()


def sleep_event(line):
    """True (going to sleep) / False (woke up) for a logind PrepareForSleep line from gdbus monitor, else None."""
    m = re.search(r"\.PrepareForSleep \((true|false),\)", line)
    return None if not m else m.group(1) == "true"


def watch_sleep():
    """Runs under systemd-inhibit --mode=delay (tv-sleep.service), so logind waits (max 5 s) for the TV to go off."""
    monitor = subprocess.Popen(["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1",
                                "--object-path", "/org/freedesktop/login1"], stdout=subprocess.PIPE, text=True)
    for line in monitor.stdout:
        going_to_sleep = sleep_event(line)
        if going_to_sleep is not None:
            # A separate process, so a TV that does not answer never stops the watcher.
            subprocess.run([sys.executable, __file__, "off" if going_to_sleep else "on"])
    sys.exit("tvpower: gdbus monitor ended")


def main():
    commands = {"on": on, "off": off, "toggle": toggle, "pair": pair, "status": status}
    if len(sys.argv) != 2 or sys.argv[1] not in [*commands, "watch-sleep"]:
        sys.exit(__doc__)
    tv = settings()
    if not tv:
        # watch-sleep exits too, so tv-sleep.service holds no sleep delay lock for nothing (restart it after adding "tv").
        print("tvpower: no \"tv\" settings in secrets.json; nothing to do", file=sys.stderr)
        return
    if sys.argv[1] == "watch-sleep":
        return watch_sleep()
    use_venv()
    CONFIG.mkdir(parents=True, exist_ok=True)
    asyncio.run(commands[sys.argv[1]](tv))


if __name__ == "__main__":
    main()
