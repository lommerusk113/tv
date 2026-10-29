# TV project TODO

Status and conventions: see CLAUDE.md. Do phases in order. Each phase ends with screenshot verification, a CLAUDE.md update, and a commit.
[ME] = something I must do physically or decide. Stop and ask me when you reach one.

## Standing rules
- Screenshot-check every UI change before reporting it as done.
- Ask before: rpm-ostree changes, reboots, installs, sudo, editing outside ~/tv-project, and login/system settings.
- Never commit secrets (TMDb API key, Jellyfin token/URL, RiksTV credentials). Keep them in ~/.config/tv-project/secrets.json and add it to .gitignore.
- Logging out kills the terminal Claude Code runs in. Before any session switch, tell me, so I can restart Claude Code from Konsole inside the new session.

## Phase 1: TV and remote hardware
- [ME] Connect the LG 55UJ701V over HDMI. On the TV: set the aspect ratio to "Just Scan" (or "Original") to avoid overscan.
- Run `kscreen-doctor -o` and report modes and refresh rates. If 3840x2160 is only available at 30 Hz (laptop HDMI 1.4), recommend 1920x1080 at 60 Hz. Propose resolution, scale, and whether to turn off eDP-1; apply only after I approve.
- Check text size and tile size in the prototype on the TV. [ME] Judge readability from the couch.
- [x] (2026-10-28) [ME] Pair the Strong Bluetooth remote (Kjell p66355). It is "RemoteG20".
- [x] (2026-10-28, host) Key codes captured; table in CLAUDE.md ("Remote"). Every button sends a key; the mic button sends KEY_SEARCH and is used for the laptop-mic voice control. Plasma-grabbed or nameless buttons are remapped (scripts/install-remote-keys.sh, sudo once) and become global shortcuts (homescreen/remote.py install, config/remote.json), so they work inside apps too. Verified with the real remote in a swap session: YouTube, Netflix, Disney+, TV. Off/Input need "tv" in secrets.json.

## Phase 2: Move the prototype into Plasma Bigscreen
- [x] (2026-10-28, see CLAUDE.md "Bigscreen packaging") Find how Bigscreen's home screen is packaged (shell/containment QML package) and whether a modified copy can live in ~/.local/share/plasma/ without touching the read-only system.
- [x] (2026-10-28, container-tested) Port the prototype's QML into that package; keep the config files (theme.json, apps.json, layout.json) working. Keep changes modular to make upstream KDE updates easy to merge.
- [ME] Run `scripts/install-bigscreen.sh`, then either `plasma-bigscreen-swap-session` (no logout, Claude Code keeps running) or log out, choose "Plasma Bigscreen", open Konsole, and restart Claude Code.
- [x] (2026-10-28, host, via plasma-bigscreen-swap-session) Verify navigation in the real session with ydotool + screenshots.
- [x] (2026-10-28, host) Launched apps open fullscreen: HomeScreen.qml watches TaskManager windows and requests fullscreen once for any window whose AppId matches an apps.json desktopId. Verified with VacuumTube and Jellyfin (incl. re-raise after Home).
- [ME] Decide on auto-login to the Bigscreen session (System Settings → Login Screen). Recommended once Phase 3 works.

## Phase 3: Launching apps and the remote
- [x] (2026-10-28, container-tested with a fake .desktop; host: YouTube/VacuumTube launched from Bigscreen, others untested) Make Enter run the launch command from apps.json:
  - YouTube: `flatpak run rocks.shy.VacuumTube`
  - Jellyfin: `flatpak run org.jellyfin.JellyfinDesktop`
  - Moonlight: `flatpak run com.moonlight_stream.Moonlight`
  - RiksTV: `flatpak run com.google.Chrome --kiosk https://www.rikstv.no`
- [x] (2026-10-28, host, swap-session) Home on the remote returns to the home screen from any app: Bigscreen's global
  "Toggle Bigscreen Home Screen" shortcut (Home Page key) minimizes all apps; our HomeScreen.qml also resets the rows and
  re-activates the window. Enter on a running app's tile brings it back (no second instance). Back stays with the app
  (apps need it for their own navigation). Still to check: Home while Moonlight streams (it may capture the shortcut).
- [x] (2026-10-28, logging only; rebind to the real remote codes after Phase 1) Remote key mapping driven by a keymap.json in config (button → action, e.g. `launch:jellyfin`, `home`, `volume_up`). Prefer handling keys inside the home screen. A system-level remapper (input-remapper/keyd) is an install, so ask first.
- Map one remote button to Moonlight's exit-stream shortcut (Ctrl+Alt+Shift+Q). Blocked: needs the remote's key codes (Phase 1) and a Moonlight host to test. Moonlight captures the keyboard while streaming (and may inhibit KWin global shortcuts), so this probably needs Moonlight's "capture system shortcuts" setting off plus a global shortcut.
- [ME] Test RiksTV playback in Chrome (DRM shows black in screenshots). If needed: Chrome policies (URL allowlist) to keep the kiosk on RiksTV domains.
  First start of the Chrome Flatpak shows "Google Chrome and ChromeOS Additional Terms of Service" (Accept/Cancel) over the
  kiosk; accept it once yourself (2026-10-28: the tile launches Chrome fine, the dialog blocks rikstv.no until accepted).
- [ME] Jellyfin Desktop asks for the server address on first start (launch from the tile works, 2026-10-28).

## Phase 4: Real data in the rows
- [x] (2026-10-28, mock-tested; needs a Trakt API app + `python3 homescreen/trakt.py auth` on the host) Trakt "Up next" row (replaces the placeholder Continue watching row).
- [x] (2026-10-28, mock-tested + prototype screenshot; real server untested, needs `jellyfin` in secrets.json) Jellyfin "Continue watching": `homescreen/jellyfin.py` (API key + user), row hidden until configured.
- [x] (2026-10-28, mock-tested) TMDb backdrops on the Up next tiles (optional `tmdb.apiKey` in secrets.json).
- [x] (2026-10-28, mock-tested) Hero = Trakt recommendations with TMDb backdrops + fanart.tv title logos.
- [x] (2026-10-28, mock-tested + prototype screenshot; real TMDb untested, needs `tmdb.apiKey`) TMDb "Trending": `homescreen/tmdb.py`, run by Bigscreen on activation; response cached 6 h, posters cached; offline/no key keeps the last row (or the placeholder).
- Optional: "Because you watched X" using TMDb similar/recommendations based on recent Jellyfin history.
- [x] (2026-10-28) Enter on a Jellyfin item opens Jellyfin Desktop (item `"app": "jellyfin"`). Opening the exact item is not done: Jellyfin Desktop 2.0 has no known deep-link argument; revisit if it gets one.

- [x] (2026-10-28) Yr weather next to the clock (MET Norway, `location` in secrets.json).

## Phase 5: Turning the TV on and off
- [ME] On the TV: enable "Mobile TV On → Turn On Via WiFi" and "LG Connect Apps" (Network settings). Connect the TV to the router with an Ethernet cable (Wake-on-LAN is unreliable over Wi-Fi after long standby).
- [ME] In the router: reserve a fixed IP for the TV's MAC, block all its internet traffic (IPv4 and IPv6, including DNS), and allow local traffic to the laptop. Set this up before the TV first connects. Verify nothing goes out (TV browser, router logs).
- [x] (2026-10-28) bscpylgtv 0.5.5 installed in the venv `~/.local/share/tv-project/venv`. Pairing still to do with the TV
  [ME]: add `"tv": {"ip", "mac", "input"}` to secrets.json, run `python3 homescreen/tvpower.py pair`, accept on the TV
  (key -> `~/.config/tv-project/lgtv-keys.sqlite`).
- [x] (2026-10-28, tested without a TV: test_tvpower.py) `homescreen/tvpower.py on|off|pair|status|watch-sleep`: WOL to
  broadcast + TV IP, retry until the API answers (40 s), set input; off via the API. Bigscreen runs `tvpower.py on` when
  the home screen starts.
- [ME] Run `scripts/install-tv-power.sh` (enables the user service `tv-sleep.service`: TV off before sleep, on after
  wake). Claude Code's auto mode refused to enable a login service on its own, so this is yours; `--remove` undoes it.
- Fallback if Wake-on-LAN is unreliable: ESP32 IR blaster over USB serial (LG uses NEC IR codes with discrete power on/off).

## Phase 6: Voice control
- [x] (2026-10-28, host, Bigscreen) Push-to-talk: keymap action `voice` (placeholder key F5 until the remote is mapped),
  records 4 s from the laptop mic. Verified: F5 + "Open YouTube" (spoken by espeak-ng through the speakers) started VacuumTube.
- [x] (2026-10-28) whisper.cpp 1.9.5 from Homebrew + multilingual base model (`scripts/install-voice.sh`); ~4 s per command
  on the i7-1255U. Not tested with a real human voice or Norwegian speech yet [ME: try "åpne YouTube", "skru opp"].
- [x] (2026-10-28) Intent rules in `config/voice.json` + `voice.py` (English + Norwegian phrases, fuzzy app names).
  Not done: "play X on Jellyfin" (needs a Jellyfin search + deep link), Claude API fallback.
- [x] (2026-10-28) On-screen feedback: VoiceOverlay pill (Listening… countdown, Recognizing…, heard text / not understood).
- [x] (2026-10-28, host) Volume actions (`volume_up/down/mute`) via wpctl in Bigscreen; voice `tv_off` -> tvpower.py off.

## Backlog (optional)
- Casting alternatives (no real Google Cast possible on Linux): YouTube "Link with TV code" in VacuumTube, Jellyfin "Play On", UxPlay (AirPlay), DLNA renderer, spotifyd, KDE Connect. A cheap Google TV stick on a second HDMI input if real casting is needed.
- Settings screen in the home screen to edit theme.json/layout.json/keymap.json with the remote.
- Ambient screensaver when idle.
- Lighter variant for grandma on a Raspberry Pi 5: Chromium kiosk on RiksTV, only channel up/down, number keys and volume, read-only file system.
- [x] (2026-10-28, host, real server) Voice "play <title> [on Jellyfin]" (EN/NO): voice.py -> jellyfin_play:<title> ->
  HomeScreen.qml opens Jellyfin Desktop and runs `jellyfin.py play <title>` (server search, in-progress/next-up pick,
  PlayNow on this computer's Jellyfin Desktop session). Verified: "lord of the rings" resumed Fellowship of the Ring.
  The API key in secrets.json is temporary; replace it later (Dashboard -> API Keys).

## Next (written 2026-10-29, end of day)
- Trakt: user creates an API app (trakt.tv/oauth/applications/new, redirect urn:ietf:wg:oauth:2.0:oob), puts
  clientId/clientSecret in secrets.json, runs `python3 homescreen/trakt.py auth`. Then: "Recommended for you" row from
  Trakt recommendations, limited to titles on the Jellyfin server (playable), maybe also the banner.
- Voice with an LLM (idea, not started): whisper text -> small model with the available actions as tools (launch,
  jellyfin_play, youtube_search, volume, settings, move_to_tv...) instead of fixed phrases; fall back to voice.py rules
  offline. Needs an API key from the user and a decision on which model/provider.
- Untested on the host: Wi-Fi connect/disconnect, Bluetooth pairing, sleep/restart/shut down, the TV itself (Phase 1),
  "move to TV" from a real other Jellyfin device, weather (needs location), install-tv-power.sh (user runs it).
- Small: "S? E?" on episodes without numbers; Trending row is still placeholder (TMDb key or replace it).

