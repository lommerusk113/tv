// Replaces contents/ui/HomeScreen.qml of the stock org.kde.bigscreen.homescreen plasmoid (6.7.5).
// Everything else in that package stays upstream; scripts/install-bigscreen.sh puts this file in place
// and links homescreen/ next to it as contents/ui/tv.
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.bigscreen as Bigscreen
import org.kde.private.biglauncher

import "tv"

Item {
    id: root

    // Read by upstream main.qml (wallpaper blur and scrim). Our page is opaque, so neither is needed.
    readonly property bool blurBackground: false
    readonly property bool darkenBackground: false

    // Whenever the home screen is active again (start, or back from an app): take key focus and refresh
    // the Trakt rows (trakt.py sync, then reload; a no-op until `trakt.py auth` has been run) and the weather.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: {
        if (!windowActive)
            return;
        tv.forceActiveFocus();
        runScript("trakt.py sync", tv.reloadLive);
        runScript("tmdb.py", tv.reloadLive);
        runScript("weather.py", tv.reloadWeather);
    }

    // Home Page is Bigscreen's global "Toggle Bigscreen Home Screen" shortcut: upstream main.qml minimizes all apps,
    // and the key never reaches TvHome. Also reset the home screen, like the keymap's "home" action does in the prototype.
    Connections {
        target: Shortcuts
        function onToggleHomeScreen() {
            tv.goHome();
            tv.forceActiveFocus();
            // Minimizing everything leaves no active window, so the home screen would not get the next key.
            if (root.Window.window)
                root.Window.window.requestActivate();
        }
    }

    // weather.py itself skips the request until MET's Expires, so a short interval costs nothing.
    Timer {
        interval: 10 * 60 * 1000
        running: root.windowActive
        repeat: true
        onTriggered: root.runScript("weather.py", tv.reloadWeather)
    }

    // Runs "<script> [args]" from homescreen/ with python3, then onSuccess().
    function runScript(command, onSuccess) {
        const [script, ...args] = command.split(" ");
        exec.run(["python3", "'" + localPath(Qt.resolvedUrl("tv/" + script)) + "'"].concat(args).join(" "), data => {
            if (data["exit code"] === 0)
                onSuccess();
            else
                console.warn("tv: " + command + ": " + data.stderr.trim());
        });
    }

    function localPath(url) {
        return decodeURIComponent(url.toString().replace("file://", ""));
    }

    // Upstream main.qml opens the Bigscreen overlay (tasks, search, settings) on Back. Let Home use Back for its own
    // navigation first and hand it to the overlay only once focus is on the tabs.
    Binding {
        target: root.parent.Bigscreen.BackHandler
        property: "enabled"
        value: tv.atTop
    }

    // Runs shell commands; run(cmd, callback(data)) with data.stdout, data.stderr, data["exit code"].
    P5Support.DataSource {
        id: exec
        engine: "executable"
        property var callbacks: ({})

        function run(cmd, callback) {
            callbacks[cmd] = callback;
            connectSource(cmd);
        }

        onNewData: (source, data) => {
            const callback = callbacks[source];
            delete callbacks[source];
            disconnectSource(source);
            callback(data);
        }
    }

    TvHome {
        id: tv
        anchors.fill: parent
        focus: true

        // plasmashell has no QML_XHR_ALLOW_FILE_READ, so read the JSON files with cat instead.
        // A missing file gives "" like XHR does (the optional live content file is often missing).
        readFile: function (url, callback) {
            exec.run("cat '" + root.localPath(url) + "'", data => callback(data.stdout));
        }

        Component.onCompleted: {
            Config.launcher = app => {
                const model = Plasmoid.applicationListModel;
                if (model.isApplicationRunning(app.desktopId))
                    model.maximizeApplication(app.desktopId);
                else
                    model.runApplication(app.desktopId);
            };
            forceActiveFocus();
        }
    }
}
