//  🖥️ TUI — A Terminal UI framework for Swift
//  StackSpacingPreference.swift
//
//  Which views state a spacing preference of their own, and where one is
//  found: what `LayoutSubview.spacing` answers, and what a row given
//  `spacing: nil` resolves each pair of neighbours by (decisions B20).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

// MARK: - The views that state one

@MainActor extension _LayoutCore {
    /// A layout states what its ``Layout/spacing(subviews:cache:)`` says.
    public static var _statesSpacingPreference: Bool { true }
}

@MainActor extension Subview {
    /// A member resolved elsewhere may be anything, a layout among them; asked,
    /// the proxy answers with its member's.
    public static var _statesSpacingPreference: Bool { true }
}

/// A spacer asks for no space beside it, on any edge, as SwiftUI's does
/// (decisions A-BITEMS1-1): the stack's gap beside it, where its `spacing` is
/// `nil`, is none, and its own minimum length is the default gap instead.
@MainActor extension Spacer: SpacingPreferenceProviding {
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
@MainActor extension ModifiedView: SpacingPreferenceProviding where Modifier == PaddingModifier {
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
@MainActor extension FlexibleFrameView: SpacingPreferenceProviding {
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
@MainActor extension PositionView: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing { ViewSpacing() }
}

/// What `content` states, looking through its wrappers and into a view of the
/// app's own, or the default where it states nothing — what a wrapper above
/// says on the edges it leaves alone.
@MainActor
private func contentSpacing<Content: View>(of content: Content, context: RenderContext) -> ViewSpacing {
    statedSpacing(ofView: content, context: context) ?? ViewSpacing()
}

// MARK: - The stacks: their children's, by the edges they form

/// An eager row states its children's preferences as SwiftUI's does, by the
/// edges each child forms (measured, `Tools/SwiftUIProbes/Stack spacing per
/// pair/nested.out`): its leading edge is its first child's, its trailing edge
/// its last child's, and its top and bottom every child's, merged — so
/// `HStack { HStack { tight; Text("x") }; box }` keeps the default gap after
/// `x`, and `HStack { HStack { Text("x"); tight }; box }` none. A lazy row
/// states nothing (measured: the default gap).
@MainActor extension _HStackCore: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        guard overflow == .clip else { return ViewSpacing() }
        let children = stackChildren(of: content, context: context.publishingContainerAxis(.horizontal)).laidOut
        return edgesFormed(by: children, along: .horizontal, context: context)
    }
}

/// An eager column: its top edge is its first child's, its bottom edge its
/// last child's, and its leading and trailing edges every child's, merged
/// (measured: `HStack { VStack { tight; box }; box }` keeps no gap, every row
/// of the column forming its trailing edge).
@MainActor extension _VStackCore: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        guard overflow == .clip else { return ViewSpacing() }
        let children = stackChildren(of: content, context: context.publishingContainerAxis(.vertical)).laidOut
        return edgesFormed(by: children, along: .vertical, context: context)
    }
}

/// The edges a stack of `children` forms along `axis`: the first child's
/// leading (or top) edge, the last child's trailing (or bottom) edge, and every
/// child's edges across but a spacer's, merged — each as the child states it,
/// the default where it states nothing. A spacer's "none" is about the stack's
/// own axis: across, it states nothing (measured: `HStack { VStack { box;
/// Spacer() }; box }` keeps the default gap, `HStack { HStack { box; Spacer()
/// }; box }` none, `Tools/SwiftUIProbes/Stack spacing per pair/nested.out`).
@MainActor
private func edgesFormed(by children: [ChildView], along axis: Axis, context: RenderContext) -> ViewSpacing {
    let (start, end, across): (Edge.Set, Edge.Set, Edge.Set) =
        axis == .horizontal ? (.leading, .trailing, [.top, .bottom]) : (.top, .bottom, [.leading, .trailing])
    var formed = ViewSpacing()
    for (index, child) in children.enumerated() {
        guard let stated = statedSpacing(of: child, context: context) else { continue }
        var edges: Edge.Set = child.isSpacer ? [] : across
        if index == 0 { edges.formUnion(start) }
        if index == children.count - 1 { edges.formUnion(end) }
        formed.formUnion(stated, edges: edges)
    }
    return formed
}

@MainActor extension VStack {
    /// Its content's answer: an eager column states the edges its children
    /// form (`_VStackCore.preferredSpacing(context:)`).
    public static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

@MainActor extension _VStackCore {
    /// See ``VStack/_statesSpacingPreference``.
    package static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

@MainActor extension HStack {
    /// Its content's answer: an eager row states the edges its children form.
    public static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

@MainActor extension _HStackCore {
    /// See ``HStack/_statesSpacingPreference``.
    package static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }
}

@MainActor extension LazyVStack {
    /// A lazy stack states nothing, as SwiftUI's does (measured: the default
    /// gap beside a `LazyHStack` of a layout that asks for none).
    public static var _statesSpacingPreference: Bool { false }
}

@MainActor extension LazyHStack {
    /// See ``LazyVStack/_statesSpacingPreference``.
    public static var _statesSpacingPreference: Bool { false }
}

// MARK: - The shapes a body takes

/// An `if`/`else` states what its live branch states.
@MainActor extension ConditionalView: SpacingPreferenceProviding {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        switch self {
        case .trueContent(let content):
            contentSpacing(of: content, context: context.withBranchIdentity("true"))
        case .falseContent(let content):
            contentSpacing(of: content, context: context.withBranchIdentity("false"))
        }
    }
}

/// An `if` states what its view states while it is there.
extension Optional: SpacingPreferenceProviding where Wrapped: View {
    func preferredSpacing(context: RenderContext) -> ViewSpacing {
        guard case .some(let view) = self else { return ViewSpacing() }
        return contentSpacing(of: view, context: context)
    }
}

// MARK: - Where it is found

/// The spacing `child` states: what the first view at or inside it that states
/// one says, looking through the single-content wrappers (which move none of
/// its edges) and into the body of a view of the app's own — or `nil` where it
/// states none, and the default applies.
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
    statedSpacing(ofErased: child.wrappedView, context: child.renderContext(under: context))
}

/// The spacing `view` states, laid out in `context` (its own): its own, as a
/// ``SpacingPreferenceProviding`` view says it, its content's through a
/// single-content wrapper, or its body's for a view of the app's own — the
/// body evaluated as the walk evaluates it, at the identity it renders at.
/// `nil` where it states none.
@MainActor
private func statedSpacing<V: View>(ofView view: V, context: RenderContext) -> ViewSpacing? {
    guard V._statesSpacingPreference else { return nil }
    if let provider = view as? any SpacingPreferenceProviding { return provider.preferredSpacing(context: context) }
    if let wrapper = view as? any SingleContentWrapper { return statedSpacing(ofContentOf: wrapper, context: context) }
    guard V.Body.self != Never.self, !(view is Renderable) else { return nil }
    let bodyContext = context.withChildIdentity(type: V.Body.self)
    guard let plan = propertyPlan(for: V.self) else {
        return statedSpacing(ofView: view.body, context: bodyContext)
    }
    return statedSpacing(
        ofView: preparedBody(of: view, plan: plan, context: context, isMeasuring: true), context: bodyContext)
}

/// ``statedSpacing(ofView:context:)`` of `wrapper`'s content, the existential
/// opened.
@MainActor
private func statedSpacing<W: SingleContentWrapper>(ofContentOf wrapper: W, context: RenderContext) -> ViewSpacing? {
    statedSpacing(ofView: wrapper.wrappedContent, context: context)
}

/// ``statedSpacing(ofView:context:)`` of a view held as an existential, opened.
/// Named apart from it, not an overload: inside the opener, an overload taking
/// `any View` would be chosen over the generic one and call itself for ever.
@MainActor
private func statedSpacing(ofErased view: any View, context: RenderContext) -> ViewSpacing? {
    func open<V: View>(_ opened: V) -> ViewSpacing? { statedSpacing(ofView: opened, context: context) }
    return open(view)
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
        // conformance cast of any child and nothing allocated. A child that
        // may state one only on edges this row does not read — a column of
        // a view and a spacer — is not one that can (`mayStateSpacing(_:along:)`).
        var spacers: UInt64 = 0
        var othersMayState = false
        for (index, child) in children.enumerated() {
            if child.isSpacer, index < UInt64.bitWidth {
                spacers |= 1 << UInt64(index)
            } else if child.isSpacer || mayStateSpacing(child, along: axis) {
                othersMayState = true
            }
        }
        guard othersMayState else {
            self = StackGaps(uniform: uniform, besideSpacers: spacers)
            return
        }
        var anyStated = false
        let preferences = children.map { child -> ViewSpacing? in
            guard child.isSpacer || mayStateSpacing(child, along: axis) else { return nil }
            let stated = statedSpacing(of: child, context: context)
            if stated != nil { anyStated = true }
            return stated
        }
        self = anyStated ? StackGaps(uniform: uniform, preferences: preferences, along: axis) : StackGaps(uniform: uniform)
    }
}
