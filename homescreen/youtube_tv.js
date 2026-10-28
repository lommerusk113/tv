// Runs inside VacuumTube's YouTube TV page (youtube_tv.py, over the Chrome DevTools port) and asks YouTube's own API
// for one feed with the app's current login: FEhistory (watch history) or FEwhat_to_watch (the start page's
// recommendations). Returns [{id, title, channel, duration, watched (0..1)}]. FEED is replaced by youtube_tv.py.
(async () => {
    const tokens = JSON.parse(localStorage.getItem("yt.leanback.default::cached-access-tokens") || "{}").data || {};
    const token = Object.values(tokens)[0];
    if (!token)
        return {error: "not signed in"};
    const res = await fetch("https://www.youtube.com/youtubei/v1/browse?prettyPrint=false", {
        method: "POST",
        headers: {"Content-Type": "application/json", "Authorization": "Bearer " + token.accessToken},
        body: JSON.stringify({context: ytcfg.data_.INNERTUBE_CONTEXT, browseId: FEED}),
    });
    if (!res.ok)
        return {error: "HTTP " + res.status};
    const out = [], seen = new Set();
    const text = runs => runs ? (runs.simpleText || (runs.runs || []).map(r => r.text).join("")) : "";
    (function walk(o) {
        if (!o || typeof o !== "object")
            return;
        const tile = o.tileRenderer;
        const id = tile && tile.onSelectCommand && tile.onSelectCommand.watchEndpoint
            && tile.onSelectCommand.watchEndpoint.videoId;
        if (id && !seen.has(id)) {
            seen.add(id);
            const meta = tile.metadata && tile.metadata.tileMetadataRenderer || {};
            const lines = (meta.lines || []).map(l => ((l.lineRenderer || {}).items || [])
                .map(i => text((i.lineItemRenderer || {}).text)).join(" ").trim());
            const overlays = JSON.stringify(tile.header || {});
            const pct = overlays.match(/"percentDurationWatched":(\d+)/);
            const len = overlays.match(/"thumbnailOverlayTimeStatusRenderer":\{"text":\{(?:"simpleText":"([^"]+)|"runs":\[\{"text":"([^"]+))/);
            out.push({id: id, title: text(meta.title), channel: lines[0] || "",
                      duration: len ? (len[1] || len[2]) : null, watched: pct ? Number(pct[1]) / 100 : 0});
        }
        for (const v of Array.isArray(o) ? o : Object.values(o))
            walk(v);
    })(await res.json());
    return out;
})()
