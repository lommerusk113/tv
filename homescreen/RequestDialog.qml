import QtQuick
import "."

// A film/series from Jellyseerr ("Get more" tiles, the Jellyseerr page): poster, plot, and buttons by its status:
// not there -> Request; requested/downloading -> nothing to do; on the server -> ▶ Play (jellyfin_play:<title>);
// plus ▶ Trailer when it has one. Left/right pick a button, OK runs it, Back cancels. Request goes to
// Config.system("jellyseerr_request:<movie|tv>:<tmdb id>:<title>") (requested() lets the page mark it); Trailer plays
// the tile's "trailer" (YouTube id) through Config.system("youtube_watch:<id>") and leaves the dialog open for when
// you come back. Tiles without "trailer" get it (and the plot) from `jellyseerr.py details` via Config.seerrQuery.
// Series: "Choose seasons" (or "More seasons" when some are there already) opens a season list (`jellyseerr.py
// seasons`): up/down, OK ticks a season ("All seasons" ticks every one that can be requested), the last row requests
// the ticked ones (jellyseerr_request:tv:<tmdb>:s<1,2>:<title>); seasons already there or requested are greyed out.
Item {
    id: dialog
    property bool open: false
    property string kind: ""
    property string tmdb: ""
    property string title: ""
    property var item: ({})
    property int choice: 0
    property string step: "info"      // "info", or "seasons" (the season list of a series)
    property var seasons: null        // jellyseerr.py seasons, once loaded
    property var picked: ({})         // season number -> ticked
    property int seasonRow: 0         // 0 = "All seasons", 1..n = seasons, n + 1 = the request button
    readonly property var theme: Config.theme
    readonly property int status: item.status || 1
    readonly property bool series: kind === "tv"
    readonly property var buttons: (status >= 4 ? ["▶  Play"] : [])
        .concat(series ? [status >= 2 ? "More seasons" : "Choose seasons"] : status >= 2 ? [] : ["Request"])
        .concat(item.trailer ? ["▶  Trailer"] : []).concat([status < 2 ? "Cancel" : "Close"])
    readonly property var requestable: (seasons || []).filter(x => x.state === "")
    readonly property var regular: requestable.filter(x => x.number !== 0)  // what "All seasons" ticks (not specials)
    readonly property var chosen: requestable.filter(x => picked[x.number]).map(x => x.number)

    signal requested(string kind, string tmdb)
    onButtonsChanged: choice = Math.min(choice, buttons.length - 1)  // the details came in and changed them

    // The tile with this action, from whichever row has it (for its poster, plot and trailer).
    function findItem(action) {
        for (const key in Config.content) {
            const rows = Config.content[key];
            if (Array.isArray(rows)) {
                const hit = rows.find(i => i && i.action === action);
                if (hit)
                    return hit;
            }
        }
        return {};
    }

    // action is "request:<movie|tv>:<tmdb id>:<title>" (the title may contain colons)
    // item: the tile, when the caller has it (else it is looked up in Config.content)
    function ask(action, tile) {
        const parts = action.split(":");
        kind = parts[1];
        tmdb = parts[2];
        title = parts.slice(3).join(":");
        item = tile || findItem(action);
        choice = 0;
        step = "info";
        seasons = null;
        open = true;
        if (item.trailer === undefined && Config.seerrQuery) {
            const asked = tmdb;
            Config.seerrQuery(["details", kind, tmdb], data => {
                if (data && data.ok && asked === dialog.tmdb)
                    dialog.item = Object.assign({}, dialog.item, { trailer: data.trailer || "",
                        overview: dialog.item.overview || data.overview, status: dialog.item.status || data.status });
            });
        }
    }

    function showSeasons() {
        step = "seasons";
        if (seasons) {
            const first = seasons.findIndex(x => x.state === "");
            seasonRow = first >= 0 ? first + 1 : seasons.length + 1;
            return;
        }
        seasonRow = 0;
        if (!Config.seerrQuery) {
            seasons = [];
            return;
        }
        const asked = tmdb;
        Config.seerrQuery(["seasons", tmdb], data => {
            if (asked !== dialog.tmdb)
                return;
            dialog.seasons = data && data.ok ? data.seasons : [];
            const ticks = {};
            for (const x of dialog.seasons)
                ticks[x.number] = x.state === "" && x.number !== 0;  // everything missing, but not the specials
            dialog.picked = ticks;
            const first = dialog.seasons.findIndex(x => x.state === "");
            dialog.seasonRow = first >= 0 ? first + 1 : dialog.seasons.length + 1;
        });
    }

    function sendRequest(list) {
        open = false;
        const request = "jellyseerr_request:" + kind + ":" + tmdb + ":" + (list ? "s" + list.join(",") + ":" : "") + title;
        if (!(Config.system && Config.system(request)))
            console.log("action:" + request);
        requested(kind, tmdb);
    }

    function handleSeasons(action) {
        const rows = (seasons || []).length + 2;
        switch (action) {
        case "up": seasonRow = Math.max(0, seasonRow - 1); break;
        case "down": seasonRow = Math.min(rows - 1, seasonRow + 1); break;
        case "back": step = "info"; break;
        case "select": {
            if (!seasons)
                break;
            const ticks = Object.assign({}, picked);
            if (seasonRow === 0) {  // All seasons: tick all (or untick all when all are ticked)
                const all = regular.every(x => ticks[x.number]);
                for (const x of regular)
                    ticks[x.number] = !all;
                picked = ticks;
            } else if (seasonRow <= seasons.length) {
                const x = seasons[seasonRow - 1];
                if (x.state === "") {
                    ticks[x.number] = !ticks[x.number];
                    picked = ticks;
                }
            } else if (chosen.length) {
                sendRequest(chosen);
            }
            break;
        }
        }
        return true;
    }

    // Returns true when the action was used.
    function handle(action) {
        if (step === "seasons")
            return handleSeasons(action);
        switch (action) {
        case "left": choice = Math.max(0, choice - 1); return true;
        case "right": choice = Math.min(buttons.length - 1, choice + 1); return true;
        case "back": open = false; return true;
        case "select": {
            const button = buttons[choice];
            if (button === "Request") {
                sendRequest(null);
            } else if (button === "Choose seasons" || button === "More seasons") {
                showSeasons();
            } else if (button === "▶  Play") {
                open = false;
                Config.run("jellyfin_play:" + title);
            } else if (button === "Cancel" || button === "Close") {
                open = false;
            } else if (!(Config.system && Config.system("youtube_watch:" + item.trailer))) {
                console.log("action:youtube_watch:" + item.trailer);
            }
            return true;
        }
        }
        return true;  // up/down etc. do nothing while the dialog is open
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: dialog.theme.animationMs * 2 } }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.65
    }

    Rectangle {
        anchors.centerIn: parent
        width: Config.px(1180)
        height: Math.max(poster.height, dialog.step === "info" ? content.implicitHeight : seasonList.implicitHeight)
                + Config.px(96)
        radius: Config.px(32)
        color: Qt.lighter(dialog.theme.colors.surface, 1.12)
        scale: dialog.open ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs * 2; easing.type: Easing.OutCubic } }

        Rectangle {
            id: poster
            x: Config.px(48)
            anchors.verticalCenter: parent.verticalCenter
            width: Config.px(260)
            height: width * 1.5
            radius: Config.px(16)
            clip: true
            gradient: Gradient {
                GradientStop { position: 0; color: (dialog.item.colors || ["#333333", "#111111"])[0] }
                GradientStop { position: 1; color: (dialog.item.colors || ["#333333", "#111111"])[1] }
            }
            Image {
                anchors.fill: parent
                source: dialog.item.image || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Column {
            id: content
            visible: dialog.step === "info"
            anchors.left: poster.right
            anchors.leftMargin: Config.px(44)
            anchors.right: parent.right
            anchors.rightMargin: Config.px(56)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(14)

            Text {
                width: parent.width
                text: (dialog.item.downloading ? "Downloading"
                       : { 2: "Requested", 3: "Requested", 4: "Partly on your server", 5: "On your server" }[dialog.status]
                         || "Not on your server") + " · " + (dialog.kind === "tv" ? "Series" : "Film")
                      + (dialog.item.meta && dialog.item.meta.match(/\d{4}/) ? " · " + dialog.item.meta.match(/\d{4}/)[0] : "")
                color: dialog.theme.colors.accent
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: dialog.title
                wrapMode: Text.WordWrap
                color: dialog.theme.colors.text
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(48)
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: dialog.item.overview || ""
                wrapMode: Text.WordWrap
                maximumLineCount: 5
                elide: Text.ElideRight
                color: dialog.theme.colors.textDim
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
                lineHeight: 1.15
            }
            Text {
                width: parent.width
                text: dialog.status >= 4 ? "Play opens it in Jellyfin." + (dialog.series ? " More seasons gets the rest." : "")
                      : dialog.status >= 2 ? "It is on its way; it shows up on the home screen when it is ready."
                      : dialog.series ? "Pick the seasons you want; they show up on the home screen when they are ready."
                      : "Request asks Radarr to download it; it shows up on the home screen when it is ready."
                wrapMode: Text.WordWrap
                color: Config.withAlpha(dialog.theme.colors.text, 0.5)
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(19)
            }
            Item {
                width: 1
                height: Config.px(10)
            }
            Row {
                spacing: Config.px(20)
                Repeater {
                    model: dialog.buttons
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool focused: dialog.choice === index
                        width: Math.max(Config.px(150), buttonLabel.implicitWidth + Config.px(56))
                        height: Config.px(68)
                        radius: height / 2
                        color: focused ? dialog.theme.colors.focusBorder : Config.withAlpha(dialog.theme.colors.text, 0.1)
                        scale: focused ? 1.05 : 1
                        Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs } }
                        Behavior on color { ColorAnimation { duration: dialog.theme.animationMs } }
                        Text {
                            id: buttonLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: parent.focused ? dialog.theme.colors.onFocused : dialog.theme.colors.text
                            font.family: dialog.theme.font.family
                            font.pixelSize: Config.px(24)
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // Step 2 for a series: which seasons.
        Column {
            id: seasonList
            visible: dialog.step === "seasons"
            anchors.left: poster.right
            anchors.leftMargin: Config.px(44)
            anchors.right: parent.right
            anchors.rightMargin: Config.px(56)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(14)

            Text {
                text: dialog.title + " · which seasons?"
                width: parent.width
                elide: Text.ElideRight
                color: dialog.theme.colors.text
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(34)
                font.weight: Font.Bold
            }
            Text {
                visible: dialog.seasons === null
                text: "Loading seasons…"
                color: dialog.theme.colors.textDim
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
            }
            ListView {
                id: rows
                visible: dialog.seasons !== null
                width: parent.width
                height: Math.min(contentHeight, Config.px(62) * 7)
                clip: true
                interactive: false
                spacing: Config.px(6)
                currentIndex: dialog.seasonRow
                highlightMoveDuration: dialog.theme.animationMs
                preferredHighlightBegin: Config.px(62) * 2
                preferredHighlightEnd: Config.px(62) * 5
                highlightRangeMode: ListView.ApplyRange
                model: dialog.seasons ? [{ number: -1, name: "All seasons", episodes: 0, state: "" }]
                                        .concat(dialog.seasons) : []
                delegate: Rectangle {
                    id: seasonRowItem
                    required property var modelData
                    required property int index
                    readonly property bool focused: dialog.seasonRow === index
                    readonly property bool isButton: false
                    readonly property bool isAll: modelData.number === -1
                    readonly property bool enabled: isAll ? dialog.regular.length > 0 : modelData.state === ""
                    readonly property bool ticked: isAll ? dialog.regular.length > 0
                                                           && dialog.regular.every(x => dialog.picked[x.number])
                                                         : !!dialog.picked[modelData.number]
                    width: rows.width
                    height: Config.px(56)
                    radius: height / 2
                    color: focused ? (enabled ? dialog.theme.colors.focusBorder : Config.withAlpha(dialog.theme.colors.text, 0.25))
                                   : isButton && enabled ? Config.withAlpha(dialog.theme.colors.accent, 0.25)
                                   : Config.withAlpha(dialog.theme.colors.text, 0.06)
                    Behavior on color { ColorAnimation { duration: dialog.theme.animationMs } }
                    readonly property color ink: focused && enabled ? dialog.theme.colors.onFocused
                                                 : enabled ? dialog.theme.colors.text : dialog.theme.colors.textDim

                    // Checkbox
                    Rectangle {
                        visible: !seasonRowItem.isButton
                        x: Config.px(22)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.px(28)
                        height: width
                        radius: Config.px(7)
                        color: seasonRowItem.ticked ? (seasonRowItem.focused ? dialog.theme.colors.onFocused : dialog.theme.colors.accent)
                                                    : "transparent"
                        border.width: Config.px(3)
                        border.color: seasonRowItem.ticked ? color : seasonRowItem.ink
                        opacity: seasonRowItem.enabled ? 1 : 0.4
                        Text {
                            anchors.centerIn: parent
                            visible: seasonRowItem.ticked
                            text: "✓"
                            color: seasonRowItem.focused ? dialog.theme.colors.focusBorder : dialog.theme.colors.onFocused
                            font.pixelSize: Config.px(20)
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        x: seasonRowItem.isButton ? (parent.width - width) / 2 : Config.px(70)
                        anchors.verticalCenter: parent.verticalCenter
                        text: seasonRowItem.isButton
                              ? (dialog.chosen.length ? "Request " + dialog.chosen.length + " season" + (dialog.chosen.length > 1 ? "s" : "")
                                                      : "Tick the seasons you want")
                              : seasonRowItem.modelData.name
                        color: seasonRowItem.ink
                        font.family: dialog.theme.font.family
                        font.pixelSize: Config.px(24)
                        font.weight: seasonRowItem.isButton || seasonRowItem.isAll ? Font.Bold : Font.DemiBold
                    }
                    Text {
                        visible: !seasonRowItem.isButton && !seasonRowItem.isAll
                        anchors.right: parent.right
                        anchors.rightMargin: Config.px(24)
                        anchors.verticalCenter: parent.verticalCenter
                        text: ({ available: "On your server", partly: "Partly on your server", requested: "Requested",
                                 downloading: "Downloading" }[seasonRowItem.modelData.state]
                               || (seasonRowItem.modelData.episodes ? seasonRowItem.modelData.episodes + " episodes" : "Not out yet"))
                        color: seasonRowItem.ink
                        opacity: 0.8
                        font.family: dialog.theme.font.family
                        font.pixelSize: Config.px(20)
                    }
                }
            }
            // The request button, always in view under the list (row seasons.length + 1).
            Rectangle {
                readonly property bool focused: dialog.seasons !== null && dialog.seasonRow === dialog.seasons.length + 1
                readonly property bool enabled: dialog.chosen.length > 0
                visible: dialog.seasons !== null
                width: parent.width
                height: Config.px(64)
                radius: height / 2
                color: focused ? (enabled ? dialog.theme.colors.focusBorder : Config.withAlpha(dialog.theme.colors.text, 0.25))
                               : enabled ? Config.withAlpha(dialog.theme.colors.accent, 0.25) : Config.withAlpha(dialog.theme.colors.text, 0.06)
                Behavior on color { ColorAnimation { duration: dialog.theme.animationMs } }
                Text {
                    anchors.centerIn: parent
                    text: dialog.chosen.length ? "Request " + dialog.chosen.length + " season" + (dialog.chosen.length > 1 ? "s" : "")
                                               : "Tick the seasons you want"
                    color: parent.focused && parent.enabled ? dialog.theme.colors.onFocused
                           : parent.enabled ? dialog.theme.colors.text : dialog.theme.colors.textDim
                    font.family: dialog.theme.font.family
                    font.pixelSize: Config.px(24)
                    font.weight: Font.Bold
                }
            }
            Text {
                text: "OK ticks · Back to go back"
                color: Config.withAlpha(dialog.theme.colors.text, 0.5)
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(19)
            }
        }
    }
}
