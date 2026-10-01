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
                text: "Strix Halo Power"
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

        Item {
            height: 1
            Layout.fillWidth: true
            Rectangle {
                anchors.fill: parent
                color: "#2a2f35"
            }
        }

        // Power row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "PWR"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Text {
                text: tip.fmt(tip.powerW, " W", 1)
                color: "#3ddc84"
                font.bold: true
                font.pointSize: 10
            }
        }

        // Temperature row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "TMP"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Text {
                text: tip.fmt(tip.tempC, "°C", 0)
                color: "#ff8c42"
                font.bold: true
                font.pointSize: 10
            }
        }

        // Fan rows
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "FAN"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Text {
                text: {
                    let parts = [];
                    if (tip.fan1Rpm > 0) parts.push("1:" + tip.fan1Rpm);
                    if (tip.fan2Rpm > 0) parts.push("2:" + tip.fan2Rpm);
                    if (tip.fan3Rpm > 0) parts.push("3:" + tip.fan3Rpm);
                    return parts.length ? parts.join(" ") : "N/A";
                }
                color: "#c8ccd2"
                font.pointSize: 9
            }
        }

        // Load row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "LDA"
                color: "#8a9199"
                font.pointSize: 9
                Layout.preferredWidth: 40
            }
            Text {
                text: tip.fmt(tip.load1, "", 2)
                color: "#b07fe8"
                font.pointSize: 9
            }
        }

        Text {
            text: i18n("Right-click to change mode")
            color: "#4a4f55"
            font.pointSize: 8
            Layout.topMargin: 4
        }
    }
}
