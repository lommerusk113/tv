#!/usr/bin/env python3
"""Tests tvpower.py without a TV: settings handling, the magic packet, the sleep-signal parser, and a TV that
does not answer. Usage: python3 test_tvpower.py (the last part needs bscpylgtv, see scripts/install-tv-power.sh)."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import tvpower


def main():
    home = Path(tempfile.mkdtemp())
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.bind(("127.0.0.1", 0))
    listener.settimeout(5)
    env = dict(os.environ, TV_DISCOVER="0", XDG_CONFIG_HOME=str(home / "config"), TV_WOL_PORT=str(listener.getsockname()[1]),
               TV_BOOT_WAIT="3")
    script = str(Path(__file__).with_name("tvpower.py"))

    def run(command):
        return subprocess.run([sys.executable, script, command], env=env, capture_output=True, text=True, timeout=60)

    # No settings: every command is a no-op.
    for command in ("on", "off", "status"):
        res = run(command)
        assert res.returncode == 0 and "nothing to do" in res.stderr, res

    # Magic packet: 6 x 0xff, then the MAC 16 times; any separator style.
    packet = tvpower.magic_packet("AA-bb:cc.dd:ee:FF")
    assert packet == b"\xff" * 6 + bytes.fromhex("aabbccddeeff") * 16 and len(packet) == 102
    try:
        tvpower.magic_packet("aa:bb")
        raise AssertionError("short MAC accepted")
    except ValueError:
        pass

    # logind's PrepareForSleep as printed by gdbus monitor.
    path = "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep"
    assert tvpower.sleep_event(path + " (true,)") is True
    assert tvpower.sleep_event(path + " (false,)") is False
    assert tvpower.sleep_event("/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('3', ...)") is None

    # A TV that does not answer (127.0.0.1 has no webOS API): "on" sends the magic packet to the TV's IP,
    # keeps trying for TV_BOOT_WAIT seconds, then fails with a clear message.
    (home / "config/tv-project").mkdir(parents=True)
    (home / "config/tv-project/secrets.json").write_text(
        json.dumps({"tv": {"ip": "127.0.0.1", "mac": "aa:bb:cc:dd:ee:ff"}}))
    started = time.monotonic()
    res = run("on")
    assert listener.recv(200) == packet
    assert res.returncode != 0 and "cannot reach the TV at 127.0.0.1" in res.stderr, res
    assert time.monotonic() - started < 40, "gave up too late"
    print("ok")


if __name__ == "__main__":
    main()
