//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectingFocusHandler.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A focused control that finds its rows by typed characters (type select),
/// asked by the input handler whether a prefix is under way.
protocol TypeSelectingFocusHandler: AnyObject {
    /// Whether characters typed now continue a prefix — one was typed less
    /// than the type-select timeout ago.
    var isTypeSelecting: Bool { get }
}
