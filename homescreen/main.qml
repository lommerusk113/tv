import QtQuick
import QtQuick.Window
import "."

// Prototype window. Bigscreen uses TvHome directly (see bigscreen/HomeScreen.qml).
Window {
    width: 1920
    height: 1080
    minimumWidth: 1920
    maximumWidth: 1920
    minimumHeight: 1080
    maximumHeight: 1080
    visible: true
    title: "TV Home Screen (prototype)"
    color: "#000000"

    TvHome {
        anchors.fill: parent
        focus: true
    }
}
