import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Chat panel for "Iris", the pixel-art assistant. Slides in on the right,
// under the bar. Talks to scripts/assistant.py, a daemon that keeps a
// streaming `claude -p` open (fast replies), routes between Haiku and
// Sonnet, stores the conversation history and forwards permission requests
// here as Autoriser / Refuser cards.
// Look: "liquid glass" — a translucent panel that Hyprland blurs behind
// (layer rule on the "quickshell-assistant" namespace, see
// ~/.config/hypr/modules/animation.lua), with a specular edge.
// Messages are selectable (drag to select, Ctrl+C or the copy button), and
// file paths written in backticks become links that open the file manager.
// Enter sends, Esc closes, Ctrl+N new chat, Ctrl+H history.
PanelWindow {
    id: overlay

    required property var shellRoot
    required property var theme

    readonly property bool _open: shellRoot.assistantOpen
    visible: _open || exitAnim.running
    WlrLayershell.namespace: "quickshell-assistant"
    WlrLayershell.keyboardFocus: _open ? WlrKeyboardFocus.Exclusive
                                       : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    color: "transparent"

    readonly property int panelWidth: 460

    // ── Glass tokens (derived from the active theme) ──────────────────
    readonly property bool  light:       theme.light
    readonly property color glassFill:   light ? Qt.rgba(1, 1, 1, 0.55)
                                               : Qt.rgba(theme.bg.r, theme.bg.g, theme.bg.b, 0.58)
    readonly property color glassStroke: light ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.11)
    readonly property color glassShine:  light ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.07)
    readonly property color cardFill:    light ? Qt.rgba(1, 1, 1, 0.6)  : Qt.rgba(1, 1, 1, 0.055)
    readonly property color cardStroke:  light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color cardHover:   light ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.10)
    readonly property color wellFill:    light ? Qt.rgba(1, 1, 1, 0.7)  : Qt.rgba(0, 0, 0, 0.22)
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Chat items: role = "user" | "assistant" | "error" | "ask" | "nudge"
    // (an alert Iris sends on her own, from scripts/iris-watch.py).
    // Ask items also carry askId / askTool / askState (pending|allowed|denied).
    ListModel { id: messages }
    ListModel { id: history }

    property bool   busy:        false
    property bool   streaming:   false   // last item is the reply being streamed
    property bool   replying:    false   // text is flowing right now
    property string toolStatus:  ""
    property string modelName:   ""      // "haiku" | "sonnet" (last reply)
    property string mode:        "auto"  // auto | fast | power
    property bool   showHistory: false
    property var    agentList:  ["claude"]   // agents the daemon accepts (claude + config.json's "agents")
    property string agent:      "claude"
    property bool   agentMenu:  false
    property string searchQuery: ""      // text typed in the history search field
    // Subscription usage (0..1) reported by Claude Code; -1 = unknown yet.
    property real   usage5h:     -1
    property real   usageWeek:   -1
    property real   usageResets: 0       // epoch ms of the next reset, 0 = unknown
    // Texts sent by the daemon at startup (see ui_strings() in assistant.py);
    // tr() falls back to the French default when a key is missing.
    property var ui: ({})
    function tr(key, fallback) { return ui[key] !== undefined ? ui[key] : fallback }

    readonly property var modeList: [
        { key: "auto",  label: "Auto",                       icon: "󰁨" },
        { key: "fast",  label: overlay.tr("mode_fast", "Rapide"),    icon: "󱐋" },
        { key: "power", label: overlay.tr("mode_power", "Puissant"), icon: "󰧑" }
    ]

    readonly property string mood:
        !busy ? "idle" : (toolStatus !== "" || !replying) ? "thinking" : "talking"
    onMoodChanged: shellRoot.assistantMood = mood

    // Wall clock, refreshed every 30 s (greeting, date, reset countdown).
    property date now: new Date()
    Timer { interval: 30000; repeat: true; running: overlay.visible; triggeredOnStart: true
            onTriggered: overlay.now = new Date() }

    function close()  { shellRoot.closeAssistant() }
    function cmd(o)   { daemon.write(JSON.stringify(o) + "\n") }

    // `act` = {id, label, arg} adds a button under an alert (see iris-watch.py).
    function _push(role, text, act) {
        messages.append({ role: role, text: text, askId: "", askTool: "", askState: "",
                          action: act && act.id ? act.id : "",
                          actionLabel: act && act.label ? act.label : "",
                          actionArg: act && act.arg ? act.arg : "",
                          actionState: "" })
    }

    // Button under an alert: "update" has its own flow, the rest goes to the
    // daemon as a checked action (e.g. git_pull).
    function runAction(i) {
        const it = messages.get(i)
        if (it.action === "update") { runUpdate(i); return }
        messages.setProperty(i, "actionState", "running")
        cmd({ cmd: "action", id: it.action, arg: it.actionArg })
    }

    // "Update now" button on an update alert: the daemon runs iris-update.
    property bool updateAvailable: false   // a newer Iris exists (badge on the header button)
    property bool updating: false          // iris-update is running
    function runUpdate(i) {
        if (updating) return
        updating = true
        if (i >= 0) messages.setProperty(i, "actionState", "running")
        else _push("nudge", tr("updating_msg", "Mise à jour en cours… le panneau peut se recharger."))
        cmd({ cmd: "update" })
    }

    // Text attached to the next message (iris-ask --edit: the user's selection).
    property string attached: ""
    function prefill(text) {
        attached = text
        showHistory = false
        Qt.callLater(() => input.forceActiveFocus())
    }

    // Image pasted with Ctrl+V (a file the daemon saved), sent with the next message.
    property string image: ""

    function send() {
        const typed = input.text.trim()
        if ((!typed && attached === "" && image === "") || busy) return
        let msg = attached === "" ? typed
            : (typed !== "" ? typed : tr("attached_default", "Voici le texte que j'ai sélectionné :"))
              + "\n\n```\n" + attached + "\n```"
        if (image !== "") {
            if (msg === "") msg = tr("image_default", "Regarde cette image :")
            msg += "\n\n" + tr("image_line", "[Image jointe : {path}]").replace("{path}", image)
        }
        attached = ""
        image = ""
        input.text  = ""
        showHistory = false
        _push("user", msg)
        busy = true; streaming = false; replying = false; toolStatus = ""
        cmd({ cmd: "send", text: msg, mode: mode })
        list.stick = true; list.positionViewAtEnd()
    }
    function ask(text) { input.text = text; send() }
    function stop()    { if (busy) cmd({ cmd: "stop" }) }
    function newChat() { showHistory = false; image = ""; cmd({ cmd: "new" }) }
    function answer(index, allow) {
        const it = messages.get(index)
        if (it.askState !== "pending") return
        messages.setProperty(index, "askState", allow ? "allowed" : "denied")
        cmd({ cmd: "answer", id: it.askId, allow: allow })
    }
    function toggleHistory() {
        showHistory = !showHistory
        if (showHistory) cmd({ cmd: "list" })
    }
    function copy(text) { Quickshell.execDetached(["wl-copy", "--", text]) }

    // ── File links ────────────────────────────────────────────────────
    // A path in backticks (`~/Documents/x.pdf`, `/home/…/dossier/`) becomes
    // a link "iris-file:<path>"; clicking it shows the item in Nautilus
    // (file selected inside its folder, or the folder opened).
    // Inline HTML anchor (Qt's Markdown keeps it): lets us colour the link,
    // TextEdit ignores palette.link and would draw it pure blue.
    function _linkText(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                .replace(/([\\\[\]_*`~])/g, "\\$1")
    }
    function linkify(t) {
        return t.replace(/`((?:~\/|~$|\/)[^`\n]*)`/g, (m, p) => {
            p = p.trim()
            if (p === "/" || /\s{2,}/.test(p)) return m
            const name = p.replace(/\/+$/, "").split("/").pop() || p
            const isDir = /\/$/.test(p) || !/\.[A-Za-z0-9]{1,8}$/.test(name)
            return "<a href=\"iris-file:" + encodeURIComponent(p) + "\" style=\"color:"
                   + theme.primary + "; text-decoration:none; font-weight:600\">"
                   + (isDir ? " " : " ") + _linkText(p) + "</a>"
        })
    }
    function openLink(link) {
        let path = ""
        if (link.startsWith("iris-file:")) path = decodeURIComponent(link.slice(10))
        else if (link.startsWith("file://")) path = decodeURIComponent(link.slice(7))
        console.log("[iris] open link", link)
        if (path === "") {
            if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link)
            return
        }
        path = path.replace(/^~(?=\/|$)/, shellRoot.homeDir)
        Quickshell.execDetached(["sh", "-c",
            // The shell runs without LANG: GLib would then reject accented
            // paths ("Invalid byte sequence"), so force UTF-8.
            'export LANG="${LANG:-C.UTF-8}"; '
          + 'if command -v nautilus >/dev/null 2>&1; then '
          + '  if [ -d "$1" ]; then exec nautilus --new-window "$1"; '
          + '  elif [ -e "$1" ]; then exec nautilus --select "$1"; '
          + '  else exec nautilus --new-window "$(dirname "$1")"; fi; '
          + 'else '
          + '  if [ -d "$1" ]; then exec xdg-open "$1"; else exec xdg-open "$(dirname "$1")"; fi; '
          + 'fi'
          + ' >"$XDG_RUNTIME_DIR/iris-reveal.log" 2>&1', "reveal", path])
        close()
    }

    function _relTime(ts) {
        const s = Date.now() / 1000 - ts
        if (s < 3600)     return Math.max(1, Math.round(s / 60)) + " min"
        if (s < 86400)    return Math.round(s / 3600) + " h"
        if (s < 7 * 86400) return Math.round(s / 86400) + " " + overlay.tr("day_abbr", "j")
        return Qt.formatDate(new Date(ts * 1000), "dd/MM")
    }
    function _resetLabel() {
        if (usageResets <= 0) return ""
        const left = (usageResets - now.getTime()) / 60000
        if (left <= 0) return ""
        const h = Math.floor(left / 60), m = Math.round(left % 60)
        return overlay.tr("reset", "réinit. ") + (h > 0 ? h + " h " + String(m).padStart(2, "0") : m + " min")
    }
    readonly property string greeting: {
        const h = now.getHours()
        return h < 5 ? overlay.tr("greet_night", "Encore debout ?") : h < 18 ? overlay.tr("greet_day", "Bonjour") : overlay.tr("greet_evening", "Bonsoir")
    }

    // ── Daemon ────────────────────────────────────────────────────────
    Process {
        id: daemon
        running: true
        stdinEnabled: true
        command: ["python3", overlay.shellRoot.configDir + "/scripts/assistant.py"]
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                overlay._onEvent(d)
            }
        }
        // Restart if it ever dies (keeps the panel usable).
        onExited: { overlay.busy = false; restartTimer.restart() }
    }
    Timer { id: restartTimer; interval: 1000; onTriggered: daemon.running = true }

    // Watcher: local checks (git, agenda, PC health) → alerts, no quota.
    Process {
        id: watcher
        running: true
        command: ["python3", overlay.shellRoot.configDir + "/scripts/iris-watch.py"]
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.t === "nudge") overlay.cmd({ cmd: "nudge", text: d.text, kind: d.kind || "", action: d.action || null })
            }
        }
        onExited: watcherRestart.restart()
    }
    Timer { id: watcherRestart; interval: 60000; onTriggered: watcher.running = true }

    // Plain-text version of an alert for the desktop notification.
    function _plain(t) {
        return t.replace(/[\uE000-\uF8FF]\s*/g, "").replace(/\*\*|`/g, "").replace(/\n+/g, " ").trim()
    }

    function _onEvent(d) {
        switch (d.t) {
        case "conversation":
            messages.clear()
            // Only the latest alert of each action keeps its button (older ones are stale).
            const lastOf = {}
            const keyOf = a => a.id + "|" + (a.arg || "")
            d.messages.forEach((m, k) => { if (m.action && m.action.id) lastOf[keyOf(m.action)] = k })
            d.messages.forEach((m, k) => _push(m.role, m.text,
                m.action && m.action.id && lastOf[keyOf(m.action)] === k ? m.action : null))
            busy = false; streaming = false
            list.stick = true; Qt.callLater(() => list.positionViewAtEnd())
            break
        case "ui":
            ui = d.s
            break
        case "model":
            modelName = d.v
            break
        case "text": {
            toolStatus = ""
            replying   = true
            if (!streaming) { _push("assistant", ""); streaming = true }
            const i = messages.count - 1
            messages.setProperty(i, "text", messages.get(i).text + d.v)
            if (list.stick) list.positionViewAtEnd()
            break
        }
        case "tool":
            toolStatus = d.v
            replying   = false
            break
        case "ask":
            streaming  = false
            replying   = false
            messages.append({ role: "ask", text: d.detail, askId: d.id,
                              askTool: d.tool, askState: "pending", action: "", actionLabel: "",
                              actionArg: "", actionState: "" })
            list.stick = true; list.positionViewAtEnd()
            break
        case "error":
            _push("error", d.v)
            break
        case "done":
            busy = false; streaming = false; replying = false; toolStatus = ""
            for (let k = 0; k < messages.count; k++)
                if (messages.get(k).askState === "pending")
                    messages.setProperty(k, "askState", "denied")
            break
        case "usage":
            if (d.five !== null && d.five !== undefined) usage5h   = d.five
            if (d.week !== null && d.week !== undefined) usageWeek = d.week
            if (d.resets) usageResets = d.resets > 1e12 ? d.resets : d.resets * 1000
            break
        case "update_state":
            updateAvailable = d.available
            updating = d.running
            break
        case "action_done":
            for (let k = 0; k < messages.count; k++) {
                const it = messages.get(k)
                if (it.action === d.id && it.actionArg === d.arg && it.actionState === "running")
                    messages.setProperty(k, "actionState", d.ok ? "done" : "failed")
            }
            _push(d.ok ? "nudge" : "error", d.v)
            if (list.stick) Qt.callLater(() => list.positionViewAtEnd())
            break
        case "update_done":
            updating = false
            if (d.ok) updateAvailable = false
            for (let k = 0; k < messages.count; k++)
                if (messages.get(k).action === "update" && messages.get(k).actionState === "running")
                    messages.setProperty(k, "actionState", d.ok ? "done" : "failed")
            _push(d.ok ? "nudge" : "error", d.v)
            if (!_open && d.ok)
                Quickshell.execDetached(["notify-send", "-a", "Iris", "Iris", _plain(d.v)])
            if (list.stick) Qt.callLater(() => list.positionViewAtEnd())
            break
        case "nudge":
            if (d.kind === "update") updateAvailable = true
            _push("nudge", d.v, d.action)
            if (!_open) {
                shellRoot.assistantUnread++
                Quickshell.execDetached(["notify-send", "-a", "Iris", "Iris", _plain(d.v)])
            }
            if (list.stick) Qt.callLater(() => list.positionViewAtEnd())
            break
        case "agents":
            agentList = d.v; agent = d.current; agentMenu = false
            if (d.switched) _push("nudge", tr("agent_switched", "Agent : ") + d.current)
            break
        case "image":
            image = d.path
            break
        case "history":
            history.clear()
            for (const h of d.v) history.append({ cid: h.id, title: h.title, updated: h.updated, snippet: h.snippet || "" })
            break
        }
    }

    on_OpenChanged: {
        if (_open) {
            exitAnim.stop()
            enterAnim.restart()
            now = new Date()
            shellRoot.assistantUnread = 0
            list.stick = true; Qt.callLater(() => list.positionViewAtEnd())
            cmd({ cmd: "warm" })     // start Claude now so the first reply is quick
            Qt.callLater(() => input.forceActiveFocus())
        } else {
            enterAnim.stop()
            exitAnim.restart()
        }
    }

    // Window-wide shortcuts (work even while a message has focus for copying).
    Shortcut { sequence: "Escape"; enabled: overlay._open
               onActivated: overlay.showHistory ? overlay.showHistory = false : overlay.close() }
    Shortcut { sequence: "Ctrl+N"; enabled: overlay._open; onActivated: overlay.newChat() }
    Shortcut { sequence: "Ctrl+H"; enabled: overlay._open; onActivated: overlay.toggleHistory() }

    // Backdrop: click outside the panel closes it.
    MouseArea {
        anchors.fill: parent
        onClicked: overlay.close()
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: panel;      property: "opacity"; from: 0; to: 1;     duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: panelSlide; property: "x";       from: 48; to: 0;    duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        NumberAnimation { target: panel;      property: "scale";   from: 0.97; to: 1;  duration: 420; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: panel;      property: "opacity"; to: 0;    duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: panelSlide; property: "x";       to: 48;   duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: panel;      property: "scale";   to: 0.98; duration: 200; easing.type: Easing.InCubic }
    }

    // ═════════════════════════════════════════════════════════════════
    // Glass panel
    // ═════════════════════════════════════════════════════════════════
    Rectangle {
        id: panel
        anchors {
            right: parent.right; rightMargin: 10
            top: parent.top;     topMargin: 44
            bottom: parent.bottom; bottomMargin: 10
        }
        width: overlay.panelWidth
        radius: 24
        color: overlay.glassFill
        border.color: overlay.glassStroke; border.width: 1
        opacity: 0
        transformOrigin: Item.Right
        transform: Translate { id: panelSlide; x: 48 }

        MouseArea { anchors.fill: parent }   // swallow clicks

        // Sheen: light from the top, a faint accent glow at the bottom.
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0;  color: overlay.glassShine }
                GradientStop { position: 0.28; color: "transparent" }
                GradientStop { position: 0.8;  color: "transparent" }
                GradientStop { position: 1.0;  color: overlay.alpha(overlay.theme.primary, overlay.light ? 0.10 : 0.07) }
            }
        }
        // Specular highlight along the top edge.
        Rectangle {
            anchors { top: parent.top; topMargin: 1; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 2 * parent.radius; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, overlay.light ? 0.9 : 0.32) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // ── Header ────────────────────────────────────────────────────
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 78

            // Avatar sits in a small glass disc.
            Rectangle {
                id: avatarDisc
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                width: 52; height: 52; radius: 26
                color: overlay.cardFill
                border.color: overlay.cardStroke; border.width: 1
                AssistantAvatar {
                    anchors.centerIn: parent
                    theme: overlay.theme
                    mood: overlay.mood
                    size: 36
                }
            }

            Column {
                anchors {
                    left: avatarDisc.right; leftMargin: 12
                    right: actions.left; rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 3
                Row {
                    spacing: 8
                    Text {
                        text: "Iris"
                        color: overlay.theme.fg
                        font.family: overlay.theme.ff; font.weight: Font.DemiBold
                        font.pixelSize: overlay.theme.fs + 4
                    }
                    Rectangle {
                        visible: overlay.modelName !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: modelTxt.implicitWidth + 12; height: 18; radius: 9
                        color: overlay.alpha(modelTxt.color, 0.14)
                        Text {
                            id: modelTxt
                            anchors.centerIn: parent
                            text: overlay.modelName === "sonnet" ? "Sonnet" : "Haiku"
                            color: overlay.modelName === "sonnet" ? overlay.theme.secondary : overlay.theme.tertiary
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 4
                            font.weight: Font.Medium
                        }
                    }
                }
                Row {
                    spacing: 6
                    width: parent.width
                    // Status dot: steady green when idle, pulsing accent when busy.
                    Rectangle {
                        id: statusDot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7; radius: 3.5
                        color: overlay.busy ? overlay.theme.primary : overlay.theme.tertiary
                        SequentialAnimation on opacity {
                            running: overlay.busy; loops: Animation.Infinite
                            onRunningChanged: if (!running) statusDot.opacity = 1
                            NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1;    duration: 550; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        width: parent.width - 13
                        elide: Text.ElideRight
                        text: overlay.toolStatus !== "" ? overlay.toolStatus
                            : overlay.mood === "thinking" ? overlay.tr("thinking", "Je réfléchis…")
                            : overlay.mood === "talking"  ? overlay.tr("writing", "J'écris…")
                            : overlay.tr("online", "En ligne")
                        color: overlay.busy ? overlay.theme.primary : overlay.theme.txt2
                        opacity: overlay.busy ? 1 : 0.75
                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 2
                    }
                }
            }

            Row {
                id: actions
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 6
                // Agent picker: shows the current agent, opens a small menu.
                Rectangle {
                    visible: overlay.agentList.length > 1
                    height: 34; radius: 17
                    width: Math.min(110, agentLabel.implicitWidth + 24)
                    opacity: overlay.busy ? 0.5 : 1
                    color: overlay.agentMenu ? overlay.alpha(overlay.theme.primary, 0.18)
                         : agentHover.hovered ? overlay.cardHover : overlay.cardFill
                    border.color: overlay.agentMenu ? overlay.alpha(overlay.theme.primary, 0.4) : overlay.cardStroke
                    border.width: 1
                    Text {
                        id: agentLabel
                        anchors.centerIn: parent
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: overlay.agent
                        color: overlay.agentMenu ? overlay.theme.primary : overlay.theme.txt2
                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                    }
                    HoverHandler { id: agentHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !overlay.busy; onTapped: overlay.agentMenu = !overlay.agentMenu }
                }
                Repeater {
                    model: [
                        { icon: "", tip: "history" },
                        { icon: "", tip: "new" },
                        { icon: "\uf019", tip: "update" }      // always there: click = update now
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: (modelData.tip === "history" && overlay.showHistory)
                                                   || (modelData.tip === "update" && overlay.updating)
                        width: 34; height: 34; radius: 17
                        color: on ? overlay.alpha(overlay.theme.primary, 0.18)
                             : aHover.hovered ? overlay.cardHover : overlay.cardFill
                        border.color: on ? overlay.alpha(overlay.theme.primary, 0.4) : overlay.cardStroke
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: parent.on ? overlay.theme.primary
                                 : modelData.tip === "update" && overlay.updateAvailable ? overlay.theme.tertiary
                                 : overlay.theme.txt2
                            font.family: overlay.theme.ff; font.pixelSize: 15
                            SequentialAnimation on opacity {
                                running: modelData.tip === "update" && overlay.updating; loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 600 }
                                NumberAnimation { to: 1;    duration: 600 }
                            }
                        }
                        // Badge: a newer version is available.
                        Rectangle {
                            visible: modelData.tip === "update" && overlay.updateAvailable && !overlay.updating
                            x: parent.width - 11; y: 3
                            width: 9; height: 9; radius: 4.5
                            color: overlay.theme.tertiary
                            border.color: overlay.cardFill; border.width: 1
                        }
                        HoverHandler { id: aHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            enabled: modelData.tip !== "update" || !overlay.updating
                            onTapped: modelData.tip === "history" ? overlay.toggleHistory()
                                    : modelData.tip === "new"     ? overlay.newChat()
                                    : overlay.runUpdate(-1)
                        }
                    }
                }
            }
        }

        // ── Mode selector (segmented glass control) ───────────────────
        Rectangle {
            id: modeBar
            anchors { top: header.bottom; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 32; height: 34; radius: 17
            color: overlay.wellFill
            border.color: overlay.cardStroke; border.width: 1

            readonly property int idx: overlay.modeList.findIndex(m => m.key === overlay.mode)
            readonly property real segW: (width - 6) / 3

            // Sliding knob
            Rectangle {
                x: 3 + modeBar.idx * modeBar.segW; y: 3
                width: modeBar.segW; height: parent.height - 6; radius: height / 2
                color: overlay.light ? "#ffffff" : Qt.rgba(1, 1, 1, 0.12)
                border.color: overlay.light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
            Row {
                x: 3; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: overlay.modeList
                    delegate: Item {
                        required property var modelData
                        readonly property bool on: overlay.mode === modelData.key
                        width: modeBar.segW; height: 28
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: modelData.icon
                                color: !parent.parent.on ? overlay.theme.outline
                                     : modelData.key === "power" ? overlay.theme.secondary
                                     : modelData.key === "fast"  ? overlay.theme.tertiary
                                     : overlay.theme.primary
                                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                            }
                            Text {
                                text: modelData.label
                                color: parent.parent.on ? overlay.theme.fg : overlay.theme.txt2
                                opacity: parent.parent.on ? 1 : 0.7
                                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 2
                                font.weight: parent.parent.on ? Font.DemiBold : Font.Normal
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: overlay.mode = modelData.key }
                    }
                }
            }
        }

        // ── History ────────────────────────────────────────────────────
        // The search field lives outside the list: the list's model is reset on
        // every answer, which took the focus away from a field inside it.
        Rectangle {
            id: searchBox
            visible: overlay.showHistory
            anchors { left: parent.left; right: parent.right; top: modeBar.bottom
                      leftMargin: 16; rightMargin: 16; topMargin: 16 }
            height: 36; radius: 18
            color: overlay.wellFill
            border.color: searchInput.activeFocus ? overlay.alpha(overlay.theme.primary, 0.6) : overlay.cardStroke
            border.width: 1
            TextInput {
                id: searchInput
                anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16
                          verticalCenter: parent.verticalCenter }
                color: overlay.theme.fg
                selectionColor: overlay.alpha(overlay.theme.primary, 0.45)
                selectedTextColor: overlay.theme.fg
                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                clip: true
                onTextChanged: { overlay.searchQuery = text; overlay.cmd({ cmd: "search", q: text }) }
                Connections {
                    target: overlay
                    function onShowHistoryChanged() {
                        if (!overlay.showHistory) return
                        searchInput.text = ""
                        searchInput.forceActiveFocus()
                    }
                }
                Text {
                    visible: searchInput.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.tr("search_placeholder", "Rechercher une conversation…")
                    color: overlay.theme.outline
                    font: searchInput.font
                }
            }
        }

        ListView {
            id: historyList
            visible: overlay.showHistory
            anchors {
                left: parent.left; right: parent.right
                top: searchBox.bottom; bottom: inputBox.top
                margins: 16; topMargin: 10
            }
            clip: true
            spacing: 6
            model: history
            boundsBehavior: Flickable.StopAtBounds

            Text {
                visible: history.count === 0
                anchors.centerIn: parent
                text: overlay.searchQuery.trim() !== "" ? overlay.tr("no_match", "Aucun résultat")
                    : overlay.tr("no_history", "Aucune conversation pour l'instant")
                color: overlay.theme.outline
                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs
            }

            delegate: Rectangle {
                id: hrow
                required property string cid
                required property string title
                required property real   updated
                required property string snippet
                width: historyList.width; height: snippet !== "" ? 64 : 48
                radius: 14
                color: hHover.hovered ? overlay.cardHover : overlay.cardFill
                border.color: overlay.cardStroke; border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler { id: hHover }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { overlay.cmd({ cmd: "load", id: hrow.cid }); overlay.showHistory = false }
                }
                Text {
                    id: hIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "󰍩"
                    color: overlay.theme.primary; opacity: 0.8
                    font.family: overlay.theme.ff; font.pixelSize: 15
                }
                Text {
                    id: hTitle
                    anchors { left: hIcon.right; leftMargin: 10; right: hDate.left; rightMargin: 10
                              verticalCenter: parent.verticalCenter
                              verticalCenterOffset: hrow.snippet !== "" ? -10 : 0 }
                    text: hrow.title
                    elide: Text.ElideRight
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                }
                Text {
                    visible: hrow.snippet !== ""
                    anchors { left: hTitle.left; right: hTitle.right; top: hTitle.bottom; topMargin: 2 }
                    text: hrow.snippet
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                }
                Text {
                    id: hDate
                    anchors { right: hDel.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: overlay._relTime(hrow.updated)
                    color: overlay.theme.outline
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                }
                Text {
                    id: hDel
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: ""                       // trash
                    opacity: hHover.hovered ? 1 : 0
                    color: delHover.hovered ? overlay.theme.error : overlay.theme.outline
                    font.family: overlay.theme.ff; font.pixelSize: 14
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    HoverHandler { id: delHover }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.cmd({ cmd: "delete", id: hrow.cid })
                    }
                }
            }
        }

        // ── Messages ───────────────────────────────────────────────────
        ListView {
            id: list
            visible: !overlay.showHistory
            anchors {
                left: parent.left; right: parent.right
                top: modeBar.bottom; bottom: inputBox.top
                leftMargin: 16; rightMargin: 16; topMargin: 12; bottomMargin: 10
            }
            clip: true
            spacing: 12
            model: messages
            boundsBehavior: Flickable.StopAtBounds
            // Mouse drags select text instead of flicking; the wheel /
            // touchpad scrolls (smoothly) through the MouseArea below the list.
            interactive: false

            // Follow the bottom while the reply streams in (Markdown
            // bubbles resize after layout, so react to the content height),
            // unless the user scrolled up to read.
            property bool stick: true
            onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)
            onCountChanged:         if (stick) Qt.callLater(positionViewAtEnd)

            readonly property real maxY: Math.max(originY, originY + contentHeight - height)
            function scrollBy(dy, smooth) {
                const from = scrollAnim.running ? scrollAnim.to : contentY
                const to = Math.max(originY, Math.min(maxY, from - dy))
                scrollAnim.stop()
                if (smooth) { scrollAnim.from = contentY; scrollAnim.to = to; scrollAnim.start() }
                else contentY = to
                stick = to >= maxY - 2
            }
            NumberAnimation { id: scrollAnim; target: list; property: "contentY"
                              duration: 220; easing.type: Easing.OutCubic }

            // Empty state: greeting, date and a few suggestions.
            Column {
                visible: messages.count === 0
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: overlay.greeting
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs + 8
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const d = Qt.locale(overlay.tr("locale", "fr_FR")).toString(overlay.now, overlay.tr("date_fmt", "dddd d MMMM · HH:mm"))
                        return d.charAt(0).toUpperCase() + d.slice(1)
                    }
                    color: overlay.theme.txt2; opacity: 0.7
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                }
                Item { width: 1; height: 16 }
                Repeater {
                    model: [
                        { icon: "", text: overlay.tr("chip1", "Qu'est-ce que j'ai aujourd'hui ?") },
                        { icon: "󰃭", text: overlay.tr("chip2", "Aide-moi à planifier ma semaine") },
                        { icon: "", text: overlay.tr("chip3", "Où est mon dernier PDF téléchargé ?") },
                        { icon: "󰍛", text: overlay.tr("chip4", "Qu'est-ce qui ralentit mon PC ?") }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 300; height: 40
                        radius: 20
                        color: sugHover.hovered ? overlay.cardHover : overlay.cardFill
                        border.color: sugHover.hovered ? overlay.alpha(overlay.theme.primary, 0.35) : overlay.cardStroke
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: sugIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            text: modelData.icon
                            color: overlay.theme.primary
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs
                        }
                        Text {
                            anchors { left: sugIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: modelData.text
                            color: overlay.theme.fg
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                        }
                        HoverHandler { id: sugHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: overlay.ask(modelData.text) }
                    }
                }
            }

            delegate: Item {
                id: msg
                required property string role
                required property string text
                required property string askTool
                required property string askState
                required property string action
                required property string actionLabel
                required property string actionArg
                required property string actionState
                required property int    index
                readonly property bool mine: role === "user"
                readonly property bool live: overlay.streaming && index === messages.count - 1
                width: list.width
                readonly property bool hasAction: action !== ""
                height: role === "ask" ? askCard.height : bubble.height + (hasAction ? 42 : 0)

                HoverHandler { id: msgHover }

                // Chat bubble (user / assistant / error)
                Rectangle {
                    id: bubble
                    visible: msg.role !== "ask"
                    anchors.right: msg.mine ? parent.right : undefined
                    anchors.left:  msg.mine ? undefined : parent.left
                    width: Math.min(body.implicitWidth + 28, list.width * 0.86)
                    height: body.implicitHeight + 20
                    radius: 18
                    bottomRightRadius: msg.mine ? 6 : 18
                    bottomLeftRadius:  msg.mine ? 18 : 6
                    gradient: msg.mine ? userGrad : null
                    color: msg.role === "error" ? overlay.alpha(overlay.theme.error, 0.14)
                         : msg.role === "nudge" ? overlay.alpha(overlay.theme.primary, 0.10)
                         : overlay.cardFill
                    border.width: msg.mine ? 0 : 1
                    border.color: msg.role === "error" ? overlay.alpha(overlay.theme.error, 0.35)
                                : msg.role === "nudge" ? overlay.alpha(overlay.theme.primary, 0.45)
                                : overlay.cardStroke

                    Gradient {
                        id: userGrad
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: overlay.theme.primary }
                        GradientStop { position: 1; color: Qt.tint(overlay.theme.primary, overlay.alpha(overlay.theme.lavender, 0.55)) }
                    }

                    // Selectable text (drag to select, Ctrl+C to copy).
                    TextEdit {
                        id: body
                        x: 14; y: 10
                        width: Math.min(implicitWidth, list.width * 0.86 - 28)
                        readOnly: true
                        selectByMouse: true
                        text: msg.mine || msg.role === "error" ? msg.text : overlay.linkify(msg.text)
                        textFormat: msg.mine ? TextEdit.PlainText : TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        color: msg.mine ? overlay.theme.bg
                             : msg.role === "error" ? overlay.theme.error
                             : overlay.theme.fg
                        selectionColor: msg.mine ? overlay.alpha(overlay.theme.bg, 0.35)
                                                 : overlay.alpha(overlay.theme.primary, 0.4)
                        selectedTextColor: color
                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs
                        // Click on a link (TapHandler: also fires when the
                        // pointer moved a hair, which cancels linkActivated).
                        TapHandler {
                            onTapped: (pt) => {
                                const l = body.linkAt(pt.position.x, pt.position.y)
                                if (l !== "") overlay.openLink(l)
                            }
                        }
                        // Typing while a message has focus goes back to the input.
                        Keys.onPressed: e => {
                            if (e.modifiers & Qt.ControlModifier || e.text === "" || e.text < " ") return
                            input.forceActiveFocus()
                            input.insert(input.cursorPosition, e.text)
                            e.accepted = true
                        }
                        HoverHandler {
                            cursorShape: body.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                        }
                    }
                }

                // Action button under an alert (e.g. "Update now").
                Rectangle {
                    visible: msg.hasAction
                    anchors { left: bubble.left; top: bubble.bottom; topMargin: 8 }
                    readonly property bool idle: (msg.actionState === "" || msg.actionState === "failed")
                                                 && !(msg.action === "update" && overlay.updating)
                    width: actionText.implicitWidth + 32; height: 32; radius: 16
                    color: !idle ? overlay.cardFill
                         : actHover.hovered ? Qt.lighter(overlay.theme.primary, 1.1) : overlay.theme.primary
                    border.color: idle ? "transparent" : overlay.cardStroke
                    border.width: 1
                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: msg.actionState === "running"
                                ? (msg.action === "update" ? overlay.tr("updating", "Mise à jour…") : overlay.tr("working", "En cours…"))
                            : msg.actionState === "done"
                                ? "\uf00c  " + (msg.action === "update" ? overlay.tr("updated_state", "À jour") : overlay.tr("done_state", "Fait"))
                            : msg.actionLabel !== "" ? msg.actionLabel : overlay.tr("update_btn", "Mettre à jour")
                        color: parent.idle ? overlay.theme.bg : overlay.theme.txt2
                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: actHover; enabled: parent.idle; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: parent.idle; onTapped: overlay.runAction(msg.index) }
                }

                // Copy button, beside the bubble on hover.
                Rectangle {
                    visible: msg.role !== "ask" && !msg.live && msg.text !== ""
                    opacity: msgHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    anchors.bottom: bubble.bottom
                    anchors.right: msg.mine ? bubble.left : undefined
                    anchors.left:  msg.mine ? undefined : bubble.right
                    anchors.leftMargin: 6; anchors.rightMargin: 6
                    width: 28; height: 28; radius: 14
                    color: cpHover.hovered ? overlay.cardHover : overlay.cardFill
                    border.color: overlay.cardStroke; border.width: 1
                    property bool done: false
                    Timer { id: cpReset; interval: 1400; onTriggered: parent.done = false }
                    Text {
                        anchors.centerIn: parent
                        text: parent.done ? "" : ""
                        color: parent.done ? overlay.theme.tertiary : overlay.theme.txt2
                        font.family: overlay.theme.ff; font.pixelSize: 13
                    }
                    HoverHandler { id: cpHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: { overlay.copy(msg.text); parent.done = true; cpReset.restart() }
                    }
                }

                // Permission request card
                Rectangle {
                    id: askCard
                    visible: msg.role === "ask"
                    width: list.width
                    height: askCol.implicitHeight + 28
                    radius: 18
                    color: overlay.cardFill
                    border.width: 1
                    border.color: msg.askState === "pending" ? overlay.alpha(overlay.theme.warn, 0.55)
                                : msg.askState === "allowed" ? overlay.alpha(overlay.theme.tertiary, 0.45)
                                : overlay.cardStroke

                    Column {
                        id: askCol
                        x: 14; y: 14
                        width: parent.width - 28
                        spacing: 10

                        Row {
                            spacing: 8
                            width: parent.width
                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: overlay.alpha(overlay.theme.warn, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: overlay.theme.warn
                                    font.family: overlay.theme.ff; font.pixelSize: 12
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 32
                                text: overlay.tr("wants", "Iris veut utiliser") + " <b>" + msg.askTool.replace(/^mcp__claude_ai_/, "").replace(/__/g, " · ").replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>"
                                textFormat: Text.StyledText
                                color: overlay.theme.fg
                                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: detail.implicitHeight + 16
                            radius: 10
                            color: overlay.wellFill
                            TextEdit {
                                id: detail
                                x: 10; y: 8
                                width: parent.width - 20
                                readOnly: true; selectByMouse: true
                                text: msg.text
                                wrapMode: TextEdit.WrapAnywhere
                                color: overlay.theme.fg
                                selectionColor: overlay.alpha(overlay.theme.primary, 0.4)
                                font.family: "JetBrainsMono Nerd Font Mono"; font.pixelSize: overlay.theme.fs - 2
                            }
                        }
                        Row {
                            visible: msg.askState === "pending"
                            spacing: 8
                            Repeater {
                                model: [
                                    { label: overlay.tr("allow", "Autoriser"), allow: true  },
                                    { label: overlay.tr("deny", "Refuser"),     allow: false }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: btnText.implicitWidth + 32; height: 32
                                    radius: 16
                                    color: modelData.allow
                                           ? (bHover.hovered ? Qt.lighter(overlay.theme.tertiary, 1.1) : overlay.theme.tertiary)
                                           : (bHover.hovered ? overlay.cardHover : overlay.cardFill)
                                    border.color: modelData.allow ? "transparent" : overlay.cardStroke
                                    border.width: 1
                                    Text {
                                        id: btnText
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: modelData.allow ? overlay.theme.bg : overlay.theme.fg
                                        font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                                        font.weight: Font.DemiBold
                                    }
                                    HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: overlay.answer(msg.index, modelData.allow) }
                                }
                            }
                        }
                        Text {
                            visible: msg.askState !== "pending"
                            text: msg.askState === "allowed" ? "  " + overlay.tr("allowed", "Autorisé") : "  " + overlay.tr("denied", "Refusé")
                            color: msg.askState === "allowed" ? overlay.theme.tertiary : overlay.theme.outline
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 2
                        }
                    }
                }
            }
        }

        // Wheel / touchpad scrolling for the message list. A wheel-only
        // MouseArea (no buttons) sits above the delegates: clicks, links and
        // text selection pass through, but the wheel always reaches the list.
        MouseArea {
            anchors.fill: list
            visible: !overlay.showHistory
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                if (wheel.pixelDelta.y !== 0) list.scrollBy(wheel.pixelDelta.y, false)
                else list.scrollBy(wheel.angleDelta.y / 120 * 90, true)
                wheel.accepted = true
            }
        }

        // Thin scroll indicator for the message list.
        Rectangle {
            visible: !overlay.showHistory && list.contentHeight > list.height + 4
            x: panel.width - 7; width: 3; radius: 1.5
            readonly property real ratio: list.height / Math.max(1, list.contentHeight)
            height: Math.max(24, list.height * ratio)
            y: list.y + (list.contentY - list.originY) / Math.max(1, list.contentHeight - list.height)
                        * (list.height - height)
            color: overlay.theme.outline
            opacity: scrollFade.running || list.moving || scrollAnim.running ? 0.6 : 0.18
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Timer { id: scrollFade; interval: 800 }
            Connections { target: list; function onContentYChanged() { scrollFade.restart() } }
        }

        // "Back to bottom" pill when scrolled up.
        Rectangle {
            visible: !overlay.showHistory && !list.stick && list.contentHeight > list.height
            anchors { horizontalCenter: parent.horizontalCenter; bottom: inputBox.top; bottomMargin: 10 }
            width: 34; height: 34; radius: 17
            color: overlay.cardHover
            border.color: overlay.cardStroke; border.width: 1
            Text {
                anchors.centerIn: parent
                text: ""
                color: overlay.theme.fg
                font.family: overlay.theme.ff; font.pixelSize: 13
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { list.stick = true; list.positionViewAtEnd() } }
        }

        // Attached-text pill (iris-ask --edit): type an instruction, send both.
        Rectangle {
            id: attachedPill
            visible: overlay.attached !== ""
            anchors { left: inputBox.left; bottom: inputBox.top; bottomMargin: 6 }
            height: 26; radius: 13
            width: Math.min(inputBox.width, attachedRow.implicitWidth + 20)
            color: overlay.alpha(overlay.theme.primary, 0.14)
            border.color: overlay.alpha(overlay.theme.primary, 0.45); border.width: 1
            Row {
                id: attachedRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: "\uf0c6  " + overlay.tr("attached", "Texte joint") + " · " + overlay.attached.length + " " + overlay.tr("chars", "car.")
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                }
                Text {
                    text: "\uf00d"
                    color: overlay.theme.txt2
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: overlay.attached = "" }
                }
            }
        }

        // Agent menu, under the header's picker.
        Rectangle {
            visible: overlay.agentMenu
            z: 20
            anchors { right: parent.right; rightMargin: 14; top: header.bottom; topMargin: -8 }
            width: 150; height: agentCol.implicitHeight + 12; radius: 14
            color: overlay.theme.bg
            border.color: overlay.cardStroke; border.width: 1
            Column {
                id: agentCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Repeater {
                    model: overlay.agentList
                    delegate: Rectangle {
                        required property string modelData
                        width: agentCol.width; height: 30; radius: 10
                        color: modelData === overlay.agent ? overlay.alpha(overlay.theme.primary, 0.18)
                             : rowHover.hovered ? overlay.cardHover : "transparent"
                        Text {
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10
                                      verticalCenter: parent.verticalCenter }
                            text: modelData
                            elide: Text.ElideRight
                            color: modelData === overlay.agent ? overlay.theme.primary : overlay.theme.fg
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 1
                        }
                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { overlay.agentMenu = false; overlay.cmd({ cmd: "agent", name: modelData }) } }
                    }
                }
            }
        }

        // Pasted-image pill (Ctrl+V), next to the attached-text one when both exist.
        Rectangle {
            visible: overlay.image !== ""
            anchors {
                left: overlay.attached !== "" ? attachedPill.right : inputBox.left
                leftMargin: overlay.attached !== "" ? 6 : 0
                bottom: inputBox.top; bottomMargin: 6
            }
            height: 26; radius: 13
            width: imageRow.implicitWidth + 20
            color: overlay.alpha(overlay.theme.primary, 0.14)
            border.color: overlay.alpha(overlay.theme.primary, 0.45); border.width: 1
            Row {
                id: imageRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: "\uf03e  " + overlay.tr("image_attached", "Image jointe")
                    color: overlay.theme.fg
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                }
                Text {
                    text: "\uf00d"
                    color: overlay.theme.txt2
                    font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 3
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: overlay.image = "" }
                }
            }
        }

        // ── Input ──────────────────────────────────────────────────────
        Rectangle {
            id: inputBox
            anchors { left: parent.left; right: parent.right; bottom: usageRow.top
                      leftMargin: 14; rightMargin: 14; bottomMargin: 8 }
            height: 50
            radius: 25
            color: overlay.wellFill
            border.color: input.activeFocus ? overlay.alpha(overlay.theme.primary, 0.6) : overlay.cardStroke
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 160 } }

            TextInput {
                id: input
                anchors {
                    left: parent.left; leftMargin: 20
                    right: sendBtn.left; rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                color: overlay.theme.fg
                selectionColor: overlay.alpha(overlay.theme.primary, 0.45)
                selectedTextColor: overlay.theme.fg
                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs
                clip: true
                // Ctrl+V still pastes text; if the clipboard holds an image the daemon picks it up.
                Keys.onPressed: e => { if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_V) overlay.cmd({ cmd: "paste_image" }) }
                Keys.onReturnPressed: overlay.send()
                Keys.onEnterPressed:  overlay.send()

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.busy ? overlay.tr("replying", "Iris répond…") : overlay.tr("placeholder", "Demande-moi quelque chose…")
                    color: overlay.theme.outline
                    font: input.font
                }
            }

            // Send / stop
            Rectangle {
                id: sendBtn
                readonly property bool ready: input.text.trim() !== "" || overlay.attached !== "" || overlay.image !== ""
                anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                width: 36; height: 36; radius: 18
                color: overlay.busy ? overlay.theme.error
                     : ready ? overlay.theme.primary
                     : overlay.cardFill
                border.color: overlay.busy || ready ? "transparent" : overlay.cardStroke
                border.width: 1
                scale: sendHover.hovered && (overlay.busy || ready) ? 1.06 : 1
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Text {
                    anchors.centerIn: parent
                    text: overlay.busy ? "" : ""
                    color: overlay.busy || sendBtn.ready ? overlay.theme.bg : overlay.theme.outline
                    font.family: overlay.theme.ff; font.pixelSize: 14
                }
                HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: overlay.busy ? overlay.stop() : overlay.send() }
            }
        }

        // ── Pro usage: two slim gauges + reset time ────────────────────
        Item {
            id: usageRow
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 22; rightMargin: 22; bottomMargin: 12 }
            height: 16

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Repeater {
                    model: [
                        { label: "5 h",     v: overlay.usage5h },
                        { label: "Semaine", v: overlay.usageWeek }
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: 6
                        readonly property color tone: modelData.v > 0.85 ? overlay.theme.error
                                                    : modelData.v > 0.6  ? overlay.theme.warn
                                                    : overlay.theme.primary
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: overlay.theme.outline
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 4
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 54; height: 4; radius: 2
                            color: overlay.wellFill
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, modelData.v))
                                height: parent.height; radius: 2
                                color: parent.parent.tone
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.v < 0 ? "—" : Math.round(modelData.v * 100) + " %"
                            color: modelData.v > 0.6 ? parent.tone : overlay.theme.txt2
                            font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 4
                        }
                    }
                }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: overlay._resetLabel() !== "" ? "󰑓 " + overlay._resetLabel()
                                                   : Qt.formatTime(overlay.now, "HH:mm")
                color: overlay.theme.outline
                font.family: overlay.theme.ff; font.pixelSize: overlay.theme.fs - 4
            }
        }
    }
}
