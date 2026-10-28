#!/usr/bin/env python3
"""Tests voice.py: the sentence -> action rules always; with --whisper also a real transcription of whisper.cpp's
JFK sample (downloaded once to ~/.cache/tv-project/jfk.wav). Usage: python3 test_voice.py [--whisper]"""
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import voice

CASES = {
    "Open YouTube.": "launch:youtube",
    "Åpne Jellyfin": "launch:jellyfin",
    "start riks tv": "launch:rikstv",
    "Play Moonlight please": "launch:moonlight",
    "spill moon light": "launch:moonlight",
    "open your cube": "launch:youtube",
    "åpne jelly fin": "launch:jellyfin",
    "turn off the light": None,
    "Go home!": "home",
    "Hjem.": "home",
    "Turn it up": "volume_up",
    "skru ned": "volume_down",
    "Mute": "volume_mute",
    "Turn off the TV.": "tv_off",
    "slå av TV-en": "tv_off",
    "[BLANK_AUDIO]": None,
    "(music playing)": None,
    "What is the weather like": None,
    "": None,
    "Play Lord of the Rings on Jellyfin.": "jellyfin_play:lord of the rings",
    "play the lord of the rings": "jellyfin_play:the lord of the rings",
    "Spill Ringenes herre på Jellyfin": "jellyfin_play:ringenes herre",
    "Can you play Breaking Bad please": "jellyfin_play:breaking bad",
    "Jellyfin, play The Martian": "jellyfin_play:the martian",
    "watch the office on jelly fin": "jellyfin_play:the office",
    "Open Jellyfin please": "launch:jellyfin",
    "play cat videos on youtube": "launch:youtube",
    "Play Deadman's Chest.": "jellyfin_play:deadmans chest",
}


def main():
    for text, expected in CASES.items():
        got = voice.parse(text)
        assert got == expected, f"{text!r}: {got!r} != {expected!r}"
    assert voice.normalize(" [BLANK_AUDIO]  Open, YouTube! ") == "open youtube"

    if "--whisper" in sys.argv:
        wav = Path.home() / ".cache/tv-project/jfk.wav"
        if not wav.exists():
            wav.parent.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve("https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/samples/jfk.wav", wav)
        res = subprocess.run([sys.executable, str(Path(__file__).with_name("voice.py")), "file", str(wav)],
                             capture_output=True, text=True, timeout=180)
        assert res.returncode == 0, res.stderr
        out = json.loads(res.stdout)
        assert "ask not what your country can do for you" in out["text"], out
        assert out["action"] is None, out
        print("whisper:", out["text"])
    print("ok")


if __name__ == "__main__":
    main()
