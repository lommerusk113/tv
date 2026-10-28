// Replaces contents/ui/HomeScreen.qml of the stock org.kde.bigscreen.homescreen plasmoid (6.7.5).
// Everything else in that package stays upstream; scripts/install-bigscreen.sh puts this file in place
// and links homescreen/ next to it as contents/ui/tv.
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.bigscreen as Bigscreen

import "tv"

Item {
    id: root

    // Read by upstream main.qml (wallpaper blur and scrim). Our page is opaque, so neither is needed.
    readonly property bool blurBackground: false
    readonly property bool darkenBackground: false

    // Give the home screen key focus whenever its window is active again (e.g. after an app closes).
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: if (windowActive) tv.forceActiveFocus()

    // Upstream main.qml opens the Bigscreen overlay (tasks, search, settings) on Back. Let Home use Back for its own
    // navigation first and hand it to the overlay only once focus is on the tabs.
    Binding {
        target: root.parent.Bigscreen.BackHandler
        property: "enabled"
        value: tv.atTop
    }

    // plasmashell has no QML_XHR_ALLOW_FILE_READ, so read the JSON files with cat instead.
    P5Support.DataSource {
        id: exec
        engine: "executable"
        property var callbacks: ({})

        onNewData: (source, data) => {
            const callback = callbacks[source];
            delete callbacks[source];
            disconnectSource(source);
            if (data["exit code"] !== 0)
                console.error("tv: " + source + " failed: " + data.stderr);
            callback(data.stdout);
        }
    }

    TvHome {
        id: tv
        anchors.fill: parent
        focus: true

        readFile: function (url, callback) {
            const cmd = "cat '" + decodeURIComponent(url.toString().replace("file://", "")) + "'";
            exec.callbacks[cmd] = callback;
            exec.connectSource(cmd);
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
