//  🖥️ TUI — A Terminal UI framework for Swift
//  PointingHandCursor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// Over which of TUI's own views the pointer becomes a pointing hand, where
/// the terminal lets an app shape the pointer — see
/// ``View/pointingHandCursor(over:)``.
///
/// Two conventions are both sound. A Mac keeps the arrow over a button and
/// shows the hand over a link only (``links``, the default); a web page shows
/// the hand over everything that can be clicked (``everythingClickable``). The
/// owner asked for the choice (decisions A-O12-1, 2026-10-27), and for these
/// names over "control pointer style": a control is too many things.
public enum PointingHandCursorScope: Sendable, Equatable, CaseIterable {
    /// The Mac's convention: a pointing hand over links — a ``Link``, a link
    /// inside a ``Text``, a button styled ``ButtonStyle/link`` — and the arrow
    /// over everything else.
    case links

    /// A web page's convention: a pointing hand over everything that acts on a
    /// click — buttons, toggles, segments, tabs, swatches, menus' triggers —
    /// as well as links.
    case everythingClickable
}

// MARK: - Environment

private struct PointingHandCursorScopeKey: EnvironmentKey {
    static let defaultValue = PointingHandCursorScope.links
}

extension EnvironmentValues {
    /// Over which views the pointer becomes a pointing hand — see
    /// ``View/pointingHandCursor(over:)``.
    public var pointingHandCursorScope: PointingHandCursorScope {
        get { self[PointingHandCursorScopeKey.self] }
        set { self[PointingHandCursorScopeKey.self] = newValue }
    }
}

extension View {
    /// Sets over which of TUI's views in this view's subtree the pointer
    /// becomes a pointing hand.
    ///
    /// Set it once at the root for the whole app, or on a subtree:
    ///
    /// ```swift
    /// WindowGroup {
    ///     ContentView()
    ///         .pointingHandCursor(over: .everythingClickable)   // as a web page does
    /// }
    /// ```
    ///
    /// The default, ``PointingHandCursorScope/links``, is the Mac's: a hand over
    /// links only. A view's own ``View/pointerStyle(_:)`` wins over either. As
    /// with any pointer shape, only a terminal that lets an app choose the
    /// pointer shows it (see ``PointerStyle``).
    ///
    /// TUI-specific: SwiftUI has no counterpart, since a Mac app follows the
    /// Mac's convention.
    nonisolated public func pointingHandCursor(over scope: PointingHandCursorScope) -> some View {
        environment(\.pointingHandCursorScope, scope)
    }
}
