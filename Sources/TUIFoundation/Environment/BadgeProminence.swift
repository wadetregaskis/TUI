//  🖥️ TUI — A Terminal UI framework for Swift
//  BadgeProminence.swift
//
//  How much attention a list row's badge draws to itself.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling
import TUIView

/// The visual prominence of a badge.
///
/// Badges can be used for different kinds of information, from the passive
/// number of items in a container to the number of required actions. The
/// prominence of badges in lists can be adjusted to reflect this and be made
/// to draw more or less attention to themselves.
///
/// Badges default to ``standard`` prominence:
///
/// ```swift
/// List(folders) { folder in
///     Text(folder.name)
///         .badge(folder.numberOfItems)
/// }
/// .badgeProminence(.decreased)
/// ```
///
/// A `List` draws its badges in the palette's tertiary foreground, and a
/// ``decreased`` badge in its quaternary, the dimmest text it has. An
/// ``increased`` badge draws as a ``standard`` one does: measured on macOS
/// 15.8, a list's `.increased` badge is the same capsule as its `.standard`
/// one, in the default style and the sidebar style alike.
public struct BadgeProminence: Hashable, Sendable {
    /// Where this prominence sits: below, at or above the standard.
    private let level: Int8

    /// The lowest level of prominence for a badge.
    ///
    /// This level of prominence should be used for badges that display a
    /// value of passive information that requires no user action, such as
    /// total number of messages or content.
    public static let decreased = Self(level: -1)

    /// The standard level of prominence for a badge.
    ///
    /// This level of prominence should be used for badges that display a
    /// value that suggests user action, such as a count of unread messages
    /// or new invitations.
    public static let standard = Self(level: 0)

    /// The highest level of prominence for a badge.
    ///
    /// This level of prominence should be used for badges that display a
    /// value that requires user action, such as number of updates or account
    /// errors.
    public static let increased = Self(level: 1)

    /// The ink a list draws a badge of this prominence in.
    package func badgeInk(in palette: any Palette) -> Color {
        self == .decreased ? palette.foregroundQuaternary : palette.foregroundTertiary
    }
}

/// Environment key for ``View/badgeProminence(_:)``.
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct BadgeProminenceKey: EnvironmentKey {
    @usableFromInline static let defaultValue: BadgeProminence = .standard
}

extension EnvironmentValues {
    /// The prominence to apply to badges associated with this environment.
    ///
    /// Read by a `List` for the badges on its rows: the value in the
    /// environment each badge is written in — the list's own, so
    /// `.badgeProminence(_:)` applies to a list from the list or from anything
    /// containing it, or one written around a row's `.badge(_:)`.
    @inlinable
    public var badgeProminence: BadgeProminence {
        get { self[BadgeProminenceKey.self] }
        set { self[BadgeProminenceKey.self] = newValue }
    }
}

extension View {
    /// Specifies the prominence of badges created by this view.
    ///
    /// ```swift
    /// List(folders) { folder in
    ///     Text(folder.name)
    ///         .badge(folder.numberOfItems)
    /// }
    /// .badgeProminence(.decreased)
    /// ```
    ///
    /// A badge is drawn in the prominence of the environment its `.badge(_:)`
    /// is written in, as any view sees its environment: on the list or on
    /// anything containing it, it reaches every row's badge; written on a row
    /// around its `.badge(_:)` — `.badge(5).badgeProminence(.decreased)` — it
    /// reaches that badge, and wins over the list's; written inside it —
    /// `.badgeProminence(.decreased).badge(5)` — it does not, as measured on
    /// macOS 15.8 (decisions B72). Between the badge and the prominence only
    /// other environment writes are seen through: a `.badge(_:)` with any
    /// other modifier after it is not seen as the row's badge at all
    /// (decisions B-LISTS-1).
    ///
    /// - Parameter prominence: The prominence to apply to badges.
    public func badgeProminence(_ prominence: BadgeProminence) -> some View {
        environment(\.badgeProminence, prominence)
    }
}
