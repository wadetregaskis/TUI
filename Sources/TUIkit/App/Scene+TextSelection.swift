//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+TextSelection.swift
//
//  The scene's settings for TUIkit's own selection of what is on the screen.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Public Modifier

extension Scene {
    /// Copies a selection made with the mouse as soon as the drag that made it
    /// ends, as tmux and iTerm2 do by default — a TUIkit setting with no
    /// SwiftUI counterpart.
    ///
    /// By default a selection is copied only when asked: by the app's ⌘C,
    /// which a terminal delivers as Ctrl-C (⌘C itself never reaches an app —
    /// the terminal takes it for its own selection, empty here), as on a Mac,
    /// where an accidental drag leaves the clipboard alone. With this, every
    /// selection the user drags or double-clicks goes to the clipboard at the
    /// release, and the status bar says what became of it. See
    /// `Documentation/Terminal-compatibility.md`, "OSC 52 clipboard writes",
    /// for where a copy goes.
    ///
    /// ```swift
    /// WindowGroup { LogView() }
    ///     .textSelectionCopiesOnRelease()
    /// ```
    ///
    /// - Parameter copies: Whether a selection is copied at the release.
    /// - Returns: A scene that copies its selections at the release.
    public func textSelectionCopiesOnRelease(_ copies: Bool = true) -> some Scene {
        _EnvironmentScene(content: self) { $0.textSelectionCopiesOnRelease = copies }
    }
}

// MARK: - Environment

private struct TextSelectionCopiesOnReleaseKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a selection made with the mouse is copied at the release — the
    /// scene's ``Scene/textSelectionCopiesOnRelease(_:)``, read by the run
    /// loop from the scene's root environment.
    var textSelectionCopiesOnRelease: Bool {
        get { self[TextSelectionCopiesOnReleaseKey.self] }
        set { self[TextSelectionCopiesOnReleaseKey.self] = newValue }
    }
}

// MARK: - Adopting the scene's settings

extension ScreenSelection {
    /// Takes this frame's scene settings: whether a release copies, and the key
    /// that copies — the app's ⌘C, resolved through the scene's `commandKey`.
    /// Resolved again only when the binding changes.
    func adopt(commandKey: CommandKeyBinding, copiesOnRelease: Bool) {
        self.copiesOnRelease = copiesOnRelease
        guard commandKey != adoptedCommandKey else { return }
        adoptedCommandKey = commandKey
        copyTrigger = KeyboardShortcut("c", modifiers: .command).resolved(commandKey: commandKey)?.trigger
    }

    /// What a key does while something is selected: the copy key copies, and
    /// keeps the selection, as a Mac does; a bare Escape clears it. `nil` for
    /// any other key, which goes on through the chain.
    func handleKey(_ event: KeyEvent) -> Bool? {
        // While its menu is open the keys are the menu's: Escape closes it,
        // Return chooses.
        guard hasSelection, menuAnchor == nil else { return nil }
        if let copyTrigger, KeyboardShortcut.trigger(for: event) == copyTrigger {
            return copySelection()
        }
        if event.key == .escape, !event.ctrl, !event.alt {
            clear()
            return true
        }
        return nil
    }
}
