#!/usr/bin/env python3
"""Voice commands for the home screen: record from the mic, transcribe locally with whisper.cpp, map to an action.

  python3 voice.py listen            record config/voice.json "seconds" from the default mic, print JSON
                                     {"text": "open youtube", "action": "launch:youtube"} (action null if not understood)
  python3 voice.py file <wav>        the same for a 16 kHz mono WAV file
  python3 voice.py parse <sentence>  only the text -> action step (rules + AI step)
  python3 voice.py rules <sentence>  only the fixed rules

Actions are the keymap's: home, launch:<app id>, volume_up, volume_down, volume_mute, tv_off, plus
jellyfin_play:<title> for "play <title> [on Jellyfin]" (jellyfin.py play), youtube_search:<query> for
"play <query> on YouTube" (media.py youtube), move_to_tv (Jellyfin from another device, else YouTube history) and
youtube_history, jellyfin_search:<text> / youtube_search:<text> for "search (for) <text> [on YouTube]". Phrases (English and Norwegian) are in
config/voice.json; app names come from config/apps.json "name" plus optional "voiceNames".
Needs whisper-cli (brew install whisper-cpp) and the model in config/voice.json (scripts/install-voice.sh).
With an OpenAI key (agent.py) the speech goes to OpenAI's speech-to-text instead (whisper.cpp when that fails), and
sentences the rules do not understand, or "play <title>" ones (misheard titles), go to the AI step in agent.py.
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

import agent

HERE = Path(__file__).resolve().parent
WHISPER = shutil.which("whisper-cli") or "/home/linuxbrew/.linuxbrew/bin/whisper-cli"


def config():
    return json.loads((HERE / "config/voice.json").read_text())


def normalize(text):
    """Lower case, no punctuation or whisper markers like [BLANK_AUDIO] / (music), single spaces."""
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*", " ", text.lower())
    text = re.sub(r"['\u2019]", "", text)  # "man's" -> "mans", not "man s"
    return " ".join(re.sub(r"[^\w\s-]", " ", text).split())


def contains(text, phrase):
    return re.search(r"(^|\s)" + re.escape(phrase) + r"($|\s)", text) is not None


def name_match(words, name):
    """(score, start, end) of the run of up to 3 words that, joined without spaces, best matches the name (1.0 = exact).

    Fuzzy, because whisper hears "open your cube" for "open YouTube" and "riks tv" for "RiksTV".
    """
    name = name.replace(" ", "")
    runs = [(difflib.SequenceMatcher(None, "".join(words[i:j]), name).ratio(), i, j)
            for i in range(len(words)) for j in range(i + 1, min(i + 3, len(words)) + 1)]
    return max(runs, default=(0, 0, 0))


def name_score(text, name):
    return name_match(text.split(), name)[0]


def best_app(words, apps):
    """(app, score, start, end) of the app whose name (or voiceNames) best matches a run of words."""
    best = (None, 0, 0, 0)
    for app in apps:
        for name in [normalize(n) for n in [app.get("name", ""), *app.get("voiceNames", [])] if n]:
            score, i, j = name_match(words, name)
            if score > best[1]:
                best = (app, score, i, j)
    return best


def remove_phrases(words, phrases):
    text = " " + " ".join(words) + " "
    for phrase in sorted(phrases, key=len, reverse=True):
        text = text.replace(" " + phrase + " ", " ")
    return text.split()


def search_request(words, conf, app, start, end):
    """The text in "search (for) <text> [on <app>]" (a search word first), or None."""
    verbs = sorted((normalize(v).split() for v in conf.get("search", [])), key=len, reverse=True)
    verb = next((v for v in verbs if words[:len(v)] == v), None)
    if not verb:
        return None
    if app and start >= len(verb):  # drop "[on] <app name>"
        if start > 0 and words[start - 1] in conf.get("prepositions", []):
            start -= 1
        words = words[:start] + words[end:]
    rest = remove_phrases(words[len(verb):], [normalize(f) for f in conf.get("fillers", [])])
    return " ".join(rest) or None


def title_request(words, conf, app, start, end):
    """The title in "play <title> [on <app>]", or None. Only for apps in titleActions, or when no app is named."""
    verbs = sorted((normalize(v).split() for v in conf.get("open", [])), key=len, reverse=True)
    at = next(((i, len(v)) for i in range(len(words)) for v in verbs if words[i:i + len(v)] == v), None)
    if at is None:
        return None
    if app:
        if app["id"] not in conf.get("titleActions", {}):
            return None
        if start > 0 and words[start - 1] in conf.get("prepositions", []):
            start -= 1
        words = words[:start] + words[end:]
        if at[0] >= start:  # the verb came after the app name ("jellyfin play x"): shift it
            at = (at[0] - (end - start), at[1])
    rest = remove_phrases(words[at[0] + at[1]:], [normalize(f) for f in conf.get("fillers", [])])
    return " ".join(rest) or None


def parse(text, conf=None, apps=None):
    """Action for a sentence, or None. "play <title> [on Jellyfin]" plays the title; otherwise app names win over the
    fixed phrases ("play youtube" opens YouTube)."""
    conf = conf or config()
    apps = apps if apps is not None else json.loads((HERE / "config/apps.json").read_text())
    text = normalize(text)
    if not text:
        return None
    words = text.split()
    best, best_score, start, end = best_app(words, apps)
    named = best if best and best_score >= conf.get("nameMatch", 0.75) else None
    # "search (for) X [on YouTube|Jellyfin]": opens that app's search with X (Jellyfin unless YouTube is named).
    query = search_request(words, conf, named, start, end)
    if query:
        return ("youtube_search:" if named and named["id"] == "youtube" else "jellyfin_search:") + query
    # A sentence that is exactly one of the fixed phrases wins ("play it here" is not a title called "it here").
    exact = remove_phrases(words, [normalize(f) for f in conf.get("fillers", [])])
    for action, ps in conf["phrases"].items():
        if " ".join(exact) in (normalize(p) for p in ps):
            return action
    title = title_request(words, conf, named, start, end)
    if title:
        app_id = named["id"] if named else conf.get("defaultTitleApp", "jellyfin")
        return conf["titleActions"][app_id] + ":" + title
    if named:
        return "launch:" + named["id"]
    # Longest phrase first, so "turn off the tv" is not read as something shorter.
    phrases = sorted(((p, action) for action, ps in conf["phrases"].items() for p in ps), key=lambda x: -len(x[0]))
    for phrase, action in phrases:
        if contains(text, normalize(phrase)):
            return action
    return None


def transcribe(wav, conf):
    # The prompt biases whisper toward the words it should expect (app names, a few commands).
    apps = json.loads((HERE / "config/apps.json").read_text())
    prompt = ", ".join([a["name"] for a in apps] + ["open", "home", "volume up", "volume down", "mute"])
    text = agent.transcribe(wav, prompt)
    if text is not None:
        return text
    model = os.path.expanduser(conf["model"])
    res = subprocess.run([WHISPER, "-m", model, "-f", str(wav), "-l", conf.get("language", "auto"),
                          "--prompt", prompt, "-np", "-nt", "-t", str(min(8, os.cpu_count() or 4))],
                         capture_output=True, text=True, timeout=120)
    if res.returncode != 0:
        sys.exit("voice: whisper-cli failed: " + res.stderr.strip()[-300:])
    return " ".join(res.stdout.split())


FAKE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/voice-fake.json"
LAST = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project/last-voice.wav"


def record(path, seconds):
    """The remote's own mic when it is connected (remote_mic.py: stops when you stop talking), else the laptop's.
    A copy goes to ~/.cache/tv-project/last-voice.wav for checking what was heard. False = the remote heard no speech."""
    res = subprocess.run([sys.executable, str(HERE / "remote_mic.py"), "record", str(path), str(seconds + 4)],
                         capture_output=True, text=True, timeout=seconds + 15)
    if res.returncode == 0:
        shutil.copy(path, LAST)
        return json.loads(res.stdout).get("speech", True)
    print("voice: remote mic: " + res.stderr.strip(), file=sys.stderr)
    res = subprocess.run(["arecord", "-q", "-d", str(seconds), "-f", "S16_LE", "-r", "16000", "-c", "1", str(path)],
                         capture_output=True, text=True, timeout=seconds + 10)
    if res.returncode != 0:
        sys.exit("voice: arecord failed: " + res.stderr.strip())
    shutil.copy(path, LAST)
    return True


def in_library(title):
    """Whether a film/series on Jellyfin sounds like the title (agent.library(); True when the list is unknown)."""
    import jellyfin
    names = [n.removesuffix(" (series)") for n in agent.library()]
    # Stricter than jellyfin.MIN_MATCH: "the bear" reaches 0.64 against "The Matrix Revolutions".
    return not names or max(jellyfin.match_score(title, n) for n in names) >= 0.75


# Rule results the AI step may improve: titles ("dead mans chest") and searches; everything else is final.
AGENT_FIXES = ("jellyfin_play:", "jellyfin_search:", "youtube_search:")


def result(text, conf, use_agent=True):
    """{"text", "action", "say" (a short answer to show, or null), "options" ([{label, action}]: guesses to choose
    from when the AI step is unsure), "by" ("rules" or the model)}."""
    action = parse(text, conf)
    out = {"text": normalize(text), "action": action, "say": None, "options": [], "by": "rules"}
    if use_agent and out["text"] and (action is None or action.startswith(AGENT_FIXES)):
        answer = agent.ask(text, action)
        if answer:
            # Unsure: no action, a few guesses to pick from ("Did you mean…?") instead of the rules' guess.
            unsure = not answer["action"] and answer["options"]
            # ...unless it was "play X" and nothing on the server sounds like X: offer to download X instead.
            if unsure and action and action.startswith("jellyfin_play:") and not in_library(action[14:]):
                answer.update(action="request_search:" + action[14:], options=[])
                unsure = False
            out.update(action=answer["action"] or (None if unsure else action), say=answer["say"],
                       options=answer["options"], by=answer["model"])
    return out


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("listen", "file", "parse", "rules"):
        sys.exit(__doc__)
    conf = config()
    if sys.argv[1] in ("parse", "rules"):
        print(json.dumps(result(" ".join(sys.argv[2:]), conf, sys.argv[1] == "parse"), ensure_ascii=False))
        return
    if sys.argv[1] == "file":
        print(json.dumps(result(transcribe(sys.argv[2], conf), conf), ensure_ascii=False))
        return
    if FAKE.exists():  # testing the screens: ~/.cache/tv-project/voice-fake.json is used once instead of the mic
        print(FAKE.read_text().strip())
        FAKE.unlink()
        return
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "voice.wav"
        heard = record(wav, int(conf.get("seconds", 4)))
        print(json.dumps(result(transcribe(wav, conf) if heard else "", conf), ensure_ascii=False))


if __name__ == "__main__":
    main()
