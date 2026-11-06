import AppKit
import SwiftUI

/// Which edge of the panel the pointer tail grows out of.
///
/// The tail always points back at the text the user selected, so the translation
/// panel reads as an annotation on that text rather than a detached window.
enum BubbleTail {
    case none
    case top
    case bottom
    case left
    case right

    /// Whether the tail adds length along the Y axis (top/bottom) or the X axis.
    var isVertical: Bool { self == .top || self == .bottom }
}

/// Rounded rectangle with an optional tail on one edge, drawn as a single shape
/// so `glassEffect(in:)` renders glass through both the body and the tail.
struct BubbleShape: Shape {
    var cornerRadius: CGFloat = 24
    var tail: BubbleTail = .none
    /// Centre of the tail measured along its edge, in this shape's own
    /// coordinates. Only used when `tail` is not `.none`.
    var tailOffset: CGFloat = 0
    var tailWidth: CGFloat = 26
    var tailLength: CGFloat = 14

    /// How much the shape's bounds grow past the body on the tail side.
    var tailInsets: NSEdgeInsets {
        switch tail {
        case .none: return NSEdgeInsets()
        case .top: return NSEdgeInsets(top: tailLength, left: 0, bottom: 0, right: 0)
        case .bottom: return NSEdgeInsets(top: 0, left: 0, bottom: tailLength, right: 0)
        case .left: return NSEdgeInsets(top: 0, left: tailLength, bottom: 0, right: 0)
        case .right: return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: tailLength)
        }
    }

    func path(in rect: CGRect) -> Path {
        let inset = tailInsets
        let body = CGRect(
            x: rect.minX + inset.left,
            y: rect.minY + inset.top,
            width: rect.width - inset.left - inset.right,
            height: rect.height - inset.top - inset.bottom
        )

        let bodyPath = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        guard tail != .none else { return bodyPath }
        var path = Path()

        // A triangle whose base sits on the body edge, apex on the tail tip. The
        // apex is rounded slightly with quad curves: a razor-sharp point reads as
        // a glitch at these sizes, and the system pointer has a soft tip too.
        let half = tailWidth / 2
        let apexRadius = half * 0.30

        switch tail {
        case .top, .bottom:
            let cx = min(max(tailOffset, body.minX + cornerRadius + half), body.maxX - cornerRadius - half)
            if tail == .top {
                let baseY = body.minY
                let tipY = rect.minY
                path.move(to: CGPoint(x: cx - half, y: baseY))
                path.addLine(to: CGPoint(x: cx - apexRadius * 0.7, y: tipY + apexRadius))
                path.addQuadCurve(
                    to: CGPoint(x: cx + apexRadius * 0.7, y: tipY + apexRadius),
                    control: CGPoint(x: cx, y: tipY - apexRadius * 0.35)
                )
                path.addLine(to: CGPoint(x: cx + half, y: baseY))
            } else {
                let baseY = body.maxY
                let tipY = rect.maxY
                path.move(to: CGPoint(x: cx - half, y: baseY))
                path.addLine(to: CGPoint(x: cx - apexRadius * 0.7, y: tipY - apexRadius))
                path.addQuadCurve(
                    to: CGPoint(x: cx + apexRadius * 0.7, y: tipY - apexRadius),
                    control: CGPoint(x: cx, y: tipY + apexRadius * 0.35)
                )
                path.addLine(to: CGPoint(x: cx + half, y: baseY))
            }
        case .left, .right:
            let cy = min(max(tailOffset, body.minY + cornerRadius + half), body.maxY - cornerRadius - half)
            if tail == .left {
                let baseX = body.minX
                let tipX = rect.minX
                path.move(to: CGPoint(x: baseX, y: cy - half))
                path.addLine(to: CGPoint(x: tipX + apexRadius, y: cy - apexRadius * 0.7))
                path.addQuadCurve(
                    to: CGPoint(x: tipX + apexRadius, y: cy + apexRadius * 0.7),
                    control: CGPoint(x: tipX - apexRadius * 0.35, y: cy)
                )
                path.addLine(to: CGPoint(x: baseX, y: cy + half))
            } else {
                let baseX = body.maxX
                let tipX = rect.maxX
                path.move(to: CGPoint(x: baseX, y: cy - half))
                path.addLine(to: CGPoint(x: tipX - apexRadius, y: cy - apexRadius * 0.7))
                path.addQuadCurve(
                    to: CGPoint(x: tipX - apexRadius, y: cy + apexRadius * 0.7),
                    control: CGPoint(x: tipX + apexRadius * 0.35, y: cy)
                )
                path.addLine(to: CGPoint(x: baseX, y: cy + half))
            }
        case .none:
            break
        }
        path.closeSubpath()
        return bodyPath.union(path)
    }
}
