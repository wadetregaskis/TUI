//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+RowDrag.swift
//
//  A `.draggable` row from the keyboard (A53-KEYBOARD-DRAG): the list or
//  table, which is its rows' focus stop, answers Copy with the cursor row's
//  payload, and its pick-up chord carries the row as a drag — in both, the
//  whole selection, where the row is one of several selected, as the pointer's
//  drag does (DRAG-SELECTION).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// The drawn rows' drags, as a list or table offers them to the keyboard.
package struct RowDragOffer {
    /// Each drawn row's drag, by row.
    var drags: [Int: RowDrag] = [:]

    /// The focus manager a carry moves. Weak: the handler outlives a manager
    /// a test makes.
    weak var focusManager: FocusManager?

    /// The clipboard a Copy of the selection is waiting to fill, in a list,
    /// until the next frame has drawn the selected rows (`_ListCore`, as a
    /// drag's selection is gathered): a list knows only its window's payloads.
    package var selectionCopy: ClipboardAccess?

    package init() {}
}

extension ItemListHandler {
    /// Offers the drawn rows' drags to the keyboard, this frame: the cursor
    /// row's is what Copy copies and the pick-up chord carries
    /// (``pickUpFocusedRowDrag()``). Copy answers on the container's stop, as
    /// a `.draggable`'s own stop does (`TransferKeys`), and only where a row
    /// drew one.
    ///
    /// On a row that is one of several selected, Copy takes the selection, as a
    /// drag from it does (DRAG-SELECTION): `selectedPayloads`, for a container
    /// that knows every row's, and otherwise on the next frame, which draws the
    /// selected rows to ask them (``RowDragOffer/selectionCopy``).
    @MainActor
    package func offerRowDrags(
        _ drags: [Int: RowDrag], selectedPayloads: (() -> [Any])? = nil, context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        rowDragOffer.drags = drags
        rowDragOffer.focusManager = context.environment.focusManager
        guard !drags.isEmpty, context.environment.isEnabled else { return }
        TransferKeys.register("c", focusIDs: [focusID], context: context) { [weak self] _, clipboard in
            guard let self, let value = rowDragOffer.drags[focusedIndex]?.payload() else { return false }
            guard cursorRowIsOneOfSeveralSelected else {
                clipboard.copy([value])
                return true
            }
            if let selectedPayloads {
                clipboard.copy(selectedPayloads())
            } else {
                rowDragOffer.selectionCopy = clipboard
                drawing?.changed()
            }
            return true
        }
    }

    /// Whether the row the cursor is on is selected, with others.
    private var cursorRowIsOneOfSeveralSelected: Bool {
        guard let selection = multiSelection?.wrappedValue, selection.count > 1, let id = id(at: focusedIndex) else {
            return false
        }
        return selection.contains(id)
    }

    /// Picks the cursor row up as a carry, where it is a drag source, and
    /// answers whether it did: what the pick-up chord does on such a row,
    /// ahead of moving it within the list.
    ///
    /// One gesture for both, as the pointer's is: a drag from a `.draggable`
    /// row is a drag, never an `onMove` reorder, and it lands in its own list
    /// where the list takes it (`ForEach.dropDestination(for:action:)`) — the
    /// carry's stops are every destination that takes it, the list included,
    /// whose rows Up and Down move between. A row with no drag is moved
    /// within the list, as before; the single-step move chords move either.
    func pickUpFocusedRowDrag() -> Bool {
        guard let drag = rowDragOffer.drags[focusedIndex], let focusManager = rowDragOffer.focusManager else {
            return false
        }
        return drag.pickUp(focusID, focusManager)
    }
}
