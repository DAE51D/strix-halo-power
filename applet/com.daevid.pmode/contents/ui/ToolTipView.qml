import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: tip

    property string mode: "balanced"
    property real powerW: 0
    property real tempC: 0
    property int fan1Rpm: 0
    property int fan2Rpm: 0
    property int fan3Rpm: 0
    property real load1: 0

    readonly property int tempMax: 100
    readonly property real powerMax: 150  // EVO-X2 max socket power
    readonly property real loadMax: 16    // 16 cores

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6
        width: 220

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Strix Halo"
                font.bold: true
                font.pointSize: 11
                Layout.fillWidth: true
            }
            Text {
                text: tip.mode
                color: "#4d9fff"
                font.pointSize: 9
                font.bold: true
            }
        }

        // Power row with bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "POWER"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 44
            }
            Text {
                text: tip.fmt(tip.powerW, "W", 0)
                color: "#3ddc84"
                font.bold: true
                font.pointSize: 10
                Layout.preferredWidth: 40
            }
            Item { Layout.fillWidth: true }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * Math.min(1, tip.powerW / tip.powerMax)
                height: parent.height
                color: "#3ddc84"
                radius: 2
            }
        }

        // Temperature row with bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "TEMP"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 44
            }
            Text {
                text: tip.fmt(tip.tempC, "°", 0)
                color: "#b07fe8"
                font.bold: true
                font.pointSize: 10
                Layout.preferredWidth: 40
            }
            Item { Layout.fillWidth: true }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * Math.min(1, tip.tempC / tip.tempMax)
                height: parent.height
                color: "#b07fe8"
                radius: 2
            }
        }

        // Fan row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "FAN"
                color: Kirigami.Theme.textColor
                font.pointSize: 9
                Layout.preferredWidth: 32
            }
            Text {
                text: {
                    let parts = [];
                    if (tip.fan1Rpm > 0) parts.push(tip.fan1Rpm);
                    if (tip.fan2Rpm > 0) parts.push(tip.fan2Rpm);
                    if (tip.fan3Rpm > 0) parts.push(tip.fan3Rpm);
                    return parts.length ? parts.join(" / ") + " rpm" : "N/A";
                }
                color: Kirigami.Theme.textColor
                font.pointSize: 9
            }
        }

        // Load row with bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "LOAD"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 44
            }
            Text {
                text: tip.fmt(tip.load1, "", 2)
                color: "#ff8c42"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Item { Layout.fillWidth: true }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "#2a2f35"
            radius: 2
            Rectangle {
                width: parent.width * Math.min(1, tip.load1 / tip.loadMax)
                height: parent.height
                color: "#ff8c42"
                radius: 2
            }
        }

        Text {
            text: i18n("Click for details")
            color: "#4a4f55"
            font.pointSize: 8
            Layout.topMargin: 4
        }
    }
}
