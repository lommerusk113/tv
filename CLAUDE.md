# TV project – Google TV-style living room setup

Remaining work and decisions: see TODO.md

## Decisions (already made, do not re-litigate)
- Machine: old laptop running Bazzite, HDMI to an LG 55UJ701V TV (2017, webOS 3.5).
- Goal: a Google TV-style living room setup. Home screen = Plasma Bigscreen (KDE, Plasma 6.7+), later customized in QML.
- Apps launched from the home screen:
  - Google Chrome Flatpak (`com.google.Chrome`) in kiosk mode -> https://www.rikstv.no
  - VacuumTube (YouTube TV interface; Flathub: `rocks.shy.VacuumTube`)
  - Jellyfin Media Player (Flathub currently lists `org.jellyfin.JellyfinDesktop`)
  - Moonlight (`com.moonlight_stream.Moonlight`)
- Input: Strong Bluetooth remote (acts as a keyboard). Voice later via whisper.cpp; the remote's mic is not expected to work.
- TV control: Wake-on-LAN + bscpylgtv over Ethernet. The TV's internet is blocked in the router; local traffic is allowed.
- Later phases: custom QML home screen, app launching and key mapping, TMDb/Jellyfin recommendation rows, voice control.

## System facts (verified 2026-10-27)
- Booted image: `ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable`, 44.20261026 (Fedora 44, Kinoite base).
  - Never roll back or change deployments without asking.
- Plasma 6.7.5, Wayland session.
- `plasma-bigscreen` 6.7.5-1.fc44 layered via `rpm-ostree install` on 2026-10-27 (plus plasma-bigscreen-wayland, plasma-nano). Rebooted and active; session file `/usr/share/wayland-sessions/plasma-bigscreen-wayland.desktop`.
- Flatpaks installed (system) 2026-10-27: com.google.Chrome 156, rocks.shy.VacuumTube 2.0.1, com.moonlight_stream.Moonlight 6.2.0, org.jellyfin.JellyfinDesktop 2.0.0.
- Only display active during setup: laptop panel eDP-1, 1920x1200. The TV (HDMI) was not connected.

## Where this runs
- **Bazzite laptop (host):** the screenshot/key commands below (spectacle, ydotool) apply only here.
- **Container (any machine):** see `README.md`. Use `scripts/headless-start.sh`, `scripts/key.sh <X11 key names>`,
  `scripts/shot.sh <file>` (then Read the PNG), `scripts/stop.sh`. Log: `/tmp/homescreen.log`.
  Same Qt (Fedora 44, PySide6 6.11), Xvfb + llvmpipe. Verified 2026-10-27: identical render incl. glow.
- Repo: https://github.com/lommerusk113/tv (private).

## Screenshot command (Bazzite host only, works)
```bash
spectacle -b -n -f -o /tmp/shot.png
```
Then open `/tmp/shot.png` with the Read tool to look at it. Captures the full desktop (all outputs).

## Key-press command (Bazzite host only, works, no sudo)
The user has rw access to `/dev/uinput` via a seat ACL, so ydotoold runs as the user.
The system `ydotool.service` is disabled; do not enable it without asking. Start the daemon temporarily:
```bash
S=/run/user/1000/.ydotool_socket
(ydotoold -p $S -P 0600 >/dev/null 2>&1 &); sleep 1
YDOTOOL_SOCKET=$S ydotool key 125:1 125:0     # Meta (opens launcher) – keycodes from linux/input-event-codes.h
YDOTOOL_SOCKET=$S ydotool key 1:1 1:0         # Escape
# arrows: 103 up, 108 down, 105 left, 106 right; 28 Enter; 158 Back
pkill -u $(id -u) -x ydotoold; rm -f $S        # stop when done
```
Keys go to the focused window. Be careful when the Claude terminal has focus.

## Home screen prototype (`~/tv-project/homescreen/`)
Standalone Qt Quick (Qt 6) prototype of a Google TV-style home screen, 1920x1080 window.
Plain QtQuick + QtQuick.Effects only (no Kirigami/Plasma) so it can be ported into Bigscreen unchanged.

### Run
No `qml`/`qml6` runner is installed (it's in `qt6-qtdeclarative-devel`; the user said NOT to install it).
Use the PySide6 launcher instead (python3-pyside6 6.11.2 is in the base image):
```bash
cd ~/tv-project/homescreen && python3 run.py            # foreground, QML errors + console.log on stderr
pkill -f '^python3 run\.py'                              # stop (anchor the pattern, or pkill kills its own shell)
```
- `run.py` only sets env vars and loads `main.qml`; exits 1 if loading fails. Keep all logic in QML/JS.
- Env set by run.py: `QML_XHR_ALLOW_FILE_READ=1` (needed for XHR to read the JSON files),
  `QT_LOGGING_RULES=qml.debug=true;js.debug=true` (Fedora's `/usr/share/qt6/qtlogging.ini` has `*.debug=false`,
  which silences console.log), `QT_FORCE_STDERR_LOGGING=1`. Bigscreen will need the XHR flag too (or another loader).
- Config is read at startup: restart after editing JSON.

### Keys
Arrows move focus (row to row lands on the nearest tile horizontally), Enter activates, Escape/Back goes back
(first to tile 0 of the row, then to the tabs). Enter logs only: `launch:<app-id>` (app tiles),
`open:<item-id>` (hero/media), `tab:<name>`. Nothing is launched.
Initial focus: the row named by `layout.json` `initialFocus`.

### Files
```
homescreen/
  run.py            PySide6 launcher (no app logic)
  qmldir            registers the Config singleton + components
  main.qml          Window 1920x1080; loads the JSON via XHR into Config, then loads Home.qml
  Config.qml        singleton: theme, apps, layout, content, scale; px(v) scales 1920-based sizes; withAlpha()
  Home.qml          page: top bar (profile, tabs, clock), vertical scrolling, ALL key handling
  HeroBanner.qml    full-bleed featured carousel (Left/Right switches item)
  TileRow.qml       titled horizontal row, animated horizontal scroll, focusNearest()
  Tile.qml          tile styles app / landscape / poster; focus = scale + white outline + blurred glow
  config/theme.json, config/apps.json, config/layout.json
  data/placeholder.json   placeholder hero/continue/trending content (replace with real data later)
```

### Config format
All sizes are in 1920x1080 reference px (scaled by `Config.px()`); colors are `#rrggbb`.
- `theme.json`: `colors` {background, surface, text, textDim, accent, focusBorder, glow, onFocused},
  `font` {family, sizes{clock, tab, profile, heroMeta, heroTitle, heroBody, button, rowTitle, appName, tileTitle, tileMeta}},
  `radius`, `animationMs` (focus anim; scrolls use 2x), `focus` {scale, borderWidth, glowOpacity},
  `spacing` {page, tile, row, titleGap}, `topBar` {height}, `hero` {height}, `tiles` {app|landscape|poster: [w, h]}.
- `apps.json`: array of `{id, name, colors: [top, bottom], image: "" | path relative to homescreen/,
  imageScale (optional, icon height / tile height, default 0.5), showName (optional, default true; false for icons
  that already contain the name), launch: [argv...]}`. `launch` is stored only, never run yet.
  Icons in `homescreen/icons/`: jellyfin/moonlight SVGs copied from the installed Flatpaks
  (`/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/`), rikstv.png = rikstv.no's official 512px web-app icon, youtube.png = YouTube's official 192px favicon (from youtube.com's web manifest).
  SVG needs qt6-qtsvg (in the Dockerfile; already on the Bazzite host).
- `layout.json`: `tabs` [names], `profile` {initial, color}, `initialFocus` (row id), `rows` in display order:
  `{id, type: "hero"|"row" (default row), title, source, style: app|landscape|poster}`.
  `source` = `"apps"` (apps.json) or a key in `data/placeholder.json` (`featured`, `continueWatching`, `trending`).
  Rows whose source is empty are skipped with a warning.
- `data/placeholder.json` items: `{id, title, meta | subtitle, description (hero), progress 0..1 (optional), colors: [c0, c1, c2]}`.

### Verified 2026-10-27 (screenshots)
Key sequence Right×3, Down, Right, Down, Enter, Up×2 (+ Enter, Esc×2), horizontal scroll to the end of a row,
and theme.json / layout.json / apps.json edits all verified on the laptop panel. Not yet tested on the TV.

## Rules
- **Every UI change must be verified with a screenshot (and you must look at it) before you report it as done.**
- In the container, the system rules below are about the Bazzite host; never run real app launches anywhere yet.
- Ask before: any `rpm-ostree` change, any reboot, installing any package or Flatpak, editing anything outside `~/tv-project`, changing system or login settings, any use of sudo.
- Report each step as ✅ (done + result) or ❌ (what failed + why).
