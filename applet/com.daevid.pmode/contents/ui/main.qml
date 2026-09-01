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
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.refresh()
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
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 24
        height: 24
        source: root.iconForMode(currentMode)
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
