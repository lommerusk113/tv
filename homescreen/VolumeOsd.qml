import QtQuick
import QtQuick.Effects
import "."

// Volume popup (instead of Plasma's small one): a tall pill at the right edge with the level, a bar that fills from
// the bottom and an icon, for ~2 s after any change. bigscreen/HomeScreen.qml puts it in an overlay window over apps
// and calls show(); Plasma's own popup is turned off (plasmaparc VolumeOsd/MuteOsd, scripts/install.sh).
Item {
    id: osd
    property real level: 0      // 0..1 (can go above 1 if something else raised it)
    property bool muted: false
    property bool open: false
    readonly property var theme: Config.theme
    readonly property bool showing: body.opacity > 0
    readonly property int percent: Math.round(level * 100)

    function show(value, isMuted) {
        level = value;
        muted = isMuted;
        open = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osd.open = false
    }

    width: card.width
    height: card.height

    Item {
        id: body
        width: card.width
        height: card.height
        opacity: osd.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        transform: Translate {
            x: osd.open ? 0 : Config.px(60)
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }

        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: Config.px(48)
            color: "#b0000000"
        }

        Rectangle {
            id: card
            width: Config.px(104)
            height: Config.px(460)
            radius: width / 2
            color: Qt.alpha(osd.theme.colors.surface, 0.94)
            border.width: 1
            border.color: Qt.alpha(osd.theme.colors.text, 0.08)

            Text {
                id: number
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Config.px(30)
                text: osd.muted ? "–" : osd.percent
                color: osd.muted ? osd.theme.colors.textDim : osd.theme.colors.text
                font.family: osd.theme.font.family
                font.pixelSize: Config.px(30)
                font.weight: Font.DemiBold
            }

            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: number.bottom
                anchors.topMargin: Config.px(18)
                anchors.bottom: icon.top
                anchors.bottomMargin: Config.px(24)
                width: Config.px(14)
                radius: width / 2
                color: Qt.alpha(osd.theme.colors.text, 0.14)

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: parent.radius
                    height: osd.level > 0 ? Math.max(width, parent.height * Math.min(osd.level, 1)) : 0
                    color: osd.muted ? osd.theme.colors.textDim : "#ffffff"
                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    layer.enabled: !osd.muted
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#ffffff"
                        shadowBlur: 0.6
                        shadowOpacity: 0.5
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                    }
                }
            }

            Item {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Config.px(30)
                width: Config.px(40)
                height: width
                Image {
                    id: img
                    anchors.fill: parent
                    source: Qt.resolvedUrl("icons/settings/volume-" + (osd.muted || osd.level <= 0 ? "muted"
                                           : osd.level < 0.34 ? "low" : osd.level < 0.67 ? "medium" : "high") + ".svg")
                    sourceSize: Qt.size(width * 2, height * 2)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: img
                    colorization: osd.muted ? 0 : 1  // muted keeps Breeze's red strike-through
                    colorizationColor: osd.theme.colors.text
                    brightness: osd.muted ? 0 : 1
                }
            }
        }
    }
}
