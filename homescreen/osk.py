#!/usr/bin/env python3
"""On-screen keyboard for apps that are web pages (Jellyfin Desktop, the Jellyseerr kiosk): OK on a text field opens
the home screen's keyboard (bigscreen/HomeScreen.qml, TextEntry.qml), which types into that field over DevTools.

  python3 osk.py watch               runs until the home screen (its parent) goes away: adds a handler to each app's
                                     page (Jellyseerr also gets a visible TV focus, TV_FOCUS); OK (Enter /
                                     Jellyfin's "enter" command) on a text field logs a marker, and this sends "keyboard:<app>:<url-encoded {type, value, label}>" to the home screen
                                     (remote.py send). Password values are not sent.
  python3 osk.py set <app> <text>    replace the focused field's text (url-encoded, so any character fits a command
                                     line); typed with Input.insertText, so the page sees real typing (React etc.)
  python3 osk.py enter <app>         press Enter in the field (submit), without opening the keyboard again

DevTools ports, 127.0.0.1 only: Jellyfin 9232 (scripts/install-jellyfin-debug.sh), Jellyseerr 9233 (jellyseerr.py
open). YouTube has its own keyboard. Needs the websockets module: reruns itself in the tv-project venv.
"""
import asyncio
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

PORTS = {"jellyfin": 9232, "jellyseerr": 9233}
MARKER = "tv-project:keyboard"
HERE = Path(__file__).resolve().parent
VENV_PYTHON = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "tv-project/venv/bin/python"

# Installed once per page. Chrome gets the remote's OK as a DOM Enter; Jellyfin Desktop sends remote keys as commands
# on window.api.input.hostInput instead (OK = "enter"). Enter right after `osk.py enter` (__tvKeyboardSkip) is the
# submit: let it be.
HANDLER = r"""
if (!window.__tvKeyboard) {
    window.__tvKeyboard = true;
    let opened = 0;
    const editable = el => !!el && !el.disabled && !el.readOnly && (el.tagName === "TEXTAREA" || el.tagName === "INPUT"
        && /^(text|search|email|password|url|tel|number)?$/.test(el.getAttribute("type") || ""));
    const open = () => {
        const el = document.activeElement;
        if (!editable(el) || Date.now() - opened < 600)
            return editable(el);
        opened = Date.now();
        const label = el.getAttribute("placeholder") || el.getAttribute("aria-label")
            || (el.labels && el.labels[0] && el.labels[0].textContent) || el.name || "";
        const type = el.type === "password" ? "password" : el.type === "email" ? "email" : "text";
        console.info("MARKER", JSON.stringify({type, value: type === "password" ? "" : el.value,
                                               label: label.trim().slice(0, 60)}));
        return true;
    };
    document.addEventListener("keydown", e => {
        if (e.key !== "Enter" || Date.now() - (window.__tvKeyboardSkip || 0) < 1500)
            return;
        if (open()) {
            e.preventDefault();
            e.stopImmediatePropagation();
        }
    }, true);
    // A login page starts on its first field (otherwise the first arrow goes to whatever spatial navigation finds).
    const startOnLogin = () => {
        if (!/login|signin/i.test(location.pathname + location.hash)
                || document.activeElement && document.activeElement !== document.body)
            return;
        const first = [...document.querySelectorAll("input")].find(el => editable(el) && el.offsetParent);
        if (first)
            first.focus();
    };
    new MutationObserver(startOnLogin).observe(document.documentElement, {childList: true, subtree: true});
    startOnLogin();
    let tries = 0;
    const hook = () => {
        if (window.api && window.api.input && window.api.input.hostInput)
            window.api.input.hostInput.connect(actions => {
                if (actions.includes("enter") || actions.includes("select"))
                    open();
            });
        else if (++tries < 20)
            setTimeout(hook, 500);
    };
    hook();
}
""".replace("MARKER", MARKER)

# Jellyseerr is a desktop site: Chrome's spatial navigation moves the focus, but the site's focus outline is a dark
# 1 px line. A TV focus instead (white ring + glow, like the home screen's tiles), and the focused thing is scrolled
# to the middle when it gets near an edge (spatial navigation only scrolls it just into view).
TV_FOCUS = r"""
if (!window.__tvFocus) {
    window.__tvFocus = true;
    const css = `
        :focus { outline: none !important; }
        :focus-visible {
            outline: 4px solid #ffffff !important;
            outline-offset: -4px !important;
            box-shadow: 0 0 0 4px #ffffff, 0 0 32px 8px rgba(255, 255, 255, 0.5) !important;
            border-radius: 10px;
            filter: brightness(1.12);
            transform: scale(1.06) !important;
            transition: transform 120ms ease-out, box-shadow 120ms ease-out;
            z-index: 10;
        }`;
    const addStyle = () => {
        const style = document.createElement("style");
        style.textContent = css;
        document.head.appendChild(style);
    };
    if (document.head)
        addStyle();
    else
        document.addEventListener("DOMContentLoaded", addStyle);
    document.addEventListener("focusin", e => {
        const r = e.target.getBoundingClientRect();
        if (r.top < 90 || r.bottom > innerHeight - 60)
            e.target.scrollIntoView({block: "center", inline: "nearest", behavior: "smooth"});
    }, true);
}
"""
# Jellyfin Desktop, TV layout: a focus you can see from the sofa (white instead of a thin blue tint), and ← → that
# seek in the player. Jellyfin gets remote keys as hostInput commands; with the player's controls hidden "left"/"right"
# skip without showing anything, and once the controls are up they only move between the buttons, so the timeline
# never moves. Here they become the arrow keys of Jellyfin's own keyboard path instead: controls up with the timeline
# focused, each press moves it by Jellyfin's skip lengths (10 s back / 30 s ahead by default; Settings → Playback),
# and 1 s after the last press it jumps there. On the buttons (or with a menu open) the arrows still move between them.
JELLYFIN_TV = r"""
if (!window.__tvPlayer) {
    window.__tvPlayer = true;
    const css = `
        .paper-icon-button-light.show-focus:focus {
            background: #ffffff !important; color: #101010 !important;
            box-shadow: 0 0 0 3px #ffffff, 0 0 28px 8px rgba(255, 255, 255, 0.45) !important;
        }
        .mdl-slider.show-focus:focus::-webkit-slider-thumb {
            transform: scale(2.2) !important; background: #ffffff !important;
            box-shadow: 0 0 14px 4px rgba(255, 255, 255, 0.7) !important;
        }
        .card:focus .cardBox.visualCardBox, .card:focus .cardBox:not(.visualCardBox) .cardScalable {
            border-color: #ffffff !important;
            box-shadow: 0 0 0 3px #ffffff, 0 0 36px 10px rgba(255, 255, 255, 0.4) !important;
        }
        .emby-button.show-focus:focus, .layout-tv .emby-button.detailFloatingButton:focus {
            background: #ffffff !important; color: #101010 !important;
            box-shadow: 0 0 28px 6px rgba(255, 255, 255, 0.4) !important;
        }
        .listItem:focus, .actionSheetMenuItem:focus { background: #ffffff !important; color: #101010 !important; }
        .emby-tab-button.show-focus:focus { color: #ffffff !important; box-shadow: inset 0 -4px 0 #ffffff !important; }`;
    const addStyle = () => {
        const style = document.createElement("style");
        style.textContent = css;
        document.head.appendChild(style);
    };
    if (document.head)
        addStyle();
    else
        document.addEventListener("DOMContentLoaded", addStyle);

    const seek = action => {
        const slider = document.querySelector(".videoOsdBottom .osdPositionSlider");
        if (!location.hash.startsWith("#/video") || !slider || document.querySelector(".dialogContainer"))
            return false;
        const osd = slider.closest(".videoOsdBottom");
        const hidden = osd.classList.contains("hide") || osd.classList.contains("videoOsdBottom-hidden");
        if (!hidden && document.activeElement !== slider)
            return false;
        const right = action === "right";
        const key = right ? "ArrowRight" : "ArrowLeft";
        // Hidden: Jellyfin's player page shows the controls, focuses the timeline and steps it. Up: the timeline steps.
        (hidden ? document.activeElement || document.body : slider).dispatchEvent(new KeyboardEvent("keydown",
            {key, code: key, keyCode: right ? 39 : 37, which: right ? 39 : 37, bubbles: true, cancelable: true}));
        return true;
    };
    // Put this in front of Jellyfin's own hostInput callback (qwebchannel keeps them in __objectSignals__).
    let tries = 0;
    const wrap = () => {
        const input = window.api && window.api.input;
        const lists = input && input.__objectSignals__ ? Object.values(input.__objectSignals__) : [];
        if (lists.some(l => l.some(f => f.__tv)))
            return;
        const list = lists.find(l => l.some(f => String(f).includes("inputManager.handleCommand")));
        const at = list ? list.findIndex(f => String(f).includes("inputManager.handleCommand")) : -1;
        if (at < 0) {
            if (++tries < 40)
                setTimeout(wrap, 500);
            return;
        }
        const original = list[at];
        const wrapped = actions => {
            let rest = actions;
            try {
                rest = actions.filter(a => !((a === "left" || a === "right") && seek(a)));
            } catch (e) {
                console.warn("tv seek:", e);
            }
            if (rest.length)
                original(rest);
        };
        wrapped.__tv = true;
        list[at] = wrapped;
    };
    wrap();
}
"""
SCRIPTS = {"jellyfin": HANDLER + JELLYFIN_TV, "jellyseerr": HANDLER + TV_FOCUS}


def page_socket(port):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/json" % port, timeout=3) as res:
            pages = [t for t in json.load(res) if t.get("type") == "page" and t.get("url", "").startswith("http")]
    except (OSError, ValueError):
        return None
    return pages[0]["webSocketDebuggerUrl"] if pages else None


async def call(ws, calls, first_id=1):
    """Send DevTools calls in order and wait for each answer (5 s each: a page in the middle of loading may never
    answer)."""
    async def answer(i):
        while json.loads(await ws.recv()).get("id") != i:
            pass
    for i, (method, params) in enumerate(calls, first_id):
        await ws.send(json.dumps({"id": i, "method": method, "params": params}))
        await asyncio.wait_for(answer(i), 5)


async def watch_app(app, port, parent):
    import websockets
    while os.getppid() == parent:
        url = page_socket(port)
        if not url:
            await asyncio.sleep(3)
            continue
        try:
            async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
                since = time.time() * 1000  # Runtime.enable replays older console messages
                script = SCRIPTS[app]
                await call(ws, [("Page.addScriptToEvaluateOnNewDocument", {"source": script}),
                                ("Runtime.evaluate", {"expression": script}),
                                ("Runtime.enable", {})])
                injected = time.monotonic()
                while os.getppid() == parent:
                    # Again every 5 s (it does nothing when already there): a reload or a new page may have come
                    # without it.
                    if time.monotonic() - injected > 5:
                        injected = time.monotonic()
                        await ws.send(json.dumps({"id": 1000, "method": "Runtime.evaluate",
                                                  "params": {"expression": script}}))
                    try:
                        msg = json.loads(await asyncio.wait_for(ws.recv(), 5))
                    except asyncio.TimeoutError:
                        continue
                    if msg.get("method") != "Runtime.consoleAPICalled" or msg["params"].get("timestamp", 0) < since:
                        continue
                    args = [a.get("value") for a in msg["params"].get("args", [])]
                    if len(args) == 2 and args[0] == MARKER:
                        subprocess.run([sys.executable, str(HERE / "remote.py"), "send",
                                        f"keyboard:{app}:{urllib.parse.quote(args[1])}"])
        except Exception as e:  # app closed or reloaded: look again
            print(f"osk: {app}: {type(e).__name__}: {e}", file=sys.stderr)
        await asyncio.sleep(3)


async def watch():
    parent = os.getppid()
    await asyncio.gather(*(watch_app(app, port, parent) for app, port in PORTS.items()))


async def type_into(app, text=None, enter=False):
    import websockets
    url = page_socket(PORTS[app])
    if not url:
        sys.exit(f"osk: {app} has no page on its DevTools port")
    async with websockets.connect(url, max_size=None, open_timeout=5) as ws:
        if enter:
            key = {"key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13}
            await call(ws, [("Runtime.evaluate", {"expression": "window.__tvKeyboardSkip = Date.now()"}),
                            ("Input.dispatchKeyEvent", {"type": "keyDown", "text": "\r", **key}),
                            ("Input.dispatchKeyEvent", {"type": "keyUp", **key})])
            return
        # Select what is there, then type over it (Backspace when the new text is empty).
        calls = [("Runtime.evaluate", {"expression": "document.activeElement && document.activeElement.select"
                                                     " && document.activeElement.select()"})]
        if text:
            calls.append(("Input.insertText", {"text": text}))
        else:
            key = {"key": "Backspace", "code": "Backspace", "windowsVirtualKeyCode": 8, "nativeVirtualKeyCode": 8}
            calls += [("Input.dispatchKeyEvent", {"type": "rawKeyDown", **key}),
                      ("Input.dispatchKeyEvent", {"type": "keyUp", **key})]
        await call(ws, calls)


def main():
    try:
        import websockets  # noqa: F401
    except ImportError:
        if VENV_PYTHON.exists() and not os.environ.get("OSK_IN_VENV"):
            os.environ["OSK_IN_VENV"] = "1"
            os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), __file__, *sys.argv[1:]])
        sys.exit("osk: needs the websockets module (scripts/install-tv-power.sh makes the venv)")
    args = sys.argv[1:]
    if args == ["watch"]:
        asyncio.run(watch())
    elif len(args) == 3 and args[0] == "set" and args[1] in PORTS:
        asyncio.run(type_into(args[1], urllib.parse.unquote(args[2])))
    elif len(args) == 2 and args[0] == "set" and args[1] in PORTS:
        asyncio.run(type_into(args[1], ""))
    elif len(args) == 2 and args[0] == "enter" and args[1] in PORTS:
        asyncio.run(type_into(args[1], enter=True))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
