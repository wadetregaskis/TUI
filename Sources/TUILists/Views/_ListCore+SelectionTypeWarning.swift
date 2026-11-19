//  🖥️ TUI — A Terminal UI framework for Swift
//  _ListCore+SelectionTypeWarning.swift
//
//  A debug build's word when a `List`'s selection can name none of its rows:
//  a selection of one type over rows identified by another selects nothing, as
//  in SwiftUI, and says nothing there either (tuiarcade's feedback,
//  2026-11-17: `GameID?` over rows whose `id` was a `String`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

extension _ListCore {
    /// Warns, once per pair of types, that this list's selection binding cannot
    /// hold the ids its rows are identified by, so no row can be selected. Only
    /// for a list that has a selection binding: without one, nothing was asked
    /// of the ids. Nothing else changes: the rows are drawn, and select
    /// nothing, as SwiftUI's do.
    ///
    /// Through ``SoftTrap/warn(_:)``, TUI's runtime warning: on stderr once the
    /// app gives the terminal back, or in `TUI_DIAGNOSTICS_FILE` at once. A
    /// debug build only (the caller's `#if DEBUG`), since a release build of
    /// an app that shipped this has nobody to read it.
    ///
    /// - Parameter idType: The type the rows are identified by.
    func warnSelectionNamesNoRow(identifiedBy idType: Any.Type) {
        guard singleSelection != nil || multiSelection != nil, idType != SelectionValue.self else { return }
        SoftTrap.warn(Self.selectionNamesNoRowMessage(idType: idType))
    }

    /// ``warnSelectionNamesNoRow(identifiedBy:)`` for `content`, when it is a
    /// `ForEach` or an outline (`List(_:children:selection:)`) whose rows this
    /// list's selection can name none of: a list's whole content, or one
    /// section's (a `ForEach` of `Section`s, or sections written out), where
    /// the rows are not windowed and so are not asked about where the flat
    /// `ForEach`'s are. A debug build only (the caller's `#if DEBUG`).
    func warnIfSelectionNamesNoRow(of content: Any) {
        let idType =
            (content as? any WindowedListRowExtractor)?.listRowIDTypeNamingNone(SelectionValue.self)
            ?? (content as? any WindowedOutlineListRows)?.listRowIDTypeNamingNone(SelectionValue.self)
        guard let idType else { return }
        warnSelectionNamesNoRow(identifiedBy: idType)
    }

    /// The words of ``warnSelectionNamesNoRow(identifiedBy:)``.
    static func selectionNamesNoRowMessage(idType: Any.Type) -> String {
        "List's selection holds \(SelectionValue.self), but its rows are identified by \(idType): "
            + "no row can be selected. Bind the selection to \(idType), or give each row a "
            + ".tag(_:) of \(SelectionValue.self)."
    }
}
