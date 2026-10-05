//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderWalkCheckpoint.swift
//
//  Where a walk's registrations stood before a subtree rendered, so a view
//  that draws the subtree again in the same walk can put them back first.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// The walk's per-walk registrations as they stood before a subtree rendered.
///
/// A coordinate space whose reader drew from a wrong answer draws its subtree
/// once more in the same walk (`GeometryCoordinator`). Everything the subtree
/// registered the first time would otherwise be registered twice, and the
/// registries that number their entries by position would hand the second
/// drawing different numbers:
///
/// - mouse handler and geometry marker ids are interned per `(identity,
///   slot)`, the slot counted per walk — the second drawing would take the
///   next slots, so its controls and markers would come out under new ids;
/// - `onChange` indices are claimed the same way, and a second drawing would
///   compare against an empty slot and fire as though for the first time;
/// - key handlers append, and a duplicate that declines with a side effect
///   runs it twice;
/// - preferences reduce, so an accumulating key would count the subtree twice.
///
/// ``rollBack(context:)`` puts those back. What it cannot put back is what the
/// first drawing DID: an `onChange` that fired, a task that started. Those
/// happen twice on a correcting frame — the known issue the app header's
/// correction re-render had until the window's chrome was adopted a frame
/// late (`RenderPassScopeTests`), scoped to the subtree, and made only as
/// often as a reader's answer moves.
struct RenderWalkCheckpoint {
    private let identity: ViewIdentity
    private let handlerSlots: Int?
    private let markerSlots: Int?
    private let onChangeCount: Int?
    private let keyMark: KeyEventDispatcher.Mark?
    private let preferences: PreferenceValues?

    /// Notes where the walk stands, before the subtree at `context.identity`
    /// renders.
    init(context: RenderContext) {
        identity = context.identity
        let dispatcher = context.environment.mouseEventDispatcher
        handlerSlots = dispatcher?.handlerIDs.slotCount(at: identity)
        markerSlots = dispatcher?.geometryMarkerIDs.slotCount(at: identity)
        onChangeCount = context.stateStorage?.onChangeCount(at: identity)
        keyMark = context.environment.keyEventDispatcher?.mark
        preferences = context.environment.preferenceStorage?.current
    }

    /// Puts the registrations back to where they stood, for the subtree to be
    /// drawn again.
    func rollBack(context: RenderContext) {
        if let dispatcher = context.environment.mouseEventDispatcher {
            dispatcher.handlerIDs.rewind(at: identity, to: handlerSlots)
            dispatcher.geometryMarkerIDs.rewind(at: identity, to: markerSlots)
        }
        context.stateStorage?.rewindOnChangeCounters(at: identity, to: onChangeCount)
        if let keyMark { context.environment.keyEventDispatcher?.rollBack(to: keyMark) }
        if let preferences { context.environment.preferenceStorage?.current = preferences }
        // What the first drawing stored below here was drawn from the answers
        // the correction exists to replace, and a reader notes its answers once
        // a pass, so the second drawing would be served the first's.
        context.renderCache?.clearAffected(by: identity)
    }
}
