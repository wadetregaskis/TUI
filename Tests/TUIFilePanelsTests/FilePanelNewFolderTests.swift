//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelNewFolderTests.swift
//
//  New Folder: a save panel, or a mover's, makes a folder in the folder it shows
//  and opens it (the owner's NEW-FOLDER, 2026-10-28; none in an open panel, 2026-11-02).
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

    @Test("An open panel that chooses folders has no New Folder either")
    func openOfFoldersHasNone() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver {
            FilePanelPresenter(
                content: Text("Page"), isPresented: caller.binding,
                request: {
                    FilePanelRequest(
                        purpose: .open(allowsMultipleSelection: false),
                        rule: FileChoiceRule(allowedContentTypes: [.folder], choosesFiles: false), title: "Panel",
                        confirmationLabel: "Go", startDirectory: fixture.root, homeDirectory: fixture.root)
                },
                onChoose: { _ in }, onCancel: {})
        }
        let shown = await driver.waitFor("Show Hidden")
        #expect(!shown.contains("New Folder"), "\(shown)")
    }

    @Test("A mover has New Folder")
    func moverHasIt() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver {
            Text("Page").fileMover(isPresented: caller.binding, file: fixture.url("notes.md")) { _ in }
        }
        await driver.waitFor("New Folder")
    }

    @Test("A name taken says so in the sheet, which stays up with the name to change")
    func nameTaken() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .save(contentTypes: [.plainText])) }
        await driver.waitFor("notes.md")
        #expect(driver.click("New Folder"))
        await driver.waitFor("Name of new folder")
        // The offered name is free until now: something else takes it meanwhile.
        try FileManager.default.createDirectory(
            at: fixture.url("untitled folder"), withIntermediateDirectories: false)
        #expect(driver.click("Create"))
        let said = await driver.waitFor("already taken")
        #expect(said.contains("Name of new folder"), "\(said)")
        // The focus is back in the field with the name selected, so typing replaces
        // it, which takes the words away, and Return there makes it.
        driver.press([KeyEvent(key: .character("x"))])
        await settle { !driver.screen().contains("already taken") }
        #expect(!driver.screen().contains("already taken"), "\(driver.screen())")
        driver.press(.enter)
        await settle { FileManager.default.fileExists(atPath: fixture.url("x").path) }
        #expect(FileManager.default.fileExists(atPath: fixture.url("x").path))
    }

    @Test("Typing in the sheet replaces the name it offers")
    func typingReplacesTheOffer() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let driver = FilePanelDriver { panel(fixture, purpose: .save(contentTypes: [.plainText])) }
        await driver.waitFor("notes.md")
        #expect(driver.click("New Folder"))
        await driver.waitFor("untitled folder")
        driver.press(Array("Reports").map { KeyEvent(key: .character($0)) })
        driver.press(.enter)
        await settle { FileManager.default.fileExists(atPath: fixture.url("Reports").path) }
        #expect(FileManager.default.fileExists(atPath: fixture.url("Reports").path))
    }

    /// Skipped where permissions don't bind, as for root, which some CI containers are.
    @Test("A folder the user may not write to says so in the sheet")
    func noPermission() async throws {
        let fixture = try FilePanelFixture()
        let locked = fixture.url("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            fixture.remove()
        }
        guard !FileManager.default.isWritableFile(atPath: locked.path) else { return }
        let driver = FilePanelDriver {
            FilePanelPresenter(
                content: Text("Page"), isPresented: caller.binding,
                request: {
                    FilePanelRequest(
                        purpose: .save(contentTypes: [.plainText]), rule: FileChoiceRule(), title: "Panel",
                        confirmationLabel: "Go", defaultFilename: "note.txt", startDirectory: locked,
                        homeDirectory: fixture.root)
                },
                onChoose: { _ in }, onCancel: {})
        }
        await driver.waitFor("New Folder")
        #expect(driver.click("New Folder"))
        await driver.waitFor("Name of new folder")
        #expect(driver.click("Create"))
        await driver.waitFor("permission")
    }

    @Test("A failure's words: TUI's own for what a person can act on, the system's for the rest")
    func failureWords() {
        typealias Prompt = FilePanelNewFolderPrompt<EmptyView>
        #expect(Prompt.failureMessage(CocoaError(.fileWriteFileExists), named: "a").contains("“a” is already taken"))
        #expect(Prompt.failureMessage(CocoaError(.fileWriteNoPermission), named: "a").contains("permission"))
        #expect(Prompt.failureMessage(CocoaError(.fileWriteVolumeReadOnly), named: "a").contains("permission"))
        #expect(Prompt.failureMessage(CocoaError(.fileWriteInvalidFileName), named: "a/b").contains("“a/b” can’t be used"))
        let other = CocoaError(.fileWriteOutOfSpace)
        #expect(Prompt.failureMessage(other, named: "a").hasPrefix("The folder “a” can’t be created. "))
        #expect(Prompt.failureMessage(other, named: "a").hasSuffix(other.localizedDescription))
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
