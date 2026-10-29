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
        return !settingsPanel.open && !requestDialog.open && !choiceDialog.open && !getDialog.open && !loadingScreen.open && section === initialSection
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

    // Where focus is ({row id, item id, tile index}), so a rebuild of the rows (new live content) can put it back.
    function focusState() {
        const s = sections[section];
        const row = sectionAt(section);
        const at = row ? row.current : 0;
        return { id: s ? s.id : "", item: s && s.items[at] ? s.items[at].id : "", index: at };
    }

    // Back to that row and the same item (it may have moved), else the same position; the start if the row is gone.
    function restoreFocus(state) {
        const i = sections.findIndex(s => s.id === state.id);
        if (i < 0)
            return goHome();
        section = i;
        const items = sections[i].items;
        let at = items.findIndex(item => item.id === state.item);
        if (at < 0)
            at = Math.min(state.index, items.length - 1);
        const row = sectionAt(i);
        if (row)
            row.current = Math.max(0, at);
        scrollToSection();
    }

    // Home closes whatever window is open on the home screen (request, "Did you mean", "Not on your server", settings).
    function closeWindows() {
        stopMoving();
        requestDialog.open = false;
        choiceDialog.open = false;
        getDialog.open = false;
        if (settingsPanel.open)
            settingsPanel.close();
    }

    // Back to the start state: every row at its first tile, focus on layout.initialFocus.
    function goHome() {
        closeWindows();
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
        if (moving) {  // moving an app tile: left/right move it, anything else finishes
            if (action === "left" || action === "right")
                sectionAt(section).swap(action === "left" ? -1 : 1);
            else
                stopMoving();
            return;
        }
        if (action === "home")
            closeWindows();
        if (loadingScreen.open) {  // a Moonlight stream is starting: only Back cancels it
            if (action === "back" && !(Config.system && Config.system("moonlight_cancel")))
                loadingScreen.hide();
            return;
        }
        if (requestDialog.open && requestDialog.handle(action))
            return;
        if (choiceDialog.open && choiceDialog.handle(action))
            return;
        if (getDialog.open && getDialog.handle(action))
            return;
        if (action.startsWith("request:")) {  // a "Get more" tile: ask first
            requestDialog.ask(action);
            return;
        }
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

    // "Did you mean…?" with the AI step's guesses ([{label, action}]); the chosen one runs.
    function showChoices(text, options) {
        choiceDialog.ask(text, options);
    }

    // "Not on your server": Jellyseerr's hits for a title ({query, results}, jellyseerr.py search), OK downloads one.
    function showGetDialog(result) {
        voiceOverlay.hide();
        getDialog.ask(result);
    }

    // Short message in the pill at the bottom; goes away by itself.
    function showMessage(text) {
        voiceOverlay.show("message", text);
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
            console.log("voice: \"" + result.text + "\" -> " + result.action + " (" + result.by + ")");
            // say = the AI step's short answer ("12° and cloudy"), shown instead of the sentence it heard
            if (!result.action && result.options && result.options.length) {
                voiceOverlay.hide();
                showChoices(result.text, result.options);
                return;
            }
            if (result.say)
                voiceOverlay.show("message", result.say);
            else
                voiceOverlay.show(result.action ? "heard" : "unknown", result.text);
            if (result.action)
                runAction(result.action);
        });
    }

    function keyAction(event) {
        let action = event.key ? keyActions[event.key] : undefined;
        // On Linux the native scan code is the evdev code + 8.
        if (action === undefined && event.nativeScanCode > 8)
            action = keyActions["evdev:" + (event.nativeScanCode - 8)];
        return action;
    }

    // OK on an app tile waits for the release: a short press opens the app, holding it moves the tile (like Google TV).
    readonly property bool onAppRow: !!sections[section] && sections[section].action === "launch" && atHomeLevel
    readonly property bool atHomeLevel: !settingsPanel.open && !requestDialog.open && !choiceDialog.open
                                        && !getDialog.open && !loadingScreen.open
    Timer {
        id: holdTimer
        interval: 600
        onTriggered: home.startMoving()
    }

    function startMoving() {
        const row = sectionAt(section);
        if (!row)
            return;
        row.moving = true;
        showMessage("Move with ‹ › · OK when done");
    }

    // Leaves move mode and saves the order (Config.system("save_app_order:<ids>"): apps.py order).
    function stopMoving() {
        const row = sectionAt(section);
        if (!row || !row.moving)
            return false;
        row.moving = false;
        const ids = Config.apps.map(a => a.id);
        if (!(Config.system && Config.system("save_app_order:" + ids.join(","))))
            console.log("action:save_app_order:" + ids.join(","));
        showMessage("Apps saved in this order");
        return true;
    }

    readonly property bool moving: !!sectionAt(section) && sectionAt(section).moving === true

    Keys.onPressed: event => {
        if (settingsPanel.typeKey(event)) {
            event.accepted = true;
            return;
        }
        const action = keyAction(event);
        if (action === undefined)
            return;
        event.accepted = true;
        if (action === "select" && onAppRow && !moving) {
            if (!event.isAutoRepeat && !holdTimer.running)
                holdTimer.restart();
            return;
        }
        if (event.isAutoRepeat && action === "select")
            return;
        runAction(action);
    }

    Keys.onReleased: event => {
        if (event.isAutoRepeat || keyAction(event) !== "select" || !holdTimer.running)
            return;
        holdTimer.stop();  // a short press: open the app
        event.accepted = true;
        runAction("select");
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

    GetDialog {
        id: getDialog
        onMessage: text => home.showMessage(text)
    }

    ChoiceDialog {
        id: choiceDialog
        onChosen: action => home.runAction(action)
    }

    RequestDialog {
        id: requestDialog
    }

    LoadingScreen {
        id: loadingScreen
    }

    function showLoading(name) {
        loadingScreen.show(name);
    }

    function hideLoading() {
        loadingScreen.hide();
    }

    VoiceOverlay {
        id: voiceOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(72)
    }
}
