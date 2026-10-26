//  🖥️ TUI — A Terminal UI framework for Swift
//  SoftDrainTests.swift
//
//  A parent's write keeps what lies below it, marked, when that recorded what
//  it was drawn from and under; drops it otherwise; and a marked entry is not
//  served as it stands (Option C, C4b — the re-check that would serve it is
//  C4c's, so a suspect looked up is dropped).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

private enum Root {}
private enum Step {}

@MainActor
@Suite("A parent's write keeps, marked, what it can re-check")
struct SoftDrainTests {

    /// Root → parent → row → cell, and a sibling of the parent.
    private struct Tree {
        let root: ViewIdentity
        let parent: ViewIdentity
        let row: ViewIdentity
        let cell: ViewIdentity
        let sibling: ViewIdentity

        init(raw: Bool) {
            root = raw ? ViewIdentity(path: "Root") : ViewIdentity(rootType: Root.self)
            parent = root.child(type: Step.self, index: 0)
            row = parent.child(type: Step.self, index: 0)
            cell = row.child(type: Step.self, index: 0)
            sibling = root.child(type: Step.self, index: 1)
        }

        var all: [ViewIdentity] { [root, parent, row, cell, sibling] }
    }

    private static func sizeKey(_ node: ViewIdentity) -> RenderCache.SizeKey {
        RenderCache.SizeKey(
            identityHash: node.structuralHash, proposalWidth: nil, proposalHeight: nil, availableWidth: 10,
            availableHeight: 1, hasExplicitWidth: false, hasExplicitHeight: false, measureGeneration: 0)
    }

    /// A cache with a buffer and a size at each of `nodes`, each recording
    /// what it was drawn from and under when `stamped`.
    private static func filled(_ nodes: [ViewIdentity], stamped: Bool) -> RenderCache {
        let cache = RenderCache()
        let context = RenderContext(availableWidth: 10, availableHeight: 1, environment: EnvironmentValues())
        for (index, node) in nodes.enumerated() {
            let record = stamped ? cache.revalidationRecord(for: index, context: context) : nil
            cache.store(
                identity: node, view: index, buffer: FrameBuffer(text: "\(index)"), contextWidth: 10, contextHeight: 1,
                gradientFrame: nil, surfaceBackground: nil, recorded: ([], .none, nil), revalidation: record)
            cache.storeSize(
                key: sizeKey(node), identity: node, view: index, size: .fixed(index, 1), lease: nil, revalidation: record)
        }
        return cache
    }

    /// For each node, whether the buffer and the size are still held, and
    /// whether the buffer is a suspect, read without looking up (a lookup of a
    /// suspect drops it).
    private static func state(_ cache: RenderCache, _ nodes: [ViewIdentity]) -> [String] {
        nodes.map { node in
            let entry = cache.entries[node.structuralHash]
            let size = cache.sizeEntries[sizeKey(node)]
            return (entry == nil ? "-" : entry!.isSuspect ? "b" : "B") + (size == nil ? "-" : size!.isSuspect ? "s" : "S")
        }
    }

    @Test("Below a soft writer a stamped entry is kept, marked; at and above it, entries go", arguments: [false, true])
    func softKeepsBelow(raw: Bool) {
        let tree = Tree(raw: raw)
        let cache = Self.filled(tree.all, stamped: true)
        cache.link.invalidateRenderSoftly(for: tree.parent)
        cache.beginRenderPass()
        #expect(Self.state(cache, tree.all) == ["--", "--", "bs", "bs", "BS"])
        #expect(cache.revalidation.counts.suspectsMarked == 2)
    }

    @Test("Below a soft writer an entry that recorded nothing goes", arguments: [false, true])
    func unstampedGoes(raw: Bool) {
        let tree = Tree(raw: raw)
        let cache = Self.filled(tree.all, stamped: false)
        cache.link.invalidateRenderSoftly(for: tree.parent)
        cache.beginRenderPass()
        #expect(Self.state(cache, tree.all) == ["--", "--", "--", "--", "BS"])
        #expect(cache.revalidation.counts.unstampedDropped == 2)
    }

    @Test("Below a hard writer everything goes, and a hard writer above a soft one wins", arguments: [false, true])
    func hardDrops(raw: Bool) {
        let tree = Tree(raw: raw)
        let cache = Self.filled(tree.all, stamped: true)
        cache.link.invalidateRender(for: tree.parent)
        cache.beginRenderPass()
        #expect(Self.state(cache, tree.all) == ["--", "--", "--", "--", "BS"])

        let both = Self.filled(tree.all, stamped: true)
        both.link.invalidateRenderSoftly(for: tree.row)
        both.link.invalidateRender(for: tree.parent)
        both.beginRenderPass()
        #expect(Self.state(both, tree.all) == ["--", "--", "--", "--", "BS"])
    }

    @Test("A suspect looked up misses and goes: the re-check is not on yet", arguments: [false, true])
    func suspectLookedUpGoes(raw: Bool) {
        let tree = Tree(raw: raw)
        let cache = Self.filled(tree.all, stamped: true)
        cache.link.invalidateRenderSoftly(for: tree.parent)
        cache.beginRenderPass()
        let rowIndex = 2
        #expect(cache.lookup(identity: tree.row, view: rowIndex, contextWidth: 10, contextHeight: 1) == nil)
        #expect(cache.lookupSize(key: Self.sizeKey(tree.row), view: rowIndex) == nil)
        #expect(Self.state(cache, tree.all) == ["--", "--", "--", "bs", "BS"])
        #expect(cache.revalidation.counts.suspectsDropped == 2)
    }

    @Test("A suspect nobody looked up goes at the pass's end", arguments: [false, true])
    func unresolvedSuspectsGo(raw: Bool) {
        let tree = Tree(raw: raw)
        let cache = Self.filled(tree.all, stamped: true)
        cache.link.invalidateRenderSoftly(for: tree.parent)
        cache.beginRenderPass()
        for node in tree.all { cache.markActive(node) }
        cache.removeInactive()
        #expect(Self.state(cache, tree.all) == ["--", "--", "--", "--", "BS"])
    }

    @Test("A row that can be re-checked records its value and environment; one that cannot, nothing")
    func records() {
        let cache = RenderCache()
        let context = RenderContext(availableWidth: 10, availableHeight: 1, environment: EnvironmentValues())
        let record = cache.revalidationRecord(for: 7, context: context)
        #expect(record?.snapshot as? Int == 7)
        #expect(record.map { $0.equal($0.snapshot, 7) && !$0.equal($0.snapshot, 8) } == true)
        #expect(record?.environment != nil)
        #expect(cache.revalidationRecord(for: { () in }, context: context) == nil)
    }
}
