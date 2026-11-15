import QtQuick
import QtQuick.Layouts

// Hover tooltip. It paints its own dark card instead of drawing on Plasma's popup
// background, so the colors read the same on light and dark themes (the old
// fixed grays and theme-colored FAN row clashed on a light theme).
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
    readonly property int fanMax: 3000    // bar scale only

    readonly property color textColor: "#e6e9ed"
    readonly property color dimColor: "#8d949c"
    readonly property color trackColor: "#272d34"

    readonly property var fans: {
        let parts = [];
        if (fan1Rpm > 0) parts.push(fan1Rpm);
        if (fan2Rpm > 0) parts.push(fan2Rpm);
        if (fan3Rpm > 0) parts.push(fan3Rpm);
        return parts;
    }

    function fmt(v, suffix, digits) {
        if (v === null || v === undefined) return "N/A";
        return Number(v).toFixed(digits === undefined ? 0 : digits) + (suffix || "");
    }

    function clamp01(v) { return Math.max(0, Math.min(1, v || 0)); }

    implicitWidth: 260
    implicitHeight: card.implicitHeight

    // One metric: colored label, thin bar, value text, dim detail text.
    component MetricRow: RowLayout {
        id: row
        property string label: ""
        property color accent: "#4d9fff"
        property real ratio: 0
        property string value: ""
        property string detail: ""

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: row.label
            color: row.accent
            font.bold: true
            font.pointSize: 8
            Layout.preferredWidth: 32
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: tip.trackColor
            Rectangle {
                width: Math.max(parent.height, parent.width * tip.clamp01(row.ratio))
                visible: row.ratio > 0
                height: parent.height
                radius: 3
                color: row.accent
            }
        }
        Text {
            text: row.value
            color: tip.textColor
            font.bold: true
            font.pointSize: 9
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 40
        }
        Text {
            text: row.detail
            color: tip.dimColor
            font.pointSize: 8
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 80
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: col.implicitHeight + 20
        color: "#14181d"
        radius: 8

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 10
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Strix Halo"
                    color: tip.textColor
                    font.bold: true
                    font.pointSize: 10
                    Layout.fillWidth: true
                }
                Text {
                    text: tip.mode
                    color: "#4d9fff"
                    font.pointSize: 8
                    font.bold: true
                }
            }

            MetricRow {
                label: "PWR"; accent: "#3ddc84"
                ratio: (tip.powerW || 0) / tip.powerMax
                value: tip.fmt(tip.powerW, "W")
                detail: "of " + tip.powerMax + "W"
            }
            MetricRow {
                label: "TMP"; accent: "#b07fe8"
                ratio: (tip.tempC || 0) / tip.tempMax
                value: tip.fmt(tip.tempC, "°")
                detail: ""
            }
            MetricRow {
                label: "FAN"; accent: "#e8c33a"
                ratio: tip.fans.length ? Math.max.apply(null, tip.fans) / tip.fanMax : 0
                value: tip.fans.length ? String(Math.max.apply(null, tip.fans)) : "N/A"
                detail: tip.fans.length > 1 ? tip.fans.join(" / ") : (tip.fans.length ? "rpm" : "")
            }
            MetricRow {
                label: "LOAD"; accent: "#ff8c42"
                ratio: (tip.load1 || 0) / tip.loadMax
                value: tip.fmt(tip.load1, "", 2)
                detail: "of " + tip.loadMax + " cores"
            }

            Text {
                text: i18n("Click for details")
                color: tip.dimColor
                font.pointSize: 7
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 1
            }
        }
    }
}
