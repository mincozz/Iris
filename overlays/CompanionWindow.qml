import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "CompanionPhrases.js" as Phrases

// Iris as a desktop companion: she walks on the floor and on top of windows,
// sits, sleeps, comes over when the cursor is far away, hops when a reply is
// done, can be petted (click), carried (drag) and opens the chat (double-click).
// The window is full screen and transparent; its input mask is the sprite only.
// Window titles and classes from `hyprctl clients` are never kept, only rectangles.
PanelWindow {
    id: win

    property var shellRoot: null     // optional: assistantMood, openAssistant()
    required property var theme
    property bool active: false

    visible: active
    WlrLayershell.namespace: "quickshell-companion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {
        item: sprite
        Region { item: bubbleBox }
    }

    // ── Tunables ─────────────────────────────────────────────────────
    readonly property real spriteSize: 100
    readonly property real groundOffset: 0      // lift the floor (e.g. a bottom bar)
    readonly property real walkSpeed: 150
    readonly property real maxJump: 1400

    // ── State ────────────────────────────────────────────────────────
    // idle | walk | sit | sleep | happy | held | fall | jump
    property string st: "idle"
    property real px: 0                 // feet, window coordinates
    property real py: 0
    property real vx: 0
    property real vy: 0
    property int  dir: 1
    property real stT: 2
    property real target: -1            // x to reach while walking, -1 = none
    property bool inited: false
    property var  supports: []          // window tops: {x1, x2, y}
    property real jt: 0
    property real jx0: 0; property real jy0: 0; property real jx1: 0; property real jy1: 0
    property real jh: 60; property real jd: 0.6

    // Reactions
    property string bubbleText: ""
    property real   lastSay: 0
    property real   lastFocusGo: 0
    property string focusAddr: ""
    property bool   pendingFocus: false
    property bool   alertGo: false

    readonly property string busy: (shellRoot && shellRoot.assistantMood && shellRoot.assistantMood !== "idle")
                                   ? shellRoot.assistantMood : ""
    property bool stepPhase: false
    Timer { interval: 140; repeat: true; running: win.st === "walk"; onTriggered: win.stepPhase = !win.stepPhase }

    readonly property string mood: st === "happy" ? "happy"
                                 : st === "sleep" ? "sleepy"
                                 : (st === "held" || st === "fall") ? "held"
                                 : busy !== ""    ? busy : "idle"
    readonly property bool grounded: st === "idle" || st === "walk" || st === "sit" || st === "sleep" || st === "happy"

    onActiveChanged: if (!active) inited = false

    onBusyChanged: {
        if (!grounded) return
        if (busy !== "") { enter("sit"); stT = 3600 }
        else enter("happy")
    }

    // ── Geometry ─────────────────────────────────────────────────────
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }

    function allSupports() {
        return [{ x1: 0, x2: width, y: height - groundOffset, ground: true }].concat(supports)
    }

    // Nearest support at or below `y` (within `tol` above) that contains x.
    function supportAt(x, y, tol) {
        let best = null
        for (const s of allSupports()) {
            if (x < s.x1 || x > s.x2 || s.y < y - tol) continue
            if (!best || s.y < best.y) best = s
        }
        return best
    }

    function parseClients(t) {
        let arr
        try { arr = JSON.parse(t) } catch (e) { return }
        const mon = Hyprland.monitorFor(win.screen)
        const ox = mon ? mon.x : 0, oy = mon ? mon.y : 0
        const ws = (mon && mon.activeWorkspace) ? mon.activeWorkspace.id : -1
        const out = []
        for (const c of arr) {
            if (!c.mapped || c.hidden || c.workspace.id !== ws || (mon && c.monitor !== mon.id)) continue
            out.push({ x1: c.at[0] - ox, x2: c.at[0] - ox + c.size[0], y: c.at[1] - oy,
                       addr: (c.address || "").replace("0x", ""), cls: c.class || "" })
        }
        supports = out
        if (pendingFocus) { pendingFocus = false; reactFocus() }
    }

    // ── Behaviour ────────────────────────────────────────────────────
    function enter(s) {
        st = s
        if (s !== "walk") target = -1
        if (s === "idle")       stT = 0.6 + Math.random() * 1.6
        else if (s === "walk")  stT = 2 + Math.random() * 4
        else if (s === "sit")   stT = 3 + Math.random() * 5
        else if (s === "sleep") stT = 12 + Math.random() * 18
        else if (s === "happy") stT = 1.6
    }

    function jumpTo(c) {
        const tx = clamp(px, c.x1 + 20, c.x2 - 20)
        const dy = Math.max(0, py - c.y)
        jx0 = px; jy0 = py; jx1 = tx; jy1 = c.y
        jh = 60 + dy * 0.25
        jd = 0.45 + dy / 2000 + Math.abs(tx - px) / 3000
        jt = 0
        dir = tx >= px ? 1 : -1
        st = "jump"
    }

    function tryJump(s) {
        const cands = []
        for (const c of supports) {
            if (c === s || c.y > py - 20 || py - c.y > maxJump || c.x2 - c.x1 <= 60) continue
            if (Math.abs(clamp(px, c.x1 + 20, c.x2 - 20) - px) <= 700) cands.push(c)
        }
        if (cands.length === 0) return false
        jumpTo(cands[Math.floor(Math.random() * cands.length)])
        return true
    }

    function pickNext(s) {
        if (busy !== "") { stT = 3600; return }
        if (st === "sleep" || st === "happy") { enter("idle"); return }
        if (st === "sit") { enter(Math.random() < 0.3 ? "sleep" : "idle"); return }
        const r = Math.random()
        if (r < 0.45)      { dir = Math.random() < 0.5 ? -1 : 1; enter("walk") }
        else if (r < 0.55) enter("sit")
        else if (r < 0.80) { if (!tryJump(s)) enter("walk") }
        else if (r < 0.88 && !s.ground) { vx = dir * 40; vy = 0; enter("fall") }   // hop off the window
        else               enter("idle")
    }

    // Come over to the cursor now and then, when it is roughly at her height.
    function curious(cx, cy, force) {
        if (!grounded || busy !== "") return
        if (!force && (st === "sleep" || st === "happy" || Math.random() > 0.25)) return
        const s = supportAt(px, py, 6)
        const reachable = s && Math.abs(cx - px) >= 140 && Math.abs(cy - py) <= 350
                          && cx >= s.x1 + 24 && cx <= s.x2 - 24
        if (!reachable) { if (force) enter("happy"); return }
        dir = cx > px ? 1 : -1
        target = cx - dir * 70
        st = "walk"
        stT = 12
    }

    function tick(dt) {
        if (!inited) {
            if (width <= 0) return
            px = width * (0.15 + Math.random() * 0.7); py = 0; vx = 0; vy = 0
            inited = true
            enter("fall")
            return
        }
        if (st === "held") return

        if (st === "fall") {
            const prev = py
            vy = Math.min(vy + 1400 * dt, 1200)
            py += vy * dt
            px = clamp(px + vx * dt, 32, width - 32)
            const s = supportAt(px, prev, 2)
            if (s && py >= s.y) { py = s.y; vx = 0; vy = 0; enter("idle") }
            return
        }

        if (st === "jump") {
            jt += dt / jd
            if (jt >= 1) { px = jx1; py = jy1; enter("idle") }
            else { px = jx0 + (jx1 - jx0) * jt; py = jy0 + (jy1 - jy0) * jt - jh * 4 * jt * (1 - jt) }
            return
        }

        const s = supportAt(px, py, 6)
        if (!s || s.y - py > 6) { vx = 0; vy = 0; enter("fall"); return }
        py = s.y
        stT -= dt

        if (st === "walk") {
            px += dir * walkSpeed * dt
            if (target >= 0 && Math.abs(px - target) < 4) { enter("sit"); return }
            const m = s.ground ? 24 : 0
            if (px < s.x1 + m || px > s.x2 - m) {
                if (s.ground || Math.random() < 0.5) {
                    px = clamp(px, s.x1 + m, s.x2 - m); dir = -dir; target = -1
                } else {
                    px += dir * 2; vx = dir * 70; vy = 0; enter("fall"); return
                }
            }
        }
        if (stT <= 0) pickNext(s)
    }

    // ── Speech and reactions ─────────────────────────────────────────
    function say(text, secs, force) {
        if (!active || !text) return
        if (shellRoot && shellRoot.assistantOpen) return
        const now = Date.now()
        if (!force && (now - lastSay < 12000 || st === "sleep" || st === "held")) return
        lastSay = now
        bubbleText = text
        bubbleTimer.interval = (secs || 5) * 1000
        bubbleTimer.restart()
    }

    // A notification arrived: show it and run to the cursor.
    function notify(app, summary, urgent) {
        if (!active) return
        let t = (summary || "").replace(/\s+/g, " ").trim()
        if (t.length > 70) t = t.slice(0, 69) + "…"
        say((app === "Iris" ? "" : app + " : ") + (t || "Une notification !"), urgent ? 10 : 7, true)
        if (grounded && busy === "") {
            if (st === "sleep") enter("idle")
            alertGo = true
            cursorProc.running = true
        }
    }

    // The focused window changed: maybe climb on it, maybe comment.
    function reactFocus() {
        const c = supports.find(w => w.addr === focusAddr)
        if (!c) return
        if (grounded && busy === "" && Date.now() - lastFocusGo > 20000 && Math.random() < 0.6) {
            const s = supportAt(px, py, 6)
            if (s && s.addr !== c.addr) { lastFocusGo = Date.now(); jumpTo(c) }
        }
        if (Math.random() < 0.35) say(Phrases.focus(Phrases.category(c.cls)), 5)
    }

    function hyprEvent(name, data) {
        if (!active) return
        if (name === "activewindowv2") {
            if (data) { focusAddr = data; focusTimer.restart() }
        } else if (name === "openwindow") {
            const p = data.split(",")
            if (Math.random() < 0.6) say(Phrases.opened(Phrases.category(p[2])), 5)
            if (supports.length >= 8) say(Phrases.many(), 6)
            clientsProc.running = true
        } else if (name === "closewindow") {
            if (Math.random() < 0.3) say(Phrases.closed(), 4)
            clientsProc.running = true
        } else if (name === "fullscreen") {
            if (data === "1") say("Mode cinéma !", 4)
        } else if (name === "workspacev2") {
            clientsProc.running = true
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) { win.hyprEvent(ev.name, ev.data) }
    }
    Timer { id: focusTimer; interval: 500; onTriggered: { win.pendingFocus = true; clientsProc.running = true } }
    Timer { id: bubbleTimer; onTriggered: win.bubbleText = "" }
    Timer {
        interval: 240000; repeat: true; running: win.active
        onTriggered: {
            interval = 240000 + Math.random() * 240000
            if (win.grounded && win.busy === "") win.say(Phrases.idle(new Date().getHours()), 6)
        }
    }

    FrameAnimation {
        running: win.active
        onTriggered: win.tick(Math.min(frameTime, 0.05))
    }

    Timer {
        interval: 2000; repeat: true; running: win.active; triggeredOnStart: true
        onTriggered: clientsProc.running = true
    }
    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: win.parseClients(text) }
    }

    Timer {
        interval: 1500; repeat: true
        running: win.active && (win.st === "idle" || win.st === "walk" || win.st === "sit")
        onTriggered: cursorProc.running = true
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().split(/,\s*/)
                if (m.length !== 2) return
                const mon = Hyprland.monitorFor(win.screen)
                const force = win.alertGo
                win.alertGo = false
                win.curious(parseFloat(m[0]) - (mon ? mon.x : 0), parseFloat(m[1]) - (mon ? mon.y : 0), force)
            }
        }
    }

    // ── Sprite ───────────────────────────────────────────────────────
    Item {
        id: sprite
        width: win.spriteSize
        height: win.spriteSize
        x: win.px - width / 2
        y: win.py - height

        Item {
            id: body
            anchors.fill: parent
            rotation: win.st === "walk" ? win.dir * 7 : 0
            transformOrigin: Item.Bottom
            transform: Scale {
                origin.x: body.width / 2
                origin.y: body.height
                yScale: win.st === "sleep" ? 0.7 : (win.st === "sit" ? 0.86 : 1)
                xScale: win.st === "sleep" ? 1.12 : 1
                Behavior on yScale { NumberAnimation { duration: 180 } }
                Behavior on xScale { NumberAnimation { duration: 180 } }
            }

            property real bob: 0
            SequentialAnimation on bob {
                running: win.st === "walk"
                loops: Animation.Infinite
                onRunningChanged: if (!running) body.bob = 0
                NumberAnimation { to: -5; duration: 140; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0;  duration: 140; easing.type: Easing.InQuad }
            }
            y: bob

            CompanionSprite {
                theme: win.theme
                mood: win.mood
                walking: win.st === "walk"
                phase: win.stepPhase
                size: win.spriteSize
                anchors.fill: parent
            }
        }

        Text {
            visible: win.st === "happy"
            text: "♥"
            color: "#ff6bd6"
            font.pixelSize: 14
            x: parent.width / 2 - width / 2
            y: -18
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            property real offX: 0
            property real offY: 0
            property real startX: 0
            property real startY: 0
            property bool moved: false

            onPressed: m => {
                const g = mapToItem(win.contentItem, m.x, m.y)
                offX = win.px - g.x; offY = win.py - g.y
                startX = g.x; startY = g.y
                moved = false
            }
            onPositionChanged: m => {
                if (!pressed) return
                const g = mapToItem(win.contentItem, m.x, m.y)
                if (!moved && Math.hypot(g.x - startX, g.y - startY) > 6) {
                    moved = true; win.enter("held")
                    if (Math.random() < 0.5) win.say(Phrases.grabbed(), 3, true)
                }
                if (moved) {
                    win.px = win.clamp(g.x + offX, 32, win.width - 32)
                    win.py = win.clamp(g.y + offY, win.spriteSize, win.height)
                }
            }
            onReleased: {
                if (moved) { win.vx = 0; win.vy = 0; win.enter("fall") }
                else { win.enter("happy"); win.say(Phrases.pet(), 3, true) }
            }
            onDoubleClicked: {
                if (win.shellRoot && win.shellRoot.openAssistant) win.shellRoot.openAssistant()
            }
        }
    }

    // ── Speech bubble ────────────────────────────────────────────────
    Item {
        id: bubbleBox
        readonly property bool shown: win.bubbleText !== ""
        readonly property bool above: sprite.y - height - 4 > 8
        width: shown ? bubbleRect.width : 0
        height: shown ? bubbleRect.height + 8 : 0
        x: win.clamp(sprite.x + sprite.width / 2 - width / 2, 8, win.width - width - 8)
        y: above ? sprite.y - height - 4 : sprite.y + sprite.height + 4
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        TextMetrics { id: tm; font: label.font; text: win.bubbleText }

        Rectangle {
            visible: bubbleBox.above
            width: 10; height: 10; rotation: 45
            color: bubbleRect.color
            x: win.clamp(sprite.x + sprite.width / 2 - bubbleBox.x, 14, bubbleBox.width - 14) - 5
            y: bubbleRect.height - 5
        }
        Rectangle {
            id: bubbleRect
            width: label.width + 24
            height: label.contentHeight + 16
            radius: 12
            color: "#f01d1326"
            border.width: 1
            border.color: win.theme.primary
            Text {
                id: label
                x: 12; y: 8
                width: Math.min(236, tm.width + 2)
                text: win.bubbleText
                wrapMode: Text.Wrap
                color: "#ffffff"
                font.family: win.theme.ff
                font.pixelSize: 13
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                win.bubbleText = ""
                if (win.shellRoot && win.shellRoot.openAssistant) win.shellRoot.openAssistant()
            }
        }
    }
}
