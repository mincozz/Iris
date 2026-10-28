import QtQuick

// Iris's avatar: a little pixel-art blob with two big eyes, drawn on a Canvas.
// `mood` drives the animation:
//   "idle"     — soft float, blinks
//   "thinking" — sparkles orbit around her
//   "talking"  — the mouth opens and closes, with a small bounce
//   "happy"    — ^ ^ eyes, a grin, a little hop (after a finished reply)
//   "sleepy"   — eyes shut, slow float, floating "z" (long idle)
// Any other value behaves like "idle", so an older host never breaks.
Item {
    id: av

    required property var theme
    property string mood: "idle"
    property real   size: 64

    readonly property int cols: 16
    readonly property int rows: 12
    implicitWidth:  size
    implicitHeight: size * rows / cols
    property bool talkOpen: false

    // Left half (8 columns), mirrored to 16. . transparent · o outline · L light
    // b body · S shade · w eye white · k dark · p cheek · m mouth
    readonly property var halfRows: [
        "...ooooo",
        "..oLLLbb",
        ".oLLbbbb",
        ".oLbbbbb",
        "oLbbbbbb",
        "obwkbbbb",
        "obkkbbbb",
        "obbbbbbb",
        "opbbbbmm",
        "obbbbbSS",
        "oSbbbSSS",
        "oooooooo"
    ]

    readonly property var pal: ({
        "o": "#1d1326",
        "L": Qt.lighter(av.theme.primary, 1.45),
        "b": av.theme.primary,
        "S": Qt.darker(av.theme.primary, 1.35),
        "w": "#ffffff",
        "k": "#1d1326",
        "p": "#f09aa6",
        "m": "#1d1326"
    })

    // ── Gentle float ──────────────────────────────────────────────────
    property real floatY: 0
    SequentialAnimation on floatY {
        loops: Animation.Infinite
        NumberAnimation { to: -av.size * 0.03; duration: av.mood === "thinking" ? 450 : av.mood === "sleepy" ? 2600 : 1600; easing.type: Easing.InOutSine }
        NumberAnimation { to:  av.size * 0.01; duration: av.mood === "thinking" ? 450 : av.mood === "sleepy" ? 2600 : 1600; easing.type: Easing.InOutSine }
    }

    // ── Hop when happy ───────────────────────────────────────────────
    property real hopY: 0
    SequentialAnimation on hopY {
        running: av.mood === "happy"
        loops: Animation.Infinite
        onRunningChanged: if (!running) av.hopY = 0
        NumberAnimation { to: -av.size * 0.12; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0;               duration: 170; easing.type: Easing.InQuad }
        PauseAnimation  { duration: 140 }
    }

    // ── Blob ─────────────────────────────────────────────────────────
    Canvas {
        id: canvas
        width: av.size
        height: av.implicitHeight
        x: (av.width - width) / 2
        y: (av.height - height) / 2 + av.floatY + av.hopY

        transformOrigin: Item.Bottom
        SequentialAnimation on scale {
            running: av.mood === "talking"
            loops: Animation.Infinite
            NumberAnimation { to: 1.04; duration: 160; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 160; easing.type: Easing.InOutSine }
        }

        onPaint: {
            const ctx = getContext("2d")
            const p = av.size / av.cols
            ctx.reset()

            for (let r = 0; r < av.rows; r++) {
                for (let c = 0; c < av.cols; c++) {
                    let ch = av.halfRows[r][c < av.cols / 2 ? c : av.cols - 1 - c]
                    if (ch === ".") continue

                    const eye = c === 2 || c === 3 || c === 12 || c === 13
                    if (eye && (blink.closed || av.mood === "sleepy")) ch = r === 5 ? "b" : (r === 6 ? "k" : ch)
                    if (eye && av.mood === "happy") ch = r === 5 ? "k" : (r === 6 ? "b" : ch)   // ^ ^
                    if (av.mood === "happy" && r === 7 && (c === 1 || c === 14)) ch = "p"       // blush
                    if (((av.mood === "talking" && av.talkOpen) || av.mood === "happy")
                            && (r === 8 || r === 9) && c >= 6 && c <= 9)
                        ch = "m"

                    const x0 = Math.round(c * p), x1 = Math.round((c + 1) * p)
                    const y0 = Math.round(r * p), y1 = Math.round((r + 1) * p)
                    ctx.fillStyle = av.pal[ch]
                    ctx.fillRect(x0, y0, x1 - x0, y1 - y0)
                }
            }
        }
    }

    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: canvas.requestPaint()
    }

    // ── Mouth while talking ──────────────────────────────────────────
    Timer {
        interval: 170; repeat: true; running: av.mood === "talking"
        onTriggered: av.talkOpen = !av.talkOpen
    }
    onMoodChanged: { talkOpen = false; canvas.requestPaint() }

    // ── Sparkles orbiting while thinking ─────────────────────────────
    Item {
        anchors.fill: parent
        visible: av.mood === "thinking"
        RotationAnimation on rotation {
            running: av.mood === "thinking"
            loops: Animation.Infinite
            from: 0; to: 360; duration: 1800
        }
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                readonly property real a: index * 2 * Math.PI / 3
                width: Math.max(2, av.size * 0.07); height: width
                color: index === 1 ? av.theme.secondary : "#ffffff"
                x: av.width / 2 + Math.cos(a) * av.size * 0.5 - width / 2
                y: av.implicitHeight / 2 + Math.sin(a) * av.size * 0.3 - height / 2
            }
        }
    }

    // ── Floating z while sleepy ──────────────────────────────────────
    Repeater {
        model: av.mood === "sleepy" ? 2 : 0
        delegate: Text {
            required property int index
            text: "z"
            color: av.theme.txt2
            font.family: av.theme.ff; font.weight: Font.Bold
            font.pixelSize: Math.max(7, av.size * (0.2 - index * 0.04))
            x: av.width * 0.68 + index * av.size * 0.12
            property real rise: 0
            y: av.height * 0.2 - rise
            opacity: 1 - rise / (av.size * 0.4)
            SequentialAnimation on rise {
                loops: Animation.Infinite
                PauseAnimation { duration: index * 900 }
                NumberAnimation { from: 0; to: av.size * 0.4; duration: 1800; easing.type: Easing.OutSine }
            }
        }
    }

    // ── Blink ────────────────────────────────────────────────────────
    QtObject { id: blink; property bool closed: false }
    Timer {
        interval: 2600 + Math.random() * 2600; repeat: true; running: true
        onTriggered: {
            blink.closed = true
            unblink.restart()
            interval = 2600 + Math.random() * 2600
        }
    }
    Timer { id: unblink; interval: 120; onTriggered: blink.closed = false }
}
