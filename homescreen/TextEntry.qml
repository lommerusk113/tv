import QtQuick
import QtQuick.Effects
import "."

// Keyboard panel for typing into an app's text field (Jellyseerr's login and search, Jellyfin's search): opened by
// OK on the field (osk.py watch -> "keyboard:<app>:<field>"), shown in HomeScreen.qml's overlay window over the app.
// What is typed goes into the field as you type (edited(text) -> osk.py set); the done key submits (submitted()),
// Back closes it. A plugged-in keyboard types too.
Item {
    id: entry
    property bool open: false
    property string app: ""
    property string label: ""
    property bool secret: false
    property string text: ""
    readonly property var theme: Config.theme

    signal edited(string text)
    signal submitted()

    // field: {type: text|password|email, value, label} from the page
    function show(appId, field) {
        app = appId;
        secret = field.type === "password";
        label = field.label || (secret ? "Password" : "");
        text = field.value || "";
        keyboard.row = 1;
        keyboard.col = 0;
        keyboard.shift = false;
        keyboard.symbols = false;
        open = true;
    }

    function setText(value) {
        text = value;
        edited(value);
    }

    function handle(action) {
        if (action === "back") {
            open = false;
            return;
        }
        keyboard.handle(action);
    }

    // Remote: arrows, OK (Return/Enter/Select), Back (Escape/Back); anything printable from a real keyboard is typed.
    function key(event) {
        const actions = { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
                          [Qt.Key_Return]: "select", [Qt.Key_Enter]: "select", [Qt.Key_Select]: "select",
                          [Qt.Key_Escape]: "back", [Qt.Key_Back]: "back" };
        if (actions[event.key]) {
            handle(actions[event.key]);
        } else if (event.key === Qt.Key_Backspace) {
            setText(text.slice(0, -1));
        } else if (event.text && event.text >= " ") {
            setText(text + event.text);
        } else {
            return;
        }
        event.accepted = true;
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: entry.theme.animationMs * 2 } }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: Config.px(60)
        color: "#cc000000"
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(40)
        width: Config.px(1320)
        height: column.implicitHeight + Config.px(80)
        radius: Config.px(36)
        color: Qt.lighter(entry.theme.colors.surface, 1.12)
        border.width: 1
        border.color: Config.withAlpha(entry.theme.colors.text, 0.08)
        transform: Translate {
            y: entry.open ? 0 : Config.px(60)
            Behavior on y { NumberAnimation { duration: entry.theme.animationMs * 2; easing.type: Easing.OutCubic } }
        }

        Column {
            id: column
            anchors.centerIn: parent
            width: parent.width - Config.px(80)
            spacing: Config.px(22)

            // What is in the field: label above, the text (dots for a password) with a blinking caret.
            Rectangle {
                width: parent.width
                height: Config.px(96)
                radius: Config.px(20)
                color: Config.withAlpha(entry.theme.colors.text, 0.06)
                border.width: Config.px(2)
                border.color: entry.theme.colors.accent

                Text {
                    x: Config.px(28)
                    y: Config.px(12)
                    text: entry.label || "Type"
                    color: entry.theme.colors.accent
                    font.family: entry.theme.font.family
                    font.pixelSize: Config.px(19)
                    font.weight: Font.DemiBold
                }
                Row {
                    x: Config.px(28)
                    y: Config.px(42)
                    width: parent.width - Config.px(260)
                    spacing: Config.px(2)
                    Text {
                        id: value
                        width: Math.min(implicitWidth, parent.width - caret.width)
                        elide: Text.ElideLeft
                        text: entry.secret ? "•".repeat(entry.text.length) : entry.text
                        color: entry.theme.colors.text
                        font.family: entry.theme.font.family
                        font.pixelSize: Config.px(34)
                        font.letterSpacing: entry.secret ? Config.px(4) : 0
                    }
                    Rectangle {
                        id: caret
                        width: Config.px(3)
                        height: Config.px(38)
                        anchors.verticalCenter: value.verticalCenter
                        color: entry.theme.colors.text
                        SequentialAnimation on opacity {
                            running: entry.open
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Config.px(28)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Back to close"
                    color: Config.withAlpha(entry.theme.colors.text, 0.5)
                    font.family: entry.theme.font.family
                    font.pixelSize: Config.px(20)
                }
            }

            OnScreenKeyboard {
                id: keyboard
                width: parent.width
                doneLabel: entry.label.match(/search|søk/i) ? "Search" : "Enter ⏎"
                onTyped: t => entry.setText(entry.text + t)
                onBackspace: entry.setText(entry.text.slice(0, -1))
                onDone: entry.submitted()
            }
        }
    }
}
