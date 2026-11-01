//  🖥️ TUI — A Terminal UI framework for Swift
//  StateBoxStampTests.swift
//
//  A `StateBox`'s identity and sink — what a write reads to ask for a frame —
//  are written once while the box is kept at a place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

private struct StampProbe {}
private struct StampLeaf {}

@MainActor
@Suite("A state box's identity and sink are published once")
struct StateBoxStampTests {
    /// The key of the probe's first property, built afresh as each frame's
    /// walk builds its identities: equal to every other, never the same nodes.
    private func freshKey() -> StateStorage.StateKey {
        StateStorage.StateKey(
            identity: ViewIdentity(rootType: StampProbe.self).child(type: StampLeaf.self, index: 0),
            propertyIndex: 0)
    }

    /// Every hydration used to store the box's identity again — the walking
    /// frame's nodes — and its sink. The key the box is found by equals the one
    /// it was kept at, so there is nothing to store.
    @Test("A kept box found again is not stamped again")
    func keptBoxIsStampedOnce() {
        let storage = StateStorage()
        let cache = RenderCache()
        storage.renderCache = cache
        let first = freshKey()
        let box: StateBox<Int> = storage.storage(for: first, default: 0)
        let found: StateBox<Int> = storage.storage(for: freshKey(), default: 0)
        #expect(found === box)
        #expect(box.identity?.node === first.identity.node, "finding the box stored its identity again")
        #expect(box.invalidationSink === cache.link)
    }
}
