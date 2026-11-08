//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneStorageSessionTests.swift
//
//  `@SceneStorage` per terminal session (owner, 2026-11-08): a write goes to
//  the session's copy and the last saved; a read takes the session's, else the
//  last saved, else the default; the ledger keeps the sessions bounded.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A property for `key` in `store`, as its view would find it drawn in
/// `session` (or none) and the window namespace `namespace`.
private func property(
    _ key: String, in store: MockStorageBackend, session: String?, namespace: String = ""
) -> SceneStorage<String> {
    let property = SceneStorage(wrappedValue: "default", key, store: store)
    var environment = EnvironmentValues()
    environment.sceneStorageSession = session
    environment.sceneStorageNamespace = namespace
    property.resolveEnvironment(environment)
    return property
}

@Suite("SceneStorage per terminal session")
struct SceneStorageSessionTests {
    @Test("With no session it reads and writes only the last saved, under the key it always had")
    func noSession() {
        let store = MockStorageBackend()
        property("tab", in: store, session: nil).wrappedValue = "sent"
        #expect(store.value(forKey: "scene.tab") == Optional("sent"))
        #expect(store.value(forKey: SceneStorageSessions.ledgerKey) as [String: SceneStorageSessions.Record]? == nil)
        #expect(property("tab", in: store, session: nil).wrappedValue == "sent")
    }

    @Test("A session reads its own, a new session the last saved, and neither disturbs the other")
    func sessionsKeepTheirOwn() {
        let store = MockStorageBackend()
        #expect(property("tab", in: store, session: "A").wrappedValue == "default")

        property("tab", in: store, session: "A").wrappedValue = "inbox"
        // A new window — opened for this task — starts where the user last was.
        #expect(property("tab", in: store, session: "B").wrappedValue == "inbox")

        property("tab", in: store, session: "B").wrappedValue = "archive"
        #expect(property("tab", in: store, session: "A").wrappedValue == "inbox")
        #expect(property("tab", in: store, session: "B").wrappedValue == "archive")
        // The last saved is B's, for the next new window, and for no session.
        #expect(property("tab", in: store, session: "C").wrappedValue == "archive")
        #expect(property("tab", in: store, session: nil).wrappedValue == "archive")
    }

    @Test("A window's namespace is kept under the session's key")
    func namespacesUnderTheSession() {
        let store = MockStorageBackend()
        property("tab", in: store, session: "A", namespace: "viewer#2.").wrappedValue = "x"
        let key = SceneStorageSessions.key("scene.viewer#2.tab", session: "A")
        #expect(key.hasPrefix("scene@") && key.hasSuffix(".viewer#2.tab"))
        #expect(key.count == "scene@".count + 16 + ".viewer#2.tab".count)
        #expect(store.value(forKey: key) == Optional("x"))
        #expect(store.value(forKey: "scene.viewer#2.tab") == Optional("x"))
        #expect(property("tab", in: store, session: "A").wrappedValue == "default", "the launch window's is its own")
    }

    @Test("A store keeps every session written within the lifetime, however many")
    func noSessionLimit() {
        let store = MockStorageBackend()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let count = 100
        for index in 0..<count {
            let session = "S\(index)"
            let key = SceneStorageSessions.key("scene.tab", session: session)
            store.setValue(session, forKey: key)
            SceneStorageSessions.noteWrite(
                of: key, session: session, in: store, now: start.addingTimeInterval(TimeInterval(index)))
        }
        let ledger: [String: SceneStorageSessions.Record]? = store.value(forKey: SceneStorageSessions.ledgerKey)
        #expect(ledger?.count == count)
        #expect(store.value(forKey: SceneStorageSessions.key("scene.tab", session: "S0")) == Optional("S0"))
        #expect(store.value(forKey: SceneStorageSessions.key("scene.tab", session: "S99")) == Optional("S99"))
    }

    @Test("A session that wrote nothing for longer than its lifetime goes when another writes")
    func sessionLifetime() {
        let store = MockStorageBackend()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let old = SceneStorageSessions.key("scene.tab", session: "old")
        store.setValue("old", forKey: old)
        SceneStorageSessions.noteWrite(of: old, session: "old", in: store, now: start)

        let new = SceneStorageSessions.key("scene.tab", session: "new")
        let later = start.addingTimeInterval(SceneStorageSessions.sessionLifetime + 1)
        SceneStorageSessions.noteWrite(of: new, session: "new", in: store, now: later)

        let ledger: [String: SceneStorageSessions.Record]? = store.value(forKey: SceneStorageSessions.ledgerKey)
        #expect(ledger.map { Set($0.keys) } == ["new"])
        #expect(store.value(forKey: old) as String? == nil)
    }

    @Test("A write of a key the session has, inside the stamp interval, leaves the ledger as it was")
    func stampInterval() {
        let store = MockStorageBackend()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let key = SceneStorageSessions.key("scene.tab", session: "A")
        SceneStorageSessions.noteWrite(of: key, session: "A", in: store, now: start)
        SceneStorageSessions.noteWrite(of: key, session: "A", in: store, now: start.addingTimeInterval(60))
        var ledger: [String: SceneStorageSessions.Record]? = store.value(forKey: SceneStorageSessions.ledgerKey)
        #expect(ledger?["A"] == SceneStorageSessions.Record(lastWritten: start.timeIntervalSince1970, keys: [key]))

        let renewed = start.addingTimeInterval(SceneStorageSessions.stampInterval)
        SceneStorageSessions.noteWrite(of: key, session: "A", in: store, now: renewed)
        ledger = store.value(forKey: SceneStorageSessions.ledgerKey)
        #expect(ledger?["A"]?.lastWritten == renewed.timeIntervalSince1970)
    }

    @Test("A property that names no store uses the one defaultAppStorage(_:) set, as @AppStorage does")
    func honoursTheEnvironmentsStore() {
        let store = MockStorageBackend()
        let property = SceneStorage(wrappedValue: "default", "SceneStorageSessionTests.tab")
        var environment = EnvironmentValues()
        environment.defaultAppStorage = DefaultAppStorage(store)
        property.resolveEnvironment(environment)
        property.wrappedValue = "kept here"
        #expect(store.value(forKey: "scene.SceneStorageSessionTests.tab") == Optional("kept here"))
    }
}
