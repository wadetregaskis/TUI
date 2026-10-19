//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StateBoxStampTests.swift
//
//  A `StateBox`'s identity and sink — what a write reads on its own thread to
//  ask for a frame — are written once while the box is kept at a place, and
//  under a lock, so a `@State` written from a background task never reads
//  them while the main actor stores them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitView

private struct StampProbe {}
private struct StampLeaf {}

@MainActor
@Suite("A state box's identity and sink are published once, under a lock")
struct StateBoxStampTests {
    /// The key of the probe's first property, built afresh as each frame's
    /// walk builds its identities: equal to every other, never the same nodes.
    private func freshKey() -> StateStorage.StateKey {
        StateStorage.StateKey(
            identity: ViewIdentity(rootType: StampProbe.self).child(type: StampLeaf.self, index: 0),
            propertyIndex: 0)
    }

    /// Every hydration used to store the box's identity again — the walking
    /// frame's nodes — and its sink, while a write on another thread could be
    /// reading both. The key the box is found by equals the one it was kept
    /// at, so there is nothing to store.
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

    /// The box's sink moves when an object's state is handed from one holder
    /// to another; a write on another thread meanwhile reads the old sink or
    /// the new one, whole, and asks it for a frame.
    @Test("Writes on another thread while the main actor moves the sink report to one sink or the other")
    func writesDuringRestamp() async {
        let storage = StateStorage()
        let first = RenderCache()
        let second = RenderCache()
        storage.renderCache = first
        let box: StateBox<Int> = storage.storage(for: freshKey(), default: 0)
        let writes = 2_000
        let writer = Task.detached {
            for index in 0..<writes { box.value = index }
        }
        for index in 0..<writes {
            box.setInvalidationSink(index.isMultiple(of: 2) ? second.link : first.link)
        }
        await writer.value
        #expect(box.value == writes - 1)
    }
}
