#!/usr/bin/env bash
# Host only (Bigscreen session): give keyboard focus to Bigscreen's home screen window via a throwaway KWin script,
# so ydotool keys don't land in Konsole. Prints the window that had focus before and after.
set -euo pipefail
Q=$(command -v qdbus6 || command -v qdbus)
js=$(mktemp --suffix=.js)
trap 'rm -f "$js"; "$Q" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript tvfocus >/dev/null 2>&1 || true' EXIT
cat > "$js" <<'JS'
const name = w => w ? w.caption + " [" + w.resourceClass + "]" : "none";
const before = name(workspace.activeWindow);
let target = null;
for (const w of workspace.stackingOrder)
    if (w.resourceClass === "plasmashell" && (w.desktopWindow || w.fullScreen)) target = w;
if (target) workspace.activeWindow = target;
console.info("TVFOCUS before=" + before + " | after=" + name(workspace.activeWindow));
JS
since=$(date '+%Y-%m-%d %H:%M:%S')
id=$("$Q" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" tvfocus)
"$Q" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run
sleep 1
journalctl --user --since "$since" --no-pager -o cat | grep TVFOCUS | tail -1
