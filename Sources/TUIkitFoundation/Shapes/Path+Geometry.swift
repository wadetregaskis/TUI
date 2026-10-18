//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Path+Geometry.swift
//
//  What a path covers and how long it is: its bounds, its winding, its
//  trimming, and the polylines the rasterizer draws it from.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Segments

extension Path {
    /// One drawn piece of a path: a line, or a quadratic or cubic Bézier
    /// curve, with its start point spelled out — which an element leaves to
    /// the one before it.
    struct Segment {
        /// The points: two for a line, three for a quadratic, four for a cubic.
        var points: [CGPoint]
        /// Which subpath it belongs to, counting moves from zero.
        var subpath: Int

        /// The point at `t` along it, `0…1`.
        func point(at t: CGFloat) -> CGPoint {
            var work = points
            while work.count > 1 {
                for index in 0..<(work.count - 1) {
                    work[index] = CGPoint(
                        x: work[index].x + (work[index + 1].x - work[index].x) * t,
                        y: work[index].y + (work[index + 1].y - work[index].y) * t)
                }
                work.removeLast()
            }
            return work[0]
        }

        /// The part of it between `t0` and `t1`, by de Casteljau's split.
        func slice(from t0: CGFloat, to t1: CGFloat) -> Self {
            guard points.count > 2 else { return Self(points: [point(at: t0), point(at: t1)], subpath: subpath) }
            // Split at t1, keep the head; split that at t0/t1, keep the tail.
            let head = split(points, at: t1).head
            let tail = t1 > 0 ? split(head, at: t0 / t1).tail : head
            return Self(points: tail, subpath: subpath)
        }

        private func split(_ points: [CGPoint], at t: CGFloat) -> (head: [CGPoint], tail: [CGPoint]) {
            var head: [CGPoint] = [points[0]]
            var tail: [CGPoint] = [points[points.count - 1]]
            var work = points
            while work.count > 1 {
                for index in 0..<(work.count - 1) {
                    work[index] = CGPoint(
                        x: work[index].x + (work[index + 1].x - work[index].x) * t,
                        y: work[index].y + (work[index + 1].y - work[index].y) * t)
                }
                work.removeLast()
                head.append(work[0])
                tail.append(work[work.count - 1])
            }
            return (head, tail.reversed())
        }

        /// How many straight pieces draw it to within `tolerance`: the second
        /// difference of the control points bounds a curve's bend, and a chord
        /// of `1/n` of it strays by at most an eighth of that over `n²`.
        func pieces(tolerance: CGFloat) -> Int {
            guard points.count > 2 else { return 1 }
            var bend: CGFloat = 0
            for index in 0..<(points.count - 2) {
                let dx = points[index].x - 2 * points[index + 1].x + points[index + 2].x
                let dy = points[index].y - 2 * points[index + 1].y + points[index + 2].y
                bend = max(bend, (dx * dx + dy * dy).squareRoot())
            }
            let degree = CGFloat(points.count - 1)
            let pieces = (degree * (degree - 1) * bend / (8 * max(tolerance, 1e-6))).squareRoot().rounded(.up)
            return max(1, min(512, Int(pieces.isFinite ? pieces : 512)))
        }

        /// Its length, along the polyline that draws it to within `tolerance`.
        func length(tolerance: CGFloat) -> CGFloat {
            guard points.count > 2 else { return Self.distance(points[0], points[1]) }
            let count = pieces(tolerance: tolerance)
            var total: CGFloat = 0
            var previous = points[0]
            for index in 1...count {
                let next = point(at: CGFloat(index) / CGFloat(count))
                total += Self.distance(previous, next)
                previous = next
            }
            return total
        }

        static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }
    }

    /// The path as segments, a close as a line back to its subpath's start.
    var segments: [Segment] {
        var segments: [Segment] = []
        var start = CGPoint.zero
        var current = CGPoint.zero
        var subpath = -1
        for element in elements {
            switch element {
            case .move(let to):
                start = to
                current = to
                subpath += 1
            case .line(let to):
                segments.append(Segment(points: [current, to], subpath: subpath))
                current = to
            case .quadCurve(let to, let control):
                segments.append(Segment(points: [current, control, to], subpath: subpath))
                current = to
            case .curve(let to, let control1, let control2):
                segments.append(Segment(points: [current, control1, control2, to], subpath: subpath))
                current = to
            case .closeSubpath:
                segments.append(Segment(points: [current, start], subpath: subpath))
                current = start
            }
        }
        return segments
    }
}

// MARK: - Polylines

extension Path {
    /// A subpath drawn as straight lines: its points, and whether it was
    /// closed. An open one is still filled as though closed.
    struct Contour: Equatable {
        var points: [CGPoint]
        var isClosed: Bool
    }

    /// The path as polylines that stray from its curves by at most
    /// `tolerance`, one per subpath that draws anything.
    func contours(tolerance: CGFloat) -> [Contour] {
        var contours: [Contour] = []
        var points: [CGPoint] = []
        var current = CGPoint.zero
        func finish(closed: Bool) {
            if !points.isEmpty { contours.append(Contour(points: points, isClosed: closed)) }
            points = []
        }
        func curve(_ segment: Segment) {
            if points.isEmpty { points.append(current) }
            let count = segment.pieces(tolerance: tolerance)
            for index in 1...count { points.append(segment.point(at: CGFloat(index) / CGFloat(count))) }
        }
        for element in elements {
            switch element {
            case .move(let to):
                finish(closed: false)
                current = to
                points = [to]
            case .line(let to):
                if points.isEmpty { points.append(current) }
                points.append(to)
                current = to
            case .quadCurve(let to, let control):
                curve(Segment(points: [current, control, to], subpath: 0))
                current = to
            case .curve(let to, let control1, let control2):
                curve(Segment(points: [current, control1, control2, to], subpath: 0))
                current = to
            case .closeSubpath:
                current = points.first ?? current
                finish(closed: true)
            }
        }
        finish(closed: false)
        return contours
    }
}

// MARK: - Bounds and containment

extension Path {
    /// A rectangle containing all path segments: the smallest that encloses
    /// every point ON the path — a curve's extremes, not its control points.
    /// `CGRect.null` for an empty path.
    public var boundingRect: CGRect {
        var (minX, minY) = (CGFloat.infinity, CGFloat.infinity)
        var (maxX, maxY) = (-CGFloat.infinity, -CGFloat.infinity)
        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        for element in elements {
            if case .move(let to) = element { include(to) }
        }
        for segment in segments {
            include(segment.points[0])
            include(segment.points[segment.points.count - 1])
            for t in Self.extremes(of: segment.points) { include(segment.point(at: t)) }
        }
        guard minX <= maxX else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The parameters inside `0…1` where a Bézier curve turns back along an
    /// axis — the roots of its derivative, axis by axis.
    private static func extremes(of points: [CGPoint]) -> [CGFloat] {
        guard points.count > 2 else { return [] }
        var roots: [CGFloat] = []
        for axis in [\CGPoint.x, \CGPoint.y] {
            let p = points.map { $0[keyPath: axis] }
            if p.count == 3 {
                let denominator = p[0] - 2 * p[1] + p[2]
                if denominator != 0 { roots.append((p[0] - p[1]) / denominator) }
            } else {
                // The derivative of a cubic is a quadratic: a t² + b t + c.
                let a = -p[0] + 3 * p[1] - 3 * p[2] + p[3]
                let b = 2 * (p[0] - 2 * p[1] + p[2])
                let c = p[1] - p[0]
                if abs(a) < 1e-12 {
                    if b != 0 { roots.append(-c / b) }
                } else {
                    let discriminant = b * b - 4 * a * c
                    if discriminant >= 0 {
                        let root = discriminant.squareRoot()
                        roots.append((-b + root) / (2 * a))
                        roots.append((-b - root) / (2 * a))
                    }
                }
            }
        }
        return roots.filter { $0 > 0 && $0 < 1 }
    }

    /// Whether `p` is inside the path — every subpath closed for the question —
    /// by the non-zero winding rule, or by even-odd when `eoFill` is `true`.
    ///
    /// - Parameters:
    ///   - p: The point to test.
    ///   - eoFill: Whether to use the even-odd rule.
    /// - Returns: Whether the point is inside.
    public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
        var winding = 0
        for contour in contours(tolerance: 0.01) where contour.points.count > 2 {
            var previous = contour.points[contour.points.count - 1]
            for point in contour.points {
                if (previous.y <= p.y) != (point.y <= p.y) {
                    let x = previous.x + (p.y - previous.y) / (point.y - previous.y) * (point.x - previous.x)
                    if x > p.x { winding += point.y > previous.y ? 1 : -1 }
                }
                previous = point
            }
        }
        return eoFill ? !winding.isMultiple(of: 2) : winding != 0
    }
}

// MARK: - Trimming

extension Path {
    /// The part of the path between `from` and `to`, fractions of its length
    /// from its start — a close counting as the line it draws.
    ///
    /// The fractions are shared out between the path's segments by their
    /// lengths, and each curve is split at the parameter its share names, as
    /// SwiftUI splits it (measured), so a trimmed circle is still curves. A trim that starts at or after where it ends is empty, and one
    /// over the whole length is the path.
    ///
    /// - Parameters:
    ///   - from: Where the kept part starts, `0…1`.
    ///   - to: Where it ends, `0…1`.
    /// - Returns: The kept part.
    public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
        let (from, to) = (min(max(from, 0), 1), min(max(to, 0), 1))
        guard from < to else { return Path() }
        guard from > 0 || to < 1 else { return self }
        let tolerance: CGFloat = 0.01
        let segments = segments
        let lengths = segments.map { $0.length(tolerance: tolerance) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return Path() }
        let (start, end) = (from * total, to * total)
        var trimmed = Path()
        var travelled: CGFloat = 0
        var openSubpath: Int?
        for (segment, length) in zip(segments, lengths) {
            defer { travelled += length }
            guard travelled + length > start, travelled < end, length > 0 else { continue }
            // The fraction of THIS segment's length is its curve parameter:
            // SwiftUI shares the trim between segments by length and then
            // splits each at the parameter, not at an arc length (measured: a
            // circle trimmed to 0.1…0.3 starts at the parameter 0.4 of its
            // first quarter and ends at 0.2 of its second).
            let t0 = min(max((start - travelled) / length, 0), 1)
            let t1 = min(max((end - travelled) / length, 0), 1)
            let piece = segment.slice(from: t0, to: t1)
            if openSubpath != segment.subpath {
                trimmed.move(to: piece.points[0])
                openSubpath = segment.subpath
            }
            switch piece.points.count {
            case 2: trimmed.addLine(to: piece.points[1])
            case 3: trimmed.addQuadCurve(to: piece.points[2], control: piece.points[1])
            default: trimmed.addCurve(to: piece.points[3], control1: piece.points[1], control2: piece.points[2])
            }
        }
        return trimmed
    }
}
