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
    // the rows (Trakt: a no-op until `trakt.py auth`; TMDb, Jellyfin, YouTube channels) and the weather.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: {
        if (!windowActive)
            return;
        tv.forceActiveFocus();
        runScript("trakt.py sync", tv.reloadLive);
        runScript("tmdb.py", tv.reloadLive);
        runScript("jellyfin.py", tv.reloadLive);
        runScript("youtube.py", tv.reloadLive);
        runScript("apps.py", tv.reloadLive);
        runScript("weather.py", tv.reloadWeather);
    }

    // Home Page is Bigscreen's global "Toggle Bigscreen Home Screen" shortcut: upstream main.qml minimizes all apps,
    // and the key never reaches TvHome. Also reset the home screen, like the keymap's "home" action does in the prototype.
    Connections {
        target: Shortcuts
        function onToggleHomeScreen() {
            root.leaveApps(""); // like a TV box: going home pauses, and apps start from their start page next time
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
            if (action === "show_home") { // Back on Jellyfin's start page (jellyfin_back.py)
                Shortcuts.toggleHomeScreen();
                remoteRestart.restart();
                return;
            }
            if ((action === "voice" || action === "settings") && !root.windowActive)
                Shortcuts.toggleHomeScreen(); // the voice overlay / settings live on the home screen: show it first
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

    property bool youtubeSearch: false // set while a voice search opens YouTube, so it is not reset to its front page

    // media.py leave: pause everything, reset YouTube and Jellyfin to their start page, except keepAppId (being opened).
    function leaveApps(keepAppId) {
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/media.py")) + "' leave " + (keepAppId || ""), () => {});
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

    function openYoutube(mediaArgs) {
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/media.py")) + "' " + mediaArgs, () => {});
        youtubeSearch = true;
        raiseYoutube.restart();
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
    // navigation first and hand it to the overlay only once Back has nothing left to do (start row, first tile).
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
                // Switching to another app pauses whatever plays (Jellyfin keeps playing in the background otherwise)
                // and sends the other apps back to their start page.
                if (!root.appIsActive(app.desktopId))
                    root.leaveApps(app.id);
                // YouTube starts from its front page, unless it is being opened for a voice search.
                if (app.id === "youtube" && !root.appIsActive(app.desktopId) && !root.youtubeSearch
                        && model.isApplicationRunning(app.desktopId))
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/media.py")) + "' youtube-home", () => {});
                root.youtubeSearch = false;
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
            // Wi-Fi, Bluetooth and display for the Settings panel: system.py prints one JSON object.
            Config.systemQuery = (args, callback) => {
                const quoted = args.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
                exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/system.py")) + "' " + quoted, data => {
                    let result = null;
                    try {
                        result = JSON.parse(data.stdout);
                    } catch (e) {
                        result = { error: (data.stderr || data.stdout).trim().slice(-200) || "no answer" };
                    }
                    callback(result);
                });
            };
            // Current output volume for the Settings panel ("Volume: 0.75" or "Volume: 0.75 [MUTED]").
            Config.volumeReader = callback => {
                exec.run("wpctl get-volume @DEFAULT_AUDIO_SINK@", data => {
                    const m = data.stdout.match(/Volume:\s*([\d.]+)/);
                    if (m)
                        callback(Number(m[1]));
                });
            };
            // Actions the home screen cannot do itself (from the keymap or voice).
            Config.system = action => {
                const commands = {
                    "volume_up": "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+",
                    "volume_down": "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
                    "volume_mute": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
                    // Settings panel (logind allows these for the active local user, no password)
                    "sleep": "systemctl suspend",
                    "restart": "systemctl reboot",
                    "shutdown": "systemctl poweroff"
                };
                if (action.startsWith("launch_desktop:")) {
                    // A "More apps" tile: any installed app, by its desktop file (apps.py).
                    Config.launcher({ id: action.slice(15), desktopId: action.slice(15) });
                    return true;
                }
                if (action === "system_settings") {
                    Plasmoid.applicationListModel.runApplication("systemsettings.desktop");
                    return true;
                }
                if (action.startsWith("youtube_watch:")) {
                    // OK on a "New from your channels" tile: VacuumTube plays the video.
                    root.openYoutube("youtube-watch '" + action.slice(14).replace(/[^A-Za-z0-9_-]/g, "") + "'");
                } else if (action.startsWith("youtube_search:") || action === "youtube_history") {
                    // Voice "play <query> on YouTube" / "move YouTube to the TV": VacuumTube opens the search results or
                    // the watch history (media.py pauses other players first); then raise its window, which the
                    // deeplink alone does not do.
                    root.openYoutube(action === "youtube_history" ? "youtube-history"
                                     : "youtube '" + action.slice(15).replace(/'/g, "'\\''") + "'");
                } else if (action === "move_to_tv") {
                    // Voice "move to TV": what plays on another Jellyfin device (phone) stops there and continues
                    // here; with nothing playing on Jellyfin, the YouTube history to pick from. Not started
                    // automatically: YouTube's own previews on its start page land at the top of the history, and the
                    // history's resume positions are rarely the PC's (the PC should use YouTube's "Play on TV").
                    // First only look: Jellyfin must come to the front before the pull, as raising it pauses players.
                    const jellyfin = "python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyfin.py")) + "' ";
                    exec.run(jellyfin + "playing", data => {
                        if (data["exit code"] !== 0 || data.stdout.indexOf('"ok": true') < 0) {
                            root.openYoutube("youtube-history");
                            return;
                        }
                        Config.launch("jellyfin");
                        exec.run(jellyfin + "pull", result => {
                            if (result["exit code"] !== 0 || result.stdout.indexOf('"ok": true') < 0)
                                console.warn("tv: jellyfin.py pull: " + (result.stdout + result.stderr).trim());
                        });
                    });
                } else if (action.startsWith("jellyfin_play:") || action.startsWith("jellyfin_play_id:")) {
                    // Voice "play <title> on Jellyfin" / OK on a Jellyfin tile or the banner: the server starts the
                    // item on Jellyfin Desktop (jellyfin.py waits for it to connect, then for the video to run).
                    // Jellyfin must be in front first: minimized it gets no animation frames and the start page stays
                    // on top of the player. When it already runs, a black "Starting…" curtain hides its start page.
                    const jellyfinApp = Config.apps.find(app => app.id === "jellyfin");
                    const running = Plasmoid.applicationListModel.isApplicationRunning(jellyfinApp.desktopId);
                    const byId = action.startsWith("jellyfin_play_id:");
                    const arg = action.slice(action.indexOf(":") + 1).replace(/'/g, "'\\''");
                    const scripts = "python3 '" + root.localPath(Qt.resolvedUrl("tv/"));
                    const play = () => exec.run(scripts + "jellyfin.py' " + (byId ? "play-id" : "play") + " '" + arg + "'", data => {
                        if (running)
                            exec.run(scripts + "jellyfin_curtain.py' off", () => {});
                        if (data["exit code"] !== 0 || data.stdout.indexOf('"ok": true') < 0)
                            console.warn("tv: jellyfin.py play: " + (data.stdout + data.stderr).trim());
                    });
                    root.leaveApps("jellyfin");
                    if (!running) {
                        Config.launch("jellyfin");
                        play();
                    } else {
                        exec.run(scripts + "jellyfin_curtain.py' on", () => {
                            Config.launch("jellyfin");
                            play();
                        });
                    }
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
            // Back on Jellyfin's start page returns here (runs as long as the home screen does).
            exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyfin_back.py")) + "'", data => {
                console.warn("tv: jellyfin_back.py ended: " + data.stderr.trim().slice(-300));
            });
            // Wake the TV and switch it to this laptop's input (no-op without "tv" in secrets.json).
            root.runScript("tvpower.py on", () => {});
        }
    }
}
