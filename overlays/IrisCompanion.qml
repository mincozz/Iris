import QtQuick
import Quickshell
import Quickshell.Io

// Entry point of the walking companion (see CompanionWindow.qml).
// Off by default: `qs ipc call companion on|off|toggle`.
// The IPC handler lives here because a hidden PanelWindow does not create its children.
Scope {
    id: root

    property var shellRoot: null
    required property var theme
    property bool active: false

    IpcHandler {
        target: "companion"
        function on(): void { root.active = true }
        function off(): void { root.active = false }
        function toggle(): void { root.active = !root.active }
    }

    // Called by the shell for every notification (Iris alerts included).
    function notify(app, summary, urgent) { win.notify(app, summary, urgent) }

    CompanionWindow {
        id: win
        shellRoot: root.shellRoot
        theme: root.theme
        active: root.active
    }
}
