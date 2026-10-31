//  🖥️ TUI — A Terminal UI framework for Swift
//  BufferModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore

/// A modifier that transforms a view's rendered output.
///
/// `BufferModifier` works on the `FrameBuffer` level: it takes a rendered
/// buffer and returns a transformed buffer. This allows modifiers like
/// `.padding()` and `.frame()` to manipulate layout after rendering.
///
/// # Example
///
/// ```swift
/// struct MyModifier: BufferModifier {
///     func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
///         // transform the buffer
///         return buffer
///     }
/// }
/// ```
@MainActor
public protocol BufferModifier {
    /// Transforms a rendered buffer.
    ///
    /// - Parameters:
    ///   - buffer: The rendered content of the wrapped view.
    ///   - context: The rendering context.
    /// - Returns: The modified buffer.
    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer

    /// Transforms a rendered buffer, told which ``ModifiedView`` type encloses
    /// this modifier.
    ///
    /// Implement this INSTEAD of ``modify(buffer:context:)`` only when the
    /// modifier keys per-view state — an animation store entry, say — because
    /// `owner` is the discriminator such a key needs and the modifier's own
    /// type cannot supply it: `BackgroundModifier<Color>` is the same type
    /// whether it is the inner or the outer `.background` around one view,
    /// whereas `ModifiedView<Content, Modifier>` is generic over its content
    /// and so differs. Exactly why ``_animated(_:owner:context:isMeasuring:)``
    /// takes an owner too, and a witness rather than an existential cast for
    /// the same reason.
    ///
    /// The default ignores `owner` and calls ``modify(buffer:context:)``, which
    /// is the method to write for everything else.
    ///
    /// - Parameters:
    ///   - buffer: The rendered content of the wrapped view.
    ///   - context: The rendering context.
    ///   - owner: The enclosing ``ModifiedView``'s own type.
    /// - Returns: The modified buffer.
    func _modify(buffer: FrameBuffer, context: RenderContext, owner: Any.Type) -> FrameBuffer

    /// Static witness: whether this modifier type nominates something
    /// continuous about itself — that is, whether it conforms to ``Animatable``.
    ///
    /// The same shape and the same measured reason as ``View/_isAnimatable``,
    /// and it exists separately because a *conditional* conformance cannot
    /// supply that witness: `ModifiedView` is `Animatable` only when its
    /// modifier is, so Swift picks the unconstrained default for it and the
    /// answer would always be `false`. `ModifiedView` forwards to this instead,
    /// which stays a constant the specialiser can fold.
    ///
    /// Not to be implemented by hand: conform to ``Animatable`` instead.
    static var _isAnimatable: Bool { get }

    /// Static witness: whether an explicit alignment guide inside this
    /// modifier's content is still a guide of the modified view.
    ///
    /// `true` only for a modifier that lays its content out at an offset a
    /// guide can be translated by — padding, which is measured to pass a guide
    /// through in SwiftUI. Every other modifier answers `false`, and a guide
    /// inside it stops there: a guide is a position in its view's own
    /// dimensions, and reporting it through a modifier that moves or resizes
    /// the content without translating it would report a position from the
    /// wrong coordinate space. A conforming modifier's `ModifiedView` answers
    /// the context-carrying guide query itself.
    static var _translatesAlignmentGuides: Bool { get }

    /// Static witness: whether this modifier lays its content out exactly
    /// where the modified view is laid out — its own size, origin and
    /// identity — rewriting only what its content drew (an `.id`, a
    /// background, a shadow), so a guide inside it is the modified view's,
    /// unmoved, as SwiftUI's is through every single-child modifier.
    ///
    /// `false` by default: a modifier of the app's own that draws cells
    /// beside its content moves the content off its origin, and a guide that
    /// passed it unmoved would report the wrong position. See
    /// ``SingleContentWrapper/_keepsContentGeometry``.
    static var _keepsContentGeometry: Bool { get }

    /// Static witness: whether this modifier lays its content out anew —
    /// changes the size it is offered or reports — so that a priority written
    /// inside it (``View/layoutPriority(_:)``) is not the modified view's.
    /// `false` by default, and the modifier's `ModifiedView` passes its
    /// content's priority on; `true` for padding. SwiftUI's own split,
    /// measured: a priority survives `.foregroundStyle`, `.font`, `.opacity`,
    /// `.background`, `.id` and `.tag`, and is lost under `.padding` and
    /// `.frame` (`Tools/SwiftUIProbes/Layout priority/priority.out`).
    static var _changesLayout: Bool { get }

    /// Static witness: this modifier at the value the animation store says to
    /// draw it at, or `nil` when nothing is moving. See
    /// ``View/_animated(_:context:isMeasuring:)`` for why it is a witness
    /// rather than an existential cast.
    ///
    /// `owner` is passed in rather than taken as `Self` so the store key stays
    /// the `ModifiedView`'s own generic type — which distinguishes two of the
    /// same modifier nested around one view, where the modifier type alone
    /// would not.
    @MainActor
    static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self?

    /// The explicit identity key this modifier binds to its content, or `nil`
    /// — the key `View.id(_:)` plants, and nothing else.
    ///
    /// Surfaced because that key is otherwise invisible from OUTSIDE the
    /// modified view: `.id(_:)` splices its step into the identity of the
    /// subtree BELOW it, so the tagged child keeps whatever identity its
    /// position gave it and a container looking for the tag has nowhere to
    /// read it. A scroll seek is the container that needs it —
    /// `ScrollViewProxy.scrollTo(_:anchor:)` addresses `.id(_:)` tags in
    /// SwiftUI's own `ScrollViewReader` example.
    ///
    /// A requirement on the MODIFIER, forwarded by ``ModifiedView``, for the
    /// reason ``BufferModifier/_isAnimatable`` is one: a *conditional*
    /// conformance cannot supply a witness for `ModifiedView`, so the answer
    /// has to come from the modifier itself.
    ///
    /// Not to be implemented by hand outside `View.id(_:)`.
    var _explicitIDKey: String? { get }

    /// The id value `View.id(_:)` bound, of which ``_explicitIDKey`` is the
    /// string — see ``ExplicitIDProviding/explicitID``. Not to be implemented
    /// by hand outside `View.id(_:)`.
    var _explicitID: AnyHashable? { get }

    /// Adjusts the rendering context before the wrapped content is rendered.
    ///
    /// Override this method in modifiers that consume space (like padding)
    /// to reduce `availableWidth` or `availableHeight` so that flexible
    /// child views size themselves correctly.
    ///
    /// The default implementation returns the context unchanged.
    ///
    /// - Parameter context: The current rendering context.
    /// - Returns: The adjusted context for content rendering.
    func adjustContext(_ context: RenderContext) -> RenderContext

    /// The cells, per axis, that ``adjustContext(_:)`` offers the content
    /// past the modified view's own extent: a negative padding's, which lays
    /// its content out larger than the frame it reports and draws it past
    /// that frame. The measure takes them off the size it reports, and adds
    /// them to the proposal it hands the content.
    ///
    /// `(0, 0)` by default, a constant the specialiser folds: every other
    /// modifier offers its content at most what it was offered. Not to be
    /// implemented by hand outside padding.
    var _contentOverhang: (width: Int, height: Int) { get }
}

extension BufferModifier {
    /// Passes the context through unchanged.
    ///
    /// The default, and the right answer for any modifier that only rewrites
    /// the buffer its content produced. Override it when the modifier changes
    /// the space the content is being offered — padding and borders reduce
    /// `availableWidth`/`availableHeight` here so a flexible child fills the
    /// interior rather than the whole box and then overflows it.
    ///
    /// - Parameter context: The context this modifier was reached with.
    /// - Returns: The context its content should render under.
    public func adjustContext(_ context: RenderContext) -> RenderContext {
        context
    }

    /// A modifier that keys no per-view state has no use for its owner.
    @inlinable
    public func _modify(
        buffer: FrameBuffer, context: RenderContext, owner: Any.Type
    ) -> FrameBuffer {
        modify(buffer: buffer, context: context)
    }

    /// A modifier offers its content nothing past its own extent unless it is
    /// a negative padding.
    @inlinable
    public var _contentOverhang: (width: Int, height: Int) { (0, 0) }

    /// A modifier binds no identity key unless it is `View.id(_:)`'s.
    @inlinable
    public var _explicitIDKey: String? { nil }

    /// Nor an id value.
    @inlinable
    public var _explicitID: AnyHashable? { nil }

    /// A modifier says nothing continuous about itself unless it is
    /// ``Animatable``.
    @inlinable
    public static var _isAnimatable: Bool { false }

    /// A guide inside a modifier's content stops at the modifier unless the
    /// modifier translates it.
    @inlinable
    public static var _translatesAlignmentGuides: Bool { false }

    /// A modifier is not taken to keep its content where it is unless it
    /// says so.
    @inlinable
    public static var _keepsContentGeometry: Bool { false }

    /// A modifier draws its content where it lays out, at the size it was
    /// given, unless it says otherwise.
    @inlinable
    public static var _changesLayout: Bool { false }

    /// A modifier with nothing continuous about it never needs substituting.
    @inlinable
    public static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        nil
    }
}

extension BufferModifier where Self: Animatable {
    /// An ``Animatable`` modifier's data is substituted before its view
    /// renders, exactly as an animatable view's is.
    @inlinable
    public static var _isAnimatable: Bool { true }

    /// This modifier at the value the store says to draw it at.
    @MainActor
    public static func _animated(
        _ modifier: Self, owner: Any.Type, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        animatedValue(of: modifier, owner: owner, context: context, isMeasuring: isMeasuring)
    }
}

// MARK: - ModifiedView

/// A view that wraps another view with a modifier.
///
/// This is the return type of modifier methods like `.frame()` and `.padding()`.
/// It is created automatically — users don't instantiate this directly.
///
/// `ModifiedView` is a **primitive view**: it declares `body: Never`
/// and conforms to `Renderable`. The rendering system calls
/// `renderToBuffer(context:)` which first renders the
/// wrapped `content`, then applies the modifier's transformation.
/// The `body` property is never called.
///
/// - Important: This is framework infrastructure. Created automatically by
///   `.modifier()`. Do not instantiate directly.
public struct ModifiedView<Content: View, Modifier: BufferModifier>: View {
    /// The original view.
    public let content: Content

    /// The modifier to apply.
    ///
    /// A `var` only so an animatable modifier's data can be substituted before
    /// the view renders; nothing else mutates it.
    public var modifier: Modifier

    /// Creates a modified view.
    ///
    /// - Parameters:
    ///   - content: The original view.
    ///   - modifier: The modifier to apply.
    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }

    /// Never called — rendering is handled by `Renderable` conformance.
    public var body: Never {
        fatalError("ModifiedView renders via Renderable")
    }
}

// MARK: - ModifiedView Rendering

extension ModifiedView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let adjustedContext = modifier.adjustContext(context)
        let childBuffer = TUIView.renderToBuffer(content, context: adjustedContext)
        // `Self.self`, not `Modifier.self`: this type is generic over the
        // content, so it distinguishes two of the same modifier nested around
        // one view — which is the whole reason the owner is passed at all.
        var result = modifier._modify(
            buffer: childBuffer, context: context, owner: Self.self)

        // Overlay-layer safety net: if the modifier produced a buffer without
        // overlay layers but the wrapped content carried some, re-attach them.
        // Modifiers that reposition content (padding, …) attach their own
        // shifted layers, so this only fires for transform-in-place modifiers
        // (background, foreground colour, …) that leave content where it is.
        if result.overlays.isEmpty && !childBuffer.overlays.isEmpty {
            result.overlays = childBuffer.overlays
        }
        return result
    }
}

// MARK: - Seeing Through the Wrapper
//
// A `ModifiedView` stands between a container and the content it was handed,
// and there are two things the container must still be able to reach past it:
// the `.id(_:)` tag bound somewhere inside, and — when the content is several
// views rather than one — the members themselves. Both are the same idea from
// opposite ends of the wrapper, so they are stated together.
//
// They differ in ONE respect, and deliberately. `ExplicitIDProviding` is
// unconditional, because the tag it looks for can sit under any number of
// further `ModifiedView`s of any content type, so the answer has to be
// optional and the walk inward has to be a cast. `ChildViewProvider` is
// conditional, because a modifier on an ordinary single view genuinely has no
// members to offer and must stay as opaque as it ever was — which makes the
// witness a compile-time fact rather than a cast per child.
//
// The two compose, and the composition is load-bearing: `modified(by:)` puts a
// `ModifiedView` around each member it hands back, and that wrapper is
// unconditionally `ExplicitIDProviding`, so a `.id(_:)` written on a member of
// a `Group { … }.padding()` is still found by a seek — through the padding the
// re-wrapping added. Before the members were resolved at all, that tag was
// invisible: the pair arrived as one child wrapping a `Group`, which is not an
// `ExplicitIDProviding`.

/// This view's `View.id(_:)` tag: the key this modifier binds, else the one a
/// modifier further in bound.
///
/// The walk inward is the point — `.id(k).padding()` is a `ModifiedView` whose
/// own modifier is the padding, and SwiftUI finds that tag too. It costs
/// nothing on any frame but the one a seek arrives on, because that is the
/// only thing that asks.
/// The READ direction through this wrapper: what a container asking for a
/// z-index or an alignment guide walks. `.zIndex(1).padding(0)` kept neither
/// before, because the static witness that gates the walk answered `false` here
/// and the search never started.
///
/// Not ``ContentRewrapping`` — that is stated separately, below, and is a
/// different question with a different answer per wrapper.
extension ModifiedView: SingleContentWrapper {
    public var wrappedContent: Content { content }

    /// The modifier's answer (``BufferModifier/_keepsContentGeometry``).
    public static var _keepsContentGeometry: Bool { Modifier._keepsContentGeometry }
}

extension ModifiedView {
    /// A guide inside the content is the modified view's only when the
    /// modifier translates guides (``BufferModifier/_translatesAlignmentGuides``)
    /// — padding — or keeps its content where it is
    /// (``BufferModifier/_keepsContentGeometry``), and the content holds one.
    public static var _providesAlignmentGuide: Bool {
        (Modifier._translatesAlignmentGuides || Modifier._keepsContentGeometry) && Content._providesAlignmentGuide
    }

    /// A priority inside the content is the modified view's unless the
    /// modifier lays the content out anew (``BufferModifier/_changesLayout``):
    /// `.layoutPriority(1).background(…)` keeps it, `.layoutPriority(1)
    /// .padding()` does not, as in SwiftUI.
    public static var _providesLayoutValues: Bool {
        !Modifier._changesLayout && Content._providesLayoutValues
    }
}

extension ModifiedView: ExplicitIDProviding {
    public var explicitIDKey: String? {
        modifier._explicitIDKey ?? (content as? ExplicitIDProviding)?.explicitIDKey
    }

    public var explicitID: AnyHashable? {
        modifier._explicitID ?? (content as? ExplicitIDProviding)?.explicitID
    }
}

/// A modifier written on multi-view content applies to each MEMBER of it, not
/// to the content as a unit — SwiftUI states the rule for `Group` in so many
/// words ("The modifier applies to all members of the group — and not to the
/// group itself") and repeats it for `GridRow`.
///
/// Without this a modifier made its content opaque to child resolution, and the
/// enclosing container stopped seeing the members as its own children: a
/// `Group` of two `Text`s in an `HStack` drew as a row, and the same `Group`
/// carrying `.padding()` drew as a COLUMN, because the fallback in
/// ``resolveChildViews(from:context:)`` handed the stack one opaque child whose
/// buffer `TupleView` had already stacked vertically.
///
/// Conditional on the content, so nothing else changes: a modifier on an
/// ordinary single view is as opaque as it ever was, and the witness is a
/// compile-time fact rather than a cast per child.
///
/// - Note: `onDelete`/`onMove` need no exception here. They are declared on
///   `ForEach` and return a `ForEach`, so they never build a `ModifiedView` and
///   stay scoped to the collection, which is SwiftUI's `DynamicViewContent`
///   rule.
extension ModifiedView: ChildViewProvider where Content: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        let children = content.childViews(context: context)
        // A `nil` under `.id`, whose view drew a step below where a `nil` asks. Only
        // a key: a modifier that moves its content or draws has a picture of its own.
        if children.isEmpty, modifier._explicitIDKey != nil,
            let slot = departingSlot(throughStep: modifier.adjustContext, of: Content.self, context: context)
        {
            return [slot.modified(by: modifier)]
        }
        return children.map { $0.modified(by: modifier) }
    }

    /// The content's answer: whether the resolution is worth remembering is a
    /// property of how many children it produces, which the wrapper does not
    /// change.
    public var childViewsAreWorthMemoising: Bool { content.childViewsAreWorthMemoising }

    /// Forwarded, or a modified `if`/`else` would resolve both of its branches
    /// against one identity and the two arms would share a `@State` box — the
    /// defect ``ChildViewProvider/identityBranchLabel`` exists to prevent, one
    /// wrapper further out.
    public var identityBranchLabel: String? { content.identityBranchLabel }

    /// The content's answer: a modified `Section` is still a section to a
    /// container that keeps sections whole.
    public func staysWhole(in context: RenderContext) -> Bool { content.staysWhole(in: context) }
}

// MARK: - Layoutable

extension ModifiedView: Layoutable {
    /// Measures the wrapped content through the modifier without rendering it.
    ///
    /// `Renderable` views without a `Layoutable` conformance fall through to
    /// `measureChild`'s render-to-measure fallback (a single `renderToBuffer` —
    /// historically two, with a `naturalWidth + 8` flexibility probe since
    /// retired). Rendering to measure is a disaster for expensive content (an
    /// `Image` whose `renderToBuffer` runs the ASCII converter, for example)
    /// wrapped in even one `.padding()` or custom modifier — so forward instead.
    ///
    /// Forwards measurement to the content under the modifier's
    /// `adjustContext`, then adds the per-axis delta the modifier shrank
    /// off back onto the reported size. For modifiers that don't adjust
    /// the context — colour, background, etc. — the delta is zero and we
    /// just report the child's size. For modifiers that do (padding), the
    /// caller sees the post-modifier dimensions, which matches what
    /// `renderToBuffer` would produce.
    ///
    /// A negative padding offers its content MORE than it was offered
    /// (`BufferModifier._contentOverhang`): the delta is then negative, the
    /// proposal grows by it and the reported size shrinks by it, never below
    /// zero, as SwiftUI's does.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let adjustedContext = modifier.adjustContext(context)
        let overhang = modifier._contentOverhang
        let widthDelta =
            max(0, context.availableWidth + overhang.width - adjustedContext.availableWidth) - overhang.width
        let heightDelta =
            max(0, context.availableHeight + overhang.height - adjustedContext.availableHeight) - overhang.height

        // Propagate the modifier's shrink to the proposal too, so a flex
        // child still treats the remaining space as its budget.
        var adjustedProposal = proposal
        if let proposedWidth = proposal.width {
            adjustedProposal = ProposedSize(
                width: max(0, proposedWidth - widthDelta),
                height: proposal.height
            )
        }
        if let proposedHeight = adjustedProposal.height {
            adjustedProposal = ProposedSize(
                width: adjustedProposal.width,
                height: max(0, proposedHeight - heightDelta)
            )
        }

        let childSize = measureChild(content, proposal: adjustedProposal, context: adjustedContext)
        return ViewSize(
            width: max(0, childSize.width + widthDelta),
            height: max(0, childSize.height + heightDelta),
            isWidthFlexible: childSize.isWidthFlexible,
            isHeightFlexible: childSize.isHeightFlexible
        )
    }
}

// MARK: - Animating a modifier

extension ModifiedView: Animatable where Modifier: Animatable {
    /// A modified view's animatable data is its modifier's.
    ///
    /// The general route by which a *modifier* animates — `.padding`,
    /// `.offset`, and any `BufferModifier` an app writes. It is where SwiftUI
    /// puts it too (`ModifiedContent: Animatable where Modifier: Animatable`),
    /// and it means a modifier author declares one property rather than
    /// learning anything about the render pipeline.
    public var animatableData: Modifier.AnimatableData {
        get { modifier.animatableData }
        set { modifier.animatableData = newValue }
    }
}

extension ModifiedView {
    /// Forwarded from the modifier.
    ///
    /// **Unconditional**, deliberately: the `Animatable` conformance above is
    /// conditional, so a witness declared inside it cannot satisfy the
    /// *unconditional* `View` conformance — Swift falls back to the `false`
    /// default and every animated modifier silently stops animating. Which is
    /// exactly what happened, and what the padding test caught.
    @inlinable
    public static var _isAnimatable: Bool { Modifier._isAnimatable }

    /// Forwarded to the modifier, for the same reason and with the same
    /// unconditional placement as ``_isAnimatable``.
    @MainActor
    public static func _animated(
        _ view: Self, context: RenderContext, isMeasuring: Bool
    ) -> Self? {
        guard let animated = Modifier._animated(
            view.modifier, owner: Self.self, context: context, isMeasuring: isMeasuring)
        else { return nil }
        var copy = view
        copy.modifier = animated
        return copy
    }
}
