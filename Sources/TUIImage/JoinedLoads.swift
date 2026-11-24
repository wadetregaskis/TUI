//  🖥️ TUI — A Terminal UI framework for Swift
//  JoinedLoads.swift
//
//  One load per key at a time: a caller asking for a key while its load runs
//  waits for that load rather than starting its own. The image cache's join
//  table (`URLImageCache`), so it travels with the cache through the
//  environment, as the cache does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// The loads under way, by key, each shared by every caller that asks for its
/// key while it runs.
///
/// Thirty rows of a list showing one avatar start thirty loads in the frame
/// that first draws them, none of which finds the picture in the cache, since
/// none has landed. Each downloaded and decoded it (`URLSession`'s own cache
/// does not join requests in flight), filed its own decode over the last, and
/// went to the terminal as a picture of its own. Joined, they are one
/// download, one decode and one picture.
///
/// **Cancellation.** A caller's task cancelled while it waits stops waiting at
/// once, with `CancellationError`, and the load carries on for the others. The
/// load itself is cancelled when the last caller waiting on it has gone: a
/// list scrolled past a hundred pictures does not go on downloading the
/// hundred, and a single view's load is abandoned when it goes, as it was
/// before loads were joined. A caller that asks after that starts a new one.
///
/// The load is an unstructured task, as it has to be — it belongs to no one
/// caller — so it runs with the first caller's priority and task-local values.
package final class JoinedLoads<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private typealias Waiter = CheckedContinuation<Value, any Error>

    private struct Flight {
        /// Which load this is: a key's load abandoned by every caller is
        /// forgotten at once, and a new one can be under way by the time the
        /// abandoned one ends.
        let id: UInt64
        let task: Task<Void, Never>
        var waiters: [UInt64: Waiter]
    }

    private struct State {
        var flights: [Key: Flight] = [:]
        var nextID: UInt64 = 0
        var started = 0

        mutating func takeID() -> UInt64 {
            nextID &+= 1
            return nextID
        }
    }

    /// What a caller found when it asked.
    private enum Answer {
        case held(Value)
        case cancelled
        case waiting
    }

    private let state = Mutex(State())

    package init() {}

    /// The value for `key`: what `held` says is there already; or what the
    /// load of `key` under way comes back with; or, with none under way, what
    /// `load` comes back with, started here for this caller and every other
    /// that asks while it runs.
    ///
    /// - Parameters:
    ///   - held: The value kept for `key` already, if there is one. Called
    ///     with the table locked, so that a load landing cannot fall between
    ///     the look and the join.
    ///   - land: What a load's value becomes for its callers: filed where
    ///     `held` will find it, say, or what is there already. Called with the
    ///     table locked, as `held` is, before the load is let go of.
    ///   - load: The work, run once for every caller it is shared by.
    /// - Throws: What `load` throws, or `CancellationError` if the calling
    ///   task was cancelled while it waited.
    package func value(
        for key: Key, held: () -> Value?, land: @escaping @Sendable (Value) -> Value,
        load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let waiter = state.withLock { $0.takeID() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Waiter) in
                let answer = state.withLock { state -> Answer in
                    // A cancellation before this is one the handler could not
                    // find a waiter for; after it, the handler finds this one.
                    if Task.isCancelled { return .cancelled }
                    if let value = held() { return .held(value) }
                    if state.flights[key] != nil {
                        state.flights[key]?.waiters[waiter] = continuation
                        return .waiting
                    }
                    let id = state.takeID()
                    state.started += 1
                    let task = Task { await self.run(key, id: id, load: load, land: land) }
                    state.flights[key] = Flight(id: id, task: task, waiters: [waiter: continuation])
                    return .waiting
                }
                switch answer {
                case .held(let value): continuation.resume(returning: value)
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .waiting: break
                }
            }
        } onCancel: {
            leave(key, waiter: waiter)
        }
    }

    /// How many loads have been started: one for every key asked for while
    /// no load of it was under way and nothing was held for it.
    package var started: Int {
        state.withLock { $0.started }
    }

    /// How many callers wait on the load of a key `matching` says is wanted.
    package func waiting(where matching: (Key) -> Bool) -> Int {
        state.withLock { state in
            state.flights.reduce(0) { total, flight in total + (matching(flight.key) ? flight.value.waiters.count : 0) }
        }
    }

    /// Stops `waiter` waiting, and the load with it if no other caller waits.
    private func leave(_ key: Key, waiter: UInt64) {
        let (gone, abandoned) = state.withLock { state -> (Waiter?, Task<Void, Never>?) in
            guard let gone = state.flights[key]?.waiters.removeValue(forKey: waiter) else { return (nil, nil) }
            guard state.flights[key]?.waiters.isEmpty == true else { return (gone, nil) }
            return (gone, state.flights.removeValue(forKey: key)?.task)
        }
        gone?.resume(throwing: CancellationError())
        abandoned?.cancel()
    }

    /// Runs load `id` of `key`, and hands what it came back with to every
    /// caller still waiting on it.
    private func run(
        _ key: Key, id: UInt64, load: @Sendable () async throws -> Value, land: @Sendable (Value) -> Value
    ) async {
        let loaded: Result<Value, any Error>
        do {
            loaded = .success(try await load())
        } catch {
            loaded = .failure(error)
        }
        let (landed, waiters) = state.withLock { state -> (Result<Value, any Error>, [Waiter]) in
            // Landed even where every caller has gone: the work is done, and
            // the next to ask finds it.
            let landed = loaded.map(land)
            guard state.flights[key]?.id == id, let flight = state.flights.removeValue(forKey: key) else {
                return (landed, [])
            }
            return (landed, Array(flight.waiters.values))
        }
        for waiter in waiters { waiter.resume(with: landed) }
    }
}
