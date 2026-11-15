//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemListHandler+WrittenSelection.swift
//
//  A selection the app writes moves the cursor onto it. On macOS the cursor
//  is the selection, so an app that selects a row — Duplicate selecting the
//  copy, Find selecting a match — has the next arrow go on from there; here
//  the cursor stayed where it was, and the next arrow went on from it.
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

    /// Moves the cursor onto a selection the app wrote since the last frame:
    /// for a single selection onto its row, and for a multiple one onto its
    /// first row in the rows' order, unless the cursor is on a selected row
    /// already — the rule the focus leaving puts it by
    /// (``onFocusLost()``). A selection the list wrote itself
    /// (``writeSingleSelection(_:)``), one emptied, and one whose rows are not
    /// among the rows leave it where it is. Render pass only, once the
    /// selection binding and the rows' ids are this frame's.
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
            guard case .single(let seen)? = seenSelection, seen != current, let current,
                id(at: focusedIndex) != current, let index = index(of: current)
            else { return }
            moveCursor(toWritten: index)
        case .multi:
            let current = multiSelection?.wrappedValue ?? []
            defer { seenSelection = .multiple(current) }
            guard case .multiple(let seen)? = seenSelection, seen != current, !current.isEmpty else { return }
            func selected(_ index: Int) -> Bool { id(at: index).map(current.contains) ?? false }
            guard !selected(focusedIndex), let index = (0..<itemCount).first(where: selected) else { return }
            moveCursor(toWritten: index)
        }
    }

    /// Puts the cursor on `index` for a selection the app wrote, and the
    /// range anchor with it, so a Shift-arrow extends from the row written.
    private func moveCursor(toWritten index: Int) {
        focusedIndex = index
        if selectionAnchor != nil { selectionAnchor = index }
    }
}
