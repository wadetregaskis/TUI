//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationRecordRetentionTests.swift
//
//  A value the render memo serves keeps the record a later change animates
//  from, as its `@State` is kept: a row served on the frames after the first
//  was dropped from the animation store, and its next change jumped to its
//  end (the To do clip's strikethrough, drawn whole live, 2026-10-28).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A row memoized by its value alone, as a list's rows are.
private struct Row: View, @MainActor Equatable {
    let done: Bool

    var body: some View {
        Text("abcdefgh").strikethrough(done)
    }
}

@MainActor
@Suite("An animation's record survives the frames the memo serves")
struct AnimationRecordRetentionTests {
    private let tui = TUIContext()

    /// Which cells of the first line are struck at `millis`, the frame drawn
    /// under `animation` (a change's transaction) or none.
    private func struck(done: Bool, atMillis millis: Int, animation: Animation? = nil) -> String {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.mouseEventDispatcher = nil
        environment.installVolatileReadTracker(VolatileReadTracker())
        environment.animationFrame = AnimationFrame(nowNanos: Int64(millis) * 1_000_000, step: 0, canAnimate: true)
        environment.transaction = Transaction(animation: animation)
        let context = RenderContext(availableWidth: 20, availableHeight: 2, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let line = renderToBuffer(VStack { Row(done: done).equatable() }, context: context).lines.first ?? ""
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return String((0..<line.strippedLength).map { line.ansiSGRStateAt(visibleColumn: $0).isStruckThrough ? "-" : " " })
    }

    @Test("A strike changed under an animation sweeps though the row was served for frames before")
    func servedRowStillSweeps() {
        _ = struck(done: false, atMillis: 0)
        let misses = tui.renderCache.stats.misses
        _ = struck(done: false, atMillis: 17)
        _ = struck(done: false, atMillis: 33)
        #expect(tui.renderCache.stats.misses == misses, "the row was not served from the memo, so this proves nothing")
        #expect(struck(done: true, atMillis: 50, animation: .linear(duration: 1)) == "        ")
        #expect(struck(done: true, atMillis: 550) == "----    ")
        #expect(struck(done: true, atMillis: 1100) == "--------")
    }

    /// A served subtree keeps its records for a stretch of passes and is asked
    /// again halfway through it (`AnimationStore.keepPasses`): served for
    /// longer than the stretch, the row still has what it animates from.
    @Test("A row served for longer than the store's keeping stretch still sweeps")
    func longServedRowStillSweeps() {
        _ = struck(done: false, atMillis: 0)
        for frame in 1...100 { _ = struck(done: false, atMillis: frame * 17) }
        #expect(struck(done: true, atMillis: 2000, animation: .linear(duration: 1)) == "        ")
        #expect(struck(done: true, atMillis: 2500) == "----    ")
    }
}
