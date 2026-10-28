#!/usr/bin/env python3
"""Back on Jellyfin's start page goes to the TV home screen (Jellyfin itself does nothing there).

  python3 jellyfin_back.py   runs until the home screen (its parent) goes away: whenever Jellyfin Desktop runs, it adds
                             a key handler to its page over Jellyfin's DevTools port; Back/Escape on the start page
                             (no dialog open, not typing) logs a marker, and this sends "show_home" to the home screen
                             (remote.py send)

The port comes from the Flatpak override QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:9232 (scripts/install-jellyfin-debug.sh),
on 127.0.0.1 only. Needs the websockets module: reruns itself in the tv-project venv like youtube_tv.py.
"""
import asyncio
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

PORT = int(os.environ.get("JELLYFIN_DEBUG_PORT", "9232"))
MARKER = "tv-project:back-at-home"
HERE = Path(__file__).resolve().parent
VENV_PYTHON = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "tv-project/venv/bin/python"

# Installed once per page. Jellyfin Desktop turns remote/keyboard keys into commands ("back", "up"...) on
# window.api.input.hostInput instead of DOM key events, so listen there (keydown too, for a plain keyboard).
# Jellyfin's own handler may already have closed a dialog when ours runs, so a dialog open in the last moment counts.
HANDLER = r"""
if (!window.__tvProjectBack) {
    window.__tvProjectBack = true;
    let dialogAt = 0;
    setInterval(() => {
        if (document.querySelector(".dialogContainer .dialog, .dialog.opened"))
            dialogAt = Date.now();
    }, 150);
    const back = () => {
        const typing = /^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement || {}).tagName || "");
        const atHome = /^#\/(home(\.html)?)?(\?|$)/.test(location.hash);
        if (atHome && !typing && Date.now() - dialogAt > 400) {
            console.info("MARKER");
            return true;
        }
        return false;
    };
    const hook = () => {
        if (!(window.api && window.api.input && window.api.input.hostInput))
            return setTimeout(hook, 500);
        window.api.input.hostInput.connect(actions => { if (actions.includes("back")) back(); });
    };
    hook();
    document.addEventListener("keydown", e => {
        if (["Escape", "GoBack", "BrowserBack"].includes(e.key) && back()) {
            e.preventDefault();
            e.stopImmediatePropagation();
        }
    }, true);
}
""".replace("MARKER", MARKER)


def page_socket():
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/json" % PORT, timeout=3) as res:
            pages = [t for t in json.load(res) if t.get("type") == "page" and t.get("url", "").startswith("http")]
    except (OSError, ValueError):
        return None
    return pages[0]["webSocketDebuggerUrl"] if pages else None


async def watch(url, parent):
    import websockets
    async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
        # Runtime.enable replays the page's earlier console messages: only react to newer ones.
        since = time.time() * 1000
        for i, (method, params) in enumerate([
                ("Runtime.enable", {}),
                ("Page.addScriptToEvaluateOnNewDocument", {"source": HANDLER}),  # after reloads
                ("Runtime.evaluate", {"expression": HANDLER})], 1):  # the page as it is now
            await ws.send(json.dumps({"id": i, "method": method, "params": params}))
        while os.getppid() == parent:
            try:
                msg = json.loads(await asyncio.wait_for(ws.recv(), 5))
            except asyncio.TimeoutError:
                continue
            if msg.get("method") == "Runtime.consoleAPICalled" and msg["params"].get("timestamp", 0) >= since:
                if any(a.get("value") == MARKER for a in msg["params"].get("args", [])):
                    subprocess.run([sys.executable, str(HERE / "remote.py"), "send", "show_home"])


def main():
    try:
        import websockets  # noqa: F401
    except ImportError:
        if VENV_PYTHON.exists() and not os.environ.get("JELLYFIN_BACK_IN_VENV"):
            os.environ["JELLYFIN_BACK_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), __file__, *sys.argv[1:]])
        sys.exit("jellyfin_back: needs the websockets module (scripts/install-tv-power.sh makes the venv)")
    parent = os.getppid()
    while os.getppid() == parent:  # quit when the home screen goes away
        url = page_socket()
        if url:
            try:
                asyncio.run(watch(url, parent))
            except Exception as e:  # Jellyfin closed or reloaded: look again
                print(f"jellyfin_back: {type(e).__name__}: {e}", file=sys.stderr)
        asyncio.run(asyncio.sleep(3))


if __name__ == "__main__":
    main()
