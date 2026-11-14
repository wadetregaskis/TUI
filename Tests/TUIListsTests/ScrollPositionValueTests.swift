//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPositionValueTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUILists
@testable import TUITestSupport
@testable import TUIView

/// A bound `ScrollPosition` is a VALUE, and a different value is a request,
/// as SwiftUI's is: `.scrollPosition(.constant(ScrollPosition(y: line)))`
/// with `line` changing scrolls to each line, and an equal value handed over
/// again does not undo the user's scroll (measured,
/// `Tools/SwiftUIProbes/Scroll position bound to a changing value/changing.swift`).
///
/// Every `ScrollPosition(y:)` carries the same request token, so a scroll
/// view that told one request from another by the token alone acted on the
/// first and ignored every later one: a page bound this way never moved
/// after its first frame.
@MainActor
@Suite("ScrollPosition compared by value")
struct ScrollPositionValueTests {
    private static let viewport = 6
    private static let rowCount = 40

    /// One frame, with the render-pass hooks the real loop drives.
    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: Self.viewport,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The first row label each line draws, in order.
    private func rows(_ lines: [String]) -> [String] {
        lines.compactMap { line in line.range(of: #"row \d+"#, options: .regularExpression).map { String(line[$0]) } }
    }

    private func scrollView(_ position: Binding<ScrollPosition>) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
            }
        }
        .scrollPosition(position)
    }

    private func list(_ position: Binding<ScrollPosition>) -> some View {
        List(0..<Self.rowCount, id: \.self) { Text("row \($0)") }
            .scrollPosition(position)
    }

    @Test("A position built afresh each frame scrolls a scroll view to each new offset")
    func freshValueScrollsScrollView() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        for line in [0, 10, 20, 10] {
            let frame = renderFrame(
                scrollView(.constant(ScrollPosition(y: line))), tuiContext: tuiContext, focusManager: focusManager)
            #expect(rows(frame).first == "row \(line)", "line \(line): \(frame)")
        }
    }

    @Test("A position built afresh each frame scrolls a List to each new offset")
    func freshValueScrollsList() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        for line in [0, 10, 20, 10] {
            let frame = renderFrame(
                list(.constant(ScrollPosition(y: line))), tuiContext: tuiContext, focusManager: focusManager)
            #expect(rows(frame).first == "row \(line)", "line \(line): \(frame)")
        }
    }

    @Test("An equal position built afresh does not undo the user's scroll")
    func equalValueKeepsUserScroll() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        // A first frame measures the content an offset is clamped against.
        renderFrame(scrollView(.constant(ScrollPosition(y: 0))), tuiContext: tuiContext, focusManager: focusManager)
        let landed = renderFrame(
            scrollView(.constant(ScrollPosition(y: 10))), tuiContext: tuiContext, focusManager: focusManager)
        #expect(rows(landed).first == "row 10", "\(landed)")

        let handler = focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil, "the ScrollView registered its handler")
        handler?.userScrollFine(by: 3)
        let again = renderFrame(
            scrollView(.constant(ScrollPosition(y: 10))), tuiContext: tuiContext, focusManager: focusManager)
        #expect(rows(again).first == "row 13", "\(again)")
    }

    @Test("The same position assigned again after the user scrolled scrolls back")
    func reassignedAfterUserScroll() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        var position = ScrollPosition(y: 0)
        let binding = Binding(get: { position }, set: { position = $0 })
        renderFrame(scrollView(binding), tuiContext: tuiContext, focusManager: focusManager)
        position = ScrollPosition(y: 10)
        let landed = renderFrame(scrollView(binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(rows(landed).first == "row 10", "\(landed)")

        let handler = focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        handler?.userScrollFine(by: 3)
        let scrolled = renderFrame(scrollView(binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(rows(scrolled).first == "row 13", "\(scrolled)")
        #expect(position.isPositionedByUser)
        // The write-back changed the app's state, which draws a frame: the
        // binding is read holding no request.
        renderFrame(scrollView(binding), tuiContext: tuiContext, focusManager: focusManager)

        // SwiftUI scrolls here: the binding now holds the user's position, and
        // the app's new value differs from it.
        position = ScrollPosition(y: 10)
        let back = renderFrame(scrollView(binding), tuiContext: tuiContext, focusManager: focusManager)
        #expect(rows(back).first == "row 10", "\(back)")
    }

    /// A first value places the view on its first frame, as SwiftUI's does
    /// (measured, `Tools/SwiftUIProbes/Scroll position bound to a changing
    /// value/starting.swift`): an offset, an offset asked for by `scrollTo`,
    /// an edge, and an offset past the end, which lands on the last offset.
    /// Rendered with no layout pass before it, as the opening frame of a view
    /// drawn directly is: the offset was clamped against an extent of 0, and
    /// the view opened at the top. (SwiftUI's macOS `List` follows no bound
    /// position at all, measured in the same probe; TUI's follows one as its
    /// scroll view does.)
    @Test(
        "A starting position places the view on its first frame",
        arguments: ["y: 10", "scrollTo(y: 10)", "edge: .bottom", "y: 500"])
    func startingPosition(name: String) {
        // At the end, the last row is on screen; a `List` gives a line to its
        // "more above" indicator, so its first row there is not a scroll view's.
        let atEnd = name.hasPrefix("edge") || name == "y: 500"
        func placed(_ shown: [String]) -> Bool {
            atEnd ? shown.last == "row 39" && !shown.contains("row 0") : shown.first == "row 10"
        }
        for kind in ["ScrollView", "List"] {
            let tuiContext = TUIContext()
            let focusManager = FocusManager()
            var position = Self.position(named: name)
            let binding = Binding(get: { position }, set: { position = $0 })
            let view = kind == "List" ? AnyView(list(binding)) : AnyView(scrollView(binding))
            let frame = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(placed(rows(frame)), "\(kind) \(name): \(frame)")
            // And it stays there: the request is spent, not read again.
            let next = renderFrame(view, tuiContext: tuiContext, focusManager: focusManager)
            #expect(placed(rows(next)), "\(kind) \(name), second frame: \(next)")
        }
    }

    @Test("A starting constant position places the view on its first frame")
    func startingConstant() {
        let frame = renderFrame(
            scrollView(.constant(ScrollPosition(y: 10))), tuiContext: TUIContext(), focusManager: FocusManager())
        #expect(rows(frame).first == "row 10", "\(frame)")
    }

    @Test("A starting x places a sideways scroll view on its first frame")
    func startingColumn() {
        let line = (0..<60).map { String($0 % 10) }.joined()
        let view = ScrollView(.horizontal) { Text(line) }
            .scrollIndicators(.hidden)
            .scrollPosition(.constant(ScrollPosition(x: 13)))
        let frame = renderFrame(view, tuiContext: TUIContext(), focusManager: FocusManager())
        #expect(frame.first?.hasPrefix("3456789012") == true, "\(frame)")
    }

    /// The starting position `name` spells: `ScrollPosition` is not
    /// `Sendable`, so ``startingPosition(name:)``'s arguments name it.
    private static func position(named name: String) -> ScrollPosition {
        switch name {
        case "scrollTo(y: 10)":
            var position = ScrollPosition()
            position.scrollTo(y: 10)
            return position
        case "edge: .bottom": return ScrollPosition(edge: .bottom)
        case "y: 500": return ScrollPosition(y: 500)
        default: return ScrollPosition(y: 10)
        }
    }
}
