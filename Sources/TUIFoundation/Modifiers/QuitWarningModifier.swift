//  🖥️ TUI — A Terminal UI framework for Swift
//  QuitWarningModifier.swift
//
//  What quitting now would lose: `.quitWarning(_:isActive:)`, which has the quit
//  keys ask first and the dialog name it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Preference Key

/// What the views drawn this frame say quitting would lose, in the order drawn,
/// for the run loop's quit keys to ask about.
package struct QuitWarningsKey: PreferenceKey {
    package static let defaultValue: [String] = []

    package static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View Modifier

extension View {
    /// States that quitting now would lose something, so that every way of
    /// quitting asks first, with a dialog that names it.
    ///
    /// ```swift
    /// UploadsView()
    ///     .quitWarning("Uploading 6 photos", isActive: isUploading)
    /// DraftEditor(draft: $draft)
    ///     .quitWarning("Unsaved changes to \(draft.title)", isActive: draft.isDirty)
    /// ```
    ///
    /// While any view drawn states one, Control-Q and the menu's Quit ask as well
    /// as ⌃\\, whatever the scene's ``QuitConfirmation``. Everything
    /// stated goes in the dialog, as a list, once each. It says nothing about the
    /// app's own ways out: `dismiss()` at the top level quits as it always does,
    /// and a signal from outside (`kill`) does too. Nor about a view that isn't
    /// drawn, such as one on a tab not chosen, so state it where it will be, at or
    /// near the root of the scene's content for something that goes on behind
    /// every screen.
    ///
    /// For a question with answers of its own, such as Save and Don't Save, see
    /// `dismissalConfirmationDialog`, which asks instead, and first. A running ``View/terminalProgress(_:)``
    /// counts as a warning without any words.
    ///
    /// TUI-specific. Neither SwiftUI nor AppKit has a list of this: AppKit asks
    /// an app's delegate (`applicationShouldTerminate(_:)`) and each document
    /// (`NSDocument.isDocumentEdited`), and `ProcessInfo.beginActivity(options:reason:)`
    /// takes a reason nothing can read back.
    ///
    /// A string **literal** binds here, so the words are a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - reasonKey: What would be lost, as a phrase.
    ///   - isActive: Whether it would be, right now.
    /// - Returns: A view that says so while it is drawn.
    public func quitWarning(_ reasonKey: LocalizedStringKey, isActive: Bool = true) -> some View {
        preference(key: QuitWarningsKey.self, value: isActive ? [reasonKey.localized] : [])
    }

    /// States that quitting now would lose something, in words as written.
    ///
    /// - Parameters:
    ///   - reason: What would be lost, as a phrase.
    ///   - isActive: Whether it would be, right now.
    /// - Returns: A view that says so while it is drawn.
    @_disfavoredOverload
    public func quitWarning<S: StringProtocol>(_ reason: S, isActive: Bool = true) -> some View {
        preference(key: QuitWarningsKey.self, value: isActive ? [String(reason)] : [])
    }
}
