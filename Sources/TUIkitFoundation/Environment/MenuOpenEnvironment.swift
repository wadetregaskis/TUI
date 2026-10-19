//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuOpenEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - onMenuOpen

/// The action a subtree's menus run when they open — see
/// ``View/onMenuOpen(_:)``.
///
/// An object the modifier keeps in `@State` and refreshes with the app's closure
/// each time its body runs, compared by identity — the shape ``DismissAction``'s
/// box and the searchable's `SearchDismissal` take, for their reason: an
/// environment value that cannot be compared turns every memo off beneath it,
/// and a closure cannot be compared. As a struct around the closure it was, and
/// nothing under an `.onMenuOpen` — the menu it watches, the page it wraps — was
/// ever stored or served. Equal-by-fiat would have been worse: a buffer served
/// from a memo replays the handlers captured when it was stored, and a stored
/// closure would be the one the app had then. Through one object, a menu opened
/// from a served buffer runs the closure the app gave most recently.
///
/// `@unchecked Sendable` on the same terms as every other action closure here:
/// it is created and invoked only on the render loop's single thread.
/// `@usableFromInline`: the type of an `@inlinable` environment accessor (module split step A3).
@usableFromInline
package final class MenuOpenAction: Equatable, @unchecked Sendable {
    /// What opening a menu runs: the closure the modifier's body was given last.
    var action: () -> Void

    init(_ action: @escaping () -> Void = {}) {
        self.action = action
    }

    package func callAsFunction() { action() }

    @usableFromInline
    nonisolated package static func == (lhs: MenuOpenAction, rhs: MenuOpenAction) -> Bool { lhs === rhs }
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct MenuOpenKey: EnvironmentKey {
    @usableFromInline static let defaultValue: MenuOpenAction? = nil
}

extension EnvironmentValues {
    /// What to run when a pop-up menu in this subtree opens. `nil` — do
    /// nothing — everywhere it has not been set.
    @inlinable
    package var menuOpenAction: MenuOpenAction? {
        get { self[MenuOpenKey.self] }
        set { self[MenuOpenKey.self] = newValue }
    }
}

extension View {
    /// Runs `action` each time a pop-up menu in this subtree opens: a `Menu`'s
    /// items appearing, or a ``View/contextMenu(menuItems:)``
    /// popping up.
    ///
    /// The use it exists for is clearing whatever the LAST choice from that menu
    /// left on screen, so that choosing the same item again reads as a new
    /// choice rather than as nothing having happened:
    ///
    /// ```swift
    /// Menu("Actions") {
    ///     Button("Rename") { lastAction = "Rename" }
    ///     Button("Duplicate") { lastAction = "Duplicate" }
    /// }
    /// .onMenuOpen { lastAction = "—" }
    /// ```
    ///
    /// TUIkit-specific: SwiftUI has no equivalent (its menus are system-drawn,
    /// and their open moment is not the app's to observe).
    ///
    /// It fires on the OPEN, never on the close, and never from a render — so it
    /// is safe to change state from, and it runs exactly once per opening,
    /// however the menu was opened (click, Return, or <kbd>Shift</kbd>+<kbd>F10</kbd>).
    ///
    /// - Parameter action: Run as the menu opens.
    public func onMenuOpen(_ action: @escaping () -> Void) -> some View {
        _MenuOpenModifier(content: self, action: action)
    }
}

/// ``View/onMenuOpen(_:)``: the app's closure, handed to the subtree through
/// one ``MenuOpenAction`` for the modifier's life.
private struct _MenuOpenModifier<Content: View>: View {
    let content: Content
    let action: () -> Void

    /// The object the subtree's menus call, refreshed below.
    @State private var opening = MenuOpenAction()

    var body: some View {
        // A write to the object, not to the state: the box stays the one the
        // environment compared equal last frame, and what it runs is now this
        // body's closure.
        opening.action = action
        return content.environment(\.menuOpenAction, opening)
    }
}
