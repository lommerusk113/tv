import QtQuick
import "."

// The whole home screen. All keyboard navigation lives here: the sections
// (hero + rows) only expose move()/activate()/current.
FocusScope {
    id: home
    focus: true

    readonly property var theme: Config.theme
    readonly property var sections: buildSections()
    property int section: 0       // index into sections
    // Where the home screen starts (layout.initialFocus) and where Back returns to.
    readonly property int initialSection: Math.max(0, sections.findIndex(s => s.id === Config.layout.initialFocus))
    // True when Back has nothing left to do: settings closed, on the start row at its first tile (Bigscreen then opens
    // its overlay).
    readonly property bool atRoot: {
        const loader = sectionRepeater.count > section ? sectionRepeater.itemAt(section) : null;
        return !settingsPanel.open && section === initialSection
                && (!loader || !loader.item || loader.item.current === 0);
    }

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
        sectionAt(section).move(d);
    }

    function moveVertical(d) {
        const next = section + d;
        if (next < 0 || next >= sections.length)
            return;
        const from = sectionAt(section);
        const to = sectionAt(next);
        // Row to row: land on the tile closest to the one we leave, like Google TV.
        if (from && to && from.isRow && to.isRow)
            to.focusNearest(from.focusCenterX());
        section = next;
        scrollToSection();
    }

    function activate() {
        sectionAt(section).activate();
    }

    // Back: first tile of the row, then the start row, then (atRoot) nothing left; Bigscreen takes over.
    function back() {
        if (sectionAt(section).current > 0) {
            sectionAt(section).current = 0;
            return;
        }
        if (section !== initialSection) {
            section = initialSection;
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
        section = initialSection;
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
        if (settingsPanel.open && settingsPanel.handle(action))
            return;
        if (action === "settings") {
            settingsPanel.show();
            return;
        }
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

    // Status pill at the bottom ("Starting…"); an empty text hides it.
    function showStatus(text) {
        if (text)
            voiceOverlay.show("busy", text);
        else if (voiceOverlay.state === "busy")
            voiceOverlay.hide();
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
            topPadding: home.sections.length && home.sections[0].type === "hero" ? 0 : Config.px(home.theme.spacing.page) / 2
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

    // Clock and weather in the top-right corner of the banner; they fade out as the page scrolls.
    Item {
        id: topBar
        width: parent.width
        height: Config.px(home.theme.topBar.height)
        opacity: Math.max(0, 1 - page.contentY / Config.px(80))
        visible: opacity > 0

        // Dark pill so the time stays readable on bright banner pictures: [weather] time over date.
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: Config.px(home.theme.spacing.page) - Config.px(24)
            anchors.top: parent.top
            anchors.topMargin: Config.px(28)
            width: corner.implicitWidth + Config.px(48)
            height: corner.implicitHeight + Config.px(24)
            radius: Config.px(22)
            color: Config.withAlpha("#000000", 0.45)

            Row {
                id: corner
                anchors.centerIn: parent
                spacing: Config.px(24)

                // Weather (MET Norway / Yr, from weather.py); hidden until there is data.
                Row {
                    visible: !!Config.weather
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Config.px(10)

                    Image {
                        visible: status === Image.Ready
                        anchors.verticalCenter: parent.verticalCenter
                        width: Config.px(52)
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
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    id: clock
                    property date now: new Date()
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(clock.now, "HH:mm")
                        color: home.theme.colors.text
                        font.family: home.theme.font.family
                        font.pixelSize: Config.px(home.theme.font.sizes.clock)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.locale("en_GB").toString(clock.now, "dddd d MMMM")
                        color: home.theme.colors.text
                        opacity: 0.8
                        font.family: home.theme.font.family
                        font.pixelSize: Config.px(home.theme.font.sizes.clockDate)
                    }

                    Timer {
                        interval: 5000
                        running: true
                        repeat: true
                        onTriggered: clock.now = new Date()
                    }
                }
            }
        }
    }

    SettingsPanel {
        id: settingsPanel
    }

    VoiceOverlay {
        id: voiceOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(72)
    }
}
