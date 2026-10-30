import QtQuick
import QtQuick.Effects
import "."

// One tile. style: "app" (name/logo), "landscape" (title, subtitle, progress), "poster" (title, meta).
Item {
    id: tile
    required property var modelData
    required property int index
    property string style: "landscape"
    property bool focused: false
    readonly property var theme: Config.theme
    readonly property var size: theme.tiles[style]
    readonly property var colors: modelData.colors || [modelData.color || theme.colors.surface, theme.colors.surface]

    width: Config.px(size[0])
    height: Config.px(size[1])
    z: focused ? 1 : 0
    scale: focused ? theme.focus.scale : 1
    Behavior on scale { NumberAnimation { duration: tile.theme.animationMs; easing.type: Easing.OutCubic } }

    // Soft glow: a blurred copy of the card shape behind it.
    Rectangle {
        id: glowShape
        anchors.fill: parent
        radius: card.radius
        color: tile.theme.colors.glow
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: glowShape
        source: glowShape
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        opacity: tile.focused ? tile.theme.focus.glowOpacity : 0
        Behavior on opacity { NumberAnimation { duration: tile.theme.animationMs } }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Config.px(tile.theme.radius)
        gradient: Gradient {
            GradientStop { position: 0; color: tile.colors[0] }
            GradientStop { position: 1; color: tile.colors[1] }
        }

        Rectangle {
            visible: tile.colors.length > 2
            anchors.fill: parent
            radius: parent.radius
            opacity: 0.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: tile.colors.length > 2 ? tile.colors[2] : "transparent" }
                GradientStop { position: 0.7; color: "transparent" }
            }
        }

        // App tiles: icon (optional) with the name below it. apps.json can set
        // imageScale (icon height / tile height) and showName: false for icons that contain the name.
        Column {
            visible: tile.style === "app"
            anchors.centerIn: parent
            spacing: Config.px(8)

            Image {
                visible: !!tile.modelData.image
                anchors.horizontalCenter: parent.horizontalCenter
                width: tile.width * 0.9
                height: visible ? tile.height * (tile.modelData.imageScale || 0.5) : 0
                fillMode: Image.PreserveAspectFit
                sourceSize.height: height * 2   // render SVGs sharp at the focused scale
                smooth: true
                source: tile.style === "app" && tile.modelData.image ? Qt.resolvedUrl(tile.modelData.image) : ""
            }
            Text {
                visible: !tile.modelData.image || tile.modelData.showName !== false
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.modelData.name || ""
                color: "#ffffff"
                font.family: tile.theme.font.family
                font.pixelSize: Config.px(tile.modelData.image ? tile.theme.font.sizes.tileTitle : tile.theme.font.sizes.appName)
                font.weight: tile.modelData.image ? Font.DemiBold : Font.Bold
            }
        }

        // App tiles: a small status pill in the corner (Config.appBadges, e.g. the game server's "● Steam running").
        Rectangle {
            readonly property string badge: tile.style === "app" ? Config.appBadges[tile.modelData.id] || "" : ""
            visible: badge !== ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Config.px(10)
            width: badgeText.implicitWidth + Config.px(20)
            height: Config.px(30)
            radius: height / 2
            color: badge.indexOf("●") === 0 ? "#2e7d32" : "#5f6368"
            z: 2
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: parent.badge
                color: "#ffffff"
                font.family: tile.theme.font.family
                font.pixelSize: Config.px(16)
                font.weight: Font.DemiBold
            }
        }

        // Media tiles: artwork (optional, e.g. TMDb backdrops from trakt.py), cropped to the rounded card.
        // The gradient above stays visible while it loads or when there is none.
        Image {
            id: art
            anchors.fill: parent
            visible: false
            source: tile.style !== "app" && tile.modelData.image ? Qt.resolvedUrl(tile.modelData.image) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: tile.width * tile.theme.focus.scale
        }
        Rectangle {
            id: artMask
            anchors.fill: parent
            radius: parent.radius
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: art
            visible: art.status === Image.Ready
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // Media tiles: scrim + text at the bottom.
        Rectangle {
            visible: tile.style !== "app"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.6
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: "#cc000000" }
            }
        }
        Column {
            visible: tile.style !== "app"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: progressTrack.visible ? progressTrack.top : parent.bottom
            anchors.margins: Config.px(16)
            spacing: Config.px(2)

            Text {
                width: parent.width
                text: tile.modelData.title || ""
                color: "#ffffff"
                elide: Text.ElideRight
                wrapMode: tile.style === "poster" ? Text.WordWrap : Text.NoWrap
                maximumLineCount: 2
                font.family: tile.theme.font.family
                font.pixelSize: Config.px(tile.theme.font.sizes.tileTitle)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: tile.modelData.subtitle || tile.modelData.meta || ""
                color: "#ffffff"
                opacity: 0.75
                elide: Text.ElideRight
                font.family: tile.theme.font.family
                font.pixelSize: Config.px(tile.theme.font.sizes.tileMeta)
            }
        }
        Rectangle {
            id: progressTrack
            visible: tile.modelData.progress !== undefined
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Config.px(16)
            height: Config.px(5)
            radius: height / 2
            color: "#55ffffff"

            Rectangle {
                width: parent.width * (tile.modelData.progress || 0)
                height: parent.height
                radius: parent.radius
                color: tile.theme.colors.accent
            }
        }

        // Focus outline.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: Config.px(tile.theme.focus.borderWidth)
            border.color: tile.theme.colors.focusBorder
            opacity: tile.focused ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: tile.theme.animationMs } }
        }
    }
}
