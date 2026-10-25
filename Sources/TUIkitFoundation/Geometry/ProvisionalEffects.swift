//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProvisionalEffects.swift
//
//  A drawing the walk may still throw away, open on the effect stage: what
//  its views do waits until it is kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

/// One drawing the walk may still discard, open on the app's ``EffectStage``
/// from when this is made until ``keep()``.
///
/// While it is open its views hold back what they do (an `onChange` action,
/// an `onAppear`, a task's start) and note how to put back what they
/// remembered in deciding to. ``discard()`` throws the drawing away for
/// another to be made in its place: its held effects dropped and its views'
/// memories put back. ``keep()`` lets the effects run, once no drawing
/// encloses it — the walk's end, for the scene root's.
///
/// What a geometry owner opens for the subtree it may draw again
/// (``RenderWalkCheckpoint``), and what a scene's root opens for each walk of
/// the scene (`FrameSettling`).
///
/// Every one made must be kept, once, whatever becomes of the drawing — the
/// last drawing made is the one kept — or every effect after it is held back
/// until the next render pass, which closes it with a soft trap
/// (``EffectStage/beginRenderPass()``).
package struct ProvisionalEffects {
    private let stage: EffectStage?
    private let mark: EffectStage.Mark?

    /// Opens a drawing on `stateStorage`'s stage. With no storage there is no
    /// stage, and the drawing's views act at once.
    package init(stateStorage: StateStorage?) {
        stage = stateStorage?.effectStage
        mark = stage?.open()
    }

    /// Opens a drawing on the stage of `context`'s storage.
    package init(context: RenderContext) {
        self.init(stateStorage: context.stateStorage)
    }

    /// Throws away what the drawing held back so far, and puts back what its
    /// views remembered in holding it, for another drawing to be made in its
    /// place. It stays open.
    package func discard() {
        if let stage, let mark { stage.discard(since: mark) }
    }

    /// Keeps the drawing as it last stands: what it held back runs, now or
    /// with the drawing that encloses it.
    package func keep() {
        if let stage, let mark { stage.close(mark) }
    }
}

extension RenderContext {
    /// Does what a view decided, as it renders, to do: at once, or — in a
    /// drawing that may yet be drawn again — once the drawing is kept, with
    /// `undo` putting back what deciding it changed should the drawing be
    /// discarded (``EffectStage``). For a decision whose memory is not a
    /// tracked value (``StateStorage/setChangedTrackedValue(_:for:)``) — the
    /// last value a scroll view told an observer.
    ///
    /// - Parameters:
    ///   - kind: What kind of effect it is, which decides when it runs among
    ///     the others the drawing held (``EffectStage/Kind``).
    ///   - effect: What the view does.
    ///   - undo: Puts back what the view changed in deciding to do it.
    package func performEffect(
        as kind: EffectStage.Kind, _ effect: @escaping () -> Void, undo: @escaping () -> Void
    ) {
        guard let stage = stateStorage?.effectStage else {
            effect()
            return
        }
        stage.noteUndo(undo)
        stage.perform(as: kind, effect)
    }
}
