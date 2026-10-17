import QtQuick
import org.kde.kirigami as Kirigami

// Hourly power-history line chart, drawn on Canvas (same approach as
// Ring.qml). `points` is a fixed-length array of average-W-per-hour
// values, oldest first, with missing hours already filled as 0.
Item {
    id: chart

    property var points: []
    property color lineColor: "#3ddc84"
    readonly property color gridColor: Qt.rgba(Kirigami.Theme.textColor.r,
        Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
    readonly property color labelColor: Qt.rgba(Kirigami.Theme.textColor.r,
        Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            if (!chart.points || chart.points.length < 2) {
                ctx.fillStyle = chart.labelColor
                ctx.font = "7px sans-serif"
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.fillText(i18n("collecting data…"), width / 2, height / 2)
                return
            }

            var padL = 2, padR = 2, padT = 10, padB = 12
            var w = Math.max(1, width - padL - padR)
            var h = Math.max(1, height - padT - padB)
            var n = chart.points.length

            var maxV = 1  // floor so an all-zero window doesn't divide by 0
            for (var k = 0; k < n; k++) {
                if (chart.points[k] > maxV) maxV = chart.points[k]
            }

            function xAt(i) { return padL + (w * i / (n - 1)) }
            function yAt(v) { return padT + h - (h * Math.min(v, maxV) / maxV) }

            // mid + baseline gridlines
            ctx.strokeStyle = chart.gridColor
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(padL, padT); ctx.lineTo(padL + w, padT); ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(padL, padT + h / 2); ctx.lineTo(padL + w, padT + h / 2)
            ctx.stroke()
            ctx.beginPath(); ctx.moveTo(padL, padT + h); ctx.lineTo(padL + w, padT + h); ctx.stroke()

            // filled area under the line
            ctx.beginPath()
            ctx.moveTo(xAt(0), yAt(chart.points[0]))
            for (var i = 1; i < n; i++) ctx.lineTo(xAt(i), yAt(chart.points[i]))
            ctx.lineTo(xAt(n - 1), padT + h)
            ctx.lineTo(xAt(0), padT + h)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(chart.lineColor.r, chart.lineColor.g, chart.lineColor.b, 0.18)
            ctx.fill()

            // the line itself
            ctx.beginPath()
            ctx.moveTo(xAt(0), yAt(chart.points[0]))
            for (var j = 1; j < n; j++) ctx.lineTo(xAt(j), yAt(chart.points[j]))
            ctx.strokeStyle = chart.lineColor
            ctx.lineWidth = 1.5
            ctx.stroke()

            // scale label (top-left)
            ctx.fillStyle = chart.labelColor
            ctx.font = "7px sans-serif"
            ctx.textAlign = "left"; ctx.textBaseline = "bottom"
            ctx.fillText(Math.round(maxV) + "W", padL, padT - 1)
        }
    }

    // Canvas.onPaint does not re-run just because a property it reads
    // changed — without these, the chart only ever paints once.
    onPointsChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
