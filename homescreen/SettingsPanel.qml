import QtQuick
import "."

// Settings slide-in from the right (Settings tile, the remote's gear button, voice "open settings").
// Pages: main (volume + links), wifi, bluetooth, display, power, password. Home routes keys here while it is open:
// up/down pick, select runs, left/right change values, back goes up a page / closes. Wi-Fi, Bluetooth and display run
// through Config.systemQuery (system.py in Bigscreen); the prototype shows that they need Bigscreen.
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
    property var pending: ({})       // display: output id -> mode index chosen with left/right, not applied yet
    property var revert: null        // display: {output, mode, seconds} while "Keep this resolution?" counts down
    property string passwordFor: ""  // Wi-Fi network the password page is for
    readonly property var theme: Config.theme
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var titles: ({ main: "Settings", wifi: "Wi-Fi", bluetooth: "Bluetooth", display: "Display",
                                     power: "Power", password: "Password" })

    // Rows of the current page: {key, label, value, kind: link|action|toggle|value|header|info, ...extra}
    readonly property var entries: {
        const w = wifi, b = bt, d = display, p = pending, r = revert, c = confirming;
        switch (page) {
        case "main": {
            const net = w && w.networks ? w.networks.find(n => n.connected) : null;
            const out = d && d.outputs ? d.outputs.find(o => o.enabled) : null;
            return [
                { key: "volume", label: "Volume", kind: "value" },
                { key: "wifi", label: "Wi-Fi", kind: "link", value: w ? (!w.enabled ? "Off" : net ? net.ssid : "Not connected") : "" },
                { key: "bluetooth", label: "Bluetooth", kind: "link", value: b ? (b.powered ? "On" : "Off") : "" },
                { key: "display", label: "Display", kind: "link", value: out ? out.modeLabel : "" },
                { key: "power", label: "Power", kind: "link", value: "TV, sleep, restart" }
            ];
        }
        case "wifi": {
            if (!w)
                return [{ key: "loading", label: "Loading…", kind: "info" }];
            const rows = [{ key: "wifi-power", label: "Wi-Fi", kind: "toggle", on: w.enabled }];
            if (w.enabled) {
                rows.push({ key: "wifi-rescan", label: "Search again", kind: "action" });
                for (const n of w.networks)
                    rows.push({ key: "net:" + n.ssid, label: n.ssid, kind: "action", net: n,
                                value: n.connected ? "Connected" : (n.known ? "Saved" : "") + (n.secure && !n.known ? "🔒" : "")
                                       + "  " + n.signal + " %" });
            }
            return rows;
        }
        case "bluetooth": {
            if (!b)
                return [{ key: "loading", label: "Loading…", kind: "info" }];
            const rows = [{ key: "bt-power", label: "Bluetooth", kind: "toggle", on: b.powered }];
            if (b.powered) {
                rows.push({ key: "bt-scan", label: "Search for devices", kind: "action" });
                for (const dev of b.devices)
                    rows.push({ key: "dev:" + dev.mac, label: dev.name, kind: "action", dev: dev,
                                value: dev.connected ? "Connected" : dev.paired ? "Paired" : "Pair" });
            }
            return rows;
        }
        case "display": {
            if (!d)
                return [{ key: "loading", label: "Loading…", kind: "info" }];
            if (r)
                return [{ key: "keep", label: "Keep this resolution?", kind: "action", value: "OK = keep" },
                        { key: "info", label: "Going back in " + r.seconds + " s", kind: "info" }];
            const rows = [];
            for (const o of d.outputs) {
                if (d.outputs.length > 1) {
                    rows.push({ key: "hdr:" + o.id, label: (o.type === "Panel" ? "Laptop screen" : "TV / " + o.name), kind: "header" });
                    rows.push({ key: "screen:" + o.id, label: "Use this screen", kind: "toggle", on: o.enabled, out: o });
                }
                if (!o.enabled)
                    continue;
                const at = p[o.id] !== undefined ? p[o.id] : o.modes.findIndex(m => m.id === o.mode);
                const chosen = o.modes[at] || { label: o.modeLabel };
                rows.push({ key: "mode:" + o.id, label: "Resolution", kind: "value", out: o, index: at,
                            value: "◀ " + chosen.label + " ▶" + (at !== o.modes.findIndex(m => m.id === o.mode) ? "   OK = apply" : "") });
                rows.push({ key: "scale:" + o.id, label: "Text and app size", kind: "value", out: o,
                            value: "◀ " + Math.round(o.scale * 100) + " % ▶" });
            }
            return rows;
        }
        case "power":
            return [
                { key: "tv_off", label: "Turn off the TV", kind: "action" },
                { key: "sleep", label: "Sleep", kind: "action" },
                { key: "restart", label: c === "restart" ? "Press OK again to restart" : "Restart", kind: "action", confirm: true },
                { key: "shutdown", label: c === "shutdown" ? "Press OK again to shut down" : "Shut down", kind: "action", confirm: true }
            ];
        case "password":
            return [{ key: "password", label: "Password for " + passwordFor, kind: "input" },
                    { key: "join", label: "Connect", kind: "action" }];
        }
        return [];
    }

    function focusable(i) {
        return entries[i] && entries[i].kind !== "header" && entries[i].kind !== "info";
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
            undoResolution();
        open = false;
        busy = "";
        passwordInput.text = "";
    }

    function go(newPage, index) {
        page = newPage;
        confirming = "";
        current = index || 0;
        while (current < entries.length - 1 && !focusable(current))
            ++current;
        if (newPage === "password")
            passwordInput.forceActiveFocus();
        else if (passwordInput.activeFocus)
            panel.parent.forceActiveFocus();  // keys back to Home
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
        } else if (e.key.startsWith("mode:")) {
            const p = Object.assign({}, pending);
            p[e.out.id] = Math.max(0, Math.min(e.out.modes.length - 1, e.index + d));  // largest first: right = next lower
            pending = p;
        } else if (e.key.startsWith("scale:")) {
            const at = scales.findIndex(s => Math.abs(s - e.out.scale) < 0.01);
            const next = scales[Math.max(0, Math.min(scales.length - 1, (at < 0 ? 0 : at) + d))];
            if (Math.abs(next - e.out.scale) > 0.01)
                query(["display-set", e.out.name, "scale", String(next)], r => display = r, "Changing size…");
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
        case "keep": revert = null; revertTimer.stop(); return;
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
                passwordInput.text = "";
                go("password", 0);
            }
        } else if (e.dev) {
            const dev = e.dev;
            const verb = dev.connected ? "bt-disconnect" : dev.paired ? "bt-connect" : "bt-pair";
            const text = dev.connected ? "Disconnecting…" : dev.paired ? "Connecting…" : "Pairing with " + dev.name + "…";
            query([verb, dev.mac], r => bt = r, text);
        } else if (e.key.startsWith("screen:")) {
            query(["display-set", e.out.name, e.on ? "disable" : "enable"], r => display = r, "Changing screens…");
        } else if (e.key.startsWith("mode:")) {
            const mode = e.out.modes[e.index];
            if (!mode || mode.id === e.out.mode)
                return;
            const before = e.out.mode;
            query(["display-set", e.out.name, "mode", mode.id], r => {
                display = r;
                pending = {};
                revert = { output: e.out.name, mode: before, seconds: 15 };
                revertTimer.restart();
                current = 0;
            }, "Changing resolution…");
        }
    }

    function joinWifi() {
        const ssid = passwordFor, password = passwordInput.text;
        passwordInput.text = "";
        go("wifi", 0);
        query(["wifi-connect", ssid, password], r => wifi = r, "Connecting to " + ssid + "…");
    }

    function undoResolution() {
        const r = revert;
        revert = null;
        revertTimer.stop();
        query(["display-set", r.output, "mode", r.mode], res => display = res, "Going back…");
    }

    // Returns true when the action was used (Home then does nothing else with it).
    function handle(action) {
        if (busy && action !== "back")
            return true;
        switch (action) {
        case "up": move(-1); return true;
        case "down": move(1); return true;
        case "left": adjust(-1); return true;
        case "right": adjust(1); return true;
        case "select": activate(); return true;
        case "settings": close(); return true;  // the gear again toggles
        case "back":
            if (page === "display" && revert)
                undoResolution();
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
                return panel.undoResolution();
            panel.revert = Object.assign({}, panel.revert, { seconds: panel.revert.seconds - 1 });
        }
    }

    Timer {
        id: messageTimer
        interval: 6000
        onTriggered: panel.message = ""
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
        width: Config.px(680)
        height: parent.height
        x: panel.open ? parent.width - width : parent.width
        Behavior on x { NumberAnimation { duration: panel.theme.animationMs * 2; easing.type: Easing.OutCubic } }
        color: panel.theme.colors.surface

        Text {
            id: title
            x: Config.px(56)
            y: Config.px(48)
            text: (panel.page !== "main" ? "‹  " : "") + panel.titles[panel.page]
            color: panel.theme.colors.text
            font.family: panel.theme.font.family
            font.pixelSize: Config.px(panel.theme.font.sizes.heroMeta * 2)
            font.weight: Font.Bold
        }

        Text {
            id: note
            x: Config.px(56)
            anchors.top: title.bottom
            anchors.topMargin: Config.px(8)
            width: sheet.width - Config.px(112)
            text: panel.busy || panel.message
            visible: text !== ""
            color: panel.busy ? panel.theme.colors.accent : "#f28b82"
            wrapMode: Text.WordWrap
            font.family: panel.theme.font.family
            font.pixelSize: Config.px(panel.theme.font.sizes.tileMeta)
        }

        ListView {
            id: list
            anchors.top: title.bottom
            anchors.topMargin: Config.px(56)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.px(40)
            x: Config.px(56)
            width: sheet.width - Config.px(112)
            clip: true
            interactive: false
            spacing: Config.px(8)
            model: panel.entries
            currentIndex: panel.current
            highlightFollowsCurrentItem: false
            preferredHighlightBegin: Config.px(120)
            preferredHighlightEnd: height - Config.px(120)
            highlightRangeMode: ListView.ApplyRange
            highlightMoveDuration: panel.theme.animationMs * 2

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool focused: index === panel.current && panel.focusable(index)
                readonly property color ink: focused ? panel.theme.colors.onFocused : panel.theme.colors.text

                width: list.width
                height: modelData.kind === "header" ? Config.px(56)
                        : Config.px(modelData.key === "volume" || modelData.kind === "input" ? 112 : 76)
                radius: Config.px(16)
                color: focused ? panel.theme.colors.focusBorder : "transparent"
                Behavior on color { ColorAnimation { duration: panel.theme.animationMs } }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Config.px(modelData.kind === "header" ? 4 : 28)
                    anchors.rightMargin: Config.px(28)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Config.px(10)

                    Item {
                        width: parent.width
                        height: label.height

                        Text {
                            id: label
                            width: parent.width - value.implicitWidth - Config.px(16)
                            elide: Text.ElideRight
                            text: row.modelData.label
                            color: row.modelData.kind === "header" || row.modelData.kind === "info"
                                   ? panel.theme.colors.textDim : row.ink
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(row.modelData.kind === "header" ? panel.theme.font.sizes.tileMeta
                                                                                       : panel.theme.font.sizes.tab)
                            font.weight: row.modelData.kind === "header" ? Font.Bold : Font.DemiBold
                        }
                        Text {
                            id: value
                            anchors.right: parent.right
                            anchors.verticalCenter: label.verticalCenter
                            text: row.modelData.key === "volume" ? (panel.volume >= 0 ? "◀ " + Math.round(panel.volume * 100) + " % ▶" : "")
                                  : row.modelData.kind === "toggle" ? (row.modelData.on ? "On" : "Off")
                                  : (row.modelData.value || "") + (row.modelData.kind === "link" ? "   ›" : "")
                            color: row.focused ? panel.theme.colors.onFocused : panel.theme.colors.textDim
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(panel.theme.font.sizes.tileMeta)
                        }
                    }

                    // Volume bar
                    Rectangle {
                        visible: row.modelData.key === "volume"
                        width: parent.width
                        height: Config.px(8)
                        radius: height / 2
                        color: Config.withAlpha(row.ink, 0.2)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, panel.volume))
                            height: parent.height
                            radius: height / 2
                            color: row.focused ? panel.theme.colors.onFocused : panel.theme.colors.accent
                            Behavior on width { NumberAnimation { duration: panel.theme.animationMs } }
                        }
                    }

                    // Password field (the password page); typed with a keyboard or Bigscreen's on-screen keyboard.
                    Rectangle {
                        visible: row.modelData.kind === "input"
                        width: parent.width
                        height: Config.px(44)
                        radius: Config.px(10)
                        color: Config.withAlpha(row.ink, 0.12)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Config.px(14)
                            anchors.verticalCenter: parent.verticalCenter
                            text: passwordInput.text.length ? "•".repeat(passwordInput.text.length) : "Type the password"
                            color: row.ink
                            opacity: passwordInput.text.length ? 1 : 0.6
                            font.family: panel.theme.font.family
                            font.pixelSize: Config.px(panel.theme.font.sizes.tileMeta)
                        }
                    }
                }
            }
        }
    }

    // Receives the typing on the password page (drawn as dots in the row above). Enter connects, Escape goes back.
    TextInput {
        id: passwordInput
        width: 1
        height: 1
        opacity: 0  // not visible: false, which could not take keyboard focus
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        Keys.onReturnPressed: panel.joinWifi()
        Keys.onEnterPressed: panel.joinWifi()
        Keys.onEscapePressed: panel.handle("back")
    }
}
