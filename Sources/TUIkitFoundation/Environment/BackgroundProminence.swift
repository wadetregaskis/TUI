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
///
/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct BackgroundProminenceKey: EnvironmentKey {
    @usableFromInline static let defaultValue: BackgroundProminence = .standard
}

extension EnvironmentValues {
    /// The prominence of the background underneath views associated with this
    /// environment.
    ///
    /// A `List` sets ``BackgroundProminence/increased`` for the content of its
    /// focused, selected row: the row under the cursor while the list has the
    /// focus, when that row is also in the selection. A
    /// ``SelectionShapeStyle`` background raises it for the content in front
    /// of it too (`.background(.selection)`). The system content styles
    /// (`.primary`, `.secondary`, …) resolve to the palette's text tiers
    /// there. Set it yourself above a custom background that needs the same.
    @inlinable
    public var backgroundProminence: BackgroundProminence {
        get { self[BackgroundProminenceKey.self] }
        set { self[BackgroundProminenceKey.self] = newValue }
    }
}

// MARK: - A background that raises it

/// A ``ShapeStyle`` whose fill, drawn behind a view, raises the prominence of
/// that view's content: ``SelectionShapeStyle``, and an ``AnyShapeStyle``
/// erasing one.
///
/// SwiftUI documents the one style: "standard shape styles like
/// `ShapeStyle.selection` will automatically update the background prominence
/// of foreground views" (`EnvironmentValues.backgroundProminence`). Its fill is
/// what a selected row is drawn in — here the tint, else the accent, always
/// vivid, as a terminal's one window is always the key one — so the content
/// over it takes the same inks a list's raised row does.
///
/// A conformance rather than a test of the style's type, so the erasure can
/// answer for what it erased: `AnyShapeStyle` keeps a closure, not the style.
package protocol BackgroundProminenceRaising {
    /// Whether this style raises the prominence of the content drawn over it.
    var raisesBackgroundProminence: Bool { get }
}

extension RenderContext {
    /// This context for the content of a background filled with `style`: with
    /// ``EnvironmentValues/backgroundProminence`` raised to
    /// ``BackgroundProminence/increased`` when the style raises it
    /// (``BackgroundProminenceRaising``), and unchanged — at no more than a
    /// cast — for every other style.
    ///
    /// The value is noted with the render cache as an applied environment
    /// value, as ``EnvironmentModifier`` notes what it writes: an
    /// `AnyShapeStyle` can raise on one frame and not the next, and a memo
    /// below — a `List`'s looped rows, an `.equatable()` view — keys on its
    /// own value and size, not on the prominence. Noted only by a render, for
    /// `publishingContainerSize(_:noting:)`'s reason.
    package func raisingBackgroundProminence(under style: some ShapeStyle) -> RenderContext {
        guard let raising = style as? any BackgroundProminenceRaising else { return self }
        var copy = self
        if raising.raisesBackgroundProminence { copy.environment.backgroundProminence = .increased }
        copy.environmentApplicationDepth += 1
        if !isMeasuring, let cache = renderCache,
            case .changed = cache.noteAppliedEnvironment(
                copy.environment.backgroundProminence, identity: identity,
                keyPath: \EnvironmentValues.backgroundProminence, depth: copy.environmentApplicationDepth)
        {
            cache.clearAffected(by: identity)
        }
        return copy
    }
}
