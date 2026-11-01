//  🖥️ TUI — A Terminal UI framework for Swift
//  TestClock.swift
//
//  A clock a test moves by hand, for the waits a view's own code makes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A `Clock` whose time passes only when a test says, for the waits a view's own
/// code makes.
///
/// ``TestApp/advance(by:)`` moves what the frames read, but a `Task.sleep` in a
/// `.task` sleeps on the machine's clock, which nothing can hurry. So have the
/// view sleep on a clock it is given, the real one in the app and this one in a
/// test:
///
/// ```swift
/// struct Ticker<C: Clock<Duration>>: View {
///     let clock: C
///     @State private var ticks = 0
///
///     var body: some View {
///         Text("Ticks: \(ticks)").task {
///             while let _ = try? await clock.sleep(for: .seconds(1)) { ticks += 1 }
///         }
///     }
/// }
///
/// @MainActor
/// @Test func ticks() async throws {
///     let clock = TestClock()
///     let app = TestApp { Ticker(clock: clock) }
///     try await app.wait(until: { clock.sleepers == 1 })
///     clock.advance(by: .seconds(1))
///     try await app.wait(for: "Ticks: 1")
/// }
/// ```
public final class TestClock: Clock, @unchecked Sendable {
    /// A reading of a ``TestClock``.
    public struct Instant: InstantProtocol {
        fileprivate var offset: Duration

        public func advanced(by duration: Duration) -> Self { Self(offset: offset + duration) }
        public func duration(to other: Self) -> Duration { other.offset - offset }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    /// A task asleep on the clock.
    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var reading = Instant(offset: .zero)
    private var asleep: [Sleeper] = []
    private var nextSleeperID = 0

    /// Creates a clock reading zero.
    public init() {}

    /// The clock's reading.
    public var now: Instant { lock.withLock { reading } }

    /// The clock has no resolution to speak of: it reads what it was told.
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// How many tasks are asleep on the clock, for a test that must not move it
    /// until a task has gone to sleep.
    public var sleepers: Int { lock.withLock { asleep.count } }

    /// Sleeps until the clock reads `deadline`, which is at once if it already
    /// has, or until the task is cancelled, which throws `CancellationError`.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = lock.withLock {
            nextSleeperID += 1
            return nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let isDue = lock.withLock {
                    guard reading < deadline else { return true }
                    asleep.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if isDue { continuation.resume() }
                if Task.isCancelled { wake(id, with: .failure(CancellationError())) }
            }
        } onCancel: {
            wake(id, with: .failure(CancellationError()))
        }
    }

    /// Moves the clock on by `duration`, and wakes every task whose time has come.
    ///
    /// A task that wakes runs when it gets its turn, which on the main actor is
    /// when your test next suspends, so wait for what it does with
    /// ``TestApp/wait(for:timeout:)``.
    public func advance(by duration: Duration) {
        let due = lock.withLock {
            reading = reading.advanced(by: duration)
            let now = reading
            let due = asleep.filter { $0.deadline <= now }
            asleep.removeAll { $0.deadline <= now }
            return due.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Wakes one sleeper, if it is still asleep.
    private func wake(_ id: Int, with result: Result<Void, any Error>) {
        let sleeper = lock.withLock { () -> Sleeper? in
            guard let index = asleep.firstIndex(where: { $0.id == id }) else { return nil }
            return asleep.remove(at: index)
        }
        sleeper?.continuation.resume(with: result)
    }
}
