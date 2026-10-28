import QtQuick
import "."

// Settings slide-in from the right (Settings tile, the remote's gear button, voice "open settings").
// Home routes keys here while it is open: up/down pick, select runs, left/right change the volume, back closes.
// Actions go to Config.system (Bigscreen); the prototype only logs them. Power actions ask for a second OK.
Item {
    id: panel
    property bool open: false
    property int current: 0
    property string confirming: ""   // id of the entry waiting for its second OK
    property real volume: -1         // 0..1 from Config.volumeReader; -1 = unknown
    readonly property var theme: Config.theme

    readonly property var entries: [
        { id: "volume", label: "Volume", hint: "◀ ▶" },
        { id: "tv_off", label: "Turn off the TV" },
        { id: "system_settings", label: "Wi-Fi, Bluetooth and display" },
        { id: "sleep", label: "Sleep" },
        { id: "restart", label: "Restart", confirm: true },
        { id: "shutdown", label: "Shut down", confirm: true }
    ]

    function show() {
        current = 0;
        confirming = "";
        open = true;
        readVolume();
    }

    function close() {
        open = false;
        confirming = "";
    }

    function readVolume() {
        if (Config.volumeReader)
            Config.volumeReader(v => panel.volume = v);
    }

    function system(action) {
        if (!(Config.system && Config.system(action)))
            console.log("action:" + action);
    }

    // Returns true when the action was used (Home then does nothing else with it).
    function handle(action) {
        const entry = entries[current];
        switch (action) {
        case "up": current = Math.max(0, current - 1); confirming = ""; return true;
        case "down": current = Math.min(entries.length - 1, current + 1); confirming = ""; return true;
        case "back": close(); return true;
        case "left":
        case "right":
            if (entry.id === "volume") {
                system(action === "left" ? "volume_down" : "volume_up");
                volumeRefresh.restart();
            }
            return true;
        case "select":
            if (entry.id === "volume")
                return true;
            if (entry.confirm && confirming !== entry.id) {
                confirming = entry.id;
                return true;
            }
            close();
            system(entry.id);
            return true;
        case "settings": close(); return true;  // the gear again toggles
        }
        return false;  // home, volume keys, launch:... are handled by Home as usual
    }

    // wpctl needs a moment before the new volume can be read back.
    Timer {
        id: volumeRefresh
        interval: 150
        onTriggered: panel.readVolume()
    }

    visible: sheet.x < width
    anchors.fill: parent

    // Dims the home screen behind the sheet.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: panel.open ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: panel.theme.animationMs * 2 } }
    }

    Rectangle {
        id: sheet
        width: Config.px(640)
        height: parent.height
        x: panel.open ? parent.width - width : parent.width
        Behavior on x { NumberAnimation { duration: panel.theme.animationMs * 2; easing.type: Easing.OutCubic } }
        color: panel.theme.colors.surface

        Column {
            anchors.fill: parent
            anchors.margins: Config.px(56)
            spacing: Config.px(14)

            Text {
                text: "Settings"
                color: panel.theme.colors.text
                font.family: panel.theme.font.family
                font.pixelSize: Config.px(panel.theme.font.sizes.heroMeta * 2)
                font.weight: Font.Bold
                bottomPadding: Config.px(24)
            }

            Repeater {
                model: panel.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool focused: index === panel.current
                    readonly property bool asking: panel.confirming === modelData.id

                    width: parent.width
                    height: Config.px(modelData.id === "volume" ? 112 : 80)
                    radius: Config.px(16)
                    color: focused ? panel.theme.colors.focusBorder : "transparent"
                    Behavior on color { ColorAnimation { duration: panel.theme.animationMs } }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Config.px(28)
                        anchors.rightMargin: Config.px(28)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Config.px(10)

                        Item {
                            width: parent.width
                            height: label.height

                            Text {
                                id: label
                                text: row.asking ? "Press OK again to " + row.modelData.label.toLowerCase() : row.modelData.label
                                color: row.focused ? panel.theme.colors.onFocused : panel.theme.colors.text
                                font.family: panel.theme.font.family
                                font.pixelSize: Config.px(panel.theme.font.sizes.tab)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: label.verticalCenter
                                text: row.modelData.id === "volume" && panel.volume >= 0
                                      ? Math.round(panel.volume * 100) + " %" : (row.modelData.hint || "")
                                color: row.focused ? panel.theme.colors.onFocused : panel.theme.colors.textDim
                                font.family: panel.theme.font.family
                                font.pixelSize: Config.px(panel.theme.font.sizes.tileMeta)
                            }
                        }

                        // Volume bar
                        Rectangle {
                            visible: row.modelData.id === "volume"
                            width: parent.width
                            height: Config.px(8)
                            radius: height / 2
                            color: Config.withAlpha(row.focused ? panel.theme.colors.onFocused : panel.theme.colors.text, 0.2)

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, panel.volume))
                                height: parent.height
                                radius: height / 2
                                color: row.focused ? panel.theme.colors.onFocused : panel.theme.colors.accent
                                Behavior on width { NumberAnimation { duration: panel.theme.animationMs } }
                            }
                        }
                    }
                }
            }
        }
    }
}
