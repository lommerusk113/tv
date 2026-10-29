import QtQuick
import QtCore
import "."

// Loads the JSON config into Config, then shows Home. Shared by the prototype window (main.qml)
// and the Bigscreen plasmoid (bigscreen/HomeScreen.qml), which passes its own readFile.
FocusScope {
    id: root

    // readFile(url, callback(text)): default is XHR, which needs QML_XHR_ALLOW_FILE_READ=1 (run.py sets it).
    property var readFile: function (url, callback) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE)
                callback(xhr.responseText);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // Live rows written by trakt.py sync; their keys override data/placeholder.json. Optional.
    readonly property string liveUrl: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/tv-project/content.json"
    readonly property string weatherUrl: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/tv-project/weather.json"
    property var placeholder: ({})
    property string liveText: ""

    property int pending: 7
    // True when Back has nothing left to do in Home (start row, first tile); Bigscreen then opens its overlay.
    readonly property bool atTop: loader.item ? loader.item.atRoot : false

    function loadJson(path, apply, optional) {
        root.readFile(Qt.resolvedUrl(path), text => {
            try {
                apply(JSON.parse(text));
            } catch (e) {
                if (!optional) {
                    console.error("config: failed to load " + path + ": " + e);
                    return;
                }
                console.log("config: no " + path + ", using placeholders");
            }
            if (--root.pending === 0) {
                applyContent();
                loader.source = "Home.qml";
            }
        });
    }

    function applyContent() {
        let live = {};
        try {
            live = JSON.parse(liveText);
        } catch (e) {}
        Config.content = Object.assign({}, placeholder, live);
    }

    // Re-read the live content (after a sync). Only rebuilds the rows when it changed, keeping focus where it was
    // (the syncs run when the home screen comes back, often while the user is already moving).
    function reloadLive() {
        readFile(liveUrl, text => {
            let normalized;
            try {
                normalized = JSON.stringify(JSON.parse(text));
            } catch (e) {
                return; // missing or unreadable: keep what is shown
            }
            if (normalized === liveText)
                return;
            liveText = normalized;
            const focus = loader.item ? loader.item.focusState() : null;
            applyContent();
            Qt.callLater(() => focus ? loader.item.restoreFocus(focus) : loader.item.goHome());
            console.log("config: live content updated");
        });
    }

    // Same as the keymap's "home" action: every row back to tile 0, scroll to the top, focus the initial row.
    function goHome() {
        if (loader.item)
            loader.item.goHome();
    }

    function showStatus(text) {
        if (loader.item)
            loader.item.showStatus(text);
    }

    // Runs a keymap action (e.g. "launch:youtube", "voice") as if its key had been pressed.
    function runAction(action) {
        if (loader.item)
            loader.item.runAction(action);
    }

    // Re-read weather.json (written by weather.py); a missing or unreadable file keeps what is shown.
    function reloadWeather() {
        readFile(weatherUrl, text => {
            try {
                Config.weather = JSON.parse(text);
            } catch (e) {}
        });
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.reloadWeather()
    }

    Binding {
        target: Config
        property: "scale"
        value: root.width / 1920
    }

    Component.onCompleted: {
        loadJson("config/theme.json", v => Config.theme = v);
        loadJson("config/apps.json", v => Config.apps = v);
        loadJson("config/layout.json", v => Config.layout = v);
        loadJson("data/placeholder.json", v => root.placeholder = v);
        loadJson("config/keymap.json", v => Config.keymap = v);
        loadJson("config/voice.json", v => Config.voice = v);
        loadJson(liveUrl, v => root.liveText = JSON.stringify(v), true);
    }

    Loader {
        id: loader
        anchors.fill: parent
        focus: true
    }
}
