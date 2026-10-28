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
- [ME] Pair the Strong Bluetooth remote (Kjell p66355).
- Find the remote's input device (`libinput list-devices` or /proc/bus/input/devices). Capture key codes with `evtest` (ask first if it needs sudo/group changes). Prompt me to press each button; save a button → key code table in CLAUDE.md. Note buttons that send nothing. The mic button is not expected to work on Linux (Google's voice protocol).

## Phase 2: Move the prototype into Plasma Bigscreen
- [x] (2026-10-28, see CLAUDE.md "Bigscreen packaging") Find how Bigscreen's home screen is packaged (shell/containment QML package) and whether a modified copy can live in ~/.local/share/plasma/ without touching the read-only system.
- Port the prototype's QML into that package; keep the config files (theme.json, apps.json, layout.json) working. Keep changes modular to make upstream KDE updates easy to merge.
- [ME] Log out, choose "Plasma Bigscreen", open Konsole, and restart Claude Code and the remote connection.
- Verify navigation in the real session with ydotool + screenshots.
- [ME] Decide on auto-login to the Bigscreen session (System Settings → Login Screen). Recommended once Phase 3 works.

## Phase 3: Launching apps and the remote
- Make Enter run the launch command from apps.json:
  - YouTube: `flatpak run rocks.shy.VacuumTube`
  - Jellyfin: `flatpak run org.jellyfin.JellyfinDesktop`
  - Moonlight: `flatpak run com.moonlight_stream.Moonlight`
  - RiksTV: `flatpak run com.google.Chrome --kiosk https://www.rikstv.no`
- Home/Back on the remote must always return to the home screen from any app (close or hide the app; confirm with screenshots).
- [x] (2026-10-28, logging only; rebind to the real remote codes after Phase 1) Remote key mapping driven by a keymap.json in config (button → action, e.g. `launch:jellyfin`, `home`, `volume_up`). Prefer handling keys inside the home screen. A system-level remapper (input-remapper/keyd) is an install, so ask first.
- Map one remote button to Moonlight's exit-stream shortcut (Ctrl+Alt+Shift+Q).
- [ME] Test RiksTV playback in Chrome (DRM shows black in screenshots). If needed: Chrome policies (URL allowlist) to keep the kiosk on RiksTV domains.

## Phase 4: Real data in the rows
- Jellyfin "Continue watching": the server's resume-items API with a user token from secrets.json; artwork from the server.
- TMDb "Trending": TMDb API with the key from secrets.json; cache responses and images locally; show placeholders when offline.
- Optional: "Because you watched X" using TMDb similar/recommendations based on recent Jellyfin history.
- Enter on a Jellyfin item opens it in Jellyfin Desktop if possible; otherwise just opens the app.

## Phase 5: Turning the TV on and off
- [ME] On the TV: enable "Mobile TV On → Turn On Via WiFi" and "LG Connect Apps" (Network settings). Connect the TV to the router with an Ethernet cable (Wake-on-LAN is unreliable over Wi-Fi after long standby).
- [ME] In the router: reserve a fixed IP for the TV's MAC, block all its internet traffic (IPv4 and IPv6, including DNS), and allow local traffic to the laptop. Set this up before the TV first connects. Verify nothing goes out (TV browser, router logs).
- Install bscpylgtv in the user's home (pipx/venv; ask first). Pair it with the TV (accept the prompt on screen [ME]); store the client key outside the repo.
- Scripts: TV on (wakeonlan to the TV's MAC and IP, then switch to the laptop's HDMI input), TV off. Run on laptop wake/sleep and when the home screen starts.
- Fallback if Wake-on-LAN is unreliable: ESP32 IR blaster over USB serial (LG uses NEC IR codes with discrete power on/off).

## Phase 6: Voice control
- Push-to-talk on a mapped remote button, recording from the laptop mic (or a USB mic).
- whisper.cpp locally for speech-to-text (ask before building or installing).
- Intent parsing into actions ("open YouTube", "play X on Jellyfin", "volume up"). Start with simple rules; optionally the Claude API later.
- On-screen feedback while listening and when a command is recognized.

## Backlog (optional)
- Casting alternatives (no real Google Cast possible on Linux): YouTube "Link with TV code" in VacuumTube, Jellyfin "Play On", UxPlay (AirPlay), DLNA renderer, spotifyd, KDE Connect. A cheap Google TV stick on a second HDMI input if real casting is needed.
- Settings screen in the home screen to edit theme.json/layout.json/keymap.json with the remote.
- Ambient screensaver when idle.
- Lighter variant for grandma on a Raspberry Pi 5: Chromium kiosk on RiksTV, only channel up/down, number keys and volume, read-only file system.
