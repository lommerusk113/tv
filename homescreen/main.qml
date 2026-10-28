import QtQuick
import QtQuick.Window
import "."

Window {
    id: root
    width: 1920
    height: 1080
    minimumWidth: 1920
    maximumWidth: 1920
    minimumHeight: 1080
    maximumHeight: 1080
    visible: true
    title: "TV Home Screen (prototype)"
    color: "#000000"

    property int pending: 5

    function loadJson(path, apply) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            try {
                apply(JSON.parse(xhr.responseText));
            } catch (e) {
                console.error("config: failed to load " + path + ": " + e);
                Qt.exit(1);
                return;
            }
            if (--root.pending === 0)
                loader.source = "Home.qml";
        };
        xhr.open("GET", Qt.resolvedUrl(path));
        xhr.send();
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
