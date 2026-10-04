//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackgroundProminence.swift
//
//  How prominent the background under a view is — raised on a list's focused,
//  selected row, where the content styles read as that row's own ink.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// The prominence of backgrounds underneath other views.
///
/// Background prominence should influence foreground styling to maintain
/// sufficient contrast against the background. A `List`'s selected row is the
/// case the framework raises itself: while the list has focus, the row under
/// the cursor that is also selected paints the accent's breathing fill, and its
/// content renders with ``increased`` prominence.
///
/// Read it to adapt a custom element:
///
/// ```swift
/// struct StarRating: View {
///     var rating: Int
///     @Environment(\.backgroundProminence) private var backgroundProminence
///
///     var body: some View {
///         Text(String(repeating: "★", count: rating))
///             .foregroundStyle(backgroundProminence == .increased
///                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.yellow))
///     }
/// }
/// ```
///
/// Under ``increased`` prominence the content styles — `.primary` through
/// `.quinary` — resolve to the palette's own text tiers, the inks a list row's
/// fills are chosen to carry, whatever foreground style the row inherited.
public struct BackgroundProminence: Hashable, Sendable {
    /// Whether the background is the raised one.
    private let isIncreased: Bool

    /// The standard prominence of a background.
    ///
    /// This is the default level of prominence and doesn't require any
    /// adjustment to achieve satisfactory contrast with the background.
    public static let standard = Self(isIncreased: false)

    /// A more prominent background that likely requires some changes to the
    /// views above it.
    ///
    /// This is the level of prominence for more highly saturated and full
    /// color backgrounds, such as focused selected list rows. Foreground
    /// content takes on the palette's own text inks there.
    public static let increased = Self(isIncreased: true)
}

/// Environment key for ``EnvironmentValues/backgroundProminence``.
private struct BackgroundProminenceKey: EnvironmentKey {
    static let defaultValue: BackgroundProminence = .standard
}

extension EnvironmentValues {
    /// The prominence of the background underneath views associated with this
    /// environment.
    ///
    /// A `List` sets ``BackgroundProminence/increased`` for the content of its
    /// focused, selected row: the row under the cursor while the list has the
    /// focus, when that row is also in the selection. The system content
    /// styles (`.primary`, `.secondary`, …) resolve to the palette's text tiers
    /// there. Set it yourself above a custom background that needs the same.
    public var backgroundProminence: BackgroundProminence {
        get { self[BackgroundProminenceKey.self] }
        set { self[BackgroundProminenceKey.self] = newValue }
    }
}
