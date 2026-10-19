//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ZoomNavigationTransitionTests.swift
//
//  The zoom navigation transition: a pushed screen revealed through a
//  rectangle growing from its matched transition source, and folded back
//  into it when popped (refusal review O4).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitNavigation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// A stack 40×12 whose root has a source `s`, 4×2 at (10, 3), among dots; the
/// screen it pushes fills itself with `D` under its two-row bar, and zooms
/// from the source.
private struct Zooming: View {
    let path: Binding<NavigationPath>
    var sourceID = 1
    var background: Color?
    var destination: String?
    /// Whether the root hugs its five rows rather than filling the stack, as
    /// a root of a few links does: its picture is then shorter than the
    /// screen pushed over it, which fills the stack.
    var hugging = false
    @Namespace private var space

    var body: some View {
        NavigationStack(path: path) {
            VStack(alignment: .leading, spacing: 0) {
                GlyphFill(".").frame(width: 40, height: 3)
                HStack(spacing: 0) {
                    GlyphFill(".").frame(width: 10, height: 2)
                    source
                    GlyphFill(".").frame(width: 26, height: 2)
                }
                if !hugging { GlyphFill(".").frame(width: 40, height: 7) }
            }
            .navigationDestination(for: Int.self) { _ in
                screen.navigationTransition(.zoom(sourceID: sourceID, in: space))
            }
        }
    }

    @ViewBuilder private var source: some View {
        if let background {
            GlyphFill("s").frame(width: 4, height: 2)
                .matchedTransitionSource(id: 1, in: space) { $0.background(background) }
        } else {
            GlyphFill("s").frame(width: 4, height: 2).matchedTransitionSource(id: 1, in: space)
        }
    }

    @ViewBuilder private var screen: some View {
        if let destination {
            Text(verbatim: destination)
        } else {
            GlyphFill("D")
        }
    }
}

/// A stack and the path it shows, drawn frame by frame.
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
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
        #expect(start.count == 12, "the pushed screen's size")
        let halfway = navigator.lines(navigator.draw(view, atMillis: 500))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        navigator.draw(view, atMillis: 1000)
        navigator.path.removeLast()
        let back = navigator.lines(navigator.draw(view, atMillis: 1000, transaction: linear))
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
        #expect(rect(of: "D", in: start) == CellRect(x: 0, y: 2, width: 40, height: 10))
        let halfway = navigator.lines(navigator.draw(view, atMillis: 2500))
        #expect(rect(of: "D", in: halfway) == CellRect(x: 5, y: 2, width: 22, height: 6))
        #expect(halfway[0].hasPrefix("....."), "the root draws round it")
        let end = navigator.lines(navigator.draw(view, atMillis: 3000))
        #expect(rect(of: "D", in: end) == nil)
        #expect(rect(of: "s", in: end) == CellRect(x: 10, y: 3, width: 4, height: 2))
    }

    @Test("A push with no animation of its own zooms under the default one")
    func defaultAnimation() {
        let navigator = Navigator()
        let view = { (path: Binding<NavigationPath>) in Zooming(path: path) }
        navigator.draw(view, atMillis: 0)
        navigator.path.append(1)
        let start = navigator.lines(navigator.draw(view, atMillis: 0))
        #expect(rect(of: "D", in: start) == CellRect(x: 10, y: 3, width: 4, height: 2))
        let later = navigator.lines(navigator.draw(view, atMillis: 2000))
        #expect(rect(of: "D", in: later) == CellRect(x: 0, y: 2, width: 40, height: 10))
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

    @Test("The zoom transition and its source configuration are SwiftUI's spellings")
    func spellings() {
        struct Spelled: View {
            @Namespace private var space
            var body: some View {
                Text("source")
                    .matchedTransitionSource(id: "card", in: space) { source in
                        source.background(.blue)
                    }
                    .navigationTransition(.zoom(sourceID: "card", in: space))
            }
        }
        let lines = renderToBuffer(Spelled(), context: makeRenderContext(width: 10, height: 1)).lines
        #expect(lines.first?.stripped == "source")
    }
}
