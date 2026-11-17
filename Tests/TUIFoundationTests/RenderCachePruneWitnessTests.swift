//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCachePruneWitnessTests.swift
//
//  A render cache's prune skips its walk over the entries when the pass
//  changed nothing an entry's verdict reads (`PruneWitness`), and walks again
//  the moment anything did: an entry stored, a different set marked active,
//  a different subtree retained.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A render cache's prune skips a pass that changed nothing")
struct RenderCachePruneWitnessTests {
    private let root = ViewIdentity(path: "Root")
    private let card = ViewIdentity(path: "Root/Card")
    private let rows = (0..<3).map { ViewIdentity(path: "Root/Card/Row\($0)") }

    /// A cache with a picture at each row below the card.
    private func cache() -> RenderCache {
        let cache = RenderCache()
        for (index, row) in rows.enumerated() {
            cache.store(identity: row, view: index, buffer: FrameBuffer(text: "row \(index)"), contextWidth: 80, contextHeight: 1)
        }
        return cache
    }

    /// One pass that marks the root and serves the card whole: everything
    /// below it retained, nothing below it marked.
    private func servedPass(_ cache: RenderCache) {
        cache.beginRenderPass()
        cache.markActive(root)
        cache.retainSubtree(card)
        cache.removeInactive()
    }

    private func retainedChecks(_ cache: RenderCache) -> String? {
        cache.lastPruneSummary.split(separator: " ").drop { $0 != "retainedChecks:" }.dropFirst().first.map(String.init)
    }

    @Test("The rows below a served card are asked about once, then kept unasked")
    func unchangedPassSkipsTheWalk() {
        let cache = cache()
        servedPass(cache)
        #expect(cache.count == 3)
        #expect(retainedChecks(cache) == "3")
        servedPass(cache)
        servedPass(cache)
        #expect(cache.count == 3)
        #expect(retainedChecks(cache) == "0", "a pass that changed nothing walked the entries again")
    }

    @Test("A pass that no longer retains the card drops its rows")
    func droppedRetentionIsWalked() {
        let cache = cache()
        servedPass(cache)
        servedPass(cache)
        cache.beginRenderPass()
        cache.markActive(root)
        cache.removeInactive()
        #expect(cache.isEmpty)
    }

    @Test("A pass that marks another set drops what it no longer marks")
    func changedActiveSetIsWalked() {
        let cache = cache()
        let beside = ViewIdentity(path: "Root/Beside")
        cache.store(identity: beside, view: 9, buffer: FrameBuffer(text: "beside"), contextWidth: 80, contextHeight: 1)
        for _ in 0..<2 {
            cache.beginRenderPass()
            cache.markActive(root)
            cache.markActive(beside)
            cache.retainSubtree(card)
            cache.removeInactive()
        }
        #expect(cache.count == 4)
        servedPass(cache)
        #expect(cache.count == 3)
        #expect(cache.lookup(identity: beside, view: 9, contextWidth: 80, contextHeight: 1) == nil)
    }

    @Test("An entry stored since the last prune is walked for, and dropped if dead")
    func storeSincePruneIsWalked() {
        let cache = cache()
        servedPass(cache)
        servedPass(cache)
        let gone = ViewIdentity(path: "Root/Gone")
        cache.beginRenderPass()
        cache.markActive(root)
        cache.retainSubtree(card)
        cache.store(identity: gone, view: 7, buffer: FrameBuffer(text: "gone"), contextWidth: 80, contextHeight: 1)
        cache.removeInactive()
        #expect(cache.count == 3)
        #expect(cache.lookup(identity: gone, view: 7, contextWidth: 80, contextHeight: 1) == nil)
    }

    @Test("A second prune in one pass walks, as the witness saw only the first")
    func secondPruneInAPassIsWalked() {
        let cache = cache()
        servedPass(cache)
        servedPass(cache)
        // The pass's second prune, after its first kept everything: nothing
        // stored since, the same marks, but it decides from this pass.
        cache.removeInactive()
        #expect(retainedChecks(cache) == "3")
        #expect(cache.count == 3)
    }
}
