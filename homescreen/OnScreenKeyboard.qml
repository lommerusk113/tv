import QtQuick
import "."

// Remote-friendly keyboard: arrows move over the keys, OK presses one. Used where no app keyboard exists (the Wi-Fi
// password in SettingsPanel). The owner routes up/down/left/right/select to handle() and reacts to the signals.
// Plasma's own virtual keyboard cannot be reached with arrow keys (they go to the app), so it is no help on a TV.
Item {
    id: kb
    property int row: 0
    property int col: 0
    property bool shift: false
    property bool symbols: false
    property bool focused: true
    property string doneLabel: "OK"
    readonly property var theme: Config.theme

    signal typed(string text)
    signal backspace()
    signal done()

    readonly property var letters: [
        "1234567890".split(""),
        "qwertyuiop".split(""),
        "asdfghjklæ".split(""),
        "zxcvbnmøå.".split("")
    ]
    readonly property var signs: [
        "1234567890".split(""),
        "!@#$%&*()-".split(""),
        "_=+[]{};:'".split(""),
        "\"<>/?\\|~,.".split("")
    ]
    // Bottom row: special keys, each with a width in key units (10 units per row).
    readonly property var specials: [
        { key: "shift", label: "⇧", span: 2 },
        { key: "symbols", label: "#+=", span: 2 },
        { key: "space", label: "Space", span: 3 },
        { key: "back", label: "⌫", span: 1 },
        { key: "done", label: kb.doneLabel, span: 2 }
    ]
    readonly property var grid: symbols ? signs : letters
    readonly property real unit: (width - Config.px(8) * 9) / 10
    readonly property real keyHeight: Config.px(58)

    implicitHeight: keyHeight * 5 + Config.px(8) * 4

    function label(k) {
        return shift && !symbols ? k.toUpperCase() : k;
    }

    // Column of the special key under unit column c, and back.
    function specialAt(c) {
        let at = 0;
        for (let i = 0; i < specials.length; ++i) {
            at += specials[i].span;
            if (c < at)
                return i;
        }
        return specials.length - 1;
    }
    function unitOf(i) {
        let at = 0;
        for (let j = 0; j < i; ++j)
            at += specials[j].span;
        return at;
    }

    function handle(action) {
        switch (action) {
        case "left": col = Math.max(0, col - 1); return true;
        case "right": col = Math.min(row === 4 ? specials.length - 1 : 9, col + 1); return true;
        case "up":
            if (row === 0)
                return false;  // leave the keyboard upwards
            if (row === 4)
                col = Math.min(9, unitOf(col));
            --row;
            return true;
        case "down":
            if (row === 4)
                return false;
            if (row === 3)
                col = specialAt(col);
            ++row;
            return true;
        case "select":
            press();
            return true;
        }
        return false;
    }

    function press() {
        if (row < 4) {
            typed(label(grid[row][col]));
            if (shift)
                shift = false;  // one capital, like a phone
            return;
        }
        switch (specials[col].key) {
        case "shift": shift = !shift; break;
        case "symbols": symbols = !symbols; break;
        case "space": typed(" "); break;
        case "back": backspace(); break;
        case "done": done(); break;
        }
    }

    component Key: Rectangle {
        id: key
        property string text
        property bool on
        property bool lit
        height: kb.keyHeight
        radius: Config.px(12)
        color: on ? kb.theme.colors.focusBorder
               : lit ? Config.withAlpha(kb.theme.colors.accent, 0.35) : Config.withAlpha(kb.theme.colors.text, 0.08)
        scale: on ? 1.08 : 1
        z: on ? 1 : 0
        Behavior on scale { NumberAnimation { duration: kb.theme.animationMs } }
        Text {
            anchors.centerIn: parent
            text: key.text
            color: key.on ? kb.theme.colors.onFocused : kb.theme.colors.text
            font.family: kb.theme.font.family
            font.pixelSize: Config.px(key.text.length > 1 ? 20 : 26)
            font.weight: Font.DemiBold
        }
    }

    Column {
        spacing: Config.px(8)
        Repeater {
            model: 4
            delegate: Row {
                id: keyRow
                required property int index
                spacing: Config.px(8)
                Repeater {
                    model: kb.grid[keyRow.index]
                    delegate: Key {
                        required property string modelData
                        required property int index
                        width: kb.unit
                        text: kb.label(modelData)
                        on: kb.focused && kb.row === keyRow.index && kb.col === index
                    }
                }
            }
        }
        Row {
            spacing: Config.px(8)
            Repeater {
                model: kb.specials
                delegate: Key {
                    required property var modelData
                    required property int index
                    width: kb.unit * modelData.span + Config.px(8) * (modelData.span - 1)
                    text: modelData.label
                    lit: modelData.key === "shift" && kb.shift || modelData.key === "symbols" && kb.symbols
                         || modelData.key === "done"
                    on: kb.focused && kb.row === 4 && kb.col === index
                }
            }
        }
    }
}
