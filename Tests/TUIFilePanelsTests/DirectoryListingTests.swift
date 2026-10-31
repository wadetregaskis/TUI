//  🖥️ TUI — A Terminal UI framework for Swift
//  DirectoryListingTests.swift
//
//  Reading a folder into a file panel's rows, and the browser that sorts
//  them: what each row says, which can be chosen, and in what order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFilePanels

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@Suite("Directory listing")
struct DirectoryListingTests {
    private func entries(_ fixture: FilePanelFixture, rule: FileChoiceRule = FileChoiceRule()) throws -> [String: FileEntry] {
        let listed = try DirectoryListing.read(fixture.root, rule: rule).get()
        return Dictionary(uniqueKeysWithValues: listed.map { ($0.name, $0) })
    }

    @Test("Every item is listed, hidden ones included and marked")
    func listsEverything() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture)
        #expect(Set(byName.keys) == [".hidden", "Alpha", "beta.txt", "gamma.pdf", "linked", "notes.md"])
        #expect(byName[".hidden"]?.isHidden == true)
        #expect(byName["beta.txt"]?.isHidden == false)
    }

    @Test("A folder, and a link to one, open as folders; files do not")
    func foldersAndLinks() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture)
        #expect(byName["Alpha"]?.isFolder == true)
        #expect(byName["linked"]?.isFolder == true)
        #expect(byName["beta.txt"]?.isFolder == false)
        #expect(byName["Alpha"]?.displayName == "Alpha/")
        #expect(byName["beta.txt"]?.displayName == "beta.txt")
    }

    @Test("A file's row has its size and date; a folder's size is --")
    func rowText() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture, rule: FileChoiceRule(locale: Locale(identifier: "en_US")))
        #expect(byName["gamma.pdf"]?.size == 1024)
        // "1 kB" in Foundation's byte-count style, "1 KB" in the older formatter's.
        #expect(byName["gamma.pdf"]?.sizeText.lowercased() == "1 kb")
        #expect(byName["Alpha"]?.size == nil)
        #expect(byName["Alpha"]?.sizeText == "--")
        #expect(byName["beta.txt"]?.modifiedText.isEmpty == false)
        #expect(byName["Alpha"]?.kind.isEmpty == false)
    }

    @Test("A file is typed by what it is")
    func contentTypes() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture)
        #expect(byName["gamma.pdf"]?.contentType.conforms(to: .pdf) == true)
        #expect(byName["beta.txt"]?.contentType.conforms(to: .plainText) == true)
        #expect(byName["Alpha"]?.contentType == .folder)
    }

    @Test("With no types named, every file can be chosen and no folder can")
    func defaultRule() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture)
        #expect(byName["beta.txt"]?.isChoosable == true)
        #expect(byName["gamma.pdf"]?.isChoosable == true)
        #expect(byName["Alpha"]?.isChoosable == false)
    }

    @Test("Only files of a type named can be chosen")
    func typedRule() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture, rule: FileChoiceRule(allowedContentTypes: [.pdf]))
        #expect(byName["gamma.pdf"]?.isChoosable == true)
        #expect(byName["beta.txt"]?.isChoosable == false)
        #expect(byName["notes.md"]?.isChoosable == false)
    }

    @Test("A folder type makes folders choosable, and files not")
    func folderRule() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let byName = try entries(fixture, rule: FileChoiceRule(allowedContentTypes: [.folder]))
        #expect(byName["Alpha"]?.isChoosable == true)
        #expect(byName["linked"]?.isChoosable == true)
        #expect(byName["beta.txt"]?.isChoosable == false)
        // `.item` takes both.
        let both = try entries(fixture, rule: FileChoiceRule(allowedContentTypes: [.item]))
        #expect(both["Alpha"]?.isChoosable == true && both["beta.txt"]?.isChoosable == true)
    }

    @Test("A folder that cannot be read says so, by name")
    func unreadableFolder() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let missing = fixture.url("missing")
        let result = DirectoryListing.read(missing, rule: FileChoiceRule())
        guard case .failure(let failure) = result else {
            Issue.record("a missing folder listed: \(result)")
            return
        }
        #expect(failure.folderName == "missing")
        #expect(!failure.reason.isEmpty)
    }

    @Test("The root's name is its path")
    func rootName() {
        #expect(DirectoryListing.displayName(of: URL(fileURLWithPath: "/")) == "/")
    }

    @Test("A path under the home folder is written from ~")
    func displayPath() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(FilePanelPathBar.displayPath(of: home, home: home) == "~")
        #expect(
            FilePanelPathBar.displayPath(of: URL(fileURLWithPath: "/Users/someone/Documents"), home: home)
                == "~/Documents")
        #expect(
            FilePanelPathBar.displayPath(of: URL(fileURLWithPath: "/Users/someoneelse"), home: home)
                == "/Users/someoneelse")
        #expect(FilePanelPathBar.displayPath(of: URL(fileURLWithPath: "/tmp"), home: home) == "/tmp")
    }
}

@MainActor
@Suite("File browser")
struct FileBrowserTests {
    @Test("A folder's rows are its visible items, folders first, then by name")
    func rowsInOrder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        #expect(browser.state == .loading)
        await browser.refresh()
        #expect(browser.state == .loaded)
        #expect(browser.rows.map(\.name) == ["Alpha", "linked", "beta.txt", "gamma.pdf", "notes.md"])
        #expect(browser.hiddenCount == 1)
    }

    @Test("Showing hidden files lists them, without reading the folder again")
    func hiddenFiles() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        // Removed from disk: a second read would lose it, a re-sort keeps it.
        try FileManager.default.removeItem(at: fixture.url(".hidden"))
        browser.showsHiddenFiles = true
        await browser.refresh()
        #expect(browser.rows.map(\.name).contains(".hidden"))
    }

    @Test("Reloading reads the folder again")
    func reload() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        try Data().write(to: fixture.url("delta.txt"))
        browser.reload()
        await browser.refresh()
        #expect(browser.rows.map(\.name).contains("delta.txt"))
    }

    @Test("Sorting by size puts the largest file first, folders still first")
    func sortBySize() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        browser.sortOrder = [KeyPathComparator(\FileEntry.sortSize, order: .reverse)]
        await browser.refresh()
        #expect(browser.rows.prefix(2).map(\.isFolder) == [true, true])
        #expect(browser.rows[2].name == "gamma.pdf")
    }

    @Test("Opening a folder and going up move the browser, and empty the rows until read")
    func moving() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        browser.open(fixture.url("Alpha"))
        #expect(browser.state == .loading)
        #expect(browser.rows.isEmpty)
        await browser.refresh()
        #expect(browser.rows.map(\.name) == ["inner.txt"])
        browser.goUp()
        #expect(browser.directory == fixture.root.standardizedFileURL)
    }

    /// The column view: P selected (its column reads P), Down to Q (P's
    /// column goes, its task cancelled), Up to P again (a new column asks).
    @Test("A folder's read, under way for an ask that moved on, is kept for the next ask")
    func readOutlivesItsAsker() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        let alpha = fixture.url("Alpha")
        let first = Task { await browser.loadFolder(alpha) }
        // Under way: begun, and gone off the main actor to read.
        while browser.foldersReading[alpha.standardizedFileURL.path] == nil { await Task.yield() }
        first.cancel()
        await browser.loadFolder(alpha)
        await first.value
        #expect(browser.folderRows[alpha.standardizedFileURL.path]?.map(\.name) == ["inner.txt"])
    }

    /// A new order arranges the folders read again, off the main actor; one
    /// read meanwhile was dropped from the rows when the arranging finished,
    /// though its listing stayed, so nothing read it again.
    @Test("A folder read while the others are arranged again keeps its rows")
    func readDuringArranging() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        // Many items, so arranging them takes a while.
        let many = fixture.url("Many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: false)
        for index in 0..<1_500 {
            FileManager.default.createFile(atPath: many.appendingPathComponent("item\(index).txt").path, contents: nil)
        }
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()
        await browser.loadFolder(many)
        browser.sortOrder = [KeyPathComparator(\FileEntry.name, order: .reverse)]
        let arranging = Task { await browser.arrangeFolders(as: browser.refreshKey) }
        // Begun: it took the listings and went off the main actor to sort.
        await Task.yield()
        await browser.loadFolder(fixture.url("Alpha"))
        await arranging.value
        #expect(browser.folderRows[fixture.url("Alpha").standardizedFileURL.path]?.map(\.name) == ["inner.txt"])
        // As Finder compares names, by their numbers, where Foundation can;
        // elsewhere by their characters (`FileBrowser.nameOrder`).
        #if canImport(Darwin)
            let last = "item1499.txt"
        #else
            let last = "item999.txt"
        #endif
        #expect(browser.folderRows[many.standardizedFileURL.path]?.first?.name == last)
    }

    @Test("The root has nothing above it")
    func root() {
        let browser = FileBrowser(directory: URL(fileURLWithPath: "/"), rule: FileChoiceRule())
        #expect(browser.isAtRoot)
        browser.goUp()
        #expect(browser.directory.path == "/")
    }

    @Test("A folder that cannot be read fails, with no rows")
    func failure() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let browser = FileBrowser(directory: fixture.url("missing"), rule: FileChoiceRule())
        await browser.refresh()
        guard case .failed(let failure) = browser.state else {
            Issue.record("expected a failure, got \(browser.state)")
            return
        }
        #expect(failure.folderName == "missing")
        #expect(browser.rows.isEmpty)
    }
}
