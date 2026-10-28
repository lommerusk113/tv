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
  `scripts/vnc.sh` shares the screen over VNC (README). `scripts/bigscreen-start.sh` instead runs it inside the real Bigscreen 6.7.5 containment (plasmoidviewer + openbox,
  same key.sh/shot.sh/stop.sh). Apps don't exist there, so launches do nothing. Upstream logs `appletsLayout is not defined`
  (harmless, from the dummy clock applet plasmoidviewer requires).
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
  which silences console.log), `QT_FORCE_STDERR_LOGGING=1`. Bigscreen reads the JSON with `cat` instead (see Bigscreen integration).
- Config is read at startup: restart after editing JSON.

### Keys
Keys come from `config/keymap.json` (see Config format). Default: arrows move focus (row to row lands on the nearest tile horizontally), Enter activates, Escape/Back goes back
(first to tile 0 of the row, then to the tabs; in Bigscreen one more Back opens Bigscreen's overlay: tasks, search, settings).
Enter on an app tile logs `launch:<app-id>` and, in Bigscreen only, starts the app (`Config.launch`, see Bigscreen below);
the prototype only logs. Hero/media logs `open:<item-id>`, tabs log `tab:<name>`.
Initial focus: the row named by `layout.json` `initialFocus`. Home (`HomePage`, X11 `XF86HomePage`) resets every row
to tile 0, scrolls to the top and returns to that row. F1-F4 = `launch:youtube|jellyfin|rikstv|moonlight`; volume keys log `action:volume_*`.

### Files
```
homescreen/
  run.py            PySide6 launcher (no app logic)
  qmldir            registers the Config singleton + components
  main.qml          prototype Window 1920x1080 containing TvHome
  TvHome.qml        loads the JSON into Config (readFile: XHR by default), then loads Home.qml; atTop for Bigscreen's Back
  Config.qml        singleton: theme, apps, layout, content, keymap, scale; px(v); withAlpha(); launch(appId) -> launcher hook
  Home.qml          page: top bar (profile, tabs, clock), vertical scrolling, ALL key handling
  HeroBanner.qml    full-bleed featured carousel (Left/Right switches item)
  TileRow.qml       titled horizontal row, animated horizontal scroll, focusNearest()
  Tile.qml          tile styles app / landscape / poster; focus = scale + white outline + blurred glow
  config/theme.json, config/apps.json, config/layout.json, config/keymap.json
  data/placeholder.json   placeholder hero/continue/trending content (replace with real data later)
  desktop/tv-rikstv.desktop  Chrome kiosk on rikstv.no; install-bigscreen.sh copies it to ~/.local/share/applications
bigscreen/HomeScreen.qml    replaces the stock plasmoid's HomeScreen.qml (see Bigscreen below)
scripts/install-bigscreen.sh  host: install/--remove the home screen in Bigscreen; container: used by bigscreen-start.sh
```

### Config format
All sizes are in 1920x1080 reference px (scaled by `Config.px()`); colors are `#rrggbb`.
- `theme.json`: `colors` {background, surface, text, textDim, accent, focusBorder, glow, onFocused},
  `font` {family, sizes{clock, tab, profile, heroMeta, heroTitle, heroBody, button, rowTitle, appName, tileTitle, tileMeta}},
  `radius`, `animationMs` (focus anim; scrolls use 2x), `focus` {scale, borderWidth, glowOpacity},
  `spacing` {page, tile, row, titleGap}, `topBar` {height}, `hero` {height}, `tiles` {app|landscape|poster: [w, h]}.
- `apps.json`: array of `{id, name, colors: [top, bottom], image: "" | path relative to homescreen/,
  imageScale (optional, icon height / tile height, default 0.5), showName (optional, default true; false for icons
  that already contain the name), desktopId: "<storage id>.desktop"}`. Launched via Bigscreen's app model; the Flatpak
  ids are their app id + `.desktop` (not yet checked on the host); RiksTV uses our `tv-rikstv.desktop`.
  Icons in `homescreen/icons/`: jellyfin/moonlight SVGs copied from the installed Flatpaks
  (`/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/`), rikstv.png = rikstv.no's official 512px web-app icon, youtube.png = YouTube's official 192px favicon (from youtube.com's web manifest).
  SVG needs qt6-qtsvg (in the Dockerfile; already on the Bazzite host).
- `layout.json`: `tabs` [names], `profile` {initial, color}, `initialFocus` (row id), `rows` in display order:
  `{id, type: "hero"|"row" (default row), title, source, style: app|landscape|poster}`.
  `source` = `"apps"` (apps.json) or a key in `data/placeholder.json` (`featured`, `continueWatching`, `trending`).
  Rows whose source is empty are skipped with a warning.
- `keymap.json`: `{ "<Qt key name>": "<action>" }`; the name is `Qt.Key_<name>` without the prefix (`Left`, `Return`,
  `Back`, `HomePage`, `VolumeUp`, `F1`...). Actions: `left right up down select back home`, `launch:<app-id>` (logged),
  anything else is logged as `action:<name>` (not implemented yet). Unknown key names / app ids are warned on stderr.
  Placeholder bindings until the remote's real key codes are captured (Phase 1).
- `data/placeholder.json` items: `{id, title, meta | subtitle, description (hero), progress 0..1 (optional), colors: [c0, c1, c2]}`.

### Verified 2026-10-27 (screenshots)
Key sequence Right×3, Down, Right, Down, Enter, Up×2 (+ Enter, Esc×2), horizontal scroll to the end of a row,
and theme.json / layout.json / apps.json edits all verified on the laptop panel. Not yet tested on the TV.
keymap.json verified 2026-10-28 in the container: Home key, F2/F4 launch logs, volume/mute action logs, warnings for
an unknown key name and an unknown app id.

## Bigscreen integration (built 2026-10-28, tested in the container only, not yet on the host)
- Session: `plasma-bigscreen-wayland` sources `plasma-bigscreen-common-env` (`PLASMA_DEFAULT_SHELL=org.kde.plasma.bigscreen`),
  then `startplasma-wayland`. The shell's `contents/defaults` sets `Containment=org.kde.bigscreen.homescreen`.
- That containment = QML package `/usr/share/plasma/plasmoids/org.kde.bigscreen.homescreen/` + C++ plugin
  `/usr/lib64/qt6/plugins/plasma/applets/org.kde.bigscreen.homescreen.so`. Its `ui/main.qml` does the overlay (Meta/Back:
  tasks, search, settings), toggleHomeScreen shortcut (minimize all), startup feedback, wallpaper; then `HomeScreen {}`.
- `scripts/install-bigscreen.sh` copies it to `~/.local/share/plasma/plasmoids/` (the user copy wins, verified; the .so still
  loads), swaps in `bigscreen/HomeScreen.qml`, symlinks `homescreen/` as `contents/ui/tv`, installs `homescreen/desktop/*.desktop`,
  clears `~/.cache/plasmashell/qmlcache`. Refuses if plasma-bigscreen != 6.7.5 (`FORCE=1` after checking upstream main.qml).
  `--remove` restores the stock home screen. Edits under homescreen/ need only a plasmashell restart.
- `bigscreen/HomeScreen.qml`: reads the JSON with the plasma5support `executable` engine (`cat`), because plasmashell has no
  `QML_XHR_ALLOW_FILE_READ`; sets `Config.launcher` to `Plasmoid.applicationListModel` (maximize if running, else
  runApplication(desktopId), verified with a fake .desktop in the container); enables upstream's BackHandler only when
  Home is at the tabs; refocuses Home when the window becomes active.
- Try without logging out: `/usr/bin/plasma-bigscreen-swap-session` = `plasmashell --replace` with the Bigscreen env in the
  current session; run again to swap back. Ask before running it (session change).

## Rules
- **Every UI change must be verified with a screenshot (and you must look at it) before you report it as done.**
- In the container, the system rules below are about the Bazzite host; never run real app launches anywhere yet.
- Ask before: any `rpm-ostree` change, any reboot, installing any package or Flatpak, editing anything outside `~/tv-project`, changing system or login settings, any use of sudo.
- Report each step as ✅ (done + result) or ❌ (what failed + why).
