# TV home screen

Google TV-style home screen for a Bazzite living-room PC, prototyped in plain Qt Quick (Qt 6)
and later ported into Plasma Bigscreen. See `CLAUDE.md` for decisions, config format and rules.

## Run on the Bazzite laptop
```bash
cd homescreen && python3 run.py
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
```
Rendering uses Mesa llvmpipe, so no GPU is needed. `shots/` is git-ignored.
