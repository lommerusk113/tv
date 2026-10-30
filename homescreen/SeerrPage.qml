import QtQuick
import "."

// Jellyseerr made for the remote (its website is a desktop site): a search box and poster rows from its API
// (jellyseerr.py browse / search --all, through Config.seerrQuery). OK on a poster runs its request:<kind>:<tmdb>:<title>
// action, which Home sends to RequestDialog with the tile (itemFor): Play / Request / Trailer by status.
// Up from the first row reaches the search box; OK there opens the keyboard and results show as you type.
// Home routes every action to handle() while it is open.
Item {
    id: page
    property bool open: false
    property bool loading: false
    property string error: ""
    property var rows: []          // [{id, title, items}] from browse
    property var results: null     // the search row, or null
    property string query: ""
    property int section: 0        // -1 = search box, else index into shownRows
    readonly property var theme: Config.theme
    readonly property bool typing: entry.open
    readonly property var shownRows: (results ? [results] : []).concat(rows)
        .map(r => ({ id: r.id, title: r.title, style: "poster", action: "open", items: r.items }))

    function show() {
        open = true;
        section = shownRows.length ? 0 : -1;
        load();
    }

    function close() {
        entry.open = false;
        open = false;
    }

    function load() {
        if (!Config.seerrQuery) {
            error = "Jellyseerr needs the Bigscreen home screen";
            return;
        }
        loading = !rows.length;
        Config.seerrQuery(["browse"], data => {
            loading = false;
            if (!data || !data.ok) {
                if (!rows.length)
                    error = "Could not reach Jellyseerr";
                return;
            }
            error = "";
            const first = !rows.length;
            const state = focusState();
            rows = data.rows;
            if (first && section < 0 && !typing)
                section = 0;  // opened before the rows were there: start on the first row, not the search box
            else
                restoreFocus(state);
        });
    }

    function runSearch() {
        const q = query.trim();
        if (!q) {
            results = null;
            return;
        }
        if (!Config.seerrQuery)
            return;
        Config.seerrQuery(["search", "--all", q], data => {
            if (q !== query.trim())
                return;  // typed on meanwhile
            const state = focusState();
            results = { id: "results", title: data && data.results && data.results.length
                            ? "Results for “" + q + "”" : "Nothing found for “" + q + "”",
                        items: data && data.results ? data.results : [] };
            if (!results.items.length)
                results = null;
            restoreFocus(state);
        });
    }

    // The tile behind a request: action (for RequestDialog).
    function itemFor(action) {
        for (const r of shownRows) {
            const hit = r.items.find(i => i.action === action);
            if (hit)
                return hit;
        }
        return null;
    }

    // After a request: show it as requested everywhere on the page, and fetch the real state.
    function markRequested(kind, tmdb) {
        const mark = list => list.map(i => i.kind === kind && String(i.tmdb) === String(tmdb) && i.status < 2
            ? Object.assign({}, i, { status: 2, label: "Requested", meta: "Requested" })
            : i);
        const state = focusState();
        rows = rows.map(r => Object.assign({}, r, { items: mark(r.items) }));
        if (results)
            results = Object.assign({}, results, { items: mark(results.items) });
        restoreFocus(state);
        load();
    }

    // Rebuilding the rows resets their tiles: keep the row and tile that had focus.
    function focusState() {
        const row = rowAt(section);
        return { id: section >= 0 && shownRows[section] ? shownRows[section].id : "", index: row ? row.current : 0 };
    }
    function restoreFocus(state) {
        Qt.callLater(() => {
            if (section < 0)
                return;
            const i = shownRows.findIndex(r => r.id === state.id);
            section = i >= 0 ? i : Math.min(section, shownRows.length - 1);
            const row = rowAt(section);
            if (row && i >= 0)
                row.current = Math.min(state.index, row.items.length - 1);
            scroll();
        });
    }

    function rowAt(i) {
        const loader = rowRepeater.itemAt(i);
        return loader || null;
    }

    function moveVertical(d) {
        const next = Math.max(-1, Math.min(shownRows.length - 1, section + d));
        if (next === section)
            return;
        const from = rowAt(section), to = rowAt(next);
        if (from && to)
            to.focusNearest(from.focusCenterX());
        section = next;
        scroll();
    }

    function scroll() {
        const row = rowAt(section);
        flick.contentY = section <= 0 || !row ? 0 : Math.min(row.y, Math.max(0, flick.contentHeight - flick.height));
    }

    function handle(action) {
        if (typing) {
            entry.handle(action);
            return true;
        }
        switch (action) {
        case "up": moveVertical(-1); break;
        case "down": moveVertical(1); break;
        case "left":
        case "right":
            if (rowAt(section))
                rowAt(section).move(action === "left" ? -1 : 1);
            break;
        case "select":
            if (section < 0)
                entry.show("seerr", { type: "text", value: query, label: "Search films and series" });
            else if (rowAt(section))
                rowAt(section).activate();
            break;
        case "back":
            if (section > 0 || rowAt(section) && rowAt(section).current > 0) {
                if (rowAt(section))
                    rowAt(section).current = 0;
                section = 0;
                scroll();
            } else {
                close();
            }
            break;
        case "home":
            close();
            break;
        default:
            return false;  // volume, voice...
        }
        return true;
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: page.theme.animationMs * 2 } }

    Rectangle {
        anchors.fill: parent
        color: page.theme.colors.background
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: header.height
        interactive: false
        clip: true
        contentWidth: width
        contentHeight: column.height + height / 2
        Behavior on contentY { NumberAnimation { duration: page.theme.animationMs * 2; easing.type: Easing.OutCubic } }

        Column {
            id: column
            width: flick.width
            spacing: Config.px(page.theme.spacing.row) / 2

            Repeater {
                id: rowRepeater
                model: page.shownRows
                delegate: TileRow {
                    required property var modelData
                    required property int index
                    width: column.width
                    section: modelData
                    focused: page.section === index && !page.typing
                }
            }
        }
    }

    // Header: logo, name and the search box (focused = section -1).
    Rectangle {
        id: header
        width: parent.width
        height: Config.px(150)
        color: page.theme.colors.background

        Row {
            x: Config.px(page.theme.spacing.page)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(22)
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(64)
                height: width
                source: Qt.resolvedUrl("icons/jellyseerr.png")
                sourceSize: Qt.size(width * 2, height * 2)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Jellyseerr"
                color: page.theme.colors.text
                font.family: page.theme.font.family
                font.pixelSize: Config.px(40)
                font.weight: Font.Bold
            }
        }

        Rectangle {
            id: searchBox
            readonly property bool focused: page.section < 0 && !page.typing
            anchors.right: parent.right
            anchors.rightMargin: Config.px(page.theme.spacing.page)
            anchors.verticalCenter: parent.verticalCenter
            width: Config.px(820)
            height: Config.px(76)
            radius: height / 2
            color: focused ? page.theme.colors.focusBorder : Config.withAlpha(page.theme.colors.text, 0.08)
            border.width: page.typing ? Config.px(3) : 0
            border.color: page.theme.colors.accent
            scale: focused ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: page.theme.animationMs } }
            Behavior on color { ColorAnimation { duration: page.theme.animationMs } }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: Config.px(34)
                width: parent.width - Config.px(68)
                elide: Text.ElideLeft
                text: page.query ? page.query : "⌕  Search films and series"
                color: searchBox.focused ? page.theme.colors.onFocused
                       : page.query ? page.theme.colors.text : page.theme.colors.textDim
                font.family: page.theme.font.family
                font.pixelSize: Config.px(28)
                font.weight: page.query ? Font.DemiBold : Font.Normal
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: page.loading || (page.error !== "" && !page.shownRows.length)
        text: page.loading ? "Loading…" : page.error
        color: page.theme.colors.textDim
        font.family: page.theme.font.family
        font.pixelSize: Config.px(32)
    }

    // Typing the search: results come in as you type (a pause of 0.5 s), the done key goes to them.
    Timer {
        id: searchDelay
        interval: 500
        onTriggered: page.runSearch()
    }

    TextEntry {
        id: entry
        anchors.fill: parent
        onEdited: text => {
            page.query = text;
            searchDelay.restart();
        }
        onSubmitted: {
            open = false;
            searchDelay.stop();
            page.runSearch();
            page.section = 0;
            page.scroll();
        }
    }
}
