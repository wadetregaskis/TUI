//  🖥️ TUI — A Terminal UI framework for Swift
//  GlideFrames.swift
//
//  Frames drawn as the run loop draws them, for the animated-scrolling tests
//  (decisions B27-ANIMATING): the change's transaction and completions for
//  the one pass that shows it, the frame clock set by hand, and the next
//  frame taken from the scheduler's wakes. Shared by the `ScrollView` suites
//  and the `List` and `Table` ones.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUIView

/// Where a test keeps the `ScrollViewProxy` a reader hands its content.
final class GlideProxyBox: @unchecked Sendable {
    var proxy: ScrollViewProxy?
}

/// A view drawn frame by frame as the run loop draws it.
@MainActor
final class GlideFrames {
    let tuiContext = TUIContext()
    let focusManager = FocusManager()
    let scheduler = AnimationScheduler()
    var reduceMotion = false
    var canAnimate = true
    /// The frame clock, in nanoseconds.
    private(set) var now: Int64 = 1_000_000_000
    /// The volatile-read tracker of the frame drawn last.
    private(set) var tracker = VolatileReadTracker()

    /// Draws `view` at `nanos` (or at the clock as it stands) under the
    /// transaction a change since the last frame was made under — or under
    /// `transaction`, for a change made without one — handing that change's
    /// completions to the pass, and returns its lines, trimmed.
    @discardableResult
    func render<V: View>(
        _ view: V, atNanos nanos: Int64? = nil, transaction: Transaction? = nil, height: Int = 6
    ) -> [String] {
        if let nanos { now = nanos }
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tuiContext)
        environment.animationScheduler = canAnimate ? scheduler : nil
        environment.animationFrame = AnimationFrame(nowNanos: now, step: 0, canAnimate: canAnimate)
        environment.accessibilityReduceMotion = reduceMotion
        environment.transaction = transaction ?? tuiContext.appState.consumePendingTransaction() ?? Transaction()
        tracker = VolatileReadTracker()
        environment.volatileReadTracker = tracker
        let context = RenderContext(
            availableWidth: 20, availableHeight: height, environment: environment, tuiContext: tuiContext)
        let storage = tuiContext.stateStorage
        tuiContext.preferences.beginRenderPass()
        storage.beginRenderPass()
        storage.animationCompletions.beginPass(placing: tuiContext.appState.consumePendingCompletions())
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        scheduler.beginFrame()
        let buffer = renderToBuffer(view, context: context)
        scheduler.endFrame()
        focusManager.endRenderPass()
        storage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        storage.animationCompletions.endPass(at: now, animations: storage.animations)
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// When the frames drawn so far asked to be drawn next, if they did.
    var nextWake: Int64? { scheduler.nextFiring(after: now) }

    /// Draws `view` at each frame it asks for until it asks for none, and
    /// returns each one's instant and lines. Stops after `limit` frames.
    @discardableResult
    func follow<V: View>(_ view: V, limit: Int = 200) -> [(nanos: Int64, lines: [String])] {
        var frames: [(nanos: Int64, lines: [String])] = []
        while let wake = nextWake, frames.count < limit {
            frames.append((wake, render(view, atNanos: wake)))
        }
        return frames
    }

    var handler: ScrollViewHandler? {
        focusManager.activeSection?.focusables.compactMap { $0 as? ScrollViewHandler }.first
    }
}

/// The row a frame shows first, by its number.
func topRow(_ lines: [String]) -> Int? {
    lines.first.flatMap { Int($0.replacingOccurrences(of: "row ", with: "")) }
}

@MainActor
final class GlidePhaseLog {
    var changes: [String] = []
    var velocities: [CellVector?] = []
}

@MainActor
final class GlideBuiltRows {
    var count = 0
}

#endif
