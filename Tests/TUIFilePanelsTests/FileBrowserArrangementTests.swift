//  🖥️ TUI — A Terminal UI framework for Swift
//  FileBrowserArrangementTests.swift
//
//  Which folders a file panel's browser sorts as it moves between them, and
//  when: an arrangement of 50,000 items takes a second, so a folder opened
//  must not wait for the sort of folders it did not change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization
import Testing

@testable import TUIFilePanels

/// The folders arranged while a watch is bound, each by its path, in order.
private final class ArrangedFolders: Sendable {
    private let paths = Mutex<[String]>([])

    /// The folders heard, in the order they were arranged.
    var heard: [String] { paths.withLock { $0 } }

    /// A watch that records each arrangement's folder (`""` for an empty one).
    var watch: FileArrangementWatch {
        FileArrangementWatch { entries in
            let path = entries.first.map { $0.url.deletingLastPathComponent().standardizedFileURL.path } ?? ""
            self.paths.withLock { $0.append(path) }
        }
    }
}

@MainActor
@Suite("File browser arrangement")
struct FileBrowserArrangementTests {
    /// The order by name, the other way round.
    private var reversedNames: [KeyPathComparator<FileEntry>] {
        var order = FileBrowser.nameOrder
        order.order = .reverse
        return [order]
    }

    @Test("Opening a folder arranges it alone, not the folders kept on the way to it")
    func openingArrangesTheFolderAlone() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        let alpha = fixture.url("Alpha")
        let arranged = ArrangedFolders()
        await FileArrangementWatch.$current.withValue(arranged.watch) {
            browser.open(alpha)
            await browser.refresh()
        }
        // The root is kept, for the column view's column of it, as arranged
        // when it was shown: nothing has changed its order since.
        #expect(arranged.heard == [alpha.standardizedFileURL.path])
        #expect(browser.rows.map(\.name) == ["inner.txt"])
        #expect(browser.folderRows[fixture.root.path]?.contains { $0.name == "Alpha" } == true)
    }

    @Test("Going back to a folder kept on the way shows it as it was arranged, with no sort")
    func goingBackArrangesNothing() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        let shown = browser.rows.map(\.name)
        let hidden = browser.hiddenCount
        browser.open(fixture.url("Alpha"))
        await browser.refresh()
        let arranged = ArrangedFolders()
        await FileArrangementWatch.$current.withValue(arranged.watch) {
            browser.goUp()
            await browser.refresh()
        }
        #expect(arranged.heard.isEmpty)
        #expect(browser.state == .loaded)
        #expect(browser.rows.map(\.name) == shown)
        #expect(browser.hiddenCount == hidden && hidden == 1)
        #expect(browser.entry(for: fixture.url("notes.md"))?.name == "notes.md")
    }

    @Test("A new order, and the hidden items shown, arrange the folders kept on the way again")
    func newOrderArrangesTheKeptFolders() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        browser.open(fixture.url("Alpha"))
        await browser.refresh()
        browser.sortOrder = reversedNames
        await browser.refresh()
        // Folders first, each group the other way round; the hidden file left out.
        #expect(
            browser.folderRows[fixture.root.path]?.map(\.name) == ["linked", "Alpha", "notes.md", "gamma.pdf", "beta.txt"])
        browser.showsHiddenFiles = true
        await browser.refresh()
        #expect(browser.folderRows[fixture.root.path]?.last?.name == ".hidden")
        // Found by the selection's lookups, as the kept folder's other rows are.
        #expect(browser.entry(for: fixture.url(".hidden"))?.name == ".hidden")
    }
}
