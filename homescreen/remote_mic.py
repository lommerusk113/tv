#!/usr/bin/env python3
"""Records from the microphone in the Bluetooth remote (Strong RemoteG20) over Google's "ATV Voice" GATT service.

  python3 remote_mic.py record <out.wav> [max seconds]   16 kHz mono WAV; stops early after speech + a pause; prints
                                                        {"seconds", "speech"}; speech false = nobody talked (whisper
                                                        invents words from silence: "volume down mute down…")
  python3 remote_mic.py check                           exit 0 if a connected remote has the voice service

Linux does not turn the remote's mic into an audio device, so voice.py used the laptop's mic across the room.
Protocol (ATVV v0.4, as the remote answers it; see github.com/b0o/ATVVoice docs/research/report.md):
TX ab5e0002 (write): GET_CAPS 0a 0004 0001, MIC_OPEN 0c 0001 (ADPCM 8 kHz), MIC_CLOSE 0d.
CTL ab5e0004 (notify): 0b caps, 04 audio start, 0a <frame count> sync, 00 audio stop.
RX ab5e0003 (notify): 134-byte frames in 20-byte pieces: seq(2) 00 predictor(int16 BE) step index(1), then 128 bytes
IMA/DVI ADPCM (256 samples, high nibble first). Each frame decodes on its own. v1.0 MIC_OPEN is refused (0c 0f 02).
Needs dbus-python + PyGObject (in Bazzite's base image).
"""
import array
import json
import math
import sys
import wave

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE = "ab5e0001-5a21-4f05-bc7d-af01f617b664"
TX, RX, CTL = ("ab5e0002-5a21-4f05-bc7d-af01f617b664", "ab5e0003-5a21-4f05-bc7d-af01f617b664",
               "ab5e0004-5a21-4f05-bc7d-af01f617b664")
CHAR = "org.bluez.GattCharacteristic1"
FRAME = 134
RATE = 8000
# Stop after speech followed by this much quiet; give up when nothing is said at all.
PAUSE_SECONDS = 0.9
QUIET_START_SECONDS = 4.0

STEPS = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
         107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
         876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
         4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
         22385, 24623, 27086, 29794, 32767]
INDEX = [-1, -1, -1, -1, 2, 4, 6, 8]


def decode(frame):
    """256 16-bit samples from one 134-byte frame."""
    pred = int.from_bytes(frame[3:5], "big", signed=True)
    index = min(max(frame[5], 0), 88)
    out = []
    for byte in frame[6:FRAME]:
        for nib in (byte >> 4, byte & 15):
            step = STEPS[index]
            diff = step >> 3
            if nib & 4:
                diff += step
            if nib & 2:
                diff += step >> 1
            if nib & 1:
                diff += step >> 2
            pred = max(-32768, min(32767, pred - diff if nib & 8 else pred + diff))
            index = min(max(index + INDEX[nib & 7], 0), 88)
            out.append(pred)
    return out


def find_chars(bus):
    """{uuid: object path} of the voice service of a connected remote, or None."""
    objects = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager").GetManagedObjects()
    for path, ifaces in objects.items():
        svc = ifaces.get("org.bluez.GattService1")
        if not svc or str(svc["UUID"]) != SERVICE:
            continue
        device = objects.get(str(svc["Device"]), {}).get("org.bluez.Device1", {})
        if not device.get("Connected"):
            continue
        return {str(i[CHAR]["UUID"]): p for p, i in objects.items() if CHAR in i and p.startswith(path + "/")}
    return None


def rms(samples):
    return math.sqrt(sum(s * s for s in samples) / len(samples)) if samples else 0


def record(out, max_seconds=8):
    """Writes a 16 kHz WAV of what was said; returns (seconds recorded, whether anyone spoke)."""
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    chars = find_chars(bus)
    if not chars:
        sys.exit("remote_mic: no connected remote with the voice service")
    char = {u: dbus.Interface(bus.get_object("org.bluez", p), CHAR) for u, p in chars.items()}
    buf, samples, state = bytearray(), [], {"speech": False, "quiet": 0, "noise": None}
    loop = GLib.MainLoop()

    def on_rx(iface, props, invalidated):
        if "Value" not in props:
            return
        buf.extend(bytes(props["Value"]))
        while len(buf) >= FRAME:
            frame = decode(bytes(buf[:FRAME]))
            del buf[:FRAME]
            samples.extend(frame)
            level = rms(frame)
            # The first ~0.2 s set the noise floor (capped); speech = 3x above it.
            if state["noise"] is None and len(samples) >= RATE // 5:
                state["noise"] = min(max(rms(samples), 150), 300)  # silence measured ~30; talking from the start must still count
            if state["noise"] is None:
                continue
            if level > state["noise"] * 3:
                state["speech"], state["quiet"] = True, 0
            else:
                state["quiet"] += len(frame)
            seconds = len(samples) / RATE
            if (state["speech"] and state["quiet"] > PAUSE_SECONDS * RATE) or seconds >= max_seconds \
                    or (not state["speech"] and seconds >= QUIET_START_SECONDS):
                loop.quit()

    bus.add_signal_receiver(on_rx, "PropertiesChanged", "org.freedesktop.DBus.Properties", path=chars[RX])
    for u in (RX, CTL):
        char[u].StartNotify()

    def send(hexs):
        char[TX].WriteValue(dbus.Array(bytes.fromhex(hexs), signature="y"), {"type": "command"})

    send("0a00040001")  # GET_CAPS v0.4, ADPCM 8 kHz
    GLib.timeout_add(150, lambda: (send("0c0001"), False)[1])  # MIC_OPEN
    GLib.timeout_add(int((max_seconds + 3) * 1000), loop.quit)  # nothing arrives at all
    loop.run()
    try:
        send("0d")  # MIC_CLOSE
    except dbus.DBusException:
        pass
    write_wav(out, samples)
    return len(samples) / RATE, state["speech"]


def write_wav(out, samples):
    """16 kHz (whisper's rate: linear in-between samples), loudness normalized, light low-pass against ADPCM hiss."""
    smooth = [(samples[max(i - 1, 0)] + 2 * s + samples[min(i + 1, len(samples) - 1)]) / 4 for i, s in enumerate(samples)]
    peak = max((abs(s) for s in smooth), default=0)
    gain = min(8.0, 0.9 * 32767 / peak) if peak else 1
    up = []
    for i, s in enumerate(smooth):
        nxt = smooth[i + 1] if i + 1 < len(smooth) else s
        up += [s * gain, (s + nxt) / 2 * gain]
    pcm = array.array("h", (int(max(-32768, min(32767, v))) for v in up))
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE * 2)
        w.writeframes(pcm.tobytes())


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        sys.exit(0 if find_chars(dbus.SystemBus()) else 1)
    if len(sys.argv) < 3 or sys.argv[1] != "record":
        sys.exit(__doc__)
    seconds, speech = record(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 8)
    print(json.dumps({"seconds": round(seconds, 1), "speech": speech}))


if __name__ == "__main__":
    main()
