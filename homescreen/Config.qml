pragma Singleton
import QtQuick

// Holds the loaded JSON (config/*.json and data/placeholder.json) and the UI scale.
// main.qml fills it in before Home.qml is loaded.
QtObject {
    property var theme: null      // config/theme.json
    property var apps: []         // config/apps.json
    property var layout: null     // config/layout.json
    property var content: ({})    // data/placeholder.json
    property var keymap: ({})     // config/keymap.json: Qt key name (Qt.Key_<name>) -> action
    property var weather: null    // ~/.cache/tv-project/weather.json (weather.py); null until there is one
    property real scale: 1        // window width / 1920
    property var launcher: null   // function(app); set by the Bigscreen plasmoid, null in the prototype (log only)
    property var voice: ({})      // config/voice.json (recording seconds etc.; phrases are used by voice.py)
    // Set by the Bigscreen plasmoid, null in the prototype:
    property var voiceListener: null  // function(callback({text, action} or null)): record + transcribe (voice.py)
    property var system: null         // function(action) -> true if handled: volume_*, tv_off, sleep, restart...
    property var volumeReader: null   // function(callback(volume 0..1)): current output volume (Settings panel)
    property var systemQuery: null    // function(args, callback(json)): system.py <args> (Wi-Fi, Bluetooth, display)

    property var appOrder: []         // app ids in the order the user moved them to (~/.config/tv-project/app-order.json)
    property var seerrQuery: null     // function(args, callback(json | null)): jellyseerr.py <args> (Jellyseerr page)
    property var scriptQuery: null    // function(script, args, callback(json | null)): any helper's JSON (Bigscreen)
    property bool homeActive: true    // Bigscreen: the home screen is the active window (not an app in front)

    property var actionRunner: null   // function(action); set by Home.qml (its runAction), for tiles with an "action"

    // Runs a keymap-style action ("launch:x", "jellyfin_play_id:<id>", ...), as tiles with an "action" do.
    function run(action) {
        if (actionRunner)
            actionRunner(action);
        else
            console.log("action:" + action);
    }

    function launch(appId) {
        const app = apps.find(a => a.id === appId);
        if (!app) {
            console.warn("launch: no app '" + appId + "'");
            return;
        }
        console.log("launch:" + appId);
        if (app.action)  // a built-in "app" such as Settings
            run(app.action);
        else if (launcher)
            launcher(app);
    }

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
