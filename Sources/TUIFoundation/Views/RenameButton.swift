//  🖥️ TUI — A Terminal UI framework for Swift
//  RenameButton.swift
//
//  SwiftUI's standard rename interaction: `RenameButton` performs whatever
//  `renameAction(_:)` put in the environment, and is disabled where nothing
//  did.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The action

/// An action that activates a standard rename interaction.
///
/// Use the ``View/renameAction(_:)-(()->Void)`` modifier to configure the
/// rename action in the environment; a ``RenameButton`` performs it.
///
/// Not `Sendable`, as SwiftUI's is explicitly not, and it holds the caller's
/// closure as SwiftUI's signature takes it. Not `Equatable` — a closure has no
/// equality — so, as with any
/// environment value that is not, the render memos below the modifier compare
/// it as changed every frame rather than serve a buffer holding the old one.
public struct RenameAction {
    /// What a rename does.
    let action: () -> Void

    /// Triggers the standard rename action provided through the environment.
    @MainActor
    public func callAsFunction() {
        action()
    }
}

private struct RenameActionKey: EnvironmentKey {
    static var defaultValue: RenameAction? { nil }
}

extension EnvironmentValues {
    /// An action that activates the standard rename interaction, or `nil`
    /// where no ``View/renameAction(_:)-(()->Void)`` has set one.
    public var rename: RenameAction? {
        self[RenameActionKey.self]
    }

    /// The writable side of ``rename``: SwiftUI's is get-only, and set through
    /// the modifier.
    var renameAction: RenameAction? {
        get { self[RenameActionKey.self] }
        set { self[RenameActionKey.self] = newValue }
    }
}

extension View {
    /// Sets a closure to run for the rename action.
    ///
    /// ```swift
    /// TextField("Name", text: $item.name)
    ///     .focused($isFocused)
    ///     .contextMenu { RenameButton() }
    ///     .renameAction { isFocused = true }
    /// ```
    ///
    /// - Parameter action: The closure to run when the rename button is
    ///   activated.
    /// - Returns: A view whose rename buttons perform `action`.
    public func renameAction(_ action: @escaping () -> Void) -> some View {
        environment(\.renameAction, RenameAction(action: action))
    }

    /// Sets the rename action in the environment to move the focus to the
    /// field `isFocused` is bound to.
    ///
    /// - Parameter isFocused: The focus state the rename sets to `true`.
    /// - Returns: A view whose rename buttons focus that field.
    public func renameAction(_ isFocused: FocusState<Bool>.Binding) -> some View {
        renameAction { isFocused.wrappedValue = true }
    }
}

// MARK: - The button

/// A button that triggers a standard rename action.
///
/// A rename button receives its action from the environment — set it with
/// ``View/renameAction(_:)-(()->Void)`` — and is disabled where none was set.
///
/// ```swift
/// Text(item.name)
///     .contextMenu {
///         RenameButton()
///     }
///     .renameAction { isRenaming = true }
/// ```
public struct RenameButton<Label: View>: View {
    let label: Label

    @Environment(\.rename) private var rename

    public var body: some View {
        Button {
            rename?()
        } label: {
            label
        }
        .disabled(rename == nil)
    }
}

extension RenameButton where Label == TUIFoundation.Label<Text, Image> {
    /// Creates a rename button, titled "Rename" in the current language.
    public init() {
        self.label = TUIFoundation.Label {
            Text(localized: LocalizationKey.Button.rename)
        } icon: {
            Image(systemName: "pencil")
        }
    }
}

// MARK: - Environment without reflection

extension RenameButton: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _rename.resolveEnvironment(environment)
    }
}
