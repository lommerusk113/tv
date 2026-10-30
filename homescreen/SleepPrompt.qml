import QtQuick
import QtQuick.Effects
import "."

// The last minute before the TV turns off (sleep timer, or "Still watching?" after hours of playing untouched):
// a card with a countdown. bigscreen/HomeScreen.qml shows it in an overlay window that takes the keyboard, so any
// remote button reaches it (also over apps) and keeps watching (kept()); at 0 it emits expired().
Item {
    id: prompt
    property bool open: false
    property string title: ""
    property int seconds: 60
    readonly property var theme: Config.theme

    signal kept()
    signal expired()

    function show(text, from) {
        title = text;
        seconds = from || 60;
        open = true;
    }

    function key(event) {
        if (!open)
            return;
        event.accepted = true;
        open = false;
        kept();
    }

    Timer {
        interval: 1000
        repeat: true
        running: prompt.open
        onTriggered: {
            if (--prompt.seconds > 0)
                return;
            prompt.open = false;
            prompt.expired();
        }
    }

    // For the window around it (an item in a hidden window never counts as visible itself).
    readonly property bool showing: card.opacity > 0

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: Config.px(60)
        color: "#cc000000"
        opacity: card.opacity
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Config.px(860)
        height: Config.px(220)
        radius: Config.px(32)
        color: Qt.lighter(prompt.theme ? prompt.theme.colors.surface : "#1f2329", 1.15)
        border.width: 1
        border.color: Config.withAlpha("#ffffff", 0.08)
        opacity: prompt.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }

        // Countdown ring
        Item {
            id: ring
            x: Config.px(36)
            anchors.verticalCenter: parent.verticalCenter
            width: Config.px(140)
            height: width
            Canvas {
                id: arc
                anchors.fill: parent
                property real part: prompt.seconds / 60
                onPartChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.lineWidth = Config.px(10);
                    ctx.strokeStyle = Config.withAlpha("#ffffff", 0.12);
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth, 0, 2 * Math.PI);
                    ctx.stroke();
                    ctx.strokeStyle = prompt.theme ? prompt.theme.colors.accent : "#8ab4f8";
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(width / 2, height / 2, width / 2 - ctx.lineWidth, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * part);
                    ctx.stroke();
                }
            }
            Text {
                anchors.centerIn: parent
                text: prompt.seconds
                color: prompt.theme ? prompt.theme.colors.text : "#ffffff"
                font.family: prompt.theme ? prompt.theme.font.family : ""
                font.pixelSize: Config.px(52)
                font.weight: Font.Bold
            }
        }
        Column {
            anchors.left: ring.right
            anchors.leftMargin: Config.px(36)
            anchors.right: parent.right
            anchors.rightMargin: Config.px(36)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(10)
            Text {
                width: parent.width
                text: prompt.title
                wrapMode: Text.WordWrap
                color: prompt.theme ? prompt.theme.colors.text : "#ffffff"
                font.family: prompt.theme ? prompt.theme.font.family : ""
                font.pixelSize: Config.px(40)
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: "Press any button to keep watching"
                color: prompt.theme ? prompt.theme.colors.textDim : "#9aa0a6"
                font.family: prompt.theme ? prompt.theme.font.family : ""
                font.pixelSize: Config.px(26)
            }
        }
    }
}
