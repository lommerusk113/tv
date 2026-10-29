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
(first to tile 0 of the row, then to the start row `initialFocus`; in Bigscreen one more Back opens Bigscreen's overlay: tasks,
search, settings). Up stops at the hero; there is no top bar (removed 2026-10-29: only a clock/weather in the corner).
Enter on an app tile logs `launch:<app-id>` and, in Bigscreen only, starts the app (`Config.launch`, see Bigscreen below);
the prototype only logs. Hero/media log `open:<item-id>` and run the item's `action` (`Config.run`), e.g.
`jellyfin_play_id:<id>` or `youtube_watch:<id>`.
Initial focus: the row named by `layout.json` `initialFocus`. Home (`HomePage`, X11 `XF86HomePage`) resets every row
to tile 0, scrolls to the top and returns to that row. F1-F4 = `launch:youtube|jellyfin|rikstv|moonlight`; volume keys log `action:volume_*`.

### Files
```
homescreen/
  run.py            PySide6 launcher (no app logic)
  qmldir            registers the Config singleton + components
  main.qml          prototype Window 1920x1080 containing TvHome
  TvHome.qml        loads the JSON into Config (readFile: XHR by default), then loads Home.qml; atTop for Bigscreen's Back;
                    overlays ~/.cache/tv-project/content.json (live rows) on placeholder.json; reloadLive()
  recommend.py      banner homeFeatured (Trakt top picks only, via jellyfin.featured: 6, one per franchise;
                    layout hero source ["homeFeatured", "jellyfinFeatured", "featured"]) and
                    "Recommended for you" (traktRecommended): Trakt /recommendations/movies+shows (100 each, cached 6 h
                    in trakt-recommendations.json), interleaved, matched to Jellyfin by tmdb/imdb/tvdb ProviderIds,
                    finished/started left out, max 20, Jellyfin tiles ("Film · 2025"). Run on every home-screen
                    activation (instead of `trakt.py sync`). test_recommend.py. Login done 2026-10-29: new Trakt apps
                    are PKCE-only (no client secret, redirect must be localhost); the device-code login needs only
                    clientId. Free accounts have a limit on connected apps.
  jellyseerr.py     "Get more" row (traktMissing): Trakt picks NOT on the server (recommend.py writes
                    trakt-missing.json) with Jellyseerr 3.1's poster (TMDb w342, no TMDb key needed), year, status
                    ("Requested"/"Downloading"; available/blacklisted left out); `request movie|tv <tmdb>` POSTs
                    /api/v1/request (tv: seasons "all"). secrets "jellyseerr": {url, apiKey}; the key's user is
                    admin, so requests are auto-approved. Tile action request:<kind>:<tmdb>:<title> -> RequestDialog.qml
                    (Request/Cancel) -> Config.system("jellyseerr_request:...") -> message on the home screen.
  moonlight.py      Moonlight (Flatpak CLI list/stream/pair/quit), config/moonlight.json {host, tileApp, options}:
                    "Games" row (moonlightApps, plain `list` output: `--csv` hangs against Wolf), `stream [app]` (the
                    Moonlight tile does this; without a host it opens Moonlight), `pair <host> <pin>`, `quit` =
                    Ctrl+Alt+Shift+Q via ydotool (red button, global shortcut "Red"; verified to work during a stream).
                    Host: Wolf (games-on-whales) on 192.168.0.100, run by Coolify (service usnnqk2hwn9yjp419cdp8zd0),
                    paired 2026-10-29, tileApp "Wolf UI". Pairing: Wolf logs "Insert pin at http://..:47989/pin/#.."
                    (`docker logs <wolf> | grep -i pin`). Wolf ignores Moonlight's "quit app" prompt: a leftover
                    session blocks other apps (`moonlight quit <host>`).
                    Wolf/NVIDIA "no video": driver files live in a Docker volume built for one host driver version;
                    after a host driver update -> CUDA_ERROR_SYSTEM_DRIVER_MISMATCH + EGL failure. Fix: rebuild
                    gow/nvidia-driver for `cat /sys/module/nvidia/version` (docker build from an EMPTY dir), remove
                    the containers using the volume, `docker volume rm <volume>`, `docker create --mount
                    source=<volume>,...` (only fills an EMPTY volume), then restart Wolf. Coolify prefixes volume
                    names (usnnqk..._nvidia-driver-vol, see NVIDIA_DRIVER_VOLUME_NAME) and its Docker cleanup deletes
                    unused images (Wolf app images too). Recreate Wolf: sudo docker compose -p <uuid> -f
                    /data/coolify/services/<uuid>/docker-compose.yml --project-directory <same> up -d.
  trakt.py          Trakt "Up next": `auth` (device code login), `sync` (writes content.json); stdlib only;
                    update_content() = locked, atomic merge into content.json (each script owns its keys)
  tmdb.py           TMDb "trending" key (posters); test_tmdb.py = mock test (`--keep DIR` to view it in the prototype)
  jellyfin.py       Jellyfin rows: jellyfinContinue ("Continue watching" = started videos, most recent first, then the
                    next episode of followed series; one tile per series), jellyfinFeatured (banner), also
                    jellyfinResume / jellyfinNextUp; play/play-id/pull/playing/home; test_jellyfin.py (`--keep DIR`)
  voice.py          `listen` (arecord 4 s -> whisper-cli -> action), `file <wav>`, `parse <text>`; config/voice.json;
                    test_voice.py (`--whisper` also transcribes whisper.cpp's jfk.wav)
  VoiceOverlay.qml  push-to-talk feedback pill (bottom centre) (also "busy" status: showStatus("Starting…"))
  SettingsPanel.qml slide-in from the right (Settings tile, gear button, "open settings"), pages: main (volume
                    left/right; links), Wi-Fi (on/off, rescan, networks: OK connects/disconnects, unknown secured ->
                    password page), Bluetooth (on/off, search 8 s, OK connects/disconnects/pairs), Display (per screen:
                    use it (2+ screens), sliders for resolution and size 100-200 % only choose; Apply sets both ->
                    "Keep these settings" 15 s auto-revert / Go back),
                    Power (TV off, sleep, restart/shut down need a second OK). Back = up a page / close. While open,
                    Home routes keys to it and atRoot is false (Back does not open Bigscreen's overlay). Look: cards
                    with Breeze icons (icons/settings/, copied from breeze-dark, tinted with MultiEffect), toggles,
                    sliders, section headers. Avoid property names Item already has (`top` is FINAL: page fails to load)
  OnScreenKeyboard.qml  remote-driven keyboard (arrows + OK; æøå, ⇧, #+=, space, ⌫, OK) on the Wi-Fi password page.
                    The password is a plain string (SettingsPanel.password); a real keyboard types via
                    SettingsPanel.typeKey() from Home's key handler. Never give a hidden TextInput focus: it kept the
                    focus after leaving the page and swallowed the arrows (2026-10-29 bug).
                    Plasma Keyboard (plasma-keyboard, KWin /VirtualKeyboard mode 2 = any input) does pop up for text
                    fields, but arrow keys go to the app, so it cannot be used with the remote; left at mode 1.
                    Jellyfin (TV layout) and YouTube TV have their own remote keyboards in search.
  jellyfin_nav.py   `search <text>`: Jellyfin's search page with the text typed in (voice "search for X")
  system.py         backend for those pages: nmcli, bluetoothctl, kscreen-doctor; JSON out ({"error"} + exit 1);
                    refuses to disable the last screen
  apps.py           (not in the layout since 2026-10-29) "More apps" row (installedApps): every exported Flatpak .desktop not pinned in apps.json, with its
                    hicolor icon; action launch_desktop:<id>; test_apps.py
  youtube.py        "New from your channels" (channel /videos pages, config/youtube.json) + "Recommended on YouTube"
                    and history progress (youtube_tv.py + youtube_tv.js, VacuumTube's DevTools port); test_youtube.py
  media.py          pause (MPRIS), leave (pause + Jellyfin GoHome), YouTube deeplinks (search, history, watch, home)
  remote.py         global remote buttons (config/remote.json -> X-KDE-Shortcuts .desktop files) and the FIFO to Home
  jellyfin_back.py  Back on Jellyfin's start page -> home screen (see DevTools ports)
  jellyfin_curtain.py  loading screen over Jellyfin's page while a tile starts a video (`on [item id]`/`off`): built
                    in the page with its ApiClient (backdrop, logo, episode line, bar), fades out
  tvpower.py        LG TV on/off: WOL + bscpylgtv (venv ~/.local/share/tv-project/venv, reruns itself there);
                    `on|off|pair|status|watch-sleep`; settings "tv": {ip, mac, input}; test_tvpower.py (no TV needed)
  test_trakt.py     runs trakt.py auth + sync against a local mock Trakt API: python3 homescreen/test_trakt.py
  weather.py        MET Norway (Yr) current weather -> ~/.cache/tv-project/weather.json; test_weather.py = mock test
  Config.qml        singleton: theme, apps, layout, content, keymap, scale; px(v); withAlpha(); launch(appId) -> launcher hook
  Home.qml          page: corner clock/weather, vertical scrolling, ALL key handling
  HeroBanner.qml    full-bleed featured carousel (Left/Right switches item)
  TileRow.qml       titled horizontal row, animated horizontal scroll (focused tile at the left margin), focusNearest();
                    tiles scrolled past the margin fade out; round ‹ › arrows in the margins when tiles are hidden
                    (› only on the focused row). Note: QT_QPA_PLATFORM=offscreen does not draw MultiEffect (tinted icons
                    look empty there); check those in Bigscreen
  Tile.qml          tile styles app / landscape / poster; focus = scale + white outline + blurred glow
  config/theme.json, config/apps.json, config/layout.json, config/keymap.json
  data/placeholder.json   placeholder featured/upNext/trending content; keys in content.json override it
  desktop/tv-rikstv.desktop  Chrome kiosk on rikstv.no; install-bigscreen.sh copies it to ~/.local/share/applications
bigscreen/HomeScreen.qml    replaces the stock plasmoid's HomeScreen.qml (see Bigscreen below)
scripts/install-bigscreen.sh  host: install/--remove the home screen in Bigscreen; container: used by bigscreen-start.sh
scripts/install-tv-power.sh   host: bscpylgtv venv + tv-sleep.service (systemd user unit, systemd-inhibit delay lock + gdbus
                              PrepareForSleep -> tvpower off/on); --remove. NOT run yet (auto mode refused; user runs it)
scripts/focus-home.sh         host: give keyboard focus to Bigscreen's home screen before ydotool tests
scripts/install-voice.sh      host: brew whisper-cpp + ggml-base.bin (sha1-checked) in ~/.local/share/tv-project/whisper; --remove
```

### Config format
All sizes are in 1920x1080 reference px (scaled by `Config.px()`); colors are `#rrggbb`.
- `theme.json`: `colors` {background, surface, text, textDim, accent, focusBorder, glow, onFocused},
  `font` {family, sizes{clock, clockDate, tab, heroMeta, heroTitle, heroBody, button, rowTitle, appName, tileTitle, tileMeta}},
  `radius`, `animationMs` (focus anim; scrolls use 2x), `focus` {scale, borderWidth, glowOpacity},
  `spacing` {page, tile, row, titleGap}, `topBar` {height}, `hero` {height}, `tiles` {app|landscape|poster: [w, h]}.
- `apps.json`: array of `{id, name, colors: [top, bottom], image: "" | path relative to homescreen/, action (optional:
  a built-in "app" such as Settings, run instead of launching), voiceNames (optional),
  imageScale (optional, icon height / tile height, default 0.5), showName (optional, default true; false for icons
  that already contain the name), desktopId: "<storage id>.desktop"}`. Launched via Bigscreen's app model; the Flatpak
  ids are their app id + `.desktop` (not yet checked on the host); RiksTV uses our `tv-rikstv.desktop`.
  Icons in `homescreen/icons/`: jellyfin/moonlight SVGs copied from the installed Flatpaks
  (`/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/`), rikstv.png = rikstv.no's official 512px web-app icon, youtube.png = YouTube's official 192px favicon (from youtube.com's web manifest).
  SVG needs qt6-qtsvg (in the Dockerfile; already on the Bazzite host).
- `layout.json`: `initialFocus` (row id), `rows` in display order:
  `{id, type: "hero"|"row" (default row), title, source, style: app|landscape|poster}`.
  `source` = `"apps"` (apps.json) or a content key, or a list of keys (first with items wins, e.g.
  `["jellyfinFeatured", "featured"]`): live keys from ~/.cache/tv-project/content.json (jellyfin.py, youtube.py, tmdb.py,
  trakt.py) over `data/placeholder.json` (`featured`, `continueWatching`, `trending`).
  Rows whose source is empty are skipped with a warning.
- `keymap.json`: `{ "<Qt key name>": "<action>" }`; the name is `Qt.Key_<name>` without the prefix (`Left`, `Return`,
  `Back`, `HomePage`, `VolumeUp`, `F1`...). Actions: `left right up down select back home`, `launch:<app-id>` (logged),
  anything else is logged as `action:<name>` (not implemented yet). Unknown key names / app ids are warned on stderr.
  Placeholder bindings until the remote's real key codes are captured (Phase 1).
- Live content: `~/.cache/tv-project/content.json`, same shape as placeholder.json (`upNext`, `featured`); an empty
  list hides that row/hero (featured is empty without a TMDb key, so made-up placeholder shows never mix with real ones).
  Missing/unreadable = placeholders. Bigscreen runs `trakt.py sync` each time the home screen becomes active (start,
  back from an app) and rebuilds the rows + goes home only if the content changed. The prototype only reads it.
- Trakt: secrets in `~/.config/tv-project/secrets.json`
  `{"trakt": {"clientId", "clientSecret"}, "tmdb": {"apiKey"}, "fanart": {"apiKey", "clientKey"}}` (tmdb, fanart optional), token in
  `~/.config/tv-project/trakt-token.json` (600, auto-refreshed). Up next = paused episodes (newest first, with progress),
  then the next episode of recently watched shows; hidden/dropped shows skipped; max 15. Artwork: the show's TMDb backdrop (w780), downloaded
  once to `~/.cache/tv-project/images/tmdb-tv-<id>.jpg`, item field `image` (file URL); media tiles draw any `image`
  cropped to the rounded card, over the fallback gradient (colors from a hash of the show slug).
  Hero (`featured`): Trakt `/recommendations/shows` (10), first 5 with a TMDb backdrop (w1280); meta "Series · <genre> ·
  N seasons", TMDb overview, `logo` = fanart.tv `hdtvlogo` (else `clearlogo`) by TVDB id, en/textless first, most liked.
  HeroBanner draws `image` over the gradient and `logo` (max 150 px high) instead of the title text.
  Verified 2026-10-28 in the container against the mock + generated images only, not real Trakt/TMDb/fanart.tv.
- Trending (`tmdb.py`): `/3/trending/all/week` (films + series, people and poster-less items skipped, max 20), poster
  w500 cached as `images/tmdb-<movie|tv>-<id>-poster.jpg`, meta "Film · 2026" / "Series · 2025". Raw response cached in
  `~/.cache/tv-project/tmdb-trending.json` for 6 h; on failure the stale cache is used; no key and no cache = content.json
  untouched (placeholder row stays). Bigscreen runs it on activation. Verified 2026-10-28 against the mock only.
- Continue watching (`jellyfin.py`): secrets `"jellyfin": {"url", "apiKey" (Dashboard -> API Keys), "user" (name; optional
  with one user)}`. `/UserItems/Resume?userId=` (10.9+), falls back to `/Users/{id}/Items/Resume`; max 15. Tile: series
  title, "S2 E5 · <name> · 30 min left" (films: year), progress, 16:9 art (Thumb, parent Thumb, Backdrop, parent
  Backdrop, Primary) cached as `images/jellyfin-<id>-<type>-<tag>.jpg`, `"app": "jellyfin"`. Server down / not configured
  = content.json untouched. The layout's "continue" row has no placeholder data, so it is hidden until configured.
- Voice: keymap action `voice` (F5 for now). Home.startVoice -> `Config.voiceListener` (Bigscreen: `voice.py listen` via
  the executable engine; prototype: overlay says it needs Bigscreen) -> runAction(action). `config/voice.json`: seconds,
  language (auto), model path, nameMatch (fuzzy app-name threshold, difflib ratio over runs of up to 3 words joined),
  phrases per action (longest match wins; app names checked first), open words (informational). App names come from
  apps.json `name` + optional `voiceNames`. whisper gets `--prompt` with the app names to bias recognition.
- `Config.system(action)`: Bigscreen hook for actions the page can't do; volume_up/down/mute = `wpctl ... @DEFAULT_AUDIO_SINK@`
  (5 %, capped at 100 %), tv_off = `tvpower.py off`. Prototype: logged as action:<name>.
- Items may carry `"app": "<apps.json id>"`: Enter logs open:<id> and launches that app (TileRow.activate).
- Weather: `secrets.json` `"location": {"lat", "lon"}`. weather.py uses Locationforecast 2.0 compact, the forecast step
  for the current hour, honours Expires/If-Modified-Since, downloads Yr's SVG symbol once (`~/.cache/tv-project/weather-icons/`).
  Top bar shows icon + temperature left of the clock, hidden without data. TvHome re-reads weather.json every 5 min;
  Bigscreen runs weather.py on activation and every 10 min while active. Verified 2026-10-28 live (Oslo) in the container.
- `data/placeholder.json` items: `{id, title, meta | subtitle, description (hero), progress 0..1 (optional), colors: [c0, c1, c2],
  image (optional URL: tile/hero backdrop), logo (optional URL, hero only)}`.

### Verified 2026-10-27 (screenshots)
Key sequence Right×3, Down, Right, Down, Enter, Up×2 (+ Enter, Esc×2), horizontal scroll to the end of a row,
and theme.json / layout.json / apps.json edits all verified on the laptop panel. Not yet tested on the TV.
keymap.json verified 2026-10-28 in the container: Home key, F2/F4 launch logs, volume/mute action logs, warnings for
an unknown key name and an unknown app id.

## Bigscreen integration (built 2026-10-28; host-verified 2026-10-28 via swap-session, see end of section)
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
  Back has nothing left to do (start row, first tile); refocuses Home when the window becomes active.
- Try without logging out: `/usr/bin/plasma-bigscreen-swap-session` = `plasmashell --replace` with the Bigscreen env in the
  current session. Ask before running it (session change). Run it detached: `(setsid nohup plasma-bigscreen-swap-session >log 2>&1 &)`.
  **Swapping back** needs `PLASMA_BIGSCREEN_LAUNCH_REASON=swap` in the calling shell (the script checks the caller's env,
  not plasmashell's); without it a second run just restarts Bigscreen. It restores `~/.cache/plasma-bigscreen/saved-env`.
- On swap, `plasma-bigscreen-inputhandler` asks for "Remote Control: Konsole is asking for special privileges: Control input
  devices" (labelled Konsole because Konsole started it). The user must answer it; not needed for keyboard/BT remote.
- Focus: Konsole keeps keyboard focus after the swap and after an app closes. Before ydotool tests run
  `scripts/focus-home.sh` (throwaway KWin script, activates the plasmashell desktop window, prints before/after).
- Host-verified 2026-10-28 (laptop panel, swap-session, no secrets so placeholder rows): install script, navigation sequence,
  Enter on YouTube starts VacuumTube via the app model, back to home after `flatpak kill` + focus-home. plasmashell log shows
  no console.log (Fedora `*.debug=false`). Flatpak desktopIds exist on the host; tv-rikstv.desktop is installed by the script.
  Fullscreen: HomeScreen.qml has its own TaskManager.TasksModel + Instantiator; 500 ms after a window appears whose
  `AppId` (= desktop file name incl. ".desktop") matches an apps.json `desktopId`, it calls requestToggleFullScreen once.
  (Bigscreen's kwinrc `Placement=Maximizing` only maximizes, and only in a real login.) Host-verified 2026-10-28.
- Home key: Bigscreen binds Home Page globally ("Toggle Bigscreen Home Screen", kglobalshortcutsrc; Menu = tasks overview,
  Settings = settings). Upstream minimizes all tasks; our HomeScreen.qml listens to the same `Shortcuts.toggleHomeScreen`
  signal (`import org.kde.private.biglauncher`) to call `tv.goHome()` and `Window.requestActivate()` (without it nothing
  is active after minimizing, so the next key is lost). Host-verified with Moonlight.
- Swap without the inputhandler permission dialog (for unattended tests):
  `( . /usr/bin/plasma-bigscreen-common-env; export PLASMA_BIGSCREEN_LAUNCH_REASON=swap; setsid nohup plasmashell --replace >log 2>&1 & )`;
  back: `(setsid nohup plasmashell --replace >log 2>&1 &)` from a normal shell.

## Rules
- **Every UI change must be verified with a screenshot (and you must look at it) before you report it as done.**
- In the container, the system rules below are about the Bazzite host; never run real app launches anywhere yet.
- Ask before: any `rpm-ostree` change, any reboot, installing any package or Flatpak, editing anything outside `~/tv-project`, changing system or login settings, any use of sudo.
- Report each step as ✅ (done + result) or ❌ (what failed + why).

## Remote (Strong "RemoteG20", Bluetooth, vendor 0957 product 000f)

| Button | HID scan | Kernel key (default) | After remap | Qt key | Action |
|---|---|---|---|---|---|
| Off | c0030 | POWER (PowerDevil would sleep) | F14 | Launch (5) | tv_power (global) |
| Input | c01bb | UNKNOWN 240 | F15 | Launch (6) | tv_input (global) |
| Mic | c0221 | SEARCH (KRunner) | F16 | Launch (7) | voice (global) |
| Gear | c009f | UNKNOWN 240 | F17 | Launch (8) | settings (global) |
| YouTube | c0077 | 588 | F18 | Launch (9) | launch:youtube (global) |
| Netflix | c0078 | 589 | F19 | F19 | launch:jellyfin (global) |
| Prime Video | c0079 | KBDILLUMUP (keyboard light) | PROG3 | Launch (3) | launch:moonlight (global) |
| Disney+ | c007a | KBDILLUMDOWN (keyboard light) | PROG4 | Launch (4) | launch:rikstv (global) |
| TV | c008d | PROGRAM 362 | PROG1 | Launch (1) | launch:rikstv (global) |
| Red | | RED | unchanged | Red | moonlight_quit (global) |
| 0-9, green/yellow/blue, list (SUBTITLE), ⓘ (INFO 358), profile (LOGOFF), ch +/- (402/403) | | as named | unchanged | | keymap.json (ch +/- = up/down) |
| OK | c0041 | SELECT (apps ignore it) | ENTER | Return | select |
| Back | c0224 | BACK (VacuumTube quits on it) | ESC | Escape | back |
| arrows, home, vol +/-, mute | | as named | unchanged | | keymap.json / Plasma |

- The remote can NOT wake the laptop (tested 2026-10-29, s2idle, Intel AX211): with USB wakeup enabled on the adapter
  (3-10) a connected remote wakes it instantly (the link drops at suspend: "ACL packet for unknown connection
  handle"; GPE wake via IRQ 9), a disconnected one never ("Controller resume with wake event 0x0"). Rule removed again.
  So the laptop does not sleep on AC (powerdevilrc [AC][SuspendAndShutdown] AutoSuspendAction=0, LidAction=0: a
  closed lid with the TV off would otherwise suspend); Off = TV off only. Used ~once a week: battery sits at 100 % on
  AC (ThinkPad, BAT0 charge_control_end_threshold supported) -> user sets a charge limit (System Settings > Power).
  Screen lock off (kscreenlockerrc Autolock/LockOnResume=false; needs `qdbus org.freedesktop.ScreenSaver /ScreenSaver
  configure` to take effect). Autologin into Bigscreen: scripts/install-autologin.sh (Plasma Login Manager drop-in;
  user runs it).
- Remap: scripts/remote/70-strong-remote.hwdb → /etc/udev/hwdb.d (scripts/install-remote-keys.sh, pkexec). Afterwards the
  remote must reconnect (turn off/on, or `bluetoothctl disconnect`, then press a key): libinput drops keys the device did
  not declare when it appeared (PROG1-4).
- Avoid F13 (xkb Tools = System Settings' shortcut), F20-F23 (mic mute / touchpad), KBDILLUM*, SEARCH, LOGOFF.
- Global buttons: `python3 homescreen/remote.py install` writes hidden ~/.local/share/applications/tv-remote-*.desktop
  with X-KDE-Shortcuts; Plasma runs `remote.py send <action>`, which hands it to the home screen through a FIFO
  (HomeScreen.qml keeps `remote.py wait` running), or launches the app directly when no home screen is listening.
- Capture codes without the input group: `pkexec evtest /dev/input/eventN` (password dialog). The Bigscreen "Tools"
  clash and the libinput issue were found with a PySide6 key logger window (prints Qt key + nativeScanCode).
- RiksTV's Chrome runs with `--class=tv-rikstv`, otherwise its window is "google-chrome" and Bigscreen cannot raise it.
- Jellyfin Desktop must be in TV layout or the arrows only scroll: in its profile's jellyfin-desktop.conf
  (~/.var/app/org.jellyfin.JellyfinDesktop/data/jellyfin-desktop/profiles/<id>/), "main": "layout": "tv",
  "webMode": "tv" (edit with Jellyfin closed; `--tv` does the same for one start). Set on the host 2026-10-28.

## Jellyfin picture quality (2026-10-29)
- Jellyfin Desktop 2.0 ignores mpv.conf (tested: ~/.var/app/.../config/mpv, data/jellyfin-desktop, profile dir).
  Extra mpv options go in the profile's jellyfin-desktop.conf "other": {"other_conf": "key=value\n..."} (tested with
  vf=hflip); "video": {"deinterlace": true} turns on bwdif (SD TV recordings were combed).
- scripts/install-jellyfin-video.sh: deinterlace only (current setting). `--upscale` adds FSRCNNX_x2_8-0-4-1.glsl
  (igv, LGPL, sha256-checked) + scale/cscale=ewa_lanczossharp: tried 2026-10-29, the user saw no gain and laggier
  playback, so it is off and the shader deleted. `--remove` = everything off. Backup: jellyfin-desktop.conf.before-upscaling.

## DevTools ports (127.0.0.1 only; the user accepted this on 2026-10-29: "its just youtube, its not that sensitive")
- VacuumTube: `--remote-debugging-port=9231` in its flags.txt (scripts/install-youtube-debug.sh). homescreen/youtube_tv.py
  runs youtube_tv.js inside the YouTube TV page: InnerTube browse (FEwhat_to_watch = recommendations, FEhistory =
  history with percentDurationWatched) with the app's own token from localStorage
  `yt.leanback.default::cached-access-tokens`; the token never leaves the page. YouTube's Data API has no history.
  Deeplinks VacuumTube understands: `watch?v=ID`, `tv?launch=search&vq=Q`, `tv?c=FEhistory`; any deeplink raises it.
- Jellyfin Desktop: Flatpak override `QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:9232` (scripts/install-jellyfin-debug.sh).
  homescreen/jellyfin_back.py (started by HomeScreen.qml) injects a handler: Jellyfin Desktop delivers remote keys as
  commands on `window.api.input.hostInput` ("back", "up"...), not DOM keydown; "back" on `#/home` without a dialog ->
  `remote.py send show_home` -> Shortcuts.toggleHomeScreen(). Runtime.enable replays old console messages: filter by
  timestamp.
- Jellyfin tiles (`jellyfin_play_id:`): a MINIMIZED Jellyfin gets no requestAnimationFrame (measured: 0 frames/s), so
  PlayNow sent while it is hidden leaves its start page on top of the player (sound, but "Because you watched"
  visible). So Jellyfin is raised first; when it already runs, jellyfin_curtain.py puts a loading screen over
  its page (DevTools, removes itself after 20 s), PlayNow goes out, jellyfin.py start returns once PositionTicks moves,
  then the curtain comes off. media.py leave <app> does not pause the app being opened. Host-verified 2026-10-29.
