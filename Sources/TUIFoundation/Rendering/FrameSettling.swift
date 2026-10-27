//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameSettling.swift
//
//  A frame's walks until what its views did has settled: the effects run
//  after the walk, and a walk whose effects wrote state is walked again before
//  the frame is written, at most twice.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

// MARK: - Frame Settling

/// Walks a frame until its effects have settled, as SwiftUI updates a view
/// graph again before it draws (decisions B-D5G-11).
///
/// A walk holds every effect its views make — an `onAppear`, an `onChange`
/// action, a preference or geometry report, a task's start — on the app's
/// ``EffectStage``, from its first view to its last, and runs them once the
/// walk is done, in SwiftUI's order (``EffectStage/Kind``). If one of them
/// wrote state (a `@State`, an `@Observable` a body read: anything that
/// reaches the render cache's invalidation queue), the walk that was just
/// made is out of date before anyone has seen it, so the frame is walked
/// again, against what they wrote, before it is written: the state an
/// `onAppear` loads, an `onChange` derives or a preference feeds back is in
/// the first frame that reaches the screen, and no view drawn before the
/// effect shows the old value beside one drawn after it.
///
/// At most ``maxRewalks`` walks more, as SwiftUI re-updates twice inside its
/// layout pass (`Tools/SwiftUIProbes/Effect and update ordering/`): a chain of
/// effects longer than that is written as it stands after the last, and
/// carries on one walk a frame, as every chain did before, so a chain that
/// never ends never holds the main thread. Its last effects' writes ask for
/// the next frame, as any write does.
///
/// A frame whose effects wrote nothing is walked once: the cost of settling
/// is one comparison of the invalidation queue's count.
///
/// Every driver of a frame goes through here — `RenderLoop`, the Stress
/// bench's headless frame (`HeadlessInputChannels`), the test harness — so
/// each walks, settles and counts the same.
package enum FrameSettling {
    /// How many times a frame is walked again for what its effects wrote,
    /// at most: two, as SwiftUI updates its graph twice inside the layout
    /// pass before it draws.
    package static let maxRewalks = 2

    /// Walks a frame, runs what its views did, and walks it again while that
    /// wrote state, at most ``maxRewalks`` times; returns the last walk, the
    /// one to write.
    ///
    /// - Parameters:
    ///   - storage: The state storage the frame renders against: its stage
    ///     holds the walk's effects, and its stores are told of a walk made
    ///     again (``StateStorage/beginRewalk()``).
    ///   - cache: The render cache, whose invalidation queue says whether the
    ///     effects wrote, and which drains it before the walk made again
    ///     (``RenderCache/beginRewalk()``). Without one nothing is walked
    ///     again.
    ///   - lifecycle: The lifecycle manager, which counts a view's presence
    ///     per walk (``LifecycleManager/beginRewalk()``).
    ///   - appState: The app's render state: a walk made again is the frame
    ///     the effects' writes asked for, so the request is let go before it
    ///     (a write made after it asks again).
    ///   - walk: Draws the frame, with the root's drawing open on the stage —
    ///     the drawing handed in, which the scene root's geometry correction
    ///     discards before it walks the scene again.
    ///   - endWalk: What the frame owes once it is drawn and before its
    ///     effects run — the geometry reports made at the frame's end — with
    ///     the root's drawing still open, so what they do joins its effects.
    ///   - beginRewalk: What the driver resets for a walk made again, beyond
    ///     what this resets.
    /// - Returns: The last walk.
    package static func settle<Walk>(
        storage: StateStorage?,
        cache: RenderCache?,
        lifecycle: LifecycleManager?,
        appState: AppState?,
        walk: (ProvisionalEffects) -> Walk,
        endWalk: (Walk) -> Void,
        beginRewalk: () -> Void = {}
    ) -> Walk {
        var rewalks = 0
        while true {
            let effects = ProvisionalEffects(stateStorage: storage)
            let drawn = walk(effects)
            // Counted from the walk's end, not its start: a write made during
            // the walk is a body's, which asks for the next frame as it always
            // has, and walking again for it would walk a body that writes
            // every time it runs three times a frame.
            let writes = cache?.link.writeCount
            endWalk(drawn)
            effects.keep()
            guard let cache, cache.link.writeCount != writes else {
                note(rewalks: rewalks, stillWriting: false, storage: storage, cache: cache)
                return drawn
            }
            guard rewalks < maxRewalks else {
                note(rewalks: rewalks, stillWriting: true, storage: storage, cache: cache)
                return drawn
            }
            rewalks += 1
            appState?.didRender()
            cache.beginRewalk()
            storage?.beginRewalk()
            lifecycle?.beginRewalk()
            beginRewalk()
        }
    }

    /// Counts how a frame settled, on the stage and — when
    /// `TUI_DIAGNOSE_BODY_MUTATION` is set — on the diagnostic channel.
    private static func note(rewalks: Int, stillWriting: Bool, storage: StateStorage?, cache: RenderCache?) {
        storage?.effectStage.noteSettled(rewalks: rewalks, stillWriting: stillWriting)
        cache?.bodyMutationDiagnostic?.noteSettled(rewalks: rewalks, stillWriting: stillWriting)
    }
}
