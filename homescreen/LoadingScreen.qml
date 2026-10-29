import QtQuick
import "."

// Full-screen "Starting Steam…" while a Moonlight stream connects (Moonlight's own windows are kept hidden meanwhile,
// see bigscreen/HomeScreen.qml). show(name) picks the tile with that name from apps.json for its logo and colours
// (Steam), else Moonlight's. Back/Home cancel (Home routes them to Config.system("moonlight_cancel")).
Item {
    id: loading
    property bool open: false
    property string name: ""
    property var app: null
    readonly property var theme: Config.theme
    readonly property var fallback: Config.apps.find(a => a.id === "moonlight") || {}
    readonly property var look: app || fallback

    function show(appName) {
        name = appName || "Moonlight";
        app = Config.apps.find(a => (a.name || "").toLowerCase() === name.toLowerCase()) || null;
        open = true;
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

    Text {
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
