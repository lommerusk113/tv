import QtQuick
import "."

// "Request <title>?" for a "Get more" tile (titles not on the server). Left/right pick Request or Cancel, OK runs it,
// Back cancels. Request goes to Config.system("jellyseerr_request:<movie|tv>:<tmdb id>:<title>") (Bigscreen).
Item {
    id: dialog
    property bool open: false
    property string kind: ""
    property string tmdb: ""
    property string title: ""
    property int choice: 0   // 0 = Request, 1 = Cancel
    readonly property var theme: Config.theme

    // action is "request:<movie|tv>:<tmdb id>:<title>" (the title may contain colons)
    function ask(action) {
        const parts = action.split(":");
        kind = parts[1];
        tmdb = parts[2];
        title = parts.slice(3).join(":");
        choice = 0;
        open = true;
    }

    // Returns true when the action was used.
    function handle(action) {
        switch (action) {
        case "left": choice = 0; return true;
        case "right": choice = 1; return true;
        case "back": open = false; return true;
        case "select":
            open = false;
            if (choice === 0) {
                const request = "jellyseerr_request:" + kind + ":" + tmdb + ":" + title;
                if (!(Config.system && Config.system(request)))
                    console.log("action:" + request);
            }
            return true;
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
        opacity: 0.6
    }

    Rectangle {
        anchors.centerIn: parent
        width: Config.px(760)
        height: content.implicitHeight + Config.px(96)
        radius: Config.px(32)
        color: Qt.lighter(dialog.theme.colors.surface, 1.12)
        scale: dialog.open ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs * 2; easing.type: Easing.OutCubic } }

        Column {
            id: content
            anchors.centerIn: parent
            width: parent.width - Config.px(112)
            spacing: Config.px(16)

            Text {
                width: parent.width
                text: "Request " + (dialog.kind === "tv" ? "this series" : "this film") + "?"
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
                font.pixelSize: Config.px(44)
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: "Jellyseerr asks Sonarr/Radarr to download it" + (dialog.kind === "tv" ? " (all seasons)" : "")
                      + ". It shows up on the home screen when it is ready."
                wrapMode: Text.WordWrap
                color: dialog.theme.colors.textDim
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
            }
            Item {
                width: 1
                height: Config.px(12)
            }
            Row {
                spacing: Config.px(20)
                Repeater {
                    model: ["Request", "Cancel"]
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
