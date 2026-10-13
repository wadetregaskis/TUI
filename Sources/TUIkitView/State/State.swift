//  🖥️ TUIkit — Terminal UI Kit for Swift
//  State.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - App State

/// Application state that triggers re-renders when modified.
///
/// `AppState` is thread-safe: ``setNeedsRender()`` can be called from any thread
/// (e.g., from an animation timer on a background queue). Internal state is protected
/// by an `NSLock`.
///
/// The `AppRunner` subscribes to state changes and re-renders when notified.
/// Property wrappers like ``State`` and ``AppStorage`` access the shared instance
/// via `AppState.shared`.
///
/// - Important: This is framework infrastructure. Prefer using ``State`` for reactive state
///   management in your views. Direct use of `AppState` is only necessary in advanced scenarios
///   where you manage state outside the view hierarchy.
public final class AppState: Sendable {
    /// The global shared instance.
    public static let shared = AppState()

    /// Internal state protected by a lock.
    private struct StateData: Sendable {
        var needsRender = false
        var pendingTransaction: Transaction?
        /// Every completion a change since the last frame was made under — not
        /// only the last transaction's: a frame renders under one transaction,
        /// but each completion must still fire exactly once.
        var pendingCompletions: [AnimationCompletion] = []
        var pendingAnimationClocks: Set<AnimationClock> = []
        var needsCacheClear = false
        var shouldExit = false
        var observers: [@Sendable () -> Void] = []

        /// Stamps the change being recorded with whatever ``Transaction`` is in
        /// force where it was made — the seam that makes
        /// ``withAnimation(_:_:)`` reach the render that follows it.
        ///
        /// Only an *explicit* transaction is recorded. A plain
        /// `setNeedsRender()` leaves whatever an earlier animated change put
        /// here, because the two mean different things: without this,
        /// `withAnimation { a = 1 }` followed by an unrelated `b = 2` before
        /// the next frame would drop the animation on the floor.
        mutating func recordAmbientTransaction() {
            guard let ambient = Transaction.ambient else { return }
            pendingTransaction = ambient
            for completion in ambient.completions
            where !pendingCompletions.contains(where: { $0 === completion }) {
                // Claimed: the render that shows this change decides when it
                // fires, rather than the `withTransaction` it was made in.
                completion.claim()
                pendingCompletions.append(completion)
            }
        }
    }

    /// Lock protecting all mutable state.
    private let lock = Lock(initialState: StateData())

    /// Creates a new app state instance.
    public init() {}
}

// MARK: - Public API

extension AppState {
    /// Marks state as changed and notifies observers.
    ///
    /// This method is thread-safe and can be called from any thread.
    ///
    /// Callers that change visual output (theme, palette, appearance) do
    /// **not** need to manually clear the render cache. `RenderLoop`
    /// automatically detects environment changes via `EnvironmentSnapshot`
    /// comparison and clears the cache when needed.
    public func setNeedsRender() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.needsRender = true
            state.recordAmbientTransaction()
            return state.observers
        }
        // Call observers outside the lock to avoid potential deadlocks
        for observer in observers {
            observer()
        }
    }

    /// Records that an animation clock ticked, WITHOUT asking for a render.
    ///
    /// The distinction is the whole point. A state change means the view tree
    /// now describes something different, so it has to be walked again. A clock
    /// tick means only that time passed: the tree describes exactly what it did
    /// a moment ago, and the sole difference on screen is the next frame of
    /// whatever cells declared themselves animated. Conflating the two is what
    /// made a blinking cursor cost a full measure-layout-render pass 20 times a
    /// second — see ``AnimatedCellRun``.
    ///
    /// The run loop tries to serve these by replaying the animated cells of the
    /// frame already on screen. If it cannot — because some view still animates
    /// the old way, by reading the phase during its own render — it falls back
    /// to a full render, which is exactly the behaviour this replaces.
    public func setNeedsAnimationTick(_ clock: AnimationClock) {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.pendingAnimationClocks.insert(clock)
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }

    /// Takes the transaction the pending change was made under, clearing it.
    ///
    /// Called once by the run loop at the start of each render pass. The pass
    /// publishes it as ``EnvironmentValues/transaction`` so every view affected
    /// by the change can see how it was meant to arrive.
    ///
    /// A frame coalesces every change made since the last one, so a frame with
    /// two animated changes in it renders both under the *last* transaction —
    /// there is one pass and it can only run under one. Two animations of
    /// genuinely different lengths in one frame want
    /// ``View/animation(_:value:)``, which scopes the animation to a subtree
    /// and a value rather than to the whole update.
    public func consumePendingTransaction() -> Transaction? {
        lock.withLock { state in
            defer { state.pendingTransaction = nil }
            return state.pendingTransaction
        }
    }

    /// Takes the completions every change since the last frame was made
    /// under, clearing them. Called by the run loop with
    /// ``consumePendingTransaction()``: the pass that renders the change
    /// places them (``AnimationCompletionTracker``).
    public func consumePendingCompletions() -> [AnimationCompletion] {
        lock.withLock { state in
            defer { state.pendingCompletions = [] }
            return state.pendingCompletions
        }
    }

    /// Takes the clocks that have ticked since the last call, clearing them.
    public func consumePendingAnimationClocks() -> Set<AnimationClock> {
        lock.withLock { state in
            defer { state.pendingAnimationClocks = [] }
            return state.pendingAnimationClocks
        }
    }

    /// Marks state as changed and requests a full cache clear on next render.
    ///
    /// For a change nothing can scope to the views it affects: a language
    /// change, which may alter every string, and an observed change drawn with
    /// no render cache to scope it to. An `@Observable` property and an
    /// `@AppStorage` or `@SceneStorage` key are observed where they are read,
    /// and invalidate only those views. Unlike ``setNeedsRender()``, this also
    /// sets a flag that tells the render loop to clear the entire render cache —
    /// a process-wide flag, which the next app to draw takes.
    ///
    /// Thread-safe: can be called from any thread.
    public func setNeedsRenderWithCacheClear() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.needsRender = true
            state.needsCacheClear = true
            state.recordAmbientTransaction()
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }
}

// MARK: - Internal API

extension AppState {
    /// Whether state has changed since last render.
    public var needsRender: Bool {
        lock.withLock { $0.needsRender }
    }

    /// Registers an observer to be notified of state changes.
    ///
    /// - Parameter callback: The callback to invoke on state change.
    public func observe(_ callback: @escaping @Sendable () -> Void) {
        lock.withLock { state in
            state.observers.append(callback)
        }
    }

    /// Clears all observers.
    public func clearObservers() {
        lock.withLock { state in
            state.observers.removeAll()
        }
    }

    /// Resets the needs render flag.
    public func didRender() {
        lock.withLock { state in
            state.needsRender = false
        }
    }

    /// Consumes and returns the cache-clear flag.
    ///
    /// Called by the render loop at the start of each frame. Returns `true`
    /// if any `@Observable` property changed since the last render, signaling
    /// that the render cache should be fully cleared.
    public func consumeNeedsCacheClear() -> Bool {
        lock.withLock { state in
            let value = state.needsCacheClear
            state.needsCacheClear = false
            return value
        }
    }

    /// Requests that the application's run loop exit gracefully on the next
    /// iteration.
    ///
    /// Backs the SwiftUI-parity `@Environment(\.dismiss)` action. Setting
    /// this flag makes `AppRunner` fall out of its run loop, restore the
    /// terminal to its prior state, and return from `App.main()` — exactly
    /// the same shutdown path that the built-in quit key follows. Safe to
    /// call from any thread.
    public func requestExit() {
        let observers = lock.withLock { state -> [@Sendable () -> Void] in
            state.shouldExit = true
            return state.observers
        }
        for observer in observers {
            observer()
        }
    }

    /// Consumes and returns the exit-requested flag.
    ///
    /// Returns `true` once after ``requestExit()`` has been called. Called by
    /// `AppRunner` once per loop iteration.
    public func consumeShouldExit() -> Bool {
        lock.withLock { state in
            let value = state.shouldExit
            state.shouldExit = false
            return value
        }
    }
}

// MARK: - Render Invalidation Sink

/// Receives render-invalidation requests raised by state mutations.
///
/// A `@State` write fires ``StateBox``'s `didSet`, which must (a) drop the
/// cached buffers for the affected subtree and (b) request a re-render. The
/// write can originate off the main actor (a `@State` mutated from a background
/// `Task`), and ``RenderCache`` is single-threaded — so the box must not touch
/// the cache directly. Instead it calls this sink, whose conformer records the
/// invalidation behind a lock and applies it on the main-actor frame boundary.
///
/// ``RenderCache`` conforms (it is the per-context object that owns the cached
/// buffers, so routing through it keeps each context's invalidations isolated).
/// Keeping the seam a protocol lets ``StateBox`` stay free of both the concrete
/// cache type and the app-state singleton name.
public protocol RenderInvalidationSink: AnyObject, Sendable {
    /// Records that the subtree rooted at `identity` (or the whole cache, when
    /// `identity` is `nil`) needs its cached buffers dropped, and requests a
    /// re-render. Thread-safe; the cache mutation itself is deferred to the
    /// next main-actor frame boundary.
    func invalidateRender(for identity: ViewIdentity?)
}

// MARK: - Environment Registration

/// Publishes the active environment during a composite view's `body` evaluation
/// so `@Environment` resolves against it.
///
/// `@State` no longer self-hydrates here: it binds to its view's *own* render
/// identity in `renderToBuffer` / `measureChild` (see
/// `prepareProperties(of:plan:identity:storage:environment:isMeasuring:)`), not by construction order in
/// an enclosing scope.
public enum StateRegistration {
    /// The environment of the `body` currently being evaluated, or `nil`
    /// outside one.
    ///
    /// This is a **fallback**, not the mechanism. `@Environment` resolves
    /// primarily from a per-view reference box that the property walk
    /// (`PropertyWalk`) fills immediately before `body` —
    /// the equivalent of SwiftUI updating a `DynamicProperty` before its view's
    /// body runs, and what makes an `@Environment` read work inside a captured
    /// closure. This value covers only the paths that publish an environment
    /// without running that resolution — `App.body`'s, where a read the walk
    /// cannot reach looks here — and `@FocusState` reaching for a
    /// `FocusManager` before a `.focused` modifier has wired one.
    ///
    /// It is a `@TaskLocal` rather than a mutable global because the scoping is
    /// what the render pipeline actually wants — a value that exists for the
    /// duration of one `body` evaluation and nests — and because a global
    /// cannot express that safely under concurrency. Rendering is
    /// single-threaded on the run loop, so this is not fixing a production
    /// race; it removes one that the *tests* could hit, since suites run in
    /// parallel and more than one of them publishes an environment. A task
    /// local is per-task, so no test can write into another's scope.
    ///
    /// Only readable directly; publish it with ``withHydration(context:_:)`` or
    /// ``withHydration(environment:_:)``.
    @TaskLocal public static var activeEnvironment: EnvironmentValues?

    /// Evaluates `block` with `context`'s environment published as
    /// ``activeEnvironment``. Needed whenever `view.body` is evaluated outside
    /// the normal `renderToBuffer` dispatch (e.g. in `measureChild`). The name
    /// is retained for its existing call sites.
    ///
    /// Nesting works by construction: an inner scope shadows an outer one and
    /// the outer value is restored when it returns.
    public static func withHydration<R>(context: RenderContext, _ block: () -> R) -> R {
        withHydration(environment: context.environment, block)
    }

    /// The environment-only form, for publishers that have no `RenderContext` —
    /// `App.body`, and tests exercising the fallback directly.
    public static func withHydration<R>(
        environment: EnvironmentValues?, _ block: () -> R
    ) -> R {
        $activeEnvironment.withValue(environment, operation: block)
    }

    /// The render pass under way where this is read, a serial of
    /// ``StateStorage/currentPass``'s, or `0` outside every pass: what each
    /// `@State` notes when it is made (``StateBacking/createdIn``).
    ///
    /// Bound from a pass's beginning to its end by whatever draws it
    /// (``StateStorage/inRenderPass(_:)``): the run loop, a snapshot render,
    /// the test harnesses' frames. Not around input dispatch, a task or a
    /// timer, so a `@State` made there notes `0`. A render no pass is bound
    /// around makes every `@State` note `0` too, and an object made there
    /// with a view value is then taken for one made before the pass.
    ///
    /// A task local, not a global the storage writes: a `@State` can be made
    /// on any thread, and a pass's binding must not reach another task's —
    /// the tests draw in parallel. Reading it costs a `@State`'s construction
    /// 4.5 to 7.7 ns over a 92 ns `init` (measured in isolation, arm64 `-O`:
    /// `Tools/SwiftUIProbes/Swift runtime layouts/stamp.out`).
    @TaskLocal package static var renderPass: UInt32 = 0
}

// MARK: - Binding

/// A two-way connection to a mutable value.
///
/// `Binding` provides read and write access to a value owned elsewhere.
/// Use bindings to connect interactive views to state.
///
/// # Example
///
/// ```swift
/// struct ContentView: View {
///     @State var selectedIndex = 0
///
///     var body: some View {
///         Menu(items: menuItems, selection: $selectedIndex)
///     }
/// }
/// ```
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    /// The getter for the value.
    private let getValue: () -> Value

    /// The setter for the value.
    private let setValue: (Value) -> Void

    /// The transaction writes through this binding are made under, or `nil`
    /// for "whatever is ambient".
    ///
    /// Optional, where ``transaction`` is not: an empty `Transaction` is a
    /// STATEMENT — "this change is not animated, whatever the caller said" —
    /// and a plain binding must not make it. Stored as `nil`, a write inside
    /// `withAnimation { … }` is animated; stored as `Transaction()`, it would
    /// silently override the caller. Same third-state shape as `\.font`'s
    /// `Font??`.
    private var declaredTransaction: Transaction?

    /// The transaction writes through this binding are made under.
    ///
    /// Reads as an empty transaction until one is set, which is what SwiftUI
    /// reports for a binding that has never been given one.
    public var transaction: Transaction {
        get { declaredTransaction ?? Transaction() }
        set { declaredTransaction = newValue }
    }

    /// The current value.
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set {
            guard let declaredTransaction else {
                setValue(newValue)
                return
            }
            withTransaction(declaredTransaction) { setValue(newValue) }
        }
    }

    /// The binding itself (for projectedValue access).
    public var projectedValue: Binding<Value> {
        self
    }

    /// Creates a binding with custom getter and setter.
    ///
    /// - Parameters:
    ///   - get: The getter closure.
    ///   - set: The setter closure.
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    /// Creates a constant binding that never changes.
    ///
    /// - Parameter value: The constant value.
    /// - Returns: A binding that always returns the given value.
    public static func constant(_ value: Value) -> Binding<Value> {
        Self(get: { value }, set: { _ in })
    }

    /// Creates a binding from an existing binding's projected value.
    ///
    /// Mirrors SwiftUI's `Binding(projectedValue:)`; used by generic code and
    /// macros that re-wrap a `$value` projection.
    ///
    /// - Parameter projectedValue: The binding to wrap.
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    /// A binding whose writes are made under `animation`, so a control that
    /// knows nothing about animation still animates what it changes.
    ///
    /// ```swift
    /// Toggle("Expanded", isOn: $isExpanded.animation(.easeInOut))
    /// ```
    ///
    /// The third place an animation can be stated, and the one for when
    /// neither the change nor the view is yours to annotate: the *binding* is.
    /// Reads are untouched — only the write is wrapped.
    ///
    /// - Parameter animation: How to animate changes made through the returned
    ///   binding. `nil` makes them explicitly un-animated.
    /// - Returns: A binding that writes inside ``withAnimation(_:_:)``.
    public func animation(_ animation: Animation? = .default) -> Self {
        // Through the transaction, because that is what it IS —
        // `withAnimation(a)` is `withTransaction(Transaction(animation: a))`,
        // so writing the wrapping by hand here was the same mechanism spelled
        // twice. `nil` still means explicitly un-animated: it is a stated
        // transaction whose animation is none, not the absence of one.
        transaction(Transaction(animation: animation))
    }

    /// A binding whose writes are made under `transaction`.
    ///
    /// The general form of ``animation(_:)`` — reach for it when the thing to
    /// state is not the animation but `disablesAnimations`, so a control's
    /// writes opt out of whatever the caller is animating.
    ///
    /// Reads are untouched; only the write is wrapped.
    ///
    /// - Parameter transaction: The context to write under.
    /// - Returns: A binding that writes inside ``withTransaction(_:_:)``.
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        var copy = self
        copy.transaction = transaction
        return copy
    }

    /// Derives a binding to a sub-property of the wrapped value via key path.
    ///
    /// This is what makes `$model.field` work: writing to the derived binding
    /// reads the parent value, mutates the addressed member, and writes the
    /// whole value back through this binding's setter. Matches SwiftUI's
    /// `@dynamicMemberLookup` `Binding` exactly. A `ReferenceWritableKeyPath`
    /// is a `WritableKeyPath`, so reference members work through this subscript
    /// too.
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        Binding<Subject>(
            get: { self.wrappedValue[keyPath: keyPath] },
            set: { newValue in self.wrappedValue[keyPath: keyPath] = newValue }
        )
    }
}

// MARK: - State Property Wrapper

/// A property wrapper that stores mutable state for a view.
///
/// When the value changes, the view hierarchy is re-rendered.
/// Use `@State` for simple value types owned by a single view.
///
/// # Example
///
/// ```swift
/// struct CounterView: View {
///     @State var count = 0
///
///     var body: some View {
///         VStack {
///             Text("Count: \(count)")
///             // When count changes, view re-renders
///         }
///     }
/// }
/// ```
///
/// # Accessing the Binding
///
/// Use the `$` prefix to get a `Binding` to the state:
///
/// ```swift
/// Menu(selection: $selectedIndex)
/// ```
///
/// # Render Integration
///
/// `@State` binds to persistent storage at **render time, by the view's own
/// structural identity** — not at construction. When `renderToBuffer` (or
/// `measureChild`) processes a view, the property walk (`PropertyWalk`)
/// visits its `@State` properties (in declaration order) and points each at the
/// `StateStorage` slot keyed by `(this view's identity, property index)`.
///
/// Keying by the view's *own* identity — rather than the scope it was
/// constructed in — is what keeps conditionally-swapped views (`if` / `switch`
/// branches, which carry distinct `#true` / `#false` identities) from aliasing
/// each other's state. Values survive view reconstruction because the same
/// identity always resolves to the same `StateBox`. One value drawn at two
/// places keeps a state for each: each place's copy is bound to its own box,
/// as SwiftUI installs each place's state in its own copy.
///
/// Mutations signal re-renders through `AppState.shared`.
@propertyWrapper
public struct State<Value> {
    /// Reference-typed backing whose `box` is bound to the persistent
    /// `StateStorage` slot at render time — see ``StateBacking`` and
    /// ``prepareProperties(of:plan:identity:storage:environment:isMeasuring:)``. A `var`
    /// because a value drawn at a second place has its backing replaced, in
    /// that place's copy, by one of its own.
    private var backing: StateBacking<Value>

    /// The current state value.
    public var wrappedValue: Value {
        get { backing.box.value }
        nonmutating set { backing.box.value = newValue }
    }

    /// A binding to the state value.
    public var projectedValue: Binding<Value> {
        let backing = self.backing
        return Binding(
            get: { backing.box.value },
            set: { backing.box.value = $0 }
        )
    }

    /// Creates a state with an initial value. Binds to persistent storage at
    /// render time (keyed by the view's own identity), not at construction.
    public init(wrappedValue: Value) {
        self.backing = StateBacking(wrappedValue)
    }

    /// Creates a state with an initial value (SwiftUI-parity alias for
    /// ``init(wrappedValue:)``).
    ///
    /// Rarely written by hand, but some generic code and macros construct
    /// `@State` via `initialValue:` rather than `wrappedValue:`.
    public init(initialValue value: Value) {
        self.backing = StateBacking(value)
    }

    /// Creates an optional state that starts out `nil`.
    ///
    /// SwiftUI's initialiser for code that constructs a `State` by name. A
    /// declaration does not need it: `@State private var selection: Item?`
    /// with no value is default-initialised through `init(wrappedValue: nil)`.
    public init<Wrapped>() where Value == Wrapped? {
        self.init(wrappedValue: nil)
    }
}

// MARK: - State backing

/// Reference-typed backing for ``State``: the box the state's value is in,
/// which the property walk binds to the one `StateStorage` keeps for the
/// place the view is drawn at, and the default it was declared with.
///
/// Every copy of a `State` value shares its backing, so a binding or closure
/// made from any of them reads and writes the box it was bound to. A value
/// drawn at two places would share one box between them, the second place
/// binding the first's copies to its own (DYNV bug 1); so a backing stays
/// bound to its box while the storage keeps that box, and a place whose copy
/// holds one bound to another kept box is given a backing of its own, in that
/// copy (``State/bindState(at:to:key:)``), as SwiftUI installs each place's
/// state in that place's copy (measured, `Tools/SwiftUIProbes/Dynamic property discovery/dv.out`,
/// `twice` and `value`). Once the storage drops the box — its place pruned,
/// the storage reset, its enum case left — the backing is bound afresh, so a
/// value kept across frames reads its place's state again, and pays for no
/// backing of its own on every body.
///
/// A `@State` inside a class property's object is the object's
/// (``State/bindObjectState(at:to:key:in:isMeasuring:)``): its own box, which
/// no view's key holds — unless the object was made with a value of the view
/// holding it, in the pass that walks it, which ``createdIn`` tells.
final class StateBacking<Value> {
    let defaultValue: Value
    private(set) var box: StateBox<Value>
    /// What ``box`` is: the one made with the backing, one `StateStorage`
    /// keeps for a place, or an object's own.
    ///
    /// Before ``createdIn``, and both after the stored fields of any type, so
    /// the two share the word the binding byte alone would pad out:
    /// `StateBacking<Int>`, `<String>` and `<Bool>` keep their instance sizes
    /// (40, 48 and 40 bytes) and their 48-byte allocations.
    private(set) var bound = BackingBinding.unbound
    /// The render pass the backing was made in — ``StateRegistration/renderPass``
    /// when it was made, a serial of ``StateStorage/currentPass``'s — or `0`
    /// outside every pass: in an event handler, a task, or a render no
    /// pass was bound around.
    let createdIn: UInt32

    init(_ value: Value) {
        self.defaultValue = value
        self.box = StateBox(value)
        self.createdIn = StateRegistration.renderPass
    }

    /// A backing bound to `box` from the start, made by a walk in render pass
    /// `pass`: the walk knows the pass, so the task local is not read.
    init(defaultValue: Value, boundTo box: StateBox<Value>, createdIn pass: UInt32) {
        self.defaultValue = defaultValue
        self.box = box
        self.bound = .place
        self.createdIn = pass
    }

    /// A backing of an object's own from the start, at `defaultValue`, its box
    /// redrawing what `sink` redraws: made by a walk in render pass `pass`.
    init(ownDefault defaultValue: Value, sink: (any RenderInvalidationSink)?, createdIn pass: UInt32) {
        self.defaultValue = defaultValue
        self.box = StateBox(defaultValue)
        self.box.invalidationSink = sink
        self.bound = .own
        self.createdIn = pass
    }

    /// Binds the backing to `box`, one `StateStorage` keeps for a place.
    func bind(to box: StateBox<Value>) {
        self.box = box
        bound = .place
    }

    /// Binds the backing, for a measure, to `box`, one `StateStorage` keeps
    /// for a place already: a render confirms or replaces it.
    func bindProvisionally(to box: StateBox<Value>) {
        self.box = box
        bound = .provisional
    }

    /// Makes the box the backing has its object's own, redrawing what `sink`
    /// redraws when one is given.
    func own(sink: (any RenderInvalidationSink)?) {
        if let sink { box.invalidationSink = sink }
        bound = .own
    }

    /// Moves the backing to `box`, one of its object's own: what the object's
    /// state held when the object made next at its place took over the box
    /// the backing was bound to (``ObjectHub/takeState(handedOverWith:)``).
    func take(_ box: StateBox<Value>) {
        self.box = box
        bound = .own
    }

    /// Moves the backing from the box a place keeps to one of its object's
    /// own, holding the value the place's holds: the object outlived the pass
    /// it was made in.
    func convert(sink: (any RenderInvalidationSink)?) {
        let own = StateBox(box.value)
        own.invalidationSink = sink
        box = own
        bound = .own
    }
}

/// What a ``StateBacking``'s box is.
enum BackingBinding: UInt8 {
    /// The box made with the backing, which holds what is written before any
    /// walk binds it.
    case unbound
    /// A box `StateStorage` keeps under a view's key: the place's — a view
    /// value's `@State`, or that of an object made with the value of the view
    /// holding it.
    case place
    /// A box `StateStorage` keeps under a view's key, which a measure bound an
    /// object made in the pass to: the next render walk keeps it or replaces
    /// it.
    case provisional
    /// An object's own box, which no view's key holds: its long-lived state.
    case own
}

// MARK: - Render-time binding

/// A `@State` property that can be bound to storage at render time (mirrors
/// ``EnvironmentResolvable``).
protocol StateBindable {
    /// Binds the property at `address`, a value of this type, to the storage
    /// `storage` keeps under `key`, created with the property's default if
    /// there is none.
    ///
    /// - Returns: Whether the property at `address` was changed — given a
    ///   backing of its own — rather than its shared backing bound.
    static func bindState(at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey) -> Bool

    /// What the object holding the property at `address`, a value of this
    /// type, is to the render pass `pass`, as the property says without being
    /// bound (``FieldsPlan/objectKind(at:in:)``).
    static func objectKind(at address: UnsafeRawPointer, in pass: UInt32) -> ObjectKind

    /// Binds the property at `address`, a value of this type inside the
    /// storage of `object`'s object (``State/bindObjectState(at:to:key:in:isMeasuring:)``).
    static func bindObjectState(
        at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey,
        in object: ObjectStateContext, isMeasuring: Bool
    ) -> ObjectStateBinding
}

/// What the walk knows of the object whose `@State` it binds.
struct ObjectStateContext {
    /// The object.
    let object: AnyObject
    /// Its hub, the sink of its state's boxes; `nil` for a measure that
    /// reached it before any render walk made one.
    let hub: ObjectHub?
    /// Whether the object the view showed in this field the last time it was
    /// drawn was made with that frame's value of the view: only then does an
    /// object made with this frame's value take the state its place keeps.
    let adoptsPlace: Bool
    /// The hub of that object, which such a box is taken from: what it held
    /// is left to it (``StateStorage/placeBox(_:at:adopting:from:)``). `nil`
    /// for a measure, which takes no box.
    let predecessor: ObjectHub?
}

/// What binding a `@State` inside an object did, and found the object to be.
struct ObjectStateBinding {
    /// Whether the property was changed where it lies — given a backing of
    /// its own — so a copy the walk is on must be assigned back.
    var changed = false
    /// Whether the object was made in the pass that walked it.
    var kind: ObjectKind
}

extension State: StateBindable {
    /// Binds the `@State` at `address` — in the copy of a view whose body is
    /// about to be evaluated — to the box `storage` keeps under `key`. Its
    /// backing is bound if it is not yet, or if the box it is bound to has
    /// been dropped; if it is bound to another box still kept, the value is
    /// being drawn at a second place, and this copy is given a backing of its
    /// own, so the two places never share their state.
    static func bindState(at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey) -> Bool {
        let state = address.assumingMemoryBound(to: Self.self)
        let backing = state.pointee.backing
        let box = storage.storage(for: key, default: backing.defaultValue)
        if backing.box === box { return false }
        // Rebound where its box is gone, not given a backing in this copy:
        // the copy may be one the runtime made (an `indirect` case's
        // payload), which `body` never reads, and a value kept across frames
        // would otherwise allocate a backing on every body from then on.
        guard backing.bound != .unbound, !backing.box.wasDropped else {
            backing.bind(to: box)
            return false
        }
        state.pointee.backing = StateBacking(
            defaultValue: backing.defaultValue, boundTo: box, createdIn: storage.currentPass)
        return true
    }

    /// Made in `pass` and not yet an object's own, it is one an object made
    /// with a view value holds, as ``bindObjectState(at:to:key:in:isMeasuring:)``
    /// finds it.
    static func objectKind(at address: UnsafeRawPointer, in pass: UInt32) -> ObjectKind {
        let backing = address.assumingMemoryBound(to: Self.self).pointee.backing
        return backing.createdIn != 0 && backing.createdIn == pass && backing.bound != .own ? .perValue : .longLived
    }

    /// Binds the `@State` at `address`, inside the storage of `object`'s
    /// object, which a view holds in a property field: the object's state,
    /// whichever view draws it.
    ///
    /// - An object made before the pass that walks it keeps its state in its
    ///   own box, which no view's key holds (``BackingBinding/own``), so no
    ///   measure, memo hit, prune, branch flip or change of the view holding
    ///   it moves, drops or shares it. Its sink is the object's hub, so a
    ///   write redraws every view drawn holding it.
    /// - One made in the pass that walks it, with a value of the view holding
    ///   it (session notes `DYNV2/notes.md` §4.11), takes its state from its
    ///   place, as a view value's `@State` does — the box kept under `key`,
    ///   at the first holder drawn — so the object the next value makes finds
    ///   it. It takes a box the place already keeps only if the object the
    ///   view showed there last was itself made so (`object.adoptsPlace`):
    ///   otherwise the place is given the backing's own box, and what was
    ///   written to it before the walk is kept.
    /// - One made in an earlier pass whose state is still a place's outlived
    ///   its pass: a render walk moves it to a box of its own, with its value
    ///   — or, if the object made next at its place took that box over, with
    ///   what it held then, which any walk takes back. Made on demand in a
    ///   body and kept, it looked made with a view value in its first pass.
    /// - A value holding a `@State` copied from another live object into this
    ///   one shares that object's backing: it is given one of its own, at its
    ///   default.
    ///
    /// A measure creates, moves and drops nothing a view's key holds: it
    /// makes an object's backing its own (what any walk would), gives a
    /// copied value its own, and binds an object made in the pass, until a
    /// render does, to a box its place already keeps.
    static func bindObjectState(
        at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey,
        in object: ObjectStateContext, isMeasuring: Bool
    ) -> ObjectStateBinding {
        let state = address.assumingMemoryBound(to: Self.self)
        let backing = state.pointee.backing
        let pass = storage.currentPass
        let madeThisPass = backing.createdIn != 0 && backing.createdIn == pass
        switch backing.bound {
        case .own:
            let sink = backing.box.invalidationSink
            // The usual case: a load and a compare.
            if let hub = object.hub, sink === hub { return ObjectStateBinding(kind: .longLived) }
            if let other = sink as? ObjectHub, let holder = other.object, holder !== object.object {
                state.pointee.backing = StateBacking(ownDefault: backing.defaultValue, sink: object.hub, createdIn: pass)
                return ObjectStateBinding(changed: true, kind: .longLived)
            }
            // Never drawn, drawn in another context, or held by a dead
            // object's hub: this hub's from now on.
            if !isMeasuring, let hub = object.hub { backing.box.invalidationSink = hub }
            return ObjectStateBinding(kind: .longLived)
        case .unbound:
            guard madeThisPass else {
                backing.own(sink: isMeasuring ? nil : object.hub)
                return ObjectStateBinding(kind: .longLived)
            }
            bindToPlace(backing, storage: storage, key: key, object: object, isMeasuring: isMeasuring)
            return ObjectStateBinding(kind: .perValue)
        case .place, .provisional:
            guard madeThisPass else {
                // The object made next at its place took its box over: what
                // it held then is its own again, whichever walk finds it.
                if let hub = object.hub, let left = hub.takeState(handedOverWith: backing.box) as? StateBox<Value> {
                    backing.take(left)
                    return ObjectStateBinding(kind: .longLived)
                }
                // A measure reads through until a render moves it.
                if !isMeasuring { backing.convert(sink: object.hub) }
                return ObjectStateBinding(kind: .longLived)
            }
            // The first holder drawn decides; a measure's binding is the
            // render's to confirm.
            if backing.bound == .provisional, !isMeasuring {
                bindToPlace(backing, storage: storage, key: key, object: object, isMeasuring: false)
            }
            return ObjectStateBinding(kind: .perValue)
        }
    }

    /// Binds `backing`, of an object made in the pass, to its place's box
    /// (``bindObjectState(at:to:key:in:isMeasuring:)``).
    private static func bindToPlace(
        _ backing: StateBacking<Value>, storage: StateStorage, key: StateStorage.StateKey,
        object: ObjectStateContext, isMeasuring: Bool
    ) {
        if isMeasuring {
            if object.adoptsPlace, let kept: StateBox<Value> = storage.existingStorage(for: key) {
                backing.bindProvisionally(to: kept)
            }
            return
        }
        let box = storage.placeBox(backing.box, at: key, adopting: object.adoptsPlace, from: object.predecessor)
        backing.bind(to: box)
        // After the storage has stamped the box: its sink is the object's
        // hub, so a write redraws every view drawn holding the object, not
        // only the place's.
        box.invalidationSink = object.hub
    }
}

/// A property that needs only a *stable id* derived from its view's render
/// identity — not a full ``StateStorage`` slot — bound at render time.
///
/// `@FocusState` (in the higher-level `TUIkit` module, where the focus system
/// lives) uses this: it keeps its per-value focus mappings on the persistent
/// `FocusManager`, keyed by an id that must stay the same across frames so a
/// control's focusID and the "which value is focused?" reverse-lookup remain
/// stable. The id is derived from the owning view's identity + the property's
/// declaration order, exactly like a `StateBindable` slot key — and, for one
/// nested inside an app's `DynamicProperty`, a modifier or an enum's case,
/// from where it lies there (`NestedScope`). Public so a type in a module
/// layered above `TUIkitView` can participate in the same
/// property walk (`PropertyWalk`) that binds `@State`.
public protocol RenderIdentityBindable {
    /// Binds this property to a stable id derived from its view's render
    /// `path` and declaration `propertyIndex`. For a property nested inside
    /// another the view holds, `path` is followed by `::` and a code for
    /// where in the view that is, and `propertyIndex` is the property's
    /// position there.
    func bindRenderIdentity(path: String, propertyIndex: Int)
}
