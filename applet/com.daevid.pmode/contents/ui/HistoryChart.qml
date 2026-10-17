import QtQuick
import org.kde.kirigami as Kirigami

// Hourly power-history line chart, drawn on Canvas (same approach as
// Ring.qml). `points` is a fixed-length array of {hour, w} (w = avg W for
// that hour), oldest first, with missing hours already filled as 0 W.
// Hovering shows a crosshair + a small readout of time/power/cost for the
// nearest point.
Item {
    id: chart

    property var points: []
    property real rate: 0.13  // $/kWh, for the per-hour cost readout
    property color lineColor: "#3ddc84"
    readonly property color gridColor: Qt.rgba(Kirigami.Theme.textColor.r,
        Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
    readonly property color labelColor: Qt.rgba(Kirigami.Theme.textColor.r,
        Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)

    // Shared with the hit-testing in MouseArea below, so hover math and
    // paint math always agree on where points land.
    readonly property int padL: 2
    readonly property int padR: 2
    readonly property int padT: 10
    readonly property int padB: 12

    property int hoverIndex: -1

    function formatHour(epoch) {
        var d = new Date(epoch * 1000)
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var h = d.getHours()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12; if (h === 0) h = 12
        return days[d.getDay()] + " " + h + ampm
    }

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

            var padL = chart.padL, padT = chart.padT
            var w = Math.max(1, width - padL - chart.padR)
            var h = Math.max(1, height - padT - chart.padB)
            var n = chart.points.length

            var maxV = 1  // floor so an all-zero window doesn't divide by 0
            for (var k = 0; k < n; k++) {
                if (chart.points[k].w > maxV) maxV = chart.points[k].w
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
            ctx.moveTo(xAt(0), yAt(chart.points[0].w))
            for (var i = 1; i < n; i++) ctx.lineTo(xAt(i), yAt(chart.points[i].w))
            ctx.lineTo(xAt(n - 1), padT + h)
            ctx.lineTo(xAt(0), padT + h)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(chart.lineColor.r, chart.lineColor.g, chart.lineColor.b, 0.18)
            ctx.fill()

            // the line itself
            ctx.beginPath()
            ctx.moveTo(xAt(0), yAt(chart.points[0].w))
            for (var j = 1; j < n; j++) ctx.lineTo(xAt(j), yAt(chart.points[j].w))
            ctx.strokeStyle = chart.lineColor
            ctx.lineWidth = 1.5
            ctx.stroke()

            // scale label (top-left)
            ctx.fillStyle = chart.labelColor
            ctx.font = "7px sans-serif"
            ctx.textAlign = "left"; ctx.textBaseline = "bottom"
            ctx.fillText(Math.round(maxV) + "W", padL, padT - 1)

            // hover crosshair + readout
            var hi = chart.hoverIndex
            if (hi >= 0 && hi < n) {
                var hx = xAt(hi), hy = yAt(chart.points[hi].w)

                ctx.strokeStyle = chart.gridColor
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(hx, padT); ctx.lineTo(hx, padT + h); ctx.stroke()

                ctx.fillStyle = chart.lineColor
                ctx.beginPath(); ctx.arc(hx, hy, 2.2, 0, Math.PI * 2); ctx.fill()

                var p = chart.points[hi]
                var cost = p.w / 1000.0 * chart.rate
                var line1 = chart.formatHour(p.hour)
                var line2 = Math.round(p.w) + "W  $" + cost.toFixed(4)

                var pad = 6, lineH = 13
                ctx.font = "9px sans-serif"
                var w1 = ctx.measureText(line1).width
                ctx.font = "bold 11px sans-serif"
                var w2 = ctx.measureText(line2).width
                var boxW = Math.max(w1, w2) + pad * 2
                var boxH = lineH * 2 + pad

                var boxX = Math.min(Math.max(hx - boxW / 2, padL), padL + w - boxW)
                var boxY = hy > padT + h / 2 ? padT : padT + 2

                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.82)
                ctx.fillRect(boxX, boxY, boxW, boxH)
                ctx.fillStyle = "#ffffff"
                ctx.textAlign = "left"; ctx.textBaseline = "top"
                ctx.font = "9px sans-serif"
                ctx.fillText(line1, boxX + pad, boxY + pad / 2)
                ctx.font = "bold 11px sans-serif"
                ctx.fillText(line2, boxX + pad, boxY + pad / 2 + lineH)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            if (!chart.points || chart.points.length < 2) return
            var n = chart.points.length
            var w = Math.max(1, width - chart.padL - chart.padR)
            var idx = Math.round((mouse.x - chart.padL) / w * (n - 1))
            chart.hoverIndex = Math.max(0, Math.min(n - 1, idx))
        }
        onExited: chart.hoverIndex = -1
    }

    // Canvas.onPaint does not re-run just because a property it reads
    // changed — without these, the chart only ever paints once.
    onPointsChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onHoverIndexChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
