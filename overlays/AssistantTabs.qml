// Tab row of the open island: icon-only tabs, the selected one also shows its label.
import QtQuick

Row {
    id: tabs
    required property var theme
    required property int current
    required property var model      // [{ icon, label }]
    signal picked(int index)
    spacing: 4

    Repeater {
        model: tabs.model
        delegate: Rectangle {
            id: tab
            required property var modelData
            required property int index
            readonly property bool on: tabs.current === index
            height: 34; radius: 17
            width: (on ? content.implicitWidth + 26 : 40)
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            color: on ? Qt.rgba(1, 1, 1, 0.12) : hover.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
                id: content
                anchors.centerIn: parent
                spacing: 7
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.modelData.icon
                    color: tab.on ? tabs.theme.fg : tabs.theme.txt2
                    font.family: tabs.theme.ff; font.pixelSize: 15
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tab.on
                    text: tab.modelData.label
                    color: tabs.theme.fg
                    font.family: tabs.theme.ff; font.weight: Font.Medium; font.pixelSize: tabs.theme.fs - 1
                }
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: tabs.picked(tab.index) }
        }
    }
}
