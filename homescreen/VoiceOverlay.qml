import QtQuick
import "."

// Voice feedback pill: listening (with countdown) -> thinking -> what was heard, or why nothing happened.
// show(state, text); hides itself after the result states.
Rectangle {
    id: overlay
    property string state: ""
    property string heard: ""
    property int secondsLeft: 0
    readonly property var theme: Config.theme
    readonly property bool listening: state === "listening"

    function show(newState, text) {
        state = newState;
        heard = text || "";
        hideTimer.stop();
        if (newState === "listening") {
            secondsLeft = Config.voice.seconds || 4;
            countdown.restart();
        } else if (newState !== "thinking") {
            hideTimer.restart();
        }
    }

    readonly property string message: {
        switch (state) {
        case "listening": return "Listening… " + secondsLeft;
        case "thinking": return "Recognizing…";
        case "heard": return "“" + heard + "”";
        case "unknown": return heard ? "Didn't understand “" + heard + "”" : "Didn't hear anything";
        case "unavailable": return "Voice control works in Bigscreen";
        case "error": return "Voice control failed";
        }
        return "";
    }

    visible: opacity > 0
    opacity: state ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: overlay.theme.animationMs * 2 } }
    width: row.implicitWidth + Config.px(56)
    height: Config.px(76)
    radius: height / 2
    color: Config.withAlpha(theme.colors.surface, 0.96)
    border.width: Config.px(2)
    border.color: listening ? theme.colors.accent : Config.withAlpha(theme.colors.text, 0.15)

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
        interval: 2500
        onTriggered: overlay.state = ""
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.px(18)

        // Mic dot: pulses while listening.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Config.px(36)
            height: width

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: overlay.theme.colors.accent
                opacity: 0.35
                scale: 1
                SequentialAnimation on scale {
                    running: overlay.listening
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 1.5; duration: 700; easing.type: Easing.OutQuad }
                    NumberAnimation { from: 1.5; to: 1; duration: 700; easing.type: Easing.InQuad }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: width
                radius: width / 2
                color: overlay.listening ? overlay.theme.colors.accent : overlay.theme.colors.textDim
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: overlay.message
            color: overlay.theme.colors.text
            font.family: overlay.theme.font.family
            font.pixelSize: Config.px(overlay.theme.font.sizes.tab)
        }
    }
}
