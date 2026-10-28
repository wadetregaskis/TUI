//  🖥️ TUI — A Terminal UI framework for Swift
//  ZoomNavigationTransitionTests.swift
//
//  The zoom navigation transition: a pushed screen revealed through a
//  rectangle growing from its matched transition source, and folded back
//  into it when popped (refusal review O4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUINavigation
@testable import TUITestSupport
@testable import TUIView

/// A stack 40×12 whose root has a source `s`, 4×2 at (`inset`, 3) — (10, 3)
/// unless said — among dots; the screen it pushes fills itself with `D` under
/// its two-row bar, and zooms from the source.
private struct Zooming: View {
    let path: Binding<NavigationPath>
    var sourceID = 1
    var inset = 10
    var background: Color?
    /// The source's clip shape, if it has one.
    var clip: RoundedRectangle?
    /// Whether the source casts a hard half-black shadow a cell right and down.
    var shadowed = false
    var destination: String?
    /// Whether a view inside the screen declares the automatic transition, under
    /// the zoom the screen declares.
    var innerAutomatic = false
    /// Whether the root hugs its five rows rather than filling the stack, as
    /// a root of a few links does: its picture is then shorter than the
    /// screen pushed over it, which fills the stack.
    var hugging = false
    /// Where set, the screen pushed declares no zoom and holds a stack of its
    /// own, showing this path, beside a source `k` 4×2 that stack's screen
    /// zooms from.
    var inner: Binding<NavigationPath>?
    @Namespace private var space

    var body: some View {
        NavigationStack(path: path) {
            VStack(alignment: .leading, spacing: 0) {
                GlyphFill(".").frame(width: 40, height: 3)
                HStack(spacing: 0) {
                    GlyphFill(".").frame(width: inset, height: 2)
                    source
                    GlyphFill(".").frame(width: 36 - inset, height: 2)
                }
                if !hugging { GlyphFill(".").frame(width: 40, height: 7) }
            }
            .navigationDestination(for: Int.self) { _ in
                if let inner {
                    nested(inner)
                } else {
                    screen.navigationTransition(.zoom(sourceID: sourceID, in: space))
                }
            }
        }
    }

    private func nested(_ inner: Binding<NavigationPath>) -> some View {
        HStack(alignment: .top, spacing: 0) {
            GlyphFill("k").frame(width: 4, height: 2).matchedTransitionSource(id: 2, in: space)
            NavigationStack(path: inner) {
                GlyphFill("r")
                    .navigationDestination(for: Int.self) { _ in
                        GlyphFill("D").navigationTransition(.zoom(sourceID: 2, in: space))
                    }
            }
        }
    }

    @ViewBuilder private var source: some View {
        if let background {
            GlyphFill("s").frame(width: 4, height: 2)
                .matchedTransitionSource(id: 1, in: space) { $0.background(background) }
        } else if let clip {
            GlyphFill("s").frame(width: 4, height: 2)
                .matchedTransitionSource(id: 1, in: space) { $0.clipShape(clip) }
        } else if shadowed {
            GlyphFill("s").frame(width: 4, height: 2)
                .matchedTransitionSource(id: 1, in: space) { $0.shadow(color: .black.opacity(0.5), radius: 0, x: 1, y: 1) }
        } else {
            GlyphFill("s").frame(width: 4, height: 2).matchedTransitionSource(id: 1, in: space)
        }
    }

    @ViewBuilder private var screen: some View {
        if let destination {
            Text(verbatim: destination)
        } else if innerAutomatic {
            VStack(spacing: 0) { GlyphFill("D").navigationTransition(.automatic) }
        } else {
            GlyphFill("D")
        }
    }
}

/// A source `s` 4×2 above a stack 40×10, whose screen zooms from it — so the
/// zoom's rectangle starts outside the stack — and says where its `D` is. The
/// root reads where it is, so the stack is told where it is in the walk that
/// draws the zoom, and no walk draws the screen whole.
private struct ZoomingFromOutside: View {
    let path: Binding<NavigationPath>
    let seen: MainActorBox<[CellRect]>
    @Namespace private var space

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlyphFill("s").frame(width: 4, height: 2).matchedTransitionSource(id: 1, in: space)
            NavigationStack(path: path) {
                GeometryReader { proxy in Text(verbatim: "root at \(proxy.frame(in: .global).minY)") }
                    .navigationDestination(for: Int.self) { _ in
                        GlyphFill("D")
                            .onGeometryChange(for: CellRect.self) { $0.frame(in: .global) } action: {
                                seen.value.append($0)
                            }
                            .navigationTransition(.zoom(sourceID: 1, in: space))
                    }
            }
        }
    }
}

/// A stack and the path it shows, drawn frame by frame.
///
/// A zoom's clock starts on the frame after its first — the first drawn once
/// that one is presented — so a test draws that frame at the first's instant
/// for the zoom to run from it.
@MainActor
private final class Navigator {
    var path = NavigationPath()
    let harness: InputChainHarness

    init(reducesMotion: Bool = false) {
        harness = InputChainHarness(width: 40, height: 12) { environment in
            environment.canAnimate = true
            environment.accessibilityReduceMotion = reducesMotion
        }
    }

    var binding: Binding<NavigationPath> {
        Binding(get: { self.path }, set: { self.path = $0 })
    }

    /// One frame at `millis`, under `transaction`, as the screen shows it.
    @discardableResult
    func draw(
        _ view: (Binding<NavigationPath>) -> Zooming, atMillis millis: Int,
        transaction: Transaction = Transaction()
    ) -> FrameBuffer {
        harness.now = Int64(millis) * 1_000_000
        harness.transaction = transaction
        return harness.frame(view(binding))
    }

    func lines(_ buffer: FrameBuffer) -> [String] { buffer.lines.map(\.stripped) }
}

@MainActor
@Suite("Zoom navigation transition")
struct ZoomNavigationTransitionTests {
    private let linear = Transaction(animation: .linear(duration: 1))

    @Test("A pushed screen is revealed from its source's frame to the whole stack")
    func revealedFromTheSource() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        let start = navigator.lines(navigator.draw(view, atMillis: 0, transaction: linear))
        navigator.draw(view, atMillis: 0)
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
        #expect(rect(of: "s", in: start) == nil, "the screen covers the source")
        #expect(start[0].hasPrefix("....."), "the root is still drawn round it")
        // Halfway: each edge halfway — 10 → 0, 3 → 0, 14 → 40, 5 → 12.
        let halfway = navigator.lines(navigator.draw(view, atMillis: 500))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        let end = navigator.lines(navigator.draw(view, atMillis: 1000))
        #expect(rect(of: "D", in: end) == CellRect(x: 0, y: 2, width: 40, height: 10))
        #expect(!end.joined().contains("."), "the root is gone")
    }

    @Test("A root that hugs its rows is zoomed over, and folded back into, as one that fills the stack is")
    func huggingRoot() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path, hugging: true) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        let start = navigator.lines(navigator.draw(view, atMillis: 0, transaction: linear))
        navigator.draw(view, atMillis: 0)
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
        #expect(start.count == 12, "the pushed screen's size")
        let halfway = navigator.lines(navigator.draw(view, atMillis: 500))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        navigator.draw(view, atMillis: 1000)
        navigator.path.removeLast()
        let back = navigator.lines(navigator.draw(view, atMillis: 1000, transaction: linear))
        navigator.draw(view, atMillis: 1000)
        #expect(back.count == 12, "the screen leaving is drawn whole while it folds")
        #expect(rect(of: "D", in: back) == CellRect(x: 0, y: 2, width: 40, height: 10))
        let folded = navigator.lines(navigator.draw(view, atMillis: 2000))
        #expect(folded.count == 5, "and the stack is the root's size once it has")
        #expect(rect(of: "D", in: folded) == nil)
        #expect(rect(of: "s", in: folded) == CellRect(x: 10, y: 3, width: 4, height: 2))
    }

    @Test("A popped screen folds back into its source over the screen it returns to")
    func concealedIntoTheSource() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        navigator.draw(view, atMillis: 0, transaction: Transaction(animation: nil))
        navigator.draw(view, atMillis: 2000)
        navigator.path.removeLast()
        let start = navigator.lines(navigator.draw(view, atMillis: 2000, transaction: linear))
        navigator.draw(view, atMillis: 2000)
        #expect(rect(of: "D", in: start) == CellRect(x: 0, y: 2, width: 40, height: 10))
        let halfway = navigator.lines(navigator.draw(view, atMillis: 2500))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        #expect(halfway[0].hasPrefix("....."), "the root draws round it")
        let end = navigator.lines(navigator.draw(view, atMillis: 3000))
        #expect(rect(of: "D", in: end) == nil)
        #expect(rect(of: "s", in: end) == CellRect(x: 10, y: 3, width: 4, height: 2))
    }

    @Test("A popped screen folds back into its source where it is now, though the root moved it while covered")
    func concealedIntoTheMovedSource() {
        let moved = { (path: Binding<NavigationPath>) in Zooming(path: path, inset: 20) }
        /// Halfway back into the source at (20, 3), from a screen pushed from
        /// `first`'s source.
        func halfway(pushedFrom first: @escaping (Binding<NavigationPath>) -> Zooming) -> [String] {
            let navigator = Navigator()
            navigator.draw(first, atMillis: 0)
            navigator.path.append(1)
            navigator.draw(first, atMillis: 0, transaction: Transaction(animation: nil))
            navigator.draw(moved, atMillis: 2000)
            navigator.draw(moved, atMillis: 2000)
            navigator.path.removeLast()
            navigator.draw(moved, atMillis: 2000, transaction: linear)
            navigator.draw(moved, atMillis: 2000)
            return navigator.lines(navigator.draw(moved, atMillis: 2500))
        }
        // Each edge halfway: 20 → 0, 3 → 0, 24 → 40, 5 → 12.
        let expected = halfway(pushedFrom: moved)
        #expect(rect(of: "D", in: expected) == CellRect(x: 10, y: 2, width: 22, height: 6))
        // The root drew the source at (20, 3) off-screen while the screen
        // covered it, where nothing found it; it is found once the root is
        // back, and the screen folds into it there, not where it was pushed
        // from.
        #expect(halfway(pushedFrom: { Zooming(path: $0) }) == expected)
    }

    @Test("A zoom on the screen is the screen's transition, whatever a view inside it declares")
    func outermostDeclarationWins() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path, innerAutomatic: true) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        let start = navigator.lines(navigator.draw(view, atMillis: 0, transaction: linear))
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
    }

    @Test("A screen holding a stack of its own takes no zoom from that stack's screens")
    func nestedStackKeepsItsZoom() {
        var inner = NavigationPath()
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in
            Zooming(path: path, inner: Binding(get: { inner }, set: { inner = $0 }))
        }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        navigator.draw(view, atMillis: 0)
        inner.append(1)
        navigator.draw(view, atMillis: 0)
        navigator.draw(view, atMillis: 0)
        let pushed = navigator.lines(navigator.draw(view, atMillis: 2000))
        #expect(rect(of: "D", in: pushed) != nil, "the inner stack shows its screen")
        // The outer screen declared no zoom, so it goes at once when popped:
        // it does not fold into the source the inner stack's screen zooms from.
        navigator.path.removeLast()
        navigator.draw(view, atMillis: 2000, transaction: linear)
        let halfway = navigator.lines(navigator.draw(view, atMillis: 2500))
        #expect(rect(of: "k", in: halfway) == nil)
        #expect(rect(of: "D", in: halfway) == nil)
        #expect(rect(of: "s", in: halfway) == CellRect(x: 10, y: 3, width: 4, height: 2))
    }

    @Test("A screen revealed through a rectangle with nothing of it inside the stack is still found where it is")
    func revealedFromOutsideTheStack() {
        let harness = InputChainHarness(width: 40, height: 12) { $0.canAnimate = true }
        var path = NavigationPath()
        let seen = MainActorBox<[CellRect]>([])
        let view = { ZoomingFromOutside(path: Binding(get: { path }, set: { path = $0 }), seen: seen) }
        harness.frame(view())
        harness.frame(view())
        path.append(1)
        harness.transaction = linear
        let start = harness.frame(view()).lines.map(\.stripped)
        // The rectangle is the source's, above the stack: none of the screen
        // is drawn, but where it is laid out is known — under the stack's
        // bar, two rows below the source — as it is for a clipped view.
        #expect(rect(of: "D", in: start) == nil)
        #expect(seen.value == [CellRect(x: 0, y: 4, width: 40, height: 8)])
    }

    @Test("A push with no animation of its own zooms under the default one")
    func defaultAnimation() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        let start = navigator.lines(navigator.draw(view, atMillis: 0))
        navigator.draw(view, atMillis: 0)
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
        let later = navigator.lines(navigator.draw(view, atMillis: 2000))
        #expect(rect(of: "D", in: later) == CellRect(x: 0, y: 2, width: 40, height: 10))
    }

    @Test("A zoom plays from its start, though its first frame is slow to reach the screen")
    func slowFirstFrame() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        navigator.draw(view, atMillis: 0, transaction: linear)
        // The first frame took 1.3 s to write — it sent the screen's photo —
        // so the next is drawn 1.3 s on: where the zoom is first seen, and
        // starts.
        let seen = navigator.lines(navigator.draw(view, atMillis: 1300))
        #expect(rect(of: "D", in: seen) == CellRect(x: 10, y: 3, width: 4, height: 2))
        let halfway = navigator.lines(navigator.draw(view, atMillis: 1800))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        navigator.draw(view, atMillis: 2300)
        // Popped, likewise: the screen is still whole on the frame after a
        // slow first, and folds from there.
        navigator.path.removeLast()
        navigator.draw(view, atMillis: 2300, transaction: linear)
        let folding = navigator.lines(navigator.draw(view, atMillis: 3600))
        #expect(rect(of: "D", in: folding) == CellRect(x: 0, y: 2, width: 40, height: 10))
        let halfwayBack = navigator.lines(navigator.draw(view, atMillis: 4100))
        #expect(rect(of: "D", in: halfwayBack) == CellRect(x: 5, y: 2, width: 22, height: 6))
    }

    @Test("Animations disabled, motion reduced, or no source on screen: the stack changes at once")
    func noZoom() {
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        var disabled = Transaction(animation: .linear(duration: 1))
        disabled.disablesAnimations = true
        for (navigator, transaction, build) in [
            (Navigator(), disabled, view),
            (Navigator(reducesMotion: true), linear, view),
            (Navigator(), linear, { (path: Binding<NavigationPath>) in Zooming(path: path, sourceID: 9) }),
        ] {
            navigator.draw(build, atMillis: 0)
            navigator.path.append(1)
            let start = navigator.lines(navigator.draw(build, atMillis: 0, transaction: transaction))
            #expect(rect(of: "D", in: start) == CellRect(x: 0, y: 2, width: 40, height: 10))
        }
    }

    @Test("The source's background fills the rectangle behind the screen")
    func background() {
        ColorDepth.withCurrent(.truecolor) {
            let navigator = Navigator()
            let view = { (path: Binding<NavigationPath>) in
                Zooming(path: path, background: .red, destination: "x")
            }
            navigator.draw(view, atMillis: 0)
            navigator.path.append(1)
            navigator.draw(view, atMillis: 0, transaction: linear)
            navigator.draw(view, atMillis: 0)
            // Halfway the rectangle is (5, 2) 22×6; the screen draws its `x`
            // at (0, 2), outside it, and nothing inside.
            let halfway = navigator.draw(view, atMillis: 500)
            let red = paintedCells(
                renderToBuffer(Color.red.frame(width: 1, height: 1), context: navigator.harness.context).lines[0]
            )[0].background
            #expect(paintedCells(halfway.lines[4])[10].background == red)
            #expect(paintedCells(halfway.lines[4])[2].background != red, "only inside the rectangle")
        }
    }

    @Test("The source's clip shape cuts the rectangle's corners, its radius shrinking as the rectangle grows")
    func clipShape() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in
            Zooming(path: path, clip: RoundedRectangle(cornerRadius: 6, style: .circular))
        }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        navigator.draw(view, atMillis: 0, transaction: linear)
        navigator.draw(view, atMillis: 0)
        // Halfway the rectangle is (5, 2) 22×6, and the radius 3: each corner
        // cell is under half covered, and cut, showing the root behind it; the
        // cells beside it are kept.
        let halfway = navigator.lines(navigator.draw(view, atMillis: 500))
        func cell(_ column: Int, _ row: Int) -> Character { Array(halfway[row])[column] }
        #expect([cell(5, 2), cell(26, 2), cell(5, 7), cell(26, 7)] == [".", ".", ".", "."])
        #expect([cell(6, 2), cell(5, 3), cell(25, 7), cell(26, 6)] == ["D", "D", "D", "D"])
        // Grown to the stack, it has no radius left.
        let end = navigator.lines(navigator.draw(view, atMillis: 1000))
        #expect(rect(of: "D", in: end) == CellRect(x: 0, y: 2, width: 40, height: 10))
        #expect(!end.joined().contains("."))
    }

    @Test("The source's shadow falls on the screen the rectangle grows over, and fades as it grows")
    func shadow() {
        ColorDepth.withCurrent(.truecolor) {
            let navigator = Navigator()
            let view = { (path: Binding<NavigationPath>) in Zooming(path: path, shadowed: true) }
            navigator.draw(view, atMillis: 0)
            navigator.path.append(1)
            let start = navigator.draw(view, atMillis: 0, transaction: linear)
            navigator.draw(view, atMillis: 0)
            // At the start the rectangle is the source's, (10, 3) 4×2: its shadow
            // a cell right and down, at the colour's half.
            #expect(paintedCells(start.lines[5])[11].background.isEmpty == false, "under the rectangle's bottom edge")
            #expect(paintedCells(start.lines[4])[14].background.isEmpty == false, "beside its trailing edge")
            #expect(paintedCells(start.lines[5])[10].background.isEmpty, "offset a cell right")
            #expect(paintedCells(start.lines[2])[11].background.isEmpty, "nothing above it")
            let halfway = navigator.draw(view, atMillis: 500)
            #expect(paintedCells(halfway.lines[8])[10].background.isEmpty == false, "under the grown rectangle")
            let end = navigator.draw(view, atMillis: 1000)
            #expect(end.lines.allSatisfy { line in paintedCells(line).allSatisfy(\.background.isEmpty) })
        }
    }

    @Test("The zoom transition and its source configuration are SwiftUI's spellings")
    func spellings() {
        struct Spelled: View {
            @Namespace private var space
            var body: some View {
                Text("source")
                    .matchedTransitionSource(id: "card", in: space) { source in
                        source
                            .background(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 4, y: 2)
                    }
                    .navigationTransition(.zoom(sourceID: "card", in: space))
            }
        }
        let lines = renderToBuffer(Spelled(), context: makeRenderContext(width: 10, height: 1)).lines
        #expect(lines.first?.stripped == "source")
    }
}
