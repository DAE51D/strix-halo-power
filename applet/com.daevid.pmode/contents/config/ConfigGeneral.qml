import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property alias cfg_idleRevertMinutes: idleSpin.value
    property real cfg_idleLoadThreshold: thresholdValues[thresholdCombo.currentIndex]

    readonly property var thresholdValues: [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]

    Kirigami.FormLayout {
        SpinBox {
            id: idleSpin
            Kirigami.FormData.label: i18n("Auto-revert after idle:")
            from: 0
            to: 1440
            stepSize: 5
            value: 60
            textFromValue: function(value, locale) {
                return value === 0 ? i18n("Disabled") : i18n("%1 minutes", value)
            }
        }

        ComboBox {
            id: thresholdCombo
            Kirigami.FormData.label: i18n("Idle load threshold:")
            model: root.thresholdValues.map(function(value) { return value.toString() })
            currentIndex: Math.max(0, root.thresholdValues.indexOf(Number(Plasmoid.configuration.idleLoadThreshold)))
            onCurrentIndexChanged: {
                if (currentIndex >= 0) {
                    Plasmoid.configuration.idleLoadThreshold = root.thresholdValues[currentIndex]
                }
            }
        }
    }
}
