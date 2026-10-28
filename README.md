# TV home screen

Google TV-style home screen for a Bazzite living-room PC, prototyped in plain Qt Quick (Qt 6)
and later ported into Plasma Bigscreen. See `CLAUDE.md` for decisions, config format and rules.

## Run on the Bazzite laptop
```bash
cd homescreen && python3 run.py
```

## Install into Plasma Bigscreen (Bazzite laptop)
```bash
scripts/install-bigscreen.sh            # user-dir copy of the stock home screen with ours swapped in; --remove undoes it
plasma-bigscreen-swap-session           # try it in the current session (run again to swap back), or log in to Plasma Bigscreen
```

## Run headless in a container (any machine with Docker or Podman)
```bash
docker build -t tv-homescreen .
docker run --rm -it -v "$PWD":/work tv-homescreen       # podman: add :Z to the volume on SELinux hosts

# inside the container
scripts/headless-start.sh                  # Xvfb 1920x1080 + prototype in the background
scripts/key.sh Right Right Down Return     # X11 key names (Left Right Up Down Return Escape)
scripts/shot.sh shots/test.png             # screenshot of the virtual screen
cat /tmp/homescreen.log                    # QML errors and launch:/open: lines
scripts/stop.sh

# or: run it inside the real Plasma Bigscreen home screen (plasmoidviewer), then key.sh / shot.sh as above
scripts/bigscreen-start.sh
```

Watch and drive it with a real keyboard: start the container with `-p 127.0.0.1:5901:5900`, run one of the start
scripts, then `scripts/vnc.sh`, and open `vnc://localhost:5901` (password `tv`) in macOS Screen Sharing.
Rendering uses Mesa llvmpipe, so no GPU is needed. `shots/` is git-ignored.

This product uses the TMDB API but is not endorsed or certified by TMDB. Title logos from fanart.tv.
