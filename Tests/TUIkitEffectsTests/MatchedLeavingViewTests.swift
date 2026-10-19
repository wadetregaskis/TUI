//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedLeavingViewTests.swift
//
//  The view a matched geometry group loses as it gains another, carried with
//  the one arriving while its removal plays, as SwiftUI carries it (measured,
//  `Tools/SwiftUIProbes/Matched geometry/mg3.out` A1, A2; decisions
//  B-O4-1), for as long as it is still leaving.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Scenes

/// The hero whose removal outlasts the change: the card `s` 4×1 at (0, 0)
/// leaves over two seconds of its own; the one arriving is an 8×3 frame at
/// (20, 6) that paints only its corner, `B`, so what leaves into the middle
/// of it is not covered.
private struct LongLeave: View {
    let expanded: Bool
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                Text("B").frame(width: 8, height: 3, alignment: .topLeading)
                    .matchedGeometryEffect(id: "card", in: space)
                    .padding(.leading, 20).padding(.top, 6)
            } else {
                GlyphFill("s").matchedGeometryEffect(id: "card", in: space).frame(width: 4, height: 1)
                    .transition(.opacity.animation(.linear(duration: 2)))
            }
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("A matched view leaving is carried with the one arriving")
struct MatchedLeavingViewTests {

    /// The carry lands with the change, at a second; the removal plays for
    /// two. SwiftUI leaves the view leaving at the matched frame: in the
    /// 8×3 at (20, 6), the 4×1 sits at (24, 8). It went back to its own
    /// place for the rest of its removal once the one arriving stopped saying
    /// where it was carried.
    @Test("A view leaving after the carry has landed stays where it was carried")
    func leavingViewStaysWhereCarried() {
        let frames = MatchedFrames()
        frames.draw(LongLeave(expanded: false))
        frames.draw(LongLeave(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        _ = frames.draw(LongLeave(expanded: true), atMillis: 500)
        _ = frames.draw(LongLeave(expanded: true), atMillis: 1000)
        let landed = CellRect(x: 24, y: 8, width: 4, height: 1)
        for millis in [1100, 1500, 1900] {
            let screen = frames.draw(LongLeave(expanded: true), atMillis: millis)
            #expect(rect(of: "s", in: screen) == landed, "at \(millis) ms: \(screen)")
        }
        #expect(rect(of: "s", in: frames.draw(LongLeave(expanded: true), atMillis: 2100)) == nil)
    }
}
