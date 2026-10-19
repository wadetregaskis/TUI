//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - State Storage

/// Persistent store for `@State` values, indexed by `ViewIdentity`.
///
/// `StateStorage` is the backbone of TUIkit's state persistence across render
/// passes. It maps each `@State` property to a stable key derived from the
/// view's structural position in the tree (`ViewIdentity`) and the property's
/// declaration order within that view.
///
/// ## Lifecycle
///
/// - **Created** by `TUIContext` (one per application).
/// - **Populated** during rendering: when `renderToBuffer` hydrates a view's
///   `@State` properties, it looks up or creates `Storage` objects here.
/// - **Pruned** at the end of each render pass: identities not seen during
///   the current frame are removed. This runs *alongside* `LifecycleManager`'s
///   own sweep, not in coordination with it — the two key on different things
///   (`ViewIdentity` here, a lifecycle token string there) and
///   `RenderLoop.endRenderPass` simply calls them in sequence. Retaining a
///   subtree here therefore does **not** retain its `.task`s or its
///   `onDisappear`.
///
/// ## Thread Safety
///
/// The store itself is main-actor only, but a `StateBox`'s **setter** is not:
/// a `.task` or an input-thread mouse handler can write one. That path takes no
/// lock here — it hands off to `RenderCache.invalidateRender(for:)`, which does
/// (see its Thread Safety note).
public final class StateStorage: @unchecked Sendable {

    // MARK: - State Key

    /// A unique key for a single `@State` property on a specific view.
    ///
    /// ## The property-index namespace
    ///
    /// Indices `0...` belong to a composite view's own wrapped properties,
    /// bound by declaration order. Framework infrastructure that persists a
    /// box at the SAME identity as content it renders — a `Renderable`
    /// modifier or control that pushes no child identity — must use
    /// **negative** indices, or a wrapped composite view's first `@State`
    /// aliases the infrastructure's box: same type and the two share one
    /// value; different types and `storage(for:)` replaces the box each
    /// frame, resetting both sides to their defaults every render.
    ///
    /// Negative indices are reserved in RANGES, one per purpose, so wrappers
    /// stacked on one identity cannot collide with each other either. The
    /// allocation, in tens (a purpose grows downward within its ten):
    ///
    /// | range | owner |
    /// |---|---|
    /// | -10… | `FocusableModifier` |
    /// | -20… | `RefreshableModifier` |
    /// | -30… | `NavigationPresentationModifier` |
    /// | -40… | `_UserResizableCore` |
    /// | -50… | `_ToggleCore` |
    /// | -60… | `TaskModifier` |
    /// | -70… | `_VStackCore` (windowed lazy stacks) |
    /// | -80… | `_ListCore` (a lone row is drawn at the list's own identity) |
    /// | -100… | `ItemProviderDropModifier` (`onDrop(of:delegate:)`) |
    /// | -110… | `_ContentTransitionView` (`contentTransition(_:)`, a tracked value) |
    /// | -120… | `GestureAttachment` (`gesture(_:including:)` and its siblings) |
    /// | -130… | the property walk's record of an enum's case (`enumCaseIndex`) |
    /// | -140… | the property walk's record of a view holding an object (`objectHolderIndex`) |
    /// | -150… | `_ScrollIndicatorsFlashCore` (`scrollIndicatorsFlash(trigger:)`, a tracked value) |
    /// | -160… | `_InspectorToggleHost` (`inspector(isPresented:content:)`'s toggle) |
    ///
    /// Taking a new range: claim the next free ten here, in this table.
    /// (Leaf `Renderable` views whose slots can never share an identity with
    /// composite content keep their historical `0...` constants; anything
    /// that renders a caller-supplied `@ViewBuilder` at its own identity
    /// belongs in this table.)
    ///
    /// ## Nested properties
    ///
    /// A property inside another one the view holds — an app's
    /// `DynamicProperty`, a modifier, an enum's case — is keyed in a
    /// `scope` of its own: a code for where it is declared inside the view
    /// (`NestedScope`), with `propertyIndex` its position there. Neither
    /// depends on what the view's other fields hold, so an optional, an
    /// existential or an enum's case changing moves no other property's
    /// key. A view's own properties are in scope `0`.
    public struct StateKey: Hashable {
        /// The view's structural identity in the render tree.
        public let identity: ViewIdentity

        /// The property's declaration index within the view (0, 1, 2, ...),
        /// or a reserved NEGATIVE infrastructure index — see the
        /// property-index namespace note above. In a nested `scope`, the
        /// property's position among the values stored there.
        public let propertyIndex: Int

        /// Where inside the view a nested property is declared: `0` for the
        /// view's own properties. See "Nested properties" above.
        package let scope: UInt64

        /// Creates a new state key.
        public init(identity: ViewIdentity, propertyIndex: Int) {
            self.identity = identity
            self.propertyIndex = propertyIndex
            self.scope = 0
        }

        /// Creates the key of a property nested at `scope` inside the view.
        package init(identity: ViewIdentity, propertyIndex: Int, scope: UInt64) {
            self.identity = identity
            self.propertyIndex = propertyIndex
            self.scope = scope
        }

        /// Where the property walk records which case an enum keyed at a
        /// ``scope`` holds (``StateStorage/enumCaseRecord(at:)``). From the table
        /// above, because a view that is itself an enum keeps its record in
        /// its own scope, `0`.
        package static let enumCaseIndex = -130

        /// Where the property walk records that a view drawn holds an object
        /// in a field, at the field's scope (``HolderToken``). From the table
        /// above: kept at the view's own identity, so it lives exactly as long
        /// as the view's own state.
        package static let objectHolderIndex = -140

        /// The fields folded into one word before `Hasher` sees any — see
        /// ``mixHashWord(_:_:)``, and ``RenderCache/MeasureKey`` for why a
        /// process-local cache key does not need SipHash per field. `scope`
        /// is XORed into the index's word rather than mixed in after it: a
        /// view's own keys, scope `0`, fold as they did before scopes, and
        /// the equality that follows a hash match tells keys apart.
        public func hash(into hasher: inout Hasher) {
            let folded = mixHashWord(
                mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(identity.structuralHash))),
                UInt64(bitPattern: Int64(propertyIndex)) ^ scope)
            hasher.combine(finalizeHashWord(folded))
        }
    }

    // MARK: - Storage

    /// All persisted state values, keyed by view identity + property index.
    var values: [StateKey: AnyObject] = [:]

    /// Tracked values for `onChange(of:)`, keyed by view identity + property index.
    ///
    /// Unlike `values` (which stores `StateBox` objects that trigger re-renders),
    /// tracked values are plain values used only for change detection. Writing to
    /// them does not trigger a re-render.
    private var trackedValues: [StateKey: Any] = [:]

    /// Per-identity counters for `onChange(of:)` index assignment.
    ///
    /// Reset at the start of each render pass. Each `OnChangeModifier` claims the
    /// next index for its identity, ensuring chained `.onChange(of:)` modifiers at
    /// the same identity get unique keys.
    private var onChangeCounters: [ViewIdentity: Int] = [:]

    /// Identities seen during the current render pass (for garbage collection).
    private var activeIdentities: Set<ViewIdentity> = []

    /// Subtree roots whose descendants' state survives this pass's prune even
    /// when the descendant was not hydrated. Declared each frame by windowing
    /// containers (lazy stacks, `List`, `Table`): a row they skipped left the
    /// *window*, not the *tree* (§5h of "Locating things without drawing
    /// them"). Cleared by ``beginRenderPass``, so a container that stops
    /// rendering stops protecting and its subtree prunes on the next pass.
    /// Deliberately NOT pruned per-row on data deletion: knowing a row left
    /// the data would require the full id set every frame (the identity tax);
    /// a deleted row's state lingers until its container dies.
    private var retainedSubtreeRoots: [ViewIdentity] = []

    /// Whether the containers that window their rows note which they drew
    /// this walk (``noteWindowedRows(_:)``): set, before the walk's content,
    /// by whoever will ask about it afterwards (``wasLeftOutOfAWindow(_:)``),
    /// and cleared when the next walk begins. A walk nobody will ask about —
    /// every walk but one a live sheet docks — notes nothing.
    package var notesWindowedRows = false

    /// What this WALK's windowing containers drew of their rows
    /// (``noteWindowedRows(_:)``). Per walk, not per pass: a pass that walks
    /// twice — a `.global` reader's correction — draws only its last walk,
    /// and a row an earlier walk drew may be one the drawn walk left out. And
    /// a subtree drawn twice within the walk keeps its last drawing's notes
    /// alone (``rewindWindowedRows(to:)``).
    private var windowedRows: [WindowedRows] = []

    /// The render cache that state changes should invalidate — the cache of the
    /// `TUIContext` this storage belongs to. Wired by the context at creation;
    /// its link is stamped onto each ``StateBox`` at hydration, so a state
    /// change clears only its own context's cache (no process-wide singleton →
    /// no cross-test bleed).
    ///
    /// Kept as the cache's `RenderCache.Link`, not as a reference to the
    /// cache: the storage does not own the cache, and a weak reference would
    /// put every retain and release of the cache, for the rest of its life,
    /// through the runtime's slow path. Reads `nil` once the cache has gone.
    /// Main actor only, as the link's `cache` is.
    public var renderCache: RenderCache? {
        get { renderCacheLink?.cache }
        set { renderCacheLink = newValue?.link }
    }

    /// The link of ``renderCache``, which every box is given as its sink.
    var renderCacheLink: RenderCache.Link?

    /// The last-rendered branch of each `ConditionalView`, keyed by the
    /// conditional's own identity (`true` ⇒ the `.trueContent` branch was last
    /// rendered, `false` ⇒ `.falseContent`).
    ///
    /// `ConditionalView.renderToBuffer` consults this to skip the inactive-branch
    /// `invalidateDescendants` (and the identity-node alloc it needs) on frames
    /// where the branch did **not** flip — the common case — only paying that cost
    /// on an actual flip. Written only on the render path (never while measuring,
    /// per the measure-side-effect rule) and pruned in ``endRenderPass`` alongside
    /// the rest of the per-identity state, so removed conditionals don't leak.
    private var lastConditionalCase: [ViewIdentity: ConditionalRecord] = [:]

    /// What each `if` without an `else` held when it last rendered — see
    /// `OptionalPresence`. Pruned as ``lastConditionalCase`` is, by the pass
    /// stamped on each record rather than the active set.
    var optionalPresence: [ViewIdentity: OptionalPresence] = [:]

    /// How many presence records the last sweep of ``optionalPresence`` kept.
    private var optionalRecordsAfterSweep = 0

    /// How many branch records the last sweep of ``lastConditionalCase`` kept.
    ///
    /// The sweep runs when the table has grown well past that, not every pass.
    /// Each record a pass did not render costs a check of the retained
    /// subtrees, and a memo-served page renders none of its conditionals — a
    /// dashboard of a dozen cards, each with an `if` in a style host, spent a
    /// tenth of its frame confirming that every record was still wanted. A
    /// record left over a few passes is harmless: a conditional that returns
    /// compares against its old branch, and invalidating a branch whose state
    /// has already been pruned does nothing.
    private var conditionalRecordsAfterSweep = 0

    /// The hub of each object a render walk has reached in a property field
    /// (``ObjectHub``), by object: each holds its object weakly, so a new
    /// object at a freed one's address is not taken for it — its hub takes
    /// that entry, and the dead object's hub goes. Swept of dead objects'
    /// hubs at the end of a pass once it has doubled since the last sweep
    /// (``objectHubsAfterSweep``): until then, a dead object's hub waits for
    /// one of the two, and an app whose new objects keep landing at the
    /// addresses of a few freed ones may not sweep for a long time.
    var objectHubs: [ObjectIdentifier: ObjectHub] = [:]

    /// How many hubs the last sweep of ``objectHubs`` kept.
    var objectHubsAfterSweep = 0

    /// How many objects have been given ids of their own
    /// (``ObjectHub/idPath``): a count per storage, not a global.
    var objectIDs = 0

    /// The `@Environment` boxes inside class properties' objects that walks
    /// other than the objects' primary holders' render walks resolved, each
    /// with what it held before (``pushEnvironmentRestore(_:previous:)``), and
    /// those a primary's render walk resolved inside another holder's content
    /// (``notePrimaryEnvironment(_:_:)``): put back,
    /// last first, after the holder's content (``restoreEnvironments(to:)``).
    var environmentRestores: [EnvironmentRestore] = []

    /// ``environmentRestores``' count, behind a pointer the storage owns: read
    /// before and after every composite body's content, where a load through
    /// a constant pointer is a plain load and a stored property's read is
    /// checked for exclusivity at run time.
    let restoreDepth = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    /// What each animating value in the tree is doing.
    ///
    /// Held here rather than standing alone because its lifetime is exactly
    /// this one's: an animation belongs to a view identity, and dies with it.
    /// ``endRenderPass()``, ``invalidateDescendants(of:)`` and ``reset()``
    /// forward to it, so an animating view that leaves the tree — or a
    /// conditional branch that flips — takes its animations along.
    public let animations = AnimationStore()

    /// What each removed view left behind, so a removal transition has
    /// something to play out. See ``DepartureStore``.
    public let departures = DepartureStore()

    /// Where each container last placed its children, so a change of layout
    /// under an animation moves them from there. See ``PlacementStore``.
    public let placements = PlacementStore()

    /// The completions waiting on the animations a change started. See
    /// ``AnimationCompletionTracker``.
    public let animationCompletions = AnimationCompletionTracker()

    /// The `@Environment` boxes a view value drawn this pass held resolved
    /// for another place (``noteDisplacedEnvironment(_:from:)``), by box.
    private var displacedEnvironments: [ObjectIdentifier: DisplacedEnvironment] = [:]

    /// The render pass under way, or the last one: a serial from one count
    /// for the process (``renderPassSerials``), taken by
    /// ``beginRenderPass()``, so a pass of this storage is never another's,
    /// and never `0`, what a `@State` made outside every pass notes
    /// (``StateBacking/createdIn``). `0` before the first pass. Main actor
    /// only, as the pass is.
    package private(set) var currentPass: UInt32 = 0

    /// Creates an empty state storage.
    public init() {
        restoreDepth.initialize(to: 0)
        animations.completionTracker = animationCompletions
        departures.completionTracker = animationCompletions
    }

    deinit {
        restoreDepth.deallocate()
    }

    /// The number of stored state entries (for testing/debugging).
    public var count: Int { values.count }
}

// MARK: - Internal API

extension StateStorage {
    /// Returns the persistent storage for a `@State` property, creating it if needed.
    ///
    /// If a storage object already exists for the given key, it is returned as-is
    /// (preserving the current value across render passes). Otherwise, a new storage
    /// is created with the provided default value.
    ///
    /// `defaultValue` is an `@autoclosure` because the common case is a HIT, and
    /// on a hit the default is built and thrown away. That is not free for every
    /// caller: a control's focus id is `"\(prefix)-\(context.identity.path)"`,
    /// and `path` walks the identity chain rendering a string of demangled
    /// generic type names — on every measure and every render of every focusable
    /// view, to be discarded on all but the frame that created the box.
    ///
    /// - Parameters:
    ///   - key: The state key (identity + property index).
    ///   - defaultValue: The initial value for newly created storage. Evaluated
    ///     only when there is no storage yet.
    /// - Returns: The persistent `Storage` object for this property.
    public func storage<Value>(
        for key: StateKey, default defaultValue: @autoclosure () -> Value
    ) -> StateBox<Value> {
        if let existing = values[key] as? StateBox<Value> {
            // Its identity is the key's it was placed at, which this key
            // equals; its sink is written only if the storage's link moved.
            existing.setInvalidationSink(renderCacheLink)
            return existing
        }
        let fresh = StateBox(defaultValue())
        fresh.place(at: key.identity)
        fresh.setInvalidationSink(renderCacheLink)
        // A box of another type under the key — the property's type changed
        // at its place — is dropped.
        (values.updateValue(fresh, forKey: key) as? any DroppableBox)?.markDropped()
        return fresh
    }

    /// Notes that a view value drawn in this pass held `box`, an
    /// `@Environment`'s, resolved for `place`, another place. If `place` is
    /// not drawn in this pass, the value was kept and moved: at the pass's
    /// end the box is unplaced, so the next body resolves it where it lies
    /// rather than in a box of its own every body (``Environment``'s
    /// `resolveEnvironment(at:_:place:storage:)`).
    func noteDisplacedEnvironment(_ box: EnvironmentBox, from place: ViewIdentity) {
        displacedEnvironments[ObjectIdentifier(box)] = DisplacedEnvironment(box: box, place: place)
    }

    /// The record of the case the enum whose properties are keyed at `key`'s
    /// scope held when the property walk last visited it, and of the state
    /// the walk created in that case (``setEnumCaseRecord(_:at:)``), or `nil`
    /// if it keeps none.
    ///
    /// - Parameter key: The scope's record key, at ``StateKey/enumCaseIndex``.
    func enumCaseRecord(at key: StateKey) -> EnumCaseRecord? {
        values[key] as? EnumCaseRecord
    }

    /// Keeps `record` for the enum whose properties are keyed at `key`'s
    /// scope. Kept among the values, beside the state it describes, so it is
    /// pruned and invalidated with that state's identity.
    func setEnumCaseRecord(_ record: EnumCaseRecord, at key: StateKey) {
        values[key] = record
    }

    /// Removes what is stored under each of `keys`: the state an enum's case
    /// created, when another case replaces it, so the case starts at its
    /// defaults when it comes back, as SwiftUI's does (measured on macOS 15:
    /// `Tools/SwiftUIProbes/State keys in dynamic properties/skey.out`). An enum's record among them —
    /// one inside the case — has what it lists removed with it.
    func removeValues(forKeys keys: [StateKey]) {
        for key in keys {
            if let record = dropValue(forKey: key) as? EnumCaseRecord {
                removeValues(forKeys: record.keys)
            }
        }
    }

    /// Removes what is stored under `key`, telling a box it is no longer
    /// kept (``StateBox/wasDropped``), and returns it.
    @discardableResult
    private func dropValue(forKey key: StateKey) -> AnyObject? {
        let removed = values.removeValue(forKey: key)
        (removed as? any DroppableBox)?.markDropped()
        return removed
    }

    /// The storage for a property **if one already exists**, never creating it.
    ///
    /// The measure pass's ``storage(for:default:)``. A measure runs
    /// speculatively and more than once per frame, so it must not create a box
    /// — that is a persistent mutation, at an identity that may never be
    /// rendered. But it does have to READ what the render put there, or a view
    /// that sizes itself from stored state measures one size and draws another.
    ///
    /// - Parameter key: The state key (identity + property index).
    /// - Returns: The existing box, or `nil` if nothing has been stored under
    ///   `key` (or something of another type has).
    public func existingStorage<Value>(for key: StateKey) -> StateBox<Value>? {
        values[key] as? StateBox<Value>
    }

    /// Marks an identity as active during the current render pass.
    ///
    /// Called by `renderToBuffer` when hydrating a view. Identities not marked
    /// active by the end of the render pass are candidates for garbage collection.
    ///
    /// - Parameter identity: The view identity to mark as active.
    public func markActive(_ identity: ViewIdentity) {
        activeIdentities.insert(identity)
    }

    /// Declares that every identity below `root` must survive this pass's
    /// prune, hydrated or not.
    ///
    /// Called on the render path by containers that *window* their children —
    /// render only the rows meeting the viewport — so the skipped rows' state
    /// (`@State`, `onChange` baselines, conditional-branch records) persists
    /// exactly as if they had rendered. Per-pass: declare on every frame the
    /// container renders; the declaration lapses (and the subtree becomes
    /// prunable) the first frame it doesn't.
    ///
    /// - Parameter root: The windowing container's own identity.
    public func retainSubtree(_ root: ViewIdentity) {
        retainedSubtreeRoots.append(root)
    }

    /// The subtrees this pass has declared retained so far
    /// (``retainSubtree(_:)``), indexed for asking of many identities: whether a
    /// view that drew nothing this pass is still in the tree — windowed out of
    /// a lazy container — or has left it.
    public func retainedSubtrees() -> RetainedSubtreeIndex {
        RetainedSubtreeIndex(roots: retainedSubtreeRoots)
    }

    /// Notes which of its rows a container that windows them drew this walk,
    /// when ``notesWindowedRows`` asks for it — built only then: `rows` is not
    /// evaluated on a walk nobody will ask about. The render path only, and
    /// after the window is chosen.
    ///
    /// - Parameter rows: The container's rows, and which it drew.
    @MainActor
    package func noteWindowedRows(_ rows: @autoclosure () -> WindowedRows) {
        guard notesWindowedRows else { return }
        windowedRows.append(rows())
    }

    /// Whether `identity` lies in a row that a container windowing its rows
    /// left out of its window in this walk (``noteWindowedRows(_:)``): the
    /// row is among the container's rows, and the walk did not draw it.
    ///
    /// Not merely below such a container: a view below a drawn `List` that
    /// drew nothing because its branch was not taken, a disclosure group
    /// around it was collapsed, or its row left the data was not left out of
    /// any window. `false` on a walk that noted nothing.
    @MainActor
    package func wasLeftOutOfAWindow(_ identity: ViewIdentity) -> Bool {
        windowedRows.contains { $0.leftOut(identity) }
    }

    /// How many containers have noted their rows so far this walk
    /// (``noteWindowedRows(_:)``) — where a view that may draw a subtree again
    /// in the same walk notes the walk stands (`RenderWalkCheckpoint`).
    package var windowedRowsNoted: Int { windowedRows.count }

    /// Forgets what containers noted after the first `count` — a subtree's
    /// first drawing, which the same walk is about to draw again: only the
    /// drawing kept may say which rows were drawn, or a row the discarded
    /// drawing left out reads as left out of the walk, and the settle holds a
    /// sheet off the dock whose presenter the drawn rows include.
    package func rewindWindowedRows(to count: Int) {
        if windowedRows.count > count { windowedRows.removeSubrange(count...) }
    }

    // MARK: - Conditional Branch Tracking

    /// Records which branch a `ConditionalView` rendered this frame, and reports
    /// whether that **flipped** since the last frame it was recorded.
    ///
    /// Called by ``ConditionalView`` on the render path (gated `!isMeasuring`).
    /// On the first record for an identity — or the first after the conditional
    /// reappeared (its entry having been pruned while absent) — there is no prior
    /// branch, so this returns `false`: the inactive branch has no persisted
    /// state yet (nothing was ever rendered there, or it was already pruned when
    /// the conditional left the tree), so its `invalidateDescendants` would be a
    /// no-op and can be skipped.
    ///
    /// The identity is marked active so its entry survives `endRenderPass`'s
    /// prune; entries for conditionals no longer in the tree are dropped there,
    /// once enough have gathered. One that reappears before then reports a flip
    /// against the branch it left with, and the invalidation that follows finds
    /// that branch's state already pruned.
    ///
    /// - Parameters:
    ///   - identity: The conditional view's own identity.
    ///   - isTrueBranch: `true` if the `.trueContent` branch rendered this frame.
    /// - Returns: `true` if the branch differs from the last recorded one.
    public func recordConditionalBranch(_ identity: ViewIdentity, isTrueBranch: Bool) -> Bool {
        recordingConditionalBranch(identity, isTrueBranch: isTrueBranch) { record in
            let flipped = record.seen && record.isTrueBranch != isTrueBranch
            record.isTrueBranch = isTrueBranch
            record.seen = true
            return flipped
        }
    }

    /// ``recordConditionalBranch(_:isTrueBranch:)``'s access to the record of
    /// the conditional at `identity`, for a caller that records more than the
    /// branch: `body` reads and writes the record where it lies, one access
    /// to the table, and the identity is marked active as that method marks
    /// it. A record made here is a first sight (``ConditionalRecord/seen``).
    func recordingConditionalBranch<Result>(
        _ identity: ViewIdentity, isTrueBranch: Bool, _ body: (inout ConditionalRecord) -> Result
    ) -> Result {
        activeIdentities.insert(identity)
        return body(&lastConditionalCase[identity, default: ConditionalRecord(isTrueBranch: isTrueBranch)])
    }

    // MARK: - onChange Tracking

    /// Claims the next `onChange` property index for the given identity.
    ///
    /// Each `OnChangeModifier` at a given identity calls this to get a unique
    /// index, ensuring chained `.onChange(of:)` modifiers don't collide.
    ///
    /// Claim it BEFORE rendering content. The index is positional, so one
    /// claimed afterwards is the count of claimants the CONTENT contributed at
    /// the same identity — and an `if` without `else` (or an `AnyView`) changes
    /// that from frame to frame, since both render at the parent identity. A
    /// claim made first depends only on the chain above, which is body order.
    ///
    /// - Parameter identity: The view identity requesting an index.
    /// - Returns: The next available index (starting at 0).
    public func nextOnChangeIndex(for identity: ViewIdentity) -> Int {
        let index = onChangeCounters[identity, default: 0]
        onChangeCounters[identity] = index + 1
        return index
    }

    /// How many `onChange` indices `identity` has claimed so far in this walk.
    package func onChangeCount(at identity: ViewIdentity) -> Int? {
        onChangeCounters[identity]
    }

    /// Puts the `onChange` counters back to where they were before a subtree
    /// rooted at `identity` rendered: `identity`'s own to `count`, and every
    /// identity below it to none — so a subtree drawn a second time in one walk
    /// claims the indices its first drawing claimed, and compares against what
    /// that drawing stored rather than an empty slot. See
    /// `MouseHandlerIDTable.rewind(at:to:)`, which does the same for ids.
    package func rewindOnChangeCounters(at identity: ViewIdentity, to count: Int?) {
        onChangeCounters[identity] = count
        let below = onChangeCounters.keys.filter { identity.isAncestor(of: $0) }
        for key in below { onChangeCounters.removeValue(forKey: key) }
    }

    /// Returns the previously tracked value for the given key, if any.
    ///
    /// - Parameter key: The state key (identity + property index).
    /// - Returns: The tracked value, or `nil` if no value was stored yet.
    public func trackedValue<V>(for key: StateKey) -> V? {
        // Absent is `nil`, for an Optional `V` too. Cast straight from the
        // lookup, a missing entry — itself an Optional's `nil` — cast to an
        // Optional `V` as `V`'s own `nil`, as though `nil` had been tracked:
        // `onChange(of:)` an optional that started set fired on its first
        // render, from a `nil` it never had.
        guard let tracked = trackedValues[key] else { return nil }
        return tracked as? V
    }

    /// Stores a tracked value for change detection across render passes.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The state key (identity + property index).
    public func setTrackedValue<V>(_ value: V, for key: StateKey) {
        trackedValues[key] = value
    }

    // MARK: - Render Pass Lifecycle

    /// Begins a new render pass by clearing the active identity set.
    ///
    /// Draw the pass inside ``inRenderPass(_:)``, the view values its bodies
    /// make included: a `@State` made outside it notes no pass, and an object
    /// made with a view value is then taken for one made before the pass, and
    /// restarts at its defaults every frame.
    public func beginRenderPass() {
        currentPass = renderPassSerials.withLock { serial in
            // Wrapping, and skipping `0`: at sixty passes a second the count
            // goes round after two years and three months.
            serial &+= 1
            if serial == 0 { serial = 1 }
            return serial
        }
        animations.beginRenderPass()
        departures.beginRenderPass()
        placements.beginRenderPass()
        activeIdentities.removeAll(keepingCapacity: true)
        retainedSubtreeRoots.removeAll(keepingCapacity: true)
        beginSceneRender()
    }

    /// Runs `body` as the render pass ``beginRenderPass()`` began, so each
    /// `@State` made in it notes the pass (`StateRegistration.renderPass`):
    /// what everything that draws a frame wraps the frame in, the view values
    /// its bodies make included — the run loop from the pass's beginning to
    /// its end, a snapshot render and the test harnesses around their walks.
    /// An object made with a view value in a frame not wrapped so is taken
    /// for one made before the pass.
    ///
    /// Public, beside ``beginRenderPass()`` and ``endRenderPass()``, so a
    /// package drawing frames through them can wrap its frames too.
    public func inRenderPass<R>(_ body: () throws -> R) rethrows -> R {
        try StateRegistration.$renderPass.withValue(currentPass, operation: body)
    }

    /// Begins one WALK of the view tree, of which a render pass may contain
    /// more than one (the app header's height-discovery and correction
    /// re-renders — see `RenderLoop.beginSceneRender()`).
    ///
    /// Deliberately narrower than ``beginRenderPass()``: it resets only what
    /// belongs to one walk — the onChange counters, which are claimed
    /// POSITIONALLY, so a second walk that did not restart them would hand
    /// every `.onChange` / `.onPreferenceChange` a shifted index and read and
    /// write the wrong slots; and what the walk's windowing containers drew
    /// (`noteWindowedRows(_:)`), which only the walk drawn may answer.
    ///
    /// It must NOT clear `activeIdentities`. By the time a walk begins, that
    /// set already carries the App's own root identity (marked when the app
    /// body was evaluated); clearing it mid-pass would leave the root unmarked
    /// and let ``endRenderPass()`` prune App-level `@State` on every frame that
    /// walks the tree twice.
    public func beginSceneRender() {
        onChangeCounters.removeAll(keepingCapacity: true)
        // What the last walk drew of its windows is that walk's.
        notesWindowedRows = false
        if !windowedRows.isEmpty { windowedRows.removeAll() }
        // A value first seen by an earlier walk of this pass, seen differently
        // now, appears rather than animates: that walk's drawing is never shown.
        animations.beginWalk()
    }

    /// Ends a render pass by removing state for views no longer in the tree.
    ///
    /// Any state whose identity was not marked active during this render pass
    /// — and is not under a ``retainSubtree(_:)`` root — is removed. This
    /// prevents memory leaks from views that have been permanently removed
    /// (e.g., by navigation or conditional branches) while keeping windowed-out
    /// rows' state alive.
    public func endRenderPass() {
        // What a body evaluated outside the two places that put an object's
        // environment back left in place: a `List` asking a view for its rows
        // (`listRowsBody`), a stack or a section taking a view's body apart
        // into its members (`compositeMembers`), a `Form` reading its rows
        // through a view's body, a guide asked for. Each is put back at the
        // end of the content of the composite around it, or here.
        restoreEnvironments(to: 0)
        // Indexed once for the pass: the prune asks of every unmarked box,
        // and a climb per root per box was most of a frame's end on a page
        // of memoised cards (see `RetainedSubtreeIndex`).
        var retained = RetainedSubtreeIndex(roots: retainedSubtreeRoots)
        let staleKeys = values.keys.filter {
            !activeIdentities.contains($0.identity) && !retained.retains($0.identity)
        }
        for key in staleKeys {
            dropValue(forKey: key)
        }
        let staleTrackedKeys = trackedValues.keys.filter {
            !activeIdentities.contains($0.identity) && !retained.retains($0.identity)
        }
        for key in staleTrackedKeys {
            trackedValues.removeValue(forKey: key)
        }
        if !displacedEnvironments.isEmpty {
            for displaced in displacedEnvironments.values where displaced.box.place == displaced.place
                && !activeIdentities.contains(displaced.place) && !retained.retains(displaced.place) {
                displaced.box.place = nil
            }
            displacedEnvironments.removeAll(keepingCapacity: true)
        }
        // A view that held an object and was neither drawn nor retained has
        // had its `HolderToken` pruned above, and the object's hub forgot it.
        // The hubs of objects that have gone go once enough have gathered:
        // an object made with each value of a view brings a hub a pass.
        if objectHubs.count > 2 * objectHubsAfterSweep + 64 {
            objectHubs = objectHubs.filter { $0.value.object != nil }
            objectHubsAfterSweep = objectHubs.count
        }
        // Drop branch records for conditionals no longer in the tree, once
        // enough have gathered (`conditionalRecordsAfterSweep`), so the table
        // does not grow without bound. Retained rows keep theirs: if a
        // retained row's conditional flips on re-entry, the flip must be SEEN
        // so the stale branch's state gets invalidated.
        if lastConditionalCase.count > 2 * conditionalRecordsAfterSweep + 64 {
            let staleConditionals = lastConditionalCase.keys.filter {
                !activeIdentities.contains($0) && !retained.retains($0)
            }
            for identity in staleConditionals {
                lastConditionalCase.removeValue(forKey: identity)
            }
            conditionalRecordsAfterSweep = lastConditionalCase.count
        }
        if optionalPresence.count > 2 * optionalRecordsAfterSweep + 64 {
            // By the pass that last wrote each record, which an `if` stamps
            // rather than marking itself active (`presentOptional`).
            var stale: [ViewIdentity] = []
            for (identity, record) in optionalPresence where record.pass != currentPass && !retained.retains(identity) {
                stale.append(identity)
            }
            for identity in stale { optionalPresence.removeValue(forKey: identity) }
            optionalRecordsAfterSweep = optionalPresence.count
        }
        animations.endRenderPass()
        departures.endRenderPass()
        placements.endRenderPass()
    }

    /// Removes all state for descendants of the given identity.
    ///
    /// Called by ``ConditionalView`` when switching branches to clean up
    /// state from the now-inactive branch.
    ///
    /// - Parameter ancestor: The branch identity whose descendants should be removed.
    public func invalidateDescendants(of ancestor: ViewIdentity) {
        let staleKeys = values.keys.filter { ancestor.isAncestor(of: $0.identity) }
        for key in staleKeys {
            dropValue(forKey: key)
        }
        let staleTrackedKeys = trackedValues.keys.filter { ancestor.isAncestor(of: $0.identity) }
        for key in staleTrackedKeys {
            trackedValues.removeValue(forKey: key)
        }
        animations.removeDescendants(of: ancestor)
    }

    /// Removes all stored state. Used during app cleanup.
    public func reset() {
        for value in values.values {
            (value as? any DroppableBox)?.markDropped()
        }
        values.removeAll()
        objectHubs.removeAll()
        objectHubsAfterSweep = 0
        environmentRestores.removeAll()
        restoreDepth.pointee = 0
        displacedEnvironments.removeAll()
        trackedValues.removeAll()
        onChangeCounters.removeAll()
        activeIdentities.removeAll()
        windowedRows.removeAll()
        lastConditionalCase.removeAll()
        conditionalRecordsAfterSweep = 0
        optionalPresence.removeAll()
        optionalRecordsAfterSweep = 0
        animations.removeAll()
        departures.removeAll()
        placements.removeAll()
    }
}

/// The serials every ``StateStorage`` numbers its render passes with
/// (``StateStorage/currentPass``): one count for the process, so that a
/// `@State` made in one storage's pass is never taken for one made in
/// another's — the tests draw many contexts at once. A counter, behind a lock
/// taken once a pass, not an object anything else reaches.
private let renderPassSerials = Lock(initialState: UInt32(0))

// MARK: - State Box

/// Type-erased reference container for a single state value.
///
/// `StateBox` is the persistent storage backing a `@State` property.
/// It is a reference type so that mutations are visible across all copies
/// of the `@State` struct (which uses `nonmutating set`).
///
/// On value change, the box asks its ``RenderInvalidationSink`` to drop the
/// affected subtree's cached buffers and request a re-render. Invalidation is
/// identity-aware: only the affected subtree is cleared, not the whole cache.
public final class StateBox<Value>: @unchecked Sendable {
    /// The identity of the view that owns this state property.
    ///
    /// Set when ``StateStorage`` first keeps the box at a place, and when an
    /// object's own box is placed at one; not again while the storage keeps
    /// it there, since the key it is found by is equal to it. Passed to the
    /// sink so it can invalidate only the affected subtree. Written on the
    /// main actor under the box's stamp lock (``withStamp(_:)``), read under
    /// it by a write on any thread.
    private(set) var identity: ViewIdentity?

    /// The sink that turns a value change into a (deferred, thread-safe) cache
    /// invalidation plus a re-render request — the box's owning context's
    /// cache's ``RenderCache/Link`` (wired during hydration from
    /// ``StateStorage``). Routing through the per-context sink keeps each
    /// context (the app's, and every test's) invalidating only its own cache,
    /// and — because the sink defers the mutation to the main-actor frame
    /// boundary — a `@State` written from a background `Task` never races the
    /// single-threaded cache. `nil` before the box is first hydrated, in which
    /// case nothing has been cached for it yet. For a box a class property's
    /// object holds, the object's ``ObjectHub``, which hands the invalidation
    /// to that context's link for every view drawn holding the object.
    ///
    /// Strong: the link holds nothing that holds the box, where a weak store
    /// — which this was — made the cache's reference count a side table's
    /// from the first frame on.
    ///
    /// Written on the main actor, where the walks run, only when it changes
    /// (``setInvalidationSink(_:)``) — for a view's `@State`, once — and
    /// under the box's stamp lock, which a write of ``value`` on any thread
    /// reads it under. It used to be stored at every hydration while a
    /// `@State` written from a background task read it on that task's
    /// thread: a data race on a two-word existential and on the reference
    /// counts of what it held, and the same on ``identity``.
    private(set) var invalidationSink: (any RenderInvalidationSink)?

    /// The current value.
    public var value: Value {
        didSet {
            let (sink, identity) = withStamp { ($0.invalidationSink, $0.identity) }
            sink?.invalidateRender(for: identity)
        }
    }

    /// Whether the ``StateStorage`` that kept this box has dropped it: its
    /// view's place pruned, the storage reset, its enum case left. A `@State`
    /// still bound to it is then bound afresh (``State``'s `bindState`).
    private(set) var wasDropped = false

    /// Creates a state box with an initial value.
    ///
    /// - Parameter value: The initial value.
    public init(_ value: Value) {
        self.value = value
    }
}

// MARK: - The Box's Stamp

extension StateBox {
    /// Points the box's writes at `sink`, unless they point there already.
    /// Main actor only — the one writer — so the comparison reads without
    /// the lock; the store takes it.
    func setInvalidationSink(_ sink: (any RenderInvalidationSink)?) {
        guard invalidationSink !== sink else { return }
        withStamp { $0.invalidationSink = sink }
    }

    /// Notes that the box is kept at `identity`'s place. Main actor only.
    func place(at identity: ViewIdentity) {
        withStamp { $0.identity = identity }
    }

    /// Runs `body` on the box under its stamp lock: one of
    /// ``stateBoxStampLocks``, picked by the box's address — above the bits
    /// every allocation's alignment leaves zero.
    private func withStamp<R: Sendable>(_ body: @Sendable (StateBox) -> R) -> R {
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        let lock = stateBoxStampLocks[Int(truncatingIfNeeded: (address >> 5) & 15)]
        return lock.withLock { _ in body(self) }
    }
}

/// The locks a ``StateBox``'s identity and sink are written and read under:
/// sixteen, each shared by every box whose address picks it.
///
/// Not one a box. A box is made with every `@State` a view value is built
/// with, in every body, before the walk binds it to the one its place keeps:
/// a lock a box would be an allocation in the hottest constructor there is,
/// and stored at every hydration besides. Sixteen locks shared by address
/// cost nothing until a box is written, and a write already takes its link's
/// lock; two boxes writing at once on two threads share one only by chance.
/// A fixed pool of locks, which nothing outside this file reaches — not
/// state any app shares.
private let stateBoxStampLocks: [Lock<Void>] = (0..<16).map { _ in Lock(initialState: ()) }

/// A box ``StateStorage`` keeps, told when the storage drops it.
protocol DroppableBox: AnyObject {
    /// Notes that the storage no longer keeps the box.
    func markDropped()
}

extension StateBox: DroppableBox {
    func markDropped() {
        wasDropped = true
    }
}

/// An `@Environment`'s box found resolved for another place
/// (``StateStorage/noteDisplacedEnvironment(_:from:)``).
private struct DisplacedEnvironment {
    let box: EnvironmentBox
    let place: ViewIdentity
}
