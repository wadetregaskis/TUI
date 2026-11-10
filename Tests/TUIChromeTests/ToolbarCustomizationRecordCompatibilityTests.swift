//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarCustomizationRecordCompatibilityTests.swift
//
//  A customized toolbar's record, as the persisted-settings promise asks of
//  every key TUI keeps (`PersistedSettingsCompatibilityTests`): today's file
//  reads and today's writer still writes it; a later TUI's record gives up
//  what this one knows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIChrome
@testable import TUIFoundation
@testable import TUITestSupport

private typealias Fixtures = PersistedSettingsFixtures
private typealias Record = _ToolbarCustomizationRecord

@Suite("A customized toolbar's record reads forward and backward")
struct ToolbarCustomizationRecordCompatibilityTests {
    @Test("Today's record reads, and today's writer writes it as the file holds it")
    func todaysRecord() throws {
        try Fixtures.withStore("settings.json") { store, fixture in
            let record = Record.load("editor", from: store)
            #expect(record == Record(order: ["bold", "italic", "print"], shown: ["italic": false]))

            let key = Record.key("editor")
            store.removeValue(forKey: key)
            record.save("editor", to: store)
            store.synchronize()
            let original = Fixtures.url("settings.json")
            let (wrote, holds) = (try Fixtures.storedJSON(key, in: fixture), try Fixtures.storedJSON(key, in: original))
            #expect(wrote != nil && wrote == holds)
        }
    }

    @Test("A later record reads without the field this build doesn't know, and with an item it hasn't heard of")
    func laterRecordWithMore() throws {
        try Fixtures.withStore("settings-newer.json") { store, _ in
            let record = Record.load("editor", from: store)
            #expect(record.order == ["bold", "share", "italic", "print"])
            #expect(record.shown == ["italic": false, "share": true])
        }
    }

    /// A later writer may leave out a field it has nothing in. Decoded as
    /// required, an absent `shown` failed the whole record, and the person's
    /// order went with it.
    @Test("A later record without the items it shows keeps its order")
    func laterRecordWithLess() throws {
        try Fixtures.withStore("settings-newer.json") { store, _ in
            #expect(Record.load("compact", from: store) == Record(order: ["print"], shown: [:]))
        }
    }
}
