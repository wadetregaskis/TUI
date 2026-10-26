//  🖥️ TUI — A Terminal UI framework for Swift
//  RecheckTests.swift
//
//  A suspect — a row kept below a parent's write — is re-checked when it is
//  looked up: served if its rebuilt value and its environment are what it was
//  drawn from and under, dropped otherwise (Option C, C4c).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

/// A leaf whose buffer is its text, counting its renders.
private struct Leaf: View, Renderable {
    let text: String
    let renders: RenderCount
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renders.count += 1
        return FrameBuffer(text: text)
    }
}

extension Leaf: @preconcurrency Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }
}

private final class RenderCount {
    var count = 0
}

private struct ToneKey: EnvironmentKey {
    static let defaultValue = 0
}

@MainActor
@Suite("A suspect is re-checked")
struct RecheckTests {

    private let root = ViewIdentity(path: "Root")

    private func context(_ cache: RenderCache, storage: StateStorage, tone: Int = 0) -> RenderContext {
        var environment = EnvironmentValues()
        environment.renderCache = cache
        environment.stateStorage = storage
        environment[ToneKey.self] = tone
        return RenderContext(availableWidth: 10, availableHeight: 1, environment: environment, identity: root)
            .withChildIdentity(type: Leaf.self)
    }

    /// Draws `leaf` memoized in a pass, as a frame would.
    private func frame(_ leaf: Leaf, _ cache: RenderCache, _ storage: StateStorage, tone: Int = 0) -> String {
        cache.beginRenderPass()
        let lines = renderToBuffer(EquatableView(content: leaf), context: context(cache, storage: storage, tone: tone))
            .lines
        cache.removeInactive()
        return lines.joined()
    }

    private func setUp(serving: Bool) -> (RenderCache, StateStorage, RenderCount) {
        let cache = RenderCache()
        cache.revalidation.servesRechecked = serving
        return (cache, StateStorage(), RenderCount())
    }

    @Test("Unchanged, after a parent's write: served, not drawn again")
    func unchangedIsServed() {
        let (cache, storage, renders) = setUp(serving: true)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        cache.link.invalidateRenderSoftly(for: root)
        #expect(frame(Leaf(text: "a", renders: renders), cache, storage) == "a")
        #expect(renders.count == 1)
        #expect(cache.revalidation.counts.rechecked == 1)
    }

    @Test("Changed value: drawn again")
    func changedValueIsDrawn() {
        let (cache, storage, renders) = setUp(serving: true)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        cache.link.invalidateRenderSoftly(for: root)
        #expect(frame(Leaf(text: "b", renders: renders), cache, storage) == "b")
        #expect(renders.count == 2)
        #expect(cache.revalidation.counts.unequalValues == 1)
    }

    @Test("Changed environment: drawn again")
    func changedEnvironmentIsDrawn() {
        let (cache, storage, renders) = setUp(serving: true)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage, tone: 1)
        cache.link.invalidateRenderSoftly(for: root)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage, tone: 2)
        #expect(renders.count == 2)
        #expect(cache.revalidation.counts.unequalEnvironments == 1)
    }

    @Test("With serving off, a suspect is dropped as the hard drain would have dropped it")
    func servingOff() {
        let (cache, storage, renders) = setUp(serving: false)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        cache.link.invalidateRenderSoftly(for: root)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        #expect(renders.count == 2)
        #expect(cache.revalidation.counts.rechecked == 0)
        #expect(cache.revalidation.counts.suspectsDropped == 1)
    }

    @Test("A row whose value keeps changing stops being compared, and is re-checked again once it settles")
    func cooldown() {
        let (cache, storage, renders) = setUp(serving: true)
        // Changing on every parent's write: compared twice, then less and
        // less often — cooldowns of 2, 4, 8 … passes — not ten times in ten.
        for step in 0..<10 {
            _ = frame(Leaf(text: "\(step)", renders: renders), cache, storage)
            cache.link.invalidateRenderSoftly(for: root)
        }
        #expect(cache.revalidation.counts.unequalValues <= 3, "\(cache.revalidation.counts)")
        // Settled: within 64 passes it is recorded again, and served.
        for _ in 0..<70 {
            _ = frame(Leaf(text: "settled", renders: renders), cache, storage)
            cache.link.invalidateRenderSoftly(for: root)
        }
        #expect(cache.revalidation.counts.rechecked > 0)
    }

    @Test("A hard write above it drops it, served or not")
    func hardWriteDrops() {
        let (cache, storage, renders) = setUp(serving: true)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        cache.link.invalidateRender(for: root)
        _ = frame(Leaf(text: "a", renders: renders), cache, storage)
        #expect(renders.count == 2)
    }
}
