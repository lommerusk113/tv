import QtQuick
import QtQuick.Effects
import "."

// "Ready to watch": a request that just became available (jellyseerr.py ready), as a poster card that slides in at
// the top right, over apps too (bigscreen/HomeScreen.qml puts it in an overlay window), for a few seconds.
// show() queues: several titles come one after the other.
Item {
    id: toast
    property var queue: []
    property var current: null
    readonly property var theme: Config.theme

    function show(items) {
        queue = queue.concat(items);
        if (!current)
            next();
    }

    function next() {
        current = queue.length ? queue[0] : null;
        queue = queue.slice(1);
        if (current)
            hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 9000
        onTriggered: {
            toast.current = null;
            gap.restart();
        }
    }
    Timer {
        id: gap
        interval: 700
        onTriggered: toast.next()
    }

    // For the window around it (an item in a hidden window is never "visible" itself, so it cannot follow that).
    readonly property bool showing: body.opacity > 0

    width: card.width
    height: card.height

    Item {
        id: body
        width: card.width
        height: card.height
        opacity: toast.current ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        transform: Translate {
            x: toast.current ? 0 : Config.px(80)
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }

        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: Config.px(40)
            color: "#99000000"
        }

        Rectangle {
            id: card
            width: Config.px(620)
            height: Config.px(176)
            radius: Config.px(24)
            color: Qt.lighter(toast.theme ? toast.theme.colors.surface : "#1f2329", 1.15)
            border.width: 1
            border.color: Config.withAlpha("#ffffff", 0.08)

            Rectangle {
                id: poster
                x: Config.px(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(96)
                height: Config.px(144)
                radius: Config.px(10)
                clip: true
                color: "#333333"
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: toast.current ? toast.current.image : ""
                }
            }
            Column {
                anchors.left: poster.right
                anchors.leftMargin: Config.px(22)
                anchors.right: parent.right
                anchors.rightMargin: Config.px(22)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Config.px(6)
                Text {
                    text: toast.current && toast.current.partly ? "New episodes are ready" : "Ready to watch"
                    color: toast.theme ? toast.theme.colors.accent : "#8ab4f8"
                    font.family: toast.theme ? toast.theme.font.family : ""
                    font.pixelSize: Config.px(20)
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: toast.current ? toast.current.title : ""
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    color: toast.theme ? toast.theme.colors.text : "#ffffff"
                    font.family: toast.theme ? toast.theme.font.family : ""
                    font.pixelSize: Config.px(32)
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: toast.current ? "Say “play " + toast.current.title + "”" : ""
                    elide: Text.ElideRight
                    color: toast.theme ? toast.theme.colors.textDim : "#9aa0a6"
                    font.family: toast.theme ? toast.theme.font.family : ""
                    font.pixelSize: Config.px(20)
                }
            }
        }
    }
}
