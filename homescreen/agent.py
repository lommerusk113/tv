#!/usr/bin/env python3
"""AI step for voice commands: an OpenAI model turns what was said into one home-screen action, or a short answer.

  python3 agent.py ask <sentence>     print {"action": ..., "say": ...} (both may be null)
  python3 agent.py transcribe <wav>   print the text of a 16 kHz WAV (OpenAI speech-to-text)

voice.py uses it when its fixed rules do not understand a sentence, or to fix the title in "play <title>" (whisper
mishears names; the model gets the titles on the home screen and knows films, so "the second pirates film" works).
It sees: the apps (config/apps.json), the tiles on the home screen (~/.cache/tv-project/content.json), the weather
(weather.json) and the time. It can only pick actions from ALLOWED below, and ids only from those tiles.

Settings in config/voice.json "agent": models are tried in order (the next one only when one fails or gives up), so
the cheap one answers most commands. The key is in ~/.config/tv-project/secrets.json: "openai": {"apiKey": "sk-..."}
(or OPENAI_API_KEY). Standard library only.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tv-project"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "tv-project"
API = "https://api.openai.com/v1/"

# Actions the model may return: exact ones, and prefixes with free text after them.
EXACT = {"home", "volume_up", "volume_down", "volume_mute", "tv_off", "move_to_tv", "youtube_history", "settings",
         "weather_refresh"}
FREE = ("jellyfin_play:", "jellyfin_search:", "youtube_search:")
# Prefixes whose value must be one of the tiles' actions (ids cannot be guessed).
FROM_TILES = ("jellyfin_play_id:", "youtube_watch:", "moonlight_stream:", "request:", "launch_desktop:")

PROMPT = """You control a living-room TV home screen by voice. The user speaks English or Norwegian; speech-to-text
may have misheard words (names especially), so guess what they meant. Reply with JSON {"action": ..., "say": ...}.

action is ONE of these, or null:
- home, volume_up, volume_down, volume_mute, tv_off, settings
- launch:<app id>                  open an app (ids below)
- jellyfin_play_id:<id>            play a tile below (continue watching, next up, recently added, recommended)
- jellyfin_play:<title>            play a film/series from the Jellyfin library by its correct, official title
- jellyfin_search:<text>           open Jellyfin's search
- youtube_watch:<id>               play a YouTube tile below
- youtube_search:<query>           search YouTube (also "play <something> on YouTube", e.g. a channel name)
- youtube_history                  continue the last YouTube video
- move_to_tv                       move what plays on the phone/PC to the TV
- moonlight_stream:<app>           start a game-streaming app from the tiles (e.g. Steam)
- request:<kind>:<tmdb id>:<title> ask the server to download a "Get more" tile
- launch_desktop:<desktop id>      open an installed desktop app tile

Prefer a tile's exact action when the user means it ("continue Merlin", "the new Lanterns episode"). Fix misheard
titles to their real names ("dead mans chest" -> "Pirates of the Caribbean: Dead Man's Chest"). Use null when it is
not a command for the TV.
say is a short reply (max 15 words, the user's language) shown on screen: an answer to a question (weather, time,
"what should I watch?" -> suggest one tile and also play nothing), or null when the action speaks for itself.
"""


def secrets():
    try:
        return json.loads((CONFIG / "secrets.json").read_text())
    except (OSError, ValueError):
        return {}


def api_key():
    return os.environ.get("OPENAI_API_KEY") or (secrets().get("openai") or {}).get("apiKey")


def settings():
    return json.loads((HERE / "config/voice.json").read_text()).get("agent", {})


def post(path, body, headers, timeout):
    req = urllib.request.Request(API + path, data=body, headers={"Authorization": "Bearer " + api_key(), **headers})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read())


def tiles():
    """What is on the home screen, as {row: [{title, subtitle, action}]}, for the model to pick from."""
    try:
        content = json.loads((CACHE / "content.json").read_text())
    except (OSError, ValueError):
        return {}
    out = {}
    for row, items in content.items():
        if not isinstance(items, list):
            continue
        out[row] = [{k: v for k, v in (("title", i.get("title") or i.get("name")),
                                        ("about", i.get("subtitle") or i.get("meta")),
                                        ("action", i.get("action"))) if v}
                    for i in items[:25] if i.get("action")]
    return {k: v for k, v in out.items() if v}


def weather():
    try:
        w = json.loads((CACHE / "weather.json").read_text())
    except (OSError, ValueError):
        return None
    hours = [{"time": t["time"], "temp": t["data"]["instant"]["details"].get("air_temperature"),
              "next": (t["data"].get("next_1_hours") or t["data"].get("next_6_hours") or {})
              .get("summary", {}).get("symbol_code")}
             for t in w.get("timeseries", [])[:24:3]]
    return {"now": {"temp": w.get("temperature"), "symbol": w.get("symbol")}, "next hours (UTC)": hours}


def context():
    apps = json.loads((HERE / "config/apps.json").read_text())
    return {"time": datetime.now().strftime("%A %Y-%m-%d %H:%M"),
            "apps": [{"id": a["id"], "name": a["name"]} for a in apps],
            "tiles": tiles(), "weather": weather()}


def allowed(action, ctx):
    if not isinstance(action, str) or not action:
        return False
    if action in EXACT or (action.startswith(FREE) and action.split(":", 1)[1].strip()):
        return True
    if action.startswith("launch:"):
        return action[7:] in {a["id"] for a in ctx["apps"]}
    if action.startswith(FROM_TILES):
        return any(t.get("action") == action for row in ctx["tiles"].values() for t in row)
    return False


def ask_model(model, text, hint, ctx, timeout):
    user = {"said": text, "context": ctx}
    if hint:
        user["simple rules guessed"] = hint
    body = {"model": model,
            "messages": [{"role": "system", "content": PROMPT},
                         {"role": "user", "content": json.dumps(user, ensure_ascii=False)}],
            "response_format": {"type": "json_schema", "json_schema": {"name": "tv_command", "strict": True, "schema": {
                "type": "object", "additionalProperties": False, "required": ["action", "say"],
                "properties": {"action": {"type": ["string", "null"]}, "say": {"type": ["string", "null"]}}}}}}
    if model.startswith(("gpt-5", "o")):
        body["reasoning_effort"] = "minimal"  # a command, not a puzzle: answer fast
    res = post("chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"}, timeout)
    return json.loads(res["choices"][0]["message"]["content"])


def ask(text, hint=None):
    """{"action", "say", "model"} for a sentence; None when there is no key or every model failed."""
    conf = settings()
    if not api_key() or not conf.get("enabled", True):
        return None
    ctx = context()
    for model in conf.get("models", ["gpt-5-nano", "gpt-5-mini"]):
        started = time.monotonic()
        try:
            answer = ask_model(model, text, hint, ctx, conf.get("timeout", 10))
        except (OSError, ValueError, KeyError, urllib.error.URLError) as e:
            print(f"agent: {model} failed: {e}", file=sys.stderr)
            continue
        action = answer.get("action")
        if action and not allowed(action, ctx):
            print(f"agent: {model} gave an unknown action {action!r}", file=sys.stderr)
            action = None
        print(f"agent: {model} {time.monotonic() - started:.1f}s -> {action!r} / {answer.get('say')!r}",
              file=sys.stderr)
        if action or answer.get("say"):
            return {"action": action, "say": answer.get("say"), "model": model}
    return None


def transcribe(wav, prompt=""):
    """Text of a WAV via OpenAI speech-to-text; None without a key, when switched off, or on failure."""
    conf = settings()
    if not api_key() or not conf.get("enabled", True) or not conf.get("transcribeModel"):
        return None
    boundary = uuid.uuid4().hex
    fields = {"model": conf["transcribeModel"], "prompt": prompt}
    body = b"".join(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
                    for k, v in fields.items() if v)
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="voice.wav"\r\n'
             f"Content-Type: audio/wav\r\n\r\n").encode() + Path(wav).read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    try:
        res = post("audio/transcriptions", body, {"Content-Type": "multipart/form-data; boundary=" + boundary},
                   conf.get("timeout", 10))
        return res.get("text", "")
    except (OSError, ValueError, urllib.error.URLError) as e:
        print(f"agent: transcription failed: {e}", file=sys.stderr)
        return None


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("ask", "transcribe"):
        sys.exit(__doc__)
    if not api_key():
        sys.exit('agent: no OpenAI key: add "openai": {"apiKey": "sk-..."} to ~/.config/tv-project/secrets.json')
    if sys.argv[1] == "transcribe":
        print(transcribe(sys.argv[2]))
    else:
        print(json.dumps(ask(" ".join(sys.argv[2:])), ensure_ascii=False))


if __name__ == "__main__":
    main()
