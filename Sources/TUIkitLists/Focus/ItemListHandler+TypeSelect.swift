//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+TypeSelect.swift
//
//  Type select: typing a row's first characters moves a focused list's or
//  table's cursor to it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

extension ItemListHandler: TypeSelectingFocusHandler {
    package var isTypeSelecting: Bool { typeSelected.isTypeSelecting }
}

extension ItemListHandler {
    /// Takes a typed character for type select: adds it to the prefix (or
    /// starts a new one after a pause) and leaves the prefix for the next
    /// render, which knows the rows' text, to find a row for.
    ///
    /// Every printable character but Space, with neither Control nor Option
    /// held, is taken while the control has the focus — as a focused macOS
    /// table takes them, whether or not a row matches — except the first of a
    /// prefix where an app shortcut or one of TUIkit's own bare keys (`q`, `t`,
    /// `a`, the help key) claims it: the input handler gives those their key
    /// first (`InputHandler.typeSelectGivesWay`). The row shortcuts are never
    /// bare keys, so none of them is lost to it.
    ///
    /// - Returns: Whether the key was taken.
    func typeSelect(_ event: KeyEvent) -> Bool {
        guard typeSelected.take(event) else { return false }
        pendingTypeSelect = typeSelected.prefix
        return true
    }

    /// The row `prefix` names: the first, starting at the cursor for a prefix
    /// of more than one character (still typing the same name) and after it
    /// for a first character (the next match), wrapping round, whose text
    /// starts with the prefix — ignoring case. `nil` when none does.
    ///
    /// - Parameter text: A row's type-select text, or `nil` for a row type
    ///   select passes over.
    func typeSelectMatch(_ prefix: String, text: (Int) -> String?) -> Int? {
        TypeSelectBuffer.match(prefix, count: itemCount, current: focusedIndex) { index in
            isLandable(index) ? text(index) : nil
        }
    }

    /// Resolves a typed prefix, if one is waiting: moves the cursor to the row
    /// it names and brings that row into view. Called by the render, with the
    /// rows' text; a measure pass leaves the prefix for the render.
    package func resolvePendingTypeSelect(measuring: Bool, text: (Int) -> String?) {
        guard !measuring, let prefix = pendingTypeSelect else { return }
        pendingTypeSelect = nil
        guard let match = typeSelectMatch(prefix, text: text) else { return }
        focusedIndex = match
        ensureFocusedItemVisible()
    }
}
