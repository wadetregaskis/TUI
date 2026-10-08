//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SheetProposedWidth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Carrying the width to the sheet's box

private struct SheetProposedWidthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The width the presented sheet's box must take, set by the modal host
    /// when the content named a ``PresentationSizing`` that proposes one — the
    /// width twin of ``sheetDetentHeight``, consumed and cleared by the same
    /// outermost container, for the same reasons.
    var sheetProposedWidth: Int? {
        get { self[SheetProposedWidthKey.self] }
        set { self[SheetProposedWidthKey.self] = newValue }
    }
}
