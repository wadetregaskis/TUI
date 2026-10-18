//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PathTests.swift
//
//  `Path` against SwiftUI's own: every expected description below was printed
//  by SwiftUI on macOS 15.8 (the W1 lane's `paths.swift` probe, session notes),
//  and is compared point by point, to a thousandth.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUIkitFoundation

/// `path` matches SwiftUI's `description`: the same letters in the same order,
/// and every coordinate within `tolerance`.
func expectPath(_ path: Path, matches swiftUI: String, tolerance: Double = 1e-3, sourceLocation: SourceLocation = #_sourceLocation) {
    let mine = path.description.split(separator: " ")
    let theirs = swiftUI.split(separator: " ")
    #expect(mine.count == theirs.count, "\(path.description)\n≠ \(swiftUI)", sourceLocation: sourceLocation)
    for (a, b) in zip(mine, theirs) {
        if let x = Double(a), let y = Double(b) {
            #expect(abs(x - y) <= tolerance, "\(a) vs \(b) in \(path.description)", sourceLocation: sourceLocation)
        } else {
            #expect(a == b, "\(path.description)\n≠ \(swiftUI)", sourceLocation: sourceLocation)
        }
    }
}

@MainActor
@Suite("Path builds, measures and describes itself as SwiftUI's does")
struct PathTests {

    @Test("A triangle describes itself in SwiftUI's format and parses back")
    func descriptionRoundTrip() {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 10))
        path.closeSubpath()
        #expect(path.description == "0 0 m 10 0 l 10 10 l h")
        #expect(Path(path.description) == path)
        #expect(Path("1 2 x") == nil)
        #expect(Path("1 2 3 m") == nil)
        #expect(Path("")?.isEmpty == true)
        #expect(Path("0 0 m 5 10 10 0 q 0 10 10 10 10 0 c h")?.description == "0 0 m 5 10 10 0 q 0 10 10 10 10 0 c h")
    }

    @Test("Rectangles, rect lists and line lists are SwiftUI's elements")
    func rectangles() {
        #expect(Path(CGRect(x: 1, y: 2, width: 3, height: 4)).description == "1 2 m 4 2 l 4 6 l 1 6 l h")
        let rects = Path {
            $0.addRects([CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 2, y: 2, width: 1, height: 1)])
        }
        #expect(rects.description == "0 0 m 1 0 l 1 1 l 0 1 l h 2 2 m 3 2 l 3 3 l 2 3 l h")
        #expect(Path { $0.addLines([.zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0)]) }.description == "0 0 m 1 1 l 2 0 l")
    }

    @Test("An ellipse is four curves from its trailing point")
    func ellipse() {
        expectPath(
            Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 20)),
            matches: "10 10 m 10 15.5228 7.76142 20 5 20 c 2.23858 20 0 15.5228 0 10 c 0 4.47715 2.23858 0 5 0 c 7.76142 0 10 4.47715 10 10 c h")
    }

    @Test("Rounded rectangles, circular, continuous, uneven and oversized")
    func roundedRectangles() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 10)
        expectPath(
            Path(roundedRect: rect, cornerRadius: 3, style: .circular),
            matches: """
                20 5 m 20 7 l 20 8.65685 18.6569 10 17 10 c 3 10 l 1.34315 10 0 8.65685 0 7 c 0 3 l 0 1.34315 1.34315 0 3 0 c \
                17 0 l 18.6569 0 20 1.34315 20 3 c h
                """)
        expectPath(
            Path(roundedRect: rect, cornerRadius: 3, style: .continuous),
            matches: """
                20 5 m 20 5.41401 l 20 6.73453 20 7.39478 19.7753 8.10552 c 19.4928 8.88153 18.8815 9.49282 18.1055 9.77527 c \
                17.3948 10 16.7345 10 15.414 10 c 4.58599 10 l 3.26547 10 2.60522 10 1.89448 9.77527 c 1.11847 9.49282 0.50718 \
                8.88153 0.224734 8.10552 c 0 7.39478 0 6.73453 0 5.41401 c 0 4.58599 l 0 3.26547 0 2.60522 0.224734 1.89448 c \
                0.50718 1.11847 1.11847 0.50718 1.89448 0.224734 c 2.60522 0 3.26547 0 4.58599 0 c 15.414 0 l 16.7345 0 17.3948 \
                0 18.1055 0.224734 c 18.8815 0.50718 19.4928 1.11847 19.7753 1.89448 c 20 2.60522 20 3.26547 20 4.58599 c h
                """)
        expectPath(
            Path(
                roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 1, bottomLeading: 2, bottomTrailing: 3, topTrailing: 4),
                style: .circular),
            matches: """
                20 5.5 m 20 7 l 20 8.65685 18.6569 10 17 10 c 2 10 l 0.895431 10 0 9.10457 0 8 c 0 1 l 0 0.447715 0.447715 0 1 0 c \
                16 0 l 18.2091 0 20 1.79086 20 4 c h
                """)
        // A radius past half the short side is held to it, a corner size's
        // width and height each.
        expectPath(
            Path(roundedRect: rect, cornerRadius: 30, style: .circular),
            matches: """
                20 5 m 20 5 l 20 7.76142 17.7614 10 15 10 c 5 10 l 2.23858 10 0 7.76142 0 5 c 0 5 l 0 2.23858 2.23858 0 5 0 c \
                15 0 l 17.7614 0 20 2.23858 20 5 c h
                """)
        expectPath(
            Path(roundedRect: rect, cornerSize: CGSize(width: 8, height: 2), style: .circular),
            matches: """
                20 5 m 20 8 l 20 9.10457 17.7614 10 15 10 c 5 10 l 2.23858 10 0 9.10457 0 8 c 0 2 l 0 0.895431 2.23858 0 5 0 c \
                15 0 l 17.7614 0 20 0.895431 20 2 c h
                """)
        // An uneven corner may pass half a side its neighbour leaves room on.
        expectPath(
            Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 8, topTrailing: 8), style: .circular),
            matches: """
                20 9 m 20 10 l 20 10 20 10 20 10 c 0 10 l 0 10 0 10 0 10 c 0 8 l 0 3.58172 3.58172 0 8 0 c 12 0 l 16.4183 0 \
                20 3.58172 20 8 c h
                """)
    }

    @Test("Arcs run clockwise on screen when clockwise is false, as SwiftUI documents")
    func arcs() {
        var arc = Path()
        arc.addArc(center: CGPoint(x: 10, y: 10), radius: 5, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        expectPath(arc, matches: "15 10 m 15 12.7614 12.7614 15 10 15 c")
        var long = Path()
        long.addArc(center: CGPoint(x: 10, y: 10), radius: 5, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true)
        expectPath(long, matches: "15 10 m 15 7.23858 12.7614 5 10 5 c 7.23858 5 5 7.23858 5 10 c 5 12.7614 7.23858 15 10 15 c")
        var relative = Path()
        relative.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .degrees(90))
        expectPath(relative, matches: "1 0 m 1 0.552285 0.552285 1 0 1 c")
        var tangent = Path()
        tangent.move(to: .zero)
        tangent.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 3)
        expectPath(tangent, matches: "0 0 m 7 0 l 8.65685 0 10 1.34315 10 3 c")
    }

    @Test("An arc is cut as SwiftUI cuts it: quarter turns from its start, then what is left")
    func arcPieces() {
        var forward = Path()
        forward.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .degrees(135))
        expectPath(forward, matches: "1 0 m 1 0.552285 0.552285 1 0 1 c -0.265216 1 -0.51957 0.894643 -0.707107 0.707107 c")
        var back = Path()
        back.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(30), delta: .degrees(-200))
        expectPath(
            back,
            matches: """
                0.866025 0.5 m 1.14217 0.0217074 0.978293 -0.589883 0.5 -0.866025 c 0.0217074 -1.14217 -0.589883 \
                -0.978293 -0.866025 -0.5 c -0.924351 -0.398977 -0.964551 -0.288528 -0.984808 -0.173648 c
                """)
    }

    /// Every expectation is SwiftUI's on macOS 15.8 (the W1 review's
    /// `desc.swift` probe, session notes). Before, a NaN angle trapped in
    /// `Int(_:)`, and a turn of `1e10` added six billion curves.
    @Test("An arc of an angle that is no finite number, or a huge one, is SwiftUI's: a move, or 1,023 quarter turns")
    func degenerateArcs() {
        func arc(delta: Double, start: Double = 0) -> Path {
            Path { $0.addRelativeArc(center: .zero, radius: 1, startAngle: .radians(start), delta: .radians(delta)) }
        }
        func curves(_ path: Path) -> Int {
            var count = 0
            path.forEach { if case .curve = $0 { count += 1 } }
            return count
        }
        expectPath(arc(delta: .nan), matches: "1 0 m")
        expectPath(arc(delta: .infinity), matches: "1 0 m")
        #expect(arc(delta: 1, start: .nan).isEmpty)
        var joined = Path()
        joined.move(to: CGPoint(x: 5, y: 5))
        joined.addRelativeArc(center: .zero, radius: 1, startAngle: .zero, delta: .radians(.nan))
        expectPath(joined, matches: "5 5 m 1 0 l")
        // A progress ring with nothing to count, and the absolute arc's own
        // non-finite angles.
        let (done, total) = (0.0, 0.0)
        let ring = Path {
            $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .degrees(360 * done / total), clockwise: false)
        }
        expectPath(ring, matches: "1 0 m")
        let endless = Path {
            $0.addArc(center: .zero, radius: 1, startAngle: .zero, endAngle: .radians(.infinity), clockwise: false)
        }
        expectPath(endless, matches: "1 0 m")
        #expect(Path { $0.addArc(center: .zero, radius: 1, startAngle: .radians(.nan), endAngle: .zero, clockwise: false) }.isEmpty)
        // Past 1,024 quarter turns, 1,023 of them; up to it, every one and the rest.
        for (delta, count, end) in [
            (1e10, 1023, CGPoint(x: 0, y: -1)), (1e20, 1023, CGPoint(x: 0, y: -1)), (-1e4, 1023, CGPoint(x: 0, y: 1)),
            (1607, 1024, CGPoint(x: 0.0752864, y: -0.997162)),
        ] {
            let path = arc(delta: delta)
            #expect(curves(path) == count, "a turn of \(delta)")
            let reached = path.currentPoint ?? .zero
            #expect(abs(reached.x - end.x) < 1e-3 && abs(reached.y - end.y) < 1e-3, "a turn of \(delta) ends at \(reached)")
        }
    }

    @Test("Bounds hold a curve's extremes, not its control points")
    func bounds() {
        let quad = Path { $0.move(to: .zero); $0.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 10)) }
        #expect(quad.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 5))
        let curve = Path {
            $0.move(to: .zero)
            $0.addCurve(to: CGPoint(x: 10, y: 0), control1: CGPoint(x: 0, y: 10), control2: CGPoint(x: 10, y: 10))
        }
        #expect(curve.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 7.5))
        #expect(Path().boundingRect.isNull)
        #expect(Path().isEmpty)
        let lone = Path { $0.move(to: CGPoint(x: 3, y: 3)) }
        #expect(!lone.isEmpty)
        #expect(lone.boundingRect == CGRect(x: 3, y: 3, width: 0, height: 0))
    }

    @Test("Containment by non-zero winding, and by even-odd")
    func containment() {
        var triangle = Path()
        triangle.addLines([.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
        triangle.closeSubpath()
        #expect(triangle.contains(CGPoint(x: 8, y: 2)))
        #expect(!triangle.contains(CGPoint(x: 2, y: 8)))
        let nested = Path {
            $0.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
            $0.addRect(CGRect(x: 2, y: 2, width: 6, height: 6))
        }
        #expect(nested.contains(CGPoint(x: 5, y: 5)))
        #expect(!nested.contains(CGPoint(x: 5, y: 5), eoFill: true))
        #expect(nested.contains(CGPoint(x: 1, y: 5), eoFill: true))
    }

    @Test("Trimming shares the length between segments and splits curves at the parameter")
    func trimming() {
        #expect(Path(CGRect(x: 0, y: 0, width: 10, height: 10)).trimmedPath(from: 0.25, to: 0.75).description == "10 0 m 10 10 l 0 10 l")
        let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10))
        expectPath(
            circle.trimmedPath(from: 0.1, to: 0.3),
            matches: "9.03529 7.95294 m 8.12548 9.19411 6.65685 10 5 10 c 4.44772 10 3.91634 9.91046 3.41961 9.7451 c")
        #expect(circle.trimmedPath(from: 0.6, to: 0.4).isEmpty)
        #expect(circle.trimmedPath(from: 0, to: 1) == circle)
    }

    @Test("The current point, a line with no start, and a close")
    func currentPoint() {
        var path = Path()
        path.addLine(to: CGPoint(x: 3, y: 4))
        #expect(path.isEmpty)
        #expect(path.currentPoint == nil)
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 5, y: 1))
        path.closeSubpath()
        #expect(path.currentPoint == CGPoint(x: 1, y: 1))
    }

    @Test("Transforms and offsets move every point")
    func mapping() {
        let unit = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(unit.applying(CGAffineTransform(scaleX: 2, y: 3)).description == "0 0 m 2 0 l 2 3 l 0 3 l h")
        #expect(unit.offsetBy(dx: 5, dy: 6).description == "5 6 m 6 6 l 6 7 l 5 7 l h")
        var added = Path()
        added.addPath(unit, transform: CGAffineTransform(translationX: 1, y: 1))
        #expect(added.description == "1 1 m 2 1 l 2 2 l 1 2 l h")
    }

    @Test("Corner radii animate as four numbers")
    func cornerRadiiAnimate() {
        var radii = RectangleCornerRadii(topLeading: 1, bottomLeading: 2, bottomTrailing: 3, topTrailing: 4)
        let data = radii.animatableData
        #expect(data.first.first == 1 && data.first.second == 4 && data.second.first == 2 && data.second.second == 3)
        radii.animatableData = AnimatablePair(AnimatablePair(5, 6), AnimatablePair(7, 8))
        #expect(radii == RectangleCornerRadii(topLeading: 5, bottomLeading: 7, bottomTrailing: 8, topTrailing: 6))
    }

    #if canImport(CoreGraphics)
    @Test("A path survives the round trip through CoreGraphics")
    func coreGraphicsRoundTrip() {
        let path = Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 10), cornerRadius: 3)
        #expect(Path(path.cgPath) == path)
    }
    #endif
}
