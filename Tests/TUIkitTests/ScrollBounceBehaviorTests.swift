//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollBounceBehaviorTests.swift
//
//  `scrollBounceBehavior(_:axes:)`: when a scrollable may be pushed into its
//  overscroll allowance. `.basedOnSize` keeps content that fits still.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("scrollBounceBehavior")
struct ScrollBounceBehaviorTests {

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: 20, availableHeight: height,
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

        var scrollView: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    /// Pushes a scroll view at its end down twice and reports the excursion.
    private func pushedExcursion<V: View>(_ view: V) -> Int? {
        let frames = Frames()
        frames.render(view)
        frames.render(view)
        guard let handler = frames.scrollView else { return nil }
        handler.scrollOffset = handler.maxOffset
        _ = handler.userScrollFine(by: 1)
        _ = handler.userScrollFine(by: 1)
        frames.render(view)
        return handler.overscrollState.excursion
    }

    private func rows(_ count: Int) -> some View {
        VStack(spacing: 0) { ForEach(0..<count, id: \.self) { Text("row \($0)") } }
    }

    @Test("Content that fits may be pushed by default, and not under .basedOnSize")
    func basedOnSizeKeepsFittingContentStill() {
        let pushable = ScrollView { rows(3) }.scrollOverscroll(bottom: .rows(2))
        #expect(pushedExcursion(pushable) == 2, "TUIkit's default: a fitting view may be pushed")
        #expect(pushedExcursion(pushable.scrollBounceBehavior(.always)) == 2)
        #expect(pushedExcursion(pushable.scrollBounceBehavior(.automatic)) == 2)
        #expect(pushedExcursion(pushable.scrollBounceBehavior(.basedOnSize)) == 0)
    }

    @Test("Content that overflows may be pushed under .basedOnSize")
    func basedOnSizeAllowsOverflowingContent() {
        let pushable = ScrollView { rows(30) }.scrollOverscroll(bottom: .rows(2))
        #expect(pushedExcursion(pushable.scrollBounceBehavior(.basedOnSize)) == 2)
    }

    @Test("A horizontal behaviour leaves the vertical allowance alone")
    func axesAreIndependent() {
        let pushable = ScrollView { rows(3) }.scrollOverscroll(bottom: .rows(2))
        #expect(pushedExcursion(pushable.scrollBounceBehavior(.basedOnSize, axes: .horizontal)) == 2)
    }

    @Test("The environment records each axis, and two calls compose")
    func environmentValues() {
        var environment = EnvironmentValues()
        #expect(environment.verticalScrollBounceBehavior == .automatic)
        #expect(environment.horizontalScrollBounceBehavior == .automatic)
        environment.verticalScrollBounceBehavior = .basedOnSize
        #expect(environment.overscrollAllowances(overflowing: false).bottom == .none)

        var vertical: ScrollBounceBehavior?
        var horizontal: ScrollBounceBehavior?
        let frames = Frames()
        frames.render(
            ReadBounce { vertical = $0; horizontal = $1 }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollBounceBehavior(.always, axes: .vertical))
        #expect(vertical == .always)
        #expect(horizontal == .basedOnSize)
    }

    @Test("A List under .basedOnSize with rows that fit is not pushed")
    func listBasedOnSize() {
        func excursion(_ behavior: ScrollBounceBehavior) -> Int? {
            let frames = Frames()
            let view = List(0..<3, id: \.self) { Text("row \($0)") }
                .scrollOverscroll(bottom: .rows(2))
                .scrollBounceBehavior(behavior)
            frames.render(view, height: 8)
            frames.render(view, height: 8)
            let handler = frames.focusManager.activeSection?.focusables
                .compactMap { $0 as? ItemListHandler<Int> }.first
            _ = handler?.userScrollFine(by: 1)
            frames.render(view, height: 8)
            return handler?.overscrollState.excursion
        }
        #expect(excursion(.always) == 1)
        #expect(excursion(.basedOnSize) == 0)
    }
}

/// Reports the bounce behaviours it is drawn under.
private struct ReadBounce: View {
    let report: (ScrollBounceBehavior, ScrollBounceBehavior) -> Void
    @Environment(\.verticalScrollBounceBehavior) private var vertical
    @Environment(\.horizontalScrollBounceBehavior) private var horizontal

    var body: some View {
        report(vertical, horizontal)
        return Text("x")
    }
}
