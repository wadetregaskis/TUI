//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelSettingsCompatibilityTests.swift
//
//  What the file panels keep, as the persisted-settings promise asks of every
//  key TUI keeps (`PersistedSettingsCompatibilityTests`): today's file reads,
//  and a later TUI's file — a view mode or preview it added, a size out of
//  range or retyped — opens a panel at the defaults, never a broken one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFilePanels
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

private typealias Fixtures = PersistedSettingsFixtures

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel settings read forward and backward", .serialized)
struct FilePanelSettingsCompatibilityTests {
    /// The view mode and preview as the panel reads them from `store`.
    private func kept(in store: any StorageBackend) -> (FilePanelViewMode, FilePanelPreviewVisibility) {
        (
            AppStorage(wrappedValue: .list, FilePanelViewMode.storageKey(for: nil), store: store).wrappedValue,
            AppStorage(wrappedValue: .automatic, FilePanelPreviewVisibility.storageKey(for: nil), store: store)
                .wrappedValue
        )
    }

    @Test("Today's file keeps the view mode and preview it was left with")
    func todaysFile() throws {
        try Fixtures.withStore("settings.json") { store, _ in
            #expect(kept(in: store) == (.columns, .hidden))
        }
    }

    @Test("A view mode or preview a later build added reads as the default")
    func laterCases() throws {
        try Fixtures.withStore("settings-newer.json") { store, _ in
            #expect(kept(in: store) == (.list, .automatic))
        }
    }

    /// The width a later build left is -7, below anything a panel can be
    /// drawn at, and its height a fraction where a whole number is kept.
    @Test("A panel opens on a later file: a size out of range is clamped, one retyped follows the terminal")
    func panelOpensOnALaterFile() async throws {
        let copy = try Fixtures.scratchCopy("settings-newer.json")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let store = JSONFileStorage(fileURL: copy)
        defer { store.synchronize() }
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver(width: 100, height: 30) {
            FilePanelPresenter(
                content: Text("Page"), isPresented: caller.binding,
                request: {
                    FilePanelRequest(
                        purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                        confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
                },
                onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() }
            )
            .defaultAppStorage(store)
        }
        // The grip, not a file: at the narrowest a panel is drawn, a name may not fit.
        let screen = await driver.waitFor("╝")
        let rows = screen.split(separator: "\n", omittingEmptySubsequences: false)
        let top = try #require(rows.firstIndex { $0.contains("╭") }, "the panel is drawn")
        let bottom = try #require(rows.lastIndex { $0.contains("╝") }, "the panel's resize grip is on the screen")
        let edge = try #require(rows[bottom].firstIndex(of: "╰"))
        let grip = try #require(rows[bottom].firstIndex(of: "╝"))
        #expect(rows[bottom].distance(from: edge, to: grip) + 1 >= _DialogDragHandler.minWidth, "drawn at a width of -7")
        #expect(bottom - top + 1 >= _DialogDragHandler.minHeight)
        let keys = FilePanelRequest.sizeStorageKeys(for: nil, isSave: false)
        #expect(store.entry(forKey: keys.width, as: Int.self).value == -7, "opening is not saving")
    }
}
