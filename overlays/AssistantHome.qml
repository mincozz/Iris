// Home tab of the open island: big mascot, active agent / model, steps of the
// current (or last) turn, unread alerts and the next reminder.
import QtQuick
import Quickshell.Io

Item {
    id: home

    required property var theme
    required property var tr              // function (key, fallback)
    property string mood: "idle"
    property string agent: "claude"
    property bool   agentRemote: false
    property string modelName: ""
    property var    steps: []             // [{ label, done }], 6 at most
    property bool   busy: false
    property var    alerts: []            // unread alert texts, newest last
    property string remindersPath: ""     // reminders.json (read-only)

    // Next reminder; the section is hidden when the file is missing or empty.
    property var nextReminder: null
    FileView {
        path: home.remindersPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let next = null
            try {
                for (const r of JSON.parse(text()))
                    if (r && typeof r.due === "number" && typeof r.text === "string" && (!next || r.due < next.due)) next = r
            } catch (e) {}
            home.nextReminder = next
        }
        onLoadFailed: home.nextReminder = null
    }

    component Section: Text {
        color: home.theme.txt2
        font.family: home.theme.ff; font.pixelSize: 13
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
    }

    Row {
        anchors { fill: parent; margins: 20 }
        spacing: 22

        // Mascot + identity
        Column {
            width: 170
            spacing: 10
            AssistantAvatar {
                theme: home.theme
                mood: home.mood
                size: 150
            }
            Text {
                text: "Iris"
                color: home.theme.fg
                font.family: home.theme.ff; font.pixelSize: home.theme.fs + 6
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: home.agent + (home.modelName !== "" ? " · " + home.modelName : "")
                color: home.theme.txt2
                font.family: home.theme.ff; font.pixelSize: 14
                elide: Text.ElideRight
            }
            Rectangle {
                visible: home.agentRemote
                height: 22; width: remoteTxt.implicitWidth + 16; radius: 11
                color: Qt.rgba(home.theme.warn.r, home.theme.warn.g, home.theme.warn.b, 0.16)
                Text {
                    id: remoteTxt
                    anchors.centerIn: parent
                    text: home.tr("agent_remote", "distant")
                    color: home.theme.warn
                    font.family: home.theme.ff; font.pixelSize: 13
                }
            }
        }

        Column {
            width: parent.width - 170 - 22
            spacing: 14

            Section { text: home.tr("home_steps", "Étapes") }
            Column {
                width: parent.width
                spacing: 4
                Text {
                    visible: home.steps.length === 0
                    text: home.tr("home_no_steps", "Rien en cours.")
                    color: home.theme.outline
                    font.family: home.theme.ff; font.pixelSize: 14
                }
                Repeater {
                    model: home.steps
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        text: (modelData.done ? "  " : "  ") + modelData.label
                        color: modelData.done ? home.theme.txt2 : home.theme.fg
                        font.family: home.theme.ff; font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }
            }

            Section { visible: home.alerts.length > 0; text: home.tr("home_alerts", "Alertes") }
            Column {
                visible: home.alerts.length > 0
                width: parent.width
                spacing: 4
                Repeater {
                    model: home.alerts
                    delegate: Text {
                        required property string modelData
                        width: parent.width
                        text: "• " + modelData
                        color: home.theme.fg
                        font.family: home.theme.ff; font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }
            }

            Section { visible: home.nextReminder !== null; text: home.tr("home_reminder", "Prochain rappel") }
            Text {
                visible: home.nextReminder !== null
                width: parent.width
                text: home.nextReminder === null ? "" :
                      Qt.formatDateTime(new Date(home.nextReminder.due * 1000), "ddd d MMM HH:mm") + " · " + home.nextReminder.text
                color: home.theme.fg
                font.family: home.theme.ff; font.pixelSize: 14
                wrapMode: Text.Wrap
                maximumLineCount: 2; elide: Text.ElideRight
            }
        }
    }
}
