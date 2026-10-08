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
/// - preferences reduce, so an accumulating key would count the subtree twice;
/// - a memo recording around the subtree (`EffectJournal`) would keep what
///   both drawings registered, and make the first drawing's registrations
///   again on every frame it serves — the handlers of rows the frame never
///   showed;
/// - a live sheet's dock (`PaneLedger.docks`) and a windowing container's
///   note of the rows it drew (`StateStorage.noteWindowedRows`) are what the
///   frame's settle asks about the walk drawn
///   (`FocusManager.settlePresentationDock`). Left in, a presenter the first
///   drawing alone drew had posted its dock, so a sheet whose presenter the
///   kept drawing left out read as drawn — the docked rows stayed blank, the
///   focus in a sheet nothing showed, and no frame was asked for to settle
///   it — and a row the first drawing alone left out read as left out.
///
/// ``rollBack(context:)`` puts those back. What it cannot put back is what the
/// first drawing DID: an `onChange` that fired, a task that started. Those
/// happen twice on a correcting frame — the known issue the app header's
/// correction re-render had until the window's chrome was adopted a frame
/// late (`RenderPassScopeTests`), scoped to the subtree, and made only as
/// often as a reader's answer moves.
///
/// Nor does it put back the live registrations that are not numbered by
/// position: a control's place in the focus ring, a keyboard shortcut, a
/// status-bar item, a drop target. Those registries take a second
/// registration of the same thing as one, so a view drawn in both drawings is
/// registered once; but a view drawn only in the first — a row of a band the
/// scroll view replaced — stays registered for the frame, in the first
/// drawing's order (the bug class `RenderLoop.beginSceneRender()` describes,
/// for the whole scene). What a memo records of them is put back, above.
///
/// A scroll view drawing its content again for a reason of its own — a band
/// that does not cover the offset the frame settled on — puts the walk back
/// too (``rewind(context:)``), or a row drawn twice would come out under a
/// second marker id, and its scroll visibility observer would be told it
/// appeared and that its first id vanished, every such frame.
struct RenderWalkCheckpoint {
    private let identity: ViewIdentity
    private let handlerSlots: Int?
    private let markerSlots: Int?
    private let onChangeCount: Int?
    private let keyMark: KeyEventDispatcher.Mark?
    private let preferences: PreferenceValues?
    /// How many entries the recording memo's journal held, or `nil` when no
    /// memo records here.
    private let journalCount: Int?
    /// The docks the walk's live sheets had posted, or `nil` without a focus
    /// manager. Kept whole: a dictionary has no order to cut back to, and the
    /// copy is a reference until a drawing posts.
    private let docks: [String: PaneLedger.PostedDock]?
    /// How many windowing containers had noted the rows they drew.
    private let windowedRowsNoted: Int?

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
        journalCount = context.recordingEffectJournal?.count
        docks = context.environment.focusManager?.panes.docks
        windowedRowsNoted = context.stateStorage?.windowedRowsNoted
    }

    /// Puts the registrations back to where they stood, for the subtree to be
    /// drawn again with something in it corrected.
    func rollBack(context: RenderContext) {
        rewind(context: context)
        // What the first drawing stored below here was drawn from the answers
        // the correction exists to replace, and a reader notes its answers once
        // a pass, so the second drawing would be served the first's.
        context.renderCache?.clearAffected(by: identity)
    }

    /// Puts the registrations back to where they stood, for the subtree to be
    /// drawn again from the same inputs — so the second drawing takes the
    /// first one's ids and indices, and what the first stored in the render
    /// cache may serve it.
    func rewind(context: RenderContext) {
        if let dispatcher = context.environment.mouseEventDispatcher {
            dispatcher.handlerIDs.rewind(at: identity, to: handlerSlots)
            dispatcher.geometryMarkerIDs.rewind(at: identity, to: markerSlots)
        }
        context.stateStorage?.rewindOnChangeCounters(at: identity, to: onChangeCount)
        if let keyMark { context.environment.keyEventDispatcher?.rollBack(to: keyMark) }
        if let preferences { context.environment.preferenceStorage?.current = preferences }
        if let journalCount { context.renderCache?.effectJournal.truncate(to: journalCount) }
        // What the settle asks of the walk is the kept drawing's alone.
        if let docks { context.environment.focusManager?.panes.docks = docks }
        if let windowedRowsNoted { context.stateStorage?.rewindWindowedRows(to: windowedRowsNoted) }
        // A value the first drawing saw for the first time, and the second sees
        // differently, appears at the second's: the first is never shown, so
        // there is nothing for it to animate from (`AnimationStore.beginWalk()`).
        context.stateStorage?.animations.beginWalk()
    }
}
