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
    /// Whether the follower is the source of a group of its own as well: two
    /// effects on one view.
    var stacked = false
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
            if stacked {
                GlyphFill("f").matchedGeometryEffect(id: selected, in: space, isSource: false)
                    .matchedGeometryEffect(id: "own", in: space).frame(width: 1, height: 1)
            } else {
                GlyphFill("f").matchedGeometryEffect(id: selected, in: space, isSource: false)
                    .frame(width: 1, height: 1)
            }
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
    /// A transition of the chips' own, in place of the default fade.
    var transition: AnyTransition?
    @Namespace private var space

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("L")
                if !right { chip("a") }
            }
            .frame(width: 20, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 0) {
                Text("R")
                Text("x")
                if right { chip("b") }
            }
        }
    }

    @ViewBuilder
    private func chip(_ glyph: Character) -> some View {
        let drawn = GlyphFill(glyph).frame(width: 3, height: 1).matchedGeometryEffect(id: "chip", in: space)
        if let transition { drawn.transition(transition) } else { drawn }
    }
}

/// The strengths of the fades `buffer` carries, its layers' included.
private func layerFades(_ buffer: FrameBuffer) -> [Double] {
    buffer.opacityRegions.map(\.opacity) + buffer.overlays.flatMap { layerFades($0.content) }
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
        let screen = MatchedFrames().draw(Followed())
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
        let screen = MatchedFrames().draw(Followed(properties: .position, anchor: anchor, sourceAnchor: sourceAnchor))
        // A row above the screen is not drawn.
        let visible = CellRect(
            x: expected.x, y: max(0, expected.y), width: expected.width, height: expected.maxY - max(0, expected.y))
        #expect(rect(of: "f", in: screen) == visible)
    }

    @Test("Matching the size alone, a follower stays at its own top-leading corner, whatever its anchor",
        arguments: [UnitPoint.center, .topLeading, .bottomTrailing])
    func sizeOnly(anchor: UnitPoint) {
        // SwiftUI: mg2 F3–F5.
        let screen = MatchedFrames().draw(Followed(properties: .size, anchor: anchor))
        #expect(rect(of: "f", in: screen) == CellRect(x: 0, y: 5, width: 8, height: 2))
    }

    @Test("A frame matched from the follower's top-leading corner hangs from the source's centre")
    func frameWithAnchor() {
        // SwiftUI: mg2 F6.
        let screen = MatchedFrames().draw(Followed(anchor: .topLeading))
        #expect(rect(of: "f", in: screen) == CellRect(x: 24, y: 1, width: 8, height: 2))
    }

    @Test("A content that keeps its own size is placed as SwiftUI places it: twice its anchor's share in")
    func fixedContent() {
        // SwiftUI (mg1 S1, mg2b G1–G7): a centred 10×10 in a 40×20 frame at
        // the frame's bottom-trailing corner; here a 1×1 in an 8×2.
        #expect(rect(of: "f", in: MatchedFrames().draw(Followed(fixedFollower: true)))
            == CellRect(x: 27, y: 1, width: 1, height: 1))
        #expect(rect(of: "f", in: MatchedFrames().draw(Followed(anchor: .topLeading, fixedFollower: true)))
            == CellRect(x: 24, y: 1, width: 1, height: 1))
        // Matching the size alone, at its own corner (mg2b G4).
        #expect(rect(of: "f", in: MatchedFrames().draw(Followed(properties: .size, fixedFollower: true)))
            == CellRect(x: 0, y: 5, width: 1, height: 1))
    }

    @Test("A follower of a group with no source is drawn as it is laid out")
    func noSource() {
        let screen = MatchedFrames().draw(Selection(selected: 7))
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
        let frames = MatchedFrames()
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
        let frames = MatchedFrames()
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
        let over = MatchedFrames()
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
        let frames = MatchedFrames()
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

    @Test("A follower that is the source of another group too is carried as one that is not")
    func stackedEffectsKeepTheirOwnState() {
        // Both effects draw at the view's identity. Each keeps its own state
        // and its own animation: keyed by the identity alone, the follower
        // read the other effect's state on the frames it lost a dictionary's
        // walk, started a carry from where that one drew on every frame, and
        // was not carried when its source changed; and the other, reading the
        // follower's, moved the view a second time as it was carried.
        let frames = MatchedFrames()
        frames.draw(Selection(selected: 0, stacked: true))
        frames.draw(Selection(selected: 0, stacked: true))
        let start = frames.draw(Selection(selected: 1, stacked: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "f", in: start) == CellRect(x: 0, y: 0, width: 4, height: 1))
        for millis in [250, 500, 750] {
            #expect(rect(of: "f", in: frames.draw(Selection(selected: 1, stacked: true), atMillis: millis))
                == rect(of: "f", in: Self.carried(toMillis: millis)), "at \(millis) ms")
        }
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 1, stacked: true), atMillis: 1000))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
    }

    /// The follower of an unstacked ``Selection`` carried from `A` to `B`, as
    /// drawn at `millis`.
    private static func carried(toMillis millis: Int) -> [String] {
        let frames = MatchedFrames()
        frames.draw(Selection(selected: 0))
        frames.draw(Selection(selected: 0))
        frames.draw(Selection(selected: 1), atMillis: 0, animation: .linear(duration: 1))
        return frames.draw(Selection(selected: 1), atMillis: millis)
    }

    @Test("A follower carried between two sources of one size is moved, a whole cell at a time")
    func followerMoved() {
        let frames = MatchedFrames()
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
        let frames = MatchedFrames()
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
        let frames = MatchedFrames()
        frames.draw(Selection(selected: 0))
        #expect(rect(of: "f", in: frames.draw(Selection(selected: 1), atMillis: 0))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
        let reduced = MatchedFrames(reducesMotion: true)
        reduced.draw(Selection(selected: 0))
        #expect(rect(of: "f", in: reduced.draw(Selection(selected: 1), atMillis: 0, animation: .linear(duration: 1)))
            == CellRect(x: 20, y: 0, width: 8, height: 3))
    }

    @Test("A view inserted as another of its id is removed comes from where that one was drawn")
    func hero() {
        let frames = MatchedFrames()
        frames.draw(Hero(expanded: false))
        // It fades in as it is carried, from nothing where the one leaving
        // still is (`mg3.out` A1).
        let start = frames.draw(Hero(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "B", in: start) == nil)
        #expect(rect(of: "s", in: start) == CellRect(x: 0, y: 0, width: 4, height: 1))
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

    /// SwiftUI fades the view it carries in as it moves, and the one leaving
    /// out (`mg3.out` A1, A2): the fade reaches the drawing the view makes
    /// past its slot, which is all of a carried view's (decisions B-O4-2).
    @Test("A view carried into place fades in as it moves")
    func carriedViewFades() {
        let frames = MatchedFrames()
        frames.draw(Hero(expanded: false))
        frames.draw(Hero(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        let half = frames.buffer(Hero(expanded: true), atMillis: 500)
        let layers = half.overlays.flatMap { layerFades($0.content) }
        #expect(layers.contains { abs($0 - 0.5) < 0.02 }, "the carried drawing fades in: \(layers)")
        let end = frames.buffer(Hero(expanded: true), atMillis: 1100)
        #expect(end.overlays.flatMap { layerFades($0.content) }.isEmpty, "arrived, and at rest")
    }

    /// SwiftUI carries the view leaving toward the one arriving as it fades
    /// (`mg3.out` A1, A2). Its picture keeps the size it was — a cell cannot
    /// be scaled — and is placed in the frame the one arriving is drawn at, as
    /// a content of its size is placed in a matched frame: a fifth of the way,
    /// that frame is (4, 1) 5×2, and the leaving 4×1 sits a cell in and down
    /// (decisions B-O4-1). It used to fade where it was, at (0, 0).
    @Test("A view removed as another of its id arrives is carried with it while it fades")
    func leavingViewIsCarried() {
        let frames = MatchedFrames()
        frames.draw(Hero(expanded: false))
        frames.draw(Hero(expanded: true), atMillis: 0, animation: .linear(duration: 1))
        let early = frames.draw(Hero(expanded: true), atMillis: 200)
        #expect(rect(of: "s", in: early) == CellRect(x: 5, y: 2, width: 4, height: 1), "\(early)")
        #expect(rect(of: "s", in: frames.draw(Hero(expanded: true), atMillis: 1100)) == nil, "gone once it has played")
    }

    @Test("A chip moving between two columns is carried across, and the columns lay out as they will end")
    func chipBetweenColumns() {
        let frames = MatchedFrames()
        frames.draw(Columns(right: false))
        let start = frames.draw(Columns(right: true), atMillis: 0, animation: .linear(duration: 1))
        #expect(rect(of: "b", in: start) == nil, "it fades in as it is carried")
        #expect(rect(of: "a", in: start) == CellRect(x: 0, y: 1, width: 3, height: 1))
        // Halfway: x 0 → 20, y 1 → 2 (half a row from the far end, rounded
        // away from it).
        #expect(rect(of: "b", in: frames.draw(Columns(right: true), atMillis: 500))
            == CellRect(x: 10, y: 1, width: 3, height: 1))
        let end = frames.draw(Columns(right: true), atMillis: 1000)
        #expect(rect(of: "b", in: end) == CellRect(x: 20, y: 2, width: 3, height: 1))
        #expect(end[1].hasPrefix("                    x"), "the right column's rows are where they end")
    }

    /// With no transition the chip fades as it is carried, and a tenth of the
    /// way it has a tenth of its strength; written `.identity`, it is drawn
    /// whole all the way, and what is drawn over or under shows.
    @Test("A view carried toward the views before it is drawn over the views after it while it moves")
    func carriedOverLaterViews() {
        let frames = MatchedFrames()
        frames.draw(Columns(right: true, transition: .identity))
        frames.draw(Columns(right: false, transition: .identity), atMillis: 0, animation: .linear(duration: 1))
        // A tenth of the way back from (20, 2): over the right column, which
        // comes after the left one and still draws the chip leaving it.
        let early = frames.draw(Columns(right: false, transition: .identity), atMillis: 100)
        #expect(rect(of: "a", in: early) == CellRect(x: 18, y: 2, width: 3, height: 1))
        #expect(rect(of: "a", in: frames.draw(Columns(right: false, transition: .identity), atMillis: 1000))
            == CellRect(x: 0, y: 1, width: 3, height: 1))
    }

    @Test("A view inserted with nothing of its id leaving appears where it is laid out")
    func plainInsertion() {
        let frames = MatchedFrames()
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

    @Test("A source at rest with no follower is only found: it starts no carried origin")
    func sourceAtRestIsOnlyFound() {
        let frames = MatchedFrames()
        frames.draw(Hero(expanded: false))
        frames.draw(Hero(expanded: false))
        #expect(!frames.harness.tui.mouseEventDispatcher.geometry.keepsReaders)
        frames.draw(Followed())
        frames.draw(Followed())
        #expect(frames.harness.tui.mouseEventDispatcher.geometry.keepsReaders, "a follower reads where it is")
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
