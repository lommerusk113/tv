import QtQuick
import "."

// ⓘ on a media tile: a full-screen details page. Jellyfin items (action jellyfin_play_id:<id>) get their details from
// `jellyfin.py info` (Config.scriptQuery): episode, year, genres, runtime, "Ends at", progress, plot, and the buttons
// Resume / Start over / Go to series / Mark as watched. Other tiles (YouTube...) show what the tile has, with Play.
// Left/right pick a button, OK runs it, Back closes.
Item {
    id: sheet
    property bool open: false
    property var item: ({})
    property var info: ({})       // jellyfin.py info, when it has answered
    property int choice: 0
    property date now: new Date()
    readonly property var theme: Config.theme
    readonly property string jellyfinId: (item.action || "").startsWith("jellyfin_play_id:") ? item.action.slice(17) : ""
    readonly property int minutesLeft: Math.max(0, (info.runtime || 0) - (info.position || 0))
    readonly property var buttons: {
        if (!jellyfinId)
            return ["▶  Play"];
        const out = info.position > 0 ? ["▶  Resume", "↺  Start over"] : ["▶  Play"];
        if (info.seriesId)
            out.push("Go to series");
        out.push(info.played ? "Mark as unwatched" : "Mark as watched");
        return out;
    }
    onButtonsChanged: choice = Math.min(choice, buttons.length - 1)

    signal message(string text)

    function show(tile) {
        item = tile || {};
        info = {};
        choice = 0;
        now = new Date();
        open = true;
        if (jellyfinId && Config.scriptQuery) {
            const asked = jellyfinId;
            Config.scriptQuery("jellyfin", ["info", asked], data => {
                if (data && data.ok && sheet.jellyfinId === asked)
                    sheet.info = data;
            });
        }
    }

    function handle(action) {
        switch (action) {
        case "left": choice = Math.max(0, choice - 1); break;
        case "right": choice = Math.min(buttons.length - 1, choice + 1); break;
        case "back": open = false; break;
        case "select": run(buttons[choice]); break;
        }
        return true;
    }

    function run(button) {
        if (button === "▶  Play" || button === "▶  Resume") {
            open = false;
            Config.run(item.action || (item.app ? "launch:" + item.app : ""));
        } else if (button === "↺  Start over") {
            open = false;
            Config.run("jellyfin_play_id:" + jellyfinId + ":start");
        } else if (button === "Go to series") {
            open = false;
            Config.run("jellyfin_show:" + info.seriesId);
        } else if (Config.scriptQuery) {  // Mark as (un)watched
            const played = !info.played;
            Config.scriptQuery("jellyfin", [played ? "played" : "unplayed", jellyfinId], data => {
                if (!data || !data.ok) {
                    sheet.message("Could not change it on Jellyfin");
                    return;
                }
                sheet.info = Object.assign({}, sheet.info, { played: played, position: 0 });
                sheet.message(played ? "Marked as watched" : "Marked as unwatched");
                Config.run("refresh_rows");  // Continue watching changes
            });
        }
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: sheet.theme.animationMs * 2 } }

    Rectangle {
        anchors.fill: parent
        color: sheet.theme.colors.background
    }
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        source: sheet.info.backdrop || sheet.item.backdrop || sheet.item.image || ""
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Config.withAlpha(sheet.theme.colors.background, 0.97) }
            GradientStop { position: 0.5; color: Config.withAlpha(sheet.theme.colors.background, 0.8) }
            GradientStop { position: 1.0; color: Config.withAlpha(sheet.theme.colors.background, 0.25) }
        }
    }

    Column {
        x: Config.px(sheet.theme.spacing.page)
        anchors.verticalCenter: parent.verticalCenter
        width: Config.px(1050)
        spacing: Config.px(16)

        Text {
            width: parent.width
            text: sheet.info.title || sheet.item.title || ""
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: sheet.theme.colors.text
            font.family: sheet.theme.font.family
            font.pixelSize: Config.px(64)
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: sheet.info.episode || (sheet.jellyfinId ? "" : sheet.item.subtitle || sheet.item.meta || "")
            elide: Text.ElideRight
            color: sheet.theme.colors.text
            font.family: sheet.theme.font.family
            font.pixelSize: Config.px(30)
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: [sheet.info.year, (sheet.info.genres || []).join(", "), sheet.info.rating,
                   sheet.info.runtime ? sheet.info.runtime + " min" : ""].filter(p => p).join("  ·  ")
            color: sheet.theme.colors.textDim
            font.family: sheet.theme.font.family
            font.pixelSize: Config.px(24)
        }
        // "Ends at" and how far you are
        Row {
            visible: sheet.minutesLeft > 0
            spacing: Config.px(20)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Ends at " + Qt.formatTime(new Date(sheet.now.getTime() + sheet.minutesLeft * 60000), "HH:mm")
                      + (sheet.info.position > 0 ? "  ·  " + sheet.minutesLeft + " min left" : "")
                color: sheet.theme.colors.accent
                font.family: sheet.theme.font.family
                font.pixelSize: Config.px(24)
                font.weight: Font.DemiBold
            }
            Rectangle {
                visible: sheet.info.position > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(220)
                height: Config.px(6)
                radius: height / 2
                color: Config.withAlpha(sheet.theme.colors.text, 0.2)
                Rectangle {
                    width: parent.width * Math.min(1, (sheet.info.position || 0) / Math.max(1, sheet.info.runtime || 1))
                    height: parent.height
                    radius: height / 2
                    color: sheet.theme.colors.accent
                }
            }
        }
        Text {
            width: Config.px(950)
            visible: text !== ""
            text: sheet.info.overview || sheet.item.overview || sheet.item.description || ""
            wrapMode: Text.WordWrap
            maximumLineCount: 6
            elide: Text.ElideRight
            color: Config.withAlpha(sheet.theme.colors.text, 0.85)
            font.family: sheet.theme.font.family
            font.pixelSize: Config.px(24)
            lineHeight: 1.25
        }
        Item {
            width: 1
            height: Config.px(12)
        }
        Row {
            spacing: Config.px(20)
            Repeater {
                model: sheet.buttons
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool focused: sheet.choice === index
                    width: label.implicitWidth + Config.px(64)
                    height: Config.px(68)
                    radius: height / 2
                    color: focused ? sheet.theme.colors.focusBorder : Config.withAlpha(sheet.theme.colors.text, 0.12)
                    scale: focused ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: sheet.theme.animationMs } }
                    Behavior on color { ColorAnimation { duration: sheet.theme.animationMs } }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.focused ? sheet.theme.colors.onFocused : sheet.theme.colors.text
                        font.family: sheet.theme.font.family
                        font.pixelSize: Config.px(24)
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }
}
