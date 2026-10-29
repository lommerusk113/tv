// Brings Moonlight back once its stream shows a picture: unminimize its windows, activate the newest (the stream).
let last = null;
for (const w of workspace.stackingOrder) {
    if (w.resourceClass === "com.moonlight_stream.Moonlight") {
        w.minimized = false;
        last = w;
    }
}
if (last)
    workspace.activeWindow = last;
