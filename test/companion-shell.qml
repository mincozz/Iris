// Banc d'essai de la mascotte, sans le reste d'Iris :
//   qs -p test/companion-shell.qml            (dans un terminal)
//   qs -p test/companion-shell.qml ipc call companion on|off|toggle
import Quickshell
import QtQuick
import "../overlays"

ShellRoot {
    id: root

    property string assistantMood: "idle"   // essayer thinking / talking à la main
    function openAssistant() { console.log("companion: double-clic → openAssistant()") }

    QtObject {
        id: theme
        property color primary: "#cba6f7"
        property color secondary: "#89b4fa"
        property color tertiary: "#f5c2e7"
        property color txt2: "#a6adc8"
        property string ff: "sans-serif"
    }

    IrisCompanion { shellRoot: root; theme: theme; active: true }
}
