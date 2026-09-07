import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    signal configurationChanged

    function saveConfig() {
        // Plasmoid.configuration writes are persisted automatically by Plasma
    }

    Kirigami.FormLayout {
        Kirigami.FormRow {
            label: i18n("Auto-revert to power-save after idle:")
            description: i18n("When the system is idle (no CPU load) for this many minutes, the APU power mode will automatically switch back to quiet. Set to 0 to disable.")

            Kirigami.SpinBox {
                id: idleSpin
                from: 0
                to: 1440
                stepSize: 5
                value: Plasmoid.configuration.idleRevertMinutes
                onValueChanged: {
                    Plasmoid.configuration.idleRevertMinutes = value
                    root.configurationChanged()
                }
                suffixText: i18n("min")
            }
        }

        Kirigami.FormRow {
            label: i18n("Idle threshold (CPU load):")
            description: i18n("The system is considered idle when the 1-minute load average is below this value. Lower values are stricter.")

            Kirigami.SpinBox {
                id: loadSpin
                from: 0.1
                to: 16
                stepSize: 0.5
                value: Plasmoid.configuration.idleLoadThreshold
                onValueChanged: {
                    Plasmoid.configuration.idleLoadThreshold = value
                    root.configurationChanged()
                }
                suffixText: i18n("load")
            }
        }
    }
}
