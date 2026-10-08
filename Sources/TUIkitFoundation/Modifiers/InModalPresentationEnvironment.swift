//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InModalPresentationEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Inside a modal presentation

/// Environment key for the content of a presentation that holds the keyboard.
private struct InModalPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is the content of a presentation that holds the
    /// keyboard — a modal sheet, a full-screen cover, a popover — so that a
    /// sheet presented from it is a modal too, whatever its background
    /// interaction (`LiveSheet.dock`).
    ///
    /// Set by those presenters for the content they present; a live sheet's
    /// content shares the keyboard with its page, and does not set it.
    package var isInModalPresentation: Bool {
        get { self[InModalPresentationKey.self] }
        set { self[InModalPresentationKey.self] = newValue }
    }
}
