//  🖥️ TUI — A Terminal UI framework for Swift
//  State+OffMain.swift
//
//  `State` and `Binding` are `Sendable`, as SwiftUI's are, and how a `@State`
//  is read and written on any thread: one value behind a lock of the box's,
//  as SwiftUI's is.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Dispatch)
    import Dispatch
#endif
import Synchronization
import TUICore

// MARK: - Sendable

// `State`'s conformance is in State.swift, where a checked one has to be.

/// A `Binding` crosses to another thread, as SwiftUI's does, where its value
/// can: SwiftUI's conformance exactly, `@unchecked` there too, since a
/// binding is closures that say nothing of where they may run. The lint
/// exception is that spelling: SwiftUI's own.
///
/// A `@State`'s binding may be read and written on any thread. A binding made
/// with ``init(get:set:)`` runs its closures on whichever thread uses it, so
/// it is as safe as they are; one TUI makes for something other than a
/// `@State` — `@FocusState`, `@AppStorage`, a presentation's — is for the
/// main actor.
extension Binding: @unchecked Sendable where Value: Sendable {}  // swiftlint:disable:this concurrency_escape

/// Holds nothing a thread other than the main actor's reads unsynchronised:
/// that is ``StateBacking/value``'s design. `@unchecked` because its box is
/// written on the main actor only, under a lock only a read off it takes,
/// and the box's value is behind a lock of its own, neither of which the
/// compiler can see; and needed, for `State`'s conformance to be SwiftUI's
/// checked one.
extension StateBacking: @unchecked Sendable where Value: Sendable {}  // swiftlint:disable:this concurrency_escape

// MARK: - On any thread

/// The owner's O-25 (2026-11-21): a `@State` is read and written on any
/// thread; and O-25-FIRSTREAD's (d), "SwiftUI's shape" (2026-11-22): one value,
/// behind a lock of the box's, which no access holds while it waits for
/// anything, so none ever waits for the main actor.
///
/// - **A read in a render pass on the main actor** — a body's, a core's —
///   takes the pass's snapshot of the value, unlocked; the first in a pass
///   takes it, under the lock (``StateBox/stateValueOnMainActor()``). Any
///   write drops it, so a body that writes its state reads it back.
/// - **Every other read**, on the main actor (an action's, a handler's) or
///   off it, takes the lock.
/// - **A write, on any thread**, stores the value under the lock at once, so
///   any read after it, on any thread, reads it back. On the main actor it is
///   reported to the render cache there and then; off it, the report is
///   posted to the main queue, which is the main actor's, under the
///   transaction the write was made in, and made there in the order it was
///   posted: so before any frame drawn after it.
///
/// SwiftUI's is the same (measured from its binary, macOS 15.8.3): a
/// `StoredLocation`'s value is behind an `os_unfair_lock`; a read while the
/// thread updates the graph takes the `State`'s own snapshot, and every other
/// read the lock; a write stores under it at once and posts its commit to the
/// main run loop, asynchronously. Its snapshot is the view's, taken as the
/// body is evaluated; this one is the pass's, taken by its first read.
extension StateBacking {
    /// The value, read and written on any thread.
    var value: Value {
        get {
            guard StateIsolation.isMainActor else { return boxOffMain().lockedValue() }
            return box.stateValueOnMainActor()
        }
        set {
            guard StateIsolation.isMainActor else {
                writeOffMain(newValue)
                return
            }
            box.setStateValue(newValue)
        }
    }

    #if canImport(Dispatch)
        /// Stores `newValue` at once, and posts its report to the main actor.
        private func writeOffMain(_ newValue: Value) {
            let box = boxOffMain()
            box.storeStateValue(newValue)
            // Reported on the main actor under the transaction in force here,
            // which one made there would have been made under.
            let report = StoredWriteReport(box: box, transaction: Transaction.ambient)
            DispatchQueue.main.async {
                if let transaction = report.transaction {
                    Transaction.$ambient.withValue(transaction) { report.box.reportStoredWrite() }
                } else {
                    report.box.reportStoredWrite()
                }
            }
        }
    #else
        // One thread, with no queue to post to: every access is the main
        // actor's (`MainActorCheck`).
        private func writeOffMain(_ newValue: Value) { box.setStateValue(newValue) }
    #endif
}

/// A write stored off the main actor, its report on its way to the main
/// actor: the box it was stored in, and the transaction it was made under.
///
/// `@unchecked` because a box is not `Sendable`: what the main actor does
/// with it here — ask its sink for a frame — touches nothing a thread other
/// than the main actor's does. A struct, so posting it allocates nothing more
/// than the block that carries it.
private struct StoredWriteReport<Value>: @unchecked Sendable {  // swiftlint:disable:this concurrency_escape
    let box: StateBox<Value>
    let transaction: Transaction?
}

/// Whether a `@State` is being read or written on the main actor.
enum StateIsolation {
    /// ``MainActorCheck/isCurrent``, but first, off Darwin, whether this is
    /// the thread drawing a frame, a thread-local read: there a pool thread
    /// drains the main actor, and the check asks the queue, which costs more.
    @inline(__always)
    static var isMainActor: Bool {
        #if canImport(Darwin) || canImport(WASILibc)
            MainActorCheck.isCurrent
        #else
            BindingReads.isWalkingThread || MainActorCheck.isCurrent
        #endif
    }
}
