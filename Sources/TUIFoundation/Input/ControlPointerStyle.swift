//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlPointerStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Which of TUI's own controls give the pointer a pointing hand, where the
/// terminal lets an app shape the pointer — see
/// ``View/controlPointerStyle(_:)``.
///
/// Two conventions are both sound. A Mac keeps the arrow over a button and
/// shows the hand over a link only (``automatic``, the default); a web page
/// shows the hand over everything that can be clicked (``link``). The owner
/// asked for the choice (decisions A-O12-1, 2026-10-27).
public enum ControlPointerStyle: Sendable, Equatable, CaseIterable {
    /// The Mac's convention: a pointing hand over links — a ``Link``, a link
    /// inside a ``Text``, a button styled ``ButtonStyle/link`` — and the arrow
    /// over every other control.
    case automatic

    /// A web page's convention: a pointing hand over everything that acts on a
    /// click — buttons, toggles, segments, tabs, swatches, menus' triggers —
    /// as well as links.
    case link
}

// MARK: - Environment

private struct ControlPointerStyleKey: EnvironmentKey {
    static let defaultValue = ControlPointerStyle.automatic
}

extension EnvironmentValues {
    /// Which controls give the pointer a pointing hand — see
    /// ``View/controlPointerStyle(_:)``.
    public var controlPointerStyle: ControlPointerStyle {
        get { self[ControlPointerStyleKey.self] }
        set { self[ControlPointerStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets which of TUI's controls in this view's subtree give the pointer a
    /// pointing hand.
    ///
    /// Set it once at the root for the whole app, or on a subtree:
    ///
    /// ```swift
    /// WindowGroup {
    ///     ContentView()
    ///         .controlPointerStyle(.link)   // a hand over every clickable control
    /// }
    /// ```
    ///
    /// The default, ``ControlPointerStyle/automatic``, is the Mac's: a hand over
    /// links only. A view's own ``View/pointerStyle(_:)`` wins over either. As
    /// with any pointer shape, only a terminal that lets an app choose the
    /// pointer shows it (see ``PointerStyle``).
    ///
    /// TUI-specific: SwiftUI has no counterpart, since a Mac app follows the
    /// Mac's convention.
    public func controlPointerStyle(_ style: ControlPointerStyle) -> some View {
        environment(\.controlPointerStyle, style)
    }
}
