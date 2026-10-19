//  🖥️ TUIkit — Terminal UI Kit for Swift
//  WindowVisibilityToggle.swift
//
//  SwiftUI's `WindowVisibilityToggle`: a button that shows or hides a
//  `Window` scene's window.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Toggle

/// A specialized button for toggling the visibility of a window — mirrors
/// SwiftUI's `WindowVisibilityToggle`.
///
/// ```swift
/// .commands {
///     CommandGroup(before: .sidebar) {
///         WindowVisibilityToggle(windowID: "photo-library")
///             .keyboardShortcut("l", modifiers: [.command, .shift])
///     }
/// }
/// ```
///
/// On one surface a window is shown while it is in front (refusal review O9,
/// ruled (b)): the toggle reads "Hide *Title*" then, and closes the window;
/// otherwise it reads "Show *Title*", and opens the window or brings it to the
/// front. An identifier no `Window` scene has leaves the toggle disabled,
/// there being nothing for it to do. Decisions O9, B-O9-11.
public struct WindowVisibilityToggle<Label: View>: View {
    /// The `Window` scene's identifier.
    let windowID: String

    /// The toggle's label.
    let label: Label

    @Environment(\.scenePresenter) private var presenter

    public var body: some View {
        let presenter = presenter
        let windowID = windowID
        Button {
            presenter?.toggleWindow(windowID)
        } label: {
            label
        }
        .disabled(presenter?.declaresWindowScene(windowID) != true)
    }
}

extension WindowVisibilityToggle where Label == DefaultWindowVisibilityToggleLabel {
    /// Creates a window visibility toggle to alter the visibility of a
    /// specific window — mirrors SwiftUI's `init(windowID:)`.
    ///
    /// - Parameter windowID: The `id` of the `Window` scene whose window it
    ///   toggles. If no `Window` scene has it, the toggle is disabled.
    public init(windowID: String) {
        self.windowID = windowID
        self.label = DefaultWindowVisibilityToggleLabel(windowID: windowID)
    }
}

// MARK: - The Default Label

/// The default label of a window visibility toggle — mirrors SwiftUI's
/// `DefaultWindowVisibilityToggleLabel`: "Show *Title*" or "Hide *Title*",
/// the window's title, in the current language.
///
/// You don't make one: ``WindowVisibilityToggle``'s `init(windowID:)` does.
public struct DefaultWindowVisibilityToggleLabel: View {
    /// The `Window` scene's identifier.
    let windowID: String

    @Environment(\.scenePresenter) private var presenter

    /// Made by ``WindowVisibilityToggle``'s `init(windowID:)` only.
    init(windowID: String) {
        self.windowID = windowID
    }

    public var body: some View {
        let isShown = presenter?.isShowingWindow(windowID) == true
        let title = presenter?.listedScenes.first { $0.id == windowID }?.title ?? windowID
        let key = isShown ? LocalizationKey.Menu.hideWindow : LocalizationKey.Menu.showWindow
        Text(LocalizedStringKey.substituting([title], into: LocalizationService.shared.string(for: key)))
    }
}

// MARK: - Environment without reflection

extension WindowVisibilityToggle: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _presenter.resolveEnvironment(environment)
    }
}

extension DefaultWindowVisibilityToggleLabel: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _presenter.resolveEnvironment(environment)
    }
}

// MARK: - The Presenter's Side

extension ScenePresenter {
    /// Whether the app declares a `Window` scene with identifier `id`.
    package func declaresWindowScene(_ id: String) -> Bool {
        entries.contains { $0.window.opensOneWindow && $0.window.sceneID == id }
    }

    /// Whether the `Window` scene `id`'s window is the one in front.
    package func isShowingWindow(_ id: String) -> Bool {
        guard let front, let entry = entry(of: front) else { return false }
        return entry.window.opensOneWindow && entry.window.sceneID == id
    }

    /// Hides the `Window` scene `id`'s window if it is in front — closes it —
    /// and otherwise shows it: opens it, or brings it to the front.
    package func toggleWindow(_ id: String) {
        guard declaresWindowScene(id) else { return }
        if isShowingWindow(id), let front {
            close([front.serial])
        } else {
            open(WindowTarget(id: id))
        }
    }
}
