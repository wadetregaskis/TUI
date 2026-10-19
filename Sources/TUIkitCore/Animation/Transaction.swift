//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Transaction.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// The context of a state change: how — and whether — the resulting update
/// should be animated.
///
/// A transaction travels with a change rather than with a view. That is the
/// distinction that makes ``withAnimation(_:_:)`` work at all: the *caller*
/// decides that this particular change is worth animating, and every view
/// affected by it animates, without any of them having been told in advance
/// which changes to expect.
public struct Transaction: Sendable, Equatable {
    /// The values set through ``subscript(_:)``, and the completions waiting
    /// on the change, held by reference and copied on write. `nil` for every
    /// transaction that sets neither, which is nearly all of them: they cost
    /// one word.
    ///
    /// First, and a word: the animation after it is 73 bytes and the switches
    /// after that are bytes, so leading with the reference keeps the struct
    /// free of interior padding (84 bytes). Put after them it would have cost
    /// seven undefined bytes in every `Binding`.
    private var extras: TransactionExtras?

    /// The animation to apply to the change, or `nil` for an immediate one.
    public var animation: Animation?

    // Every field after the animation is a byte, and the booleans share one,
    // so the struct has no interior padding and is 84 bytes: every `Binding`
    // carries one inline, and the per-pass memos hash a view's bytes, padding
    // included unless it is skipped (`ControlLayoutPaddingTests`). The scroll
    // members cost two bytes, the anchor's; as three `Bool`s and two
    // `Double`s they cost twenty-four and left five undefined.

    /// The transaction's switches, one bit each.
    private var flags: UInt8 = 0

    /// `scrollTargetAnchor`'s point in hundredths, with `Int8.min` in `x` for
    /// none.
    private var scrollAnchorX: Int8 = .min
    private var scrollAnchorY: Int8 = 0

    private static let disablesAnimationsBit: UInt8 = 1 << 0
    private static let preservesVelocityBit: UInt8 = 1 << 1
    private static let disablesScrollAdjustmentBit: UInt8 = 1 << 2
    private static let isContinuousBit: UInt8 = 1 << 3
    private static let tracksVelocityBit: UInt8 = 1 << 4
    private static let dismissesDestructivelyBit: UInt8 = 1 << 5

    private func flag(_ bit: UInt8) -> Bool { flags & bit != 0 }

    private mutating func setFlag(_ bit: UInt8, _ on: Bool) {
        flags = on ? flags | bit : flags & ~bit
    }

    /// Whether animations in the affected subtree are suppressed.
    ///
    /// Set on a *subtree* (via `View.transaction(_:)`) to opt part of the tree
    /// out of an ambient animation — the header should not slide just because
    /// the list below it did.
    public var disablesAnimations: Bool {
        get { flag(Self.disablesAnimationsBit) }
        set { setFlag(Self.disablesAnimationsBit, newValue) }
    }

    /// Whether a programmatic change to a scroll position, made under this
    /// transaction, leaves a scroll already in progress moving. Matches
    /// SwiftUI's property of the same name; `false` by default, as there.
    ///
    /// Recorded, and met by the medium: a terminal's scrolling comes in
    /// discrete steps and keeps no momentum, so no scroll is ever still moving
    /// for a programmatic change to stop or to spare.
    public var scrollPositionUpdatePreservesVelocity: Bool {
        get { flag(Self.preservesVelocityBit) }
        set { setFlag(Self.preservesVelocityBit, newValue) }
    }

    /// A Boolean value that indicates whether the transaction originated from
    /// an action that produces a sequence of values.
    ///
    /// `true` if a continuous action created the transaction — dragging a
    /// slider, holding a stepper's arrow — and `false` for a single one, like
    /// a button press. Set by whoever makes the change, and read by whatever
    /// wants to treat a stream of changes differently from one.
    public var isContinuous: Bool {
        get { flag(Self.isContinuousBit) }
        set { setFlag(Self.isContinuousBit, newValue) }
    }

    /// Whether this transaction will track the velocity of any animatable
    /// properties that change.
    ///
    /// SwiftUI accumulates the velocity of values changed under such a
    /// transaction, so that a later animation can start from it. TUIkit's
    /// animations are closed-form functions of elapsed time that start at
    /// rest — a spring retargeted mid-flight restarts from where its picture
    /// is, without its speed — so there is no velocity to track, and this is
    /// recorded for whoever reads the transaction and changes nothing else.
    /// See `SwiftUI API completion decisions.md`, B55.
    public var tracksVelocity: Bool {
        get { flag(Self.tracksVelocityBit) }
        set { setFlag(Self.tracksVelocityBit, newValue) }
    }

    /// Where `dismissBehavior` keeps its one bit — whether a window is
    /// dismissed under this transaction even with a presentation up — the
    /// property and its type being declared above this module, beside the
    /// window actions they qualify.
    package var dismissesDestructively: Bool {
        get { flag(Self.dismissesDestructivelyBit) }
        set { setFlag(Self.dismissesDestructivelyBit, newValue) }
    }

    /// Where TUIkit's `scrollContentOffsetAdjustmentBehavior` keeps its one
    /// bit: whether a scroll view's own offset adjustments are off for the
    /// change.
    package var disablesScrollContentOffsetAdjustment: Bool {
        get { flag(Self.disablesScrollAdjustmentBit) }
        set { setFlag(Self.disablesScrollAdjustmentBit, newValue) }
    }

    /// Where TUIkit's `scrollTargetAnchor` keeps its point: the property is
    /// declared beside `UnitPoint`, which lives above this module.
    ///
    /// Kept to a hundredth, within ±1.27 — a hundredth of a viewport is finer
    /// than a row of any terminal, and an anchor is a fraction of one.
    package var scrollTargetAnchorStorage: (x: Double, y: Double)? {
        get {
            guard scrollAnchorX != .min else { return nil }
            return (Double(scrollAnchorX) / 100, Double(scrollAnchorY) / 100)
        }
        set {
            guard let point = newValue else {
                (scrollAnchorX, scrollAnchorY) = (.min, 0)
                return
            }
            func hundredths(_ value: Double) -> Int8 {
                guard value.isFinite else { return 0 }
                return Int8(max(-127, min(127, (value * 100).rounded())))
            }
            (scrollAnchorX, scrollAnchorY) = (hundredths(point.x), hundredths(point.y))
        }
    }

    /// Creates a transaction with no animation.
    public init() {}

    /// Creates a transaction that animates its change.
    public init(animation: Animation?) {
        self.animation = animation
    }

    /// The animation this transaction actually applies — `nil` when it names
    /// none, or when the subtree has opted out.
    public var effectiveAnimation: Animation? {
        disablesAnimations ? nil : animation
    }

    /// Accesses the transaction value associated with a custom key.
    ///
    /// Create custom transaction values by defining a key that conforms to
    /// ``TransactionKey``, and then using that key with this subscript:
    ///
    /// ```swift
    /// private struct MyTransactionKey: TransactionKey {
    ///     static let defaultValue = false
    /// }
    ///
    /// extension Transaction {
    ///     var myCustomValue: Bool {
    ///         get { self[MyTransactionKey.self] }
    ///         set { self[MyTransactionKey.self] = newValue }
    ///     }
    /// }
    /// ```
    public subscript<K: TransactionKey>(key: K.Type) -> K.Value {
        get {
            guard let stored = extras?.values[ObjectIdentifier(key)]?.value as? K.Value else {
                return K.defaultValue
            }
            return stored
        }
        set {
            uniqueExtras().values[ObjectIdentifier(key)] = TransactionValue(newValue, of: key)
        }
    }

    /// The completions waiting on this change, in the order they were added.
    package var completions: [AnimationCompletion] { extras?.completions ?? [] }

    /// Adds `completion` — see ``addAnimationCompletion(criteria:_:)``.
    mutating func appendCompletion(_ completion: AnimationCompletion) {
        uniqueExtras().completions.append(completion)
    }

    /// The extras, made unique to this copy and created if there were none —
    /// the copy-on-write step of every mutation that reaches them.
    private mutating func uniqueExtras() -> TransactionExtras {
        if let extras, isKnownUniquelyReferenced(&self.extras) { return extras }
        let unique = extras.map(TransactionExtras.init(copying:)) ?? TransactionExtras()
        extras = unique
        return unique
    }

    /// Two transactions are equal when every field is, and every custom value
    /// is: the same value set once (a copy of the transaction), or two values
    /// their key's `_valuesEqual(_:_:)` calls equal. A value
    /// whose type is not `Equatable` is equal only to itself.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.animation == rhs.animation && lhs.flags == rhs.flags
            && lhs.scrollAnchorX == rhs.scrollAnchorX && lhs.scrollAnchorY == rhs.scrollAnchorY
            && TransactionExtras.equal(lhs.extras, rhs.extras)
    }
}

// MARK: - Custom values

/// A key for accessing values in a transaction.
///
/// You can create custom transaction values by extending ``Transaction`` with
/// new properties. First declare a new transaction key type and specify a value
/// for the required ``defaultValue`` property:
///
/// ```swift
/// private struct MyTransactionKey: TransactionKey {
///     static let defaultValue = false
/// }
/// ```
///
/// Then use the key to define a new transaction value property, and set it for
/// a change with ``withTransaction(_:_:_:)``:
///
/// ```swift
/// withTransaction(\.myCustomValue, true) {
///     isActive.toggle()
/// }
/// ```
///
/// To use the value from inside a view or one of its descendants, read it in a
/// ``View/transaction(_:)`` modifier.
public protocol TransactionKey {
    /// The associated type representing the type of the transaction key's
    /// value.
    associatedtype Value

    /// The default value for the transaction key.
    static var defaultValue: Value { get }

    /// Whether two values of this key are the same — what makes two
    /// transactions equal. Not to be implemented by hand: a key whose `Value`
    /// is `Equatable` compares with `==`, and any other compares unequal (a
    /// value set once is still equal to itself, as a copy of the transaction
    /// carries the same value).
    static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool
}

extension TransactionKey {
    /// A value that cannot be compared is not known to equal another.
    public static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        false
    }
}

extension TransactionKey where Value: Equatable {
    /// An `Equatable` value compares with `==`.
    public static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
        lhs == rhs
    }
}

/// One custom value, with its key's comparison.
private struct TransactionValue {
    let value: Any

    /// Whether `value` equals another value of the same key, erased.
    let equals: (Any) -> Bool

    /// The value set once: what a copy of the transaction shares, so a value
    /// that cannot be compared is still equal to itself.
    let identity = TransactionValueIdentity()

    init<K: TransactionKey>(_ value: K.Value, of _: K.Type) {
        self.value = value
        equals = { other in
            guard let other = other as? K.Value else { return false }
            return K._valuesEqual(value, other)
        }
    }
}

/// What tells one setting of a value from another.
private final class TransactionValueIdentity {}

/// The part of a ``Transaction`` held by reference: its custom values.
///
/// `@unchecked Sendable` because a key's value need not be `Sendable` — as in
/// SwiftUI — while a transaction must be, to be a task local. A transaction is
/// made and read on the main actor by every path TUIkit has.
final class TransactionExtras: @unchecked Sendable {
    fileprivate var values: [ObjectIdentifier: TransactionValue] = [:]

    /// The completions waiting on the change. See `AnimationCompletion`.
    var completions: [AnimationCompletion] = []

    init() {}

    /// A copy, for a transaction about to change what it shares.
    init(copying other: TransactionExtras) {
        values = other.values
        completions = other.completions
    }

    /// Whether two transactions' extras say the same thing — `nil` and empty
    /// alike saying nothing. Completions are the same only if they are the
    /// same handlers.
    static func equal(_ lhs: TransactionExtras?, _ rhs: TransactionExtras?) -> Bool {
        if lhs === rhs { return true }
        let leftCompletions = lhs?.completions ?? []
        let rightCompletions = rhs?.completions ?? []
        guard leftCompletions.count == rightCompletions.count,
            zip(leftCompletions, rightCompletions).allSatisfy({ $0 === $1 })
        else { return false }
        let left = lhs?.values ?? [:]
        let right = rhs?.values ?? [:]
        guard left.count == right.count else { return false }
        for (key, value) in left {
            guard let other = right[key] else { return false }
            guard value.identity === other.identity || value.equals(other.value) else { return false }
        }
        return true
    }
}

// MARK: - The ambient transaction

extension Transaction {
    /// The transaction in force for changes made right now, or `nil` outside
    /// any ``withTransaction(_:_:)`` scope.
    ///
    /// A task local rather than a global for the reason
    /// `StateRegistration.activeEnvironment` is: the scoping the mechanism
    /// wants *is* "for the duration of this call, and nested", and a global
    /// cannot express that safely under concurrency. It also means a change
    /// made from a different task — a `.task` firing mid-animation — is
    /// correctly *not* part of the transaction, which is what SwiftUI does too.
    @TaskLocal public static var ambient: Transaction?
}

/// Runs `body` with `transaction` in force, so any state change it makes is
/// rendered under that transaction.
///
/// The mechanism ``withAnimation(_:_:)`` is built from. Use it directly to set
/// something other than the animation — `disablesAnimations`, most usefully:
///
/// ```swift
/// var transaction = Transaction()
/// transaction.disablesAnimations = true
/// withTransaction(transaction) { selection = item }   // no animation, ever
/// ```
///
/// Nesting works by construction: the inner scope shadows the outer one, and
/// the outer transaction is restored when it returns.
///
/// A completion on `transaction` (``Transaction/addAnimationCompletion(criteria:_:)``)
/// that no state change in `body` claimed — `body` changed nothing, so the
/// change started no animations — runs as soon as `body` returns, as SwiftUI
/// documents. One the enclosing transaction already carried belongs to the
/// enclosing call, which decides.
///
/// As `body` returns, the app whose work this is (`AmbientApp`) hears that
/// the scope ended: an `@Observable` property written in `body` whose body's
/// observation an earlier, unanimated write had already fired reports
/// nothing, and the app takes `transaction` for that change — completions
/// and all, which then run when the frame's animation completes. The app
/// cannot tell that change from none, so a `body` that changed nothing,
/// ending while such an unanimated change waits for its frame, has its
/// completions held for that frame too (deviation A7).
///
/// - Returns: Whatever `body` returns.
public func withTransaction<Result>(
    _ transaction: Transaction, _ body: () throws -> Result
) rethrows -> Result {
    let enclosing = transaction.completions.isEmpty ? [] : Transaction.ambient?.completions ?? []
    defer {
        // First: the app may claim the completions for the change it takes
        // this transaction for.
        AmbientApp.renderState?.transactionScopeEnded(transaction)
        for completion in transaction.completions
        where !completion.isClaimed && !enclosing.contains(where: { $0 === completion }) {
            completion.fire()
        }
    }
    return try Transaction.$ambient.withValue(transaction, operation: body)
}

/// Executes a closure with the specified transaction key path and value and
/// returns the result.
///
/// The transaction in force is the one around the call, if there is one, with
/// `keyPath` set — so the value composes with an enclosing
/// ``withAnimation(_:_:)`` rather than replacing it:
///
/// ```swift
/// withTransaction(\.myCustomValue, true) {
///     isActive.toggle()
/// }
/// ```
///
/// - Parameters:
///   - keyPath: A key path that indicates the property of the ``Transaction``
///     structure to update.
///   - value: The new value to set for the item specified by `keyPath`.
///   - body: A closure to execute.
/// - Returns: The result of executing the closure with the specified
///   transaction value.
public func withTransaction<R, V>(
    _ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R
) rethrows -> R {
    var transaction = Transaction.ambient ?? Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

/// Runs `body` with `animation` in force, so any state change it makes is
/// rendered as a movement from the old value to the new one rather than as a
/// jump.
///
/// ```swift
/// withAnimation(.easeInOut(duration: 0.3)) {
///     isExpanded.toggle()
/// }
/// ```
///
/// The change itself is immediate — `isExpanded` is `true` the instant the
/// closure returns, and every event handler and every `if` in every body sees
/// `true`. What lags is the *picture*: views that nominated something
/// continuous about themselves (see ``Animatable``) are rendered at values
/// between the old and the new until the animation ends.
///
/// Only changes made *synchronously, on this task*, inside the closure are part
/// of the animation. An `await` inside it, or work handed to another task, is
/// a separate change and is not animated — the same rule SwiftUI has, and for
/// the same reason: the transaction is scoped to the call, not to the clock.
///
/// - Parameters:
///   - animation: How to animate the change. `nil` makes the change explicitly
///     *un*-animated, overriding any surrounding ``withAnimation(_:_:)``.
///   - body: The changes to animate.
/// - Returns: Whatever `body` returns.
public func withAnimation<Result>(
    _ animation: Animation? = .default, _ body: () throws -> Result
) rethrows -> Result {
    try withTransaction(Transaction(animation: animation), body)
}
