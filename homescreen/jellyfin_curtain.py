#!/usr/bin/env python3
"""Black "Starting…" curtain over Jellyfin Desktop's page while a video starts from the home screen.

  python3 jellyfin_curtain.py on    cover the page (removes itself after 20 s, whatever happens)
  python3 jellyfin_curtain.py off   remove it

Why: a minimized Jellyfin gets no animation frames, so a video started while it is hidden leaves its start page on top
of the player. The home screen therefore raises Jellyfin first and starts the video then; the curtain hides Jellyfin's
start page meanwhile. Uses Jellyfin's DevTools port like jellyfin_back.py; exits 0 without it (nothing to cover).
"""
import asyncio
import json
import os
import sys
from pathlib import Path

from jellyfin_back import VENV_PYTHON, page_socket

ON = r"""
(() => {
    let c = document.getElementById("tvProjectCurtain");
    if (!c) {
        c = document.createElement("div");
        c.id = "tvProjectCurtain";
        c.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#000;display:flex;align-items:center;"
            + "justify-content:center;color:#9aa0a6;font:500 32px 'Noto Sans',sans-serif";
        c.textContent = "Starting…";
        document.body.appendChild(c);
    }
    clearTimeout(window.__tvProjectCurtainTimer);
    window.__tvProjectCurtainTimer = setTimeout(() => c.remove(), 20000);
})()
"""
OFF = r"""
(() => {
    const c = document.getElementById("tvProjectCurtain");
    if (c)
        c.remove();
})()
"""


async def evaluate(url, expression):
    import websockets
    async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expression}}))
        while json.loads(await asyncio.wait_for(ws.recv(), 10)).get("id") != 1:
            pass


def main():
    if sys.argv[1:] not in (["on"], ["off"]):
        sys.exit(__doc__)
    try:
        import websockets  # noqa: F401
    except ImportError:
        if VENV_PYTHON.exists() and not os.environ.get("JELLYFIN_CURTAIN_IN_VENV"):
            os.environ["JELLYFIN_CURTAIN_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])
        sys.exit("jellyfin_curtain: needs the websockets module")
    url = page_socket()
    if url:
        asyncio.run(evaluate(url, ON if sys.argv[1] == "on" else OFF))


if __name__ == "__main__":
    main()
