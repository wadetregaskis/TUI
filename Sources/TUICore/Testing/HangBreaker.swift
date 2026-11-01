//  🖥️ TUI — A Terminal UI framework for Swift
//  HangBreaker.swift
//
//  When a test's wait for work it spawned gives up. Here rather than beside the
//  waits because they live in several places, TUITesting and the test support
//  targets among them, and this is the lowest module they all see.
//
//  Created by Wade Tregaskis
//  License: MIT

/// When a wait in these tests gives up, and what it can say when it does.
///
/// `TestApp.wait(until:timeout:)`, the framework's own tests' `settle(until:)`
/// and the registration storm's poll suspend differently — each for a reason its
/// own documentation gives — but all are waits with a hang-breaker, and when to
/// break is one rule, so it is kept in one place.
///
/// The rule is a deadline and then a grace. A wait whose deadline has passed
/// still takes ``graceTurns`` more turns, and gives up only if its condition is
/// false after every one of them. A deadline that passed DURING a turn says
/// nothing about the work: the whole turn may have been spent queued behind a
/// saturated main actor, with the work's next hop queued behind the turn. A
/// turn that BEGINS past the deadline has whatever the work queued before it
/// in front of it, so only those count towards giving up.
package struct HangBreaker {
    /// How many turns a wait still takes once its deadline has passed.
    ///
    /// A margin, not a measurement. The longest chain these waits sit behind
    /// is a Ctrl-R's: the task the key press spawns starts on the main actor,
    /// `RefreshAction` hops to the pool, back to the main actor for its first
    /// `MainActor.run`, and to the pool again to run the body — two turns of
    /// each. Ten covers that with room to spare, and costs a wait that is
    /// genuinely stuck ten more turns: milliseconds on an idle main actor,
    /// longer on a saturated one.
    package static let graceTurns = 10

    /// How long the grace lasts at least, from the first turn past the deadline.
    ///
    /// The turns alone cover the main actor's legs of the work and not the
    /// pool's: on an idle main actor ten naps are over in about ten
    /// milliseconds, and a body waiting for a pool thread may not have been
    /// given one by then. Half a second is a margin for that leg, no more; a
    /// genuinely stuck wait pays it once.
    package static let minimumGrace: Duration = .milliseconds(500)

    private let started: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    /// When the first turn past the deadline began.
    private var overdueSince: ContinuousClock.Instant?
    /// When the last turn counted began.
    private var lastTurn: ContinuousClock.Instant?

    /// How many times the wait has suspended.
    package private(set) var turns = 0

    /// How many of those turns began at or past the deadline.
    package private(set) var overdueTurns = 0

    package init(timeout: Duration, now: ContinuousClock.Instant = .now) {
        started = now
        deadline = now + timeout
    }

    /// Whether the turn last counted began past the deadline, which makes it,
    /// and every turn after it, part of the grace.
    package var isOverdue: Bool { overdueTurns > 0 }

    /// Whether the wait should give up rather than suspend again: its deadline
    /// has passed, and since then it has taken every turn of its grace and
    /// begun its last one at least ``minimumGrace`` after the first.
    ///
    /// Timed by when the turns BEGAN, as the wait counted them, so the rule
    /// reads no clock of its own and its tests can inject every instant.
    package var hasTripped: Bool {
        guard overdueTurns >= Self.graceTurns, let overdueSince, let lastTurn else { return false }
        return overdueSince.duration(to: lastTurn) >= Self.minimumGrace
    }

    /// Counts the suspension the wait is about to make, and returns its
    /// number, counting from 1.
    @discardableResult
    package mutating func nextTurn(at now: ContinuousClock.Instant = .now) -> Int {
        turns += 1
        lastTurn = now
        if now >= deadline {
            if overdueSince == nil { overdueSince = now }
            overdueTurns += 1
        }
        return turns
    }

    /// The wait's turns and how long they took, and how long its grace took.
    ///
    /// Between them they say how the wait went. Thousands of turns and a grace
    /// over in milliseconds: the wait was served promptly, and the work still
    /// did not happen. A handful of turns and a grace that took seconds: it was
    /// served slowly throughout. A handful before a quick grace: it hardly ran
    /// before its deadline, and then the work had its turns and still did not
    /// happen.
    ///
    /// A method rather than `description`, because it reads the clock: an
    /// `#expect` that prints a breaker built at an injected instant would
    /// otherwise print durations measured against a different one.
    package func report(at now: ContinuousClock.Instant = .now) -> String {
        var text = "\(turns) turns in \(started.duration(to: now))"
        if let overdueSince {
            text += ", the last \(overdueTurns) past its deadline in \(overdueSince.duration(to: now))"
        }
        return text
    }
}
