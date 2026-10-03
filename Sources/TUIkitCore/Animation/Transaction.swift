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
    /// The animation to apply to the change, or `nil` for an immediate one.
    public var animation: Animation?

    // Every field after the animation is a byte, and the booleans share one,
    // so the struct has no interior padding and is 76 bytes: every `Binding`
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
/// - Returns: Whatever `body` returns.
public func withTransaction<Result>(
    _ transaction: Transaction, _ body: () throws -> Result
) rethrows -> Result {
    try Transaction.$ambient.withValue(transaction, operation: body)
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
