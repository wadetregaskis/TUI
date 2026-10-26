//  🖥️ TUI — A Terminal UI framework for Swift
//  SoftInvalidationTests.swift
//
//  The invalidation queue tells a parent's write — a composite `@State`'s, or
//  a body's observed read — from any other, and still drains both as hard
//  (Option C, C4a). What a drain keeps below a soft writer is C4b's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUICore
@testable import TUIView

@Observable
private final class Shown {
    var title = "a"
}

/// A composite whose body reads the model.
private struct Reader: View {
    let shown: Shown
    var body: some View { ReaderLeaf(title: shown.title) }
}

private struct ReaderLeaf: View, Renderable {
    let title: String
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer { FrameBuffer(text: title) }
}

@MainActor
@Suite("Soft invalidation is told from hard")
struct SoftInvalidationTests {

    @Test("A composite @State's box writes softly; a core's slot writes hard")
    func softBoxes() {
        let storage = StateStorage()
        let identity = ViewIdentity(path: "Root/View")
        let composite = storage.compositeStorage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: 0)
        let core = storage.storage(for: StateStorage.StateKey(identity: identity, propertyIndex: -1), default: 0)
        #expect(composite.invalidatesSoftly)
        #expect(!core.invalidatesSoftly)
    }

    @Test("A bound @State's write is queued soft; a core slot's hard; both still drop what they dropped")
    func stateWrites() {
        let storage = StateStorage()
        let cache = RenderCache()
        storage.renderCache = cache
        let identity = ViewIdentity(path: "Root/State")
        var state = State(wrappedValue: 0)
        _ = withUnsafeMutablePointer(to: &state) {
            State<Int>.bindState(
                at: UnsafeMutableRawPointer($0), to: storage,
                key: StateStorage.StateKey(identity: identity, propertyIndex: 0))
        }
        state.wrappedValue = 1
        var pending = cache.link.drain()
        #expect(pending.identities == [identity])
        #expect(pending.softOnly == [identity])

        let core = storage.storage(for: StateStorage.StateKey(identity: identity, propertyIndex: -1), default: 0)
        core.value = 1
        pending = cache.link.drain()
        #expect(pending.identities == [identity])
        #expect(pending.softOnly.isEmpty)

        // Drained as hard still (C4a): the stored entry at the writer goes.
        cache.store(
            identity: identity, view: 0, buffer: FrameBuffer(text: "cached"), contextWidth: 80, contextHeight: 24)
        state.wrappedValue = 2
        cache.beginRenderPass()
        #expect(cache.lookup(identity: identity, view: 0, contextWidth: 80, contextHeight: 24) == nil)
    }

    @Test("One hard report of an identity makes it hard, before or after soft ones; a clear of all supersedes")
    func mergeLattice() {
        let cache = RenderCache()
        let link = cache.link
        defer { withExtendedLifetime(cache) {} }  // a cache that has gone detaches its link, which queues nothing
        let a = ViewIdentity(path: "A")
        let b = ViewIdentity(path: "B")
        link.invalidateRenderSoftly(for: a)
        link.invalidateRender(for: a)
        link.invalidateRender(for: b)
        link.invalidateRenderSoftly(for: b)
        var pending = link.drain()
        #expect(pending.identities == [a, b])
        #expect(pending.softOnly.isEmpty)

        link.invalidateRenderSoftly(for: a)
        link.invalidateRenderSoftly(for: a)
        pending = link.drain()
        #expect(pending.softOnly == [a])

        link.invalidateRenderSoftly(for: a)
        link.invalidateRender(for: nil)
        pending = link.drain()
        #expect(pending.clearAll)
        #expect(pending.identities.isEmpty && pending.softOnly.isEmpty)
    }

    @Test("A body's observed read reports softly")
    func observedBodyIsSoft() {
        let cache = RenderCache()
        let shown = Shown()
        var environment = EnvironmentValues()
        environment.renderCache = cache
        environment.stateStorage = StateStorage()
        let context = RenderContext(
            availableWidth: 20, availableHeight: 2, environment: environment, identity: ViewIdentity(path: "Root"))
        _ = renderToBuffer(Reader(shown: shown), context: context)
        _ = cache.link.drain()
        shown.title = "b"
        let pending = cache.link.drain()
        #expect(!pending.identities.isEmpty, "the write reached no scope")
        #expect(pending.softOnly == pending.identities)
    }
}
