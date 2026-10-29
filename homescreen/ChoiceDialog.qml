import QtQuick
import "."

// "Did you mean…?" after a voice command the AI step was not sure about (agent.py "options"): up to 3 guesses, each a
// label + action. Up/down pick, OK runs it (choose(action) signal), Back closes.
Item {
    id: dialog
    property bool open: false
    property string heard: ""
    property var options: []
    property int choice: 0
    readonly property var theme: Config.theme

    signal chosen(string action)

    function ask(text, opts) {
        heard = text || "";
        options = opts || [];
        choice = 0;
        open = options.length > 0;
    }

    // Returns true when the action was used (everything is, while open).
    function handle(action) {
        switch (action) {
        case "up": choice = Math.max(0, choice - 1); break;
        case "down": choice = Math.min(options.length, choice + 1); break;  // the last row is "None of these"
        case "back": open = false; break;
        case "select":
            open = false;
            if (choice < options.length)
                chosen(options[choice].action);
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
        opacity: 0.6
    }

    Rectangle {
        anchors.centerIn: parent
        width: Config.px(820)
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
                width: parent.width
                text: "Did you mean…"
                color: dialog.theme.colors.accent
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(22)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: dialog.heard ? "I heard “" + dialog.heard + "”" : ""
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: dialog.theme.colors.textDim
                font.family: dialog.theme.font.family
                font.pixelSize: Config.px(24)
            }
            Item {
                width: 1
                height: Config.px(6)
            }
            Repeater {
                model: dialog.options.length + 1
                delegate: Rectangle {
                    required property int index
                    readonly property bool focused: dialog.choice === index
                    readonly property bool none: index === dialog.options.length
                    width: content.width
                    height: Config.px(74)
                    radius: height / 2
                    color: focused ? dialog.theme.colors.focusBorder : Config.withAlpha(dialog.theme.colors.text, 0.08)
                    scale: focused ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: dialog.theme.animationMs } }
                    Behavior on color { ColorAnimation { duration: dialog.theme.animationMs } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Config.px(32)
                        width: parent.width - Config.px(64)
                        elide: Text.ElideRight
                        text: parent.none ? "None of these" : dialog.options[parent.index].label
                        color: parent.focused ? dialog.theme.colors.onFocused
                                              : parent.none ? dialog.theme.colors.textDim : dialog.theme.colors.text
                        font.family: dialog.theme.font.family
                        font.pixelSize: Config.px(28)
                        font.weight: parent.none ? Font.Normal : Font.DemiBold
                    }
                }
            }
        }
    }
}
