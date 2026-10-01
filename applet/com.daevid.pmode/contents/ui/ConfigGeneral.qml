import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as PlasmaDBus
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    property alias cfg_idleRevertMinutes: idleSpin.value
    property real cfg_idleLoadThreshold: 0.5
    property real liveLoad: 0
    property real totalCost: 0
    property real totalWh: 0
    property real ratePerKwh: 0.13
    property real trackingStarted: 0

    readonly property var thresholdValues: [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]

    function refreshLoad() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "GetLoadAverage",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError && reply.values && reply.values.length > 0) {
                const load = Number(reply.values[0]);
                if (load >= 0) root.liveLoad = load;
            }
        }, () => {});
    }

    function refreshEnergy() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "GetEnergy",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError && reply.values && reply.values.length > 0) {
                try {
                    const e = JSON.parse(reply.values[0]);
                    root.totalCost = e.total_cost ?? 0;
                    root.totalWh = e.total_wh ?? 0;
                    root.trackingStarted = e.started ?? 0;
                } catch (err) {}
            }
        }, () => {});
    }

    function resetEnergy() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "ResetEnergy",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, () => {
            root.totalCost = 0;
            root.totalWh = 0;
        }, () => {});
    }

    Component.onCompleted: {
        refreshLoad();
        refreshEnergy();
        root.ratePerKwh = Plasmoid.configuration.energyRatePerKwh ?? 0.13;
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            root.refreshLoad();
            root.refreshEnergy();
        }
    }

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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

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
                text: i18n("Current: %1", root.liveLoad.toFixed(2))
                opacity: 0.8
                horizontalAlignment: Text.AlignRight
            }
        }

        Label {
            text: i18n("Set the timeout to 0 to disable automatic switching. Lower thresholds are stricter. On a 16-core box, a load of 0.5 is roughly one light task running.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }

        Item {
            height: 1
            Layout.fillWidth: true
            Rectangle {
                anchors.fill: parent
                color: "#cccccc"
            }
        }

        Label {
            text: i18n("Energy cost tracking")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.bold: true
        }

        Label {
            text: i18n("Lifetime cost: $%1 (%2 kWh)", root.totalCost.toFixed(2), (root.totalWh / 1000.0).toFixed(2))
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Label {
            visible: root.trackingStarted > 0
            text: i18n("Tracking since: %1", new Date(root.trackingStarted * 1000).toLocaleDateString())
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: i18n("Rate ($/kWh):")
            }

            TextField {
                id: rateField
                text: root.ratePerKwh.toFixed(2)
                validator: DoubleValidator { bottom: 0; top: 100; decimals: 4 }
                onAccepted: {
                    const newRate = Number(rateField.text);
                    if (!isNaN(newRate) && newRate >= 0) {
                        root.ratePerKwh = newRate;
                        Plasmoid.configuration.energyRatePerKwh = newRate;
                        const msg = new PlasmaDBus.dbusMessage({
                            service: "com.evox2.powermode",
                            path: "/com/evox2/powermode",
                            iface: "com.evox2.powermode",
                            member: "SetRate",
                            arguments: [newRate.toFixed(4)]
                        });
                        PlasmaDBus.SessionBus.asyncCall(msg, () => {}, () => {});
                    }
                }
            }
        }

        Button {
            text: i18n("Reset cost counter")
            onClicked: root.resetEnergy()
        }

        Label {
            text: i18n("Tracks total energy consumption since first use. Rate is applied to calculate cost. Reset clears the lifetime total.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.fillWidth: true
        }
    }
}
