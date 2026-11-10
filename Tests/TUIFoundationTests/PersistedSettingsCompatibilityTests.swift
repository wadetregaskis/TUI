//  🖥️ TUI — A Terminal UI framework for Swift
//  PersistedSettingsCompatibilityTests.swift
//
//  The persisted-state promise of the API stability policy (decision 8): an
//  app built with any 1.n reads the settings any 1.m wrote, older or newer.
//  Today's file must read, and today's writer must still write it; a later
//  TUI's file must give up what this one knows and keep what it doesn't. The
//  file panels' and the toolbar's own records are checked in their targets,
//  and `UserDefaults` in `UserDefaultsStorageTests`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport

private typealias Fixtures = PersistedSettingsFixtures

/// A mode stored by raw value, as the file panel's view mode is, with the
/// cases this build knows: a later one added `gallery`.
private enum StoredMode: String {
    case list, columns
}

/// `scene.page`'s property in `store`, drawn in `session` (or none).
private func scenePage(in store: any StorageBackend, session: String?) -> SceneStorage<String> {
    let property = SceneStorage(wrappedValue: "default", "page", store: store)
    var environment = EnvironmentValues()
    environment.sceneStorageSession = session
    property.resolveEnvironment(environment)
    return property
}

@Suite("Persisted settings read forward and backward")
struct PersistedSettingsCompatibilityTests {

    // MARK: Today's file

    @Test("Today's settings.json reads: every key TUI keeps, as the type it keeps it as")
    func todaysFileReads() throws {
        try Fixtures.withStore("settings.json") { store, _ in
            #expect(store.value(forKey: "TUIFilePanels.viewMode") == Optional("columns"))
            #expect(store.value(forKey: "TUIFilePanels.showsHiddenFiles") == Optional(true))
            #expect(store.value(forKey: "TUIFilePanels.open.width") == Optional(96))
            #expect(store.value(forKey: "TUIFilePanels.open.height") == Optional(30))
            #expect(store.value(forKey: "TUIFilePanels.docs.directory") == Optional("/tmp"))
            #expect(store.value(forKey: "tuikit.colorPicker.palette256.showNumbers") == Optional(true))
            #expect(store.value(forKey: "tuikit.gradientEditor.recents") == Optional("FF0000@0.000,0000FF@1.000"))
            #expect(scenePage(in: store, session: nil).wrappedValue == "Buttons")
            #expect(scenePage(in: store, session: Fixtures.session).wrappedValue == "Lists")
            let ledger: [String: SceneStorageSessions.Record]? = store.value(forKey: SceneStorageSessions.ledgerKey)
            #expect(
                ledger == [Fixtures.session: .init(lastWritten: 1_762_790_400, keys: [Fixtures.sessionPageKey])])
        }
    }

    /// The other half of "today's file": what today's writer puts there must be
    /// what the fixture holds, or the fixture would stop being today's file
    /// and a reader of the real one could break unseen.
    @Test("Today's writer writes what today's settings.json holds")
    func todaysWriterWritesTheFixture() throws {
        try Fixtures.withStore("settings.json") { _, fixture in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tui.settings-writer.\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let written = directory.appendingPathComponent("settings.json")
            let store = JSONFileStorage(fileURL: written)
            store.setValue("columns", forKey: "TUIFilePanels.viewMode")
            store.setValue(true, forKey: "TUIFilePanels.showsHiddenFiles")
            store.setValue(96, forKey: "TUIFilePanels.open.width")
            store.setValue("/tmp", forKey: "TUIFilePanels.docs.directory")
            store.setValue("FF0000@0.000,0000FF@1.000", forKey: "tuikit.gradientEditor.recents")
            scenePage(in: store, session: nil).wrappedValue = "Buttons"
            let ledger = [Fixtures.session: SceneStorageSessions.Record(lastWritten: 1_762_790_400, keys: [Fixtures.sessionPageKey])]
            store.setValue(ledger, forKey: SceneStorageSessions.ledgerKey)
            store.synchronize()
            for key in [
                "TUIFilePanels.viewMode", "TUIFilePanels.showsHiddenFiles", "TUIFilePanels.open.width",
                "TUIFilePanels.docs.directory", "tuikit.gradientEditor.recents", "scene.page",
                SceneStorageSessions.ledgerKey,
            ] {
                let (wrote, holds) = (try Fixtures.storedJSON(key, in: written), try Fixtures.storedJSON(key, in: fixture))
                #expect(wrote != nil && wrote == holds, "today's writer and today's file differ at \(key)")
            }
        }
    }

    // MARK: A later TUI's file

    /// A later TUI may keep a key as something other than this format's base64
    /// string. Read as `[String: String]` whole, one such value failed the
    /// cast, and the file read as empty: every setting back to its default.
    @Test("A later file's keys this build knows read, whatever else the file holds")
    func laterFileReadsWhatItKnows() throws {
        try Fixtures.withStore("settings-newer.json") { store, _ in
            #expect(store.value(forKey: "TUIFilePanels.showsHiddenFiles") == Optional(true))
            #expect(store.value(forKey: "tuikit.gradientEditor.recents") == Optional("FF0000@0.000,0000FF@1.000"))
            #expect(scenePage(in: store, session: nil).wrappedValue == "Buttons")
            #expect(scenePage(in: store, session: Fixtures.session).wrappedValue == "Lists")
            // A record with a field this build doesn't know reads without it.
            let ledger: [String: SceneStorageSessions.Record]? = store.value(forKey: SceneStorageSessions.ledgerKey)
            #expect(ledger?[Fixtures.session] == .init(lastWritten: 1_762_790_400, keys: [Fixtures.sessionPageKey]))
            #expect(ledger?.count == 2)
            // Out of range reads as stored; the sheet clamps it where it is used.
            #expect(store.value(forKey: "TUIFilePanels.open.width") == Optional(-7))
            // Retyped (a fraction where an Int was kept) reads as absent: the default.
            #expect(store.value(forKey: "TUIFilePanels.open.height") == Int?.none)
        }
    }

    @Test("A case a later build added to an enum kept by raw value reads as the default")
    func laterEnumCaseReadsAsDefault() throws {
        try Fixtures.withStore("settings-newer.json") { store, _ in
            #expect(AppStorage(wrappedValue: StoredMode.list, "TUIFilePanels.viewMode", store: store).wrappedValue == .list)
            #expect(AppStorage<StoredMode?>("TUIFilePanels.viewMode", store: store).wrappedValue == nil)
        }
        try Fixtures.withStore("settings.json") { store, _ in
            #expect(AppStorage(wrappedValue: StoredMode.list, "TUIFilePanels.viewMode", store: store).wrappedValue == .columns)
        }
    }

    /// A flush starts from what is on disk and lays this build's own writes
    /// over it. Read as `[String: String]` whole, a later file failed the
    /// cast, and the flush wrote this build's writes alone: every key the
    /// later build had kept, gone.
    @Test("A write to a later file keeps every key this build doesn't know, as it was")
    func writeKeepsWhatItDoesNotKnow() throws {
        try Fixtures.withStore("settings-newer.json") { store, file in
            let before = try Fixtures.topLevel(of: file)
            scenePage(in: store, session: nil).wrappedValue = "Tables"
            store.synchronize()
            let after = try Fixtures.topLevel(of: file)
            #expect(Set(after.keys) == Set(before.keys))
            for key in before.keys where key != "scene.page" {
                #expect(
                    "\(after[key] ?? "missing")" == "\(before[key] ?? "missing")", "\(key) changed under a write of another")
            }
            #expect(JSONFileStorage(fileURL: file).value(forKey: "scene.page") == Optional("Tables"))
        }
    }
}
