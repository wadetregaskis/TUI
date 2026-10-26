//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollBounceBehaviorTests.swift
//
//  `scrollBounceBehavior(_:axes:)`: when a scrollable may be pushed into its
//  overscroll allowance. `.basedOnSize` keeps content that fits still.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("scrollBounceBehavior")
struct ScrollBounceBehaviorTests {

    @MainActor
    private struct Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()

        @discardableResult
        func render<V: View>(_ view: V, height: Int = 6, atNanos nanos: Int64 = 0) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            environment.frameNowNanos = nanos
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

        var rowList: ItemListHandler<Int>? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ItemListHandler<Int> }.first
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
        #expect(pushedExcursion(pushable) == 2, "TUI's default: a fitting view may be pushed")
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

// MARK: - The bounce under `.always` (decisions B31)

extension ScrollBounceBehaviorTests {
    /// The scrollables a bounce reaches.
    enum Bouncer: String, CaseIterable, Sendable {
        case scrollView, list, table

        @MainActor
        func view(_ behavior: ScrollBounceBehavior?, bottom: ScrollOverscroll = .none) -> AnyView {
            let scrollable: AnyView =
                switch self {
                case .scrollView:
                    AnyView(ScrollView { VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("row \($0)") } } })
                case .list:
                    AnyView(List(0..<30, id: \.self) { Text("row \($0)") })
                case .table:
                    AnyView(
                        Table((0..<30).map { BounceRow(id: $0) }) { TableColumn("Name", value: \.name) })
                }
            let allowed = scrollable.scrollOverscroll(bottom: bottom)
            return behavior.map { AnyView(allowed.scrollBounceBehavior($0)) } ?? AnyView(allowed)
        }
    }

    private static let start: Int64 = 1_000_000_000
    private static let millisecond: Int64 = 1_000_000

    /// Renders `view` twice, scrolls it to its end, and pushes past it
    /// `pushes` times; returns the frames and the scrollable.
    private func pushedAtTheEnd(
        _ bouncer: Bouncer, _ view: AnyView, pushes: Int, height: Int = 12
    ) -> (Frames, any ScrollableOffsetState)? {
        let frames = Frames()
        frames.render(view, height: height, atNanos: Self.start)
        frames.render(view, height: height, atNanos: Self.start)
        let scrollable: (any ScrollableOffsetState)? =
            bouncer == .scrollView ? frames.scrollView : frames.rowList
        guard let scrollable else { return nil }
        scrollable.scrollOffset = scrollable.maxOffset
        frames.render(view, height: height, atNanos: Self.start)
        for _ in 0..<pushes { _ = scrollable.userScrollFine(by: 1) }
        frames.render(view, height: height, atNanos: Self.start)
        return (frames, scrollable)
    }

    @Test(
        "Under .always a push past the end is held while the steps come, and springs back once they stop",
        arguments: Bouncer.allCases)
    func alwaysSpringsBack(_ bouncer: Bouncer) {
        let view = bouncer.view(.always)
        guard let pushed = pushedAtTheEnd(bouncer, view, pushes: 3) else {
            Issue.record("precondition: a scrollable")
            return
        }
        let (frames, scrollable) = pushed
        #expect(scrollable.overscrollState.excursion == 2, "pushed as far as the bounce allows: two lines")
        func excursion(at milliseconds: Int64) -> Int {
            frames.render(view, height: 12, atNanos: Self.start + milliseconds * Self.millisecond)
            return scrollable.overscrollState.excursion
        }
        #expect(excursion(at: 200) == 2, "not quiet a quarter of a second yet")
        _ = scrollable.userScrollFine(by: 1)
        #expect(excursion(at: 400) == 2, "held: another step against the edge")
        #expect(excursion(at: 600) == 2, "quiet for 200 ms only")
        #expect(excursion(at: 650) == 1, "quiet: the first line back")
        #expect(excursion(at: 700) == 0, "and the second, a frame later")
        #expect(excursion(at: 2_000) == 0)
    }

    @Test("The bounce is one line in a view under eight lines tall")
    func smallViewsBounceALine() {
        let pushed = pushedAtTheEnd(.scrollView, Bouncer.scrollView.view(.always), pushes: 3, height: 6)
        #expect(pushed?.1.overscrollState.excursion == 1)
    }

    @Test(
        "Without .always nothing bounces: no push at all, as before",
        arguments: Bouncer.allCases, [ScrollBounceBehavior?.none, .automatic, .basedOnSize])
    func otherBehavioursDoNotBounce(_ bouncer: Bouncer, behavior: ScrollBounceBehavior?) {
        let pushed = pushedAtTheEnd(bouncer, bouncer.view(behavior), pushes: 3)
        #expect(pushed?.1.overscrollState.excursion == 0)
    }

    /// A framework scroller — a tall menu's column, a dialog body's, a framed
    /// container's — takes none of the page's settings for its scroll views
    /// (`ScrollView.asChrome()`). A page's `.always` pushed it two lines past
    /// its end, and a page's allowance as far as that said (lane SCROLLB's
    /// review).
    @Test(
        "A framework scroller is pushed past its end by neither a page's .always nor a page's allowance",
        arguments: [(ScrollBounceBehavior.always, ScrollOverscroll.none), (.automatic, .rows(3))])
    func chromeScrollerIsNotPushed(behavior: ScrollBounceBehavior, bottom: ScrollOverscroll) {
        let chrome = ScrollView {
            VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("row \($0)") } }
        }
        .asChrome()
        let view = AnyView(chrome.scrollOverscroll(bottom: bottom).scrollBounceBehavior(behavior))
        guard let scrollable = pushedAtTheEnd(.scrollView, view, pushes: 3)?.1 else {
            Issue.record("precondition: a scroll view")
            return
        }
        #expect(scrollable.maxOffset > 0, "precondition: it scrolls")
        #expect(scrollable.scrollOffset == scrollable.maxOffset, "precondition: at its end")
        #expect(scrollable.overscrollState.excursion == 0)
    }

    @Test(
        "An allowance the app asked for stays where it was pushed, under .always and .automatic alike",
        arguments: Bouncer.allCases, [ScrollBounceBehavior.always, .automatic])
    func explicitAllowanceStays(_ bouncer: Bouncer, behavior: ScrollBounceBehavior) {
        let view = bouncer.view(behavior, bottom: .rows(3))
        guard let pushed = pushedAtTheEnd(bouncer, view, pushes: 3) else {
            Issue.record("precondition: a scrollable")
            return
        }
        let (frames, scrollable) = pushed
        #expect(scrollable.overscrollState.excursion == 3)
        frames.render(view, height: 12, atNanos: Self.start + 5_000 * Self.millisecond)
        #expect(scrollable.overscrollState.excursion == 3, "a deliberate push stays")
    }
}

/// A table row for the bounce cases.
private struct BounceRow: Identifiable {
    let id: Int
    var name: String { "row \(id)" }
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
