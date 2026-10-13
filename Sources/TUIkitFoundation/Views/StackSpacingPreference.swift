//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackSpacingPreference.swift
//
//  Which views state a spacing preference of their own, and where one is
//  found: what `LayoutSubview.spacing` answers, and what a row given
//  `spacing: nil` resolves each pair of neighbours by (decisions B20).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The views that state one

extension _LayoutCore {
    /// A layout states what its ``Layout/spacing(subviews:cache:)`` says.
    public static var _statesSpacingPreference: Bool { true }
}

extension Subview {
    /// A member resolved elsewhere may be anything, a layout among them; asked,
    /// the proxy answers with its member's.
    public static var _statesSpacingPreference: Bool { true }
}

/// Padding moves its content's edges, so on an edge it pads the content's
/// preference is gone and the default is back; on the others it stands.
/// Measured on SwiftUI: a layout that asks for no space is the default
/// distance from a box beside it once `.padding(4)` wraps it, and none apart
/// under `.padding(0)` (`Tools/SwiftUIProbes/Stack spacing per pair/spacing.out`).
/// One-edge padding was not measured; it follows the same rule edge by edge.
extension ModifiedView: SpacingPreferenceProviding where Modifier == PaddingModifier {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        let stated =
            throughWrappers(content, as: (any SpacingPreferenceProviding).self)?
            .preferredSpacing(context: context) ?? ViewSpacing()
        let insets = modifier.insets
        var padded: Edge.Set = []
        if insets.top != 0 { padded.insert(.top) }
        if insets.leading != 0 { padded.insert(.leading) }
        if insets.bottom != 0 { padded.insert(.bottom) }
        if insets.trailing != 0 { padded.insert(.trailing) }
        return stated.defaulting(padded)
    }
}

// MARK: - Where it is found

/// The spacing `child` states: what the first view at or inside it that states
/// one says, looking through the single-content wrappers (which move none of
/// its edges) — or `nil` where it states none, and the default applies.
///
/// A sequence of runtime conformance casts, so a row asks it only where its
/// content's type says a child may state one (``View/_statesSpacingPreference``).
///
/// - Parameters:
///   - child: The child to ask.
///   - context: The context of the container `child` is in.
/// - Returns: The spacing `child` states, or `nil`.
@MainActor
func statedSpacing(of child: ChildView, context: RenderContext) -> ViewSpacing? {
    guard let provider = throughWrappers(child.wrappedView, as: (any SpacingPreferenceProviding).self) else {
        return nil
    }
    return provider.preferredSpacing(context: child.renderContext(under: context))
}

extension StackGaps {
    /// Gaps by pair over `children`: each child's stated spacing
    /// (``statedSpacing(of:context:)``), and every gap `uniform` — no
    /// preferences carried — when none of them states one.
    ///
    /// - Parameters:
    ///   - uniform: The gap between two children that state nothing.
    ///   - children: The stack's children, in order.
    ///   - axis: The axis they follow each other along.
    ///   - context: The stack's context.
    @MainActor
    init(uniform: Int, stating children: [ChildView], along axis: Axis, context: RenderContext) {
        var anyStated = false
        let preferences = children.map { child -> ViewSpacing? in
            let stated = statedSpacing(of: child, context: context)
            if stated != nil { anyStated = true }
            return stated
        }
        self = anyStated ? StackGaps(uniform: uniform, preferences: preferences, along: axis) : StackGaps(uniform: uniform)
    }
}
