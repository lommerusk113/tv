pragma Singleton
import QtQuick

// Holds the loaded JSON (config/*.json and data/placeholder.json) and the UI scale.
// main.qml fills it in before Home.qml is loaded.
QtObject {
    property var theme: null      // config/theme.json
    property var apps: []         // config/apps.json
    property var layout: null     // config/layout.json
    property var content: ({})    // data/placeholder.json
    property real scale: 1        // window width / 1920

    // Sizes in theme.json are in 1920x1080 reference pixels.
    function px(v) { return Math.round(v * scale); }

    // c is a "#rrggbb" string from the JSON config.
    function withAlpha(c, a) {
        const hex = String(c).replace("#", "").slice(-6);
        return Qt.rgba(parseInt(hex.slice(0, 2), 16) / 255,
                       parseInt(hex.slice(2, 4), 16) / 255,
                       parseInt(hex.slice(4, 6), 16) / 255, a);
    }
}
