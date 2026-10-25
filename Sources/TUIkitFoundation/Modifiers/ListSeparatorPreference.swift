//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListSeparatorPreference.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Preference

/// What a row, a section or a list says about its separators: a visibility
/// and a tint for each vertical edge (decisions A47).
///
/// A list row is whole lines of cells, so a separator drawn with cells is a
/// whole line: a faint `─` rule BETWEEN two rows, in the border's ink unless
/// tinted. Where the terminal can draw one, it is a hairline instead, along
/// the top of the row below, which takes no line (`ListSeparatorStyle`,
/// decisions A-D6L-2). Which separator answers to whom:
///
/// - Between two rows: the upper row's bottom edge (its
///   ``View/listRowSeparator(_:edges:)``). A row's TOP edge is the style's to
///   decline, as SwiftUI documents a style may ("typically the top edge"):
///   the line above a row is the one below the row before it, and two rules
///   in a row would be a gap.
/// - Below a section's header: the section's top edge
///   (``View/listSectionSeparator(_:edges:)``).
/// - Below a section's last row: the section's bottom edge.
/// - Below the list's last row: never — a list's edges are its border's, or
///   the page's.
///
/// `.automatic` is the style's answer. Under a rule look no built-in style
/// draws separators by default: each costs a line of height, which a list of
/// single-line rows doubles (decisions A47). Under a hairline look, which
/// costs none, every style but `.sidebar` and `.insetGrouped` does, as
/// SwiftUI's do (A-D6L-2, the owner's option 4).
///
/// `@usableFromInline`, with its fields (the module split's tier 2): TUIkitLists
/// asks ``overridden(by:)`` of every row's preference, and an `@inlinable`
/// member of a type that is only `package` is not serialized for another module
/// to inline, whatever it says.
@usableFromInline
package struct ListSeparatorPreference: Equatable, Sendable {
    /// Whether the line above shows.
    @usableFromInline package var top: Visibility = .automatic
    /// Whether the line below shows.
    @usableFromInline package var bottom: Visibility = .automatic
    /// The line above's ink, or `nil` for the style's.
    @usableFromInline package var topTint: Color?
    /// The line below's ink, or `nil` for the style's.
    @usableFromInline package var bottomTint: Color?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitLists makes these, for its lists.
    package init(top: Visibility = .automatic, bottom: Visibility = .automatic, topTint: Color? = nil, bottomTint: Color? = nil) {
        self.top = top
        self.bottom = bottom
        self.topTint = topTint
        self.bottomTint = bottomTint
    }

    /// `self`, with whatever `other` states — a visibility other than
    /// `.automatic`, a tint — written over it: a row's own preference over the
    /// list-wide one.
    @inlinable
    package func overridden(by other: Self) -> Self {
        var merged = self
        if other.top != .automatic { merged.top = other.top }
        if other.bottom != .automatic { merged.bottom = other.bottom }
        if let tint = other.topTint { merged.topTint = tint }
        if let tint = other.bottomTint { merged.bottomTint = tint }
        return merged
    }
}

/// One separator modifier's statement, carried as data so the views holding
/// it compare as values.
package enum ListSeparatorChange: Equatable, Sendable {
    /// `.listRowSeparator(_:edges:)` / `.listSectionSeparator(_:edges:)`.
    case visibility(Visibility, VerticalEdge.Set)
    /// `.listRowSeparatorTint(_:edges:)` / `.listSectionSeparatorTint(_:edges:)`.
    case tint(Color?, VerticalEdge.Set)

    /// Whether this statement, made by a list ROW, can make the row draw other
    /// than the list-wide `defaults` alone would — whether its report must
    /// reach the list on every frame, or may be lost to a row the memo serves
    /// without rendering it (``renderReportingSeparator(_:change:sections:context:)``).
    ///
    /// A row whose every statement answers no draws what the defaults draw, in
    /// any order and any number. Its `.top` edge is the style's to decline
    /// (``ListSeparatorPreference``); `.automatic` defers to the default; a
    /// visibility the default already has changes nothing; and a tint shows
    /// only on a rule that is drawn, which only a statement answering yes — or a
    /// default that draws one — puts there.
    ///
    /// - Parameters:
    ///   - defaults: The list-wide preference.
    ///   - automaticShows: Whether `.automatic` shows a separator in this list —
    ///     its style's answer under the look it draws (`ListSeparatorStyle`).
    package func changesRow(over defaults: ListSeparatorPreference, automaticShows: Bool) -> Bool {
        let defaultShows = defaults.bottom == .visible || defaults.bottom == .automatic && automaticShows
        switch self {
        case .visibility(let visibility, let edges):
            guard edges.contains(.bottom), visibility != .automatic else { return false }
            return (visibility == .visible) != defaultShows
        case .tint(let tint, let edges):
            guard edges.contains(.bottom), let tint else { return false }
            return defaultShows && tint != defaults.bottomTint
        }
    }

    /// `preference` with this statement applied.
    package func apply(to preference: inout ListSeparatorPreference) {
        switch self {
        case .visibility(let visibility, let edges):
            if edges.contains(.top) { preference.top = visibility }
            if edges.contains(.bottom) { preference.bottom = visibility }
        case .tint(let tint, let edges):
            if edges.contains(.top) { preference.topTint = tint }
            if edges.contains(.bottom) { preference.bottomTint = tint }
        }
    }
}
