import QtQuick
import "."

// "Not on your server": what Jellyseerr found for a title that is not on Jellyfin (voice "play X" with no match, or
// "download X"; jellyseerr.py search). Posters left/right, OK requests the focused one through
// Config.system("jellyseerr_request:<kind>:<tmdb>:<title>") (a series: chooseSeasons -> RequestDialog's season list); one on the server plays (jellyfin_play), a requested one
// says so. Back closes.
Item {
    id: dialog
    property bool open: false
    property string query: ""
    property var results: []
    property int choice: 0
    readonly property var theme: Config.theme
    readonly property var current: results[choice] || ({})
    readonly property bool anyMissing: results.some(r => r.status < 4)

    signal message(string text)
    signal chooseSeasons(var item)  // a series: Home opens RequestDialog's season list for it

    function ask(result) {
        query = result.query || "";
        results = result.results || [];
        choice = 0;
        open = results.length > 0;
    }

    // Returns true when the action was used (everything is, while open).
    function handle(action) {
        switch (action) {
        case "left": choice = Math.max(0, choice - 1); break;
        case "right": choice = Math.min(results.length - 1, choice + 1); break;
        case "back": open = false; break;
        case "select":
            if (current.status >= 4) {  // it is on the server after all: play it
                open = false;
                if (!(Config.system && Config.system("jellyfin_play:" + current.title)))
                    console.log("action:jellyfin_play:" + current.title);
                break;
            }
            if (current.status >= 2) {
                message("“" + current.title + "” is already requested");
                break;
            }
            open = false;
            if (current.kind === "tv") {
                chooseSeasons(current);
                break;
            }
            const request = "jellyseerr_request:" + current.kind + ":" + current.tmdb + ":" + current.title;
            if (!(Config.system && Config.system(request)))
                console.log("action:" + request);
            break;
        }
        return true;
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: dialog.theme.animationMs * 2 } }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.7
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Config.px(1500)
        height: content.implicitHeight + Config.px(96)
        radius: Config.px(32)
        color: Qt.lighter(dialog.theme.colors.surface, 1.12)
        scale: dialog.open ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs * 2; easing.type: Easing.OutCubic } }

        Column {
            id: content
            anchors.centerIn: parent
            width: parent.width - Config.px(112)
            spacing: Config.px(14)

            Text {
                text: dialog.anyMissing ? "Not on your server" : "Already on your server"
                color: dialog.theme.colors.accent
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: dialog.anyMissing ? "“" + dialog.query + "” isn't downloaded. Pick one to download it."
                                        : "Found “" + dialog.query + "” on your server"
                wrapMode: Text.WordWrap
                color: dialog.theme.colors.text
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(36)
                font.weight: Font.Bold
            }
            Item {
                width: 1
                height: Config.px(10)
            }

            Row {
                spacing: Config.px(26)
                Repeater {
                    model: dialog.results
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool focused: dialog.choice === index
                        width: Config.px(190)
                        height: poster.height + Config.px(70)

                        Rectangle {
                            id: poster
                            width: parent.width
                            height: width * 1.5
                            radius: Config.px(14)
                            clip: true
                            scale: parent.focused ? 1.08 : 1
                            z: 1
                            Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: (modelData.colors || ["#333", "#111"])[0] }
                                GradientStop { position: 1; color: (modelData.colors || ["#333", "#111"])[1] }
                            }
                            border.width: parent.focused ? Config.px(4) : 0
                            border.color: dialog.theme.colors.focusBorder
                            Image {
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                source: modelData.image || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            // Status badge: already requested / on the server.
                            Rectangle {
                                visible: !!modelData.label
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: Config.px(10)
                                width: badge.implicitWidth + Config.px(20)
                                height: Config.px(32)
                                radius: height / 2
                                color: modelData.status >= 4 ? "#2e7d32" : "#b26a00"
                                Text {
                                    id: badge
                                    anchors.centerIn: parent
                                    text: modelData.label || ""
                                    color: "#ffffff"
                                    font.family: dialog.theme.font.family
                                    font.pixelSize: Config.px(16)
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        Column {
                            anchors.top: poster.bottom
                            anchors.topMargin: Config.px(14)
                            width: parent.width
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: modelData.title
                                color: dialog.theme.colors.text
                                font.family: dialog.theme.font.family
                                font.pixelSize: Config.px(20)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: (modelData.kind === "tv" ? "Series" : "Film") + (modelData.year ? " · " + modelData.year : "")
                                color: dialog.theme.colors.textDim
                                font.family: dialog.theme.font.family
                                font.pixelSize: Config.px(17)
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                height: Config.px(64)
                text: dialog.current.overview || ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: dialog.theme.colors.textDim
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(21)
            }
            Text {
                text: dialog.current.status >= 4 ? "OK plays it  ·  Back to close"
                      : dialog.current.status >= 2 ? "Already requested  ·  Back to close"
                                                 : (dialog.current.kind === "tv" ? "OK picks the seasons of “" : "OK downloads “")
                                                   + (dialog.current.title || "") + "” (via Jellyseerr)  ·  Back to close"
                color: Config.withAlpha(dialog.theme.colors.text, 0.6)
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(20)
            }
        }
    }
}
