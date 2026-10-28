// Replaces contents/ui/HomeScreen.qml of the stock org.kde.bigscreen.homescreen plasmoid (6.7.5).
// Everything else in that package stays upstream; scripts/install-bigscreen.sh puts this file in place
// and links homescreen/ next to it as contents/ui/tv.
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.bigscreen as Bigscreen
import org.kde.private.biglauncher
import org.kde.taskmanager as TaskManager

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
        runScript("jellyfin.py", tv.reloadLive);
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

    // Make the windows of our apps (apps.json) fullscreen when they open, like apps on a TV. Done here rather than
    // relying on Bigscreen's KWin "Maximizing" placement, which only applies in a real Bigscreen login and still
    // leaves a maximized window instead of a fullscreen one. Only once per window, so the app can leave fullscreen.
    TaskManager.TasksModel {
        id: appWindows
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    Instantiator {
        model: appWindows
        delegate: QtObject {
            required property int index
            required property var model

            // AppId is the desktop file name, e.g. "rocks.shy.VacuumTube.desktop" (".desktop" stripped on both sides to be safe).
            readonly property bool ours: Config.apps.some(app => app.desktopId
                && app.desktopId.replace(/\.desktop$/, "") === String(model.AppId).replace(/\.desktop$/, ""))

            // Short delay: some apps (Electron, Qt) set up their window right after it appears.
            property Timer fullscreen: Timer {
                interval: 500
                running: true
                onTriggered: {
                    const idx = appWindows.makeModelIndex(index);
                    if (ours && !model.IsFullScreen)
                        appWindows.requestToggleFullScreen(idx);
                }
            }
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
            // Record + transcribe + map to an action (voice.py listen prints {"text", "action"}).
            Config.voiceListener = callback => {
                exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/voice.py")) + "' listen", data => {
                    let result = null;
                    try {
                        if (data["exit code"] === 0)
                            result = JSON.parse(data.stdout);
                    } catch (e) {}
                    if (!result)
                        console.warn("tv: voice.py: " + data.stderr.trim());
                    callback(result);
                });
            };
            // Actions the home screen cannot do itself (from the keymap or voice).
            Config.system = action => {
                const commands = {
                    "volume_up": "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+",
                    "volume_down": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
                    "volume_mute": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
                };
                if (action === "tv_off")
                    root.runScript("tvpower.py off", () => {});
                else if (commands[action])
                    exec.run(commands[action], () => {});
                else
                    return false;
                return true;
            };
            forceActiveFocus();
            // Wake the TV and switch it to this laptop's input (no-op without "tv" in secrets.json).
            root.runScript("tvpower.py on", () => {});
        }
    }
}
