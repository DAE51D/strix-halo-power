import QtQuick
import org.kde.kirigami as Kirigami

// Reusable progress ring gauge, drawn on Canvas.
Item {
    id: ring

    property real ratio: 0          // 0..1, arc fill
    property color ringColor: "#4d9fff"
    property string valueText: "0%"
    property string label: ""
    property real trackWidth: 5
    // This ring sits on Plasma's own popup background (follows the system
    // light/dark color scheme), so its text needs to track theme colors.
    property color valueColor: Kirigami.Theme.textColor
    property color labelColor: Qt.rgba(Kirigami.Theme.textColor.r,
        Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.65)
    // The unfilled track: a light tint of the ring's own color.
    readonly property color trackColor: Qt.rgba(ring.ringColor.r,
        ring.ringColor.g, ring.ringColor.b, 0.16)

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - 4
            var frac = Math.max(0, Math.min(1, ring.ratio))

            ctx.lineWidth = ring.trackWidth
            ctx.strokeStyle = ring.trackColor
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()

            ctx.strokeStyle = ring.ringColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2)
            ctx.stroke()

            ctx.fillStyle = ring.valueColor; ctx.font = "bold 12px sans-serif"
            ctx.textAlign = "center"; ctx.textBaseline = "middle"
            ctx.fillText(ring.valueText, cx, cy - 3)

            ctx.font = "7px sans-serif"; ctx.fillStyle = ring.labelColor
            ctx.fillText(ring.label, cx, cy + 10)
        }
    }

    // Canvas.onPaint does not re-run just because a property it reads
    // changed — without these, the ring only ever paints once.
    onRatioChanged: canvas.requestPaint()
    onValueTextChanged: canvas.requestPaint()
    onRingColorChanged: canvas.requestPaint()
    onLabelChanged: canvas.requestPaint()
    onValueColorChanged: canvas.requestPaint()
    onLabelColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
