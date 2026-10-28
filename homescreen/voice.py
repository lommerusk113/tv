#!/usr/bin/env python3
"""Voice commands for the home screen: record from the mic, transcribe locally with whisper.cpp, map to an action.

  python3 voice.py listen            record config/voice.json "seconds" from the default mic, print JSON
                                     {"text": "open youtube", "action": "launch:youtube"} (action null if not understood)
  python3 voice.py file <wav>        the same for a 16 kHz mono WAV file
  python3 voice.py parse <sentence>  only the text -> action step

Actions are the keymap's: home, launch:<app id>, volume_up, volume_down, volume_mute, tv_off. Phrases (English and
Norwegian) are in config/voice.json; app names come from config/apps.json "name" plus optional "voiceNames".
Needs whisper-cli (brew install whisper-cpp) and the model in config/voice.json (scripts/install-voice.sh).
Standard library only.
"""
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
WHISPER = shutil.which("whisper-cli") or "/home/linuxbrew/.linuxbrew/bin/whisper-cli"


def config():
    return json.loads((HERE / "config/voice.json").read_text())


def normalize(text):
    """Lower case, no punctuation or whisper markers like [BLANK_AUDIO] / (music), single spaces."""
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*", " ", text.lower())
    return " ".join(re.sub(r"[^\w\s-]", " ", text).split())


def contains(text, phrase):
    return re.search(r"(^|\s)" + re.escape(phrase) + r"($|\s)", text) is not None


def name_score(text, name):
    """How well some run of up to 3 words in text, joined without spaces, matches the name (1.0 = exact).

    Fuzzy, because whisper hears "open your cube" for "open YouTube" and "riks tv" for "RiksTV".
    """
    words, name = text.split(), name.replace(" ", "")
    runs = ["".join(words[i:j]) for i in range(len(words)) for j in range(i + 1, min(i + 3, len(words)) + 1)]
    return max((difflib.SequenceMatcher(None, run, name).ratio() for run in runs), default=0)


def parse(text, conf=None, apps=None):
    """Action for a sentence, or None. App names win over the fixed phrases ("play youtube" opens YouTube)."""
    conf = conf or config()
    apps = apps if apps is not None else json.loads((HERE / "config/apps.json").read_text())
    text = normalize(text)
    if not text:
        return None
    best, best_score = None, 0
    for app in apps:
        for name in [normalize(n) for n in [app.get("name", ""), *app.get("voiceNames", [])] if n]:
            score = name_score(text, name)
            if score > best_score:
                best, best_score = app, score
    if best and best_score >= conf.get("nameMatch", 0.75):
        return "launch:" + best["id"]
    # Longest phrase first, so "turn off the tv" is not read as something shorter.
    phrases = sorted(((p, action) for action, ps in conf["phrases"].items() for p in ps), key=lambda x: -len(x[0]))
    for phrase, action in phrases:
        if contains(text, normalize(phrase)):
            return action
    return None


def transcribe(wav, conf):
    model = os.path.expanduser(conf["model"])
    # The prompt biases whisper toward the words it should expect (app names, a few commands).
    apps = json.loads((HERE / "config/apps.json").read_text())
    prompt = ", ".join([a["name"] for a in apps] + ["open", "home", "volume up", "volume down", "mute"])
    res = subprocess.run([WHISPER, "-m", model, "-f", str(wav), "-l", conf.get("language", "auto"),
                          "--prompt", prompt, "-np", "-nt", "-t", str(min(8, os.cpu_count() or 4))],
                         capture_output=True, text=True, timeout=120)
    if res.returncode != 0:
        sys.exit("voice: whisper-cli failed: " + res.stderr.strip()[-300:])
    return " ".join(res.stdout.split())


def record(path, seconds):
    res = subprocess.run(["arecord", "-q", "-d", str(seconds), "-f", "S16_LE", "-r", "16000", "-c", "1", str(path)],
                         capture_output=True, text=True, timeout=seconds + 10)
    if res.returncode != 0:
        sys.exit("voice: arecord failed: " + res.stderr.strip())


def result(text, conf):
    return {"text": normalize(text), "action": parse(text, conf)}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("listen", "file", "parse"):
        sys.exit(__doc__)
    conf = config()
    if sys.argv[1] == "parse":
        print(json.dumps(result(" ".join(sys.argv[2:]), conf), ensure_ascii=False))
        return
    if sys.argv[1] == "file":
        print(json.dumps(result(transcribe(sys.argv[2], conf), conf), ensure_ascii=False))
        return
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "voice.wav"
        record(wav, int(conf.get("seconds", 4)))
        print(json.dumps(result(transcribe(wav, conf), conf), ensure_ascii=False))


if __name__ == "__main__":
    main()
