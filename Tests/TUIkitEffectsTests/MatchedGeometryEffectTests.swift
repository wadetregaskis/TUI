//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MatchedGeometryEffectTests.swift
//
//  `matchedGeometryEffect`: a follower drawn at its source's geometry, as
//  SwiftUI was measured drawing one (macOS 15.8, 2026-10-18: offscreen
//  NSHostingView probes reading the layer tree's presentation frames,
//  `Tools/SwiftUIProbes/Matched geometry/mg1`–`mg3`), and a view carried
//  between two frames under an animation. Points there are cells here.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

// MARK: - Harness

/// Frames rendered the way the run loop renders them — the scene root's
/// geometry answered, and the frame drawn again when a reader or a matched
/// view drew from a wrong answer (`InputChainHarness`) — on a clock a test
/// moves, each frame under the animation it is given, read as the screen
/// shows it: layers composited, styling stripped.
@MainActor
private final class Frames {
    let harness: InputChainHarness

    init(width: Int = 40, height: Int = 12, reducesMotion: Bool = false) {
        harness = InputChainHarness(width: width, height: height) { environment in
            environment.canAnimate = true
            environment.accessibilityReduceMotion = reducesMotion
        }
    }

    /// The root's corrections so far.
    var corrections: GeometryCorrections { harness.geometryCorrections }

    /// One frame of `view` at `millis` on the frame clock, under `animation`.
    @discardableResult
    func draw<V: View>(_ view: @autoclosure () -> V, atMillis millis: Int = 0, animation: Animation? = nil)
        -> [String]
    {
        harness.now = Int64(millis) * 1_000_000
        harness.transaction = Transaction(animation: animation)
        let buffer = harness.frame(view())
        return buffer.compositingOverlays(
            maxWidth: harness.context.availableWidth, maxHeight: harness.context.availableHeight,
            palette: harness.context.environment.palette
        ).lines.map(\.stripped)
    }
}

// MARK: - Scenes

/// A source `S`, 8×2 at (20, 0); three rows down a follower `f`, laid out
/// 2×2 at (0, 5); and a line below it, which says where the follower is laid
/// out (SwiftUI: where its own size puts it, `mg1` S1/S11).
private struct Followed: View {
    var properties: MatchedGeometryProperties = .frame
    var anchor: UnitPoint = .center
    var sourceAnchor: UnitPoint = .center
    var fixedFollower = false
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlyphFill("S").frame(width: 8, height: 2)
                .matchedGeometryEffect(id: 1, in: space, anchor: sourceAnchor)
                .padding(.leading, 20)
            GlyphFill(".").frame(width: 1, height: 3)
            if fixedFollower {
                GlyphFill("f").frame(width: 1, height: 1)
                    .matchedGeometryEffect(id: 1, in: space, properties: properties, anchor: anchor, isSource: false)
            } else {
                GlyphFill("f")
                    .matchedGeometryEffect(id: 1, in: space, properties: properties, anchor: anchor, isSource: false)
                    .frame(width: 2, height: 2)
            }
            Text("below")
        }
    }
}

/// Three sources in a row — `A` 4×1 at (0, 0), `B` 8×3 at (20, 0), `C` 4×1
/// at (30, 0) — and a follower `f` of the one `selected` names, laid out 1×1
/// at (0, 6).
private struct Selection: View {
    let selected: Int
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                GlyphFill("A").frame(width: 4, height: 1).matchedGeometryEffect(id: 0, in: space)
                GlyphFill(" ").frame(width: 16, height: 1)
                GlyphFill("B").frame(width: 8, height: 3).matchedGeometryEffect(id: 1, in: space)
                GlyphFill(" ").frame(width: 2, height: 1)
                GlyphFill("C").frame(width: 4, height: 1).matchedGeometryEffect(id: 2, in: space)
            }
            GlyphFill(" ").frame(width: 1, height: 3)
            GlyphFill("f").matchedGeometryEffect(id: selected, in: space, isSource: false).frame(width: 1, height: 1)
        }
    }
}

/// One view or the other, with one id: `small` 4×1 at (0, 0), or `big` 8×3
/// at (20, 6) — the hero.
private struct Hero: View {
    let expanded: Bool
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                GlyphFill("B").matchedGeometryEffect(id: "card", in: space).frame(width: 8, height: 3)
                    .padding(.leading, 20).padding(.top, 6)
            } else {
                GlyphFill("s").matchedGeometryEffect(id: "card", in: space).frame(width: 4, height: 1)
            }
        }
    }
}

/// A chip in one of two columns, moving between them: `a` 3×1 in the left
/// column at (0, 1), or `b` 3×1 in the right at (20, 2) — two views of one id.
private struct Columns: View {
    let right: Bool
    @Namespace private var space

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("L")
                if !right { GlyphFill("a").frame(width: 3, height: 1).matchedGeometryEffect(id: "chip", in: space) }
            }
            .frame(width: 20, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 0) {
                Text("R")
                Text("x")
                if right { GlyphFill("b").frame(width: 3, height: 1).matchedGeometryEffect(id: "chip", in: space) }
            }
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("Matched geometry effect")
struct MatchedGeometryEffectTests {

    @Test("The properties are the option set SwiftUI's are")
    func properties() {
        #expect(MatchedGeometryProperties.frame == [.position, .size])
        #expect(!MatchedGeometryProperties.position.contains(.size))
        #expect(MatchedGeometryProperties([.size, .position]).contains(.frame))
        #expect(MatchedGeometryProperties().isEmpty)
    }

    @Test("A follower matching the frame is drawn at its source's, and keeps its own place in the layout")
    func followerTakesTheFrame() {
        let screen = Frames().draw(Followed())
        #expect(rect(of: "f", in: screen) == CellRect(x: 20, y: 0, width: 8, height: 2))
        #expect(rect(of: "S", in: screen) == nil, "drawn after the source, over it")
        #expect(screen[7].hasPrefix("below"), "the line below stays where the follower's own size puts it")
        #expect(screen[5].trimmingCharacters(in: .whitespaces).isEmpty, "nothing drawn where it is laid out")
    }

    @Test("Matching the position, a follower's anchor lands on its source's anchor point", arguments: [
        // SwiftUI (mg2 F2, F9, F10, mg2b G6): .position keeps the follower's
        // own size; its anchor goes to the point the SOURCE's anchor names.
        (UnitPoint.center, UnitPoint.center, CellRect(x: 23, y: 0, width: 2, height: 2)),
        (.topLeading, .center, CellRect(x: 24, y: 1, width: 2, height: 2)),
        (.center, .topLeading, CellRect(x: 19, y: -1, width: 2, height: 2)),
        (.bottomTrailing, .bottomTrailing, CellRect(x: 26, y: 0, width: 2, height: 2)),
    ])
    func positionOnly(anchor: UnitPoint, sourceAnchor: UnitPoint, expected: CellRect) {
        let screen = Frames().draw(Followed(properties: .position, anchor: anchor, sourceAnchor: sourceAnchor))
        // A row above the screen is not drawn.
        let visible = CellRect(
            x: expected.x, y: max(0, expected.y), width: expected.width, height: expected.maxY - max(0, expected.y))
        #expect(rect(of: "f", in: screen) == visible)
    }

    @Test("Matching the size alone, a follower stays at its own top-leading corner, whatever its anchor",
        arguments: [UnitPoint.center, .topLeading, .bottomTrailing])
    func sizeOnly(anchor: UnitPoint) {
        // SwiftUI: mg2 F3–F5.
        let screen = Frames().draw(Followed(properties: .size, anchor: anchor))
        #expect(rect(of: "f", in: screen) == CellRect(x: 0, y: 5, width: 8, height: 2))
    }

    @Test("A frame matched from the follower's top-leading corner hangs from the source's centre")
    func frameWithAnchor() {
        // SwiftUI: mg2 F6.
        let screen = Frames().draw(Followed(anchor: .topLeading))
        #expect(rect(of: "f", in: screen) == CellRect(x: 24, y: 1, width: 8, height: 2))
    }

    @Test("A content that keeps its own size is placed as SwiftUI places it: twice its anchor's share in")
    func fixedContent() {
        // SwiftUI (mg1 S1, mg2b G1–G7): a centred 10×10 in a 40×20 frame at
        // the frame's bottom-trailing corner; here a 1×1 in an 8×2.
        #expect(rect(of: "f", in: Frames().draw(Followed(fixedFollower: true)))
            == CellRect(x: 27, y: 1, width: 1, height: 1))
        #expect(rect(of: "f", in: Frames().draw(Followed(anchor: .topLeading, fixedFollower: true)))
            == CellRect(x: 24, y: 1, width: 1, height: 1))
        // Matching the size alone, at its own corner (mg2b G4).
        #expect(rect(of: "f", in: Frames().draw(Followed(properties: .size, fixedFollower: true)))
            == CellRect(x: 0, y: 5, width: 1, height: 1))
    }

    @Test("A follower of a group with no source is drawn as it is laid out")
    func noSource() {
        let screen = Frames().draw(Selection(selected: 7))
        #expect(rect(of: "f", in: screen) == CellRect(x: 0, y: 6, width: 1, height: 1))
    }

    @Test("A follower drawn before its source is drawn at it in the first frame, and costs nothing after")
    func followerBeforeItsSource() {
        // The follower hangs from the source's bottom-trailing corner, so the
        // source, drawn after it and over it, does not cover it.
        struct Before: View {
            @Namespace private var space
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphFill("f")
                        .matchedGeometryEffect(
                            id: 1, in: space, properties: .position, anchor: .topLeading, isSource: false)
                        .frame(width: 3, height: 1)
                    GlyphFill("S").frame(width: 5, height: 2)
                        .matchedGeometryEffect(id: 1, in: space, anchor: .bottomTrailing)
                        .padding(.leading, 9)
                }
            }
        }
        let frames = Frames()
        let expected = CellRect(x: 14, y: 3, width: 3, height: 1)
        #expect(rect(of: "f", in: frames.draw(Before())) == expected)
        #expect(frames.corrections.root == 1, "found where the source is, then drawn again")
        for _ in 0..<3 {
            #expect(rect(of: "f", in: frames.draw(Before())) == expected)
        }
        #expect(frames.corrections.root == 1, "the source's place is kept from the frame before")
        #expect(frames.corrections.residual == 0)
    }

    @Test("A source its layout moves is followed in each frame it moves, and the follower adds no motion")
    func followsAMovingSource() {
        struct Moving: View {
            let inset: Int
            @Namespace private var space
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphFill("S").frame(width: 3, height: 1).matchedGeometryEffect(id: 1, in: space)
                        .padding(.leading, inset)
                    GlyphFill("f").matchedGeometryEffect(id: 1, in: space, properties: .size, isSource: false)
                        .frame(width: 1, height: 1)
                }
            }
        }
        let frames = Frames()
        frames.draw(Moving(inset: 2))
        // The padding animates, so the source glides; the follower matches its
        // size and so stays where it is laid out, and the follower matching
        // its frame below would be drawn over it.
        frames.draw(Moving(inset: 12), atMillis: 0, animation: .linear(duration: 1))
        for millis in [0, 500, 1000] {
            let screen = frames.draw(Moving(inset: 12), atMillis: millis)
            #expect(rect(of: "S", in: screen) == CellRect(x: 2 + millis / 100, y: 0, width: 3, height: 1))
            #expect(rect(of: "f", in: screen) == CellRect(x: 0, y: 1, width: 3, height: 1))
        }
        struct Over: View {
            let inset: Int
            @Namespace private var space
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    GlyphFill("S").frame(width: 3, height: 1).matchedGeometryEffect(id: 1, in: space)
                        .padding(.leading, inset)
                    GlyphFill("f").matchedGeometryEffect(id: 1, in: space, properties: .position, isSource: false)
                        .frame(width: 1, height: 1)
                }
            }
        }
        let over = Frames()
        over.draw(Over(inset: 2))
        over.draw(Over(inset: 12), atMillis: 0, animation: .linear(duration: 1))
        for millis in [0, 500, 1000] {
            // Its centre on the source's, in the frame the source is drawn.
            let screen = over.draw(Over(inset: 12), atMillis: millis)
            #expect(rect(of: "f", in: screen) == CellRect(x: 3 + millis / 100, y: 0, width: 1, height: 1))
        }
        #expect(over.corrections.residual == 0)
    }

    @Test("A follower whose source changes under an animation is carried there, laid out at each frame's size")
    func followerCarried() {
        let frames = Frames()
        frames.draw(Selection(selected: 0))
        let start = frames.draw(Selection(selected: 1), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "f", in: start) == CellRect(x: 0, y: 0, width: 4, height: 1))
        // Halfway: each edge halfway — 0 → 20, 4 → 28, 0 → 0, 1 → 3.
        let halfway = frames.draw(Selection(selected: 1), atMillis: 500)
        #expect(rect(of: "f", in: halfway) == CellRect(x: 10, y: 0, width: 6, height: 2))
        let end = frames.draw(Selection(selected: 1), atMillis: 1000)
        #expect(rect(of: "f", in: end) == CellRect(x: 20, y: 0, width: 8, height: 3))
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 1), atMillis: 1500))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
    }

    @Test("A follower carried between two sources of one size is moved, a whole cell at a time")
    func followerMoved() {
        let frames = Frames()
        frames.draw(Selection(selected: 0))
        frames.draw(Selection(selected: 2), atMillis: 0, animation: .linear(duration: 1))
        // 30 × 0.25 = 7.5 cells, rounded to the nearest (7.5 → 8 of the
        // 30 still to cover, from the far end): drawn at 7.
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 2), atMillis: 250))
            == CellRect(x: 7, y: 0, width: 4, height: 1))
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 2), atMillis: 1000))
            == CellRect(x: 30, y: 0, width: 4, height: 1))
    }

    @Test("Interrupted, a follower is carried on from where it was drawn")
    func interrupted() {
        let frames = Frames()
        frames.draw(Selection(selected: 0))
        frames.draw(Selection(selected: 2), atMillis: 0, animation: .linear(duration: 1))
        // Halfway to C (x 15), then sent back to A from there.
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 2), atMillis: 500))?.x == 15)
        frames.draw(Selection(selected: 0), atMillis: 500, animation: .linear(duration: 1))
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 0), atMillis: 1000))?.x == 8)
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 0), atMillis: 1500))?.x == 0)
    }

    @Test("Without an animation, or with motion reduced, the change is drawn at once")
    func unanimated() {
        let frames = Frames()
        frames.draw(Selection(selected: 0))
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 1), atMillis: 0))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
        let reduced = Frames(reducesMotion: true)
        reduced.draw(Selection(selected: 0))
        #expect(rect(of: "f", in: reduced.draw(Selection(selected: 1), atMillis: 0, animation: .linear(duration: 1)))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
    }

    @Test("A view inserted as another of its id is removed comes from where that one was drawn")
    func hero() {
        let frames = Frames()
        frames.draw(Hero(expanded: false))
        let start = frames.draw(Hero(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "B", in: start) == CellRect(x: 0, y: 0, width: 4, height: 1))
        // Halfway: 0 → 20, 4 → 28, 0 → 6, 1 → 9.
        #expect(rect(of: "B", in: frames.draw(Hero(expanded: true), atMillis: 500))
            == CellRect(x: 10, y: 3, width: 6, height: 2))
        #expect(rect(of: "B", in: frames.draw(Hero(expanded: true), atMillis: 1000))
            == CellRect(x: 20, y: 6, width: 8, height: 3))
        // And back.
        frames.draw(Hero(expanded: false), atMillis: 1000, animation: .linear(duration: 1))
        #expect(rect(of: "s", in: frames.draw(Hero(expanded: false), atMillis: 1500))
            == CellRect(x: 10, y: 3, width: 6, height: 2))
    }

    @Test("A chip moving between two columns is carried across, and the columns lay out as they will end")
    func chipBetweenColumns() {
        let frames = Frames()
        frames.draw(Columns(right: false))
        let start = frames.draw(Columns(right: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "b", in: start) == CellRect(x: 0, y: 1, width: 3, height: 1))
        // Halfway: x 0 → 20, y 1 → 2 (half a row from the far end, rounded
        // away from it).
        #expect(rect(of: "b", in: frames.draw(Columns(right: true), atMillis: 500))
            == CellRect(x: 10, y: 1, width: 3, height: 1))
        let end = frames.draw(Columns(right: true), atMillis: 1000)
        #expect(rect(of: "b", in: end) == CellRect(x: 20, y: 2, width: 3, height: 1))
        #expect(end[1].hasPrefix("                    x"), "the right column's rows are where they end")
    }

    @Test("A view inserted with nothing of its id leaving appears where it is laid out")
    func plainInsertion() {
        let frames = Frames()
        struct Lone: View {
            let shown: Bool
            @Namespace private var space
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text("x")
                    if shown { GlyphFill("n").frame(width: 2, height: 1).matchedGeometryEffect(id: 1, in: space) }
                }
            }
        }
        frames.draw(Lone(shown: false))
        let shown = frames.draw(Lone(shown: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "n", in: shown) == nil || rect(of: "n", in: shown) == CellRect(x: 0, y: 1, width: 2, height: 1))
        #expect(rect(of: "n", in: frames.draw(Lone(shown: true), atMillis: 1000))
            == CellRect(x: 0, y: 1, width: 2, height: 1))
    }

    @Test("Placement arithmetic rounds once, down")
    func placementArithmetic() {
        let source = MatchedSource(
            identity: ViewIdentity(path: "s"), frame: CellRect(x: 10, y: 0, width: 5, height: 3), anchor: .center)
        let own = CellRect(x: 0, y: 4, width: 2, height: 2)
        // 10 + 2.5 − 1 = 11.5 → 11; 0 + 1.5 − 1 = 0.5 → 0.
        #expect(MatchedGeometryPlacement.frame(following: source, own: own, properties: .position, anchor: .center)
            == CellRect(x: 11, y: 0, width: 2, height: 2))
        #expect(MatchedGeometryPlacement.frame(following: source, own: own, properties: .frame, anchor: .center)
            == CellRect(x: 10, y: 0, width: 5, height: 3))
        #expect(MatchedGeometryPlacement.contentOffset(
            in: CellSize(width: 5, height: 3), content: CellSize(width: 2, height: 2), anchor: .center,
            matchesPosition: true) == CellPoint(x: 3, y: 1))
    }
}
