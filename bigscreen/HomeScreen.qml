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
            root.pauseMedia(); // like a TV box: going home pauses what was playing
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

    // Global remote buttons (config/remote.json, shortcuts installed by `remote.py install`) work inside apps too:
    // remote.py send hands the action over through `remote.py wait`, which is rerun after every action.
    function waitForRemote() {
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/remote.py")) + "' wait", data => {
            const action = data.stdout.trim();
            if (action === "voice" && !root.windowActive)
                Shortcuts.toggleHomeScreen(); // the voice overlay lives on the home screen: show it first
            if (action)
                tv.runAction(action);
            else if (data["exit code"] !== 0)
                console.warn("tv: remote.py wait: " + data.stderr.trim());
            // A short pause, so a failing wait cannot spin.
            remoteRestart.restart();
        });
    }

    Timer {
        id: remoteRestart
        interval: 200
        onTriggered: root.waitForRemote()
    }

    function pauseMedia() {
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/media.py")) + "' pause", () => {});
    }

    // True when the app's window is the active one (then launching it again must not pause it).
    function appIsActive(desktopId) {
        const id = String(desktopId).replace(/\.desktop$/, "");
        for (let i = 0; i < appWindows.count; ++i) {
            const idx = appWindows.makeModelIndex(i);
            if (String(appWindows.data(idx, TaskManager.AbstractTasksModel.AppId)).replace(/\.desktop$/, "") === id
                    && appWindows.data(idx, TaskManager.AbstractTasksModel.IsActive))
                return true;
        }
        return false;
    }

    Timer {
        id: raiseYoutube
        interval: 1500
        onTriggered: Config.launch("youtube")
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
                // Switching to another app pauses whatever plays (Jellyfin keeps playing in the background otherwise).
                if (!root.appIsActive(app.desktopId))
                    root.pauseMedia();
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
                if (action.startsWith("youtube_search:")) {
                    // Voice "play <query> on YouTube": VacuumTube opens YouTube's search results (media.py pauses
                    // other players first); then raise its window, which the deeplink alone does not do.
                    const query = action.slice(15).replace(/'/g, "'\\''");
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/media.py")) + "' youtube '" + query + "'", () => {});
                    raiseYoutube.restart();
                } else if (action.startsWith("jellyfin_play:")) {
                    // Voice "play <title> on Jellyfin": open Jellyfin Desktop, then have the server start the title
                    // on it (jellyfin.py play waits for the app to connect).
                    Config.launch("jellyfin");
                    const title = action.slice(14).replace(/'/g, "'\\''");
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyfin.py")) + "' play '" + title + "'", data => {
                        if (data["exit code"] !== 0 || data.stdout.indexOf('"ok": true') < 0)
                            console.warn("tv: jellyfin.py play: " + (data.stdout + data.stderr).trim());
                    });
                } else if (action === "tv_off" || action === "tv_power" || action === "tv_input")
                    root.runScript("tvpower.py " + {"tv_off": "off", "tv_power": "toggle", "tv_input": "on"}[action], () => {});
                else if (commands[action])
                    exec.run(commands[action], () => {});
                else
                    return false;
                return true;
            };
            forceActiveFocus();
            root.waitForRemote();
            // Wake the TV and switch it to this laptop's input (no-op without "tv" in secrets.json).
            root.runScript("tvpower.py on", () => {});
        }
    }
}
