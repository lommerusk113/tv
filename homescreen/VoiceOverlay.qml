import QtQuick
import QtQuick.Effects
import "."

// Voice feedback card: listening -> thinking -> what was heard, or why nothing happened. show(state, text); hides
// itself after the result states. Used at the bottom of the home screen, and inside apps in an overlay window
// (bigscreen/HomeScreen.qml voiceInApp). A glowing mic badge, a title with a hint under it, sound bars while listening.
Item {
    id: overlay
    property string state: ""
    property string heard: ""
    property int secondsLeft: 0
    readonly property var theme: Config.theme
    readonly property bool listening: state === "listening"
    readonly property bool working: state === "thinking" || state === "busy"
    readonly property bool failed: state === "unknown" || state === "error" || state === "unavailable"

    function show(newState, text) {
        state = newState;
        heard = text || "";
        hideTimer.stop();
        if (newState === "listening") {
            secondsLeft = (Config.voice.seconds || 4) + 4;  // the remote mic stops earlier, when you stop talking
            countdown.restart();
        } else if (newState !== "thinking" && newState !== "busy") {
            hideTimer.interval = newState === "message" && heard.length > 40 ? 5000 : 3000;
            hideTimer.restart();
        }
    }

    function hide() {
        state = "";
    }

    readonly property string message: {
        switch (state) {
        case "listening": return "Listening…";
        case "thinking": return "One moment…";
        case "heard": return "“" + heard + "”";
        case "unknown": return heard ? "“" + heard + "”" : "Didn't hear anything";
        case "unavailable": return "Voice control works in Bigscreen";
        case "error": return "Voice control failed";
        case "busy": return heard;      // e.g. "Starting…" while a Jellyfin video loads (stays until hidden)
        case "message": return heard;   // e.g. "Nothing called X on Jellyfin" (hides by itself)
        }
        return "";
    }
    readonly property string hint: {
        switch (state) {
        case "listening": return "Try “play Merlin”, “open YouTube” or “louder”";
        case "thinking": return "Working out what you meant";
        case "unknown": return heard ? "Didn't catch that — press the mic and try again" : "Hold the remote close and try again";
        case "error": return "Check the remote's connection";
        }
        return "";
    }

    visible: opacity > 0
    opacity: state ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: overlay.theme.animationMs * 2 } }
    width: card.width
    height: card.height
    scale: state ? 1 : 0.92
    Behavior on scale { NumberAnimation { duration: overlay.theme.animationMs * 2; easing.type: Easing.OutBack } }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (--overlay.secondsLeft > 0)
                return;
            stop();
            if (overlay.state === "listening")
                overlay.state = "thinking";
        }
    }

    Timer {
        id: hideTimer
        interval: 3000
        onTriggered: overlay.state = ""
    }

    MultiEffect {
        anchors.fill: card
        source: card
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.6
        shadowBlur: 1.0
        shadowVerticalOffset: Config.px(8)
    }

    Rectangle {
        id: card
        width: Math.min(Config.px(1100), content.implicitWidth + Config.px(64))
        height: Config.px(116)
        radius: height / 2
        color: Qt.rgba(0.11, 0.12, 0.15, 0.94)
        border.width: Config.px(2)
        border.color: overlay.listening ? Config.withAlpha(overlay.theme.colors.accent, 0.8)
                                        : Config.withAlpha(overlay.theme.colors.text, 0.12)
        Behavior on border.color { ColorAnimation { duration: overlay.theme.animationMs * 2 } }
        Behavior on width { NumberAnimation { duration: overlay.theme.animationMs * 2; easing.type: Easing.OutCubic } }

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            x: Config.px(22)
            spacing: Config.px(24)

            // Mic badge: accent circle with a glow ring that breathes while listening, a spinner while thinking.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(76)
                height: width

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: overlay.theme.colors.accent
                    opacity: overlay.listening ? 0.3 : 0
                    SequentialAnimation on scale {
                        running: overlay.listening
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 1.35; duration: 800; easing.type: Easing.OutQuad }
                        NumberAnimation { from: 1.35; to: 1; duration: 800; easing.type: Easing.InQuad }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.86
                    height: width
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: overlay.failed ? "#e8716b" : Qt.lighter(overlay.theme.colors.accent, 1.15)
                        }
                        GradientStop {
                            position: 1
                            color: overlay.failed ? "#b3403a" : Qt.darker(overlay.theme.colors.accent, 1.5)
                        }
                    }
                }
                // Microphone: capsule, stand arc, foot.
                Canvas {
                    id: mic
                    anchors.centerIn: parent
                    width: parent.width * 0.5
                    height: width
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        const w = width, h = height;
                        ctx.reset();
                        ctx.strokeStyle = ctx.fillStyle = "#14161a";
                        ctx.lineWidth = w * 0.09;
                        ctx.lineCap = "round";
                        const cw = w * 0.34, cx = w / 2, top = h * 0.04, bottom = h * 0.58;
                        ctx.beginPath();
                        ctx.arc(cx, top + cw / 2, cw / 2, Math.PI, 0);
                        ctx.lineTo(cx + cw / 2, bottom - cw / 2);
                        ctx.arc(cx, bottom - cw / 2, cw / 2, 0, Math.PI);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(cx, h * 0.42, w * 0.3, 0.15 * Math.PI, 0.85 * Math.PI);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(cx, h * 0.73);
                        ctx.lineTo(cx, h * 0.9);
                        ctx.moveTo(cx - w * 0.16, h * 0.92);
                        ctx.lineTo(cx + w * 0.16, h * 0.92);
                        ctx.stroke();
                    }
                }
                // Spinner ring while thinking / busy.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 1.04
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Config.px(3)
                    border.color: Config.withAlpha(overlay.theme.colors.accent, 0.25)
                    visible: overlay.working
                    Rectangle {
                        width: Config.px(12)
                        height: width
                        radius: width / 2
                        color: overlay.theme.colors.accent
                        x: parent.width / 2 - width / 2
                        y: -height / 2 + Config.px(1)
                    }
                    RotationAnimation on rotation {
                        running: overlay.working
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1100
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Config.px(4)
                Text {
                    width: Math.min(implicitWidth, Config.px(820))
                    elide: Text.ElideRight
                    text: overlay.message
                    color: overlay.theme.colors.text
                    font.family: overlay.theme.font.family
                    font.pixelSize: Config.px(34)
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: text !== ""
                    width: Math.min(implicitWidth, Config.px(820))
                    elide: Text.ElideRight
                    text: overlay.hint
                    color: overlay.theme.colors.textDim
                    font.family: overlay.theme.font.family
                    font.pixelSize: Config.px(21)
                }
            }

            // Sound bars while listening.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Config.px(6)
                visible: overlay.listening
                width: visible ? implicitWidth : 0
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.px(7)
                        radius: width / 2
                        color: overlay.theme.colors.accent
                        height: Config.px(14)
                        SequentialAnimation on height {
                            running: overlay.listening
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 90 }
                            NumberAnimation { to: Config.px(44 - Math.abs(2 - index) * 8); duration: 260; easing.type: Easing.OutQuad }
                            NumberAnimation { to: Config.px(12); duration: 300; easing.type: Easing.InQuad }
                            PauseAnimation { duration: (4 - index) * 90 }
                        }
                    }
                }
            }
        }
    }
}
