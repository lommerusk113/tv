import QtQuick
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

    property int pending: 5
    // True when Back has nothing left to do in Home (focus is on the tabs); Bigscreen then opens its overlay.
    readonly property bool atTop: loader.item ? loader.item.section === -1 : false

    function loadJson(path, apply) {
        root.readFile(Qt.resolvedUrl(path), text => {
            try {
                apply(JSON.parse(text));
            } catch (e) {
                console.error("config: failed to load " + path + ": " + e);
                return;
            }
            if (--root.pending === 0)
                loader.source = "Home.qml";
        });
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
        loadJson("data/placeholder.json", v => Config.content = v);
        loadJson("config/keymap.json", v => Config.keymap = v);
    }

    Loader {
        id: loader
        anchors.fill: parent
        focus: true
    }
}
