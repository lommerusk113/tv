import QtQuick
import QtQuick.Window
import "."

// Full-bleed featured banner. Left/Right switches between featured items.
Item {
    id: hero
    property var section: null
    property bool focused: false
    property int current: 0
    readonly property bool isRow: false
    readonly property var theme: Config.theme
    readonly property var items: section ? section.items : []
    readonly property var entry: items.length ? items[Math.min(current, items.length - 1)] : null

    implicitHeight: Config.px(theme.hero.height)
    // The backdrop is shown whole (16:9 across the full width), so it reaches below the banner: the rows after it
    // (your apps) sit on its lower part, like Google TV.
    readonly property real backdropHeight: width * 9 / 16

    function move(d) {
        const n = current + d;
        if (n >= 0 && n < items.length)
            current = n;
        rotate.restart(); // a full interval on the title just picked
    }

    // Like Google TV, the banner moves on to the next title by itself (back to the first after the last);
    // only while the home screen is in front.
    Timer {
        id: rotate
        interval: hero.theme.hero.rotateMs || 8000
        running: hero.items.length > 1 && hero.Window.active
        repeat: true
        onTriggered: hero.current = (hero.current + 1) % hero.items.length
    }

    // "Watch now": the entry's action (Jellyfin banner items play), else only logged.
    function activate() {
        if (!entry)
            return;
        console.log("open:" + entry.id);
        if (entry.action)
            Config.run(entry.action);
    }

    // Backdrops, one per item, cross-fading: the item's image (Jellyfin/TMDb) over a generated gradient.
    Item {
        id: backdrop
        width: parent.width
        height: hero.backdropHeight
        z: -1

        Repeater {
            model: hero.items

            delegate: Item {
                required property var modelData
                required property int index
                anchors.fill: parent
                opacity: index === hero.current ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: hero.theme.animationMs * 3 } }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: modelData.colors[0] }
                        GradientStop { position: 1; color: modelData.colors[1] }
                    }
                }
                Rectangle {
                    width: hero.width * 0.5
                    height: width
                    radius: width / 2
                    x: hero.width * 0.55
                    y: -height * 0.4
                    color: modelData.colors[2]
                    opacity: 0.35
                }
                Rectangle {
                    width: hero.width * 0.28
                    height: width
                    radius: width / 2
                    x: hero.width * 0.8
                    y: backdrop.height * 0.4
                    color: modelData.colors[2]
                    opacity: 0.2
                }
                Image {
                    anchors.fill: parent
                    source: modelData.image ? Qt.resolvedUrl(modelData.image) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
        }

        // Scrims so the text stays readable and the picture fades into the page at its bottom edge.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Config.withAlpha(hero.theme.colors.background, 0.9) }
                GradientStop { position: 0.5; color: Config.withAlpha(hero.theme.colors.background, 0.45) }
                GradientStop { position: 1; color: Config.withAlpha(hero.theme.colors.background, 0) }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.3
            gradient: Gradient {
                GradientStop { position: 0; color: Config.withAlpha(hero.theme.colors.background, 0) }
                GradientStop { position: 1; color: hero.theme.colors.background }
            }
        }
    }

    Column {
        x: Config.px(hero.theme.spacing.page)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(56)
        width: hero.width * 0.45
        spacing: Config.px(14)

        Text {
            text: hero.entry ? hero.entry.meta : ""
            color: hero.theme.colors.accent
            font.family: hero.theme.font.family
            font.pixelSize: Config.px(hero.theme.font.sizes.heroMeta)
            font.weight: Font.DemiBold
        }
        // Title logo (fanart.tv) when the item has one, otherwise the title as text.
        Image {
            id: logo
            width: parent.width * 0.8
            height: visible ? Config.px(150) : 0
            source: hero.entry && hero.entry.logo ? Qt.resolvedUrl(hero.entry.logo) : ""
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            visible: !logo.visible
            width: parent.width
            text: hero.entry ? hero.entry.title : ""
            color: hero.theme.colors.text
            wrapMode: Text.WordWrap
            font.family: hero.theme.font.family
            font.pixelSize: Config.px(hero.theme.font.sizes.heroTitle)
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            text: hero.entry ? hero.entry.description : ""
            color: hero.theme.colors.text
            opacity: 0.85
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: hero.theme.font.family
            font.pixelSize: Config.px(hero.theme.font.sizes.heroBody)
        }
        Item {
            width: 1
            height: Config.px(6)
        }
        Row {
            spacing: Config.px(28)

            Rectangle {
                id: watchButton
                height: Config.px(56)
                width: watchLabel.implicitWidth + Config.px(56)
                radius: height / 2
                color: hero.focused ? hero.theme.colors.focusBorder : Config.withAlpha(hero.theme.colors.text, 0.15)
                scale: hero.focused ? hero.theme.focus.scale : 1
                transformOrigin: Item.Left
                Behavior on scale { NumberAnimation { duration: hero.theme.animationMs; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: hero.theme.animationMs } }

                Text {
                    id: watchLabel
                    anchors.centerIn: parent
                    text: "▶  Watch now"
                    color: hero.focused ? hero.theme.colors.onFocused : hero.theme.colors.text
                    font.family: hero.theme.font.family
                    font.pixelSize: Config.px(hero.theme.font.sizes.button)
                    font.weight: Font.DemiBold
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Config.px(10)

                Repeater {
                    model: hero.items.length

                    delegate: Rectangle {
                        required property int index
                        width: index === hero.current ? Config.px(28) : Config.px(10)
                        height: Config.px(10)
                        radius: height / 2
                        color: index === hero.current ? hero.theme.colors.text : Config.withAlpha(hero.theme.colors.text, 0.35)
                        Behavior on width { NumberAnimation { duration: hero.theme.animationMs } }
                    }
                }
            }
        }
    }
}
