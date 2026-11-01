//  🖥️ TUI — A Terminal UI framework for Swift
//  DismissAction.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore

// MARK: - Dismiss Action

/// An action that exits the application's run loop, mirroring SwiftUI's
/// `DismissAction`.
///
/// SwiftUI's `@Environment(\.dismiss)` dismisses whatever presented the view
/// that reads it. A TUI app has one top-level scene that fills the whole
/// terminal, so at the top level dismissing is equivalent to quitting: the run
/// loop falls out naturally, `AppRunner` restores the terminal, and
/// `App.main()` returns. Unlike calling `exit(0)`, this lets normal Swift
/// cleanup run.
///
/// Anywhere *inside* something dismissable it means what SwiftUI means, because
/// each of those installs its own action into the environment of what it
/// presents: a ``NavigationStack``'s pushed screen goes back one screen, and a
/// `sheet`, `modal`, `fullScreenCover`, `popover`, `alert` or
/// `confirmationDialog` closes — the same act as that presentation's Escape
/// route, so an `onDismiss` runs for either. The same `dismiss()` call
/// therefore does the right thing wherever it is written, and the exit-the-app
/// meaning above is only what is left when nothing encloses the view.
///
/// - Important: That fallback is why installing the action is not optional. A
///   presentation that forgets leaves its content holding the top-level
///   meaning, and `Button("Done") { dismiss() }` — the shape SwiftUI's own
///   documentation teaches — quits the program instead of closing the sheet.
///   `PresentationDismissTests` pins every presentation against that.
///
/// # Example
///
/// ```swift
/// struct ContentView: View {
///     @Environment(\.dismiss) private var dismiss
///
///     var body: some View {
///         Button("Quit") { dismiss() }
///     }
/// }
/// ```
///
/// ## Equality
///
/// Two actions are equal when they are the same action: the same `Box`,
/// compared by identity, as `dismissSearch`'s is. A closure has no equality,
/// and an environment value with none turns every memo below it off — so a
/// view that writes an action for its content keeps one box for its life
/// (`@State`) and refreshes what the box does each time it renders. The
/// action written is then equal from frame to frame, the memos below stay
/// on, and an action read on an earlier frame does what dismissing means now.
public struct DismissAction: Sendable, Equatable {
    /// What dismissing does here, or `nil` for the top-level meaning (exit
    /// the app whose work calls it).
    ///
    /// A stored closure rather than a subclass or a flag, because the set of
    /// things that can present a view is open-ended: whatever presents one
    /// supplies the action that undoes it — boxed, so the action has an
    /// identity to compare.
    private let box: Box?

    /// What a dismiss action runs, by reference: the identity two actions are
    /// compared by, and a place to keep one action across renders while what
    /// it does is brought up to date.
    ///
    /// Isolated to the main actor, where `action` is written, by a view's
    /// render, and read, by ``DismissAction/callAsFunction()``.
    @MainActor
    package final class Box {
        package var action: @MainActor @Sendable () -> Void { get { _action } set { _action = newValue } }

        /// ``action``'s storage: private, under the `package` accessor
        /// (CONTRIBUTING.md, "Crossing a module boundary").
        private var _action: @MainActor @Sendable () -> Void

        nonisolated package init(_ action: @escaping @MainActor @Sendable () -> Void = {}) {
            self._action = action
        }
    }

    /// Creates a dismiss action that exits the run loop of the app whose work
    /// calls it — its event handler, or a task it started.
    ///
    /// An app's views find a top-level action at `\.dismiss` that names their
    /// app, which its run loop puts there (`TUIContext.exitAction`), so the
    /// action exits that app wherever it is called from. This one names no
    /// app: called on no app's task — on a queue of a framework's own — it
    /// does nothing.
    public init() {
        self.box = nil
    }

    /// Creates a dismiss action that runs `action` — for a presenting view to
    /// put into the environment of what it presents.
    ///
    /// Each call is a new action, unequal to every other; a view that writes
    /// one on every render and wants the memos below it kept writes one box's
    /// instead (`init(box:)`).
    public init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.box = Box(action)
    }

    /// The action `box` runs, equal to every other made from it.
    package init(box: Box) {
        self.box = box
    }

    /// Triggers the action. Equivalent to writing `dismiss()`.
    @MainActor
    public func callAsFunction() {
        if let box {
            box.action()
        } else {
            AmbientApp.renderState?.requestExit()
        }
    }

    /// Whether the two are the same action: the same box, or both the
    /// top-level one that names no app.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.box === rhs.box
    }
}

// MARK: - Environment Key

/// Environment key for the dismiss action.
private struct DismissActionKey: EnvironmentKey {
    static let defaultValue = DismissAction()
}

extension EnvironmentValues {
    /// An action that exits the application's run loop.
    ///
    /// Read this with `@Environment(\.dismiss)` and call it like a function:
    ///
    /// ```swift
    /// @Environment(\.dismiss) private var dismiss
    /// // ...
    /// dismiss()
    /// ```
    ///
    /// The call returns immediately; the run loop notices the request on its
    /// next iteration and shuts down cleanly. The terminal is restored to
    /// its prior state before `App.main()` returns.
    ///
    /// At the top of an app this is the app's own exit action, which its run
    /// loop puts in every frame's environment, so it exits that app — and no
    /// other in the process — wherever it is called from.
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }

    /// Whether this view is inside something that was PRESENTED — a sheet,
    /// modal, full-screen cover, popover, alert or confirmation dialog.
    ///
    /// SwiftUI's `\.isPresented`, and the read-only companion to
    /// ``EnvironmentValues/dismiss``: the same presentations that publish a
    /// dismissal publish this, so a view can tell whether calling `dismiss()`
    /// will close something or quit the application.
    ///
    /// ```swift
    /// @Environment(\.isPresented) private var isPresented
    ///
    /// // A footer that only makes sense in a sheet.
    /// if isPresented { Button("Done") { dismiss() } }
    /// ```
    ///
    /// A pushed ``NavigationStack`` screen reports `false`, as it does in
    /// SwiftUI: it was navigated to, not presented.
    public package(set) var isPresented: Bool {
        get { self[IsPresentedKey.self] }
        set { self[IsPresentedKey.self] = newValue }
    }
}

/// Environment key for ``EnvironmentValues/isPresented``.
private struct IsPresentedKey: EnvironmentKey {
    static let defaultValue = false
}
