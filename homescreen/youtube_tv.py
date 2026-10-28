#!/usr/bin/env python3
"""Reads a feed from YouTube through the running VacuumTube (its Chrome DevTools port), with VacuumTube's own login.

  python3 youtube_tv.py history       watch history       -> [{id, title, channel, duration, watched}] as JSON
  python3 youtube_tv.py recommended   start page's picks  -> same

The port is opened by "--remote-debugging-port=9231" in VacuumTube's flags.txt
(~/.var/app/rocks.shy.VacuumTube/config/VacuumTube/, see scripts/install-youtube-debug.sh); it listens on 127.0.0.1 only.
youtube_tv.js runs inside the page, so the login token never leaves VacuumTube. Exits 2 when VacuumTube is not
running with the port (nothing is started), 1 on other errors. Needs the websockets module: reruns itself in the
tv-project venv (~/.local/share/tv-project/venv, made by scripts/install-tv-power.sh) when needed.
"""
import asyncio
import json
import os
import sys
import urllib.request
from pathlib import Path

PORT = int(os.environ.get("VACUUMTUBE_DEBUG_PORT", "9231"))
FEEDS = {"history": "FEhistory", "recommended": "FEwhat_to_watch"}
VENV_PYTHON = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "tv-project/venv/bin/python"


def page_socket():
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/json" % PORT, timeout=3) as res:
            targets = json.load(res)
    except OSError:
        sys.exit(2)
    pages = [t for t in targets if t.get("type") == "page" and "youtube.com/tv" in t.get("url", "")]
    if not pages:
        sys.exit(2)
    return pages[0]["webSocketDebuggerUrl"]


async def evaluate(url, expression):
    import websockets
    async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                                  "params": {"expression": expression, "returnByValue": True, "awaitPromise": True}}))
        while True:
            reply = json.loads(await asyncio.wait_for(ws.recv(), 30))
            if reply.get("id") == 1:
                result = reply.get("result", {})
                if "exceptionDetails" in result:
                    sys.exit("youtube_tv: " + json.dumps(result["exceptionDetails"])[:300])
                return result.get("result", {}).get("value")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in FEEDS:
        sys.exit(__doc__)
    try:
        import websockets  # noqa: F401
    except ImportError:
        if VENV_PYTHON.exists() and not os.environ.get("YOUTUBE_TV_IN_VENV"):
            os.environ["YOUTUBE_TV_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), __file__, *sys.argv[1:]])
        sys.exit("youtube_tv: needs the websockets module (scripts/install-tv-power.sh makes the venv)")
    script = (Path(__file__).with_name("youtube_tv.js").read_text()).replace("FEED", json.dumps(FEEDS[sys.argv[1]]))
    value = asyncio.run(evaluate(page_socket(), script))
    if not isinstance(value, list):
        sys.exit("youtube_tv: %s" % (value or {}).get("error", "no answer"))
    print(json.dumps(value, ensure_ascii=False))


if __name__ == "__main__":
    main()
