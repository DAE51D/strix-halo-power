import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as PlasmaDBus

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    property string currentMode: "balanced"

    // Telemetry (populated by TelemetryUpdated signal and GetTelemetry call)
    property real powerW: 0
    property real tempC: 0
    property int fan1Rpm: 0
    property int fan2Rpm: 0
    property int fan3Rpm: 0
    property real load1: 0

    // Energy cost (populated by GetEnergy call)
    property real totalCost: 0
    property real sessionWh: 0

    function updateTelemetry(jsonStr) {
        try {
            const t = JSON.parse(jsonStr);
            if (t.power_w !== undefined) powerW = t.power_w;
            if (t.temp_c !== undefined) tempC = t.temp_c;
            if (t.fan1_rpm !== undefined) fan1Rpm = t.fan1_rpm;
            if (t.fan2_rpm !== undefined) fan2Rpm = t.fan2_rpm;
            if (t.fan3_rpm !== undefined) fan3Rpm = t.fan3_rpm;
            if (t.load1 !== undefined) load1 = t.load1;
        } catch (e) {
            console.log("pmode: failed to parse telemetry:", e);
        }
    }

    function refreshTelemetry() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "GetTelemetry",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError && reply.values && reply.values.length > 0) {
                updateTelemetry(reply.values[0]);
            }
        }, () => {});
    }

    // Idle-revert settings (persisted via Plasmoid.configuration)
    readonly property int idleRevertMinutes: Plasmoid.configuration.idleRevertMinutes ?? 60
    readonly property real idleLoadThreshold: Plasmoid.configuration.idleLoadThreshold ?? 0.5
    property int idleSeconds: 0  // seconds the system has been continuously idle

    function checkIdle() {
        if (idleRevertMinutes <= 0) {
            idleSeconds = 0;
            return;
        }
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "GetLoadAverage",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (reply.isError || !reply.values || reply.values.length === 0) return;
            const load = Number(reply.values[0]);
            if (load < 0) return;
            if (load < idleLoadThreshold) {
                idleSeconds += 60;
            } else {
                idleSeconds = 0;
                return;
            }
            // If we've been idle long enough and not already in quiet mode, revert
            if (idleSeconds >= idleRevertMinutes * 60 && currentMode !== "quiet") {
                logDebug("idle for " + Math.floor(idleSeconds / 60) + " min, reverting to quiet");
                setMode("quiet");
                idleSeconds = 0;
            }
        }, () => {});
    }

    function refresh() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "GetMode",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError && reply.values && reply.values.length > 0) {
                currentMode = reply.values[0];
            }
        }, () => {});
    }

    function cycleMode() {
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "Cycle",
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError && reply.values && reply.values.length > 0) {
                currentMode = reply.values[0];
            }
        }, () => {});
    }

    function logDebug(s) {
        const m = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: "Log",
            arguments: [s]
        });
        PlasmaDBus.SessionBus.asyncCall(m, () => {}, () => {});
    }

    // Plasma 6.6.6 drops dbusMessage arguments (always sends signature ''),
    // so we call a dedicated no-arg method per mode on the C++ bridge.
    function setMode(mode) {
        const member = mode === "quiet" ? "SetQuiet"
                     : mode === "performance" ? "SetPerformance"
                     : "SetBalanced";
        const msg = new PlasmaDBus.dbusMessage({
            service: "com.evox2.powermode",
            path: "/com/evox2/powermode",
            iface: "com.evox2.powermode",
            member: member,
            arguments: []
        });
        PlasmaDBus.SessionBus.asyncCall(msg, (reply) => {
            if (!reply.isError) {
                currentMode = mode;
            }
        }, () => {});
    }

    function iconForMode(mode) {
        if (mode === "quiet") return "battery-profile-powersave-symbolic";
        if (mode === "performance") return "battery-profile-performance-symbolic";
        return "battery-profile-balanced-symbolic";
    }

    Plasmoid.icon: root.iconForMode(currentMode)

    Component.onCompleted: {
        root.logDebug("applet loaded, initial refresh")
        refresh()
        refreshTelemetry()
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            root.refresh()
            root.refreshTelemetry()
        }
    }

    // Idle-revert check: runs every 60 s
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.checkIdle()
    }

    PlasmaDBus.SignalWatcher {
        enabled: true
        busType: PlasmaDBus.BusType.Session
        service: "com.evox2.powermode"
        path: "/com/evox2/powermode"
        iface: "com.evox2.powermode"

        function dbusModeChanged(mode, source) {
            root.currentMode = mode;
        }

        function dbusTelemetryUpdated(telemetry) {
            root.updateTelemetry(telemetry);
        }
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 24
        height: 24
        source: root.iconForMode(currentMode)
    }

    // Compact text label showing power W and temp °C next to the icon
    // (only when not in a narrow panel, or when explicitly shown)
    Label {
        visible: !root.inPanel || Plasmoid.configuration.showTelemetry !== false
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 28
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.pointSize: 9
        text: {
            let parts = [];
            if (root.powerW > 0) parts.push(root.powerW.toFixed(0) + "W");
            if (root.tempC > 0) parts.push(root.tempC.toFixed(0) + "°C");
            return parts.join(" ");
        }
    }

    Plasmoid.toolTipMainText: i18n("Strix Halo Power Mode: %1", currentMode)

    // Custom hover tooltip showing full telemetry
    toolTipItem: ToolTipView {
        mode: root.currentMode
        powerW: root.powerW
        tempC: root.tempC
        fan1Rpm: root.fan1Rpm
        fan2Rpm: root.fan2Rpm
        fan3Rpm: root.fan3Rpm
        load1: root.load1
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Quiet")
            icon.name: "battery-profile-powersave-symbolic"
            onTriggered: { root.logDebug("action triggered: quiet"); root.setMode("quiet") }
        },
        PlasmaCore.Action {
            text: i18n("Balanced")
            icon.name: "battery-profile-balanced-symbolic"
            onTriggered: { root.logDebug("action triggered: balanced"); root.setMode("balanced") }
        },
        PlasmaCore.Action {
            text: i18n("Performance")
            icon.name: "battery-profile-performance-symbolic"
            onTriggered: { root.logDebug("action triggered: performance"); root.setMode("performance") }
        }
    ]
}
