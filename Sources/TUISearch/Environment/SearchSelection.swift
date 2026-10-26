//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchSelection.swift
//
//  `searchSelection(_:)`: binding the selection of the search field a
//  `.searchable` draws, from outside it (decisions A25), as `searchFocused`
//  binds its focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - searchSelection

extension View {
    /// Binds the selection of the search field of the nearest searchable
    /// modifier — SwiftUI's `searchSelection(_:)`.
    ///
    /// Write it after the `searchable`, as `searchFocused` is:
    ///
    /// ```swift
    /// List(results) { Text($0.name) }
    ///     .searchable(text: $query)
    ///     .searchSelection($querySelection)
    /// ```
    ///
    /// The field writes its caret and selection to the binding as they move,
    /// and a selection the app writes moves them, as a ``TextField``'s
    /// `selection:` does. Available from macOS 15, with ``TextSelection``,
    /// where SwiftUI's is macOS 26's.
    ///
    /// - Parameter selection: The selection to bind.
    /// - Returns: The modified view.
    @available(macOS 15, *)
    public func searchSelection(_ selection: Binding<TextSelection?>) -> some View {
        _SearchSelectionModifier(content: self, selection: selection)
    }
}

/// The `searchSelection` binding on its way in to the search field: one box
/// for the modifier's life, compared by identity, so the environment value is
/// the same from frame to frame and the memos below are untouched. The binding
/// in it, a `Binding<TextSelection?>` held as `Any` because ``TextSelection``
/// is macOS 15's, is refreshed each time the modifier's body runs.
final class SearchSelectionBox: Equatable, @unchecked Sendable {
    var binding: Any?

    nonisolated static func == (lhs: SearchSelectionBox, rhs: SearchSelectionBox) -> Bool { lhs === rhs }
}

/// What ``View/searchSelection(_:)`` makes: the binding, boxed, in the
/// environment of the searchable it is written around.
@available(macOS 15, *)
struct _SearchSelectionModifier<Content: View>: View {
    let content: Content
    let selection: Binding<TextSelection?>

    @State private var box = SearchSelectionBox()

    var body: some View {
        box.binding = selection
        return content.environment(\.searchSelection, box)
    }
}

private struct SearchSelectionKey: EnvironmentKey {
    static let defaultValue: SearchSelectionBox? = nil
}

extension EnvironmentValues {
    /// The `searchSelection` binding for the nearest searchable's field.
    var searchSelection: SearchSelectionBox? {
        get { self[SearchSelectionKey.self] }
        set { self[SearchSelectionKey.self] = newValue }
    }
}
