//  🖥️ TUI — A Terminal UI framework for Swift
//  StackZIndexTests.swift
//
//  `.zIndex` orders the children of every container that lets them overlap,
//  not only a `ZStack`'s: SwiftUI's modifier "controls the display order of
//  overlapping views" (Apple's documentation of `View.zIndex(_:)`), and the
//  children of a row, a column or a `Layout` overlap wherever an `.offset`, a
//  negative padding or the layout's own placement puts them. A stack drew a
//  settled row or column in declaration order whatever the z-indices, as a
//  `Layout` drew its subviews in the order it placed them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// Every subview at the layout's origin, one over the next.
private struct Piled: Layout {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return ViewSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CellPoint(x: bounds.x, y: bounds.y), proposal: .unspecified)
        }
    }
}

@MainActor
@Suite("zIndex in a stack and a Layout")
struct StackZIndexTests {
    @Test("A raised view in a row stays over a later sibling moved onto it")
    func rowKeepsTheRaisedViewOnTop() {
        let app = TestApp(width: 10, height: 1) {
            HStack(spacing: 0) {
                Text("AAAA").zIndex(1)
                Text("BBBB").offset(x: -2)
            }
        }
        #expect(app.screen.lines == ["AAAABB"])
    }

    @Test("A raised view moved onto a later sibling in a row is drawn over it")
    func rowDrawsARaisedOffsetViewOver() {
        let raised = TestApp(width: 10, height: 1) {
            HStack(spacing: 0) {
                Text("AAAA").offset(x: 2).zIndex(1)
                Text("BBBB")
            }
        }
        #expect(raised.screen.lines == ["  AAAABB"])
        // Not raised, the later sibling is drawn over it, as before.
        let flat = TestApp(width: 10, height: 1) {
            HStack(spacing: 0) {
                Text("AAAA").offset(x: 2)
                Text("BBBB")
            }
        }
        #expect(flat.screen.lines == ["  AABBBB"])
    }

    @Test("A raised view in a column stays over a later sibling moved onto it")
    func columnKeepsTheRaisedViewOnTop() {
        let app = TestApp(width: 10, height: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AAAA").zIndex(1)
                Text("BB").offset(y: -1)
            }
        }
        #expect(app.screen.lines == ["AAAA", ""])
    }

    @Test("A Layout draws its subviews in ascending z-index")
    func layoutDrawsByZIndex() {
        let app = TestApp(width: 10, height: 1) {
            Piled {
                Text("AAAA").zIndex(1)
                Text("BB")
            }
        }
        #expect(app.screen.lines == ["AAAA"])
    }

    @Test("A grid draws its cells in ascending z-index")
    func gridDrawsByZIndex() {
        let app = TestApp(width: 10, height: 1) {
            Grid(horizontalSpacing: 0) {
                GridRow {
                    Text("AAAA").zIndex(1)
                    Text("BBBB").offset(x: -2)
                }
            }
        }
        #expect(app.screen.lines == ["AAAABB"])
    }

    @Test("A click lands on the raised view where it is drawn over its sibling")
    func clickGoesToTheRaisedView() throws {
        var tapped: [String] = []
        let app = TestApp(width: 10, height: 1) {
            HStack(spacing: 0) {
                Text("AAAA").onTapGesture { tapped.append("A") }.zIndex(1)
                Text("BBBB").onTapGesture { tapped.append("B") }.offset(x: -2)
            }
        }
        app.click(at: CellPoint(x: 3, y: 0))
        app.click(at: CellPoint(x: 5, y: 0))
        #expect(tapped == ["A", "B"])
    }
}
