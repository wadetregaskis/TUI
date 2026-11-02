//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentGroupTests.swift
//
//  `DocumentGroup` as an app is: the scene in a `TestApp`, driven by its keys
//  and its menu bar, reading and writing real files.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIDocuments
@testable import TUIFilePanels
@testable import TUIFoundation
import TUITesting
import TUIView

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Serialized, and one suite: the apps' views reach what the tests set through
/// ``DocumentProbe``, which has no other way in from an `App`.
@MainActor
@Suite("Document scenes", .serialized)
struct DocumentSceneTests {
    init() {
        DocumentProbe.shared.reset()
    }

    /// The app, drawn, with `url` opened through `openDocument` if it is given.
    private func launched(opening url: URL? = nil) async -> TestApp {
        let app = TestApp(NotesApp(), width: 90, height: 28)
        app.advance(by: .zero)
        await app.see("text=new")
        if let url { await load(url, in: app) }
        return app
    }

    /// Opens `url` through `openDocument`, and waits until it is drawn.
    private func load(_ url: URL, in app: TestApp) async {
        DocumentProbe.shared.url = url
        app.tap("load")
        await app.see("file=\(url.lastPathComponent)")
    }

    // MARK: - Launch and the menu

    @Test("An editor opens with one new document, untitled")
    func launchesNew() async {
        let app = await launched()
        app.advance(by: .zero)
        app.advance(by: .zero)
        #expect(DocumentProbe.shared.made == 1, "newDocument is called once, not once per frame")
        #expect(app.title == "Untitled", "\(app.title)")
        #expect(!app.saysEdited)
        #expect(app.text.contains("file=none editable=true"))
        #expect(app.text.contains("env=none true"))
    }

    @Test("The File menu has New, Open…, Save and Save As…, and what it needs of Close")
    func fileMenu() async {
        let app = await launched()
        app.press(.f10)
        app.press(.right)
        app.press(.down)
        for item in ["New", "Open…", "Save", "Save As…"] {
            #expect(app.text.contains(item), "\(item) in\n\(app.text)")
        }
    }

    @Test("A viewer's File menu has only Open…")
    func viewerMenu() async {
        let app = TestApp(NoteViewerApp(), width: 90, height: 28)
        app.advance(by: .zero)
        app.advance(by: .zero)
        app.press(.escape)
        await app.see("No document is open.")
        app.press(.f10)
        app.press(.right)
        app.press(.down)
        #expect(app.text.contains("Open…"), "\(app.text)")
        #expect(!app.text.contains("Save"), "\(app.text)")
        #expect(!app.text.contains("New"), "\(app.text)")
    }

    // MARK: - Editing and saving

    @Test("A write through the binding marks the document edited, in its title")
    func edited() async {
        let app = await launched()
        app.tap("change")
        await app.see("text=new!")
        #expect(app.title == "Untitled — Edited", "\(app.title)")
    }

    @Test("Typing in a TextEditor edits the document, and the commands' keys get past it")
    func textEditor() async throws {
        let app = TestApp(TextEditApp(), width: 90, height: 28)
        app.advance(by: .zero)
        app.advance(by: .zero)
        app.type("hello")
        await app.see("hello")
        await app.seeEdited()
        app.command("s")
        await app.see("Save As:")
        app.press(.escape)
        try await app.wait(until: { !app.text.contains("Save As:") })
        await app.see("hello")
        #expect(app.saysEdited, "a cancelled save saved nothing")
    }

    @Test("openDocument shows a file, unedited, as editable, and the title is its name")
    func opens() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("hello", "a.txt"))
        #expect(app.text.contains("text=hello"))
        #expect(app.text.contains("file=a.txt editable=true"))
        #expect(app.text.contains("env=a.txt true"))
        #expect(app.title == "a.txt")
        #expect(!app.saysEdited)
    }

    @Test("Save writes over the file, tells the document so, and the document is no longer edited")
    func saveInPlace() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("hello", "a.txt"))
        app.tap("change")
        await app.seeEdited()
        app.command("s")
        try await app.wait(until: { folder.read("a.txt") == "hello!" })
        try await app.wait(until: { !app.saysEdited })
        #expect(DocumentProbe.shared.hadExistingFile == true)
        #expect(!app.text.contains("Save As"), "no panel")
    }

    @Test("Save of an untitled document asks where, and it then has that file")
    func saveUntitled() async throws {
        let folder = try DocumentFolder()
        // Opening a file first, so the panel opens in the test's folder.
        let app = await launched(opening: try folder.write("hello", "a.txt"))
        app.command("n")
        await app.see("file=none")
        app.tap("change")
        app.command("s")
        await app.see("Save As:")
        app.press(.enter)
        try await app.wait(until: { folder.read("Untitled.txt") == "new!" })
        await app.see("file=Untitled.txt")
        #expect(DocumentProbe.shared.hadExistingFile == false)
        try await app.wait(until: { !app.saysEdited })
    }

    @Test("Save As writes a new file, and the document is then that file's")
    func saveAs() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("hello", "a.txt"))
        app.tap("change")
        app.command("s", shift: true)
        await app.see("Save As:")
        app.press(.character("a"), modifiers: .control)
        app.press(.character("k"), modifiers: .control)
        app.type("copy.txt")
        app.press(.enter)
        try await app.wait(until: { folder.read("copy.txt") == "hello!" })
        await app.see("file=copy.txt")
        #expect(folder.read("a.txt") == "hello", "the first file as it was")
        #expect(DocumentProbe.shared.hadExistingFile == false)
    }

    @Test("A read-only file's document cannot be edited, and Save asks where")
    func readOnly() async throws {
        let folder = try DocumentFolder()
        let url = try folder.write("hello", "locked.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let app = await launched(opening: url)
        #expect(app.text.contains("file=locked.txt editable=false"))
        app.tap("change")
        app.advance(by: .zero)
        #expect(!app.text.contains("text=hello!"), "\(app.text)")
        #expect(!app.saysEdited)
        app.command("s")
        await app.see("Save As:")
    }

    @Test("A save that fails says so, and the document stays edited")
    func saveFails() async throws {
        let folder = try DocumentFolder()
        let inner = folder.url("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false)
        let url = inner.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: url)
        let app = await launched(opening: url)
        app.tap("change")
        try FileManager.default.removeItem(at: inner)
        app.command("s")
        await app.see("could not be saved")
        app.press(.enter)
        try await app.wait(until: { !app.text.contains("could not be saved") })
        #expect(app.saysEdited)
    }

    // MARK: - A second document

    @Test("Opening another with nothing unsaved replaces the first without asking")
    func replacesClean() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        await load(try folder.write("two", "b.txt"), in: app)
        #expect(app.text.contains("text=two"))
        #expect(!app.text.contains("Do you want to save"))
    }

    @Test("Opening another with unsaved changes asks; Cancel keeps it, and the open throws")
    func cancelKeeps() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.tap("change")
        DocumentProbe.shared.url = try folder.write("two", "b.txt")
        app.tap("load")
        await app.see("“a.txt”")
        app.press(.escape)
        try await app.wait(until: { DocumentProbe.shared.thrown != nil })
        #expect(DocumentProbe.shared.thrown is CancellationError)
        #expect(app.text.contains("text=one!"), "\(app.text)")
        #expect(app.saysEdited)
        #expect(folder.read("a.txt") == "one")
    }

    @Test("Don't Save loses the changes and replaces it")
    func dontSaveReplaces() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.tap("change")
        DocumentProbe.shared.url = try folder.write("two", "b.txt")
        app.tap("load")
        await app.see("Do you want to save")
        app.tap("Don’t Save")
        await app.see("file=b.txt")
        #expect(app.text.contains("text=two"))
        #expect(!app.saysEdited)
        #expect(folder.read("a.txt") == "one")
    }

    @Test("Save saves the first, then replaces it; Return is Save")
    func saveReplaces() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.tap("change")
        DocumentProbe.shared.url = try folder.write("two", "b.txt")
        app.tap("load")
        await app.see("Do you want to save")
        app.press(.enter)
        await app.see("file=b.txt")
        #expect(folder.read("a.txt") == "one!")
    }

    @Test("Answering Save for an untitled document goes by the panel, and cancelling it keeps everything")
    func savePanelCancelled() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.command("n")
        await app.see("file=none")
        app.tap("change")
        DocumentProbe.shared.url = try folder.write("two", "b.txt")
        app.tap("load")
        await app.see("“Untitled”")
        app.press(.enter)
        await app.see("Save As:")
        app.press(.escape)
        try await app.wait(until: { DocumentProbe.shared.thrown != nil })
        #expect(app.text.contains("text=new!"), "\(app.text)")
        #expect(app.saysEdited)
    }

    @Test("New asks about unsaved changes, and is then a new document from newDocument")
    func newAsks() async throws {
        let app = await launched()
        app.tap("change")
        app.command("n")
        await app.see("Do you want to save")
        app.tap("Don’t Save")
        try await app.wait(until: { DocumentProbe.shared.made == 2 })
        await app.see("file=none")
        #expect(!app.text.contains("text=new!"), "\(app.text)")
        #expect(!app.saysEdited)
    }

    @Test("newDocument(_:) replaces it with the document given")
    func newDocumentAction() async {
        let app = await launched()
        app.tap("preset")
        await app.see("text=preset")
        #expect(!app.saysEdited)
    }

    @Test("Opening a file that cannot be read throws, and keeps what is open")
    func openFails() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        DocumentProbe.shared.url = try folder.write("corrupt", "bad.txt")
        app.tap("load")
        try await app.wait(until: { DocumentProbe.shared.thrown != nil })
        #expect(app.text.contains("text=one"))
        #expect(app.text.contains("file=a.txt"))
    }

    // MARK: - Leaving

    @Test("Quitting with nothing unsaved quits")
    func quitClean() async {
        let app = await launched()
        app.command("q")
        #expect(app.hasRequestedQuit)
    }

    @Test("Quitting with unsaved changes asks: Cancel stays")
    func quitCancel() async {
        let app = await launched()
        app.tap("change")
        app.command("q")
        await app.see("Do you want to save")
        #expect(!app.hasRequestedQuit)
        app.press(.escape)
        try? await app.wait(until: { !app.text.contains("Do you want to save") })
        #expect(!app.hasRequestedQuit)
    }

    @Test("Quitting with unsaved changes asks: Don't Save quits")
    func quitDontSave() async {
        let app = await launched()
        app.tap("change")
        app.command("q")
        await app.see("Do you want to save")
        app.tap("Don’t Save")
        #expect(app.hasRequestedQuit)
    }

    @Test("Quitting with unsaved changes asks: Save saves, and only then quits")
    func quitSave() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.tap("change")
        app.command("q")
        await app.see("Do you want to save")
        app.press(.enter)
        try await app.wait(until: { app.hasRequestedQuit })
        #expect(folder.read("a.txt") == "one!")
    }

    @Test("Answering Save on quitting an untitled document waits on the panel; cancelling it stays")
    func quitSavePanel() async throws {
        let folder = try DocumentFolder()
        let app = await launched(opening: try folder.write("one", "a.txt"))
        app.command("n")
        await app.see("file=none")
        app.tap("change")
        app.command("q")
        await app.see("“Untitled”")
        app.press(.enter)
        await app.see("Save As:")
        #expect(!app.hasRequestedQuit)
        app.press(.escape)
        try await app.wait(until: { !app.text.contains("Save As:") })
        #expect(!app.hasRequestedQuit)
        app.command("q")
        await app.see("“Untitled”")
        app.press(.enter)
        await app.see("Save As:")
        app.press(.enter)
        try await app.wait(until: { app.hasRequestedQuit })
        #expect(folder.read("Untitled.txt") == "new!")
    }

    @Test("The content's own dismiss() asks too")
    func dismissAsks() async {
        let app = await launched()
        app.tap("change")
        app.tap("leave")
        await app.see("Do you want to save")
        #expect(!app.hasRequestedQuit)
        app.tap("Don’t Save")
        #expect(app.hasRequestedQuit)
    }
}
