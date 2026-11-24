//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameObservation.swift
//
//  The reads nothing keeps: observed for a frame, and nothing else.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Synchronization
import TUICore

// MARK: - Reads nothing keeps

// A read is observed for what it can make stale: in a body
// (`evaluateCompositeBody(of:context:)`), and beneath any result the cache
// keeps (`observingKeptResult(of:kind:context:_:)`), each invalidating where it
// was made. A read made outside both makes nothing stale — nothing keeps what
// it drew, and the next walk reads it again — but it needs that next walk,
// and nothing asked for one: a write made outside an event (a timer, a
// network reply, a `Task`) left a top-level `Toggle` bound to an `@Observable`,
// a custom `ButtonStyle` reading one, or an `App` body reading one, showing
// the old value until something else drew.
//
// Three kinds of read are made outside both, each observed here for a frame:
//
// - the `App`'s body (``observingFrameReads(cache:identity:_:)`` around it);
// - a control's `Binding`, read in its core after the body that made it has
//   returned: every `Binding` read on the main thread during the walk is
//   noted (``BindingReads``) and read again after it, under one scope;
// - a custom style's `makeBody`, evaluated in a control's core
//   (``observingStyleBody(of:kind:context:_:)``).
//
// NOT one scope around the whole walk, which was the first cut: a scope sees
// every read beneath it, nested scopes' included, so it re-registered every
// read of the frame, and a session whose kept results are rewritten every
// step (`editor`) paid +9.1% for installing and cancelling it.
//
// Each scope is leased as every other is (`ObservationLeases`), so a read made
// every frame of a property nobody writes leaves nothing behind once the
// frame is replaced.

/// The reader the frame's own scopes are observed as: a type of its own, so
/// the cache learns that frames read as it learns that a view type does.
package enum FrameWalk {}

/// Runs `compute` under an observation scope whose change asks the app the
/// cache draws for a frame, and invalidates nothing.
@inline(__always)
@MainActor
package func observingFrameReads<T>(cache: RenderCache?, identity: ViewIdentity, _ compute: () -> T) -> T {
    let sentinel = cache?.scopeSentinel(forReader: FrameWalk.self, at: identity)
    return withObservationTracking(
        {
            sentinel?.touch()
            return compute()
        },
        onChange: frameChange(cache: cache, reader: FrameWalk.self, kind: .frame, sentinel: sentinel))
}

/// Evaluates a style's `makeBody(configuration:)` — `make` — where a
/// control's core draws or measures it, under an observation scope that asks
/// for a frame when anything it read changes.
///
/// A style composed in a public `body` (as `Label` composes its style) is a
/// body's read already; a control whose configuration exists only once its
/// core has registered with the focus (a button's `isPressed`, a toggle's
/// value) evaluates it in the core, outside any body. Beneath a kept result
/// the reads also reach that result's scope, which invalidates it.
@inline(__always)
@MainActor
package func observingStyleBody<T>(
    of style: Any.Type, kind: ObservationCensus.Kind, context: RenderContext, _ make: () -> T
) -> T {
    let cache = context.renderCache
    let sentinel = cache?.scopeSentinel(forReader: style, at: context.identity)
    return withObservationTracking(
        {
            sentinel?.touch()
            return make()
        },
        onChange: frameChange(cache: cache, reader: style, kind: kind, sentinel: sentinel))
}

/// What a frame-only scope's change does: asks for a frame, unless its lease
/// has retired it. Evaluated only when the scope arms (it is `onChange`'s
/// autoclosure), so a scope that read nothing teaches the cache nothing.
@MainActor
private func frameChange(
    cache: RenderCache?, reader: Any.Type, kind: ObservationCensus.Kind, sentinel: ScopeSentinel?
) -> @Sendable () -> Void {
    if sentinel == nil { cache?.noteReads(reader) }
    let cancellation = cache?.leases.cancellation(armedWith: sentinel)
    let registration = cache?.observationCensus?.arm(
        kind, unleased: sentinel == nil && cache?.leases.retirement != .never)
    return { [link = cache?.link] in
        if let cancellation, cancellation.isRetired {
            registration?.cancel()
            return
        }
        registration?.fire()
        if let link {
            link.requestFrameForObservedChange()
        } else {
            AmbientApp.renderState?.setNeedsRender()
        }
    }
}

// MARK: - Binding reads

/// The `Binding`s read during a frame's walk, to be read again after it under
/// one frame-only scope (``observingFrameReads(cache:identity:_:)``).
///
/// Noted only on the thread walking, and only between ``begin()`` and
/// ``end()``: a read anywhere else is not a drawing's. A getter read twice is
/// what SwiftUI allows too: it calls them as often as it likes.
package enum BindingReads {
    /// The reads noted since ``begin()``; `nil` outside a walk. Touched only on
    /// the thread walking, which is checked before it is read.
    ///
    /// `nonisolated(unsafe)` because `Binding.wrappedValue`, which notes here,
    /// is not isolated, as SwiftUI's is not, and what it notes is its getter, a
    /// closure that is not `Sendable`: a `Mutex` would not take it, and a
    /// `MainActor.assumeIsolated` could not be handed it. The check Swift cannot
    /// see is the one below, and a wider thread-local would only hide it.
    nonisolated(unsafe) private static var noted: [() -> Void]?  // swiftlint:disable:this concurrency_escape

    /// Starts noting.
    @MainActor
    package static func begin() {
        unsafe noted = []
        #if !canImport(Darwin) && !canImport(WASILibc)
            walkingThread.set()
        #endif
    }

    /// Stops noting, and returns what was noted.
    @MainActor
    package static func end() -> [() -> Void] {
        defer {
            unsafe noted = nil
            #if !canImport(Darwin) && !canImport(WASILibc)
                walkingThread.clear()
            #endif
        }
        return unsafe noted ?? []
    }

    /// Whether this thread is the one walking.
    ///
    /// On Darwin the main actor is the main thread, so the main thread is the
    /// one walking. On WebAssembly's wasip1, which is single-threaded and has
    /// no `Thread` to ask, it always is (as `BodyMutationDiagnostic.callingThread`).
    /// Everywhere else the walk marks its thread (``WalkingThreadMark``): on
    /// Linux the main actor is drained by a pool thread after the first
    /// suspension (see `StackGuard`), and on Windows by a libdispatch worker —
    /// Swift Testing's is (measured, 6.3.3): a top-level `Toggle`'s binding went
    /// unnoted, and a write to it asked for no frame — so `Thread.isMainThread`
    /// is false for the walk there. The mark is the default, not a list of the
    /// platforms known to need it: a platform not yet run on whose main actor
    /// is the main thread pays a comparison, and one whose is not stays right.
    static var isWalkingThread: Bool {
        #if canImport(Darwin)
            Thread.isMainThread
        #elseif canImport(WASILibc)
            true
        #else
            walkingThread.isCallingThread
        #endif
    }

    #if !canImport(Darwin) && !canImport(WASILibc)
        /// The mark ``isWalkingThread`` reads, set and cleared by ``begin()``
        /// and ``end()`` on the main actor.
        private static let walkingThread = WalkingThreadMark()
    #endif

    /// Notes `get`, a binding's getter, when a walk is noting. Generic, and
    /// wrapped only after the checks, so a read outside a walk allocates
    /// nothing.
    @inline(__always)
    static func note<Value>(_ get: @escaping () -> Value) {
        guard isWalkingThread, unsafe noted != nil else { return }
        unsafe noted?.append { _ = get() }
    }
}

#if !canImport(WASILibc)
    /// Which thread, if any, is marked: a token for it, one word, set by the
    /// thread itself and compared by any thread against its own.
    ///
    /// ``BindingReads`` marks the thread walking a frame with one. Not a
    /// thread-local, which it was on Linux (`pthread_setspecific`) and on
    /// Windows (`TlsSetValue`): one mark, cleared by whichever thread ends the
    /// walk, cannot be left set on a thread the main actor has since left —
    /// which a thread-local would be, were `begin()` and `end()` ever to run on
    /// two — and needs nothing of the platform but Foundation's `Thread`.
    ///
    /// The token is the `Thread` object's identity, as
    /// `BodyMutationDiagnostic.callingThread`'s is: stable while the thread
    /// runs, as each thread keeps its `Thread` for its life, and so equal to
    /// no other running thread's. An atomic rather than a `Mutex`, as the
    /// whole state is the one word; with no thread marked a read is one load,
    /// and asks `Thread` nothing. Compiled on Darwin too, unused there, so its
    /// tests run there.
    package final class WalkingThreadMark: Sendable {
        /// The marked thread's token; `0` when none is marked.
        private let holder = Atomic<UInt>(0)

        package init() {}

        /// Marks the calling thread, in place of any thread marked before.
        package func set() {
            holder.store(Self.callingThread, ordering: .releasing)
        }

        /// Marks no thread, whichever thread calls.
        package func clear() {
            holder.store(0, ordering: .releasing)
        }

        /// Whether the calling thread is the one marked.
        package var isCallingThread: Bool {
            let held = holder.load(ordering: .acquiring)
            return held != 0 && held == Self.callingThread
        }

        /// The calling thread's token; never `0`, which no object's address is.
        private static var callingThread: UInt {
            UInt(bitPattern: ObjectIdentifier(Thread.current))
        }
    }
#endif
