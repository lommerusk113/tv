#!/usr/bin/env bash
# Install the TV home screen into Plasma Bigscreen, without touching /usr:
# copies the stock org.kde.bigscreen.homescreen plasmoid to ~/.local/share/plasma/plasmoids/ (the user copy wins),
# replaces only its HomeScreen.qml with bigscreen/HomeScreen.qml and links homescreen/ in as contents/ui/tv.
# Also installs homescreen/desktop/*.desktop (RiksTV kiosk) into ~/.local/share/applications/.
# Usage: scripts/install-bigscreen.sh            install (again after a KDE update or a HomeScreen.qml change)
#        scripts/install-bigscreen.sh --remove   back to the stock home screen
# Restart plasmashell afterwards. Edits under homescreen/ only need the restart, not a reinstall.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
id=org.kde.bigscreen.homescreen
src=/usr/share/plasma/plasmoids/$id
dst=$HOME/.local/share/plasma/plasmoids/$id
apps=$HOME/.local/share/applications
tested=6.7.5

rm -rf "$dst" "$HOME/.cache/plasmashell/qmlcache"
for f in "$repo"/homescreen/desktop/*.desktop; do rm -f "$apps/$(basename "$f")"; done
if [ "${1:-}" = --remove ]; then
    echo "removed; restart plasmashell"
    exit 0
fi

ver=$(rpm -q --qf '%{VERSION}' plasma-bigscreen)
if [ "$ver" != "$tested" ] && [ "${FORCE:-}" != 1 ]; then
    echo "plasma-bigscreen is $ver, this was written against $tested." >&2
    echo "Check that upstream main.qml still uses HomeScreen {blurBackground, darkenBackground}, then rerun with FORCE=1." >&2
    exit 1
fi

mkdir -p "$(dirname "$dst")" "$apps"
cp -r "$src" "$dst"
cp "$repo/bigscreen/HomeScreen.qml" "$dst/contents/ui/HomeScreen.qml"
ln -s "$repo/homescreen" "$dst/contents/ui/tv"
cp "$repo"/homescreen/desktop/*.desktop "$apps/"
echo "installed into $dst; restart plasmashell"
