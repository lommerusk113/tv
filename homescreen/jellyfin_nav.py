#!/usr/bin/env python3
"""Moves Jellyfin Desktop's page (over its DevTools port, like jellyfin_back.py).

  python3 jellyfin_nav.py search <text>   open Jellyfin's search with the text typed in (voice "search for X")

Waits up to 30 s for the page when Jellyfin is still starting.
"""
import json
import os
import sys
import time
import urllib.parse
from pathlib import Path

from jellyfin_back import VENV_PYTHON, page_socket


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "search":
        sys.exit(__doc__)
    try:
        import websockets  # noqa: F401
    except ImportError:
        if VENV_PYTHON.exists() and not os.environ.get("JELLYFIN_NAV_IN_VENV"):
            os.environ["JELLYFIN_NAV_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])
        sys.exit("jellyfin_nav: needs the websockets module")
    import asyncio
    from jellyfin_curtain import evaluate
    url, deadline = page_socket(), time.monotonic() + 30
    while not url and time.monotonic() < deadline:
        time.sleep(0.5)
        url = page_socket()
    if not url:
        sys.exit("jellyfin_nav: Jellyfin Desktop is not running with its debug port")
    query = urllib.parse.quote(" ".join(sys.argv[2:]))
    asyncio.run(evaluate(url, "location.hash = %s" % json.dumps("#/search?query=" + query), wait_ready=20))


if __name__ == "__main__":
    main()
