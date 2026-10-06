//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationModifier+State.swift
//
//  What a sheet's presenter keeps between frames, in `StateStorage` at its own
//  identity: the indices it keeps it at, and the boxes themselves.
//
//  Created by LAYERED.work
//  License: MIT

/// StateStorage property indices for ``ModalPresentationModifier``. A free enum
/// because the modifier is generic (which can't hold static stored properties).
enum ModalPresentationStateIndex {
    static let dragHandler = 0
    static let dismissalGate = 1
    /// The largest size a sticky ``PresentationSizing`` has given the sheet,
    /// for as long as it stays presented: emptied on the frames the sheet is
    /// closed, so presenting it again starts over — and, for the `item:`
    /// forms, when it is presented for another item (`KeptSheetSize`).
    static let keptSheetSize = 2
    /// The detent a sheet with no selection binding rests at, once the reader
    /// has moved it (`SheetDetentState`): emptied on the frames it is closed.
    static let detentState = 3
    /// The grabber's focus id and its handler (`SheetGrabber`).
    static let grabberFocusID = 4
    static let grabber = 5
    /// Whether the sheet has taken the focus since it was presented
    /// (`PresentationEntry`): a live sheet takes it on entry only.
    static let entry = 6
}

private typealias StateIndex = ModalPresentationStateIndex

extension ModalPresentationModifier {
    /// The presenter's record of the largest size a sticky sizing has kept.
    func keptSheetSize(context: RenderContext) -> KeptSheetSize? {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.keptSheetSize),
            default: KeptSheetSize()
        ).value
    }

    /// The same record, if a sticky sizing ever made one.
    ///
    /// Emptied on a closed frame rather than left to the end of the pass's
    /// prune: a presenter whose identity something else keeps — a row of a
    /// list, which keeps every row's state, or the root of a test harness —
    /// was never pruned, and a sticky sheet presented again came back at the
    /// size it had last time.
    func existingKeptSheetSize(context: RenderContext) -> KeptSheetSize? {
        (context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.keptSheetSize))
            as StateBox<KeptSheetSize>?)?.value
    }

    /// The presenter's record of the detent the reader moved the sheet to.
    func detentState(context: RenderContext) -> SheetDetentState {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.detentState),
            default: SheetDetentState()
        ).value ?? SheetDetentState()
    }

    /// The same record, if the sheet was ever presented: emptied on a closed
    /// frame, as ``existingKeptSheetSize(context:)`` is, and for its reason.
    func existingDetentState(context: RenderContext) -> SheetDetentState? {
        (context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.detentState))
            as StateBox<SheetDetentState>?)?.value
    }

    /// The presenter's record of whether the sheet has taken the focus since
    /// it was presented.
    func presentationEntry(context: RenderContext) -> PresentationEntry {
        context.stateStorage?.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.entry),
            default: PresentationEntry()
        ).value ?? PresentationEntry()
    }

    /// The same record, if the sheet was ever presented: emptied on a closed
    /// frame, as ``existingDetentState(context:)`` is.
    func existingPresentationEntry(context: RenderContext) -> PresentationEntry? {
        (context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.entry))
            as StateBox<PresentationEntry>?)?.value
    }
}
