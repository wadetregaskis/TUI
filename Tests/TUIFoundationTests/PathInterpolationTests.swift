//  🖥️ TUI — A Terminal UI framework for Swift
//  PathInterpolationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIFoundation

/// `Path.interpolated(towards:amount:)`: point by point between paths of one
/// structure, a swap at the midpoint between paths of two.
@MainActor
@Suite("Path interpolation")
struct PathInterpolationTests {
    private let square = Path(CGRect(x: 0, y: 0, width: 10, height: 10))

    /// A diamond in the square's bounds, drawn as the square is: a move,
    /// three lines and a close.
    private let diamond = Path {
        $0.move(to: CGPoint(x: 5, y: 0))
        $0.addLine(to: CGPoint(x: 10, y: 5))
        $0.addLine(to: CGPoint(x: 5, y: 10))
        $0.addLine(to: CGPoint(x: 0, y: 5))
        $0.closeSubpath()
    }

    @Test("Halfway between a square and a diamond of the same structure, every point is halfway")
    func halfway() {
        expectPath(square.interpolated(towards: diamond, amount: 0.5), matches: "2.5 0 m 10 2.5 l 7.5 10 l 0 7.5 l h")
    }

    @Test("Amount 0 is the path itself and 1 is the other, exactly")
    func ends() {
        #expect(square.interpolated(towards: diamond, amount: 0) == square)
        #expect(square.interpolated(towards: diamond, amount: 1) == diamond)
    }

    @Test("Amount is not clamped: an overshoot carries the points past the other path")
    func overshoot() {
        expectPath(square.interpolated(towards: diamond, amount: 2), matches: "10 0 m 10 10 l 0 10 l 0 0 l h")
    }

    @Test("Curves interpolate their control points too: one ellipse into another")
    func curves() {
        let small = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        let large = Path(ellipseIn: CGRect(x: 0, y: 0, width: 20, height: 20))
        let middle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 15, height: 15))
        expectPath(small.interpolated(towards: large, amount: 0.5), matches: middle.description)
    }

    @Test("Paths of different structure swap at the midpoint, without resampling")
    func differentStructureSwaps() {
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(square.interpolated(towards: circle, amount: 0.49) == square)
        #expect(square.interpolated(towards: circle, amount: 0.5) == circle)
        // The same count of elements, of different kinds, swaps as well.
        let quads = Path {
            $0.move(to: .zero)
            $0.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: -5))
            $0.addLine(to: CGPoint(x: 10, y: 10))
            $0.addLine(to: CGPoint(x: 0, y: 10))
            $0.closeSubpath()
        }
        #expect(square.interpolated(towards: quads, amount: 0.25) == square)
        #expect(square.interpolated(towards: quads, amount: 0.75) == quads)
    }

    @Test("An empty path into an empty path is empty")
    func empty() {
        #expect(Path().interpolated(towards: Path(), amount: 0.5).isEmpty)
    }
}
