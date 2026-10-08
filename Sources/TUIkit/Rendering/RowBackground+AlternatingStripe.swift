//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowBackground+AlternatingStripe.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Alternating rows

extension RowBackground {
    /// What a striped row draws: the palette's accent at low opacity over the
    /// surface the row sits on, as a 256- or 16-colour terminal can draw it
    /// quietly (``Palette/stripeFill(over:at:)``) — and nothing where no colour
    /// can be, since a band of reverse video down every other row would read
    /// as a screen full of cursors, and one in a selected row's colour as a
    /// screen of selections.
    ///
    /// Over the SURFACE, not the page (``EnvironmentValues/enclosingSurface``):
    /// a table in a `TabView`'s body sits on the tab's tone, and 15% of the
    /// accent over the page drawn there is a band darker or lighter than the
    /// rows between, rather than the same rows a step toward the accent.
    ///
    /// One answer for `_ListCore` and `Table`, which stripe the same rows the
    /// same way.
    static func alternatingStripe(palette: any Palette, over surface: Color) -> RowBackground {
        palette.stripeFill(over: surface).map(Self.fixed) ?? .none
    }
}
