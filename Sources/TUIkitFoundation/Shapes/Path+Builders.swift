//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Path+Builders.swift
//
//  Path's convenience builders — rectangles, rounded rectangles, ellipses and
//  arcs — with SwiftUI's element structure, measured.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Initialisers

extension Path {
    /// Creates a path containing a rectangle: a move to its top-leading corner
    /// and lines round it, clockwise on screen.
    ///
    /// - Parameter rect: The rectangle.
    public init(_ rect: CGRect) {
        self.init()
        addRect(rect)
    }

    /// Creates a path containing a rounded rectangle.
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - cornerSize: The size of the corners.
    ///   - style: The corner style.
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    /// Creates a path containing a rounded rectangle.
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - cornerRadius: The radius of every corner.
    ///   - style: The corner style.
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
    }

    /// Creates a path containing a rounded rectangle with uneven corners.
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - cornerRadii: The radius of each corner.
    ///   - style: The corner style.
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerRadii: cornerRadii, style: style)
    }

    /// Creates a path containing an ellipse inscribed in `rect`.
    ///
    /// - Parameter rect: The rectangle the ellipse fills.
    public init(ellipseIn rect: CGRect) {
        self.init()
        addEllipse(in: rect)
    }
}

// MARK: - Rectangles and ellipses

extension Path {
    /// Adds a rectangle as a closed subpath, from its top-leading corner and
    /// clockwise on screen.
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - transform: A transform to apply to it first.
    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        addPath(path, transform: transform)
    }

    /// Adds each rectangle as a closed subpath of its own.
    ///
    /// - Parameters:
    ///   - rects: The rectangles.
    ///   - transform: A transform to apply to them first.
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) {
        for rect in rects { addRect(rect, transform: transform) }
    }

    /// Adds an ellipse inscribed in `rect`: four cubic curves from its
    /// trailing point, clockwise on screen.
    ///
    /// - Parameters:
    ///   - rect: The rectangle the ellipse fills.
    ///   - transform: A transform to apply to it first.
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let rect = rect.standardized
        let (rx, ry) = (rect.width / 2, rect.height / 2)
        let (cx, cy) = (rect.midX, rect.midY)
        let (kx, ky) = (Self.circleControl * rx, Self.circleControl * ry)
        var path = Path()
        path.move(to: CGPoint(x: cx + rx, y: cy))
        path.addCurve(
            to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + ky),
            control2: CGPoint(x: cx + kx, y: cy + ry))
        path.addCurve(
            to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - kx, y: cy + ry),
            control2: CGPoint(x: cx - rx, y: cy + ky))
        path.addCurve(
            to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - ky),
            control2: CGPoint(x: cx - kx, y: cy - ry))
        path.addCurve(
            to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + kx, y: cy - ry),
            control2: CGPoint(x: cx + rx, y: cy - ky))
        path.closeSubpath()
        addPath(path, transform: transform)
    }

    /// The control distance, over the radius, of the one cubic curve that
    /// draws a quarter circle: `4/3 · tan(π/8)`.
    static let circleControl: CGFloat = 0.552_284_749_830_793_4
}

// MARK: - Rounded rectangles

extension Path {
    /// Adds a rounded rectangle, starting at the middle of its trailing edge
    /// and going round clockwise on screen, closed.
    ///
    /// Each corner is a quarter ellipse `cornerSize` across, its width and its
    /// height each held to half the rectangle's shorter side, as SwiftUI holds
    /// them (measured).
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - cornerSize: The size of the corners.
    ///   - style: The corner style.
    ///   - transform: A transform to apply to it first.
    public mutating func addRoundedRect(
        in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
        transform: CGAffineTransform = .identity
    ) {
        let rect = rect.standardized
        let limit = min(rect.width, rect.height) / 2
        let size = CGSize(width: min(max(0, cornerSize.width), limit), height: min(max(0, cornerSize.height), limit))
        addPath(Self.roundedRect(rect, corners: CornerSizes(all: size), style: style), transform: transform)
    }

    /// Adds a rounded rectangle with uneven corners, starting on its trailing
    /// edge and going round clockwise on screen, closed.
    ///
    /// A radius may reach past half a side where its neighbour leaves room —
    /// two top corners of 8 round a box 20 wide and 10 tall, as SwiftUI's do
    /// (measured) — so each is held to the shorter side, and two corners that
    /// would still overlap along a side are shrunk together to fit it.
    ///
    /// - Parameters:
    ///   - rect: The rectangle.
    ///   - cornerRadii: The radius of each corner.
    ///   - style: The corner style.
    ///   - transform: A transform to apply to it first.
    public mutating func addRoundedRect(
        in rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous,
        transform: CGAffineTransform = .identity
    ) {
        let rect = rect.standardized
        let limit = min(rect.width, rect.height)
        var (tl, tr, bl, br) = (cornerRadii.topLeading, cornerRadii.topTrailing, cornerRadii.bottomLeading, cornerRadii.bottomTrailing)
        func hold(_ radius: inout CGFloat) { radius = min(max(0, radius), limit) }
        hold(&tl)
        hold(&tr)
        hold(&bl)
        hold(&br)
        // The largest overflow of any side sets one shrink for all four, so
        // corners keep their proportions.
        // Spelled as one call per side, typed: the array of tuples mapped
        // through a ternary took the type checker past CI's solver threshold.
        func fit(_ sum: CGFloat, _ side: CGFloat) -> CGFloat { sum > side && sum > 0 ? side / sum : 1 }
        let widths: CGFloat = min(fit(tl + tr, rect.width), fit(bl + br, rect.width))
        let heights: CGFloat = min(fit(tl + bl, rect.height), fit(tr + br, rect.height))
        let fits = min(widths, heights)
        func size(_ radius: CGFloat) -> CGSize { CGSize(width: radius * fits, height: radius * fits) }
        let corners = CornerSizes(topLeading: size(tl), topTrailing: size(tr), bottomLeading: size(bl), bottomTrailing: size(br))
        addPath(Self.roundedRect(rect, corners: corners, style: style), transform: transform)
    }

    /// The four corners' sizes, already held to what fits.
    struct CornerSizes {
        var topLeading: CGSize
        var topTrailing: CGSize
        var bottomLeading: CGSize
        var bottomTrailing: CGSize

        init(topLeading: CGSize, topTrailing: CGSize, bottomLeading: CGSize, bottomTrailing: CGSize) {
            self.topLeading = topLeading
            self.topTrailing = topTrailing
            self.bottomLeading = bottomLeading
            self.bottomTrailing = bottomTrailing
        }

        init(all size: CGSize) {
            self.init(topLeading: size, topTrailing: size, bottomLeading: size, bottomTrailing: size)
        }
    }

    /// A rounded rectangle's outline, as SwiftUI builds it (measured): a move
    /// to the trailing edge halfway between its two corners' radii, then
    /// corner, line, corner round the box — every corner drawn, a zero one as
    /// degenerate curves — and a close.
    static func roundedRect(_ rect: CGRect, corners: CornerSizes, style: RoundedCornerStyle) -> Path {
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: maxX, y: minY + (corners.topTrailing.height + rect.height - corners.bottomTrailing.height) / 2))
        // Each corner: where it is, its size, the directions of travel along
        // the edge into it (`arrive`) and out of it (`leave`), and its
        // neighbours along the side it shares horizontally and vertically.
        typealias Step = (corner: CGPoint, size: CGSize, arrive: Direction, leave: Direction, across: CGSize, down: CGSize)
        let walk: [Step] = [
            (CGPoint(x: maxX, y: maxY), corners.bottomTrailing, Direction(dx: 0, dy: 1), Direction(dx: -1, dy: 0),
             corners.bottomLeading, corners.topTrailing),
            (CGPoint(x: minX, y: maxY), corners.bottomLeading, Direction(dx: -1, dy: 0), Direction(dx: 0, dy: -1),
             corners.bottomTrailing, corners.topLeading),
            (CGPoint(x: minX, y: minY), corners.topLeading, Direction(dx: 0, dy: -1), Direction(dx: 1, dy: 0),
             corners.topTrailing, corners.bottomLeading),
            (CGPoint(x: maxX, y: minY), corners.topTrailing, Direction(dx: 1, dy: 0), Direction(dx: 0, dy: 1),
             corners.topLeading, corners.bottomTrailing),
        ]
        for step in walk {
            let continuous =
                style == .continuous
                && Self.continuousFits(step.size, beside: step.across, step.down, in: rect.size)
            path.addCorner(at: step.corner, size: step.size, arrive: step.arrive, leave: step.leave, continuous: continuous)
        }
        path.closeSubpath()
        return path
    }

    /// Whether a continuous corner of `size` — which starts half as far again
    /// from its corner as a circle's — fits along each side it shares, with
    /// its neighbour there reaching as far: two continuous corners of radius 3
    /// need a side of 9.2, and one of 4 beside a square corner needs 6.1 (both
    /// measured as SwiftUI's). Where it does not fit, the corner is drawn
    /// circular: SwiftUI blends the two there, by an amount below anything a
    /// cell can show.
    static func continuousFits(_ size: CGSize, beside across: CGSize, _ down: CGSize, in box: CGSize) -> Bool {
        let reach = ContinuousCorner.extent
        return (size.width + across.width) * reach <= box.width + 1e-9
            && (size.height + down.height) * reach <= box.height + 1e-9
    }

    /// Apple's continuous corner, as offsets from the corner over its radius:
    /// three cubic curves, read off SwiftUI's own path (measured, the 20 × 10
    /// `RoundedRectangle` of radius 3 in the W1 probes, `Tools/SwiftUIProbes/Shape paths (W1)/`).
    enum ContinuousCorner {
        /// How far from the corner along each edge the curve begins.
        static let extent: CGFloat = 1.528_665
        /// The three curves, each `(control1, control2, end)`, as (along the
        /// arriving edge back from the corner, along the leaving edge from it).
        static let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 1.088_493, y: 0), CGPoint(x: 0.868_407, y: 0), CGPoint(x: 0.631_494, y: 0.074_911)),
            (CGPoint(x: 0.372_824, y: 0.169_060), CGPoint(x: 0.169_060, y: 0.372_824), CGPoint(x: 0.074_911, y: 0.631_494)),
            (CGPoint(x: 0, y: 0.868_407), CGPoint(x: 0, y: 1.088_493), CGPoint(x: 0, y: extent)),
        ]
    }

    /// A line along the arriving edge to where the corner at `corner` begins,
    /// then the corner itself, ending on the leaving edge.
    ///
    /// `arrive` is the direction of travel along the edge into the corner and
    /// `leave` the direction along the edge out of it; a point `a` back along
    /// the first and `l` out along the second is `corner − arrive·a + leave·l`.
    private mutating func addCorner(at corner: CGPoint, size: CGSize, arrive: Direction, leave: Direction, continuous: Bool) {
        // The radius along each direction: the corner's width runs along a
        // horizontal edge, its height along a vertical one.
        let back = arrive.dx == 0 ? size.height : size.width
        let out = leave.dx == 0 ? size.height : size.width
        func point(back a: CGFloat, out along: CGFloat) -> CGPoint {
            CGPoint(
                x: corner.x - arrive.dx * a * back + leave.dx * along * out,
                y: corner.y - arrive.dy * a * back + leave.dy * along * out)
        }
        if continuous {
            addLine(to: point(back: ContinuousCorner.extent, out: 0))
            for (control1, control2, end) in ContinuousCorner.curves {
                addCurve(
                    to: point(back: end.x, out: end.y), control1: point(back: control1.x, out: control1.y),
                    control2: point(back: control2.x, out: control2.y))
            }
        } else {
            let k = Self.circleControl
            addLine(to: point(back: 1, out: 0))
            addCurve(to: point(back: 0, out: 1), control1: point(back: 1 - k, out: 0), control2: point(back: 0, out: 1 - k))
        }
    }
}

// MARK: - Arcs

extension Path {
    /// Adds an arc of a circle, from `startAngle` to `endAngle`.
    ///
    /// Angles are measured from the positive x axis, and — y pointing down, as
    /// in SwiftUI — increase clockwise on screen. `clockwise` names the
    /// direction in the flipped coordinates SwiftUI documents, so
    /// `clockwise: false` draws the arc of increasing angle, which runs
    /// clockwise on screen. An unclosed subpath is joined to the arc's start by
    /// a line; otherwise the arc starts a subpath. The arc is cubic curves of a
    /// quarter turn or less each.
    ///
    /// As SwiftUI's does (measured): an end angle further round in the
    /// direction drawn is reached however many turns away it is, and one
    /// behind the start by going on round, a turn at most — so 0 to 3π is a
    /// turn and a half, and 0 to 3π `clockwise` half a turn. An arc of exactly
    /// one turn closes its subpath.
    ///
    /// - Parameters:
    ///   - center: The centre of the circle.
    ///   - radius: Its radius.
    ///   - startAngle: Where the arc starts.
    ///   - endAngle: Where it ends.
    ///   - clockwise: The direction, in flipped coordinates — see above.
    ///   - transform: A transform to apply to the arc first.
    public mutating func addArc(
        center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool,
        transform: CGAffineTransform = .identity
    ) {
        let raw = clockwise ? startAngle.radians - endAngle.radians : endAngle.radians - startAngle.radians
        let turn = 2 * Double.pi
        // An angle that is not a finite number is the relative arc's to
        // refuse; a whole turn here would draw a circle SwiftUI does not.
        guard raw.isFinite else {
            addRelativeArc(center: center, radius: radius, startAngle: startAngle, delta: .radians(raw), transform: transform)
            return
        }
        // Behind the start: on round to it, within a turn — and a whole number
        // of turns behind is one turn on, as SwiftUI draws it (the remainder is
        // then -0).
        let sweep = raw >= 0 ? raw : raw.truncatingRemainder(dividingBy: turn) + turn
        addRelativeArc(
            center: center, radius: radius, startAngle: startAngle, delta: .radians(clockwise ? -sweep : sweep),
            transform: transform)
        if sweep == turn { closeSubpath() }
    }

    /// Adds an arc of a circle, from `startAngle` through `delta`.
    ///
    /// A positive `delta` increases the angle, which runs clockwise on screen.
    /// An unclosed subpath is joined to the arc's start by a line; otherwise
    /// the arc starts a subpath. The arc is cubic curves of a quarter turn each
    /// from its start, and one of what is left — SwiftUI's cut (measured).
    ///
    /// An angle that is not a finite number adds what SwiftUI's does
    /// (measured): nothing for the start, only the start for `delta` — so a
    /// progress ring's `360 * done / total` with `total` zero draws nothing.
    /// And like SwiftUI's, an arc is at most 1,024 curves: past that many
    /// quarter turns it stops after 1,023 (measured: a turn of 1,608.4 radians
    /// ends on its end, one of 1,608.6 a quarter turn short of a whole number
    /// of turns), so a turn of `1e10` costs what one of a thousand quarter
    /// turns does.
    ///
    /// - Parameters:
    ///   - center: The centre of the circle.
    ///   - radius: Its radius.
    ///   - startAngle: Where the arc starts.
    ///   - delta: How far it turns.
    ///   - transform: A transform to apply to the arc first.
    public mutating func addRelativeArc(
        center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle, transform: CGAffineTransform = .identity
    ) {
        let (start, turn) = (startAngle.radians, delta.radians)
        guard start.isFinite else { return }
        let origin = CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start)).applying(transform)
        if current != nil, elements.last != .closeSubpath { addLine(to: origin) } else { move(to: origin) }
        guard turn.isFinite, turn != 0 else { return }
        let quarter = Double.pi / 2
        let sign: Double = turn < 0 ? -1 : 1
        // The tolerance keeps a whole number of quarter turns from growing a
        // sliver of a curve out of rounding.
        let needed = (abs(turn) / quarter - 1e-9).rounded(.up)
        let capped = needed > 1024
        let pieces = capped ? 1023 : max(1, Int(needed))
        for piece in 0..<pieces {
            let from = start + sign * quarter * Double(piece)
            let to = piece == pieces - 1 && !capped ? start + turn : from + sign * quarter
            addArcPiece(center: center, radius: radius, from: from, to: to, transform: transform)
        }
    }

    /// One curve of an arc, from angle `from` to angle `to` — a quarter turn
    /// or less.
    private mutating func addArcPiece(center: CGPoint, radius: CGFloat, from: Double, to: Double, transform: CGAffineTransform) {
        let control = 4.0 / 3.0 * tan((to - from) / 4) * radius
        let start = CGPoint(x: center.x + radius * cos(from), y: center.y + radius * sin(from))
        let end = CGPoint(x: center.x + radius * cos(to), y: center.y + radius * sin(to))
        let control1 = CGPoint(x: start.x - control * sin(from), y: start.y + control * cos(from))
        let control2 = CGPoint(x: end.x + control * sin(to), y: end.y - control * cos(to))
        addCurve(to: end.applying(transform), control1: control1.applying(transform), control2: control2.applying(transform))
    }

    /// Adds an arc of `radius` tangent to the line from the current point to
    /// `tangent1End` and to the line from there to `tangent2End`, joined to
    /// the current point by a line.
    ///
    /// With no current point this adds nothing; where the lines are parallel
    /// or the radius is zero it adds a line to `tangent1End`.
    ///
    /// - Parameters:
    ///   - tangent1End: The end of the first tangent line.
    ///   - tangent2End: The end of the second tangent line.
    ///   - radius: The arc's radius.
    ///   - transform: A transform to apply to the arc first.
    public mutating func addArc(
        tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity
    ) {
        guard let start = current else { return }
        let (p0, p1, p2) = (start, tangent1End.applying(transform), tangent2End.applying(transform))
        func unit(_ dx: CGFloat, _ dy: CGFloat) -> Direction? {
            let length = (dx * dx + dy * dy).squareRoot()
            return length > 0 ? Direction(dx: dx / length, dy: dy / length) : nil
        }
        let scale = (abs(transform.a * transform.d - transform.b * transform.c)).squareRoot()
        let r = radius * scale
        guard r > 0, let u1 = unit(p0.x - p1.x, p0.y - p1.y), let u2 = unit(p2.x - p1.x, p2.y - p1.y) else {
            addLine(to: p1)
            return
        }
        let cosine = max(-1, min(1, u1.dx * u2.dx + u1.dy * u2.dy))
        let half = acos(cosine) / 2
        guard half > 1e-9, half < Double.pi / 2 - 1e-9, let bisector = unit(u1.dx + u2.dx, u1.dy + u2.dy) else {
            addLine(to: p1)
            return
        }
        let reach = r / tan(half)
        let t1 = CGPoint(x: p1.x + u1.dx * reach, y: p1.y + u1.dy * reach)
        let t2 = CGPoint(x: p1.x + u2.dx * reach, y: p1.y + u2.dy * reach)
        let centre = CGPoint(x: p1.x + bisector.dx * r / sin(half), y: p1.y + bisector.dy * r / sin(half))
        let from = atan2(t1.y - centre.y, t1.x - centre.x)
        var sweep = atan2(t2.y - centre.y, t2.x - centre.x) - from
        if sweep > Double.pi { sweep -= 2 * Double.pi }
        if sweep < -Double.pi { sweep += 2 * Double.pi }
        addRelativeArc(center: centre, radius: r, startAngle: .radians(from), delta: .radians(sweep))
    }
}

/// A direction of travel in the plane — what `CGVector` is on Apple platforms,
/// which corelibs Foundation on Linux does not have.
private struct Direction {
    let dx: CGFloat
    let dy: CGFloat
}
