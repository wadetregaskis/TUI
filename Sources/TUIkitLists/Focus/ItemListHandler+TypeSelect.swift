//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+TypeSelect.swift
//
//  Type select: typing a row's first characters moves a focused list's or
//  table's cursor to it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension ItemListHandler: TypeSelectingFocusHandler {
    var isTypeSelecting: Bool {
        guard !typeSelectPrefix.isEmpty, let last = typeSelectLastKey else { return false }
        return ContinuousClock.now - last <= Self.typeSelectTimeout
    }
}

extension ItemListHandler {
    /// How long a pause starts a new prefix: macOS's type select forgets what
    /// was typed after about a second.
    static var typeSelectTimeout: Duration { .seconds(1) }

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
        guard case .character(let character) = event.key, !event.ctrl, !event.alt,
            character != " ", !character.isNewline,
            character.unicodeScalars.allSatisfy({ !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 0x20 })
        else { return false }
        let now = ContinuousClock.now
        if let last = typeSelectLastKey, now - last > Self.typeSelectTimeout { typeSelectPrefix = "" }
        typeSelectLastKey = now
        typeSelectPrefix.append(character)
        pendingTypeSelect = typeSelectPrefix
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
        guard itemCount > 0, !prefix.isEmpty else { return nil }
        let wanted = prefix.lowercased()
        let start = prefix.count > 1 ? focusedIndex : focusedIndex + 1
        for step in 0..<itemCount {
            let index = (start + step) % itemCount
            guard isLandable(index), let rowText = text(index), !rowText.isEmpty else { continue }
            if rowText.lowercased().hasPrefix(wanted) { return index }
        }
        return nil
    }

    /// Resolves a typed prefix, if one is waiting: moves the cursor to the row
    /// it names and brings that row into view. Called by the render, with the
    /// rows' text; a measure pass leaves the prefix for the render.
    func resolvePendingTypeSelect(measuring: Bool, text: (Int) -> String?) {
        guard !measuring, let prefix = pendingTypeSelect else { return }
        pendingTypeSelect = nil
        guard let match = typeSelectMatch(prefix, text: text) else { return }
        focusedIndex = match
        ensureFocusedItemVisible()
    }
}
