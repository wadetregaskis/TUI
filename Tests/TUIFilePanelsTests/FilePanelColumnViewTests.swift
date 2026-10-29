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
@testable import TUIFilePanelImages
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel column view", .serialized)
struct FilePanelColumnViewTests {
    /// A panel opening on `start`, its home `fixture`'s root, its view mode
    /// kept in `store`; to save where `saves`.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, store: MockStorageBackend, start: URL? = nil,
        id: String? = nil, saves: Bool = false
    ) -> some View {
        let presenter = FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: saves ? .save(contentTypes: [.plainText]) : .open(allowsMultipleSelection: false),
                    rule: FileChoiceRule(), title: "Open",
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

    @Test("Return opens a folder as a new column; ← goes back, its column's cursor where it was, the way back down kept")
    func returnAndLeft() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore()) }
        await driver.waitFor("notes.md")
        // Alpha/ is the first row: Return opens it as a column, and the keys
        // follow into it — Return there chooses inner.txt.
        driver.press(.enter)
        await driver.waitFor("~ │ Alpha")
        await driver.waitFor("inner.txt")
        driver.press(.left)
        // Back in ~, Alpha/ selected in its column: Alpha's column still shows
        // beside it, as Finder's does.
        await settle { !driver.screen().contains("~ │ Alpha") }
        #expect(driver.screen().contains("inner.txt"), "\(driver.screen())")
        // Its cursor still on Alpha/: Return opens it again, and the keys
        // follow into the column that showed already.
        driver.press(.enter)
        await driver.waitFor("~ │ Alpha")
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("→ opens the folder under the cursor, and on a file stays in the columns")
    func rightOpensFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore()) }
        await driver.waitFor("notes.md")
        driver.press(.right)
        await driver.waitFor("~ │ Alpha")
        await driver.waitFor("inner.txt")
        // On inner.txt, → goes nowhere, and the keys stay in Alpha's column:
        // Return chooses it.
        driver.press(.right)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    /// The owner, 2026-10-28: going to `~` from folders down took the columns
    /// down to one.
    @Test("Going up to ~ keeps the columns of the way back down, until another row is chosen there")
    func upKeepsTheWay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let deep = fixture.url("Alpha/Deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: deep.appendingPathComponent("leaf.txt").path, contents: nil)
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore(), start: deep) }
        await driver.waitFor("leaf.txt")
        await driver.waitFor("inner.txt")
        driver.press(.character("~"))
        await settle { !driver.screen().contains("~ │ Alpha") }
        let shown = driver.screen()
        #expect(shown.contains("leaf.txt") && shown.contains("inner.txt"), "\(shown)")
        // beta.txt chosen in ~'s column — past Alpha/ and linked/ — and the
        // way goes: its preview takes the columns' place.
        driver.press(.down, times: 2)
        driver.press(.space)
        await settle { !driver.screen().contains("leaf.txt") }
        #expect(!driver.screen().contains("inner.txt"))
    }

    /// New Folder reads the panel's folders again: the column of a folder
    /// above, whose task had no reason to run again, drew "Loading…" for good.
    @Test("After New Folder, the columns of the folders above are read again")
    func newFolderRereadsTheColumnsAbove() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            panel(fixture, caller: caller, store: columnsStore(), start: fixture.url("Alpha"), saves: true)
        }
        await driver.waitFor("notes.md")
        await driver.waitFor("inner.txt")
        #expect(driver.click("New Folder"))
        await driver.waitFor("Name of new folder")
        #expect(driver.click("Create"))
        await settle { FileManager.default.fileExists(atPath: fixture.url("Alpha/untitled folder").path) }
        let shown = await driver.waitFor("notes.md", timeout: .seconds(5))
        #expect(shown.contains("notes.md") && shown.contains("inner.txt"), "\(shown)")
    }

    /// How many times `text` shows on `screen`.
    private func count(_ text: String, in screen: String) -> Int {
        screen.components(separatedBy: text).count - 1
    }

    /// Selects beta.txt — ↓ moves the cursor to it, past Alpha/ and linked/,
    /// and Space selects it — and returns the screen once it is previewed,
    /// its name shown twice, in its column and in the preview's.
    private func previewingBeta(with driver: FilePanelDriver<some View>) async -> String {
        await driver.waitFor("notes.md")
        driver.press(.down, times: 2)
        driver.press(.space)
        await settle { count("beta.txt", in: driver.screen()) >= 2 }
        return driver.screen()
    }

    @Test("A file selected is previewed in a column after its folder's: its opening lines, then its name")
    func previewColumn() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore()) }
        var shown = await previewingBeta(with: driver)
        await settle {
            shown = driver.screen()
            return shown.split(separator: "\n").contains { $0.hasSuffix("│ beta") || $0.contains("│ beta ") }
        }
        #expect(count("beta.txt", in: shown) == 2, "\(shown)")
        // The excerpt, `beta`, on a line of its own in the preview column.
        let rows = shown.split(separator: "\n").map(String.init)
        let name = try #require(rows.firstIndex { count("beta.txt", in: $0) == 1 && $0.contains("│ beta.txt") })
        let excerpt = try #require(rows.firstIndex { $0.contains("│ beta ") || $0.hasSuffix("│ beta") })
        #expect(excerpt < name, "the excerpt is above the name: \(shown)")
    }

    @Test("An app's preview takes the excerpt's place")
    func appPreview() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            panel(fixture, caller: caller, store: columnsStore())
                .fileDialogPreview { url, _ in url.lastPathComponent == "beta.txt" ? Text("PREVIEWED") : nil }
        }
        _ = await previewingBeta(with: driver)
        await driver.waitFor("PREVIEWED")
    }

    /// An 8 × 8 red PNG.
    private static let redPicture = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC")!

    @Test("fileDialogPicturePreviews() previews a picture, and leaves a text file its excerpt")
    func picturePreviews() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        try Self.redPicture.write(to: fixture.url("picture.png"))
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: columnsStore()).fileDialogPicturePreviews() }
        // A text file keeps TUI's own preview.
        _ = await previewingBeta(with: driver)
        await settle { driver.screen().split(separator: "\n").contains { $0.hasSuffix("│ beta") || $0.contains("│ beta ") } }
        // ↓ past gamma.pdf and notes.md to picture.png, and Space selects it.
        driver.press(.down, times: 3)
        driver.press(.space)
        await settle { count("picture.png", in: driver.screen()) >= 2 }
        let shown = driver.screen()
        let rows = shown.split(separator: "\n").map(String.init)
        let name = try #require(rows.firstIndex { $0.contains("│ picture.png") && count("picture.png", in: $0) == 1 })
        // Above the name, the picture drawn in cells, in its red: a test
        // terminal has no graphics, and a picture all one colour is drawn as
        // cells of that colour, so the stripped screen shows nothing there.
        let styled = driver.styledRows()
        let red = styled[..<name].contains { $0.contains("2;255;0;0m") }
        #expect(red, "\(shown)")
        #expect(FileDialogPicturePreviews.isPicture(.png) && !FileDialogPicturePreviews.isPicture(.plainText))
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
