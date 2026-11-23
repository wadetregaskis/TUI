//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderRequestWake.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// Wakes the run loop for the app's render requests, once a pass however many
/// there are.
///
/// Every `setNeedsRender()`, `setNeedsAnimationTick(_:)` and exit request calls
/// the app state's observers, on any thread, and the loop's observer has to hop
/// to the main actor to wake the loop. It used to make a `Task` for each call:
/// a key that changed state made several (the consumed key, a focus move, each
/// `@State` write), and the timer posts a tick for each of the two animation
/// clocks on every wake. The first resumed the waiting loop and each of the
/// others, finding no waiter, left a wake pending, so the loop drew its frame
/// and then went round again with nothing to do: two passes for every timer
/// wake on a page whose only activity is a spinner.
///
/// Now a request posts a delivery only when none is owed, and the loop marks
/// what is owed served (``served()``) just before it reads what was asked for.
/// A delivery that runs after that finds nothing owed and wakes nothing, while
/// a request made after it, whatever its thread, posts or finds a delivery
/// still to run, which wakes the loop: the request was made after the loop
/// read, so that pass did not serve it.
///
/// Why that never loses a wake: a request sets what it asks for (under the app
/// state's lock) before it calls ``request()``, and the loop calls ``served()``
/// before it reads it. So a request the loop's read missed came after
/// `served()` cleared ``owed``, and either set it (and posted the delivery) or
/// found it set by another request made after `served()` too, whose delivery
/// has not run yet, since a delivery that runs clears it. Either way a delivery
/// to run finds it set and wakes the loop. A delivery that finds it set wakes
/// the loop even if what it was posted for was served: one spare pass, where
/// a request lands between `served()` and the read, as against two a wake.
final class RenderRequestWake: Sendable {
    /// Whether a request is waiting for a wake no pass has served: set by
    /// ``request()``, cleared by ``served()`` and by the delivery that wakes.
    private let owed = Atomic<Bool>(false)

    /// Runs `delivery` on the main actor, later. A `Task`; a test passes what
    /// keeps the deliveries to run when it chooses.
    private let post: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    /// What wakes the loop: its notifier's `wake()`.
    private let wake: @MainActor @Sendable () -> Void

    init(
        post: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { delivery in
            Task { @MainActor in delivery() }
        },
        wake: @escaping @MainActor @Sendable () -> Void
    ) {
        self.post = post
        self.wake = wake
    }

    /// Asks for a wake, from any thread: posts a delivery unless one is already
    /// owed. The app state's observer.
    func request() {
        guard !owed.exchange(true, ordering: .sequentiallyConsistent) else { return }
        post { [self] in deliver() }
    }

    /// Marks every request made so far served: the loop is about to read what
    /// they asked for.
    func served() {
        owed.store(false, ordering: .sequentiallyConsistent)
    }

    /// Wakes the loop if a request is still owed one.
    @MainActor private func deliver() {
        if owed.exchange(false, ordering: .sequentiallyConsistent) { wake() }
    }
}
