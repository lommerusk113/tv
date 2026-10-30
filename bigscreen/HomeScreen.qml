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
import org.kde.layershell as LayerShell

import "tv"

Item {
    id: root

    // Read by upstream main.qml (wallpaper blur and scrim). Our page is opaque, so neither is needed.
    readonly property bool blurBackground: false
    readonly property bool darkenBackground: false

    // Whenever the home screen is active again (start, or back from an app): take key focus and refresh
    // the rows (Trakt recommendations, TMDb, Jellyfin, YouTube channels) and the weather.
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: {
        if (!windowActive)
            return;
        tv.forceActiveFocus();
        // Trakt recommendations on the Jellyfin server, then the ones that are not ("Get more", via Jellyseerr).
        runScript("recommend.py", () => {
            tv.reloadLive();
            root.runScript("jellyseerr.py", tv.reloadLive);
        });
        runScript("tmdb.py", tv.reloadLive);
        runScript("jellyfin.py", tv.reloadLive);
        runScript("youtube.py", tv.reloadLive);
        runScript("location.py", () => runScript("weather.py", tv.reloadWeather));  // location: daily, if switched on
        runScript("audio.py auto", () => {});
    }

    // Sound follows the TV: WirePlumber keeps the laptop speaker as default after the TV is plugged in (audio.py).
    Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.runScript("audio.py auto", () => {})
    }

    // Home Page is Bigscreen's global "Toggle Bigscreen Home Screen" shortcut: upstream main.qml minimizes all apps,
    // and the key never reaches TvHome. Also reset the home screen, like the keymap's "home" action does in the prototype.
    Connections {
        target: Shortcuts
        function onToggleHomeScreen() {
            textEntry.open = false;
            root.cancelStream();  // Home while a stream starts: give up on it (media.py leave closes Moonlight)
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
        // An app closed by itself (Moonlight via the red button, a dropped stream, a crash): if no other window has
        // the focus now, take it, or the remote's keys go nowhere until something is clicked (seen 2026-10-29).
        onRowsRemoved: focusCheck.restart()
    }

    Timer {
        id: focusCheck
        interval: 400
        onTriggered: {
            for (let i = 0; i < appWindows.count; ++i)
                if (appWindows.data(appWindows.makeModelIndex(i), TaskManager.AbstractTasksModel.IsActive))
                    return;  // an app still has the focus: leave it
            tv.forceActiveFocus();
            if (root.Window.window)
                root.Window.window.requestActivate();
        }
    }

    Instantiator {
        model: appWindows
        delegate: QtObject {
            required property int index
            required property var model

            // AppId is the desktop file name, e.g. "rocks.shy.VacuumTube.desktop" (".desktop" stripped on both sides to be safe).
            // Moonlight is left out: it goes fullscreen itself, and toggling would bring its hidden windows forward
            // while a stream starts (startStream).
            readonly property bool ours: String(model.AppId).indexOf("moonlight_stream") < 0 && Config.apps.some(app => app.desktopId
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

    // Voice while an app is in front: listen and act without going to the home screen (which would pause the app).
    // The same voice card as on the home screen, in an overlay-layer window (layer-shell: above fullscreen apps,
    // never takes the keyboard). Only actions that need the home screen itself (home, settings, request dialog) show it.
    function voiceInApp() {
        appVoice.show("listening", "");
        Config.voiceListener(result => {
            const action = result ? result.action : null;
            if (result && !action && result.options && result.options.length) {
                appVoice.hide();  // "Did you mean…?" needs the arrows: on the home screen
                Shortcuts.toggleHomeScreen();
                tv.showChoices(result.text, result.options);
                return;
            }
            if (!result)
                appVoice.show("error", "");
            else if (result.say)
                appVoice.show("message", result.say);
            else
                appVoice.show(action ? "heard" : "unknown", result.text);
            if (!action)
                return;
            // Apps that live on the home screen (Settings, Jellyseerr) need it in front too.
            const builtIn = action.startsWith("launch:") && Config.apps.some(a => a.id === action.slice(7) && a.action);
            if (action === "home" || action === "settings" || action.startsWith("request:") || builtIn) {
                appVoice.hide();
                Shortcuts.toggleHomeScreen();
                if (action === "home")
                    return;
            }
            tv.runAction(action);
        });
    }

    Window {
        id: appVoiceWindow
        LayerShell.Window.scope: "tv-voice"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorBottom
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
        LayerShell.Window.exclusionZone: -1
        width: Config.px(1300)
        height: Config.px(280)
        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        visible: appVoice.visible

        VoiceOverlay {
            id: appVoice
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Config.px(72)
        }
    }

    // On-screen keyboard over an app (osk.py, TextEntry.qml): OK on a text field in Jellyseerr or Jellyfin opens it.
    // The overlay window takes the keyboard while open (layer-shell exclusive), so the remote drives it, not the app.
    // Text goes into the field as it is typed, one `osk.py set` at a time (the newest text wins); the done key sends
    // Enter after the last one.
    property var keyboardPending: null
    property bool keyboardBusy: false
    property bool keyboardSubmit: false

    function keyboardFlush() {
        if (keyboardBusy)
            return;
        const osk = "python3 '" + localPath(Qt.resolvedUrl("tv/osk.py")) + "' ";
        const done = data => {
            if (data["exit code"] !== 0)
                console.warn("tv: osk.py: " + data.stderr.trim());
            keyboardBusy = false;
            keyboardFlush();
        };
        if (keyboardPending !== null) {
            const text = encodeURIComponent(keyboardPending).replace(/'/g, "%27");
            keyboardPending = null;
            keyboardBusy = true;
            exec.run(osk + "set " + textEntry.app + " '" + text + "'", done);
        } else if (keyboardSubmit) {
            keyboardSubmit = false;
            keyboardBusy = true;
            exec.run(osk + "enter " + textEntry.app, done);
        }
    }

    Window {
        id: keyboardWindow
        LayerShell.Window.scope: "tv-keyboard"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorBottom
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
        LayerShell.Window.exclusionZone: -1
        width: Config.px(1440)
        height: Config.px(720)
        color: "transparent"
        flags: Qt.FramelessWindowHint
        visible: textEntry.visible
        onVisibleChanged: if (visible) requestActivate()

        TextEntry {
            id: textEntry
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => key(event)
            onEdited: text => {
                root.keyboardPending = text;
                root.keyboardFlush();
            }
            onSubmitted: {
                open = false;
                root.keyboardSubmit = true;
                root.keyboardFlush();
            }
        }
    }

    // Global remote buttons (config/remote.json, shortcuts installed by `remote.py install`) work inside apps too:
    // remote.py send hands the action over through `remote.py wait`, which is rerun after every action.
    function waitForRemote() {
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/remote.py")) + "' wait", data => {
            const action = data.stdout.trim();
            if (action.startsWith("keyboard:")) { // OK on a text field in an app (osk.py watch)
                const [, app, field] = action.match(/^keyboard:([^:]+):(.*)$/) || [];
                try {
                    if (app && !root.windowActive)
                        textEntry.show(app, JSON.parse(decodeURIComponent(field)));
                } catch (e) {
                    console.warn("tv: keyboard: " + e);
                }
                remoteRestart.restart();
                return;
            }
            if (action === "show_home") { // Back on Jellyfin's start page (jellyfin_back.py)
                Shortcuts.toggleHomeScreen();
                remoteRestart.restart();
                return;
            }
            if (action === "voice" && !root.windowActive)
                root.voiceInApp();  // stay in the app: feedback in Plasma's on-screen popup
            else if (action === "settings" && !root.windowActive) {
                Shortcuts.toggleHomeScreen(); // the settings panel lives on the home screen: show it first
                tv.runAction(action);
            } else if (action)
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

    // Moonlight stream start: our loading screen stays up and Moonlight's own windows are kept minimized
    // (kwin/hide-moonlight.js) until moonlight.py --wait sees the first picture; then Moonlight comes forward.
    property bool streamStarting: false

    function startStream(app) {
        const tvdir = "python3 '" + localPath(Qt.resolvedUrl("tv/"));
        const moonlightApp = Config.apps.find(a => a.id === "moonlight");
        leaveApps("moonlight");
        streamStarting = true;
        tv.showLoading(app || "Moonlight");
        exec.run(tvdir + "kwin_script.py' load hide-moonlight", () => {
            exec.run(tvdir + "moonlight.py' stream" + (app ? " '" + app.replace(/'/g, "'\\''") + "'" : "") + " --wait", data => {
                if (!streamStarting)
                    return;  // cancelled meanwhile
                streamStarting = false;
                exec.run(tvdir + "kwin_script.py' unload hide-moonlight", () => {
                    if (data["exit code"] === 0) {
                        exec.run(tvdir + "kwin_script.py' once show-moonlight", () => {
                            streamShown.restart();
                            exec.run(tvdir + "moonlight.py' wake", () => {});  // Steam's screensaver ignores keys
                        });
                        return;
                    }
                    tv.hideLoading();
                    const reason = data.stderr.trim().split("\n").pop().replace(/^moonlight: /, "");
                    if (reason.indexOf("no host paired") >= 0) {
                        Plasmoid.applicationListModel.runApplication(moonlightApp.desktopId);  // plain Moonlight
                        return;
                    }
                    exec.run("flatpak kill com.moonlight_stream.Moonlight", () => {});
                    tv.showMessage(reason || "The game stream did not start");
                });
            });
        });
    }

    function cancelStream() {
        if (!streamStarting)
            return tv.hideLoading();
        streamStarting = false;
        tv.hideLoading();
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/kwin_script.py")) + "' unload hide-moonlight", () => {});
        exec.run("python3 '" + localPath(Qt.resolvedUrl("tv/moonlight.py")) + "' cancel", () => {});  // no retry
    }

    // Lets Moonlight's stream window cover the screen before the loading screen fades out.
    Timer {
        id: streamShown
        interval: 600
        onTriggered: tv.hideLoading()
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
                // Moonlight with a paired PC: straight into the configured app (moonlight.py stream) instead of
                // Moonlight's PC-style host list; without a host (exit code 1) it opens normally.
                if (app.id === "moonlight" && !model.isApplicationRunning(app.desktopId)) {
                    root.startStream("");  // falls back to opening Moonlight when no host is paired
                    return;
                }
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
            Config.seerrQuery = (args, callback) => {
                const quoted = args.map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
                exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyseerr.py")) + "' " + quoted, data => {
                    let result = null;
                    try {
                        result = JSON.parse(data.stdout);
                    } catch (e) {
                        console.warn("tv: jellyseerr.py " + args.join(" ") + ": " + data.stderr.trim().slice(-200));
                    }
                    callback(result);
                });
            };
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
                if (action.startsWith("moonlight_stream:")) {
                    root.startStream(action.slice(17));
                    return true;
                }
                if (action === "moonlight_cancel") {
                    root.cancelStream();
                    return true;
                }
                if (action === "moonlight_quit") {  // red button: end the stream, back here
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/moonlight.py")) + "' quit", () => {});
                    return true;
                }
                if (action.startsWith("save_app_order:")) {
                    // The "Your apps" row after moving a tile (Home.qml): kept in ~/.config/tv-project/app-order.json.
                    root.runScript("apps.py order " + action.slice(15).replace(/[^A-Za-z0-9_,.-]/g, ""), () => {});
                    return true;
                }
                if (action.startsWith("request_search:")) {
                    // A title that is not on Jellyfin (voice): Jellyseerr's hits in GetDialog, OK downloads one.
                    // The dialog needs the arrows, so the home screen comes to the front first.
                    const query = action.slice(15);
                    appVoice.hide();
                    if (!root.windowActive)
                        Shortcuts.toggleHomeScreen();
                    tv.showStatus("Looking for “" + query + "”…");
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyseerr.py")) + "' search '"
                             + query.replace(/'/g, "'\\''") + "'", data => {
                        tv.showStatus("");
                        let res = null;
                        try {
                            res = JSON.parse(data.stdout);
                        } catch (e) {}
                        if (res && res.ok && res.results.length)
                            tv.showGetDialog(res);
                        else {
                            tv.showMessage("Couldn't find “" + query + "” anywhere");
                            console.warn("tv: jellyseerr.py search: " + (data.stdout + data.stderr).trim().slice(-300));
                        }
                    });
                    return true;
                }
                if (action.startsWith("jellyseerr_request:")) {
                    // "Get more" tile, confirmed in RequestDialog: Jellyseerr requests it (Sonarr/Radarr download it).
                    const [, kind, tmdb, ...rest] = action.split(":");
                    const title = rest.join(":");
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyseerr.py")) + "' request "
                             + (kind === "tv" ? "tv" : "movie") + " " + tmdb.replace(/[^0-9]/g, ""), data => {
                        let res = null;
                        try {
                            res = JSON.parse(data.stdout);
                        } catch (e) {}
                        if (res && res.ok) {
                            tv.showMessage("Requested “" + title + "”");
                            root.runScript("jellyseerr.py", tv.reloadLive);  // the tile now says "Requested"
                        } else {
                            tv.showMessage("Could not request “" + title + "”");
                            console.warn("tv: jellyseerr.py request: " + (data.stdout + data.stderr).trim());
                        }
                    });
                    return true;
                }
                if (action.startsWith("launch_desktop:")) {
                    // A "More apps" tile: any installed app, by its desktop file (apps.py).
                    Config.launcher({ id: action.slice(15), desktopId: action.slice(15) });
                    return true;
                }
                if (action === "weather_refresh") {  // Settings > Use my location
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/weather.py")) + "'", () => tv.reloadWeather());
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
                } else if (action.startsWith("jellyfin_search:")) {
                    // Voice "search for X": Jellyfin's search page with X typed in (its letter row edits it further).
                    root.leaveApps("jellyfin");
                    Config.launch("jellyfin");
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyfin_nav.py")) + "' search '"
                             + action.slice(16).replace(/'/g, "'\\''") + "'", data => {
                        if (data["exit code"] !== 0)
                            console.warn("tv: jellyfin_nav.py: " + data.stderr.trim());
                    });
                } else if (action.startsWith("jellyfin_play:")) {
                    // Voice "play <title> on Jellyfin": look the title up first, so it gets the same loading screen
                    // (with its picture) as a tile; nothing found = a message instead of silence.
                    const title = action.slice(14);
                    exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/jellyfin.py")) + "' find '"
                             + title.replace(/'/g, "'\\''") + "'", data => {
                        let found = null;
                        try {
                            found = JSON.parse(data.stdout);
                        } catch (e) {}
                        if (found && found.ok)
                            tv.runAction("jellyfin_play_id:" + found.id);
                        else  // not on the server: offer to download it
                            Config.system("request_search:" + title);
                    });
                } else if (action.startsWith("jellyfin_play_id:")) {
                    // OK on a Jellyfin tile or the banner (and voice, after the lookup above): the server starts the
                    // item on Jellyfin Desktop (jellyfin.py waits for it to connect, then for the video to run).
                    // Jellyfin must be in front first: minimized it gets no animation frames and the start page stays
                    // on top of the player. A loading screen (jellyfin_curtain.py) covers its page meanwhile; on a
                    // cold start it waits for the page to come up.
                    const jellyfinApp = Config.apps.find(app => app.id === "jellyfin");
                    const running = Plasmoid.applicationListModel.isApplicationRunning(jellyfinApp.desktopId);
                    const id = action.slice(17).replace(/[^A-Za-z0-9]/g, "");
                    const scripts = "python3 '" + root.localPath(Qt.resolvedUrl("tv/"));
                    const play = () => exec.run(scripts + "jellyfin.py' play-id " + id, data => {
                        exec.run(scripts + "jellyfin_curtain.py' off", () => {});
                        if (data["exit code"] !== 0 || data.stdout.indexOf('"ok": true') < 0) {
                            console.warn("tv: jellyfin.py play: " + (data.stdout + data.stderr).trim());
                            tv.showMessage("Could not start it on Jellyfin");
                        }
                    });
                    root.leaveApps("jellyfin");
                    if (!running) {
                        Config.launch("jellyfin");
                        exec.run(scripts + "jellyfin_curtain.py' on " + id + " --wait", play);
                    } else {
                        exec.run(scripts + "jellyfin_curtain.py' on " + id, () => {
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
            // OK on a text field in Jellyseerr/Jellyfin opens the on-screen keyboard (runs as long as the home screen does).
            exec.run("python3 '" + root.localPath(Qt.resolvedUrl("tv/osk.py")) + "' watch", data => {
                console.warn("tv: osk.py watch ended: " + data.stderr.trim().slice(-300));
            });
            // Wake the TV and switch it to this laptop's input (no-op without "tv" in secrets.json).
            root.runScript("tvpower.py on", () => {});
        }
    }
}
