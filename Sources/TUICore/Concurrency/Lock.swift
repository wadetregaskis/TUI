//  🖥️ TUI — A Terminal UI framework for Swift
//  Lock.swift
//
//  Created by LAYERED.work
//  License: MIT

import Synchronization

/// A reference to a `Mutex`-guarded value: for the places that want a lock
/// as an object, which `Mutex` itself cannot be, being noncopyable.
///
/// Elsewhere a stored `let` of `Mutex` is simpler, and one allocation and one
/// load cheaper; but see the trap below. `Mutex` is `os_unfair_lock` on Darwin, a futex on Linux, an
/// SRW lock on Windows, and a single compare-and-swap on a WebAssembly without
/// threads; so this one type behaves the same on all of them.
///
/// `State` and what the body returns must be `Sendable`, as the body must, so
/// nothing reachable from the state outlives the lock. A lock is not
/// re-entrant: taking it again on the same thread ends the process, on macOS
/// with a SIGKILL that nothing can catch, so a body must not call out.
///
/// The trap: the `Synchronization` module is built in Swift 5 mode, so Swift 6
/// checks the executor on entry to a closure passed to `Mutex.withLock` from a
/// main-actor function (SE-0423), about 100 ns where the lock itself costs 3.
/// The closure of a nonisolated function, or the `@Sendable` body taken here,
/// has no check to make.
package final class Lock<State: Sendable>: Sendable {
    private let mutex: Mutex<State>

    /// Creates a lock with the given initial state.
    ///
    /// - Parameter initialState: The initial protected state.
    package init(initialState: State) {
        mutex = Mutex(initialState)
    }

    /// Executes the closure while holding the lock and returns the result.
    ///
    /// - Parameter body: The closure to execute with exclusive access to the state.
    /// - Returns: The value returned by the closure.
    package func withLock<R: Sendable, Failure: Error>(
        _ body: @Sendable (inout State) throws(Failure) -> R
    ) throws(Failure) -> R {
        try mutex.withLock { (state: inout sending State) throws(Failure) -> sending R in
            try body(&state)
        }
    }
}
