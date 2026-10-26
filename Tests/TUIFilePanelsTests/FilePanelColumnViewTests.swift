//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelColumnViewTests.swift
//
//  A file panel's column view and the switch between it and the list view:
//  a column per folder on the way, the keys that go along them, and the view
//  kept in the app's storage.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel column view", .serialized)
struct FilePanelColumnViewTests {
    /// A panel opening on `start`, its home `fixture`'s root, its view mode
    /// kept in `store`.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, store: MockStorageBackend, start: URL? = nil,
        id: String? = nil
    ) -> some View {
        let presenter = FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: start ?? fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
        return Group {
            if let id {
                presenter.fileDialogCustomizationID(id)
            } else {
                presenter
            }
        }
        .defaultAppStorage(store)
    }

    /// A store that keeps the column view.
    private func columnsStore() -> MockStorageBackend {
        let store = MockStorageBackend()
        store.setValue(FilePanelViewMode.columns.rawValue, forKey: FilePanelViewMode.storageKey(for: nil))
        return store
    }

    @Test("A column for each folder on the way, the folder on the way selected in each")
    func columnsOnTheWay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore(), start: fixture.url("Alpha")) }
        // Each column is read on its own.
        await driver.waitFor("notes.md")
        let shown = await driver.waitFor("inner.txt")
        // ~'s items, then Alpha's, side by side on one row.
        let row = try #require(shown.split(separator: "\n").first { $0.contains("inner.txt") })
        #expect(row.contains("Alpha/"), "\(shown)")
        let alpha = try #require(row.range(of: "Alpha/"))
        let inner = try #require(row.range(of: "inner.txt"))
        #expect(alpha.lowerBound < inner.lowerBound)
        // No table header: Finder's columns have none.
        #expect(!shown.contains("Date Modified"))
    }

    @Test("Return opens a folder as a new column; ← goes back, its column's cursor where it was")
    func returnAndLeft() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore()) }
        await driver.waitFor("notes.md")
        // Alpha/ is the first row: Return opens it as a column, and the keys
        // follow into it — Return there chooses inner.txt.
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.left)
        await settle { !driver.screen().contains("inner.txt") }
        // Back in ~'s column, its cursor still on Alpha/: Return opens it again.
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("A click on a folder in an earlier column goes to it")
    func clickInEarlierColumn() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore(), start: fixture.url("Alpha")) }
        await driver.waitFor("inner.txt")
        // The column before is read on its own, after the folder shown.
        await driver.waitFor("linked/")
        // linked/ leads to Alpha too: its column lists inner.txt, under the link.
        #expect(driver.click("linked/"))
        await driver.waitFor("~ │ linked")
        #expect(caller.heard.isEmpty)
    }

    @Test("A column shows the folder on the way, however far down its folder it is")
    func columnRevealsTheFolderOnTheWay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        // Sixty folders before the folder on the way, by name, more rows than
        // a column shows.
        for index in 0..<60 {
            try FileManager.default.createDirectory(at: fixture.url("a\(index)"), withIntermediateDirectories: true)
        }
        let deep = fixture.url("zz")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: deep.appendingPathComponent("leaf.txt").path, contents: nil)
        let caller = FilePanelCaller()
        // The panel shows ~ and zz; ~'s column has scrolled to zz/.
        let driver = FilePanelDriver(height: 20) {
            panel(fixture, caller: caller, store: columnsStore(), start: deep)
        }
        await driver.waitFor("leaf.txt")
        let shown = await driver.waitFor("zz/")
        #expect(shown.contains("zz/"), "\(shown)")
    }

    @Test("The switcher changes the view, and the app's storage keeps it")
    func switcherIsKept() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let store = MockStorageBackend()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: store) }
        let list = await driver.waitFor("notes.md")
        #expect(list.contains("Date Modified"), "the list view by default: \(list)")
        #expect(driver.click("Columns"))
        await settle { !driver.screen().contains("Date Modified") }
        #expect(store.entry(forKey: FilePanelViewMode.storageKey(for: nil), as: String.self).value == "columns")
        // Presented again, it opens in the column view.
        driver.press(.escape)
        caller.isPresented = true
        let again = await driver.waitFor("notes.md")
        #expect(!again.contains("Date Modified"), "\(again)")
    }

    @Test("A customization ID keeps a view of its own")
    func viewKeptPerID() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        // The app's panels use the column view; this one, the list view.
        let store = columnsStore()
        store.setValue(FilePanelViewMode.list.rawValue, forKey: FilePanelViewMode.storageKey(for: "notes"))
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: store, id: "notes") }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Date Modified"), "\(shown)")
        #expect(FilePanelViewMode.storageKey(for: "notes") == "TUIFilePanels.notes.viewMode")
    }
}
