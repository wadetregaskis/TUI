//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProvisionalEffects.swift
//
//  A drawing the walk may still throw away, open on the effect stage: what
//  its views do, once a reader in it is told an answer, waits until it is kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

/// One drawing the walk may still discard, open on the app's ``EffectStage``
/// from when this is made until ``keep()``.
///
/// Once a reader in it has been told an answer that could be wrong — or from
/// the start, for a drawing made ``init(context:armed:)`` armed — its views
/// hold back what they do (an `onChange` action, an `onAppear`, a task's
/// start) and note how to put back what they remembered in deciding to.
/// ``discard()`` throws the drawing away for another to be made in its place:
/// its held effects dropped and its views' memories put back. ``keep()`` lets
/// the effects run, when nothing armed encloses the drawing.
///
/// What a geometry owner opens for the subtree it may draw again
/// (``RenderWalkCheckpoint``), and what a scene's root opens for a walk of the
/// scene it may walk again (`RenderLoop.renderContent`).
///
/// Every one made must be kept, once, whatever becomes of the drawing — the
/// last drawing made is the one kept — or every effect after it is held back
/// until the next render pass, which closes it with a soft trap
/// (``EffectStage/beginRenderPass()``).
package struct ProvisionalEffects {
    private let stage: EffectStage?
    private let mark: EffectStage.Mark?

    /// Opens a drawing on `stateStorage`'s stage — armed from the start when
    /// `armed`, for a drawing that may be made again for a reason no reader
    /// signals. With no storage there is no stage, and the drawing's views
    /// act at once.
    package init(stateStorage: StateStorage?, armed: Bool = false) {
        stage = stateStorage?.effectStage
        mark = stage?.open()
        if armed, let stage { stage.arm(atDepth: stage.depth) }
    }

    /// Opens a drawing on the stage of `context`'s storage.
    package init(context: RenderContext, armed: Bool = false) {
        self.init(stateStorage: context.stateStorage, armed: armed)
    }

    /// Throws away what the drawing held back so far, and puts back what its
    /// views remembered in holding it, for another drawing to be made in its
    /// place. It stays open.
    package func discard() {
        if let stage, let mark { stage.discard(since: mark) }
    }

    /// Keeps the drawing as it last stands: what it held back runs, now or
    /// with the armed drawing that encloses it.
    package func keep() {
        if let stage, let mark { stage.close(mark) }
    }
}
