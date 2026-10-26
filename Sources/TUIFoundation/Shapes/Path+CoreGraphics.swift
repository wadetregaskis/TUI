//  🖥️ TUI — A Terminal UI framework for Swift
//  Path+CoreGraphics.swift
//
//  A path to and from CoreGraphics' own, where CoreGraphics exists.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics

// A value conversion intrinsically tied to the platform that has the other
// type, so it ships where that type does and is absent elsewhere — decisions
// A18, the rule `Color(cgColor:)` already follows.
extension Path {
    /// Creates a path from an immutable CoreGraphics path.
    ///
    /// - Parameter path: The path to copy.
    public init(_ path: CGPath) {
        self.init()
        var elements: [Element] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: elements.append(.move(to: points[0]))
            case .addLineToPoint: elements.append(.line(to: points[0]))
            case .addQuadCurveToPoint: elements.append(.quadCurve(to: points[1], control: points[0]))
            case .addCurveToPoint: elements.append(.curve(to: points[2], control1: points[0], control2: points[1]))
            case .closeSubpath: elements.append(.closeSubpath)
            @unknown default: break
            }
        }
        for element in elements { append(element) }
    }

    /// Creates a path from a copy of a mutable CoreGraphics path.
    ///
    /// - Parameter path: The path to copy.
    public init(_ path: CGMutablePath) {
        self.init(path as CGPath)
    }

    /// The path as an immutable CoreGraphics path.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case .move(let to): path.move(to: to)
            case .line(let to): path.addLine(to: to)
            case .quadCurve(let to, let control): path.addQuadCurve(to: to, control: control)
            case .curve(let to, let control1, let control2): path.addCurve(to: to, control1: control1, control2: control2)
            case .closeSubpath: path.closeSubpath()
            }
        }
        return path.copy() ?? path
    }
}
#endif
