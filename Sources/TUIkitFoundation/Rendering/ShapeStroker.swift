//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStroker.swift
//
//  A stroke as the polygons it covers: a quadrilateral per segment, a piece
//  per join and per cap, all turned the same way so that filling them by the
//  non-zero rule draws their union.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The region a stroke covers, as polygons whose union is the stroke.
///
/// A stroke is the set of points within half a line width of the path, cut
/// square at a butt end, extended at a square one, rounded at a round one, and
/// filled out at each corner by the join. Each of those is convex, and each is
/// emitted turning the same way, so where two overlap the winding number is 2
/// and the non-zero rule still counts the point once: the union, with no
/// geometry to clip. ``ShapeCoverage`` draws it.
///
/// That union is the honest answer to what a stroke covers, which is all a
/// cell grid needs. It is not an OUTLINE of the stroke — overlapping pieces are
/// not one edge — so it is not offered as `Path.strokedPath(_:)`, which
/// promises one.
enum ShapeStroker {

    /// The polygons covering `contours` stroked in `style`.
    ///
    /// - Parameters:
    ///   - contours: The path as polylines, in square units.
    ///   - style: The line width, caps, joins, miter limit and dashes, in the
    ///     same units.
    ///   - roundSegments: How many sides a full circle — a round cap or join —
    ///     is drawn with.
    /// - Returns: The polygons, every one turning the same way.
    static func polygons(of contours: [Path.Contour], style: StrokeStyle, roundSegments: Int = 24) -> [[CGPoint]] {
        let halfWidth = style.lineWidth / 2
        guard halfWidth > 0, halfWidth.isFinite else { return [] }
        var pieces: [[CGPoint]] = []
        // Deduplicated again after dashing: a dash of no length — the dotted
        // line `dash: [0, 4]` draws with round caps — is one point, a dot.
        let lines = dashed(contours.map(deduplicated), style: style).map(deduplicated)
        for line in lines {
            stroke(line, halfWidth: halfWidth, style: style, roundSegments: roundSegments, into: &pieces)
        }
        return pieces.map(counterclockwise)
    }

    // MARK: Pieces

    private static func stroke(
        _ line: Path.Contour, halfWidth: CGFloat, style: StrokeStyle, roundSegments: Int, into pieces: inout [[CGPoint]]
    ) {
        let points = line.points
        guard let first = points.first else { return }
        if points.count == 1 {
            // A zero-length subpath is a dot where a cap gives it one, as
            // CoreGraphics draws it.
            switch style.lineCap {
            case .round: pieces.append(circle(at: first, radius: halfWidth, segments: roundSegments))
            case .square:
                pieces.append([
                    CGPoint(x: first.x - halfWidth, y: first.y - halfWidth), CGPoint(x: first.x + halfWidth, y: first.y - halfWidth),
                    CGPoint(x: first.x + halfWidth, y: first.y + halfWidth), CGPoint(x: first.x - halfWidth, y: first.y + halfWidth),
                ])
            default: break
            }
            return
        }
        let count = points.count
        let segmentCount = line.isClosed ? count : count - 1
        for index in 0..<segmentCount {
            let a = points[index]
            let b = points[(index + 1) % count]
            guard let normal = unitNormal(from: a, to: b) else { continue }
            let offset = CGPoint(x: normal.x * halfWidth, y: normal.y * halfWidth)
            pieces.append([
                CGPoint(x: a.x + offset.x, y: a.y + offset.y), CGPoint(x: b.x + offset.x, y: b.y + offset.y),
                CGPoint(x: b.x - offset.x, y: b.y - offset.y), CGPoint(x: a.x - offset.x, y: a.y - offset.y),
            ])
        }
        // A join at every vertex two segments meet at: each inner one, and on a
        // closed line the first too.
        let joined = line.isClosed ? 0..<count : 1..<(count - 1)
        for index in joined {
            let previous = points[(index + count - 1) % count]
            let next = points[(index + 1) % count]
            join(at: points[index], from: previous, to: next, halfWidth: halfWidth, style: style, roundSegments: roundSegments, into: &pieces)
        }
        if !line.isClosed {
            cap(at: points[0], awayFrom: points[1], halfWidth: halfWidth, style: style, roundSegments: roundSegments, into: &pieces)
            cap(
                at: points[count - 1], awayFrom: points[count - 2], halfWidth: halfWidth, style: style,
                roundSegments: roundSegments, into: &pieces)
        }
    }

    /// The piece filling the corner at `vertex`, on its outer side.
    private static func join(
        at vertex: CGPoint, from previous: CGPoint, to next: CGPoint, halfWidth: CGFloat, style: StrokeStyle,
        roundSegments: Int, into pieces: inout [[CGPoint]]
    ) {
        guard let n0 = unitNormal(from: previous, to: vertex), let n1 = unitNormal(from: vertex, to: next) else { return }
        let d0 = CGPoint(x: n0.y, y: -n0.x)
        let d1 = CGPoint(x: n1.y, y: -n1.x)
        let turn = d0.x * d1.y - d0.y * d1.x
        guard abs(turn) > 1e-12 || d0.x * d1.x + d0.y * d1.y < 0 else { return }
        if style.lineJoin == .round {
            pieces.append(circle(at: vertex, radius: halfWidth, segments: roundSegments))
            return
        }
        // The outer side is the one the line turns away from.
        let side: CGFloat = turn > 0 ? -1 : 1
        let outer0 = CGPoint(x: vertex.x + n0.x * halfWidth * side, y: vertex.y + n0.y * halfWidth * side)
        let outer1 = CGPoint(x: vertex.x + n1.x * halfWidth * side, y: vertex.y + n1.y * halfWidth * side)
        let cosine = n0.x * n1.x + n0.y * n1.y
        if style.lineJoin == .miter, cosine > -1 + 1e-9 {
            // The miter's length over the line width is 1 / sin(α/2), α the
            // angle between the segments — CoreGraphics' miter limit's measure.
            let ratio = (2 / (1 + cosine)).squareRoot()
            if ratio <= style.miterLimit {
                let reach = halfWidth * side / (1 + cosine)
                let tip = CGPoint(x: vertex.x + (n0.x + n1.x) * reach, y: vertex.y + (n0.y + n1.y) * reach)
                pieces.append([vertex, outer0, tip, outer1])
                return
            }
        }
        pieces.append([vertex, outer0, outer1])
    }

    /// The piece past an open line's end, by its cap.
    private static func cap(
        at end: CGPoint, awayFrom inner: CGPoint, halfWidth: CGFloat, style: StrokeStyle, roundSegments: Int,
        into pieces: inout [[CGPoint]]
    ) {
        switch style.lineCap {
        case .round:
            pieces.append(circle(at: end, radius: halfWidth, segments: roundSegments))
        case .square:
            guard let normal = unitNormal(from: inner, to: end) else { return }
            let along = CGPoint(x: normal.y * halfWidth, y: -normal.x * halfWidth)
            let across = CGPoint(x: normal.x * halfWidth, y: normal.y * halfWidth)
            pieces.append([
                CGPoint(x: end.x + across.x, y: end.y + across.y),
                CGPoint(x: end.x + across.x + along.x, y: end.y + across.y + along.y),
                CGPoint(x: end.x - across.x + along.x, y: end.y - across.y + along.y),
                CGPoint(x: end.x - across.x, y: end.y - across.y),
            ])
        default:
            break
        }
    }

    // MARK: Dashes

    /// The least a dash pattern's lengths may come to and be drawn as dashes:
    /// a pixel across. CoreGraphics draws a pattern shorter than a device
    /// pixel as the line unbroken, whatever share of it is painted (measured,
    /// the W1 review's `dashfine.swift` probe: at a unit a pixel `[0.75]` and
    /// `[0.1, 0.3]` are solid where `[1]` and `[0.25, 0.75]` are not, and at
    /// four pixels a unit `[0.1]` is solid where `[0.25]` is dashed).
    static let shortestDashPattern: CGFloat = 1

    /// The most lengths of a pattern one stroke walks: past this many, the
    /// line is drawn unbroken. A dashed line longer than any frame — one to the
    /// edge of the plane — would otherwise be walked a dash at a time to its far
    /// end, which CoreGraphics does (measured: `[2, 2]` over 10⁷ units takes it
    /// 0.13 s, and over 10⁹ it does not finish in two minutes). At the limit a
    /// two-length pattern a pixel long still dashes 32,768 pixels of line,
    /// many times round the largest terminal.
    static let dashWalkLimit = 65_536

    /// How long `contour` is, along its points — and back to its start when it
    /// is closed.
    private static func length(of contour: Path.Contour) -> CGFloat {
        let points = contour.points
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += Path.Segment.distance(points[index - 1], points[index])
        }
        if contour.isClosed, let first = points.first, let last = points.last {
            total += Path.Segment.distance(last, first)
        }
        return total
    }

    /// The lines `contours` dash into: the pattern's "on" stretches, as open
    /// lines, the phase walked off from each subpath's start. A contour dashes
    /// whole when the pattern is empty or has no length.
    ///
    /// An odd number of lengths is laid twice end to end, so that painted and
    /// unpainted alternate through it — `[2]` is two painted, two not, and
    /// `[4, 2, 6]` paints the 2 the second time round. That is CoreGraphics'
    /// rule, which SwiftUI strokes by (measured, the W1 review's
    /// `Tools/SwiftUIProbes/Shape paths (W1)/review/arcs.swift`); read as it stood, a lone length was all painted.
    ///
    /// A pattern too fine to show or too long to walk draws the line unbroken
    /// — one whose lengths come to less than ``shortestDashPattern``, or one
    /// that would walk more than ``dashWalkLimit`` of them along the lines
    /// given — so a dash of `1e-6` round a circle, or any dash along a line to
    /// the edge of the plane, costs what a plain stroke does.
    static func dashed(_ contours: [Path.Contour], style: StrokeStyle) -> [Path.Contour] {
        let lengths = style.dash.map { max(0, $0) }
        let pattern = lengths.count.isMultiple(of: 2) ? lengths : lengths + lengths
        let period = pattern.reduce(0, +)
        guard !pattern.isEmpty, period > 0 else { return contours }
        // A length that is not a number fails the `<=`: the line, unbroken.
        let walks = contours.reduce(0) { $0 + length(of: $1) } / period * CGFloat(pattern.count)
        guard lengths.reduce(0, +) >= shortestDashPattern, walks <= CGFloat(dashWalkLimit) else { return contours }
        var lines: [Path.Contour] = []
        for contour in contours {
            var points = contour.points
            if contour.isClosed, let first = points.first { points.append(first) }
            guard points.count > 1 else { continue }
            // Where in the pattern the subpath starts, and whether that is on.
            var index = 0
            var remaining = pattern[0]
            var phase = style.dashPhase.truncatingRemainder(dividingBy: period)
            if phase < 0 { phase += period }
            while phase > 0 {
                if phase < remaining {
                    remaining -= phase
                    phase = 0
                } else {
                    phase -= remaining
                    index = (index + 1) % pattern.count
                    remaining = pattern[index]
                }
            }
            var current: [CGPoint] = index.isMultiple(of: 2) ? [points[0]] : []
            for segment in 0..<(points.count - 1) {
                var from = points[segment]
                let to = points[segment + 1]
                var left = Path.Segment.distance(from, to)
                while left > 0 {
                    let take = min(left, remaining)
                    let point = CGPoint(x: from.x + (to.x - from.x) * take / left, y: from.y + (to.y - from.y) * take / left)
                    if index.isMultiple(of: 2) { current.append(point) }
                    left -= take
                    remaining -= take
                    from = point
                    if remaining <= 1e-12 {
                        if index.isMultiple(of: 2), current.count > 1 { lines.append(Path.Contour(points: current, isClosed: false)) }
                        index = (index + 1) % pattern.count
                        remaining = pattern[index]
                        current = index.isMultiple(of: 2) ? [from] : []
                    }
                }
            }
            if index.isMultiple(of: 2), current.count > 1 { lines.append(Path.Contour(points: current, isClosed: false)) }
        }
        return lines
    }

    // MARK: Geometry

    /// `contour` without points that repeat the one before them, which have
    /// no direction to stroke along.
    private static func deduplicated(_ contour: Path.Contour) -> Path.Contour {
        var points: [CGPoint] = []
        for point in contour.points where points.last.map({ Path.Segment.distance($0, point) > 1e-9 }) ?? true {
            points.append(point)
        }
        if contour.isClosed, points.count > 1, let first = points.first, let last = points.last,
            Path.Segment.distance(first, last) <= 1e-9
        {
            points.removeLast()
        }
        return Path.Contour(points: points, isClosed: contour.isClosed)
    }

    /// The unit normal to the left of travel from `a` to `b` — `(-dy, dx)`
    /// over the length — or `nil` when they coincide.
    private static func unitNormal(from a: CGPoint, to b: CGPoint) -> CGPoint? {
        let length = Path.Segment.distance(a, b)
        guard length > 1e-12 else { return nil }
        return CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
    }

    /// A circle of `radius` round `centre`, as a polygon of `segments` sides.
    private static func circle(at centre: CGPoint, radius: CGFloat, segments: Int) -> [CGPoint] {
        let sides = max(8, segments)
        return (0..<sides).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sides)
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
    }

    /// `polygon` turning the way every piece turns — positive area, in a
    /// y-down plane clockwise on screen — reversed if it turned the other way.
    private static func counterclockwise(_ polygon: [CGPoint]) -> [CGPoint] {
        var area: CGFloat = 0
        var previous = polygon[polygon.count - 1]
        for point in polygon {
            area += previous.x * point.y - point.x * previous.y
            previous = point
        }
        return area < 0 ? polygon.reversed() : polygon
    }
}
