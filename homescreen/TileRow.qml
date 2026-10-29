import QtQuick
import QtQuick.Effects
import "."

// A titled horizontal row of tiles. Scrolls horizontally to keep the focused tile visible.
Item {
    id: row
    property var section: null
    property bool focused: false
    property int current: 0
    property bool moving: false   // app row: the focused tile is being moved (left/right), see Home.qml
    readonly property bool isRow: true
    readonly property var theme: Config.theme
    readonly property var items: section ? section.items : []
    readonly property string style: section ? section.style : "landscape"
    readonly property int glowPad: Config.px(32)   // room for the focus scale and glow

    implicitHeight: list.y + list.height - glowPad / 2

    // Where the horizontal scroll is (or is heading): for the fade of passed tiles and the scroll arrows.
    readonly property real scrollX: hScroll.running ? hScroll.to : list.contentX
    readonly property bool moreLeft: scrollX > -list.leftMargin + 1
    readonly property bool moreRight: scrollX + list.width < list.contentWidth + list.rightMargin - 1

    // Round chevron in the page margin: shown when tiles are hidden that way (right: only on the focused row, where
    // the peeking tile alone is easy to miss). Dimmed on rows without focus.
    component ScrollArrow: Rectangle {
        id: arrow
        property bool show
        property bool pointsLeft
        width: Config.px(52)
        height: width
        radius: width / 2
        y: list.y + row.glowPad + Config.px(row.theme.tiles[row.style][1]) / 2 - height / 2
        color: Config.withAlpha(row.theme.colors.surface, 0.9)
        border.width: Config.px(1)
        border.color: Config.withAlpha(row.theme.colors.text, 0.15)
        opacity: show ? (row.focused ? 1 : 0.55) : 0
        visible: opacity > 0
        z: 2
        Behavior on opacity { NumberAnimation { duration: row.theme.animationMs * 2 } }
        Image {
            id: chevron
            anchors.centerIn: parent
            width: Config.px(26)
            height: width
            source: Qt.resolvedUrl("icons/settings/next.svg")
            sourceSize: Qt.size(width * 2, height * 2)
            rotation: arrow.pointsLeft ? 180 : 0
            visible: false
        }
        MultiEffect {
            anchors.fill: chevron
            source: chevron
            rotation: chevron.rotation
            colorization: 1
            colorizationColor: row.theme.colors.text
            brightness: 1
        }
    }

    ScrollArrow {
        x: (list.leftMargin - width) / 2
        show: row.moreLeft
        pointsLeft: true
    }
    ScrollArrow {
        x: row.width - list.rightMargin / 2 - width / 2
        show: row.moreRight && row.focused
    }

    // Move mode: swap the focused tile with its neighbour (the items array is changed in place: it is Config.apps).
    function swap(d) {
        const n = current + d;
        if (n < 0 || n >= items.length)
            return;
        const tmp = items[current];
        items[current] = items[n];
        items[n] = tmp;
        list.model = Qt.binding(() => row.items);  // same array object: force the ListView to re-read it
        current = n;
        ensureVisible();
    }

    function move(d) {
        const n = current + d;
        if (n >= 0 && n < items.length)
            current = n;
    }

    // App tiles launch their app; media items log open:<id> and run their "action" (Jellyfin: play the item), else
    // launch the "app" they name.
    function activate() {
        const item = items[current];
        if (section.action === "launch") {
            Config.launch(item.id);
            return;
        }
        console.log(section.action + ":" + item.id);
        if (item.action)
            Config.run(item.action);
        else if (item.app)
            Config.launch(item.app);
    }

    // Horizontal centre of the focused tile, in window coordinates.
    function focusCenterX() {
        const it = list.itemAtIndex(current);
        return it ? it.mapToItem(null, it.width / 2, 0).x : 0;
    }

    function focusNearest(x) {
        let best = current;
        let bestDist = Infinity;
        for (let i = 0; i < list.count; ++i) {
            const it = list.itemAtIndex(i);
            if (!it)
                continue;
            const dist = Math.abs(it.mapToItem(null, it.width / 2, 0).x - x);
            if (dist < bestDist) {
                bestDist = dist;
                best = i;
            }
        }
        current = best;
    }

    function ensureVisible() {
        const it = list.itemAtIndex(current);
        if (!it)
            return;
        // Like Google TV: the focused tile stays at the row's left edge (no half tiles on the left); only the end of
        // the row stops short, so the last tile ends at the right margin.
        const target = it.x - list.leftMargin;
        const minX = -list.leftMargin;
        const maxX = Math.max(minX, list.contentWidth + list.rightMargin - list.width);
        hScroll.stop();
        hScroll.to = Math.max(minX, Math.min(target, maxX));
        hScroll.start();
    }

    onCurrentChanged: ensureVisible()

    Text {
        id: title
        x: Config.px(row.theme.spacing.page)
        text: row.section ? row.section.title : ""
        color: row.focused ? row.theme.colors.text : row.theme.colors.textDim
        font.family: row.theme.font.family
        font.pixelSize: Config.px(row.theme.font.sizes.rowTitle)
        font.weight: Font.DemiBold
        Behavior on color { ColorAnimation { duration: row.theme.animationMs } }
    }

    ListView {
        id: list
        y: title.height + Config.px(row.theme.spacing.titleGap) - row.glowPad
        width: row.width
        height: Config.px(row.theme.tiles[row.style][1]) + row.glowPad * 2
        orientation: ListView.Horizontal
        interactive: false
        spacing: Config.px(row.theme.spacing.tile)
        leftMargin: Config.px(row.theme.spacing.page)
        rightMargin: leftMargin
        cacheBuffer: 10000
        model: row.items

        // The row tracks focus in row.current, not ListView.currentIndex, so ListView
        // doesn't jump-scroll on its own and the animation below stays in control.
        // Wrapper item because a horizontal ListView resets the delegate's y.
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: tile.width
            height: list.height
            z: tile.focused ? 1 : 0
            // Tiles scrolled past the left page margin fade out, so every row starts at the same edge (the next tile
            // still peeks in on the right). Measured against where the scroll ends, so it does not flicker meanwhile.
            opacity: cell.x < row.scrollX + list.leftMargin - 1 ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: row.theme.animationMs * 2 } }

            Tile {
                id: tile
                y: row.glowPad
                modelData: cell.modelData
                index: cell.index
                style: row.style
                focused: row.focused && cell.index === row.current
            }

            // Move mode: arrows beside the tile being moved, "Moving" under it.
            Repeater {
                model: row.moving && tile.focused ? [-1, 1] : []
                delegate: Rectangle {
                    required property int modelData
                    x: modelData < 0 ? -width / 2 - Config.px(6) : tile.width - width / 2 + Config.px(6)
                    y: row.glowPad + tile.height / 2 - height / 2
                    z: 2
                    width: Config.px(44)
                    height: width
                    radius: width / 2
                    color: row.theme.colors.accent
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData < 0 ? "‹" : "›"
                        color: row.theme.colors.onFocused
                        font.pixelSize: Config.px(34)
                        font.weight: Font.Bold
                    }
                }
            }
        }

        NumberAnimation {
            id: hScroll
            target: list
            property: "contentX"
            duration: row.theme.animationMs * 2
            easing.type: Easing.OutCubic
        }
    }
}
