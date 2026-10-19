//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedLeavingViewTests.swift
//
//  The view a matched geometry group loses as it gains another, carried with
//  the one arriving while its removal plays, as SwiftUI carries it (measured,
//  `Tools/SwiftUIProbes/Matched geometry/mg3.out` A1, A2; decisions
//  B-O4-1): only the matched view, and for as long as it is still leaving.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Scenes

/// The hero with company: collapsed, a card `s` 4×1 at (0, 0) with a line
/// `dd` below it and an avatar `a` 2×1 below that, all in one branch;
/// expanded, the card `B` 8×3 at (20, 6) and the avatar `A` 2×1 at (30, 9).
private struct HeroWithDetails: View {
    let expanded: Bool
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphFill("B").matchedGeometryEffect(id: "card", in: space).frame(width: 8, height: 3)
                        .padding(.leading, 20).padding(.top, 6)
                    GlyphFill("A").matchedGeometryEffect(id: "avatar", in: space).frame(width: 2, height: 1)
                        .padding(.leading, 30)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphFill("s").matchedGeometryEffect(id: "card", in: space).frame(width: 4, height: 1)
                    Text("dd")
                    GlyphFill("a").matchedGeometryEffect(id: "avatar", in: space).frame(width: 2, height: 1)
                }
            }
        }
    }
}

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

    /// SwiftUI moves the matched view alone; what was drawn round it fades
    /// where it was. A fifth of the way, the card's frame is (4, 1) 5×2 and
    /// the leaving 4×1 sits a cell in and down, at (5, 2); the avatar's is
    /// (6, 3) 2×1. The whole branch moved by one of the two carries — the
    /// line with it, and the other matched view a carry not its own.
    @Test("Only the matched views among what leaves are carried, each with its own")
    func onlyMatchedViewsAreCarried() {
        let frames = MatchedFrames()
        frames.draw(HeroWithDetails(expanded: false))
        frames.draw(HeroWithDetails(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        let early = frames.draw(HeroWithDetails(expanded: true), atMillis: 200)
        #expect(rect(of: "s", in: early) == CellRect(x: 5, y: 2, width: 4, height: 1), "\(early)")
        #expect(rect(of: "d", in: early) == CellRect(x: 0, y: 1, width: 2, height: 1), "\(early)")
        #expect(rect(of: "a", in: early) == CellRect(x: 6, y: 3, width: 2, height: 1), "\(early)")
        let end = frames.draw(HeroWithDetails(expanded: true), atMillis: 1100)
        #expect(rect(of: "s", in: end) == nil && rect(of: "d", in: end) == nil, "gone once it has played")
    }

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
