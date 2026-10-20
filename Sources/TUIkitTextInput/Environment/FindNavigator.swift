//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FindNavigator.swift
//
//  SwiftUI's find and replace interface for text editors: the modifiers that
//  present it and disable it, and the context a text view reads them from.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The environment

/// What the find modifiers above a text editor have said.
///
/// Compared by what an editor draws from it — whether the bar is up, and what
/// it may do — rather than by the binding, which is a pair of closures with no
/// equality: a value that compared unequal every pass would clear the memos
/// below it each frame, and one that could not compare at all would turn them
/// off.
struct FindNavigatorState: Equatable {
    /// The app's presentation binding, from ``View/findNavigator(isPresented:)``.
    var isPresented: Binding<Bool>?

    /// Whether ``View/findDisabled(_:)`` is in force.
    var isFindDisabled = false

    /// Whether ``View/replaceDisabled(_:)`` is in force.
    var isReplaceDisabled = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isPresented?.wrappedValue == rhs.isPresented?.wrappedValue,
            (lhs.isPresented == nil) == (rhs.isPresented == nil),
            lhs.isFindDisabled == rhs.isFindDisabled
        else { return false }
        return lhs.isReplaceDisabled == rhs.isReplaceDisabled
    }
}

private struct FindNavigatorStateKey: EnvironmentKey {
    // Computed: a `Binding` is not `Sendable`, so the state cannot be a stored
    // global, and nothing is presented by default anyway.
    static var defaultValue: FindNavigatorState { FindNavigatorState() }
}

extension EnvironmentValues {
    /// The find modifiers' statements for the text editors below.
    var findNavigator: FindNavigatorState {
        get { self[FindNavigatorStateKey.self] }
        set { self[FindNavigatorStateKey.self] = newValue }
    }

    /// The status of the find navigator for views that support text editing —
    /// mirrors SwiftUI's `findContext`.
    ///
    /// `nil` where find is disabled. A text view of the app's own reads it to
    /// drive a find interface the same modifiers control.
    public var findContext: FindContext? {
        let state = findNavigator
        guard !state.isFindDisabled else { return nil }
        return FindContext(isPresented: state.isPresented, supportsReplace: !state.isReplaceDisabled)
    }
}

/// The status of the find navigator for views that support text editing —
/// mirrors SwiftUI's `FindContext`.
public struct FindContext {
    /// A binding controlling whether the find navigator is presented, or `nil`
    /// if no ``View/findNavigator(isPresented:)`` provided one.
    public var isPresented: Binding<Bool>?

    /// Whether the find navigators in this context support replacing.
    public var supportsReplace: Bool
}

// MARK: - The modifiers

extension View {
    /// Programmatically presents the find and replace interface for text
    /// editor views — mirrors SwiftUI's `findNavigator(isPresented:)`.
    ///
    /// A ``TextEditor`` in this view draws a find bar above its text while
    /// `isPresented` is `true`, and sets it back to `false` when the person
    /// closes the bar. Without this modifier, an editor's own Ctrl-F presents
    /// it, as ⌘F does on macOS.
    ///
    /// - Parameter isPresented: Whether the find interface is shown.
    /// - Returns: A view whose text editors present the interface with it.
    public func findNavigator(isPresented: Binding<Bool>) -> some View {
        // Closer to the editor than a `findDisabled(_:)`, it wins, as SwiftUI
        // documents the order mattering.
        transformEnvironment(\.findNavigator) {
            $0.isPresented = isPresented
            $0.isFindDisabled = false
        }
    }

    /// Prevents find and replace operations in a text editor — mirrors
    /// SwiftUI's `findDisabled(_:)`.
    ///
    /// Disabling find disables replace too, and keeps a
    /// ``findNavigator(isPresented:)`` further out from presenting the bar.
    ///
    /// - Parameter isDisabled: Whether find is disabled.
    /// - Returns: A view whose text editors cannot find.
    public func findDisabled(_ isDisabled: Bool = true) -> some View {
        transformEnvironment(\.findNavigator) { $0.isFindDisabled = isDisabled }
    }

    /// Prevents replace operations in a text editor — mirrors SwiftUI's
    /// `replaceDisabled(_:)`.
    ///
    /// The find bar then searches without a replace row.
    ///
    /// - Parameter isDisabled: Whether replace is disabled.
    /// - Returns: A view whose text editors cannot replace.
    public func replaceDisabled(_ isDisabled: Bool = true) -> some View {
        transformEnvironment(\.findNavigator) { $0.isReplaceDisabled = isDisabled }
    }
}
