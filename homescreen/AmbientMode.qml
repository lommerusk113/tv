import QtQuick
import "."

// Ambient mode: after layout.json "ambientMinutes" without a key on the home screen, full-screen pictures from the
// rows (the tiles' backdrops and the banner) drift slowly and cross-fade, with the title, a big clock and the weather.
// Home.qml opens it (idle timer) and closes it on the next key, which does nothing else. Also keeps a TV from
// showing the same still picture for hours.
Item {
    id: ambient
    property bool open: false
    property var slides: []
    property int at: 0
    property int front: 0
    readonly property var theme: Config.theme
    readonly property var current: slides.length ? slides[at % slides.length] : null

    function show() {
        slides = collect();
        if (!slides.length)
            return;
        at = 0;
        load(slides[0]);
        open = true;
    }

    // Every tile with a wide picture, and the banner, without repeats, shuffled.
    function collect() {
        const seen = {};
        const out = [];
        for (const key in Config.content) {
            const items = Config.content[key];
            if (!Array.isArray(items))
                continue;
            for (const item of items) {
                const picture = item && (item.backdrop || (key.indexOf("Featured") >= 0 ? item.image : ""));
                if (!picture || seen[picture] || String(picture).indexOf("placeholder") >= 0)
                    continue;
                seen[picture] = true;
                out.push({ picture: picture, title: item.title || "", meta: item.meta || item.subtitle || "",
                           logo: item.logo || "" });
            }
        }
        for (let i = out.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1));
            [out[i], out[j]] = [out[j], out[i]];
        }
        return out;
    }

    function load(slide) {
        const back = front === 0 ? pic1 : pic0;
        back.source = slide.picture;
    }

    Timer {
        interval: 15000
        repeat: true
        running: ambient.open && ambient.slides.length > 1
        onTriggered: {
            ambient.at = (ambient.at + 1) % ambient.slides.length;
            ambient.load(ambient.slides[ambient.at]);
        }
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 1200; easing.type: Easing.InOutQuad } }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // Each picture drifts (slow zoom and pan, Ken Burns) while it is in front.
    component Slide: Image {
        id: pic
        required property int slot
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        opacity: ambient.front === slot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 2500; easing.type: Easing.InOutQuad } }
        onStatusChanged: {
            if (status !== Image.Ready)
                return;
            ambient.front = slot;
            drift.restart();
        }
        transform: [
            Scale { id: zoom; origin.x: pic.width / 2; origin.y: pic.height / 2 },
            Translate { id: pan }
        ]
        ParallelAnimation {
            id: drift
            NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 1.0; to: 1.12; duration: 20000 }
            NumberAnimation { target: pan; property: "x"; from: 0; to: (pic.slot ? -1 : 1) * Config.px(60); duration: 20000 }
        }
    }
    Slide { id: pic0; slot: 0 }
    Slide { id: pic1; slot: 1 }

    // Shade bottom-left (title) and top-right (clock).
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#66000000" }
            GradientStop { position: 0.35; color: "#00000000" }
            GradientStop { position: 0.65; color: "#00000000" }
            GradientStop { position: 1.0; color: "#b3000000" }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Config.px(96)
        anchors.bottomMargin: Config.px(88)
        width: Config.px(1100)
        spacing: Config.px(8)
        Image {
            visible: !!ambient.current && ambient.current.logo !== "" && status === Image.Ready
            width: Math.min(Config.px(520), implicitWidth)
            height: Config.px(130)
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            source: ambient.current ? ambient.current.logo : ""
        }
        Text {
            visible: !ambient.current || !ambient.current.logo
            width: parent.width
            text: ambient.current ? ambient.current.title : ""
            elide: Text.ElideRight
            color: "#ffffff"
            font.family: ambient.theme.font.family
            font.pixelSize: Config.px(48)
            font.weight: Font.Bold
            style: Text.Raised
            styleColor: "#80000000"
        }
        Text {
            text: ambient.current ? ambient.current.meta : ""
            color: "#e6ffffff"
            font.family: ambient.theme.font.family
            font.pixelSize: Config.px(24)
            style: Text.Raised
            styleColor: "#80000000"
        }
    }

    Column {
        id: clock
        property date now: new Date()
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Config.px(96)
        anchors.topMargin: Config.px(72)
        Text {
            anchors.right: parent.right
            text: Qt.formatTime(clock.now, "HH:mm")
            color: "#ffffff"
            font.family: ambient.theme.font.family
            font.pixelSize: Config.px(120)
            font.weight: Font.Light
            style: Text.Raised
            styleColor: "#80000000"
        }
        Text {
            anchors.right: parent.right
            text: Qt.locale("en_GB").toString(clock.now, "dddd d MMMM")
                  + (Config.weather ? "  ·  " + Config.weather.temperature + "°" : "")
            color: "#e6ffffff"
            font.family: ambient.theme.font.family
            font.pixelSize: Config.px(30)
            style: Text.Raised
            styleColor: "#80000000"
        }
        Timer {
            interval: 10000
            repeat: true
            running: ambient.open
            triggeredOnStart: true
            onTriggered: clock.now = new Date()
        }
    }
}
