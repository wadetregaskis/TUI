//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFindingFocusedValue.swift
//
//  What a focused view that can find text publishes, for the Edit menu's
//  Find… and Find Next to be enabled by.
//
//  Created by Wade Tregaskis
//  License: MIT

/// That the focused view can find in its text: a `TextEditor` with its find
/// bar (`findDisabled(false)`, the default) publishes it while it, or a view
/// inside it, has the focus.
///
/// The menu bar's Find… and Find Next (`TextEditingCommands`) read it, and are
/// disabled where nothing publishes it — as AppKit validates its Find items
/// against the responder chain, so they are disabled where nothing in it can
/// find. They act by pressing the editor's own keys, so the value says only
/// that there is something to press them for.
///
/// Package-wide, not public: SwiftUI has no such key, its Find items being
/// AppKit's.
package struct TextFinding: Equatable, Sendable {
    package init() {}
}

private struct TextFindingKey: FocusedValueKey {
    typealias Value = TextFinding
}

extension FocusedValues {
    /// That the focused view can find in its text (``TextFinding``).
    package var textFinding: TextFinding? {
        get { self[TextFindingKey.self] }
        set { self[TextFindingKey.self] = newValue }
    }
}
