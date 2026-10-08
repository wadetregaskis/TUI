//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStyle+PlainAndInsetGrouped.swift
//
//  Created by LAYERED.work
//  License: MIT

extension ListStyle {
    /// The cells a list in this style spends across its width on chrome: the
    /// two border columns when it draws a border, and its row padding either
    /// side. Every width a list proposes its rows or reports for itself takes
    /// this off, or adds it on.
    var horizontalChrome: Int {
        (showsBorder ? 2 : 0) + rowPadding.leading + rowPadding.trailing
    }
}

// MARK: - Plain List Style

/// A list style that uses minimal visual styling with no borders or backgrounds.
///
/// PlainListStyle renders lists with no border, no padding insets,
/// and no row background colors. This matches SwiftUI's `.listStyle(.plain)`.
///
/// # Rendering
/// - Rows display full width without padding
/// - No border around the list
/// - No row separators or backgrounds
/// - Content takes full available space
///
/// `Equatable` for the reason given under ``ListStyle``: a memo below a value
/// the render cache cannot compare declines to cache. It holds nothing, and its
/// three answers are literal constants, so every instance styles a list
/// identically.
public struct PlainListStyle: ListStyle, Equatable {
    /// Creates a plain list style.
    public init() {}

    public var showsBorder: Bool {
        false
    }

    public var rowPadding: EdgeInsets {
        EdgeInsets(all: 0)
    }

    public var alternatingRowColors: Bool {
        false
    }
}

// MARK: - Inset Grouped List Style

/// A list style that uses borders and inset padding.
///
/// InsetGroupedListStyle renders lists with a border and inset padding. This
/// matches SwiftUI's `.listStyle(.insetGrouped)`.
///
/// # Rendering
/// - Rows have inset padding (1 character on each side)
/// - Border surrounds the entire list
/// - No alternating row backgrounds: ``alternatingRowColors`` is false, so a
///   row's background comes from focus and selection alone
///
/// `Equatable` on the same terms as ``PlainListStyle``, and a list spelling
/// `.listStyle(.insetGrouped)` explicitly needs it as much: the default value of
/// the environment key is an instance of this type, but a default is only read
/// out of the environment, never injected into it, so it is the explicit
/// modifier that the cache has to be able to compare.
public struct InsetGroupedListStyle: ListStyle, Equatable {
    /// Creates an inset grouped list style.
    public init() {}

    public var showsBorder: Bool {
        true
    }

    public var rowPadding: EdgeInsets {
        // No container padding - row backgrounds need to extend to the borders.
        // Row padding is handled in List's renderRow() method.
        EdgeInsets(all: 0)
    }

    public var alternatingRowColors: Bool {
        false
    }
}

// MARK: - List Style Convenience

extension ListStyle where Self == PlainListStyle {
    /// The plain list style with no borders or backgrounds.
    ///
    /// Usable with leading-dot syntax: `.listStyle(.plain)`.
    public static var plain: PlainListStyle {
        PlainListStyle()
    }
}

extension ListStyle where Self == InsetGroupedListStyle {
    /// The inset grouped list style: a bordered, inset container.
    ///
    /// Usable with leading-dot syntax: `.listStyle(.insetGrouped)`.
    public static var insetGrouped: InsetGroupedListStyle {
        InsetGroupedListStyle()
    }
}
