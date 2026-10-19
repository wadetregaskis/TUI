//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedTransitionSourceOnMatchedViewTests.swift
//
//  A matched transition source written on a view in a matched geometry
//  group: two members of the matched geometry registry on one view, which a
//  test of either module alone cannot build.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Two sources, `A` 4×1 at (0, 0) and `B` 8×3 at (20, 0), and a follower `f`
/// of the one `selected` names, laid out 1×1 at (0, 6) — and the view a
/// navigation zoom grows from as well, where `zoomsFrom`.
private struct Picked: View {
    let selected: Int
    let zoomsFrom: Bool
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                GlyphFill("A").frame(width: 4, height: 1).matchedGeometryEffect(id: 0, in: space)
                GlyphFill(" ").frame(width: 16, height: 1)
                GlyphFill("B").frame(width: 8, height: 3).matchedGeometryEffect(id: 1, in: space)
            }
            GlyphFill(" ").frame(width: 1, height: 3)
            if zoomsFrom {
                GlyphFill("f").matchedGeometryEffect(id: selected, in: space, isSource: false)
                    .matchedTransitionSource(id: selected, in: space).frame(width: 1, height: 1)
            } else {
                GlyphFill("f").matchedGeometryEffect(id: selected, in: space, isSource: false)
                    .frame(width: 1, height: 1)
            }
        }
    }
}

@MainActor
@Suite("A matched transition source on a matched view")
struct MatchedTransitionSourceOnMatchedViewTests {

    /// The follower's rectangle on each frame of a carry from `A` to `B`
    /// under a one-second animation, drawn on a page of its own.
    private func carry(zoomsFrom: Bool) -> [CellRect?] {
        let harness = InputChainHarness(width: 40, height: 12) { $0.canAnimate = true }
        func draw(_ selected: Int, atMillis millis: Int) -> CellRect? {
            harness.now = Int64(millis) * 1_000_000
            let buffer = harness.frame(Picked(selected: selected, zoomsFrom: zoomsFrom))
            harness.transaction = Transaction()
            let screen = buffer.compositingOverlays(
                maxWidth: 40, maxHeight: 12, palette: harness.context.environment.palette
            ).lines.map(\.stripped)
            return rect(of: "f", in: screen)
        }
        var drawn = [draw(0, atMillis: 0), draw(0, atMillis: 0)]
        harness.transaction = Transaction(animation: .linear(duration: 1))
        for millis in [0, 250, 500, 750, 1000] { drawn.append(draw(1, atMillis: millis)) }
        return drawn
    }

    @Test("A follower that is a transition source too is carried as one that is not")
    func carriedAsWithout() {
        // The transition source and the effect both draw at the view's
        // identity. Keyed by it alone, the follower read the source's state on
        // the frames it lost a dictionary's walk — an order that changes with
        // each registry, so several pages are drawn — and started a carry from
        // there on every frame, and so was not carried when its source changed.
        let expected = carry(zoomsFrom: false)
        // A quarter of the way, each edge rounded once: 0 → 20, 4 → 28, and
        // 1 → 3 a row and a half short of its end, rounded away from it.
        #expect(expected[3] == CellRect(x: 5, y: 0, width: 5, height: 1))
        for page in 0..<8 {
            #expect(carry(zoomsFrom: true) == expected, "page \(page)")
        }
    }
}
