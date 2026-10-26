//  🖥️ TUI — A Terminal UI framework for Swift
//  ChildView.swift
//
//  A child as a container's two-pass layout sees it: measured, then rendered
//  at the size it was given. Split out of `ChildInfo.swift`, which had reached
//  the file-length ceiling.
//
//  Created by LAYERED.work
//  License: MIT

import TUICore

/// A type-erased wrapper for a child view that enables two-pass layout.
///
/// This wrapper stores the view and allows measuring without rendering,
/// then rendering with a specific size allocation.
@MainActor
public struct ChildView {
    /// The wrapped child, stored as an existential so the (often large,
    /// deeply-generic) view value is boxed ONCE here rather than copied into a
    /// pair of measure / render closure contexts. `measureChild` / `renderChild`
    /// open it back to a concrete type via implicit existential opening.
    private let view: any View
    /// The type whose name forms this child's identity-path component, or `nil`
    /// when the child descends under the parent identity (no disambiguation).
    private let identityType: Any.Type?
    private let childIndex: Int
    /// When set, the child's identity is keyed by this stable string (a
    /// `ForEach` element's id) instead of `childIndex` — identity then follows
    /// the element across reorders, as SwiftUI's `ForEach` contract requires.
    private let identityKey: String?
    /// The STATIC tuple slot of the provider this keyed child was spliced
    /// from, or `ProviderSlot.unnamespaced` for a child that was never spliced
    /// (a lone `ForEach` as a container's whole content) or is positionally
    /// identified.
    ///
    /// The identity namespace for sibling providers: two `ForEach` loops in
    /// one container whose rows share a content type and overlapping id
    /// strings would otherwise carry byte-identical identities — colliding in
    /// `StateStorage` and cross-serving each other's memoized row buffers.
    /// The slot is the provider's position in the enclosing `@ViewBuilder`
    /// tuple, which is stable however many children its siblings flatten to
    /// (an `if` occupies its slot whether or not it renders) — so reorders
    /// WITHIN a loop still keep identity through the key, exactly as before.
    /// Folded into the identity only, never into ``identityChildKey``, which
    /// scroll seeking matches against the raw user id.
    ///
    /// A keyed child a splice RESOLVED — one a deeper splice had already
    /// namespaced, or one under an `if`/`else` branch — is stamped with a slot
    /// too, but that stamp is never read into a key again (the resolved
    /// identity wins): it marks the row as addressed, so the next splice out
    /// keeps its identity instead of flattening it back to a slot-prefixed key.
    /// See `spliced(fromSlot:under:branched:)`.
    ///
    /// A keyed row that an `if`/`else` resolved for itself, before any splice saw
    /// it, carries `ProviderSlot.resolvedInBranch` for the same reason. In `Group
    /// { if … else … }` beside a sibling the `Group` has no branch label, so the
    /// mark is all that tells the splice this row's identity holds a branch step.
    /// It is a mark in this field rather than a field of its own because the
    /// struct's size is load-bearing (below). The splice decides on the mark and
    /// never on whether `resolvedIdentity` is set: the child memo resolves a
    /// loop's rows from sixteen rows on, and those rows still take the flat key,
    /// so deciding on the identity would move them as the loop grew past fifteen.
    ///
    /// An `Int32` with sentinels (`ProviderSlot`) rather than `Optional<Int>`, and it is
    /// load-bearing: the optional grew the struct from 97 to 105 bytes (a
    /// 96→112 stride step), and this struct is built and copied per child per
    /// pass — the growth alone cost the all-invalidating `churn` scenario
    /// ~16% of its frame. The `Int32` packs into existing padding: 97 again.
    ///
    /// - Note: The struct measures **105 bytes / 112 stride** today, not the
    ///   97 above — later fields have re-crossed the boundary. Shrinking it
    ///   back was tried on 2026-08-25 and **measured as nothing**: the only
    ///   way down is to shrink `childIndex` and `spacerMinLength` to `Int32`
    ///   too (a pure field REORDER measures 108/112, i.e. no help at all),
    ///   and those conversions cost per access what the smaller copy saves —
    ///   88 bytes/stride read `churn` +4.3% against a same-binary null test
    ///   of +3.7% on that scenario, with every other scenario flat. So the
    ///   number above is history, not a lever: do not re-derive it without a
    ///   clean-built A/B on both sides (§41.1 of the performance profile).
    private let providerSlot: Int32

    /// The values of `providerSlot` that are not a tuple slot.
    private enum ProviderSlot {
        /// Nothing has namespaced this child: a row straight out of its
        /// `ForEach`, or a positional child.
        static let unnamespaced: Int32 = -1
        /// A keyed row an `if`/`else` resolved for itself: its identity holds the
        /// branch step, which a flat slot-prefixed key has nowhere to put. It
        /// always has a `resolvedIdentity`.
        static let resolvedInBranch: Int32 = -2
    }

    /// The identity this child renders and measures under, when it has been
    /// resolved ahead of use — see ``resolvingIdentity(under:)``. `nil` means
    /// ``childContext(_:)`` derives it from the context it is given.
    private let resolvedIdentity: ViewIdentity?

    /// Whether this child is a Spacer.
    public let isSpacer: Bool

    /// The minimum length of this spacer (only relevant if isSpacer is true).
    public let spacerMinLength: Int?

    /// The child's explicit z-index (`0` unless set via `View.zIndex(_:)`).
    /// Overlapping containers like `ZStack` draw children in ascending order
    /// of this value; ties keep their original tree order.
    public let zIndex: Double

    /// Whether this child carries an explicit alignment guide (set via
    /// `View.alignmentGuide(_:computeValue:)`).
    ///
    /// A stored flag rather than a cast: aligning containers ask it of every
    /// child on every frame, and it is `false` for all of them in almost every
    /// tree. Only when it is `true` does a container reach for the guide
    /// itself, through ``wrappedView``.
    public let providesAlignmentGuide: Bool

    /// Whether this child's type MAY carry a layout value — a
    /// `.layoutPriority(_:)` — read once from the static witness
    /// ``View/_providesLayoutValues``: a stack asks every child for its
    /// priority on every pass, and this answers `false` for almost all of
    /// them with a load rather than a witness call through the existential.
    /// Only when it is `true` is the view walked for the value, and the walk
    /// asks the witness of each view it passes, so a wrapper put round the
    /// member since (``rewrapped(by:)``, ``modified(by:)``) that lays it out
    /// anew still hides the priority. Stored after the alignment-guide flag,
    /// in what was the struct's tail padding: its stride stays 128 bytes.
    package let providesLayoutValues: Bool

    /// Whether `view` is an `if`'s default transition round the member
    /// (``transitioningByDefault()``), which ``wrappedView`` looks through.
    /// Asked by a cast, it was a conformance check on every child of every
    /// stack each time a stack read its children — a few per cent of a frame.
    /// A flag beside the two above.
    package let isDefaultTransitioned: Bool

    /// Whether this child's TYPE says it takes all the room it is offered on
    /// both axes, whatever its content — ``View/_fillsItsOffer``, read once.
    /// A column whose only filling child this is need not measure it to deal
    /// the column out (`_VStackCore`'s render): the deal gives it what is left
    /// whatever it would say, and its measure is a walk of all its content.
    /// A copy that puts anything round the view (``rewrapped(by:)``,
    /// ``modified(by:)``, ``transitioningByDefault()``) drops it: the wrapper
    /// may lay the view out anew.
    package let fillsItsOffer: Bool

    /// Whether this child is the slot a `nil` keeps for a view still leaving
    /// from there (`DepartureSlot`, made by ``departing(_:identityType:)``),
    /// rather than a view that is present.
    ///
    /// An eager stack lays such a child out nowhere — the view has gone, and
    /// SwiftUI's stack closes up at once — and draws its parting picture
    /// where the view last was (`ChildGlide`). A flag beside the four above,
    /// in the struct's tail padding: its stride stays 128 bytes. Carried by
    /// every copy, as a wrapper put round the slot draws the same picture.
    package let isDeparting: Bool

    /// Resolves a child's spacer flag and minimum length without a speculative
    /// runtime conformance cast on the common (non-spacer) path.
    ///
    /// The static witness ``View/_isSpacer`` answers the detection per type
    /// (`false` for everything but `Spacer` and a `Subview`); only the rare
    /// spacer is then cast to `SpacerProtocol` to read its `minLength`.
    /// A `Subview` may stand for a spacer or for anything else, so it is asked
    /// which (``LayoutTraitsForwarding``), after the cast a real spacer passes.
    static func spacerInfo<V: View>(of view: V) -> (isSpacer: Bool, minLength: Int?) {
        guard V._isSpacer else { return (false, nil) }
        if let spacer = view as? SpacerProtocol { return (true, spacer.minLength) }
        if let proxy = view as? LayoutTraitsForwarding {
            let member = proxy.forwardedChild
            return (member.isSpacer, member.spacerMinLength)
        }
        return (true, nil)
    }

    /// Resolves a child's z-index without a speculative runtime conformance
    /// cast on the common path — same shape as ``spacerInfo(of:)``, using the
    /// static witness ``View/_providesZIndex``.
    ///
    /// The walk is ``throughWrappers(_:as:)``'s, stopping also at a proxy for a
    /// member resolved elsewhere (``LayoutTraitsForwarding``), whose z-index is
    /// the member's — through a modifier written on the proxy, too, as SwiftUI
    /// keeps it (measured: `$0.padding(0)` still draws on top).
    static func zIndexInfo<V: View>(of view: V) -> Double {
        guard V._providesZIndex else { return 0 }
        var current: any View = view
        while true {
            if let found = current as? ZIndexProviding { return found.zIndexValue }
            if let proxy = current as? LayoutTraitsForwarding { return proxy.forwardedChild.zIndex }
            guard let wrapper = current as? any SingleContentWrapper else { return 0 }
            current = wrapper.wrappedContent
        }
    }

    /// Whether a child carries an explicit alignment guide: the static witness
    /// ``View/_providesAlignmentGuide``, except that a proxy for a member
    /// resolved elsewhere (``LayoutTraitsForwarding``), whose witness can only
    /// say it MAY, answers with the member's flag.
    ///
    /// The cast is reached only past the witness, so a child with no guide —
    /// almost every child — pays nothing for it.
    static func guideInfo<V: View>(of view: V) -> Bool {
        guard V._providesAlignmentGuide else { return false }
        guard let proxy = view as? LayoutTraitsForwarding else { return true }
        return proxy.forwardedChild.providesAlignmentGuide
    }

    /// Wraps `view` as a child that descends under its parent's identity.
    ///
    /// The transparent form: no identity component of its own, so the view
    /// keeps whatever identity the parent already established. Use it for a
    /// container's single content view, where there are no siblings to tell
    /// apart. A child that has siblings needs ``init(_:childIndex:)`` (or
    /// ``init(_:identityType:key:)`` for `ForEach` rows) so each gets a
    /// distinct identity and its own `@State`.
    ///
    /// The layout witnesses — spacer, z-index, alignment guide — are read
    /// once here from the static `View` witnesses rather than by casting on
    /// every layout pass.
    ///
    /// - Parameter view: The child view to wrap.
    public init<V: View>(_ view: V) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = Self.guideInfo(of: view)
        self.providesLayoutValues = V._providesLayoutValues
        self.fillsItsOffer = V._fillsItsOffer
        self.view = view
        self.identityType = nil
        self.childIndex = 0
        self.identityKey = nil
        self.providerSlot = ProviderSlot.unnamespaced
        self.resolvedIdentity = nil
        self.isDefaultTransitioned = false
        self.isDeparting = false
    }

    /// Creates a child view wrapper with an explicit child index for identity propagation.
    ///
    /// Use this initializer when wrapping children from a `TupleView` or similar
    /// container so that each child receives a unique `ViewIdentity` during
    /// measure and render passes.
    ///
    /// - Parameters:
    ///   - view: The child view to wrap.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View>(_ view: V, childIndex: Int) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = Self.guideInfo(of: view)
        self.providesLayoutValues = V._providesLayoutValues
        self.fillsItsOffer = V._fillsItsOffer
        self.view = view
        self.identityType = V.self
        self.childIndex = childIndex
        self.identityKey = nil
        self.providerSlot = ProviderSlot.unnamespaced
        self.resolvedIdentity = nil
        self.isDefaultTransitioned = false
        self.isDeparting = false
    }

    /// Full-field copy initializer backing ``reindexed(to:providerSlot:)``.
    private init(
        view: any View,
        identityType: Any.Type?,
        childIndex: Int,
        identityKey: String?,
        providerSlot: Int32,
        isSpacer: Bool,
        spacerMinLength: Int?,
        zIndex: Double,
        providesAlignmentGuide: Bool,
        providesLayoutValues: Bool,
        resolvedIdentity: ViewIdentity? = nil,
        isDefaultTransitioned: Bool = false,
        fillsItsOffer: Bool = false,
        isDeparting: Bool = false
    ) {
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = identityKey
        self.providerSlot = providerSlot
        self.isSpacer = isSpacer
        self.spacerMinLength = spacerMinLength
        self.zIndex = zIndex
        self.providesAlignmentGuide = providesAlignmentGuide
        self.providesLayoutValues = providesLayoutValues
        self.resolvedIdentity = resolvedIdentity
        self.isDefaultTransitioned = isDefaultTransitioned
        self.fillsItsOffer = fillsItsOffer
        self.isDeparting = isDeparting
    }

    /// This child with its identity under `parent` worked out now, so the
    /// walks that use it share one identity node instead of each deriving
    /// its own — which, for a keyed row, was a namespaced key string and a
    /// node allocation per child per walk, five times a frame for a stack
    /// inside a scroll view. Only meaningful where every later use is under
    /// the same parent, which is what the per-pass child memo guarantees:
    /// its key carries the parent identity.
    func resolvingIdentity(under parent: ViewIdentity) -> Self {
        guard let identityType else { return self }
        // The identity directly, rather than through a throwaway `RenderContext`
        // built only to carry it. Constructing one is eleven stored properties
        // including the whole `EnvironmentValues`, which was affordable while
        // this ran on the memoised `ForEach` path alone and is not now that
        // every spliced child resolves.
        let resolved =
            resolvedIdentity
            ?? Self.identity(
                of: identityType, index: childIndex, key: identityKey, slot: providerSlot, under: parent)
        return Self(
            view: view, identityType: identityType, childIndex: childIndex,
            identityKey: identityKey, providerSlot: providerSlot, isSpacer: isSpacer,
            spacerMinLength: spacerMinLength, zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolved, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
    }

    /// This child as the content of a conditional's branch whose identity is
    /// `branch` — the identity `ConditionalView.renderToBuffer` renders that
    /// branch's content at, so the flattened and whole-view paths agree.
    ///
    /// ``resolvingIdentity(under:)``, except for a TRANSPARENT child (no step
    /// of its own: the branch was one plain view). That one is not left
    /// untouched but pinned to `branch` itself. Left untouched it derives its
    /// identity later from the context the container renders it in, which is
    /// the container's own whichever branch it came from — and two branches at
    /// one identity share a `@State` box. A child that already carries a
    /// resolved identity keeps it: it was resolved under this branch, or under
    /// a deeper one (a nested conditional, a memoised `ForEach`).
    ///
    /// A keyed row nothing has namespaced is also marked
    /// `ProviderSlot.resolvedInBranch`. Its identity now holds the branch step
    /// and a flat slot-prefixed key cannot, so a tuple splice further out has to
    /// keep it. Unmarked, `VStack { Text("h"); Group { if a { ForEach(ids) {
    /// Row($0) } } else { ForEach(ids) { Row($0) } } } }` flattened both arms'
    /// rows onto one `Row[1#id]` each, and the arm drawn second read the first
    /// arm's `@State`. The mark goes on in the construction that resolves the
    /// row, so it costs no extra copy.
    func resolvingIdentity(inBranch branch: ViewIdentity) -> Self {
        guard let identityType else {
            guard resolvedIdentity == nil else { return self }
            return Self(
                view: view, identityType: nil, childIndex: childIndex,
                identityKey: identityKey, providerSlot: providerSlot, isSpacer: isSpacer,
                spacerMinLength: spacerMinLength, zIndex: zIndex,
                providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
                resolvedIdentity: branch, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
        }
        guard let identityKey, providerSlot == ProviderSlot.unnamespaced else {
            return resolvingIdentity(under: branch)
        }
        return Self(
            view: view, identityType: identityType, childIndex: childIndex,
            identityKey: identityKey, providerSlot: ProviderSlot.resolvedInBranch,
            isSpacer: isSpacer, spacerMinLength: spacerMinLength, zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolvedIdentity ?? branch.child(erasedType: identityType, key: identityKey), isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
    }

    /// This child with its identity fixed now, in `scope`: under it, or AT it
    /// when the child adds no step of its own.
    ///
    /// For a child handed out somewhere other than the container that resolved
    /// it — a `Subview`, a member of a `SubviewsCollection` placed in another
    /// stack. A `ChildView` otherwise derives its identity from whatever
    /// context it is later measured and rendered in, which would be the other
    /// container's, so two proxies of one member placed in different places
    /// would be two views, and a member and the view the transform built
    /// beside it could land on one identity and share a `@State` box.
    ///
    /// The rule a conditional's branch pins its children by
    /// (``resolvingIdentity(inBranch:)``), for the same reason: a transparent
    /// child is pinned to `scope` itself, a keyed row is marked as resolved so
    /// a later splice keeps its identity, and anything already resolved stays
    /// where it was.
    package func pinningIdentity(to scope: ViewIdentity) -> Self {
        resolvingIdentity(inBranch: scope)
    }

    /// The identity ``pinningIdentity(to:)`` (or any earlier resolution) fixed
    /// for this child, or `nil` when it still derives one from its context.
    package var pinnedIdentity: ViewIdentity? { resolvedIdentity }

    /// The static slot of the outermost tuple this keyed child was spliced out
    /// of — each splice stamps its own slot over the one before — or `nil` for
    /// a child no tuple spliced. What tells two sibling providers' keyed rows
    /// apart when their keys are spelled alike (`FlattenedRowIDs`).
    package var spliceSlot: Int? { providerSlot >= 0 ? Int(providerSlot) : nil }

    /// This child — pinned already — as one of the views a `ForEach` row of
    /// several hands its container: keyed by the row's element, so a seek for
    /// the element and a container placing the loop's rows find it under that
    /// key, at the identity it was pinned to.
    ///
    /// Marked as resolved (`ProviderSlot.resolvedInBranch`) for the reason a
    /// branch's keyed row is: a tuple splice further out then keeps its
    /// identity, rather than flattening it to a slot-prefixed key every member
    /// of the row would share.
    package func keyedAsMember(ofRowKeyed key: String) -> Self {
        assert(resolvedIdentity != nil, "a row's member is pinned before it is keyed")
        return Self(
            view: view, identityType: identityType ?? type(of: view), childIndex: childIndex,
            identityKey: key, providerSlot: ProviderSlot.resolvedInBranch, isSpacer: isSpacer,
            spacerMinLength: spacerMinLength, zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolvedIdentity, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
    }

    /// This child with `modifier` wrapped around it — what a provider hands
    /// back when the modifier was written on the PROVIDER rather than on each
    /// of the members it resolves to.
    ///
    /// Everything but the view is carried across unchanged, which is the point:
    /// the identity a member already resolved to, its spacer flag, its z-index
    /// and its alignment-guide flag are properties of the MEMBER, and a wrapper
    /// now standing in front of it does not change any of them. Re-reading them
    /// off the wrapper would answer `false` / `0` to all three, because no
    /// single-content wrapper forwards the static `View` witnesses — so
    /// `HStack { Group { Text("A"); Spacer() }.padding() }` would quietly lose
    /// its spacer.
    /// This child inside a copy of `wrapper` — ``modified(by:)`` for the
    /// wrappers that are not `BufferModifier`s.
    ///
    /// Everything but the view is carried across unchanged, for the reason
    /// ``modified(by:)`` spells out: the identity a member already resolved to,
    /// its spacer flag, its z-index and its alignment-guide flag are properties
    /// of the MEMBER, and a wrapper now standing in front of it does not change
    /// any of them. The spacer flag is the one with teeth — measured in the
    /// real framework, a `Spacer` inside a MODIFIED `Group` still reaches the
    /// enclosing stack as a spacer, and re-reading the flag off the wrapper
    /// would answer `false`.
    ///
    /// What a wrapper sets itself is the exception: a z-index wrapper's value
    /// (``ZIndexProviding``) is the member's z-index now, the outermost one
    /// winning as it does on a single view, and a layout-value wrapper (a
    /// `.layoutPriority(_:)`) makes the member one that states a layout value,
    /// so `Group { a; b }.zIndex(1)` and `.layoutPriority(1)` reach each
    /// member, as SwiftUI's do.
    ///
    /// The existential is opened by ``SingleContentWrapper/rewrapping(_:)``
    /// being generic, so no cast happens here and nothing is boxed twice.
    package func rewrapped(by wrapper: some ContentRewrapping) -> Self {
        let wrapped = wrapper.rewrapping(view)
        return Self(
            view: wrapped,
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: providerSlot,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: (wrapper as? ZIndexProviding)?.zIndexValue ?? zIndex,
            providesAlignmentGuide: providesAlignmentGuide,
            providesLayoutValues: providesLayoutValues || type(of: wrapped)._providesLayoutValues,
            resolvedIdentity: resolvedIdentity, isDeparting: isDeparting)
    }

    /// A copy that draws its view through an `if`'s default transition — see
    /// `_DefaultTransitionView`. Everything read off the view is kept.
    package func transitioningByDefault() -> Self {
        func wrapped<V: View>(_ view: V) -> any View { _DefaultTransitionView(content: view) }
        return Self(
            view: wrapped(view),
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: providerSlot,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolvedIdentity, isDefaultTransitioned: true, isDeparting: isDeparting)
    }

    package func modified<M: BufferModifier>(by modifier: M) -> Self {
        // Implicit existential opening, not a cast: passing the `any View` to a
        // generic parameter binds `V` to its dynamic type, so what is stored is
        // the concrete `ModifiedView<V, M>` the render path measures and
        // renders. It is NOT `ModifiedView<any View, M>`, which would not even
        // compile — an existential does not conform to the protocol it erases.
        func wrapped<V: View>(_ view: V) -> any View {
            ModifiedView(content: view, modifier: modifier)
        }
        return Self(
            view: wrapped(view),
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: providerSlot,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolvedIdentity, isDeparting: isDeparting)
    }

    /// A copy whose positional identity is rebased to `index`, and whose
    /// keyed identity is namespaced by the provider's static slot.
    ///
    /// When a provider's flattened children are spliced into an enclosing
    /// container's child list, their identity must reflect the FLATTENED
    /// position — two same-typed children contributed by different providers
    /// (two `Group`s, two `if` branches) would otherwise carry identical
    /// (type, inner-index) identities and collide in `StateStorage` (the
    /// second silently adopts the first's state and focus slots). Children
    /// with a stable `identityKey` (`ForEach` rows) keep it — identity must
    /// follow the element across reorders — but take the provider's slot as a
    /// namespace, because two sibling `ForEach` loops with overlapping ids
    /// are the same collision in keyed form (see ``providesAlignmentGuide``). A child
    /// with no identity type adopts its view's dynamic type, matching what it
    /// would get as a direct tuple child.
    func reindexed(to index: Int, providerSlot slot: Int) -> Self {
        reindexed(to: index, providerSlot: slot, under: nil)
    }

    /// This child addressed as `(its view's type, 0)` under `parent` if it has
    /// no address of its own — a TRANSPARENT child, the form a provider hands
    /// back for one plain view — and unchanged otherwise.
    ///
    /// The step a tuple splice gives such a child anyway
    /// (``spliced(fromSlot:under:branched:)``), given where no splice runs: an
    /// optional that is a container's only content, whose `Group` of one view
    /// would otherwise render at the container's own identity. Pinning it is
    /// what lets the `nil` the optional becomes find that view's departure —
    /// see `DepartingSlotAddressing`.
    func addressedIfTransparent(under parent: ViewIdentity) -> Self {
        guard identityType == nil, identityKey == nil, resolvedIdentity == nil else { return self }
        return reindexed(to: 0, providerSlot: Int(ProviderSlot.unnamespaced), under: parent)
    }

    /// ``reindexed(to:providerSlot:)`` and ``resolvingIdentity(under:)`` in one
    /// construction.
    ///
    /// Fused because the splice does both, on every child of every provider, and
    /// each of them copies the whole struct — including the `any View`
    /// existential, so a separate call is a second retain and release per child
    /// for nothing. Passing `nil` is the plain reindex.
    func reindexed(to index: Int, providerSlot slot: Int, under parent: ViewIdentity?) -> Self {
        if let identityKey {
            // The slot prefix is the namespace; see ``providesAlignmentGuide``.
            let resolved = parent.map {
                $0.child(
                    erasedType: identityType ?? type(of: view),
                    key: slot >= 0 ? "\(slot)#\(identityKey)" : identityKey)
            }
            return Self(
                view: view,
                identityType: identityType,
                childIndex: childIndex,
                identityKey: identityKey,
                providerSlot: Int32(slot),
                isSpacer: isSpacer,
                spacerMinLength: spacerMinLength,
                zIndex: zIndex,
                providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
                resolvedIdentity: resolved, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
        }
        let resolvedType = identityType ?? type(of: view)
        return Self(
            view: view,
            identityType: resolvedType,
            childIndex: index,
            identityKey: nil,
            providerSlot: ProviderSlot.unnamespaced,
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: parent.map { $0.child(erasedType: resolvedType, index: index) }, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
    }

    /// This child as it leaves a provider that a `TupleView` is splicing in at
    /// static slot `slot` — the whole splice decision, in one place. `parent` is
    /// the provider's own identity step, carrying its branch when `branched`.
    ///
    /// Exactly one kind of entry is addressed from this level's slot alone. Every
    /// other kind keeps what the level below worked out, because only that level
    /// knew what told its children apart, and nothing handed up can rebuild it:
    ///
    /// - A keyed row nothing has namespaced yet, under no branch — a `ForEach`
    ///   that is itself the tuple element, or a `Group` or an `if` without `else`
    ///   holding one — takes the flat slot-prefixed key beside its parent's other
    ///   children. That is the hot shape, and it is injective: no other keyed row
    ///   comes out of this slot. A `Group` or an `if` holding an `if`/`else` of
    ///   loops does not qualify: the conditional below marked its rows
    ///   `ProviderSlot.resolvedInBranch`.
    /// - A keyed row that already carries a slot, or sits under a branch at this
    ///   level or one provider further in, keeps the identity it was resolved
    ///   to, or is resolved under `parent` with its inner slot still in its key.
    ///   Overwriting that slot with this one is what
    ///   put both loops of `Group { ForEach(0..<2); ForEach(0..<2) }` — spliced,
    ///   because a sibling sits beside the `Group` — on the same two identities,
    ///   and the row memo, which keys on identity and element, drew the first
    ///   loop's buffers where the second loop's rows belonged. A branch went the
    ///   same way: both arms of an `if`/`else` over one row type met on one key.
    /// - A positional child that is already resolved keeps its identity. It was
    ///   resolved under an inner provider's step, and re-resolving it under
    ///   `parent` at the index it had in there dropped that step: `Group { if a {
    ///   Counter() }; if b { Counter() } }` put both counters on `Counter.0` under
    ///   the `Group`, one `@State` box between them.
    /// - Any other positional child is resolved under `parent` at that index.
    ///
    /// A keyed row resolved here is stamped with `slot`, so the next splice out
    /// sees it as namespaced and keeps it. Keeping a resolved identity is as
    /// sound as the one-level resolution this always did: every provider in the
    /// framework builds its children in the context it is handed, so an identity
    /// resolved below sits under a scope descended from `parent`.
    func spliced(fromSlot slot: Int, under parent: ViewIdentity, branched: Bool) -> Self {
        guard let identityKey else {
            if resolvedIdentity != nil { return self }
            return reindexed(to: identityChildIndex ?? 0, providerSlot: slot, under: parent)
        }
        if providerSlot == ProviderSlot.unnamespaced, !branched {
            return reindexed(to: 0, providerSlot: slot, under: nil)
        }
        assert(
            providerSlot != ProviderSlot.resolvedInBranch || resolvedIdentity != nil,
            "a branch-resolved row lost its identity")
        let resolved =
            resolvedIdentity
            ?? parent.child(
                erasedType: identityType ?? type(of: view),
                key: providerSlot >= 0 ? "\(providerSlot)#\(identityKey)" : identityKey)
        return Self(
            view: view,
            identityType: identityType,
            childIndex: childIndex,
            identityKey: identityKey,
            providerSlot: Int32(slot),
            isSpacer: isSpacer,
            spacerMinLength: spacerMinLength,
            zIndex: zIndex,
            providesAlignmentGuide: providesAlignmentGuide, providesLayoutValues: providesLayoutValues,
            resolvedIdentity: resolved, isDefaultTransitioned: isDefaultTransitioned,
            fillsItsOffer: fillsItsOffer, isDeparting: isDeparting)
    }

    /// Creates a child wrapper that renders `view` but derives its per-child
    /// identity from a *different* type `IdentityType`.
    ///
    /// Used when a row is wrapped in a transparent helper (e.g. `_MemoizedRow`)
    /// that must not appear in the identity path: pass the wrapper as `view` and
    /// the original content type as `identityType`, so the child's
    /// `ViewIdentity` — and thus its `@State` / focus slots — is exactly what it
    /// would be unwrapped. The wrapper itself adds no identity (it is
    /// `Renderable`), so the inner content keeps the same identity either way.
    ///
    /// - Parameters:
    ///   - view: The (possibly wrapped) view to measure and render.
    ///   - identityType: The type whose name forms the identity path component.
    ///   - childIndex: The positional index used for identity disambiguation.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, childIndex: Int
    ) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = Self.guideInfo(of: view)
        self.providesLayoutValues = V._providesLayoutValues
        self.fillsItsOffer = V._fillsItsOffer
        self.view = view
        self.identityType = identityType
        self.childIndex = childIndex
        self.identityKey = nil
        self.providerSlot = ProviderSlot.unnamespaced
        self.resolvedIdentity = nil
        self.isDefaultTransitioned = false
        self.isDeparting = false
    }

    /// Creates a child wrapper whose per-child identity is keyed by a stable
    /// string (a `ForEach` element's id) under `identityType`, rather than by
    /// a positional index — see ``ViewIdentity/child(erasedType:key:)``.
    public init<V: View, IdentityType>(
        _ view: V, identityType: IdentityType.Type, key: String
    ) {
        (self.isSpacer, self.spacerMinLength) = Self.spacerInfo(of: view)
        self.zIndex = Self.zIndexInfo(of: view)
        self.providesAlignmentGuide = Self.guideInfo(of: view)
        self.providesLayoutValues = V._providesLayoutValues
        self.fillsItsOffer = V._fillsItsOffer
        self.view = view
        self.identityType = identityType
        self.childIndex = 0
        self.identityKey = key
        self.providerSlot = ProviderSlot.unnamespaced
        self.resolvedIdentity = nil
        self.isDefaultTransitioned = false
        self.isDeparting = false
    }

    /// The slot a `nil` keeps for a view still leaving from there, addressed
    /// as that view was: `(identityType, 0)` under the context it is resolved
    /// in, or transparent with no `identityType` (``isDeparting``).
    package static func departing<V: View>(_ view: V, identityType: Any.Type?) -> Self {
        Self(
            view: view, identityType: identityType, childIndex: 0, identityKey: nil,
            providerSlot: ProviderSlot.unnamespaced, isSpacer: false, spacerMinLength: nil,
            zIndex: 0, providesAlignmentGuide: false, providesLayoutValues: false,
            isDeparting: true)
    }

    /// The type of the view this child draws, as it draws it — wrappers and
    /// all. A load from the existential, which builds nothing.
    package var viewType: Any.Type { type(of: view) }

    /// What tells this child apart from its siblings — see ``ChildIdentityStep``.
    package var identityStep: ChildIdentityStep {
        ChildIdentityStep(
            type: identityType, index: childIndex, key: identityKey, slot: providerSlot,
            resolved: resolvedIdentity)
    }

    /// Whether this child's ``identityStep`` is `step`, asked without building
    /// one: a container that has not changed asks it of every child on every
    /// frame, and building the step copies — and retains — the key and the
    /// resolved identity to compare and drop them.
    package func hasIdentityStep(_ step: ChildIdentityStep) -> Bool {
        childIndex == step.index && providerSlot == step.slot
            && identityType.map(ObjectIdentifier.init) == step.type.map(ObjectIdentifier.init)
            && identityKey == step.key && resolvedIdentity?.structuralHash == step.resolved?.structuralHash
    }

    /// The identity a child of `type` at `index` — or keyed by `key`,
    /// namespaced by `slot` — has under `parent`: the step ``childContext(_:)``
    /// takes, for a child whose identity is worked out without a context.
    nonisolated static func identity(
        of type: Any.Type, index: Int, key: String?, slot: Int32, under parent: ViewIdentity
    ) -> ViewIdentity {
        guard let key else { return parent.child(erasedType: type, index: index) }
        return parent.child(erasedType: type, key: slot >= 0 ? "\(slot)#\(key)" : key)
    }

    /// The wrapped child view itself, for containers that need to inspect the
    /// original view value — e.g. `List` peeling a `.badge(_:)` wrapper off a
    /// row — rather than measure or render it.
    public var wrappedView: any View {
        guard isDefaultTransitioned, let wrapper = view as? any DefaultTransitionWrapping else { return view }
        return wrapper.transitionedView
    }

    /// The identity this child measures and renders under — the address that
    /// "Locating things without drawing them" §5a routes by — computed without
    /// building or rendering anything. Identical to the identity the child
    /// receives on the real measure/render paths (same `childContext`).
    public func identity(under context: RenderContext) -> ViewIdentity {
        renderContext(under: context).identity
    }

    /// The context this child measures and renders under: `context` with this
    /// child's identity step applied, and nothing else changed.
    ///
    /// For a container that hands the child to something *other than*
    /// ``measure(proposal:context:)`` / ``render(width:height:context:)`` and
    /// so cannot let those apply the step for it — `List` asking a `Section`
    /// child for its rows rather than for a buffer. This is not a variant of
    /// the render context: it is exactly the one those two methods use.
    public func renderContext(under context: RenderContext) -> RenderContext {
        childContext(context)
    }

    /// The stable `ForEach` key this child's identity is disambiguated by,
    /// or `nil` for positionally-identified children.
    public var identityChildKey: String? { identityKey }

    /// The key an explicit `View.id(_:)` bound to this child, or `nil` when
    /// nothing in its modifier chain bound one.
    ///
    /// Deliberately NOT folded into ``identityChildKey``: `.id(_:)` is a
    /// modifier, so the step it splices sits *below* this child's own and the
    /// child stays positionally identified. Reporting the tag as the child's
    /// identity key would tell every positional lookup — `LayoutPlacing`'s
    /// `ordinal(of:)` above all — that this child has no index to match.
    ///
    /// A cast rather than a stored field: this struct's size is load-bearing
    /// (see `providerSlot`), and the only caller is a scroll seek, which
    /// asks on the frames a `scrollTo` request arrives on and on no others.
    public var explicitIDKey: String? {
        (wrappedView as? ExplicitIDProviding)?.explicitIDKey
    }

    /// The id value an explicit `View.id(_:)` bound to this child — what
    /// ``explicitIDKey`` is the string of — or `nil`. A cast for the same
    /// reason; asked only by a scroll view reporting the row it shows to a
    /// `.scrollPosition(id:)` binding.
    public var explicitID: AnyHashable? {
        (wrappedView as? ExplicitIDProviding)?.explicitID
    }

    /// Whether this child is the seek target named by `key` — the one place
    /// the two spellings SwiftUI's `ScrollViewProxy.scrollTo(_:anchor:)`
    /// accepts are decided between.
    ///
    /// A child that HAS a stable identity answers by it and by nothing else:
    /// a `ForEach` row is identified by its element's `id`, so a `.id(_:)`
    /// written inside a row is not a second address for it. That is also what
    /// keeps the answer the same on every seek path — the uniform and anchored
    /// windows resolve a whole-`ForEach` stack from the data's keys and never
    /// build a row view, so a tag inside one is not theirs to see. Only an
    /// unkeyed child — a stack's own tuple children, which is where the tag is
    /// written — is asked for its tag, and only then is the cast behind
    /// ``explicitIDKey`` paid.
    ///
    /// `.tag(_:)` no longer follows that rule, and the difference is what the
    /// two modifiers are for: since 2026-09-20 a `.tag(_:)` on a `ForEach` row
    /// gives the row its `List` SELECTION value, overriding the element's
    /// `id`. It does not give the row an address — identity is still the `id`,
    /// which is what this matcher and every window resolve from.
    public func matchesSeekKey(_ key: String) -> Bool {
        if let identityKey { return identityKey == key }
        return explicitIDKey == key
    }

    /// The positional index this child's identity is disambiguated by, or
    /// `nil` when the child is keyed or descends transparently under the
    /// parent identity.
    public var identityChildIndex: Int? {
        (identityType == nil || identityKey != nil) ? nil : childIndex
    }

    /// Measures this child view without rendering.
    public func measure(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(view, proposal: proposal, context: childContext(context))
    }

    /// Renders this child view with the given size allocation.
    public func render(width: Int, height: Int, context: RenderContext) -> FrameBuffer {
        renderChild(view, width: width, height: height, context: childContext(context))
    }

    /// The context to measure / render the child in: the identity resolved
    /// ahead of use when there is one, else the parent context with this
    /// child's identity appended, or the parent context unchanged when
    /// `identityType` is `nil` (the no-disambiguation initializer).
    ///
    /// The resolved identity is asked for FIRST, before the transparent early
    /// return, because a transparent child can carry one: the single view of a
    /// lone `if`/`else` branch is pinned to its branch while adding no step of
    /// its own (``resolvingIdentity(inBranch:)``). Asked second, the pin was
    /// never read. Every other child with a resolved identity also has an
    /// identity type, so the order changes nothing for them; an unresolved
    /// typed child still pays two checks, a transparent one pays one more.
    private func childContext(_ context: RenderContext) -> RenderContext {
        if let resolvedIdentity {
            var copy = context
            copy.identity = resolvedIdentity
            return copy
        }
        guard let identityType else { return context }
        if let identityKey {
            // The slot prefix is injective: the slot is the digits before the
            // first "#", so no two (slot, key) pairs concatenate to one
            // string. `identityChildKey` stays the raw user key — scroll
            // seeking matches against it.
            let namespaced =
                providerSlot >= 0 ? "\(providerSlot)#\(identityKey)" : identityKey
            return context.withChildIdentity(erasedType: identityType, key: namespaced)
        }
        return context.withChildIdentity(erasedType: identityType, index: childIndex)
    }
}
