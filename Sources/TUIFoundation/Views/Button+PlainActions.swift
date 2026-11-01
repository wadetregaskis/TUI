//  🖥️ TUI — A Terminal UI framework for Swift
//  Button+PlainActions.swift
//
//  A button's action given as a plain closure value, and how a @MainActor one
//  is kept.
//
//  Created by Wade Tregaskis
//  License: MIT

/// `action`, as the plain closure a ``Button`` keeps.
///
/// A cast rather than a conversion only because a nonisolated initializer may
/// not write the conversion. `@MainActor` is no part of a synchronous closure's
/// representation: in a `@MainActor` context the compiler converts one with
/// `convert_function`, no thunk and no allocation (read in the SIL of Swift
/// 6.2.4, 6.3.3 and 6.4.0), and this is the same two words.
///
/// It is sound because the result is only ever called on the main actor:
/// ``Button``'s field is private, and ``Button/action`` is `@MainActor`.
///
/// It is not a wrapping closure, which would allocate per button per body and
/// give the memos, which hash a button's bytes, a new address each time. It is
/// not a second field, which would cost every button 16 bytes
/// (`ControlLayoutPaddingTests` pins 121).
func mainActorAction(_ action: @escaping @MainActor () -> Void) -> () -> Void {
    unsafeBitCast(action, to: (() -> Void).self)
}

// Each `Button` initializer taking a `@MainActor` action has one here taking a
// plain closure, so that `let action: () -> Void; Button("x", action: action)`
// compiles. SwiftUI's single overload takes both through `@preconcurrency`,
// which also turns real races into warnings; here region isolation refuses them.
// Disfavored, so that a closure literal is `@MainActor` wherever it is written.
// Hidden from the documentation: it adds nothing to read, and its twin is the
// one to link to.
//
// A title that is a `String` has none of these: see `Button(_:action:)` in
// `Coming from SwiftUI`. A disfavored plain overload there would also win a
// string LITERAL title over the key's, drawing it as written instead of looking
// it up, because a literal prefers `String` when the two are otherwise tied.
extension Button {
    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(storedAction: action, titleKey: titleKey, role: nil)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(storedAction: action, titleKey: titleKey, role: role)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init(role: ButtonRole, action: @escaping () -> Void) {
        self.init(storedAction: action, role: role)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(storedAction: action, role: nil, label: label)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init<Label: View>(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(storedAction: action, role: role, label: label)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(titleKey, systemImage: systemImage, role: nil, action: action)
    }

    /// As the initializer of the same shape taking a `@MainActor` action, for a
    /// closure value that is not one.
    @_documentation(visibility: private)
    @_disfavoredOverload
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(storedAction: action, role: role) {
            Label(titleKey, systemImage: systemImage)
        }
    }
}
