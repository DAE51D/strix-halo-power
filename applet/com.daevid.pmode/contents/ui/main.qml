import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
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

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

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
    property real trackingStarted: 0

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
                    totalCost = e.total_cost ?? 0;
                    trackingStarted = e.started ?? 0;
                } catch (err) {}
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

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    readonly property int tempMax: 100
    readonly property real powerMax: 150  // EVO-X2 max socket power
    readonly property real loadMax: 16    // 16 cores

    Plasmoid.icon: root.iconForMode(currentMode)

    Component.onCompleted: {
        root.logDebug("applet loaded, initial refresh")
        refresh()
        refreshTelemetry()
        refreshEnergy()
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

    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.refreshEnergy()
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

    // ---- compact representation: just the mode icon ---------------------
    compactRepresentation: Kirigami.Icon {
        width: 24
        height: 24
        source: root.iconForMode(currentMode)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // ---- full representation: ring gauges + stats ----------------------
    fullRepresentation: ColumnLayout {
        id: column
        spacing: 4

        // title top-left; configure + pin actions top-right (matches knvtop)
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "Strix Halo"
                color: Kirigami.Theme.textColor
                font.bold: true
                font.pointSize: 10
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents.ToolTip { text: i18n("Configure…") }
            }

            PlasmaComponents.ToolButton {
                checkable: true
                icon.name: "window-pin"
                onCheckedChanged: root.hideOnWindowDeactivate = !checked
                PlasmaComponents.ToolTip { text: i18n("Keep open") }
            }
        }

        // 4 ring gauges: POWER TEMP FAN LOAD
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            // Power ring
            Item {
                Layout.preferredWidth: 68; Layout.preferredHeight: 68
                Ring {
                    anchors.fill: parent
                    ratio: Math.min(1, root.powerW / root.powerMax)
                    ringColor: "#3ddc84"
                    valueText: root.fmt(root.powerW, "W")
                    label: "POWER"
                }
            }

            // Temp ring
            Item {
                Layout.preferredWidth: 68; Layout.preferredHeight: 68
                Ring {
                    anchors.fill: parent
                    ratio: Math.min(1, root.tempC / root.tempMax)
                    ringColor: "#b07fe8"
                    valueText: root.fmt(root.tempC, "°")
                    label: "TEMP"
                }
            }

            // Fan ring (show fan1 as primary)
            Item {
                Layout.preferredWidth: 68; Layout.preferredHeight: 68
                Ring {
                    anchors.fill: parent
                    ratio: Math.min(1, root.fan1Rpm / 4000)
                    ringColor: "#e8c33a"
                    valueText: root.fan1Rpm > 0 ? root.fmt(root.fan1Rpm, "") : "—"
                    label: "FAN"
                }
            }

            // Load ring
            Item {
                Layout.preferredWidth: 68; Layout.preferredHeight: 68
                Ring {
                    anchors.fill: parent
                    ratio: Math.min(1, root.load1 / root.loadMax)
                    ringColor: "#ff8c42"
                    valueText: root.fmt(root.load1, "", 1)
                    label: "LOAD"
                }
            }
        }

        // stats chips below rings
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Text {
                textFormat: Text.StyledText
                text: i18n("fan <b>%1 / %2 / %3</b>",
                    root.fan1Rpm > 0 ? root.fan1Rpm : "—",
                    root.fan2Rpm > 0 ? root.fan2Rpm : "—",
                    root.fan3Rpm > 0 ? root.fan3Rpm : "—")
                color: Kirigami.Theme.textColor; font.pointSize: 7
            }

            Text {
                textFormat: Text.StyledText
                text: i18n("cost <b>$%1</b>", root.totalCost.toFixed(4))
                color: Kirigami.Theme.textColor; font.pointSize: 7
            }
        }

        // energy tracking info
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: trackingStarted > 0
                ? i18n("since %1", new Date(trackingStarted * 1000).toLocaleDateString())
                : ""
            color: Kirigami.Theme.textColor
            opacity: 0.6
            font.pointSize: 7
        }

        // mode buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2
            spacing: 4

            PlasmaComponents.Button {
                text: i18n("Quiet")
                icon.name: "battery-profile-powersave-symbolic"
                checked: currentMode === "quiet"
                onClicked: root.setMode("quiet")
                font.pointSize: 8
            }
            PlasmaComponents.Button {
                text: i18n("Balanced")
                icon.name: "battery-profile-balanced-symbolic"
                checked: currentMode === "balanced"
                onClicked: root.setMode("balanced")
                font.pointSize: 8
            }
            PlasmaComponents.Button {
                text: i18n("Performance")
                icon.name: "battery-profile-performance-symbolic"
                checked: currentMode === "performance"
                onClicked: root.setMode("performance")
                font.pointSize: 8
            }
        }
    }

    // ---- hover tooltip: compact view with bars ---------------------------
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
