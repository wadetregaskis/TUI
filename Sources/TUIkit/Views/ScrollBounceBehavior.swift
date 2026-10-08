//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollBounceBehavior.swift
//
//  Whether a scrollable may be pushed past its edges when its content fits:
//  SwiftUI's bounce behaviour, over TUIkit's overscroll allowance.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollBounceBehavior

/// When a scrollable view may be pushed past the end of its content. Matches
/// SwiftUI's type of the same name.
///
/// SwiftUI's bounce is a rubber band: pushed past an edge, the content follows
/// and springs back. TUIkit's push past an edge is its overscroll allowance
/// (``View/scrollOverscroll(top:bottom:)``): the content follows and stays,
/// which is what lets a deliberate push be told from a graze (see there). The
/// allowance says how far; this says when:
///
/// - ``basedOnSize`` allows the push only when the content overflows, so
///   content that fits sits still — the common reason to write this.
/// - ``always`` allows it whatever the content's size, which is TUIkit's
///   default, as it is SwiftUI's.
/// - ``automatic`` leaves it to the view: here, as ``always``.
///
/// With no allowance — the default — there is nothing to push into, and no
/// scrollable is pushed past its edges at all; macOS under a mouse wheel does
/// not bounce either. TUIkit's allowance is vertical only, so a horizontal
/// behaviour has nothing to decide yet.
public struct ScrollBounceBehavior: Hashable, Sendable {
    enum Kind: UInt8, Sendable {
        case automatic, always, basedOnSize
    }

    let kind: Kind

    /// The view decides: here, the allowance applies whatever the content's
    /// size, as under ``always``.
    public static var automatic: Self { Self(kind: .automatic) }

    /// The allowance applies whatever the content's size.
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
    /// Recorded: TUIkit's overscroll allowance is vertical only (see
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
    /// none under ``ScrollBounceBehavior/basedOnSize`` while its content fits.
    @inlinable
    func overscrollAllowances(overflowing: Bool) -> (top: ScrollOverscroll, bottom: ScrollOverscroll) {
        verticalScrollBounceBehavior.allowsOverscroll(overflowing: overflowing)
            ? (scrollOverscrollTop, scrollOverscrollBottom) : (.none, .none)
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
    /// Reaches `ScrollView`, `List` and `Table`.
    ///
    /// - Parameters:
    ///   - behavior: When the push is allowed.
    ///   - axes: The axes it applies to; vertical by default, as in SwiftUI.
    /// - Returns: A view whose scrollables follow the behaviour.
    public func scrollBounceBehavior(
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
