import QtQuick

// Iris as a neon desktop creature: a dark round body with a cyan (left) and magenta
// (right) rim light, two little ears, big blue eyes and tiny feet, on a 20x20 pixel grid.
// The body is a fixed bitmap; eyes, mouth, cheeks and feet are drawn in code per mood.
// `mood`: idle | thinking | talking | happy | sleepy | held (anything else = idle)
// `walking` alternates the feet (`phase` toggles from the host).
Item {
    id: sp

    required property var theme
    property string mood: "idle"
    property bool   walking: false
    property bool   phase: false
    property real   size: 100

    readonly property int grid: 20
    implicitWidth: size
    implicitHeight: size
    property bool talkOpen: false
    property bool blinking: false

    // . transparent · c/B/V/m/M rim (cyan, blue, violet, magenta, purple) · d/h/D body
    // n ear inside · P ear pink · C ear tip · a/z/A faint outer glow
    readonly property var bodyRows: [
        "....CC........CC....",
        "...PnC........CnP...",
        "...Pnn........nnP...",
        "...nnnzzzzzzzAnnn...",
        ".....zBBBBBBBMA.....",
        "....acdhdhdhdhmA....",
        "...acdhdhdhdhdhmA...",
        "..acddddddddddddmA..",
        "..acddddddddddddmA..",
        ".acddddddddddddddmA.",
        ".acddddddddddddddmA.",
        ".acddddddddddddddmA.",
        ".acddddddddddddddmA.",
        "..acddddddddddddmA..",
        "..acddddddddddddmA..",
        "...zVDDDDDDDDDDMA...",
        "....zVVDDDDDDMMA....",
        ".....zzVVVMMMAA.....",
        ".......zzzAAA.......",
        "...................."
    ]

    readonly property var pal: ({
        "c": "#27d8ff", "B": "#3a6bff", "V": "#7a3cff", "m": "#d447ff", "M": "#9b44ff",
        "d": "#1f1740", "h": "#261d4e", "D": "#171132",
        "n": "#2a1f66", "P": "#e65cf5", "C": "#3fe6ff",
        "a": "#0e465f", "z": "#141e5a", "A": "#461960",
        "k": "#0e0a26", "w": "#ffffff", "v": "#6a44ff", "b": "#3b5cff", "e": "#2fe0ff",
        "q": "#c840e8", "u": "#4be0ff", "f": "#0a0618"
    })

    // Pixels [col,row,char] of one eye whose left column is `ex`.
    function eye(ex) {
        const look = sp.mood === "thinking" ? [1, -1] : [0, 0]
        if (sp.mood === "sleepy")                     // closed, curved down
            return [[ex, 11, "e"], [ex + 1, 12, "e"], [ex + 2, 11, "e"]]
        if (sp.blinking)
            return [[ex, 11, "e"], [ex + 1, 11, "e"], [ex + 2, 11, "e"]]
        if (sp.mood === "happy")                      // ^
            return [[ex, 11, "e"], [ex + 1, 10, "e"], [ex + 2, 11, "e"]]
        const out = []
        for (let y = 8; y <= 12; y++) { out.push([ex - 1, y, "k"]); out.push([ex + 3, y, "k"]) }
        for (let x = 0; x < 3; x++) out.push([ex + x, 8, "k"])
        const pat = ["wwv", "wwv", "vvb", "eee"]
        for (let j = 0; j < 4; j++)
            for (let i = 0; i < 3; i++)
                out.push([ex + i + look[0], 9 + j + look[1], pat[j][i]])
        return out
    }

    function mouth() {
        if (sp.mood === "held") return [[9, 13], [10, 13], [9, 14], [10, 14]]
        const open = (sp.mood === "talking" && sp.talkOpen) || sp.mood === "happy"
        if (open) return [[8, 13], [9, 13], [10, 13], [11, 13], [9, 14], [10, 14]]
        return [[8, 13], [11, 13], [9, 14], [10, 14]]    // small smile
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            const p = sp.size / sp.grid
            ctx.reset()

            function px(c, r, ch) {
                const x0 = Math.round(c * p), x1 = Math.round((c + 1) * p)
                const y0 = Math.round(r * p), y1 = Math.round((r + 1) * p)
                ctx.fillStyle = sp.pal[ch]
                ctx.fillRect(x0, y0, x1 - x0, y1 - y0)
            }

            for (let r = 0; r < sp.grid; r++)
                for (let c = 0; c < sp.grid; c++) {
                    const ch = sp.bodyRows[r][c]
                    if (ch !== ".") px(c, r, ch)
                }

            for (const q of sp.eye(5))  px(q[0], q[1], q[2])
            for (const q of sp.eye(12)) px(q[0], q[1], q[2])
            for (const q of sp.mouth()) px(q[0], q[1], "u")

            const cheek = sp.mood === "happy" ? "P" : "q"
            for (const q of [[4, 14], [5, 14], [14, 14], [15, 14]]) px(q[0], q[1], cheek)

            // Feet: both when standing, one at a time when walking
            const leftDown  = !sp.walking || !sp.phase
            const rightDown = !sp.walking || sp.phase
            if (leftDown)  { px(7, 18, "f"); px(8, 18, "f") }
            if (rightDown) { px(11, 18, "f"); px(12, 18, "f") }
        }
    }

    // Glow on the ground
    Rectangle {
        z: -1
        width: sp.size * 0.62; height: sp.size * 0.07; radius: height / 2
        x: (sp.width - width) / 2; y: sp.size * 0.92
        color: "#553b3bff"
    }

    onMoodChanged:     { talkOpen = false; canvas.requestPaint() }
    onWalkingChanged:  canvas.requestPaint()
    onPhaseChanged:    canvas.requestPaint()
    onBlinkingChanged: canvas.requestPaint()

    Timer {
        interval: 170; repeat: true; running: sp.mood === "talking"
        onTriggered: { sp.talkOpen = !sp.talkOpen; canvas.requestPaint() }
    }

    Timer {
        interval: 2600 + Math.random() * 2600; repeat: true; running: true
        onTriggered: { sp.blinking = true; unblink.restart(); interval = 2600 + Math.random() * 2600 }
    }
    Timer { id: unblink; interval: 120; onTriggered: sp.blinking = false }

    // ── Decorations ──────────────────────────────────────────────────
    // Diamond above the head and a few twinkling squares, as in the artwork.
    Rectangle {
        visible: sp.mood !== "sleepy" && sp.mood !== "thinking"
        width: sp.size * 0.09; height: width; rotation: 45
        color: "#3fe6ff"
        x: sp.width / 2 - width / 2; y: -sp.size * 0.12
        SequentialAnimation on y {
            loops: Animation.Infinite
            NumberAnimation { to: -sp.size * 0.16; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { to: -sp.size * 0.11; duration: 1400; easing.type: Easing.InOutSine }
        }
    }
    Repeater {
        model: [ { px: -0.04, py: 0.40, c: "#27d8ff", d: 0 }, { px: 1.0, py: 0.30, c: "#ff4fd8", d: 700 },
                 { px: 0.98, py: 0.58, c: "#ff4fd8", d: 1300 } ]
        delegate: Rectangle {
            required property var modelData
            visible: sp.mood !== "sleepy"
            width: Math.max(3, sp.size * 0.04); height: width
            color: modelData.c
            x: sp.size * modelData.px; y: sp.size * modelData.py
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation { duration: modelData.d }
                NumberAnimation { to: 0.1; duration: 900 }
                NumberAnimation { to: 1.0; duration: 900 }
            }
        }
    }

    // ? while thinking, !! when surprised
    Text {
        visible: sp.mood === "thinking" || sp.mood === "held"
        text: sp.mood === "thinking" ? "?" : "!!"
        color: "#3fe6ff"
        font.family: sp.theme.ff; font.weight: Font.Black
        font.pixelSize: sp.size * 0.24
        x: sp.width * 0.72; y: -sp.size * 0.22
    }

    // Floating z while asleep
    Repeater {
        model: sp.mood === "sleepy" ? 2 : 0
        delegate: Text {
            required property int index
            text: "z"
            color: "#3fe6ff"
            font.family: sp.theme.ff; font.weight: Font.Bold
            font.pixelSize: Math.max(9, sp.size * (0.2 - index * 0.04))
            x: sp.width * 0.68 + index * sp.size * 0.12
            property real rise: 0
            y: sp.height * 0.15 - rise
            opacity: 1 - rise / (sp.size * 0.4)
            SequentialAnimation on rise {
                loops: Animation.Infinite
                PauseAnimation { duration: index * 900 }
                NumberAnimation { from: 0; to: sp.size * 0.4; duration: 1800; easing.type: Easing.OutSine }
            }
        }
    }
}
