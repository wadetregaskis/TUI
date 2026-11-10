//  🖥️ TUI — A Terminal UI framework for Swift
//  StyleEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Style cascade environment

/// Environment key carrying the scoped style cascade (see ``StyleCascade``).
///
/// Container-level style modifiers (`.bold()`, `.style(_:_:)`, …) append to it;
/// views resolve their effective attributes from `context.environment.styleCascade`.
private struct StyleCascadeKey: EnvironmentKey {
    static let defaultValue = StyleCascade()
}

extension EnvironmentValues {
    /// The scoped style cascade contributed by ancestor style modifiers.
    public var styleCascade: StyleCascade {
        get { self[StyleCascadeKey.self] }
        set { self[StyleCascadeKey.self] = newValue }
    }

    /// The case transform text in this subtree is drawn with — SwiftUI's
    /// `\.textCase`, the value ``View/textCase(_:)`` writes.
    ///
    /// Read from the style cascade, where the modifier keeps it, as the
    /// transform a plain `Text` resolves to; writing it is the modifier, so
    /// `nil` clears a transform set further out rather than saying nothing.
    public var textCase: TextCase? {
        get { styleCascade.resolve(for: [.all, .text]).effectiveTextCase }
        set { styleCascade = styleCascade.appending(.text, StyleAttributes(textCase: .some(newValue))) }
    }
}

// MARK: - Chrome role

/// Environment key marking the structural chrome role a subtree renders (e.g. a
/// `Section` header). `Text` reads it to apply the role's default attributes and
/// to match `.chrome(role)` style-cascade entries.
private struct ChromeRoleKey: EnvironmentKey {
    static let defaultValue: ChromeRole? = nil
}

extension EnvironmentValues {
    /// The chrome role of the current subtree, if any (set by `Section` around
    /// its header/footer). Drives chrome text styling (see ``ChromeRole``).
    public var chromeRole: ChromeRole? {
        get { self[ChromeRoleKey.self] }
        set { self[ChromeRoleKey.self] = newValue }
    }
}

// MARK: - Control identity

/// The environment key marking that a subtree renders a control's label, so
/// its `Text` resolves `.control(kind)` style entries. Controls whose labels
/// are rendered via `Text` (Toggle, Picker, …) set it around the label;
/// controls that render their label procedurally (Button) resolve the same
/// scopes directly.
private struct ControlKindKey: EnvironmentKey {
    static let defaultValue: ControlKind? = nil
}

extension EnvironmentValues {
    /// The control kind whose label the current subtree renders, if any.
    public var controlKind: ControlKind? {
        get { self[ControlKindKey.self] }
        set { self[ControlKindKey.self] = newValue }
    }
}
