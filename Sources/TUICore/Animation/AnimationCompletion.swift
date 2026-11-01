//  🖥️ TUI — A Terminal UI framework for Swift
//  AnimationCompletion.swift
//
//  Running code when the animations a change started have finished:
//  `withAnimation(_:completionCriteria:_:completion:isolation:)` and
//  `Transaction.addAnimationCompletion(criteria:_:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// The criteria that determines when an animation is considered finished.
public struct AnimationCompletionCriteria: Hashable, Sendable {
    private enum Criterion: Hashable, Sendable {
        case logicallyComplete
        case removed
    }

    private let criterion: Criterion

    /// The animation has logically completed, but may still be in its long
    /// tail.
    ///
    /// If a subsequent change starts more animations on the values this one
    /// moved, the completion still fires when the animations of the change it
    /// was registered with logically complete, ignoring the new ones.
    ///
    /// For a curve that is its end. For a spring it is the spring's pace — the
    /// `duration:` it was made with — with the settling still to come; see
    /// ``Animation/logicallyComplete(after:)`` to bring it forward.
    public static let logicallyComplete = Self(criterion: .logicallyComplete)

    /// The entire animation is finished and will now be removed.
    ///
    /// If a subsequent change starts more animations on the values this one
    /// moved, the completion waits for ALL of them to finish.
    public static let removed = Self(criterion: .removed)

    /// Whether this is ``removed``.
    package var waitsForRemoval: Bool { criterion == .removed }
}

/// One completion handler, waiting on the animations of the change it was
/// registered with.
///
/// A class, so the handler can be shared by every copy of the transaction that
/// carries it and still fire exactly once, and so the run loop can tell whether
/// a state change ever claimed it. Its state is guarded by a lock because a
/// state change — and so a claim — may be made from any thread
/// (`AppState.setNeedsRender()` is), while firing happens on the main actor.
public final class AnimationCompletion: Sendable {
    /// When the handler fires.
    public let criteria: AnimationCompletionCriteria

    /// The handler, which runs on the main actor, where completions fire.
    private let handler: @MainActor () -> Void

    private struct State {
        /// Whether a state change made under the transaction recorded it, so
        /// the render that follows owns it.
        var claimed = false
        /// Whether it has run.
        var fired = false
    }

    private let state = Mutex(State())

    init(criteria: AnimationCompletionCriteria, handler: @escaping @MainActor () -> Void) {
        self.criteria = criteria
        self.handler = handler
    }

    /// Records that a state change was made under the transaction carrying
    /// this completion: the render that shows it decides when it fires.
    package func claim() {
        state.withLock { $0.claimed = true }
    }

    /// Whether a state change has claimed it.
    package var isClaimed: Bool { state.withLock { $0.claimed } }

    /// Runs the handler, unless it has already run.
    @MainActor package func fire() {
        if takeFiring() { handler() }
    }

    /// Runs the handler from code isolated to `isolation`, unless it has
    /// already run: at once on the main actor, and from anywhere else as soon
    /// as the main actor can take it.
    package func fire(from isolation: isolated (any Actor)?) {
        guard takeFiring() else { return }
        if isolation === MainActor.shared {
            MainActor.assumeIsolated { handler() }
        } else {
            let handler = handler
            Task { @MainActor in handler() }
        }
    }

    /// Whether this is the first time the handler was asked to run.
    private func takeFiring() -> Bool {
        state.withLock { state -> Bool in
            defer { state.fired = true }
            return !state.fired
        }
    }
}

extension Transaction {
    /// Adds a completion to run when the animations created with this
    /// transaction are all complete.
    ///
    /// The completion callback will always be fired exactly one time. If no
    /// animations are created by the changes in `body`, then the callback will
    /// be called immediately after `body`.
    ///
    /// "The animations created with this transaction" are the ones the render
    /// that shows the change starts: every animated value, arriving
    /// transition and departing one that begins moving on that frame.
    ///
    /// A completion is honoured on a transaction a change is made under —
    /// ``withTransaction(_:_:isolation:)``, ``withAnimation(_:completionCriteria:_:completion:isolation:)``,
    /// a binding's transaction — not on one a view's
    /// `transaction(_:)` modifier rewrites while rendering, which no change
    /// was made under.
    ///
    /// The completion runs on the main actor, wherever it was added. SwiftUI's
    /// parameter is a plain closure; a closure literal is accepted the same
    /// way from any caller, and `@preconcurrency` lets one held in a variable
    /// through with a warning rather than an error.
    @preconcurrency
    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping @MainActor () -> Void
    ) {
        appendCompletion(AnimationCompletion(criteria: criteria, handler: completion))
    }
}

/// Returns the result of recomputing the view's body with the provided
/// animation, and runs the completion when all animations are complete.
///
/// This function sets the given ``Animation`` as the ``Transaction/animation``
/// property of the thread's current ``Transaction`` as well as calling
/// ``Transaction/addAnimationCompletion(criteria:_:)`` with the specified
/// completion.
///
/// The completion callback will always be fired exactly one time. If no
/// animations are created by the changes in `body`, then the callback will be
/// called immediately after `body`.
///
/// ```swift
/// withAnimation(.easeOut(duration: 0.3)) {
///     isExpanded = false
/// } completion: {
///     showsDetail = false
/// }
/// ```
///
/// The completion runs on the main actor, wherever it was added. SwiftUI's
/// parameter is a plain closure; a closure literal is accepted the same way from
/// any caller, and one held in a variable is called from a literal (`{ done() }`).
/// Not `@preconcurrency`, as `addAnimationCompletion(criteria:_:)` is: with an
/// `isolated` parameter that trips an assertion in the compiler (6.2.4).
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
    _ body: () throws -> Result,
    completion: @escaping @MainActor () -> Void,
    isolation: isolated (any Actor)? = #isolation
) rethrows -> Result {
    var transaction = Transaction(animation: animation)
    transaction.addAnimationCompletion(criteria: completionCriteria, completion)
    return try withTransaction(transaction, body, isolation: isolation)
}
