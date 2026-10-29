import QtQuick
import QtQuick.Effects
import "."

// Settings slide-in from the right (Settings tile, the remote's gear button, voice "open settings").
// Pages: main (volume + links), wifi, bluetooth, display, power, password. Home routes keys here while it is open:
// up/down pick, select runs, left/right move sliders, back goes up a page / closes. Wi-Fi, Bluetooth and display run
// through Config.systemQuery (system.py in Bigscreen); the prototype shows that they need Bigscreen.
// Display: the sliders only choose; Apply sets resolution and size, then "Keep?" reverts by itself after 15 s.
Item {
    id: panel
    property bool open: false
    property string page: "main"
    property int current: 0
    property string confirming: ""   // key of the entry waiting for its second OK
    property string busy: ""         // "Connecting…" etc.; keys other than back wait meanwhile
    property string message: ""      // last error, shown under the title for a while
    property real volume: -1         // 0..1 from Config.volumeReader; -1 = unknown
    property var wifi: null          // system.py wifi
    property var bt: null            // system.py bt / bt-scan
    property var display: null       // system.py display
    property var pending: ({})       // display: "<output id>:mode" / ":scale" -> chosen slider index, not applied yet
    property var revert: null        // display: {undo: [[args, busy text]], seconds} while "Keep?" counts down
    property string passwordFor: ""  // Wi-Fi network the password page is for
    property string password: ""     // typed so far (on-screen keyboard, or a real keyboard through typeKey())
    readonly property var theme: Config.theme
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var titles: ({ main: "Settings", wifi: "Wi-Fi", bluetooth: "Bluetooth", display: "Display",
                                     power: "Power", password: "Wi-Fi password" })
    readonly property color danger: "#f28b82"

    // Modes smallest first, so the resolution slider grows to the right.
    function modesOf(o) {
        return o.modes.slice().reverse();
    }

    function modeIndex(o) {
        const at = pending[o.id + ":mode"];
        return at !== undefined ? at : modesOf(o).findIndex(m => m.id === o.mode);
    }

    function scaleIndex(o) {
        const at = pending[o.id + ":scale"];
        if (at !== undefined)
            return at;
        const i = scales.findIndex(s => Math.abs(s - o.scale) < 0.01);
        return i < 0 ? 0 : i;
    }

    readonly property bool displayChanged: {
        const d = display, p = pending;
        return !!d && d.outputs.some(o => o.enabled && ((modesOf(o)[modeIndex(o)] || {}).id !== o.mode
                                                        || Math.abs(scales[scaleIndex(o)] - o.scale) > 0.01));
    }

    // Rows of the current page: {key, label, sub, icon, kind: link|action|toggle|slider|button|header|input, ...}
    readonly property var entries: {
        const w = wifi, b = bt, d = display, p = pending, r = revert, c = confirming;
        switch (page) {
        case "main": {
            const net = w && w.networks ? w.networks.find(n => n.connected) : null;
            const out = d && d.outputs ? d.outputs.find(o => o.enabled) : null;
            const devs = b && b.devices ? b.devices.filter(x => x.connected).length : 0;
            return [
                { key: "volume", label: "Volume", icon: "volume", kind: "slider",
                  position: Math.max(0, volume), text: volume >= 0 ? Math.round(volume * 100) + " %" : "" },
                { key: "wifi", label: "Wi-Fi", icon: "wifi", kind: "link",
                  sub: w ? (!w.enabled ? "Off" : net ? net.ssid : "Not connected") : " " },
                { key: "bluetooth", label: "Bluetooth", icon: "bluetooth", kind: "link",
                  sub: b ? (!b.powered ? "Off" : devs ? devs + " connected" : "On") : " " },
                { key: "display", label: "Display", icon: "display", kind: "link",
                  sub: out ? out.modeLabel + " · " + Math.round(out.scale * 100) + " %" : " " },
                { key: "power", label: "Power", icon: "power", kind: "link", sub: "TV, sleep, restart, shut down" }
            ];
        }
        case "wifi": {
            if (!w)
                return [{ key: "loading", label: "Loading…", kind: "header" }];
            const rows = [{ key: "wifi-power", label: "Wi-Fi", icon: "wifi", kind: "toggle", on: w.enabled }];
            if (w.enabled) {
                rows.push({ key: "hdr-net", label: "Networks", kind: "header" });
                for (const n of w.networks)
                    rows.push({ key: "net:" + n.ssid, label: n.ssid, kind: "action", net: n, lock: n.secure && !n.known,
                                icon: "signal-" + (n.signal >= 75 ? "excellent" : n.signal >= 50 ? "good" : n.signal >= 25 ? "ok" : "weak"),
                                sub: n.connected ? "Connected" : n.known ? "Saved" : n.secure ? "Secured" : "Open" });
                rows.push({ key: "wifi-rescan", label: "Search again", icon: "refresh", kind: "action" });
            }
            return rows;
        }
        case "bluetooth": {
            if (!b)
                return [{ key: "loading", label: "Loading…", kind: "header" }];
            const rows = [{ key: "bt-power", label: "Bluetooth", icon: "bluetooth", kind: "toggle", on: b.powered }];
            if (b.powered) {
                rows.push({ key: "hdr-dev", label: "Devices", kind: "header" });
                for (const dev of b.devices) {
                    const n = dev.name.toLowerCase();
                    const icon = /remote|tv/.test(n) ? "tv" : /keyboard/.test(n) ? "keyboard" : /mouse/.test(n) ? "mouse"
                               : /bud|head|ear|pods|speaker|sound/.test(n) ? "headphones" : /phone/.test(n) ? "phone" : "bluetooth";
                    rows.push({ key: "dev:" + dev.mac, label: dev.name, kind: "action", dev: dev, icon: icon,
                                sub: dev.connected ? "Connected" : dev.paired ? "Paired · OK to connect" : "OK to pair" });
                }
                rows.push({ key: "bt-scan", label: "Search for devices", icon: "search", kind: "action" });
            }
            return rows;
        }
        case "display": {
            if (!d)
                return [{ key: "loading", label: "Loading…", kind: "header" }];
            if (r)
                return [{ key: "keep", label: "Keep these settings", icon: "display", kind: "action",
                          sub: "Going back in " + r.seconds + " s" },
                        { key: "undo", label: "Go back", icon: "refresh", kind: "action" }];
            const rows = [];
            for (const o of d.outputs) {
                if (d.outputs.length > 1) {
                    rows.push({ key: "hdr:" + o.id, label: o.type === "Panel" ? "Laptop screen" : "TV · " + o.name, kind: "header" });
                    rows.push({ key: "screen:" + o.id, label: "Use this screen", icon: o.type === "Panel" ? "display" : "tv",
                                kind: "toggle", on: o.enabled, out: o });
                }
                if (!o.enabled)
                    continue;
                const modes = modesOf(o), mi = modeIndex(o), si = scaleIndex(o);
                const mode = modes[mi] || { label: o.modeLabel };
                rows.push({ key: "mode:" + o.id, label: "Resolution", icon: "display", kind: "slider", out: o,
                            position: modes.length > 1 ? mi / (modes.length - 1) : 1, steps: modes.length,
                            text: mode.label.replace("x", " × "), changed: mode.id !== o.mode });
                rows.push({ key: "scale:" + o.id, label: "Text and app size", icon: "search", kind: "slider", out: o,
                            position: si / (scales.length - 1), steps: scales.length,
                            text: Math.round(scales[si] * 100) + " %", changed: Math.abs(scales[si] - o.scale) > 0.01 });
            }
            rows.push({ key: "apply", label: "Apply", kind: "button", enabled: displayChanged });
            return rows;
        }
        case "power":
            return [
                { key: "tv_off", label: "Turn off the TV", icon: "tv", kind: "action" },
                { key: "sleep", label: "Sleep", icon: "sleep", kind: "action", sub: "Wake it with the laptop's power button" },
                { key: "restart", label: "Restart", icon: "restart", kind: "action", confirm: true,
                  sub: c === "restart" ? "Press OK again to restart" : "", warn: c === "restart" },
                { key: "shutdown", label: "Shut down", icon: "power", kind: "action", confirm: true,
                  sub: c === "shutdown" ? "Press OK again to shut down" : "", warn: c === "shutdown" }
            ];
        case "password":
            // Typed with the on-screen keyboard below (its OK connects) or a real keyboard.
            return [{ key: "password", label: passwordFor, icon: "lock", kind: "input" }];
        }
        return [];
    }

    function focusable(i) {
        const e = entries[i];
        return !!e && e.kind !== "header" && !(e.kind === "button" && !e.enabled);
    }

    function show() {
        open = true;
        go("main", 0);
        readVolume();
        query(["wifi"], r => wifi = r);
        query(["bt"], r => bt = r);
        query(["display"], r => display = r);
    }

    function close() {
        if (revert)
            undoDisplay();
        open = false;
        busy = "";
        pending = {};
        password = "";
    }

    function go(newPage, index) {
        page = newPage;
        confirming = "";
        pending = {};
        current = index || 0;
        while (current < entries.length - 1 && !focusable(current))
            ++current;
        if (newPage === "password") {
            keyboard.row = 1;
            keyboard.col = 0;
            keyboard.shift = keyboard.symbols = false;
        }
    }

    function readVolume() {
        if (Config.volumeReader)
            Config.volumeReader(v => panel.volume = v);
    }

    // Runs system.py with args; onResult gets its JSON. busyText shows meanwhile. Errors go to `message`.
    function query(args, onResult, busyText) {
        if (!Config.systemQuery) {
            message = "Wi-Fi, Bluetooth and display settings work in Bigscreen";
            return;
        }
        if (busyText)
            busy = busyText;
        Config.systemQuery(args, result => {
            if (busyText)
                busy = "";
            if (!result || result.error) {
                message = result && result.error ? result.error : "That did not work";
                messageTimer.restart();
                return;
            }
            onResult(result);
        });
    }

    // Runs [[args, busyText], ...] one after another (display changes), then done().
    function queryAll(steps, done) {
        if (!steps.length)
            return done();
        const [args, text] = steps[0];
        query(args, r => { display = r; queryAll(steps.slice(1), done); }, text);
    }

    function system(action) {
        if (!(Config.system && Config.system(action)))
            console.log("action:" + action);
    }

    function move(d) {
        let i = current + d;
        while (i >= 0 && i < entries.length && !focusable(i))
            i += d;
        if (i >= 0 && i < entries.length) {
            current = i;
            confirming = "";
        }
    }

    function adjust(d) {
        const e = entries[current];
        if (!e)
            return;
        if (e.key === "volume") {
            system(d < 0 ? "volume_down" : "volume_up");
            volumeRefresh.restart();
        } else if (e.key.startsWith("mode:") || e.key.startsWith("scale:")) {
            const isMode = e.key.startsWith("mode:");
            const count = isMode ? e.out.modes.length : scales.length;
            const now = isMode ? modeIndex(e.out) : scaleIndex(e.out);
            const p = Object.assign({}, pending);
            p[e.out.id + (isMode ? ":mode" : ":scale")] = Math.max(0, Math.min(count - 1, now + d));
            pending = p;
        }
    }

    function activate() {
        const e = entries[current];
        if (!e || !focusable(current))
            return;
        if (e.kind === "link") {
            go(e.key, 0);
            if (e.key === "wifi" && wifi && wifi.enabled)
                query(["wifi-rescan"], r => wifi = r);  // fresh list in the background
            return;
        }
        if (e.confirm && confirming !== e.key) {
            confirming = e.key;
            return;
        }
        switch (e.key) {
        case "tv_off": case "sleep": case "restart": case "shutdown":
            close();
            system(e.key);
            return;
        case "wifi-power": query(["wifi-power", e.on ? "off" : "on"], r => wifi = r, e.on ? "Turning off…" : "Turning on…"); return;
        case "wifi-rescan": query(["wifi-rescan"], r => wifi = r, "Searching…"); return;
        case "bt-power": query(["bt-power", e.on ? "off" : "on"], r => bt = r, e.on ? "Turning off…" : "Turning on…"); return;
        case "bt-scan": query(["bt-scan", "8"], r => bt = r, "Searching for devices…"); return;
        case "apply": applyDisplay(); return;
        case "keep": revert = null; revertTimer.stop(); go("display", 0); return;
        case "undo": undoDisplay(); return;
        case "join": joinWifi(); return;
        }
        if (e.net) {
            const n = e.net;
            if (n.connected)
                query(["wifi-disconnect"], r => wifi = r, "Disconnecting…");
            else if (n.known || !n.secure)
                query(["wifi-connect", n.ssid], r => wifi = r, "Connecting to " + n.ssid + "…");
            else {
                passwordFor = n.ssid;
                password = "";
                go("password", 0);
            }
        } else if (e.dev) {
            const dev = e.dev;
            const verb = dev.connected ? "bt-disconnect" : dev.paired ? "bt-connect" : "bt-pair";
            const text = dev.connected ? "Disconnecting…" : dev.paired ? "Connecting…" : "Pairing with " + dev.name + "…";
            query([verb, dev.mac], r => bt = r, text);
        } else if (e.key.startsWith("screen:")) {
            query(["display-set", e.out.name, e.on ? "disable" : "enable"], r => display = r, "Changing screens…");
        }
    }

    // Apply: resolution and size of every screen as chosen on the sliders; then "Keep?" with a 15 s way back.
    function applyDisplay() {
        const steps = [], undo = [];
        for (const o of display.outputs) {
            if (!o.enabled)
                continue;
            const mode = modesOf(o)[modeIndex(o)], scale = scales[scaleIndex(o)];
            if (mode && mode.id !== o.mode) {
                steps.push([["display-set", o.name, "mode", mode.id], "Changing resolution…"]);
                undo.push([["display-set", o.name, "mode", o.mode], "Going back…"]);
            }
            if (Math.abs(scale - o.scale) > 0.01) {
                steps.push([["display-set", o.name, "scale", String(scale)], "Changing size…"]);
                undo.push([["display-set", o.name, "scale", String(o.scale)], "Going back…"]);
            }
        }
        queryAll(steps, () => {
            pending = {};
            revert = { undo: undo, seconds: 15 };
            revertTimer.restart();
            current = 0;
        });
    }

    function undoDisplay() {
        const r = revert;
        revert = null;
        revertTimer.stop();
        queryAll(r.undo, () => go("display", 0));
    }

    function joinWifi() {
        const ssid = passwordFor, typed = password;
        password = "";
        go("wifi", 0);
        query(["wifi-connect", ssid, typed], r => wifi = r, "Connecting to " + ssid + "…");
    }

    // A key from a real keyboard, before Home maps it (Home keeps the focus; no hidden text field, which once kept the
    // focus after leaving the page and swallowed the arrow keys). True when it was typed into the password.
    function typeKey(event) {
        if (!open || page !== "password")
            return false;
        if (event.key === Qt.Key_Backspace) {
            password = password.slice(0, -1);
            return true;
        }
        if (event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
            password += event.text;
            return true;
        }
        return false;
    }

    // Returns true when the action was used (Home then does nothing else with it).
    function handle(action) {
        if (busy && action !== "back")
            return true;
        if (page === "password" && action !== "back" && action !== "settings")
            return keyboard.handle(action) || true;  // everything else stays on the password page
        switch (action) {
        case "up": move(-1); return true;
        case "down": move(1); return true;
        case "left": adjust(-1); return true;
        case "right": adjust(1); return true;
        case "select": activate(); return true;
        case "settings": close(); return true;  // the gear again toggles
        case "back":
            if (page === "display" && revert)
                undoDisplay();
            else if (page === "password")
                go("wifi", 0);
            else if (page !== "main")
                go("main", ["main", "wifi", "bluetooth", "display", "power"].indexOf(page));
            else
                close();
            return true;
        }
        return false;  // home, volume keys, launch:... are handled by Home as usual
    }

    // wpctl needs a moment before the new volume can be read back.
    Timer {
        id: volumeRefresh
        interval: 150
        onTriggered: panel.readVolume()
    }

    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (!panel.revert)
                return stop();
            if (panel.revert.seconds <= 1)
                return panel.undoDisplay();
            panel.revert = Object.assign({}, panel.revert, { seconds: panel.revert.seconds - 1 });
        }
    }

    Timer {
        id: messageTimer
        interval: 6000
        onTriggered: panel.message = ""
    }

    // --- Look -------------------------------------------------------------------------------------------------------

    // Monochrome Breeze icon (icons/settings/<name>.svg) tinted to `color`.
    component Icon: Item {
        id: icon
        property string name
        property color color
        width: Config.px(30)
        height: width
        Image {
            id: img
            anchors.fill: parent
            source: icon.name ? Qt.resolvedUrl("icons/settings/" + icon.name + ".svg") : ""
            sourceSize: Qt.size(width * 2, height * 2)
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: img
            colorization: 1
            colorizationColor: icon.color
            brightness: 1
        }
    }

    component Toggle: Rectangle {
        id: toggle
        property bool on
        property bool focused
        width: Config.px(60)
        height: Config.px(34)
        radius: height / 2
        color: on ? panel.theme.colors.accent : Config.withAlpha(focused ? panel.theme.colors.onFocused : panel.theme.colors.text, 0.25)
        Behavior on color { ColorAnimation { duration: panel.theme.animationMs } }
        Rectangle {
            width: toggle.height - Config.px(8)
            height: width
            radius: width / 2
            y: Config.px(4)
            x: toggle.on ? toggle.width - width - Config.px(4) : Config.px(4)
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: panel.theme.animationMs; easing.type: Easing.OutCubic } }
        }
    }

    component Slider: Item {
        id: slider
        property real position          // 0..1
        property int steps: 0           // > 1: tick marks
        property color ink
        property bool focused
        height: Config.px(28)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Config.px(6)
            radius: height / 2
            color: Config.withAlpha(slider.ink, 0.18)
            Rectangle {
                width: knob.x + knob.width / 2
                height: parent.height
                radius: height / 2
                color: slider.focused ? slider.ink : panel.theme.colors.accent
            }
        }
        Repeater {
            model: slider.steps > 1 ? slider.steps : 0
            delegate: Rectangle {
                required property int index
                width: Config.px(4)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: (slider.width - knob.width) * index / (slider.steps - 1) + knob.width / 2 - width / 2
                color: Config.withAlpha(slider.ink, 0.45)
            }
        }
        Rectangle {
            id: knob
            width: Config.px(slider.focused ? 26 : 20)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: (slider.width - width) * Math.max(0, Math.min(1, slider.position))
            color: slider.focused ? slider.ink : panel.theme.colors.text
            Behavior on x { NumberAnimation { duration: panel.theme.animationMs; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: panel.theme.animationMs } }
        }
    }

    visible: sheet.x < width
    anchors.fill: parent

    // Dims the home screen behind the sheet.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: panel.open ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: panel.theme.animationMs * 2 } }
    }

    Rectangle {
        id: sheet
        readonly property real pad: Config.px(52)
        readonly property color topColor: Qt.lighter(panel.theme.colors.surface, 1.12)
        width: Config.px(720)
        height: parent.height
        x: panel.open ? parent.width - width : parent.width
        Behavior on x { NumberAnimation { duration: panel.theme.animationMs * 2; easing.type: Easing.OutCubic } }
        radius: Config.px(36)  // only the left corners show; the right edge is the screen edge
        gradient: Gradient {
            GradientStop { position: 0; color: sheet.topColor }
            GradientStop { position: 1; color: panel.theme.colors.surface }
        }

        // Header: back arrow on sub pages, title, then the busy/error line.
        Row {
            id: header
            x: sheet.pad
            y: Config.px(56)
            spacing: Config.px(14)
            Icon {
                visible: panel.page !== "main"
                anchors.verticalCenter: parent.verticalCenter
                name: "next"
                rotation: 180
                color: panel.theme.colors.textDim
            }
            Text {
                text: panel.titles[panel.page]
                color: panel.theme.colors.text
                font.family: panel.theme.font.family
                font.pixelSize: Config.px(40)
                font.weight: Font.Bold
            }
        }

        Row {
            id: status
            x: sheet.pad
            anchors.top: header.bottom
            anchors.topMargin: Config.px(10)
            height: Config.px(28)
            spacing: Config.px(10)
            opacity: panel.busy || panel.message ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: panel.theme.animationMs } }

            Rectangle {  // spinner while busy
                visible: !!panel.busy
                anchors.verticalCenter: parent.verticalCenter
                width: Config.px(18)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Config.px(3)
                border.color: panel.theme.colors.accent
                Rectangle {  // the gap that makes it look like it turns
                    width: Config.px(9)
                    height: width
                    color: sheet.topColor
                    anchors.top: parent.top
                    anchors.right: parent.right
                }
                RotationAnimation on rotation {
                    running: !!panel.busy
                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                }
            }
            Text {
                width: sheet.width - sheet.pad * 2 - Config.px(30)
                text: panel.busy || panel.message
                elide: Text.ElideRight
                color: panel.busy ? panel.theme.colors.accent : panel.danger
                font.family: panel.theme.font.family
                font.pixelSize: Config.px(20)
            }
        }

        ListView {
            id: list
            anchors.top: status.bottom
            anchors.topMargin: Config.px(20)
            anchors.bottom: keyboard.visible ? keyboard.top : parent.bottom
            x: sheet.pad - Config.px(12)
            width: sheet.width - sheet.pad * 2 + Config.px(24)
            clip: true
            interactive: false
            spacing: Config.px(6)
            topMargin: Config.px(12)
            bottomMargin: Config.px(40)
            model: panel.entries
            currentIndex: panel.current
            highlightFollowsCurrentItem: false
            preferredHighlightBegin: Config.px(140)
            preferredHighlightEnd: height - Config.px(160)
            highlightRangeMode: ListView.ApplyRange
            highlightMoveDuration: panel.theme.animationMs * 2

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property var e: modelData
                readonly property bool focused: index === panel.current && panel.focusable(index)
                readonly property color ink: focused ? panel.theme.colors.onFocused : panel.theme.colors.text
                readonly property color dim: focused ? Config.withAlpha(panel.theme.colors.onFocused, 0.65) : panel.theme.colors.textDim
                readonly property bool tall: e.kind === "slider" || e.kind === "input"
                readonly property color warn: focused ? "#c5221f" : panel.danger  // readable on the white focus

                width: list.width
                height: e.kind === "header" ? Config.px(64)
                        : e.kind === "button" ? Config.px(100)
                        : Config.px(tall ? 118 : (e.sub ? 92 : 80))

                // Section title
                Text {
                    visible: row.e.kind === "header"
                    anchors.left: parent.left
                    anchors.leftMargin: Config.px(12)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Config.px(12)
                    text: row.e.label.toUpperCase()
                    color: panel.theme.colors.textDim
                    font.family: panel.theme.font.family
                    font.pixelSize: Config.px(17)
                    font.weight: Font.Bold
                    font.letterSpacing: Config.px(2)
                }

                // Apply / Connect button
                Rectangle {
                    visible: row.e.kind === "button"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: parent.width - Config.px(24)
                    height: Config.px(72)
                    radius: height / 2
                    scale: row.focused ? 1.03 : 1
                    color: row.focused ? panel.theme.colors.focusBorder
                           : row.e.enabled ? panel.theme.colors.accent : Config.withAlpha(panel.theme.colors.text, 0.08)
                    Behavior on scale { NumberAnimation { duration: panel.theme.animationMs } }
                    Behavior on color { ColorAnimation { duration: panel.theme.animationMs } }
                    Text {
                        anchors.centerIn: parent
                        text: row.e.label
                        color: row.e.enabled ? panel.theme.colors.onFocused : panel.theme.colors.textDim
                        font.family: panel.theme.font.family
                        font.pixelSize: Config.px(24)
                        font.weight: Font.Bold
                    }
                }

                // Card for the other kinds (side margins leave room for the focus zoom inside the clipped list)
                Rectangle {
                    visible: row.e.kind !== "header" && row.e.kind !== "button"
                    anchors.fill: parent
                    anchors.leftMargin: Config.px(8)
                    anchors.rightMargin: Config.px(8)
                    radius: Config.px(22)
                    scale: row.focused ? 1.02 : 1
                    color: row.focused ? panel.theme.colors.focusBorder : "transparent"
                    Behavior on scale { NumberAnimation { duration: panel.theme.animationMs; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: panel.theme.animationMs } }

                    // Icon in a soft circle
                    Rectangle {
                        id: badge
                        visible: !!row.e.icon
                        x: Config.px(18)
                        y: row.tall ? Config.px(18) : (parent.height - height) / 2
                        width: Config.px(52)
                        height: width
                        radius: width / 2
                        color: Config.withAlpha(row.ink, 0.08)
                        Icon {
                            anchors.centerIn: parent
                            name: row.e.icon || ""
                            color: row.e.warn ? row.warn : row.ink
                        }
                    }

                    Column {
                        id: texts
                        anchors.left: badge.visible ? badge.right : parent.left
                        anchors.leftMargin: Config.px(badge.visible ? 20 : 24)
                        anchors.right: trailing.left
                        anchors.rightMargin: Config.px(16)
                        y: row.tall ? Config.px(22) : (parent.height - height) / 2
                        spacing: Config.px(4)
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.e.label
                            color: row.ink
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(25)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!row.e.sub
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.e.sub || ""
                            color: row.e.warn ? row.warn : row.dim
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(19)
                        }
                    }

                    // Right side: value text, toggle, lock or chevron
                    Row {
                        id: trailing
                        anchors.right: parent.right
                        anchors.rightMargin: Config.px(24)
                        y: row.tall ? Config.px(30) : (parent.height - height) / 2
                        spacing: Config.px(12)
                        Text {
                            visible: !!row.e.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.e.changed ? "● " : "") + (row.e.text || "")
                            color: row.e.changed ? (row.focused ? row.ink : panel.theme.colors.accent) : row.dim
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(21)
                            font.weight: Font.DemiBold
                        }
                        Toggle {
                            visible: row.e.kind === "toggle"
                            anchors.verticalCenter: parent.verticalCenter
                            on: !!row.e.on
                            focused: row.focused
                        }
                        Icon {
                            visible: !!row.e.lock
                            anchors.verticalCenter: parent.verticalCenter
                            width: Config.px(22)
                            name: "lock"
                            color: row.dim
                        }
                        Icon {
                            visible: row.e.kind === "link"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Config.px(24)
                            name: "next"
                            color: row.dim
                        }
                    }

                    Slider {
                        visible: row.e.kind === "slider"
                        anchors.left: texts.left
                        anchors.right: parent.right
                        anchors.rightMargin: Config.px(28)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Config.px(18)
                        position: row.e.position || 0
                        steps: row.e.steps || 0
                        ink: row.ink
                        focused: row.focused
                    }

                    // Password field (typed with a keyboard or Bigscreen's on-screen keyboard)
                    Rectangle {
                        visible: row.e.kind === "input"
                        anchors.left: texts.left
                        anchors.right: parent.right
                        anchors.rightMargin: Config.px(28)
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Config.px(16)
                        height: Config.px(44)
                        radius: Config.px(12)
                        color: Config.withAlpha(row.ink, 0.1)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Config.px(16)
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.password.length ? "•".repeat(panel.password.length) : "Type the password"
                            color: row.ink
                            opacity: panel.password.length ? 1 : 0.55
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(21)
                        }
                    }
                }
            }
        }
    }

    // Password page: remote-friendly keyboard at the bottom of the sheet.
    OnScreenKeyboard {
        id: keyboard
        parent: sheet
        visible: panel.page === "password"
        x: sheet.pad
        width: sheet.width - sheet.pad * 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Config.px(48)
        onTyped: text => panel.password += text
        onBackspace: panel.password = panel.password.slice(0, -1)
        onDone: panel.joinWifi()
    }
}
