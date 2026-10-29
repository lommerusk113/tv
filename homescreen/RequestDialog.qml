import QtQuick
import "."

// "Request <title>?" for a "Get more" tile (titles not on the server): poster, plot, and Request / ▶ Trailer / Cancel.
// Left/right pick a button, OK runs it, Back cancels. Request goes to
// Config.system("jellyseerr_request:<movie|tv>:<tmdb id>:<title>"); Trailer plays the tile's "trailer" (YouTube id,
// jellyseerr.py) through Config.system("youtube_watch:<id>") and leaves the dialog open for when you come back.
Item {
    id: dialog
    property bool open: false
    property string kind: ""
    property string tmdb: ""
    property string title: ""
    property var item: ({})
    property int choice: 0
    readonly property var theme: Config.theme
    readonly property var buttons: item.trailer ? ["Request", "▶  Trailer", "Cancel"] : ["Request", "Cancel"]

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
    function ask(action) {
        const parts = action.split(":");
        kind = parts[1];
        tmdb = parts[2];
        title = parts.slice(3).join(":");
        item = findItem(action);
        choice = 0;
        open = true;
    }

    // Returns true when the action was used.
    function handle(action) {
        switch (action) {
        case "left": choice = Math.max(0, choice - 1); return true;
        case "right": choice = Math.min(buttons.length - 1, choice + 1); return true;
        case "back": open = false; return true;
        case "select": {
            const button = buttons[choice];
            if (button === "Request") {
                open = false;
                const request = "jellyseerr_request:" + kind + ":" + tmdb + ":" + title;
                if (!(Config.system && Config.system(request)))
                    console.log("action:" + request);
            } else if (button === "Cancel") {
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
        height: Math.max(poster.height, content.implicitHeight) + Config.px(96)
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
            anchors.left: poster.right
            anchors.leftMargin: Config.px(44)
            anchors.right: parent.right
            anchors.rightMargin: Config.px(56)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(14)

            Text {
                width: parent.width
                text: "Not on your server · " + (dialog.kind === "tv" ? "Series" : "Film")
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
                text: "Request asks Sonarr/Radarr to download it" + (dialog.kind === "tv" ? " (all seasons)" : "")
                      + "; it shows up on the home screen when it is ready."
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
                        width: Config.px(220)
                        height: Config.px(68)
                        radius: height / 2
                        color: focused ? dialog.theme.colors.focusBorder : Config.withAlpha(dialog.theme.colors.text, 0.1)
                        scale: focused ? 1.05 : 1
                        Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs } }
                        Behavior on color { ColorAnimation { duration: dialog.theme.animationMs } }
                        Text {
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
    }
}
