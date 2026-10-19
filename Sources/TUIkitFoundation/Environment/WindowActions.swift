//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowActions.swift
//
//  SwiftUI's window actions — `\.openWindow`, `\.dismissWindow` — and
//  `\.supportsMultipleWindows`: what a view asks of the app's scenes, handed
//  to the run loop's scene presenter.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The Run Loop's Side

/// Where the window actions a view calls go: the running app's scene
/// presenter (TUIkitApp), which fills these in. An action read outside a
/// running app holds none, and does nothing.
///
/// A class, so that an action read on one frame reaches the presenter as it is
/// when it is called, and so that two actions are equal when they are the same
/// app's (``OpenWindowAction``'s equality): an environment value with no
/// equality turns every memo below it off.
@MainActor
package final class SceneActionHandler {
    /// Opens, or brings to the front, the window `target` names, and says
    /// whether a scene answered to it.
    package var openWindow: (_ target: WindowTarget) -> Bool = { _ in false }

    /// Closes the windows `dismissal` names.
    package var dismissWindow: (_ dismissal: WindowDismissal) -> Void = { _ in }

    /// Presents the app's `Settings` scene.
    package var openSettings: () -> Void = {}

    package init() {}
}

/// What an `openWindow` or a `dismissWindow` names: a scene by its
/// identifier, a value a window group presents, or both.
package struct WindowTarget {
    /// The scene's identifier, if the call named one.
    package let id: String?

    /// The value, if the call named one.
    package let value: AnyHashable?

    /// The value's type, which names the window group that presents such
    /// values (`WindowGroup(for:)`).
    package let valueType: Any.Type?

    package init(id: String?, value: AnyHashable? = nil, valueType: Any.Type? = nil) {
        self.id = id
        self.value = value
        self.valueType = valueType
    }
}

/// Which windows a `dismissWindow` closes.
package enum WindowDismissal {
    /// The window whose environment the action was read from, by its serial
    /// number (the presenter's).
    case current(Int)

    /// The windows `target` names.
    case target(WindowTarget)
}

// MARK: - Opening a Window

/// An action that presents a window — mirrors SwiftUI's `OpenWindowAction`.
///
/// Read it from the environment and call it with the identifier of a scene the
/// app declares, a value a window group presents, or both:
///
/// ```swift
/// @main
/// struct Mail: App {
///     var body: some Scene {
///         WindowGroup { MailViewer() }
///         Window("Activity", id: "activity") { ActivityView() }
///     }
/// }
///
/// struct ShowActivityButton: View {
///     @Environment(\.openWindow) private var openWindow
///
///     var body: some View {
///         Button("Show Activity") { openWindow(id: "activity") }
///     }
/// }
/// ```
///
/// A terminal shows one surface, so the window opens over the whole of it, in
/// front of the windows already open, and the window under it comes back when
/// it closes — the app's scene presenter's policy for one surface (refusal
/// review O9). A `Window` scene opens one window: opening it again brings that
/// window to the front. A `WindowGroup` opens a new window each time.
///
/// Equal to another when both reach the same app: the memos below a view that
/// reads it stay on.
public struct OpenWindowAction: Sendable, Equatable {
    /// Where the action goes, or `nil` outside a running app.
    private let handler: SceneActionHandler?

    /// The action that hands its calls to `handler`.
    package init(handler: SceneActionHandler?) {
        self.handler = handler
    }

    /// Opens a window that's associated with the specified identifier —
    /// mirrors SwiftUI's `callAsFunction(id:)`.
    ///
    /// Opens a `Window` scene's window, or brings it to the front where it is
    /// open already, or a new window of a `WindowGroup`. An identifier no scene
    /// declares opens nothing.
    ///
    /// - Parameter id: The identifier of the scene to present.
    @MainActor
    public func callAsFunction(id: String) {
        _ = handler?.openWindow(WindowTarget(id: id))
    }

    /// Opens a window defined by a window group that presents the type of the
    /// specified value — mirrors SwiftUI's `callAsFunction(value:)`.
    ///
    /// Where a window presenting an equal value is open, it is brought to the
    /// front; otherwise a new window presents the value.
    ///
    /// - Parameter value: The value to present.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(value: D) {
        _ = handler?.openWindow(WindowTarget(id: nil, value: AnyHashable(value), valueType: D.self))
    }

    /// Opens a window defined by the window group that presents the specified
    /// value type and that's associated with the specified identifier —
    /// mirrors SwiftUI's `callAsFunction(id:value:)`.
    ///
    /// - Parameters:
    ///   - id: The identifier of the scene to present.
    ///   - value: The value to present.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(id: String, value: D) {
        _ = handler?.openWindow(WindowTarget(id: id, value: AnyHashable(value), valueType: D.self))
    }

    /// Whether the two reach the same app, or are both outside one.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.handler === rhs.handler
    }
}

// MARK: - Dismissing a Window

/// An action that dismisses a window associated to a particular scene —
/// mirrors SwiftUI's `DismissWindowAction`.
///
/// ```swift
/// struct DismissActivityButton: View {
///     @Environment(\.dismissWindow) private var dismissWindow
///
///     var body: some View {
///         Button("Close Activity") { dismissWindow(id: "activity") }
///     }
/// }
/// ```
///
/// The window under the one dismissed comes back. Dismissing the last window
/// quits the app: a terminal app with no window open would show nothing, where
/// a macOS app can stay running with only its menu bar.
public struct DismissWindowAction: Sendable, Equatable {
    /// Where the action goes, or `nil` outside a running app.
    private let handler: SceneActionHandler?

    /// The serial number of the window whose environment this was read from,
    /// or `nil` outside a window.
    private let window: Int?

    /// The action that hands its calls to `handler`, dismissing `window` when
    /// called with nothing named.
    package init(handler: SceneActionHandler?, window: Int?) {
        self.handler = handler
        self.window = window
    }

    /// Dismisses the current window — mirrors SwiftUI's `callAsFunction()`.
    @MainActor
    public func callAsFunction() {
        guard let window else { return }
        handler?.dismissWindow(.current(window))
    }

    /// Dismisses the window that's associated with the specified identifier —
    /// mirrors SwiftUI's `callAsFunction(id:)`: every window of that scene
    /// that is open.
    ///
    /// - Parameter id: The identifier of the scene to dismiss.
    @MainActor
    public func callAsFunction(id: String) {
        handler?.dismissWindow(.target(WindowTarget(id: id)))
    }

    /// Dismisses the window defined by the window group that is presenting the
    /// specified value type — mirrors SwiftUI's `callAsFunction(value:)`.
    ///
    /// - Parameter value: The value the window to dismiss presents.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(value: D) {
        handler?.dismissWindow(.target(WindowTarget(id: nil, value: AnyHashable(value), valueType: D.self)))
    }

    /// Dismisses the window defined by the window group that is presenting the
    /// specified value type and that's associated with the specified
    /// identifier — mirrors SwiftUI's `callAsFunction(id:value:)`.
    ///
    /// - Parameters:
    ///   - id: The identifier of the scene to dismiss.
    ///   - value: The value the window to dismiss presents.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(id: String, value: D) {
        handler?.dismissWindow(.target(WindowTarget(id: id, value: AnyHashable(value), valueType: D.self)))
    }

    /// Whether the two reach the same app's same window.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.handler === rhs.handler && lhs.window == rhs.window
    }
}

// MARK: - Environment

private struct OpenWindowActionKey: EnvironmentKey {
    static let defaultValue = OpenWindowAction(handler: nil)
}

private struct DismissWindowActionKey: EnvironmentKey {
    static let defaultValue = DismissWindowAction(handler: nil, window: nil)
}

extension EnvironmentValues {
    /// A window presentation action stored in a view's environment — mirrors
    /// SwiftUI's `openWindow`.
    ///
    /// The running app puts its own here; read outside one, it opens nothing.
    public package(set) var openWindow: OpenWindowAction {
        get { self[OpenWindowActionKey.self] }
        set { self[OpenWindowActionKey.self] = newValue }
    }

    /// A window dismissal action stored in a view's environment — mirrors
    /// SwiftUI's `dismissWindow`.
    ///
    /// Called with nothing named, it dismisses the window the view is in.
    public package(set) var dismissWindow: DismissWindowAction {
        get { self[DismissWindowActionKey.self] }
        set { self[DismissWindowActionKey.self] = newValue }
    }

    /// Whether the app can open more than one window — mirrors SwiftUI's
    /// `supportsMultipleWindows`. `true`: ``openWindow`` opens one over the
    /// window in front, and each comes back as the one over it closes.
    ///
    /// A terminal app shows its windows one at a time, on the one surface it
    /// has, but it does open them, which is what this reports: SwiftUI's own
    /// example reads it to decide whether to offer an "Open New Window" button.
    /// See `Documentation/SwiftUI parity/Decisions/Several scenes on one surface (O9).md`,
    /// A-O9-1, the owner's to overrule.
    public var supportsMultipleWindows: Bool { true }
}

// MARK: - Sharing a Window

extension OpenWindowAction {
    /// Whether a window opened is to be shared with a sharing session —
    /// mirrors SwiftUI's `OpenWindowAction.SharingBehavior`.
    ///
    /// A terminal app has no sharing session to share a window with, so no
    /// window it opens is ever shared: ``requested`` opens it as it is, and
    /// ``required`` does not open it and throws, as SwiftUI documents for a
    /// window that could not be shared.
    public struct SharingBehavior: Sendable, Equatable {
        /// Whether the window opens only when it is shared.
        let isRequired: Bool

        /// The window is shared where there is a sharing session and the
        /// person agrees, and opened regardless.
        public static let requested = Self(isRequired: false)

        /// The window is opened only if it is shared.
        public static let required = Self(isRequired: true)
    }

    /// Opens a window that's associated with the specified identifier, using
    /// the specified sharing behavior — mirrors SwiftUI's
    /// `callAsFunction(id:sharingBehavior:)`.
    ///
    /// - Parameters:
    ///   - id: The identifier of the scene to present.
    ///   - sharingBehavior: Whether the window opens only if it is shared,
    ///     which here it never is.
    /// - Throws: Where `sharingBehavior` is ``SharingBehavior/required``, or no
    ///   scene has the identifier.
    @MainActor
    public func callAsFunction(id: String, sharingBehavior: SharingBehavior) async throws {
        try open(WindowTarget(id: id), sharingBehavior: sharingBehavior)
    }

    /// Opens a window defined by a window group that presents the type of the
    /// specified value, using the specified sharing behavior — mirrors
    /// SwiftUI's `callAsFunction(value:sharingBehavior:)`.
    ///
    /// - Parameters:
    ///   - value: The value to present.
    ///   - sharingBehavior: Whether the window opens only if it is shared,
    ///     which here it never is.
    /// - Throws: Where `sharingBehavior` is ``SharingBehavior/required``, or no
    ///   window group presents values of the type.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(
        value: D, sharingBehavior: SharingBehavior
    ) async throws {
        try open(WindowTarget(id: nil, value: AnyHashable(value), valueType: D.self), sharingBehavior: sharingBehavior)
    }

    /// Opens a window defined by the window group that presents the specified
    /// value type and that's associated with the specified identifier, using
    /// the specified sharing behavior — mirrors SwiftUI's
    /// `callAsFunction(id:value:sharingBehavior:)`.
    ///
    /// - Parameters:
    ///   - id: The identifier of the scene to present.
    ///   - value: The value to present.
    ///   - sharingBehavior: Whether the window opens only if it is shared,
    ///     which here it never is.
    /// - Throws: Where `sharingBehavior` is ``SharingBehavior/required``, or no
    ///   window group answers to the identifier and the value's type.
    @MainActor
    public func callAsFunction<D: Decodable & Encodable & Hashable>(
        id: String, value: D, sharingBehavior: SharingBehavior
    ) async throws {
        try open(WindowTarget(id: id, value: AnyHashable(value), valueType: D.self), sharingBehavior: sharingBehavior)
    }

    /// Opens `target` unless sharing is required, which no window here can be.
    @MainActor
    private func open(_ target: WindowTarget, sharingBehavior: SharingBehavior) throws {
        guard !sharingBehavior.isRequired else { throw WindowOpeningError.notShared }
        guard handler?.openWindow(target) == true else { throw WindowOpeningError.noScene }
    }
}

/// Why an `OpenWindowAction` that throws did not open its window.
enum WindowOpeningError: Error {
    /// The window was to be opened only if shared, and a terminal app has no
    /// sharing session.
    case notShared

    /// No scene the app declares answers to what the action named, or the
    /// action was not read from a running app's environment.
    case noScene
}
