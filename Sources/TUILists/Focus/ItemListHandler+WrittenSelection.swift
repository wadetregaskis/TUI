//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+WrittenSelection.swift
//
//  A selection the app writes moves the cursor onto it, and so does one it
//  starts with. On macOS the cursor is the selection, so an app that selects
//  a row — Duplicate selecting the copy, Find selecting a match, a list that
//  opens on the row chosen last time — has the next arrow go on from there;
//  here the cursor stayed where it was, and the next arrow went on from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension ItemListHandler {
    /// The selection as the list last saw it: what this frame's binding is
    /// compared with to tell a selection the app wrote since.
    enum SeenSelection {
        case single(SelectionValue?)
        case multiple(Set<SelectionValue>)
    }

    /// Writes the single selection, as the list's own keys and clicks do, and
    /// notes it as seen: a write of the list's own never moves the cursor
    /// (``followWrittenSelection()``).
    ///
    /// Noted as the binding reads back, not as written: a binding whose setter
    /// keeps only some of what it is given — a file panel's, which refuses the
    /// rows it dims — reads back less than was written, and that is still the
    /// list's own write. Noted as written, ⌃A over a dimmed row read as the app
    /// writing a selection, and the cursor jumped to its first row.
    func writeSingleSelection(_ value: SelectionValue?) {
        guard let singleSelection else { return }
        singleSelection.wrappedValue = value
        seenSelection = .single(singleSelection.wrappedValue)
    }

    /// Writes the multiple selection, as the list's own keys and clicks do,
    /// and notes it as seen, as it reads back — see ``writeSingleSelection(_:)``.
    func writeMultiSelection(_ value: Set<SelectionValue>) {
        guard let multiSelection else { return }
        multiSelection.wrappedValue = value
        seenSelection = .multiple(multiSelection.wrappedValue)
    }

    /// Takes this frame's selection mode, as the bindings are taken: a list
    /// made with no binding and later given a `Set` one, as SwiftUI's
    /// `List(selection: isEditing ? $picked : nil)` is, keeps one handler, and
    /// with the mode it was made with it never selected (hunt item LISTS-3).
    ///
    /// A change drops the range anchor and extend mode, which belonged to the
    /// other kind of selection, and what was seen of it: the selection the
    /// new binding holds is then followed as one the list starts with
    /// (``followWrittenSelection()``), so an empty one leaves the cursor where
    /// it is and one the app filled moves the cursor onto it. Called before
    /// the binding is followed, in the same frame.
    package func adoptSelectionMode(_ mode: SelectionMode) {
        guard mode != selectionMode else { return }
        selectionMode = mode
        selectionAnchor = nil
        isExtendingSelection = false
        seenSelection = nil
    }

    /// Moves the cursor onto a selection the app wrote since the last frame,
    /// or started with (the first frame, with nothing seen yet): for a single
    /// selection onto its row, and for a multiple one onto its first row in
    /// the rows' order, unless the cursor is on a selected row already — the
    /// rule the focus leaving puts it by (``onFocusLost()``). A selection the
    /// list wrote itself (``writeSingleSelection(_:)``), one emptied, and one
    /// whose rows are not among the rows leave it where it is. Render pass
    /// only, once the selection binding and the rows' ids are this frame's.
    ///
    /// The first frame's is stage 1 of
    /// `Documentation/Historical/Lists, tables and tabs/The first key from an empty selection.md`:
    /// noted as seen and nothing more, a selection the app started with left
    /// the cursor on row 0, so with row 5 selected the first Down went to
    /// row 1 (and under `.selectionFollowsCursor()` selected it), where macOS's
    /// goes to row 6. In both modes, since without the modifier the cursor
    /// the focus arrives with was row 0, not the row the list showed chosen.
    /// Not where a Bottom anchor carried the cursor to the tail that frame
    /// (``opensAtTheTail``).
    ///
    /// With `.selectionFollowsCursor()` and without it: SwiftUI's next arrow
    /// goes on from the selection whoever wrote it, its cursor being the
    /// selection, and what the owner kept apart (APPFB-1) is the keys'
    /// moves selecting, which this is not. The row is not scrolled to, as a
    /// macOS table's is not: `scrollTo` does that.
    ///
    /// Costs one compare of the selection a frame, and a search for its row
    /// only on a frame where the app changed it.
    package func followWrittenSelection() {
        switch selectionMode {
        case .single:
            let current = singleSelection?.wrappedValue
            defer { seenSelection = .single(current) }
            // Nothing seen yet is the first frame, which follows too.
            if case .single(let seen)? = seenSelection, seen == current { return }
            guard !opensAtTheTail else { return }
            guard let current else {
                forgetCursor()
                return
            }
            if id(at: focusedIndex) == current {
                cursorIsPlaced = true
                return
            }
            guard let index = index(of: current) else { return }
            moveCursor(toWritten: index)
        case .multi:
            let current = multiSelection?.wrappedValue ?? []
            defer { seenSelection = .multiple(current) }
            if case .multiple(let seen)? = seenSelection, seen == current { return }
            guard !opensAtTheTail else { return }
            guard !current.isEmpty else {
                forgetCursor()
                return
            }
            func selected(_ index: Int) -> Bool { id(at: index).map(current.contains) ?? false }
            if selected(focusedIndex) {
                cursorIsPlaced = true
                return
            }
            guard let index = (0..<itemCount).first(where: selected) else { return }
            moveCursor(toWritten: index)
        }
    }

    /// Whether this is the first frame of a list whose Bottom anchor carried
    /// the cursor to its tail (``bottomFollowCursor``): the selection it
    /// starts with leaves the cursor there. A `.defaultScrollAnchor(.bottom)`
    /// log opens on its newest rows; moved onto a selection above them, the
    /// cursor ended the follow (the cursor outranks the tail) and the focus
    /// arriving scrolled the list to it.
    private var opensAtTheTail: Bool {
        seenSelection == nil && bottomFollowCursor != nil
    }

    /// The app emptied the selection (not the first frame, where nothing was
    /// seen to empty): the cursor goes with it, as macOS's does, so under
    /// `.selectionFollowsCursor()` the next Down selects the first row and Up
    /// the last, not the rows beside the one the selection left.
    private func forgetCursor() {
        if seenSelection != nil { cursorIsPlaced = false }
    }

    /// Puts the cursor on `index` for a selection the app wrote, and the
    /// range anchor with it, so a Shift-arrow extends from the row written.
    private func moveCursor(toWritten index: Int) {
        focusedIndex = index
        if selectionAnchor != nil { selectionAnchor = index }
    }
}
