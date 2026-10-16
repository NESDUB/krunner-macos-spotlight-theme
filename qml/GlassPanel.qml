// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Shapes

Shape {
    id: panel
    property real radius: 30
    property real cornerFactor: 0.68
    property color surfaceColor: "#fa080808"
    property color outlineColor: "#606060"
    property real outlineWidth: 0.9
    property real pathInset: 0.5
    // Optional optical rim on the main glass surface only. Does not tint the fill.
    property bool rimLight: false
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: panel.outlineColor
        strokeWidth: panel.outlineWidth
        fillColor: panel.surfaceColor
        PathSvg {
            path: {
                const inset = panel.pathInset
                const w = panel.width - inset * 2, h = panel.height - inset * 2
                const r = Math.min(panel.radius, h / 2), c = r * panel.cornerFactor
                return "M " + r + " " + inset + " L " + (w-r) + " " + inset + " "
                    + "C " + (w-r+c) + " " + inset + " " + w + " " + (r-c) + " " + w + " " + r
                    + " L " + w + " " + (h-r)
                    + " C " + w + " " + (h-r+c) + " " + (w-r+c) + " " + h + " " + (w-r) + " " + h
                    + " L " + r + " " + h
                    + " C " + (r-c) + " " + h + " " + inset + " " + (h-r+c) + " " + inset + " " + (h-r)
                    + " L " + inset + " " + r
                    + " C " + inset + " " + (r-c) + " " + (r-c) + " " + inset + " " + r + " " + inset + " Z"
            }
        }
    }
    // Highlight the upper curved edge, not a rectangular line. The two masks
    // still follow the filled path; this is a purely visual, noninteractive rim.
    ShapePath {
        strokeColor: panel.rimLight ? "#35ffffff" : "transparent"
        strokeWidth: panel.rimLight ? 0.75 : 0
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathSvg {
            path: {
                if (!panel.rimLight || panel.width < 2 || panel.height < 2) return ""
                const inset = panel.pathInset + 0.9
                const w = panel.width - inset * 2, h = panel.height - inset * 2
                const r = Math.min(panel.radius, h / 2)
                const c = r * panel.cornerFactor
                return "M " + inset + " " + r
                    + " C " + inset + " " + (r-c) + " " + (r-c) + " " + inset + " " + r + " " + inset
                    + " L " + (w-r) + " " + inset
                    + " C " + (w-r+c) + " " + inset + " " + w + " " + (r-c) + " " + w + " " + r
            }
        }
    }

}
