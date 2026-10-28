import QtQuick
import "."

// The whole home screen. All keyboard navigation lives here: the sections
// (hero + rows) only expose move()/activate()/current.
FocusScope {
    id: home
    focus: true

    readonly property var theme: Config.theme
    readonly property var sections: buildSections()
    property int section: 0       // -1 = tabs in the top bar, otherwise index into sections
    property int currentTab: 0

    function buildSections() {
        const out = [];
        for (const r of Config.layout.rows) {
            // "source" is a content key, or a list of them: the first with items wins (Jellyfin, else Trakt/placeholder).
            const sources = [].concat(r.source);
            const source = sources.find(k => k === "apps" || (Config.content[k] || []).length) || sources[0];
            const items = source === "apps" ? Config.apps : (Config.content[source] || []);
            if (!items.length) {
                console.warn("layout: skipping row '" + r.id + "', no items in source '" + sources.join("', '") + "'");
                continue;
            }
            out.push({
                id: r.id,
                type: r.type || "row",
                title: r.title || "",
                style: r.style || "landscape",
                action: source === "apps" ? "launch" : "open",
                items: items
            });
        }
        return out;
    }

    function sectionAt(i) {
        const loader = sectionRepeater.itemAt(i);
        return loader ? loader.item : null;
    }

    function moveHorizontal(d) {
        if (section < 0) {
            currentTab = Math.max(0, Math.min(Config.layout.tabs.length - 1, currentTab + d));
            return;
        }
        sectionAt(section).move(d);
    }

    function moveVertical(d) {
        const next = section + d;
        if (next < -1 || next >= sections.length)
            return;
        const from = section >= 0 ? sectionAt(section) : null;
        const to = next >= 0 ? sectionAt(next) : null;
        // Row to row: land on the tile closest to the one we leave, like Google TV.
        if (from && to && from.isRow && to.isRow)
            to.focusNearest(from.focusCenterX());
        section = next;
        scrollToSection();
    }

    function activate() {
        if (section < 0) {
            console.log("tab:" + Config.layout.tabs[currentTab]);
            return;
        }
        sectionAt(section).activate();
    }

    function back() {
        if (section >= 0 && sectionAt(section).current > 0) {
            sectionAt(section).current = 0;
            return;
        }
        if (section >= 0) {
            section = -1;
            scrollToSection();
            return;
        }
        console.log("back:root");
    }

    // Like Google TV: the focused row sits right below the top bar (no half-hidden row above it), unless it fits on
    // the first screen (hero and apps), which then stays at the top. fromTop is kept for callers; the position no
    // longer depends on the previous one.
    function scrollToSection(fromTop) {
        let target = 0;
        if (section > 0) {
            const it = sectionRepeater.itemAt(section);
            const top = column.y + it.y - Config.px(theme.topBar.height);
            const bottom = column.y + it.y + it.height + Config.px(theme.spacing.row);
            target = bottom <= page.height ? 0 : top;
        }
        target = Math.max(0, Math.min(target, page.contentHeight - page.height));
        vScroll.stop();
        vScroll.to = target;
        vScroll.start();
    }

    // Back to the start state: every row at its first tile, focus on layout.initialFocus.
    function goHome() {
        for (let i = 0; i < sections.length; i++)
            sectionAt(i).current = 0;
        currentTab = 0;
        const initial = sections.findIndex(s => s.id === Config.layout.initialFocus);
        section = initial >= 0 ? initial : 0;
        scrollToSection(true);
    }

    // Qt key code -> action, built from config/keymap.json (keys are Qt.Key_<name> names, or "evdev:<code>" for
    // remote buttons that have no Qt key, e.g. the Strong remote's YouTube button is evdev:588).
    readonly property var keyActions: {
        const out = {};
        for (const name in Config.keymap) {
            if (name.startsWith("evdev:")) {
                out[name] = Config.keymap[name];
                continue;
            }
            const code = Qt["Key_" + name];
            if (code === undefined)
                console.warn("keymap: unknown key '" + name + "'");
            else
                out[code] = Config.keymap[name];
        }
        return out;
    }

    function runAction(action) {
        switch (action) {
        case "left": moveHorizontal(-1); return;
        case "right": moveHorizontal(1); return;
        case "up": moveVertical(-1); return;
        case "down": moveVertical(1); return;
        case "select": activate(); return;
        case "back": back(); return;
        case "home": goHome(); return;
        }
        if (action === "voice")
            startVoice();
        else if (action.startsWith("launch:"))
            Config.launch(action.slice(7));
        else if (!(Config.system && Config.system(action)))
            console.log("action:" + action); // the prototype has no system hook: volume etc. are only logged
    }

    // Push-to-talk: record config/voice.json "seconds", transcribe (voice.py, Bigscreen only), run the action it maps to.
    function startVoice() {
        if (voiceOverlay.state === "listening" || voiceOverlay.state === "thinking")
            return;
        if (!Config.voiceListener) {
            console.log("action:voice (voice control needs Bigscreen)");
            voiceOverlay.show("unavailable", "");
            return;
        }
        voiceOverlay.show("listening", "");
        Config.voiceListener(result => {
            if (!result) {
                voiceOverlay.show("error", "");
                return;
            }
            console.log("voice: \"" + result.text + "\" -> " + result.action);
            voiceOverlay.show(result.action ? "heard" : "unknown", result.text);
            if (result.action)
                runAction(result.action);
        });
    }

    Keys.onPressed: event => {
        let action = event.key ? keyActions[event.key] : undefined;
        // On Linux the native scan code is the evdev code + 8.
        if (action === undefined && event.nativeScanCode > 8)
            action = keyActions["evdev:" + (event.nativeScanCode - 8)];
        if (action === undefined)
            return;
        runAction(action);
        event.accepted = true;
    }

    Component.onCompleted: {
        Config.actionRunner = runAction;
        Qt.callLater(goHome);
    }

    Rectangle {
        anchors.fill: parent
        color: home.theme.colors.background
    }

    Flickable {
        id: page
        anchors.fill: parent
        interactive: false
        contentWidth: width
        // Room below the last row, so it too can scroll up to just below the top bar.
        contentHeight: {
            const last = sectionRepeater.count ? sectionRepeater.itemAt(sectionRepeater.count - 1) : null;
            const tail = last ? height - Config.px(home.theme.topBar.height) - last.height : 0;
            return column.height + Math.max(Config.px(home.theme.spacing.page) / 2, tail);
        }

        NumberAnimation {
            id: vScroll
            target: page
            property: "contentY"
            duration: home.theme.animationMs * 2
            easing.type: Easing.OutCubic
        }

        Column {
            id: column
            width: page.width
            topPadding: home.sections.length && home.sections[0].type === "hero" ? 0 : Config.px(home.theme.topBar.height)
            spacing: Config.px(home.theme.spacing.row)

            Repeater {
                id: sectionRepeater
                model: home.sections

                delegate: Loader {
                    id: sec
                    required property var modelData
                    required property int index
                    width: column.width
                    sourceComponent: modelData.type === "hero" ? heroComponent : rowComponent

                    Component {
                        id: heroComponent
                        HeroBanner {
                            section: sec.modelData
                            focused: home.section === sec.index
                        }
                    }
                    Component {
                        id: rowComponent
                        TileRow {
                            section: sec.modelData
                            focused: home.section === sec.index
                        }
                    }
                }
            }
        }
    }

    // Top bar: profile, tabs, clock. Stays in place while the page scrolls.
    Item {
        id: topBar
        width: parent.width
        height: Config.px(home.theme.topBar.height)

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Config.withAlpha(home.theme.colors.background, 0.95) }
                GradientStop { position: 0.7; color: Config.withAlpha(home.theme.colors.background, 0.6) }
                GradientStop { position: 1; color: Config.withAlpha(home.theme.colors.background, 0) }
            }
        }
        // Becomes solid once the page scrolls, so rows don't show through the tabs.
        Rectangle {
            anchors.fill: parent
            color: home.theme.colors.background
            opacity: Math.min(1, page.contentY / Config.px(80))
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Config.px(home.theme.spacing.page)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(24)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(52)
                height: width
                radius: width / 2
                color: Config.layout.profile.color

                Text {
                    anchors.centerIn: parent
                    text: Config.layout.profile.initial
                    color: "#ffffff"
                    font.family: home.theme.font.family
                    font.pixelSize: Config.px(home.theme.font.sizes.profile)
                    font.weight: Font.DemiBold
                }
            }

            Item {
                width: Config.px(12)
                height: 1
            }

            Repeater {
                model: Config.layout.tabs

                delegate: Rectangle {
                    id: tab
                    required property string modelData
                    required property int index
                    readonly property bool selected: index === home.currentTab
                    readonly property bool focused: selected && home.section === -1

                    anchors.verticalCenter: parent.verticalCenter
                    height: Config.px(52)
                    width: label.implicitWidth + Config.px(44)
                    radius: height / 2
                    color: focused ? home.theme.colors.focusBorder : "transparent"
                    scale: focused ? home.theme.focus.scale : 1
                    Behavior on scale { NumberAnimation { duration: home.theme.animationMs; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: home.theme.animationMs } }

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: tab.modelData
                        color: tab.focused ? home.theme.colors.onFocused
                                           : (tab.selected ? home.theme.colors.text : home.theme.colors.textDim)
                        font.family: home.theme.font.family
                        font.pixelSize: Config.px(home.theme.font.sizes.tab)
                        font.weight: tab.selected ? Font.DemiBold : Font.Normal
                    }

                    Rectangle {
                        visible: tab.selected && !tab.focused
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: label.width
                        height: Config.px(3)
                        radius: height / 2
                        color: home.theme.colors.accent
                    }
                }
            }
        }

        Text {
            id: clock
            property date now: new Date()
            anchors.right: parent.right
            anchors.rightMargin: Config.px(home.theme.spacing.page)
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(now, "HH:mm")
            color: home.theme.colors.text
            font.family: home.theme.font.family
            font.pixelSize: Config.px(home.theme.font.sizes.clock)

            Timer {
                interval: 5000
                running: true
                repeat: true
                onTriggered: clock.now = new Date()
            }
        }

        // Weather (MET Norway / Yr, from weather.py) left of the clock; hidden until there is data.
        Row {
            visible: !!Config.weather
            anchors.right: clock.left
            anchors.rightMargin: Config.px(28)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Config.px(10)

            Image {
                visible: status === Image.Ready
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(44)
                height: width
                sourceSize: Qt.size(width * 2, height * 2)
                source: Config.weather && Config.weather.icon ? Config.weather.icon : ""
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.weather ? Config.weather.temperature + "°" : ""
                color: home.theme.colors.text
                font.family: home.theme.font.family
                font.pixelSize: Config.px(home.theme.font.sizes.clock)
            }
        }
    }

    VoiceOverlay {
        id: voiceOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(72)
    }
}
