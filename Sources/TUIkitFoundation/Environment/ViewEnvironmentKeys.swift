//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewEnvironmentKeys.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Badge Environment Key

/// Environment key for badge values.
private struct BadgeKey: EnvironmentKey {
    static let defaultValue: BadgeValue? = nil
}

extension EnvironmentValues {
    /// The current badge value.
    ///
    /// Used to display decorative badges on list rows or other views.
    /// Set via `.badge()` modifier on views.
    var badgeValue: BadgeValue? {
        get { self[BadgeKey.self] }
        set { self[BadgeKey.self] = newValue }
    }
}

// MARK: - Terminal Height Environment Key

/// Environment key for the terminal's total height in rows.
private struct TerminalHeightKey: EnvironmentKey {
    static let defaultValue: Int = 24
}

/// Environment key for the terminal's total width in columns.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct TerminalWidthKey: EnvironmentKey {
    @usableFromInline static let defaultValue: Int = 80
}

/// Environment key for the height of the content area available to overlays —
/// the screen minus the app header and the status bar.
private struct OverlayContentHeightKey: EnvironmentKey {
    static let defaultValue: Int = 24
}

extension EnvironmentValues {
    /// The terminal's total height in rows, published once at the render root.
    ///
    /// Unlike a context's `availableHeight` — which a ``ScrollView`` inflates to a
    /// tall measure budget — this stays the true screen height however deep the
    /// reader sits, letting an overlay (e.g. a ``Picker`` drop-down) size itself to
    /// the visible area. Defaults to a conservative 24 when no render loop has set
    /// it (e.g. in isolated tests).
    ///
    /// Public so an app can lay out responsively against the real screen size —
    /// e.g. switch a row of panels to a column when the terminal is short. It is
    /// published once per frame at the render root, so it is identical across a
    /// view's measure and render passes (branching on it never oscillates).
    public var terminalHeight: Int {
        get { self[TerminalHeightKey.self] }
        set { self[TerminalHeightKey.self] = newValue }
    }

    /// The terminal's total width in columns, published once at the render root.
    ///
    /// Like ``terminalHeight``, this is the true screen width however deep the
    /// reader sits — unlike a context's `availableWidth`, which is only whatever a
    /// leaf was offered. A screen-level overlay (e.g. a centred modal) renders
    /// against it so it isn't clipped to its attachment's local area. Defaults to 80.
    ///
    /// Public so an app can lay out responsively against the real screen width —
    /// e.g. place two panels side by side only when there is room, and stack
    /// them otherwise. It is published once per frame at the render root, so it
    /// is identical across a view's measure and render passes (branching on it
    /// never oscillates, unlike a context's `availableWidth`).
    @inlinable
    public var terminalWidth: Int {
        get { self[TerminalWidthKey.self] }
        set { self[TerminalWidthKey.self] = newValue }
    }

    /// The height (in rows) of the content area that overlays composite into —
    /// the screen height minus the app header and status bar. Published once at
    /// the render root, alongside ``terminalHeight``.
    ///
    /// An anchored overlay (e.g. a ``Picker`` drop-down) must size itself to this,
    /// **not** ``terminalHeight``: the compositor clamps overlays to this area (so
    /// they never overlap the status bar), so a drop-down sized to the full screen
    /// height would have its bottom border and last rows shaved off — reading as
    /// "clipped behind the status bar". Defaults to 24 (no chrome reserved) for
    /// isolated tests with no render loop.
    package var overlayContentHeight: Int {
        get { self[OverlayContentHeightKey.self] }
        set { self[OverlayContentHeightKey.self] = newValue }
    }
}

// MARK: - List Style Environment Key

/// Environment key for list styles.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ListStyleKey: EnvironmentKey {
    @usableFromInline static let defaultValue: any ListStyle = DefaultListStyle()
}

extension EnvironmentValues {
    /// The current list style.
    ///
    /// Controls how lists render, including borders, padding, and row backgrounds.
    /// Set via `.listStyle()` modifier on List views.
    /// Default: ``DefaultListStyle`` (bordered; it does NOT alternate row
    /// backgrounds — no built-in style does).
    ///
    /// The render cache compares this value between frames to decide whether
    /// what it memoized below is still good, so a style that is not `Equatable`
    /// turns memoization off in its subtree — see ``ListStyle``.
    @inlinable
    var listStyle: any ListStyle {
        get { self[ListStyleKey.self] }
        set { self[ListStyleKey.self] = newValue }
    }
}
