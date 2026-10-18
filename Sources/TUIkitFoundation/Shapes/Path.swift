//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Path.swift
//
//  The outline of a 2D shape: SwiftUI's `Path`, as a list of elements.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Path

/// The outline of a 2D shape — mirrors SwiftUI's `Path`.
///
/// A path is coordinates: moves, lines, quadratic and cubic Bézier curves, and
/// closes. Every builder SwiftUI has is here, with SwiftUI's element structure
/// — a circle is four cubic curves starting at its trailing point, a rectangle
/// four lines from its top-leading corner — so a path built here describes
/// itself (``description``) as SwiftUI's would.
///
/// ## Its unit
///
/// A path's coordinates are in **square units**: one unit is one column across,
/// and a row is ``EnvironmentValues/imageCellAspect`` units down — about two,
/// the height of a cell over its width. That is what a ``Shape`` is handed in
/// ``Shape/path(in:)``, so `addEllipse(in:)` over a square rectangle comes out
/// round on screen, and literal lengths — a line width, a corner radius, a
/// dash — are in columns, the same deliberate choice `.padding(2)` is
/// (refusal review O0, ruled 2026-10-12). A path drawn as a view is
/// rasterised at sub-cell resolution and composited, so its partial coverage
/// is antialiasing.
///
/// ## What is not here
///
/// The boolean operations — `union`, `intersection`, `subtracting`,
/// `symmetricDifference`, `lineIntersection`, `lineSubtraction`, `normalized` —
/// and `strokedPath(_:)` need exact geometric clipping or offsetting, and are
/// absent: a call to one fails to compile rather than drawing something else.
public struct Path: Equatable, Sendable {
    /// An element of a path — mirrors SwiftUI's `Path.Element`.
    public enum Element: Equatable, Sendable {
        /// A move to a new point, starting a subpath.
        case move(to: CGPoint)
        /// A straight line from the current point to `to`.
        case line(to: CGPoint)
        /// A quadratic Bézier curve to `to`, pulled toward `control`.
        case quadCurve(to: CGPoint, control: CGPoint)
        /// A cubic Bézier curve to `to`, pulled toward `control1` and then
        /// `control2`.
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        /// A line back to the start of the current subpath, closing it.
        case closeSubpath
    }

    /// The elements, in order.
    private(set) var elements: [Element] = []

    /// Where the current subpath started — where a close returns to — or `nil`
    /// before the first move.
    private(set) var subpathStart: CGPoint?

    /// The current point, or `nil` before the first move.
    private(set) var current: CGPoint?

    /// Creates an empty path.
    public init() {}

    /// Creates an empty path, then executes a closure to add its initial
    /// elements.
    ///
    /// - Parameter callback: The function that adds the path's elements.
    public init(_ callback: (inout Self) -> Void) {
        callback(&self)
    }

    /// Whether the path contains no elements at all.
    public var isEmpty: Bool { elements.isEmpty }

    /// The last point in the path, or `nil` if the path contains no points.
    ///
    /// After a close, the start of the subpath it closed — where the next
    /// element would begin.
    public var currentPoint: CGPoint? { current }

    /// Calls `body` with each element of the path, in order.
    ///
    /// - Parameter body: The function to call with each element.
    public func forEach(_ body: (Element) -> Void) {
        elements.forEach(body)
    }

    /// Two paths are equal when they are made of the same elements.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.elements == rhs.elements
    }
}

// MARK: - Building

extension Path {
    /// Begins a new subpath at `end`.
    ///
    /// - Parameter end: The new subpath's starting point.
    public mutating func move(to end: CGPoint) {
        elements.append(.move(to: end))
        subpathStart = end
        current = end
    }

    /// Appends a straight line from the current point to `end`.
    ///
    /// With no current point this adds nothing, as SwiftUI's does (measured).
    ///
    /// - Parameter end: Where the line ends.
    public mutating func addLine(to end: CGPoint) {
        guard current != nil else { return }
        reopenIfClosed()
        elements.append(.line(to: end))
        current = end
    }

    /// Appends a quadratic Bézier curve from the current point to `end`.
    ///
    /// - Parameters:
    ///   - end: Where the curve ends.
    ///   - control: The control point.
    public mutating func addQuadCurve(to end: CGPoint, control: CGPoint) {
        guard current != nil else { return }
        reopenIfClosed()
        elements.append(.quadCurve(to: end, control: control))
        current = end
    }

    /// Appends a cubic Bézier curve from the current point to `end`.
    ///
    /// - Parameters:
    ///   - end: Where the curve ends.
    ///   - control1: The first control point.
    ///   - control2: The second control point.
    public mutating func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        guard current != nil else { return }
        reopenIfClosed()
        elements.append(.curve(to: end, control1: control1, control2: control2))
        current = end
    }

    /// Closes the current subpath with a line back to its start.
    ///
    /// The current point becomes that start. Closing a path with no open
    /// subpath does nothing.
    public mutating func closeSubpath() {
        guard let start = subpathStart, let last = elements.last, last != .closeSubpath else { return }
        elements.append(.closeSubpath)
        current = start
    }

    /// Appends straight lines through `lines`: a move to the first point, then
    /// a line to each of the rest.
    ///
    /// - Parameter lines: The points, in order.
    public mutating func addLines(_ lines: [CGPoint]) {
        guard let first = lines.first else { return }
        move(to: first)
        for point in lines.dropFirst() { addLine(to: point) }
    }

    /// Appends a copy of `path`, mapped through `transform`.
    ///
    /// - Parameters:
    ///   - path: The path to add.
    ///   - transform: The transform to apply to it first.
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) {
        let mapped = transform.isIdentity ? path : path.applying(transform)
        for element in mapped.elements { append(element) }
    }

    /// Appends one element through the builders, so the current point and the
    /// subpath's start stay true.
    mutating func append(_ element: Element) {
        switch element {
        case .move(let to): move(to: to)
        case .line(let to): addLine(to: to)
        case .quadCurve(let to, let control): addQuadCurve(to: to, control: control)
        case .curve(let to, let control1, let control2): addCurve(to: to, control1: control1, control2: control2)
        case .closeSubpath: closeSubpath()
        }
    }

    /// A drawing element straight after a close starts its subpath again where
    /// the closed one began, as CoreGraphics does: the close left the current
    /// point there.
    private mutating func reopenIfClosed() {
        guard elements.last == .closeSubpath, let start = subpathStart else { return }
        elements.append(.move(to: start))
    }
}

// MARK: - Mapping

extension Path {
    /// This path with every point mapped through `transform`.
    ///
    /// - Parameter transform: The transform to apply.
    /// - Returns: The mapped path.
    public func applying(_ transform: CGAffineTransform) -> Path {
        guard !transform.isIdentity else { return self }
        return mapPoints { $0.applying(transform) }
    }

    /// This path moved by `(dx, dy)`.
    ///
    /// - Parameters:
    ///   - dx: The horizontal offset.
    ///   - dy: The vertical offset.
    /// - Returns: The moved path.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
        mapPoints { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// Every point of every element through `map`, the structure unchanged.
    func mapPoints(_ map: (CGPoint) -> CGPoint) -> Path {
        var mapped = Path()
        mapped.elements.reserveCapacity(elements.count)
        for element in elements {
            switch element {
            case .move(let to): mapped.move(to: map(to))
            case .line(let to): mapped.addLine(to: map(to))
            case .quadCurve(let to, let control): mapped.addQuadCurve(to: map(to), control: map(control))
            case .curve(let to, let control1, let control2):
                mapped.addCurve(to: map(to), control1: map(control1), control2: map(control2))
            case .closeSubpath: mapped.closeSubpath()
            }
        }
        return mapped
    }
}

// MARK: - As a string

extension Path: LosslessStringConvertible {
    /// A description of the path that may be used to recreate it with
    /// `init?(_:)`: each element's points, then its letter — `m`
    /// move, `l` line, `q` quadratic curve, `c` cubic curve, `h` close —
    /// SwiftUI's own format (`0 0 m 10 0 l 10 10 l h`).
    public var description: String {
        var words: [String] = []
        func add(_ points: CGPoint..., op: String) {
            for point in points {
                words.append(Self.format(point.x))
                words.append(Self.format(point.y))
            }
            words.append(op)
        }
        for element in elements {
            switch element {
            case .move(let to): add(to, op: "m")
            case .line(let to): add(to, op: "l")
            case .quadCurve(let to, let control): add(control, to, op: "q")
            case .curve(let to, let control1, let control2): add(control1, control2, to, op: "c")
            case .closeSubpath: words.append("h")
            }
        }
        return words.joined(separator: " ")
    }

    /// Initializes from the result of a previous call to ``description``.
    /// Fails if the string does not describe a valid path; an empty string is
    /// an empty path.
    ///
    /// - Parameter string: The description to parse.
    public init?(_ string: String) {
        self.init()
        var numbers: [CGFloat] = []
        for word in string.split(whereSeparator: \.isWhitespace) {
            if let number = Double(word) {
                numbers.append(CGFloat(number))
                continue
            }
            guard let element = Self.element(word, operands: &numbers) else { return nil }
            append(element)
        }
        guard numbers.isEmpty else { return nil }
    }

    /// The element `letter` names, made from `operands` — which it empties —
    /// or `nil` when the letter is unknown or the operands are the wrong
    /// count for it.
    private static func element(_ letter: Substring, operands: inout [CGFloat]) -> Element? {
        let counts: [Substring: Int] = ["m": 1, "l": 1, "q": 2, "c": 3, "h": 0]
        guard let count = counts[letter], operands.count == count * 2 else { return nil }
        let points = (0..<count).map { CGPoint(x: operands[$0 * 2], y: operands[$0 * 2 + 1]) }
        operands.removeAll(keepingCapacity: true)
        switch letter {
        case "m": return .move(to: points[0])
        case "l": return .line(to: points[0])
        case "q": return .quadCurve(to: points[1], control: points[0])
        case "c": return .curve(to: points[2], control1: points[0], control2: points[1])
        default: return .closeSubpath
        }
    }

    /// A coordinate the way SwiftUI writes one: six significant digits, no
    /// trailing zeros (`12.7614`, `1.01453e-16`, `10`).
    private static func format(_ value: CGFloat) -> String {
        String(format: "%g", Double(value))
    }
}
