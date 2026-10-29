//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelPreviewPaneTests.swift
//
//  A file panel's preview: the list view's pane behind a splitter, open by
//  default where the panel is wide enough, and the one setting that opens
//  and closes it and the column view's preview column, kept in the app's
//  storage (the owner, 2026-10-28).
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
@Suite("File panel preview pane", .serialized)
struct FilePanelPreviewPaneTests {
    /// A panel opening on `fixture`'s root, which is its home, its settings
    /// kept in `store`: a fresh one, unlike the driver's, which keeps the
    /// preview closed.
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller, store: MockStorageBackend) -> some View {
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

    /// A store keeping `visibility`, and the view `mode`.
    private func store(_ visibility: FilePanelPreviewVisibility? = nil, mode: FilePanelViewMode = .list)
        -> MockStorageBackend
    {
        let store = MockStorageBackend()
        if let visibility {
            store.setValue(visibility.rawValue, forKey: FilePanelPreviewVisibility.storageKey(for: nil))
        }
        store.setValue(mode.rawValue, forKey: FilePanelViewMode.storageKey(for: nil))
        return store
    }

    private func count(_ text: String, in screen: String) -> Int {
        screen.components(separatedBy: text).count - 1
    }

    @Test("The default: open in a panel with room for it and a comfortable list, closed in a narrower one")
    func opensByDefaultWhereWide() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        // 100 columns: a page sheet of 96, a folder of 92.
        let wide = FilePanelDriver(width: 100) { panel(fixture, caller: caller, store: store()) }
        let open = await wide.waitFor("No Selection")
        // The list keeps its Size and Date Modified beside the pane.
        #expect(open.contains("Date Modified"), "\(open)")
        // 80 columns: a folder of 76, too narrow for both.
        let narrow = FilePanelDriver(width: 80) { panel(fixture, caller: caller, store: store()) }
        let closed = await narrow.waitFor("notes.md")
        #expect(!closed.contains("No Selection"), "\(closed)")
        #expect(closed.contains("Preview"), "the button stays to open it: \(closed)")
        // The rule, in cells of the folder: the list's name, Size and Date
        // Modified, the divider, and a column's width.
        #expect(FilePanelPreviewVisibility.opensByDefault(inWidth: 82))
        #expect(!FilePanelPreviewVisibility.opensByDefault(inWidth: 81))
        #expect(FilePanelPreviewVisibility.paneWidth(in: 82) == FilePanelColumnView.minimumColumnWidth)
    }

    @Test("The pane previews the item selected: its opening lines, then its name")
    func previewsSelection() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: store()) }
        await driver.waitFor("notes.md")
        await driver.waitFor("No Selection")
        // ↓ past Alpha/ and linked/ to beta.txt, and Space selects it.
        driver.press(.down, times: 2)
        driver.press(.space)
        var shown = ""
        await settle {
            shown = driver.screen()
            return count("beta.txt", in: shown) == 2
                && shown.split(separator: "\n").contains { $0.hasSuffix("│ beta") || $0.contains("│ beta ") }
        }
        #expect(!shown.contains("No Selection"), "\(shown)")
        #expect(count("beta.txt", in: shown) == 2, "in its row and in the pane: \(shown)")
    }

    @Test("The Preview button closes the pane, and the app's storage keeps the choice for the next panel")
    func buttonClosesAndIsKept() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let kept = store()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: kept) }
        await driver.waitFor("No Selection")
        #expect(driver.click("Preview"))
        await settle { !driver.screen().contains("No Selection") }
        #expect(
            kept.entry(forKey: FilePanelPreviewVisibility.storageKey(for: nil), as: String.self).value == "hidden")
        // Presented again, as wide, it opens closed.
        driver.press(.escape)
        caller.isPresented = true
        let again = await driver.waitFor("notes.md")
        #expect(!again.contains("No Selection"), "\(again)")
        // And the button opens it again.
        #expect(driver.click("Preview"))
        await driver.waitFor("No Selection")
        #expect(
            kept.entry(forKey: FilePanelPreviewVisibility.storageKey(for: nil), as: String.self).value == "shown")
    }

    @Test("Closed, the column view previews no file: one setting for both views")
    func closedInColumns() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: store(.hidden, mode: .columns)) }
        await driver.waitFor("notes.md")
        driver.press(.down, times: 2)
        driver.press(.space)
        // Frames enough for the preview column to have shown, were it open.
        for _ in 0..<5 { driver.screen() }
        #expect(count("beta.txt", in: driver.screen()) == 1, "\(driver.screen())")
        #expect(FilePanelPreviewVisibility.storageKey(for: "notes") == "TUIFilePanels.notes.preview")
    }
}
