import QtQuick
import "."

// Full-screen "Starting Steam…" while a Moonlight stream connects (Moonlight's own windows are kept hidden meanwhile,
// see bigscreen/HomeScreen.qml). show(name) picks the tile with that name from apps.json for its logo and colours
// (Steam), else Moonlight's. Back/Home cancel (Home routes them to Config.system("moonlight_cancel")). The connected
// game controllers (system.py controllers) show at the bottom with their battery, so a friend's pad that is still
// asleep gets noticed before the game starts.
Item {
    id: loading
    property bool open: false
    property string name: ""
    property var app: null
    property var pads: null       // [{name, percent}] once system.py has answered
    readonly property var theme: Config.theme
    readonly property var fallback: Config.apps.find(a => a.id === "moonlight") || {}
    readonly property var look: app || fallback

    function show(appName) {
        name = appName || "Moonlight";
        app = Config.apps.find(a => (a.name || "").toLowerCase() === name.toLowerCase()) || null;
        pads = null;
        open = true;
        if (Config.systemQuery)
            Config.systemQuery(["controllers"], r => loading.pads = r && r.controllers ? r.controllers : []);
    }

    function hide() {
        open = false;
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: loading.theme.animationMs * 3 } }

    // Background: the app's colours, a soft glow behind the logo.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter((loading.look.colors || ["#1b2838"])[0], 1.25) }
            GradientStop { position: 1; color: "#05070a" }
        }
    }
    Rectangle {
        width: parent.width * 0.6
        height: width
        radius: width / 2
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Config.px(60)
        color: Qt.lighter((loading.look.colors || ["#1b2838"])[0], 1.8)
        opacity: 0.18
        scale: pulse.running ? 1 : 1
        SequentialAnimation on opacity {
            id: pulse
            running: loading.open
            loops: Animation.Infinite
            NumberAnimation { from: 0.12; to: 0.24; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.24; to: 0.12; duration: 1400; easing.type: Easing.InOutSine }
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Config.px(40)
        spacing: Config.px(36)

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.px(220)
            height: width
            source: loading.look.image ? Qt.resolvedUrl(loading.look.image) : ""
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Starting " + loading.name
            color: loading.theme.colors.text
            font.family: loading.theme.font.family
            font.pixelSize: Config.px(56)
            font.weight: Font.Bold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Connecting to the game server…"
            color: loading.theme.colors.textDim
            font.family: loading.theme.font.family
            font.pixelSize: Config.px(26)
        }
        // Sliding bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Config.px(520)
            height: Config.px(6)
            radius: height / 2
            color: Config.withAlpha(loading.theme.colors.text, 0.15)
            clip: true
            Rectangle {
                width: parent.width * 0.3
                height: parent.height
                radius: height / 2
                color: loading.theme.colors.accent
                NumberAnimation on x {
                    running: loading.open
                    loops: Animation.Infinite
                    from: -parent.width * 0.3
                    to: parent.width
                    duration: 1300
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    // Controllers: a chip each, or how to pair one.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: cancelHint.top
        anchors.bottomMargin: Config.px(28)
        spacing: Config.px(16)
        visible: loading.pads !== null
        Repeater {
            model: loading.pads || []
            delegate: Rectangle {
                id: padChip
                required property var modelData
                readonly property bool low: modelData.percent !== null && modelData.percent <= 15
                width: chip.implicitWidth + Config.px(40)
                height: Config.px(56)
                radius: height / 2
                color: Config.withAlpha("#ffffff", 0.1)
                Row {
                    id: chip
                    anchors.centerIn: parent
                    spacing: Config.px(12)
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.px(28)
                        height: width
                        sourceSize: Qt.size(width * 2, height * 2)
                        source: Qt.resolvedUrl("icons/settings/gamepad.svg")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: padChip.modelData.name
                              + (padChip.modelData.percent !== null ? "  ·  " + padChip.modelData.percent + " %" : "")
                        color: padChip.low ? "#ffb4a9" : loading.theme.colors.text
                        font.family: loading.theme.font.family
                        font.pixelSize: Config.px(22)
                    }
                }
            }
        }
        Text {
            visible: loading.pads !== null && loading.pads.length === 0
            text: "No controller connected · pair one in Settings → Controllers"
            color: Config.withAlpha(loading.theme.colors.text, 0.6)
            font.family: loading.theme.font.family
            font.pixelSize: Config.px(22)
        }
    }

    Text {
        id: cancelHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(64)
        text: "Back to cancel"
        color: Config.withAlpha(loading.theme.colors.text, 0.45)
        font.family: loading.theme.font.family
        font.pixelSize: Config.px(22)
    }

    // Swallows the mouse, so nothing behind it reacts.
    MouseArea {
        anchors.fill: parent
        enabled: loading.open
    }
}
