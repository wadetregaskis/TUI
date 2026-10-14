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

/// A spacer asks for no space beside it, on any edge, as SwiftUI's does
/// (decisions A-BITEMS1-1): the stack's gap beside it, where its `spacing` is
/// `nil`, is none, and its own minimum length is the default gap instead.
extension Spacer: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing { .zero }
}

// The wrappers below move their content off some of their own edges, so on
// those edges the content's preference is not theirs: each says so itself,
// ahead of the single-content forwarding (`throughWrappers` stops at the first
// view that states one). Every other single-content wrapper keeps its content's
// edges and its preference with them — measured on SwiftUI for `.id`,
// `.foregroundStyle`, `.background`, `.border` and `.offset` (`spacing.out`).

/// Padding moves its content's edges, so on an edge it pads the content's
/// preference is gone and the default is back; on the others it stands.
/// Measured on SwiftUI: a layout that asks for no space is the default
/// distance from a box beside it once `.padding(4)` wraps it, and none apart
/// under `.padding(0)` (`Tools/SwiftUIProbes/Stack spacing per pair/spacing.out`).
/// One-edge padding was not measured; it follows the same rule edge by edge.
extension ModifiedView: SpacingPreferenceProviding where Modifier == PaddingModifier {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        let insets = modifier.insets
        var padded: Edge.Set = []
        if insets.top != 0 { padded.insert(.top) }
        if insets.leading != 0 { padded.insert(.leading) }
        if insets.bottom != 0 { padded.insert(.bottom) }
        if insets.trailing != 0 { padded.insert(.trailing) }
        return contentSpacing(of: content, context: context).defaulting(padded)
    }
}

/// A frame that sets a width spans a width of its own, which its content need
/// not reach, so its leading and trailing edges are the frame's: the default;
/// one that sets a height, likewise its top and bottom. The axis it leaves
/// alone keeps the content's preference. Measured on SwiftUI (`spacing.out`):
/// a layout that asks for no space, framed `.frame(width: 40)` or
/// `.frame(maxWidth: 40, alignment: .leading)`, is the default distance from a
/// box beside it, and framed `.frame(height: 30)` none.
///
/// Whatever its width against its content's: a frame that exactly fits it is
/// the default distance from a box too (`all.frame|box` +8, measured; decisions
/// B-BITEMS1-3).
extension FlexibleFrameView: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        var framed: Edge.Set = []
        if minWidth != nil || idealWidth != nil || maxWidth != nil { framed.formUnion([.leading, .trailing]) }
        if minHeight != nil || idealHeight != nil || maxHeight != nil { framed.formUnion([.top, .bottom]) }
        return contentSpacing(of: content, context: context).defaulting(framed)
    }
}

/// `.position` takes the space it is offered and puts its content's centre at
/// a point in it, so none of its edges is its content's: the default all
/// round. Measured on SwiftUI (`spacing.out`): a layout that asks for no space,
/// under `.position`, is the default distance from a box beside it.
extension PositionView: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing { ViewSpacing() }
}

/// What `content` states, looking through its wrappers, or the default where it
/// states nothing — what a wrapper above says on the edges it leaves alone.
@MainActor
private func contentSpacing(of content: some View, context: RenderContext) -> ViewSpacing {
    throughWrappers(content, as: (any SpacingPreferenceProviding).self)?.preferredSpacing(context: context)
        ?? ViewSpacing()
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
        // The common row that states anything: one whose only children that
        // can are spacers. Each asks for no space, so a gap beside one is
        // none and every other is `uniform` — said by a mask, with no
        // conformance cast of any child and nothing allocated.
        var spacers: UInt64 = 0
        var othersMayState = false
        for (index, child) in children.enumerated() {
            if child.isSpacer, index < UInt64.bitWidth {
                spacers |= 1 << UInt64(index)
            } else if child.isSpacer || type(of: child.wrappedView)._statesSpacingPreference {
                othersMayState = true
            }
        }
        guard othersMayState else {
            self = StackGaps(uniform: uniform, besideSpacers: spacers)
            return
        }
        var anyStated = false
        let preferences = children.map { child -> ViewSpacing? in
            let stated = statedSpacing(of: child, context: context)
            if stated != nil { anyStated = true }
            return stated
        }
        self = anyStated ? StackGaps(uniform: uniform, preferences: preferences, along: axis) : StackGaps(uniform: uniform)
    }
}
