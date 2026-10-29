// Loaded by the home screen while a Moonlight stream starts: keeps Moonlight's windows (its "Starting…" dialog, the
// stream window before the first picture) minimized, so the home screen's loading screen stays in front.
// Unloaded again by the home screen, which then runs show-moonlight.js.
function hide(w) {
    if (w && w.resourceClass === "com.moonlight_stream.Moonlight")
        w.minimized = true;
}
for (const w of workspace.stackingOrder)
    hide(w);
workspace.windowAdded.connect(hide);
