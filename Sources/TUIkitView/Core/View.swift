//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

/// The base protocol for all TUIkit views.
///
/// `View` is the central protocol in TUIkit and works similarly to `View` in SwiftUI.
/// It defines how components declare their structure and content.
///
/// Every View defines a `body` composed of other Views.
/// This enables a hierarchical, declarative UI description.
///
/// ## Dual Rendering System
///
/// TUIkit uses two rendering paths:
///
/// - **Composite views** implement `body` to compose other views.
///   The rendering system recurses into `body` to resolve the tree.
/// - **Primitive views** additionally conform to `Renderable` and
///   produce a ``FrameBuffer`` directly. They set `body: Never`
///   (which `fatalError`s if called) because their `body` is never used.
///
/// The free function `renderToBuffer(_:context:)` checks `Renderable`
/// first, then falls back to `body`. See `Renderable` for details.
///
/// ## Creating a composite view
///
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         Text("Hello, TUIkit!")
///     }
/// }
/// ```
///
/// ## Creating a primitive view
///
/// ```swift
/// struct MyPrimitive: View {
///     var body: Never { fatalError() }
/// }
///
/// extension MyPrimitive: Renderable {
///     func renderToBuffer(context: RenderContext) -> FrameBuffer {
///         FrameBuffer(text: "output")
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Like SwiftUI, all view operations are confined to the main actor.
/// This ensures thread-safe access to state, environment, and rendering.
@MainActor
public protocol View {
    /// The type of the body view.
    ///
    /// Swift automatically infers this type from the `body` implementation.
    /// Primitive views that conform to `Renderable` set this to `Never`.
    associatedtype Body: View

    /// The content and behavior of this view.
    ///
    /// Implement this property to define the structure of your view
    /// by composing other `View` types.
    ///
    /// For primitive views that conform to `Renderable`, set this
    /// to `Never` with a `fatalError` body. The rendering system will
    /// call `renderToBuffer(context:)` instead.
    @ViewBuilder
    var body: Body { get }

    /// Static witness: whether this view type is a spacer (the layout system's
    /// flexible filler — `Spacer`). `false` for every view but `Spacer`, which
    /// overrides it to `true`.
    ///
    /// The child layout path (`ChildView.init`, `makeChildInfo`) reads this
    /// per-type instead of probing each child with `as? SpacerProtocol` — an
    /// almost-always-failing runtime conformance cast on a hot path (`Spacer` is
    /// the sole conformer). When the witness is `true`, the rare spacer is cast
    /// to `SpacerProtocol` to read its `spacerMinLength`.
    ///
    /// `true` means MAY be, for a view that stands in for a child resolved
    /// elsewhere — a `Subview`, whose one type stands for every member — and
    /// which is asked when its `ChildView` is built (`LayoutTraitsForwarding`).
    static var _isSpacer: Bool { get }

    /// Static witness: whether this view type carries an explicit z-index (the
    /// wrapper `View.zIndex(_:)` produces). `false` for every view but
    /// `_ZIndexView`, which overrides it to `true`.
    ///
    /// `makeChildInfo` reads this per-type instead of probing each child with
    /// `as? ZIndexProviding` — an almost-always-failing runtime conformance cast
    /// (`_ZIndexView` is the sole conformer). When the witness is `true`, the
    /// rare z-index wrapper is cast to `ZIndexProviding` to read its
    /// `zIndexValue`. A `Subview` answers `true` as `_isSpacer` explains.
    static var _providesZIndex: Bool { get }

    /// Static witness: whether this view type carries an explicit alignment
    /// guide (the wrapper `View.alignmentGuide(_:computeValue:)` produces).
    /// `false` for every view but `_AlignmentGuideView`, which overrides it to
    /// `true`.
    ///
    /// Same shape and same reason as ``_providesZIndex``: the aligning
    /// containers consult a stored `Bool` per child and only cast the rare
    /// wrapper. Without it every child of every stack would pay an
    /// almost-always-failing conformance cast on the hottest path there is.
    /// A `Subview` answers `true` as `_isSpacer` explains.
    static var _providesAlignmentGuide: Bool { get }

    /// Static witness: whether this view type writes a container value — a
    /// `.tag(_:)` or a `.containerValue(_:_:)` — or wraps a view that does.
    /// `false` for every view but those two wrappers, which answer `true`, and
    /// the single-content wrappers around them, which forward their content's
    /// answer.
    ///
    /// Same shape and same reason as ``_providesZIndex``: a container asked for
    /// a subview's values reads them only when this says there are any, so a
    /// subview with none costs a constant rather than a walk of casts.
    static var _providesContainerValues: Bool { get }

    /// Static witness: whether this view type sets a layout value — a
    /// `.layoutPriority(_:)` or a `.layoutValue(key:value:)` — or wraps a view
    /// that does. `false` for every view but that wrapper, which answers
    /// `true`, a member's proxy, which MAY, and the single-content wrappers
    /// around them, which forward their content's answer.
    ///
    /// Same shape and same reason as ``_providesZIndex``: a stack asks every
    /// child for its priority, and one whose type says there is none answers
    /// with a constant rather than a walk of casts.
    static var _providesLayoutValues: Bool { get }

    /// Static witness: whether this view type may state a spacing preference
    /// of its own (a `ViewSpacing` other than the default) — because it is a
    /// `Layout` (whose `spacing(subviews:cache:)` says), or holds one where a
    /// row's `spacing: nil` would ask it: in a tuple, a loop, a `Group`, an
    /// `if`, or inside a wrapper that changes none of its edges. `false` for
    /// every other view.
    ///
    /// Same shape and same reason as ``_providesZIndex``: a row resolves its
    /// gaps per pair of neighbours only when its content's type says a child
    /// may state one (decisions B20), so a row of anything else — almost every
    /// row — asks no child anything.
    static var _statesSpacingPreference: Bool { get }

    /// Static witness: whether a container resolving this view may find other
    /// than ONE child in it — because it is a provider of children (a tuple, a
    /// `Group`, a loop, an `if`…), or a view of the app's own whose `body` is
    /// one (decisions D1S, B-D1S-6). `false` for a primitive, whose `body` is
    /// `Never`.
    ///
    /// A composite answers what its body answers — the default below — so the
    /// question follows the chain of `body` types to the first primitive or
    /// provider, a few witness calls with no cast. That is what lets a
    /// container take apart `struct Pair: View { var body: some View { a; b }
    /// }` as SwiftUI does, while a view whose body is a stack or a `Text` —
    /// almost every view — is answered `false` and kept the one child it
    /// always was, without its body being evaluated to find out
    /// (`compositeMembers(of:context:)`).
    static var _handsOverChildren: Bool { get }

    /// Static witness: whether this view type nominates something continuous
    /// about itself — that is, whether it conforms to ``Animatable``. `false`
    /// for every view but those, which get `true` from the constrained default
    /// below.
    ///
    /// Same shape and same reason as ``_isSpacer``, and the reason is measured:
    /// this is asked once per view per walk, on both the render and the measure
    /// side, and conformance-checking each one — even against a
    /// direct-mapped-by-metadata-pointer cache — cost a paired **+0.6% to +0.9%
    /// on `table`, `deep` and `kitchensink`** (41 reps, tight intervals). A tax
    /// on every app, including every app that animates nothing. As a static
    /// witness it is a constant the specialiser can fold away.
    ///
    /// Not to be implemented by hand: conform to ``Animatable`` instead.
    static var _isAnimatable: Bool { get }

    /// Static witness: this view at the value the animation store says to draw
    /// it at, or `nil` when nothing is moving.
    ///
    /// A witness rather than `view as? any Animatable` because the cast BOXES —
    /// a view struct is several words, so opening the existential heap-allocates
    /// once per animatable node per walk, and casting the result back is a
    /// second dynamic cast. With `.padding` and `.frame` animatable that is
    /// every layout node in the tree: it cost **+14% on `deep`**, whose whole
    /// shape is nested layout modifiers measured O(depth²) times.
    ///
    /// Here `Self` is concrete, so the store call is generic and nothing is
    /// boxed. Not to be implemented by hand.
    @MainActor
    static func _animated(_ view: Self, context: RenderContext, isMeasuring: Bool) -> Self?

    /// Static witness: this view rendered procedurally, or `nil` when it is a
    /// composite whose `body` should be descended into instead.
    ///
    /// A witness rather than `view as? Renderable` for the reason
    /// ``_isAnimatable`` is one, and this is the hotter of the two: the cast
    /// ran once per view per render, and `swift_dynamicCast` under it accounted
    /// for **4.5% of a frame** on the `fanout` scenario, 2.2% on `deep` and
    /// 1.0% on `kitchensink` (Instruments, Time Profiler, `--callers`). It is
    /// also the cast that succeeds most often, which is what makes it
    /// expensive rather than merely wasteful — a failing conformance check can
    /// stop at the metadata, a succeeding one builds the existential.
    ///
    /// Returning the BUFFER rather than the `Renderable` is the point: `Self`
    /// is concrete here, so the call is a direct one and nothing is boxed.
    /// Handing back `any Renderable` would keep the allocation this exists to
    /// remove.
    ///
    /// Not to be implemented by hand: conform to ``Renderable`` instead.
    @MainActor
    static func _renderSelf(_ view: Self, context: RenderContext) -> FrameBuffer?

    /// Static witness: this view's own measured size, or `nil` when it has no
    /// opinion and its `body` should be measured instead.
    ///
    /// The measure-side twin of ``_renderSelf(_:context:)``, replacing
    /// `view as? Layoutable` on the path deep nesting recurses through.
    ///
    /// Not to be implemented by hand: conform to ``Layoutable`` instead.
    @MainActor
    static func _measureSelf(
        _ view: Self, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize?
}

public extension View {
    /// Default: a view is not a spacer. `Spacer` overrides this.
    static var _isSpacer: Bool { false }

    /// Default: a view carries no explicit z-index. `_ZIndexView` overrides this.
    static var _providesZIndex: Bool { false }

    /// Default: a view sets no alignment guide. `_AlignmentGuideView` overrides
    /// this.
    static var _providesAlignmentGuide: Bool { false }

    /// Default: a view writes no container value. `.tag(_:)` and
    /// `.containerValue(_:_:)` override this.
    static var _providesContainerValues: Bool { false }

    /// Default: a view sets no layout value. `.layoutPriority(_:)` and
    /// `.layoutValue(key:value:)` override this.
    static var _providesLayoutValues: Bool { false }

    /// Default: a view states no spacing preference. A `Layout`'s view
    /// overrides this, and the views that hand one over forward it.
    static var _statesSpacingPreference: Bool { false }

    /// Default: what this view's `body` answers — to a container a view of the
    /// app's own is what its body is. A tuple, an `if`, a loop, a `Group` of
    /// those and a `Section` answer `true`; `Never` — a primitive's body —
    /// `false`.
    static var _handsOverChildren: Bool { Body._handsOverChildren }

    /// A view says nothing continuous about itself unless it is ``Animatable``.
    @inlinable
    static var _isAnimatable: Bool { false }

    /// A view with nothing continuous about it never needs substituting.
    @inlinable
    static func _animated(_ view: Self, context: RenderContext, isMeasuring: Bool) -> Self? {
        nil
    }

    /// Default: a view renders through its `body`, not procedurally.
    /// ``Renderable`` conformers override this.
    @inlinable
    @MainActor
    static func _renderSelf(_ view: Self, context: RenderContext) -> FrameBuffer? { nil }

    /// Default: a view has no size of its own; its `body` is measured instead.
    /// ``Layoutable`` conformers override this.
    @inlinable
    @MainActor
    static func _measureSelf(
        _ view: Self, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize? { nil }
}
