// Shell Quickshell minimal pour tester Iris de bout en bout (test/test-e2e.sh).
// Il fournit le strict nécessaire : une racine `root` et un objet `theme`.
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    QtObject {
        id: theme
        property color bg: "#1e1e2e"
        property color fg: "#cdd6f4"
        property color txt2: "#a6adc8"
        property color primary: "#cba6f7"
        property color secondary: "#89b4fa"
        property color tertiary: "#f5c2e7"
        property color lavender: "#b4befe"
        property color light: "#313244"
        property color outline: "#45475a"
        property color error: "#f38ba8"
        property color warn: "#f9e2af"
        property string ff: "sans-serif"
        property int fs: 14
    }
}
