//  🖥️ TUI — A Terminal UI framework for Swift
//  MainActorCheck.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
    import Darwin
#endif
#if canImport(Dispatch)
    import Dispatch
#endif
import Foundation  // Thread, off Darwin
import Synchronization

/// Whether the thread asking is running the main actor's work: a question
/// Swift answers only with a trap (`MainActor.assumeIsolated`), asked here
/// with none.
///
/// The main thread always is. On Darwin nothing else ever is: the main actor's
/// executor is the main queue, which only the main thread drains, so the
/// answer is `pthread_main_np`, about 2 ns (arm64 `-O`, 2026-11-21, against
/// 4 for `Thread.isMainThread` and 19 to 65 for the queue's specific). On
/// Linux the main actor is drained by a pool thread after the first
/// suspension (see ``StackGuard``), and on Windows by a libdispatch worker
/// under Swift Testing, so there the thread does not answer: the queue does,
/// through a specific set on the main queue, which follows the main actor
/// to whichever thread drains it. A thread running the main queue's work
/// runs the main actor's, since that is the queue the main actor is.
package enum MainActorCheck {
    /// Whether the main actor's work is what this thread is running.
    /// Inlinable, so a `@State` read in another module pays the check, not a
    /// call to it.
    @inlinable
    package static var isCurrent: Bool {
        #if canImport(WASILibc)
            // One thread: WebAssembly's, with no queue to ask.
            true
        #elseif canImport(Darwin)
            pthread_main_np() != 0
        #else
            Thread.isMainThread || isMainQueue
        #endif
    }

    #if canImport(Dispatch) && !canImport(Darwin)
        /// Set on the main queue once, by whoever asks first. In a `Mutex`,
        /// which only ever lends it to `getSpecific`, as the open-source
        /// Dispatch does not call the key `Sendable`, and Apple's does.
        private static let key: Mutex<DispatchSpecificKey<Bool>> = {
            let key = DispatchSpecificKey<Bool>()
            DispatchQueue.main.setSpecific(key: key, value: true)
            return Mutex(key)
        }()

        /// Whether the queue this thread runs is the main queue.
        package static var isMainQueue: Bool {
            key.withLock { DispatchQueue.getSpecific(key: $0) == true }
        }
    #endif
}
