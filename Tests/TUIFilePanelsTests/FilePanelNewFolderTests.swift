//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelNewFolderTests.swift
//
//  New Folder: a save panel, or one that chooses a folder, makes a folder in
//  the folder it shows and opens it (the owner's NEW-FOLDER, 2026-10-28).
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

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel New Folder", .serialized)
struct FilePanelNewFolderTests {
    /// Keeps the panel presented: held by the test, so it lives as long as the driver.
    private let caller = FilePanelCaller()

    private func panel(_ fixture: FilePanelFixture, purpose: FilePanelRequest.Purpose) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: purpose, rule: FileChoiceRule(), title: "Panel", confirmationLabel: "Go",
                    defaultFilename: "note.txt", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { _ in }, onCancel: {})
    }

    @Test("A save panel's New Folder makes untitled folder where it is, and opens it")
    func saveMakesAndOpens() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .save(contentTypes: [.plainText])) }
        await driver.waitFor("notes.md")
        #expect(driver.click("New Folder"))
        await driver.waitFor("Name of new folder")
        #expect(driver.click("Create"))
        let made = fixture.url("untitled folder")
        await settle { FileManager.default.fileExists(atPath: made.path) }
        #expect(FileManager.default.fileExists(atPath: made.path))
        // The panel shows the new folder, empty.
        await driver.waitFor("untitled folder")
        #expect(!driver.screen().contains("notes.md"), "\(driver.screen())")
    }

    @Test("Back in the folder New Folder made it in, the new folder is listed")
    func newFolderListedInItsParent() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .save(contentTypes: [.plainText])) }
        await driver.waitFor("notes.md")
        #expect(driver.click("New Folder"))
        await driver.waitFor("Name of new folder")
        #expect(driver.click("Create"))
        await settle { !driver.screen().contains("notes.md") }
        // ⌘↑, as the default command key spells it.
        driver.press([FilePanelCommand.enclosingFolder.shortcuts[0].keyEvent(commandKey: .control)!])
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("untitled folder"), "\(shown)")
    }

    @Test("+ in the folder asks for a new folder's name too")
    func plusKey() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .save(contentTypes: [.plainText])) }
        await driver.waitFor("notes.md")
        // From the name field past the path, the view switcher and the
        // Preview button to the folder.
        driver.press(.tab, times: 4)
        driver.press([KeyEvent(key: .character("+"))])
        await driver.waitFor("Name of new folder")
    }

    @Test("An open panel for files has no New Folder")
    func openHasNone() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .open(allowsMultipleSelection: false)) }
        let shown = await driver.waitFor("notes.md")
        #expect(!shown.contains("New Folder"), "\(shown)")
    }

    @Test("A name the folder holds already is numbered, as the Finder numbers it")
    func numbered() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let base = "untitled folder"
        #expect(FilePanelNewFolderPrompt<EmptyView>.availableName(base, in: fixture.root) == base)
        try FileManager.default.createDirectory(at: fixture.url(base), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: fixture.url(base + " 2"), withIntermediateDirectories: false)
        #expect(FilePanelNewFolderPrompt<EmptyView>.availableName(base, in: fixture.root) == base + " 3")
        #expect(throws: (any Error).self) { try FilePanelNewFolderPrompt<EmptyView>.makeFolder(named: "a/b", in: fixture.root) }
    }
}
