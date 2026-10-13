//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnScrollPhaseChangeTests.swift
//
//  `onScrollPhaseChange`: idle and interacting, from the user's discrete
//  scrolling, timed on a clock the tests step.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite("onScrollPhaseChange")
struct OnScrollPhaseChangeTests {

    @MainActor
    private final class Frames {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        /// The handler's clock, stepped by hand.
        var now: UInt64 = 1_000_000_000

        @discardableResult
        func render<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> [String] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.verticalScrollIndicatorVisibility = .hidden
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            handler?.phaseNow = { [weak self] in self?.now ?? 0 }
            return buffer.lines.map(\.stripped)
        }

        var handler: ScrollViewHandler? {
            focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
        }
    }

    @MainActor
    private final class Log {
        var changes: [(old: ScrollPhase, new: ScrollPhase)] = []
        var contexts: [ScrollPhaseChangeContext] = []
    }

    private func scrolling(_ log: Log) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("row \($0)") }
            }
        }
        .onScrollPhaseChange { old, new, context in
            log.changes.append((old, new))
            log.contexts.append(context)
        }
    }

    @Test("The first frame reports idle to idle, as SwiftUI does")
    func firstFrameReportsIdle() {
        let frames = Frames()
        let log = Log()
        frames.render(scrolling(log))
        #expect(log.changes.count == 1)
        #expect(log.changes.first.map { $0.old == .idle && $0.new == .idle } == true)
        #expect(log.contexts.first?.velocity == .zero, "as SwiftUI's appear call reports it (B27)")
        frames.render(scrolling(log))
        #expect(log.changes.count == 1, "nothing changed")
    }

    @Test("A user scroll is interacting until it has been quiet a quarter of a second")
    func userScrollInteractsThenIdles() {
        let frames = Frames()
        let log = Log()
        frames.render(scrolling(log))
        frames.handler?.userScrollFine(by: 3)
        frames.render(scrolling(log))
        #expect(log.changes.last.map { $0.old == .idle && $0.new == .interacting } == true)
        #expect(log.contexts.last?.geometry.contentOffset.y == 3)
        #expect(log.contexts.last?.velocity == .zero, "(0, 0) at the change to interacting, never nil (B27)")

        // Not quiet long enough yet.
        frames.now += ScrollPhase.quietNanos / 2
        frames.render(scrolling(log))
        #expect(log.changes.count == 2)

        // Another tick restarts the wait.
        frames.handler?.userScrollFine(by: 3)
        frames.now += ScrollPhase.quietNanos / 2
        frames.render(scrolling(log))
        #expect(log.changes.count == 2, "still scrolling")

        frames.now += ScrollPhase.quietNanos
        frames.render(scrolling(log))
        #expect(log.changes.last.map { $0.old == .interacting && $0.new == .idle } == true)
        #expect(log.changes.count == 3)
        #expect(log.contexts.last?.velocity == .zero, "and at the change to idle")
    }

    @Test("A programmatic scroll changes no phase, as SwiftUI's unanimated one does not")
    func programmaticScrollIsNotAPhase() {
        let frames = Frames()
        let log = Log()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = scrolling(log).scrollPosition(binding)
        frames.render(view)
        position.scrollTo(y: 10)
        frames.render(view)
        #expect(log.changes.count == 1, "only the first frame's report")
    }

    @Test("A held scrollbar keeps the view interacting however long it is held")
    func heldScrollbarStaysInteracting() {
        let frames = Frames()
        let log = Log()
        frames.render(scrolling(log))
        frames.handler?.userScrollFine(by: 1)
        frames.handler?.scrollbarDragGrab = 0
        frames.render(scrolling(log))
        frames.now += ScrollPhase.quietNanos * 4
        frames.render(scrolling(log))
        #expect(log.changes.last?.new == .interacting)
        frames.handler?.scrollbarDragGrab = nil
        frames.render(scrolling(log))
        #expect(log.changes.last?.new == .idle)
    }

    @Test("The phase readings")
    func phaseValues() {
        #expect(!ScrollPhase.idle.isScrolling)
        #expect(ScrollPhase.interacting.isScrolling)
        #expect(ScrollPhase.animating.isScrolling)
        #expect(ScrollPhase.decelerating.debugDescription == "decelerating")
    }

    @Test("The two-argument form hears the same changes")
    func twoArgumentForm() {
        let frames = Frames()
        var heard: [ScrollPhase] = []
        let view = ScrollView {
            VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("row \($0)") } }
        }
        .onScrollPhaseChange { _, new in heard.append(new) }
        frames.render(view)
        frames.handler?.userScrollFine(by: 1)
        frames.render(view)
        #expect(heard == [.idle, .interacting])
    }
}
