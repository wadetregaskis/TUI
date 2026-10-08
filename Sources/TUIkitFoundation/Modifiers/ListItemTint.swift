//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListItemTint.swift
//
//  The tint a sidebar list gives its rows' label icons.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// A tint effect configuration that you can apply to content in a list.
///
/// Use one of these with ``View/listItemTint(_:)-(ListItemTint?)``. The
/// containing list applies the tint as its style says: a ``SidebarListStyle``
/// list draws its rows' `Label` icons in it, as a macOS sidebar does, and the
/// other styles draw icons in the rows' own foreground, as macOS's do.
public struct ListItemTint: Equatable, Sendable {
    /// What the tint is.
    private enum Kind: Equatable, Sendable {
        case fixed(Color)
        case preferred(Color)
        case monochrome
    }

    private let kind: Kind

    /// An explicit tint color.
    ///
    /// - Parameter tint: The color to use to tint the content.
    public static func fixed(_ tint: Color) -> Self {
        Self(kind: .fixed(tint))
    }

    /// An explicit tint color that the system can override, like when the
    /// system has a custom user accent color on macOS.
    ///
    /// A terminal has no system accent of its own to override it with, so it
    /// draws as ``fixed(_:)`` does.
    ///
    /// - Parameter tint: The color to use to tint the content.
    public static func preferred(_ tint: Color) -> Self {
        Self(kind: .preferred(tint))
    }

    /// A standard grayscale tint effect: the palette's secondary foreground.
    public static let monochrome = Self(kind: .monochrome)

    /// The colour this tint draws in, against `palette`.
    func color(in palette: any Palette) -> Color {
        switch kind {
        case .fixed(let color), .preferred(let color): color
        case .monochrome: palette.foregroundSecondary
        }
    }
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ListItemTintKey: EnvironmentKey {
    @usableFromInline static let defaultValue: ListItemTint? = nil
}

/// Whether a view is in a row of a ``SidebarListStyle`` list, which draws its
/// `Label` icons in the list item tint. Set by the list for its rows.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct SidebarListRowKey: EnvironmentKey {
    @usableFromInline static let defaultValue = false
}

extension EnvironmentValues {
    /// The list item tint in force (``View/listItemTint(_:)-(ListItemTint?)``),
    /// or `nil` for the accent.
    @inlinable
    package var listItemTint: ListItemTint? {
        get { self[ListItemTintKey.self] }
        set { self[ListItemTintKey.self] = newValue }
    }

    /// Whether this is a row of a sidebar-style list (``SidebarListStyle``).
    @inlinable
    package var isSidebarListRow: Bool {
        get { self[SidebarListRowKey.self] }
        set { self[SidebarListRowKey.self] = newValue }
    }

    /// The colour a `Label`'s icon draws in here: the list item tint — the
    /// accent when none is set — in a sidebar list's row, and `nil`, its own
    /// foreground, anywhere else.
    var labelIconTint: Color? {
        guard isSidebarListRow else { return nil }
        return listItemTint?.color(in: palette) ?? palette.accent
    }
}
