//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+Link.swift
//
//  The way back to a render cache for whatever keeps one past the render that
//  made it, without a weak reference to the cache.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension RenderCache {
    /// What names a cache without owning it, for a holder that has to act on
    /// the cache's tables at once (a focus move, a control's drawing report).
    ///
    /// It names the cache `unowned`, which keeps no strong count and, unlike a
    /// weak reference, moves nothing to a side table: the unowned count is kept
    /// inline beside the strong one. The cache's `deinit` clears it first thing,
    /// so a holder that outlives the cache reads `nil`, as through a weak
    /// reference. `unowned`, not `unowned(unsafe)`: a holder reading a cache
    /// already deinitializing traps, rather than reading freed memory.
    ///
    /// Not `Sendable`, unlike the ``Link``, so the compiler keeps it with its
    /// holders on the render path, where caches are released: it cannot be
    /// cleared while it is being read.
    package final class Handle {
        /// The cache, or `nil` once it has gone.
        package private(set) unowned var cache: RenderCache?

        init() {}

        /// Called by the cache's `init`.
        func attach(_ cache: RenderCache) {
            self.cache = cache
        }

        /// Called first thing in the cache's `deinit`.
        func detach() {
            cache = nil
        }
    }

    /// The way back to a render cache for something that keeps it past the
    /// render that made it — a `@State` box, an observation registration, a
    /// control's handler, the focus manager — without a weak reference to the
    /// cache.
    ///
    /// A weak reference is not free for the object it names. The first one
    /// moves the object's reference count into a side table for the rest of
    /// the object's life, and from then on every retain and release of it takes
    /// the runtime's slow path through that table. This cache is retained and
    /// released with every context a render copies, and an app's cache was
    /// referenced weakly from its first frame: its `StateStorage`, every
    /// `@State` box's sink (stamped again at every hydration), the focus
    /// manager and every observed body's registration held it so. Counted with
    /// an interposed retain counter (2026-09-27), 27,688 of its retains and
    /// releases a frame went through the side table on the `chat` session,
    /// 16,053 on `notes`, 8,789 on `settings`.
    ///
    /// So such a holder keeps this instead, strongly. It is made with the cache
    /// and belongs to it, and it holds nothing that holds the cache, so keeping
    /// it keeps nothing alive and makes no cycle: a buffer's journal, which the
    /// cache keeps, can hold it.
    ///
    /// It is the way in from any thread, ``invalidateRender(for:)``: the queue of
    /// invalidations a `@State` write or an `@Observable` change makes, which
    /// the cache drains on the main actor at ``RenderCache/beginRenderPass()``,
    /// and the frame each one asks for, of the ``AppState`` of the app the cache
    /// draws (``requestFrames(from:)``). It lives here, not on the cache, so a
    /// write on another thread never touches the cache at all. Once the cache has
    /// gone the queue is closed: a report does nothing, and asks for no frame.
    /// To act on the cache's tables at once, a holder keeps its ``Handle``.
    package final class Link: RenderInvalidationSink, Sendable {
        /// What the link's lock guards: the queue, whether the cache is still
        /// there to drain it, the app a write asks for a frame, and the
        /// diagnostic a write reports to.
        private struct Queue: Sendable {
            /// `false` once the cache has gone: nothing is queued, no frame is
            /// asked for.
            var attached = true
            /// `true` once a whole-cache clear is requested; supersedes
            /// `identities`.
            var clearAll = false
            /// Subtrees whose cached buffers must be dropped (unless
            /// `clearAll`).
            var identities: Set<ViewIdentity> = []
            /// Those of `identities` every report of which was SOFT — a
            /// parent's write (Option C, §2.1): one hard report of an
            /// identity makes it hard, whatever came before or after.
            var softOnly: Set<ViewIdentity> = []
            /// The render state of the app the cache draws, which every report
            /// asks for a frame — and whose pending transaction a report made
            /// inside `withAnimation` sets — or `nil` for a cache no app
            /// draws, whose reports ask nobody. Strong: an `AppState` holds
            /// nothing that holds the link.
            var appState: AppState?
            /// The cache's ``RenderCache/bodyMutationDiagnostic``, mirrored
            /// here so a write on another thread reads it without reading the
            /// cache.
            var diagnostic: BodyMutationDiagnostic?
            /// How many invalidations have been queued since the link was
            /// made — see ``writeCount``.
            var writes: UInt64 = 0
        }

        /// What a drain takes: the invalidations queued since the last one.
        package struct Pending: Sendable {
            /// Whether a whole-cache clear was asked for.
            package let clearAll: Bool
            /// The identities queued, when `clearAll` is not set.
            package let identities: Set<ViewIdentity>
            /// Those of ``identities`` only ever reported softly — written by a
            /// composite `@State`, or read by a body whose observation fired.
            /// The drain still drops what it drops for a hard writer (C4a);
            /// Option C's soft drain keeps what is below them (C4b).
            package let softOnly: Set<ViewIdentity>
        }

        private let queue = Lock(initialState: Queue())

        init() {}

        /// Called first thing in the cache's `deinit`: from here on a report goes
        /// nowhere.
        func detach() {
            queue.withLock { queue in
                queue.attached = false
                queue.clearAll = false
                queue.identities.removeAll()
                queue.softOnly.removeAll()
                queue.appState = nil
                queue.diagnostic = nil
            }
        }

        /// Makes every report from now on ask `appState` for a frame: the
        /// render state of the app whose cache this is, which its run loop
        /// polls and whose pending transaction its next frame draws under.
        /// Called by the `TUIContext` that owns the cache, as it is assembled.
        ///
        /// Per app, not the process's: a frame requested of the process's one
        /// render state was drawn by whichever app drew next, and that app took
        /// the transaction a change was made under — two apps in one process
        /// (two tests running at once) animated each other's changes, or
        /// snapped their own.
        package func requestFrames(from appState: AppState?) {
            queue.withLock { $0.appState = appState }
        }

        /// Mirrors the cache's diagnostic, which a write reports to.
        func setDiagnostic(_ diagnostic: BodyMutationDiagnostic?) {
            queue.withLock { $0.diagnostic = diagnostic }
        }

        /// Queues an invalidation and asks for a frame — what a `@State` write
        /// does. Thread-safe; the cache's tables are changed later, on the
        /// main actor, by the drain. Does nothing once the cache has gone.
        ///
        /// - Parameter identity: The subtree whose cached buffers are now stale,
        ///   or `nil` to drop the whole cache.
        package func invalidateRender(for identity: ViewIdentity?) {
            enqueue(identity)?.setNeedsRender()
        }

        /// ``invalidateRender(for:)`` for an `@Observable` change a body's
        /// observation reported: the frame is asked as an observed change's
        /// (`AppState.setNeedsRenderForObservedChange()`), so a later write
        /// under `withAnimation` that the spent observation cannot report
        /// still animates it.
        package func invalidateRenderForObservedChange(at identity: ViewIdentity, softly: Bool = false) {
            enqueue(identity, softly: softly)?.setNeedsRenderForObservedChange()
        }

        /// ``invalidateRender(for:)`` for a parent's write: a composite
        /// `@State`'s, whose view's body — and so the values of the views it
        /// makes — is certain to be evaluated again (Option C, §2.1).
        package func invalidateRenderSoftly(for identity: ViewIdentity) {
            enqueue(identity, softly: true)?.setNeedsRender()
        }

        /// Queues the invalidation of `identity` (`nil`: of everything), and
        /// returns the app state to ask for the frame — `nil` once the cache
        /// has gone, or for a cache no app draws.
        private func enqueue(_ identity: ViewIdentity?, softly: Bool = false) -> AppState? {
            typealias Report = (queued: Bool, appState: AppState?, diagnostic: BodyMutationDiagnostic?)
            let (queued, appState, diagnostic) = queue.withLock { queue -> Report in
                guard queue.attached else { return (false, nil, nil) }
                queue.writes &+= 1
                if let identity {
                    if !queue.clearAll {
                        let (isNew, _) = queue.identities.insert(identity)
                        if !softly {
                            queue.softOnly.remove(identity)
                        } else if isNew {
                            queue.softOnly.insert(identity)
                        }
                    }
                } else {
                    queue.clearAll = true
                    queue.identities.removeAll(keepingCapacity: true)
                    queue.softOnly.removeAll(keepingCapacity: true)
                }
                return (true, queue.appState, queue.diagnostic)
            }
            guard queued else { return nil }
            // Opt-in, and free when off: one optional test. See
            // `BodyMutationDiagnostic` for why a write during the walk is worth
            // naming — this is the single funnel every `@State` write reaches,
            // so it is the only place that needs to ask. Outside the lock: it
            // may print.
            diagnostic?.note(identity)
            // The frame is asked outside the lock too: the app state calls its
            // observers.
            return appState
        }

        /// Asks the app the cache draws for a frame, and drops nothing the
        /// cache keeps — for a change the drawing shows that no memo keeps:
        /// one a view reads as an unkeyed read (`recordUnkeyedRead`), so no
        /// memo above it stores what it drew. Thread-safe. Does nothing once
        /// the cache has gone.
        package func requestFrame() {
            let appState = queue.withLock { $0.attached ? $0.appState : nil }
            appState?.setNeedsRender()
        }

        /// ``requestFrame()`` for an `@Observable` change a frame-only scope
        /// reported (`observingFrameReads`, `observingStyleBody`): asked as an
        /// observed change's, as ``invalidateRenderForObservedChange(at:)``
        /// asks it, and dropping nothing.
        package func requestFrameForObservedChange() {
            // Counted as a write (``writeCount``): an effect that wrote what
            // only such a read saw has made the walk out of date as surely as
            // one that wrote a body's read.
            let appState = queue.withLock { queue -> AppState? in
                guard queue.attached else { return nil }
                queue.writes &+= 1
                return queue.appState
            }
            appState?.setNeedsRenderForObservedChange()
        }

        /// How many invalidations — a `@State` write, an `@Observable` change a
        /// body read, a whole-cache clear — have been queued since the link was
        /// made: what tells a frame's driver that the effects it has just run
        /// wrote state, so the walk it made is out of date (`FrameSettling`).
        /// A count, not a flag, so reading it takes nothing from the queue.
        /// Thread-safe.
        package var writeCount: UInt64 {
            queue.withLock { $0.writes }
        }

        /// Whether the cache is still there: `false` from the start of its
        /// `deinit` on. Thread-safe, unlike ``cache``.
        package var isAttached: Bool {
            queue.withLock { $0.attached }
        }

        /// Takes what has been queued since the last drain, leaving the queue
        /// empty. Called by the cache, on the main actor.
        func drain() -> Pending {
            queue.withLock { queue in
                let pending = Pending(
                    clearAll: queue.clearAll, identities: queue.identities, softOnly: queue.softOnly)
                queue.clearAll = false
                queue.identities.removeAll(keepingCapacity: true)
                queue.softOnly.removeAll(keepingCapacity: true)
                return pending
            }
        }
    }
}
