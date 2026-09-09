import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property alias cfg_idleRevertMinutes: idleSpin.value
    property real cfg_idleLoadThreshold: 0.5

    readonly property var thresholdValues: [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 12

        Label {
            text: i18n("Automatically return to Quiet mode after idle")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        SpinBox {
            id: idleSpin
            from: 0
            to: 1440
            stepSize: 5
            value: 60
            Layout.fillWidth: true
            textFromValue: function(value, locale) {
                return value === 0 ? i18n("Disabled") : i18n("%1 minutes", value)
            }
        }

        Label {
            text: i18n("Idle load threshold (1-minute load average)")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ComboBox {
            id: thresholdCombo
            model: root.thresholdValues.map(function(value) { return value.toString() })
            currentIndex: Math.max(0, root.thresholdValues.indexOf(Number(Plasmoid.configuration.idleLoadThreshold)))
            Layout.fillWidth: true
            onCurrentIndexChanged: {
                if (currentIndex >= 0) {
                    root.cfg_idleLoadThreshold = root.thresholdValues[currentIndex]
                }
            }
        }

        Label {
            text: i18n("Set the timeout to 0 to disable automatic switching. Lower thresholds are stricter.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }
    }
}
