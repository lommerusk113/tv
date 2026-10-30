import QtQuick
import "."

// Behind the rows: the focused media tile's picture, dimmed, with its title, details and plot at the top left
// (Home.qml "showcase": rows below the apps). Uses the tile's "backdrop" (jellyfin.py, jellyseerr.py), or the tile
// picture itself on landscape rows (YouTube). Pictures cross-fade after a short pause, so scrolling along a row does
// not flicker through every one.
Item {
    id: showcase
    property var item: null
    property bool wide: false
    readonly property var theme: Config.theme
    readonly property string picture: item ? (item.backdrop || (wide ? item.image || "" : "")) : ""
    property var shown: null   // the item whose text is on screen (follows `item` after the pause)
    property int front: 0      // which of the two pictures is in front

    visible: opacity > 0
    opacity: item ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: showcase.theme.animationMs * 3 } }

    onItemChanged: settle.restart()
    Timer {
        id: settle
        interval: 220
        onTriggered: {
            showcase.shown = showcase.item;
            const back = showcase.front === 0 ? pic1 : pic0;
            if (back.source.toString() === showcase.picture && back.status === Image.Ready)
                showcase.front = showcase.front === 0 ? 1 : 0;
            else
                back.source = showcase.picture;
        }
    }

    component Picture: Image {
        required property int slot
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        opacity: showcase.front === slot && source.toString() !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: showcase.theme.animationMs * 4 } }
        onStatusChanged: if (status === Image.Ready && source.toString() === showcase.picture) showcase.front = slot
    }
    Picture { id: pic0; slot: 0 }
    Picture { id: pic1; slot: 1 }

    // Dark from the left (for the text) and towards the bottom (for the rows), like Google TV.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Config.withAlpha(showcase.theme.colors.background, 0.92) }
            GradientStop { position: 0.45; color: Config.withAlpha(showcase.theme.colors.background, 0.55) }
            GradientStop { position: 1.0; color: Config.withAlpha(showcase.theme.colors.background, 0.15) }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Config.withAlpha(showcase.theme.colors.background, 0.25) }
            GradientStop { position: 0.38; color: Config.withAlpha(showcase.theme.colors.background, 0.35) }
            GradientStop { position: 0.62; color: Config.withAlpha(showcase.theme.colors.background, 0.92) }
            GradientStop { position: 1.0; color: showcase.theme.colors.background }
        }
    }

    Column {
        id: details
        x: Config.px(showcase.theme.spacing.page)
        y: Config.px(96)
        width: Config.px(1000)
        spacing: Config.px(12)
        // by id: the rows hand out copies of their items, so the same tile is not always the same object
        opacity: showcase.shown && showcase.item && showcase.shown.id === showcase.item.id ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: showcase.theme.animationMs * 2 } }

        Text {
            width: parent.width
            text: showcase.shown ? showcase.shown.title || "" : ""
            elide: Text.ElideRight
            color: showcase.theme.colors.text
            font.family: showcase.theme.font.family
            font.pixelSize: Config.px(56)
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: showcase.shown ? showcase.shown.subtitle || showcase.shown.meta || "" : ""
            elide: Text.ElideRight
            color: showcase.theme.colors.accent
            font.family: showcase.theme.font.family
            font.pixelSize: Config.px(24)
            font.weight: Font.DemiBold
        }
        Text {
            width: Config.px(900)
            visible: text !== ""
            text: showcase.shown ? showcase.shown.overview || showcase.shown.description || "" : ""
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Config.withAlpha(showcase.theme.colors.text, 0.85)
            font.family: showcase.theme.font.family
            font.pixelSize: Config.px(22)
            lineHeight: 1.2
        }
    }
}
