#!/usr/bin/env python3
"""Loading screen ("curtain") over Jellyfin Desktop's page while a video starts from the home screen.

  python3 jellyfin_curtain.py on [item id]   loading screen over the page: the item's picture, logo/title and episode
                                             (without an id just "Starting" and the bar); gone after 20 s at most
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

# Loading screen: the item's backdrop (a series' for an episode), darkened, its logo (else the title), the episode line
# and a sliding bar. Built inside Jellyfin's page with its own ApiClient; without an item id only the bar and text.
# It goes away by itself when Jellyfin's player emits `playing` (window.api.player), `off` is the fallback.
ON = r"""
((itemId) => {
    clearTimeout(window.__tvProjectCurtainTimer);
    let c = document.getElementById("tvProjectCurtain");
    if (!c) {
        c = document.createElement("div");
        c.id = "tvProjectCurtain";
        c.innerHTML = `
<style>
#tvProjectCurtain { position: fixed; inset: 0; z-index: 2147483647; background: #0e1013; overflow: hidden;
  font-family: 'Noto Sans', sans-serif; color: #e8eaed; opacity: 0; transition: opacity .35s ease; }
#tvProjectCurtain.shown { opacity: 1; }
#tvProjectCurtain .bg { position: absolute; inset: -40px; background-size: cover; background-position: center;
  filter: blur(6px) brightness(.45); transform: scale(1.04); animation: tvpZoom 14s ease-out forwards; }
#tvProjectCurtain .shade { position: absolute; inset: 0;
  background: linear-gradient(90deg, rgba(14,16,19,.92) 0%, rgba(14,16,19,.55) 45%, rgba(14,16,19,.15) 100%),
              linear-gradient(0deg, rgba(14,16,19,.95) 0%, rgba(14,16,19,0) 45%); }
#tvProjectCurtain .info { position: absolute; left: 96px; bottom: 150px; max-width: 46%; }
#tvProjectCurtain .kicker { font-size: 22px; font-weight: 600; color: #8ab4f8; letter-spacing: 2px; text-transform: uppercase; }
#tvProjectCurtain .logo { display: block; max-width: 560px; max-height: 190px; margin: 18px 0 10px; }
#tvProjectCurtain .title { font-size: 64px; font-weight: 700; line-height: 1.1; margin: 14px 0 8px; }
#tvProjectCurtain .sub { font-size: 28px; color: #c4c7cc; margin-top: 8px; }
#tvProjectCurtain .bar { position: absolute; left: 96px; right: 96px; bottom: 84px; height: 5px; border-radius: 3px;
  background: rgba(232,234,237,.15); overflow: hidden; }
#tvProjectCurtain .bar i { position: absolute; top: 0; bottom: 0; width: 30%; border-radius: 3px; background: #8ab4f8;
  animation: tvpSlide 1.3s ease-in-out infinite; }
@keyframes tvpSlide { from { left: -30%; } to { left: 100%; } }
@keyframes tvpZoom { from { transform: scale(1.04); } to { transform: scale(1.12); } }
</style>
<div class="bg"></div><div class="shade"></div>
<div class="info"><div class="kicker">Starting</div><div class="name"></div><div class="sub"></div></div>
<div class="bar"><i></i></div>`;
        document.body.appendChild(c);
        requestAnimationFrame(() => c.classList.add("shown"));
    }
    const name = c.querySelector(".name"), sub = c.querySelector(".sub"), bg = c.querySelector(".bg");
    const text = t => { name.innerHTML = ""; const d = document.createElement("div"); d.className = "title"; d.textContent = t; name.appendChild(d); };
    if (itemId && window.ApiClient) {
        ApiClient.getItem(ApiClient.getCurrentUserId(), itemId).then(it => {
            const show = it.SeriesId || it.Id;  // an episode shows its series' picture and logo
            bg.style.backgroundImage = `url("${ApiClient.getScaledImageUrl(show, { type: "Backdrop", maxWidth: 1920 })}")`;
            text(it.SeriesName || it.Name);
            const logo = new Image();
            logo.className = "logo";
            logo.onload = () => { name.innerHTML = ""; name.appendChild(logo); };
            logo.src = ApiClient.getScaledImageUrl(show, { type: "Logo", maxWidth: 1120 });
            if (it.Type === "Episode")
                sub.textContent = `Season ${it.ParentIndexNumber ?? "?"} · Episode ${it.IndexNumber ?? "?"} · ${it.Name}`;
            else if (it.ProductionYear)
                sub.textContent = String(it.ProductionYear);
            if (it.UserData && it.UserData.PlaybackPositionTicks)
                c.querySelector(".kicker").textContent = "Continuing";
        }).catch(() => text(""));
    }
    // Fades out the moment Jellyfin's player starts (the server's position updates come seconds later, so waiting for
    // them let the sound start under the loading screen).
    const player = window.api && window.api.player;
    if (player && player.playing && !window.__tvProjectCurtainHooked) {
        window.__tvProjectCurtainHooked = true;
        player.playing.connect(() => {
            const cur = document.getElementById("tvProjectCurtain");
            if (cur) {
                cur.classList.remove("shown");
                setTimeout(() => cur.remove(), 400);
            }
        });
    }
    // Removes itself after 20 s whatever happens, so it can never hide Jellyfin for good.
    window.__tvProjectCurtainTimer = setTimeout(() => c.remove(), 20000);
})(ITEM)
"""
OFF = r"""
(() => {
    const c = document.getElementById("tvProjectCurtain");
    if (!c)
        return;
    c.classList.remove("shown");  // fade out, then go
    setTimeout(() => c.remove(), 400);
})()
"""


async def evaluate(url, expression):
    import websockets
    async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expression}}))
        while json.loads(await asyncio.wait_for(ws.recv(), 10)).get("id") != 1:
            pass


def main():
    if not (sys.argv[1:2] == ["on"] and len(sys.argv) <= 3 or sys.argv[1:] == ["off"]):
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
        item = json.dumps(sys.argv[2]) if len(sys.argv) == 3 else "null"
        asyncio.run(evaluate(url, ON.replace("ITEM", item) if sys.argv[1] == "on" else OFF))


if __name__ == "__main__":
    main()
