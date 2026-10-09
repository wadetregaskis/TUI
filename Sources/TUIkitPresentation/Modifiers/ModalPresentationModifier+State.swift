//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModalPresentationModifier+State.swift
//
//  What a sheet's presenter keeps between frames, in `StateStorage` at its own
//  identity: the indices it keeps it at, and the boxes themselves.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

/// StateStorage property indices for ``ModalPresentationModifier``. A free enum
/// because the modifier is generic (which can't hold static stored properties).
enum ModalPresentationStateIndex {
    static let dragHandler = 0
    static let dismissalGate = 1
    /// The largest size a sticky ``PresentationSizing`` has given the sheet,
    /// for as long as it stays presented (`KeptSheetSize`).
    static let keptSheetSize = 2
    /// The detent a sheet with no selection binding rests at, once the reader
    /// has moved it (`SheetDetentState`).
    static let detentState = 3
    /// The grabber's focus id and its handler (`SheetGrabber`).
    static let grabberFocusID = 4
    static let grabber = 5
    /// Whether the sheet has taken the focus since it was presented, and for
    /// which item (`PresentationEntry`): a live sheet takes it on entry only.
    static let entry = 6
}

extension ModalPresentationModifier {
    /// Empties what the presenter keeps for the sheet it presents, so the
    /// next is a new sheet: it opens where an undragged one does, its sticky
    /// sizing starts again from its content, it rests at the bound detent or
    /// the smallest, and a live one takes the focus again, and may dock.
    ///
    /// On the frames the sheet is closed, rather than left to the end of the
    /// pass's prune: a presenter whose identity something else keeps — a row
    /// of a list, which keeps every row's state, or the root of a test harness
    /// — was never pruned, and a sheet presented again came back as it was
    /// left.
    func startOver(context: RenderContext) {
        DialogDrag.reset(context: context, propertyIndex: StateIndex.dragHandler)
        existingKeptSheetSize(context: context)?.size = nil
        existingDetentState(context: context)?.chosen = nil
        if let entry = existingPresentationEntry(context: context) {
            entry.hasEntered = false
            entry.isKeptOffTheDock = false
            entry.rowsShortOfDetent = nil
        }
    }

    /// Starts over (``startOver(context:)``) when the sheet is presented for
    /// another item than it was: an `item:` sheet switched to another item is
    /// never closed — its binding stays non-`nil` — but the item's id is the
    /// sheet's identity, so another item is another sheet, as SwiftUI
    /// presents it.
    ///
    /// All but the hold off the dock (`PresentationEntry.isKeptOffTheDock`),
    /// which is about where the PRESENTER's row sits, and another item does
    /// not move it. Cleared here, every switch docked the next item's sheet,
    /// whose dock pushed the row out again: drawn, gone with the focus on the
    /// page, a modal again — two frames of flicker, and an appearance and a
    /// disappearance more, on every switch.
    func startOver(forItem itemKey: String, context: RenderContext) {
        let entry = presentationEntry(context: context)
        guard entry.itemKey != itemKey else { return }
        let isKeptOffTheDock = entry.isKeptOffTheDock
        startOver(context: context)
        entry.isKeptOffTheDock = isKeptOffTheDock
        entry.itemKey = itemKey
    }
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

    /// The same record, if a sticky sizing ever made one — to empty
    /// (``startOver(context:)``).
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

    /// The same record, if the sheet was ever presented — to empty.
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

    /// The same record, if the sheet was ever presented — to empty.
    func existingPresentationEntry(context: RenderContext) -> PresentationEntry? {
        (context.stateStorage?.existingStorage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.entry))
            as StateBox<PresentationEntry>?)?.value
    }
}
