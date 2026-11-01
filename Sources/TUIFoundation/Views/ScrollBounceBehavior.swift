//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollBounceBehavior.swift
//
//  Whether a scrollable may be pushed past its edges when its content fits:
//  SwiftUI's bounce behaviour, over TUI's overscroll allowance.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - ScrollBounceBehavior

/// When a scrollable view may be pushed past the end of its content. Matches
/// SwiftUI's type of the same name.
///
/// SwiftUI's bounce is a rubber band: pushed past an edge, the content follows
/// and springs back. TUI's push past an edge is its overscroll allowance
/// (``View/scrollOverscroll(top:bottom:)``): the content follows and stays,
/// which is what lets a deliberate push be told from a graze (see there). The
/// allowance says how far; this says when:
///
/// - ``basedOnSize`` allows the push only when the content overflows, so
///   content that fits sits still — the common reason to write this.
/// - ``always`` allows it whatever the content's size, and bounces: an end
///   given no allowance may be pushed two lines (one in a view under eight
///   lines tall), held while the scrolling goes on and sprung back a line a
///   frame once it has been quiet for a quarter of a second — within a frame
///   of when the scroll goes idle (``ScrollPhase``). Any scroll step past the
///   end pushes it, as it pushes any allowance: the wheel's, a scroll view's
///   arrow and page keys', the scrollbar's arrows'. A focused `List`'s or
///   `Table`'s arrow and page keys move its cursor instead, and push nothing.
///   An end given an allowance keeps its push.
/// - ``automatic`` leaves it to the view: here, the allowance whatever the
///   content's size, and no bounce.
///
/// Without `.always` and with no allowance — the default — there is nothing to
/// push into, and no scrollable is pushed past its edges at all; macOS under a
/// mouse wheel does not bounce either. Reaches `ScrollView`, `List` and
/// `Table`. TUI's allowance is vertical only, so a horizontal behaviour has
/// nothing to decide yet.
public struct ScrollBounceBehavior: Hashable, Sendable {
    enum Kind: UInt8, Sendable {
        case automatic, always, basedOnSize
    }

    let kind: Kind

    /// The view decides: here, the allowance applies whatever the content's
    /// size, as under ``always``, with no bounce.
    public static var automatic: Self { Self(kind: .automatic) }

    /// The allowance applies whatever the content's size, and an end given
    /// none bounces: pushed a line or two, it springs back once the scrolling
    /// stops.
    public static var always: Self { Self(kind: .always) }

    /// The allowance applies only while the content overflows the view.
    public static var basedOnSize: Self { Self(kind: .basedOnSize) }

    /// Whether a view whose content does or does not overflow may be pushed
    /// into its allowance.
    ///
    /// `@usableFromInline`: the `@inlinable` `EnvironmentValues.overscrollAllowances(overflowing:)`
    /// calls it (module split step A3).
    @usableFromInline
    func allowsOverscroll(overflowing: Bool) -> Bool {
        kind != .basedOnSize || overflowing
    }

    /// Whether an end with no allowance of its own gets the sprung one — the
    /// bounce, under ``always`` alone (decisions B31).
    ///
    /// `@usableFromInline` for `EnvironmentValues.overscrollAllowances(overflowing:)`,
    /// as ``allowsOverscroll(overflowing:)`` is.
    @usableFromInline
    var springs: Bool { kind == .always }
}

// MARK: - Environment

private struct HorizontalScrollBounceBehaviorKey: EnvironmentKey {
    static let defaultValue = ScrollBounceBehavior.automatic
}

private struct VerticalScrollBounceBehaviorKey: EnvironmentKey {
    static let defaultValue = ScrollBounceBehavior.automatic
}

extension EnvironmentValues {
    /// When the scrollable views in this subtree may be pushed past their
    /// leading and trailing edges. Matches SwiftUI's value of the same name.
    ///
    /// Recorded: TUI's overscroll allowance is vertical only (see
    /// ``ScrollBounceBehavior``).
    public var horizontalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[HorizontalScrollBounceBehaviorKey.self] }
        set { self[HorizontalScrollBounceBehaviorKey.self] = newValue }
    }

    /// When the scrollable views in this subtree may be pushed past their top
    /// and bottom. Matches SwiftUI's value of the same name.
    public var verticalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[VerticalScrollBounceBehaviorKey.self] }
        set { self[VerticalScrollBounceBehaviorKey.self] = newValue }
    }

    /// The overscroll allowances (``View/scrollOverscroll(top:bottom:)``) a
    /// scrollable is given this frame, after its vertical bounce behaviour:
    /// none under ``ScrollBounceBehavior/basedOnSize`` while its content fits;
    /// and whether an end given none gets the sprung bounce, under
    /// ``ScrollBounceBehavior/always`` (`ScrollOverscrollState.resolve`).
    ///
    /// `@inlinable` (module split step A3): `ItemListHandler` asks it as it
    /// settles its overscroll, in the Lists group, which leaves the substrate
    /// at B6.
    @inlinable
    package func overscrollAllowances(
        overflowing: Bool
    ) -> (top: ScrollOverscroll, bottom: ScrollOverscroll, springs: Bool) {
        let behavior = verticalScrollBounceBehavior
        return behavior.allowsOverscroll(overflowing: overflowing)
            ? (scrollOverscrollTop, scrollOverscrollBottom, behavior.springs) : (.none, .none, false)
    }
}

extension View {
    /// Sets when the scrollable views in this subtree may be pushed past the
    /// end of their content along `axes`. Matches SwiftUI's
    /// `scrollBounceBehavior(_:axes:)`; see ``ScrollBounceBehavior``.
    ///
    /// ```swift
    /// ScrollView { ShortForm() }
    ///     .scrollOverscroll(bottom: .rows(2))
    ///     .scrollBounceBehavior(.basedOnSize)   // still while it fits
    /// ```
    ///
    /// Reaches `ScrollView`, `List` and `Table`, but not the scrollers the
    /// framework puts around a tall menu, a sheet's or a framed container's
    /// content (the scrollables in that content do).
    ///
    /// - Parameters:
    ///   - behavior: When the push is allowed.
    ///   - axes: The axes it applies to; vertical by default, as in SwiftUI.
    /// - Returns: A view whose scrollables follow the behaviour.
    nonisolated public func scrollBounceBehavior(
        _ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]
    ) -> some View {
        // Each axis written only when named, so two calls compose — the rule
        // `scrollIndicators(_:axes:)` follows, for its reason.
        transformEnvironment(\.verticalScrollBounceBehavior) {
            if axes.contains(.vertical) { $0 = behavior }
        }
        .transformEnvironment(\.horizontalScrollBounceBehavior) {
            if axes.contains(.horizontal) { $0 = behavior }
        }
    }
}
