//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlertActions.swift
//
//  How a dialog finds its buttons in the actions builder the app wrote.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - An action

/// One of a dialog's actions: its button, and what the modifiers written on
/// the button say that the dialog keeps.
///
/// A dialog draws each action's button itself, so the modifiers written on one
/// are looked through to find it — and a macOS alert, read back on 15.8, keeps
/// two of them (`Tools/SwiftUIProbes/Menu items and alert buttons/alert.out`):
/// `.disabled`, which disables its button, and
/// `.keyboardShortcut`, which gives its button that key equivalent — Return for
/// `.defaultAction`, Escape for `.cancelAction`. `.help`, `.tint` and
/// `.foregroundStyle` show nothing there, and are left out here too.
@MainActor
struct AlertAction {
    /// The button, disabled where a modifier written on it said so.
    let button: Button

    /// The keyboard shortcut written on the button — the innermost, as the
    /// control would claim it — put back on it where the dialog draws it.
    let shortcut: KeyboardShortcut?

    init(_ button: Button, shortcut: KeyboardShortcut? = nil) {
        self.button = button
        self.shortcut = shortcut
    }

    /// The button's role.
    var role: ButtonRole? { button.role }

    /// Whether the action can be chosen.
    var isDisabled: Bool { button.isDisabled }

    /// The view the dialog draws: the button, carrying its shortcut.
    var view: some View { button.keyboardShortcut(shortcut) }

    /// This action, running `action` instead of its own.
    func running(_ action: @escaping () -> Void) -> Self {
        Self(Button(button, action: action), shortcut: shortcut)
    }

    /// This action as the modifiers outside it say: disabled where one
    /// disabled it, which nothing further in can undo, and carrying their
    /// shortcut where it states none of its own.
    func modified(disabled: Bool, shortcut outer: KeyboardShortcut?) -> Self {
        let button = disabled && !button.isDisabled ? button.disabled(true) : button
        return Self(button, shortcut: shortcut ?? outer)
    }
}

@MainActor
extension [AlertAction] {
    /// The action Escape answers the dialog with: the `.cancel`-role one, or
    /// failing that one carrying `.keyboardShortcut(.cancelAction)`, as a macOS
    /// alert gives that button Escape (read back on 15.8) — and neither when it
    /// is disabled, since it cannot be chosen.
    var escapeAction: AlertAction? {
        first { $0.role == .cancel && !$0.isDisabled }
            ?? first { $0.shortcut == .cancelAction && !$0.isDisabled }
    }
}

// MARK: - Button Provider Protocol

/// A view that is a dialog's actions, as given: a `Button`, or the actions
/// the dialog presenters wrap round the app's to add their own.
@MainActor
protocol ButtonProvider {
    /// The actions this view is, resolved in `context`.
    func extractActions(in context: RenderContext) -> [AlertAction]
}

/// Identity tag for resolving a dialog's actions, a step in from the dialog,
/// so a view of the app's own among them keeps its `@State` apart.
private enum AlertActionsID {}

/// The actions an alert's `actions` builder produced, in declaration order.
///
/// Resolved as ``Group/init(subviews:transform:)`` resolves members
/// (`subviewGroups(of:in:)`), so a button is found wherever it is written —
/// in an `if`/`else`, a `Group`, a `ForEach`, a view of the app's own — and
/// behind the modifiers written on it, as SwiftUI keeps "a Button … wherever in
/// the builder it was written". Of those modifiers the dialog keeps what a
/// macOS alert keeps, `.disabled` and `.keyboardShortcut` (``AlertAction``):
/// it draws the button itself, so the others are looked through and left. A
/// member that is no button is left out, as SwiftUI leaves out what an alert
/// cannot show.
///
/// Shared by ``_AlertPanelCore``, which lays them out, and
/// ``AlertPresentationModifier``, which needs the one that answers Escape.
@MainActor
func alertActions(from view: some View, in context: RenderContext) -> [AlertAction] {
    if let provider = view as? ButtonProvider { return provider.extractActions(in: context) }
    let scope = context.withChildIdentity(type: AlertActionsID.self)
    var actions: [AlertAction] = []
    for group in subviewGroups(of: view, in: scope) {
        for member in group.members {
            var current = member.memberView
            // What the modifiers passed on the way in said, outermost first.
            var disabled = false
            var shortcut: KeyboardShortcut?
            while true {
                if let provider = current as? ButtonProvider {
                    actions += provider.extractActions(in: context).map {
                        $0.modified(disabled: disabled, shortcut: shortcut)
                    }
                    break
                }
                if let disabling = current as? any ContentDisabling, disabling.disablesContent {
                    disabled = true
                }
                // Walking in, so a later one is nearer the button — the one it
                // would claim. A `nil` leaves the one further out in force.
                if let binding = current as? any KeyboardShortcutBinding, let bound = binding.boundShortcut {
                    shortcut = bound
                }
                if let wrapper = current as? any SingleContentWrapper {
                    current = wrapper.wrappedContent
                } else if let row = current as? any _ValueMemoWrapping {
                    // A `ForEach` row of an equatable element, memoized.
                    current = row.memoizedContent
                } else {
                    break
                }
            }
        }
    }
    return actions
}

// MARK: - ButtonProvider Conformances

extension Button: ButtonProvider {
    func extractActions(in context: RenderContext) -> [AlertAction] {
        [AlertAction(self)]
    }
}
