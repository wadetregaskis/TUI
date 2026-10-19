//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileExporterTests.swift
//
//  The save panel, through `fileExporter` for `Transferable` items: the name,
//  the write, the replace alert, and saving several items into a folder.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@Suite("Save names")
struct SaveNameTests {
    @Test("A name is given its type's extension unless it has one of the types'")
    func resolve() {
        #expect(SaveName.resolve("notes", contentTypes: [.plainText]) == "notes.txt")
        #expect(SaveName.resolve("notes.txt", contentTypes: [.plainText]) == "notes.txt")
        // Markdown is plain text, so its extension stands.
        #expect(SaveName.resolve("notes.md", contentTypes: [.plainText]) == "notes.md")
        #expect(SaveName.resolve("notes.pdf", contentTypes: [.plainText]) == "notes.pdf.txt")
        #expect(SaveName.resolve("  notes ", contentTypes: []) == "notes")
    }

    @Test("A name no file can have is no name")
    func invalid() {
        for name in ["", "  ", ".", "..", "a/b"] {
            #expect(SaveName.resolve(name, contentTypes: [.plainText]) == nil, "\(name)")
        }
    }

    @Test("The type saved as is the one the name names, else the first")
    func typeForName() {
        #expect(SaveName.type(for: "a.json", among: [.plainText, .json]) == .json)
        #expect(SaveName.type(for: "a.md", among: [.json, .plainText]) == .plainText)
        #expect(SaveName.type(for: "a", among: [.json, .plainText]) == .json)
        #expect(SaveName.type(for: "a", among: []) == nil)
    }

    @Test("Several files are named by their suggestions, else Untitled, numbered")
    func exportNames() {
        let names = ExportNames.names(
            ["report", nil, nil], contentTypes: [[.plainText], [.plainText], [.json]])
        #expect(names == ["report.txt", "Untitled.txt", "Untitled 2.json"])
    }
}

#if canImport(CoreTransferable)
    import CoreTransferable

    /// A note that exports as plain text and suggests its own name.
    struct ExportedNote: Transferable {
        var text: String

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .plainText) { note in Data(note.text.utf8) }
                .suggestedFileName("note.txt")
        }
    }

    /// A note that exports as plain text and suggests no name.
    struct UnnamedNote: Transferable {
        var text: String

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .plainText) { note in Data(note.text.utf8) }
        }
    }

    /// What an exporter's caller heard.
    @MainActor
    final class FileExporterCaller {
        var isPresented = true
        var heard: [String] = []
        var saved: [URL] = []
        var failure: (any Error)?

        var binding: Binding<Bool> {
            Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
        }

        func completed(_ result: Result<URL, any Error>) {
            completedAll(result.map { [$0] })
        }

        func completedAll(_ result: Result<[URL], any Error>) {
            heard.append("completed (presented: \(isPresented))")
            switch result {
            case .success(let urls): saved = urls
            case .failure(let error): failure = error
            }
        }

        func cancelled() {
            heard.append("cancelled (presented: \(isPresented))")
        }
    }

    /// Serialized for the reason ``FileImporterPanelTests`` is.
    @MainActor
    @Suite("File exporter", .serialized)
    struct FileExporterTests {
        private func exporter(
            _ fixture: FilePanelFixture, caller: FileExporterCaller, item: ExportedNote? = ExportedNote(text: "hello"),
            defaultFilename: String? = nil
        ) -> some View {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, item: item, defaultFilename: defaultFilename,
                    onCompletion: { caller.completed($0) }, onCancellation: { caller.cancelled() }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }

        private func contents(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
        }

        @Test("The name field offers the item's suggested name; Return saves it there")
        func savesSuggestedName() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller) }
            let shown = await driver.waitFor("notes.md")
            #expect(shown.contains("Save As:"))
            #expect(shown.contains("note.txt"))
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.heard == ["completed (presented: false)"])
            #expect(caller.saved.map(\.path) == [fixture.url("note.txt").path])
            #expect(contents(fixture.url("note.txt")) == "hello")
        }

        @Test("A default name without the type's extension is given it")
        func defaultNameGetsExtension() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller, defaultFilename: "greeting") }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.saved.map(\.path) == [fixture.url("greeting.txt").path])
        }

        @Test("Saving over a file asks first; Replace replaces it")
        func replaceAsks() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller, defaultFilename: "beta.txt") }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            let asking = driver.screen()
            #expect(asking.contains("“beta.txt” already exists"), "\(asking)")
            #expect(caller.heard.isEmpty)
            // The alert's buttons: Cancel, then Replace.
            driver.press(.tab)
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.saved.map(\.path) == [fixture.url("beta.txt").path])
            #expect(contents(fixture.url("beta.txt")) == "hello")
        }

        @Test("Cancelling the replace keeps the panel and the file")
        func replaceCancelled() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller, defaultFilename: "beta.txt") }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            driver.press(.escape)
            let shown = driver.screen()
            #expect(!shown.contains("already exists"))
            #expect(shown.contains("notes.md"), "the panel is still up")
            #expect(caller.heard.isEmpty)
            #expect(contents(fixture.url("beta.txt")) == "beta")
        }

        @Test("Return on a file of the type puts its name in the field")
        func fileNameFromRow() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller) }
            await driver.waitFor("notes.md")
            // To the table, then Alpha/, linked/, beta.txt.
            driver.press(.tab)
            driver.press(.down, times: 2)
            driver.press(.enter)
            #expect(caller.heard.isEmpty, "a file is a name, not a save")
            // The focus is back in the field: Return saves, and asks to replace.
            driver.press(.enter)
            #expect(driver.screen().contains("“beta.txt” already exists"))
        }

        @Test("The name field's label is the app's")
        func filenameLabel() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller).fileExporterFilenameLabel("Export As:") }
            let shown = await driver.waitFor("notes.md")
            #expect(shown.contains("Export As:"))
            #expect(!shown.contains("Save As:"))
        }

        @Test("With no item, the panel is not presented")
        func noItem() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller, item: nil) }
            #expect(!driver.screen().contains("Save"))
        }

        @Test("Several items are saved into the folder chosen, each under its own name")
        func savesSeveral() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let notes = [UnnamedNote(text: "one"), UnnamedNote(text: "two")]
            let driver = FilePanelDriver {
                Text("Page")
                    .fileExporter(
                        isPresented: caller.binding, items: notes, onCompletion: { caller.completedAll($0) })
                    .fileDialogDefaultDirectory(fixture.root)
            }
            await driver.waitFor("notes.md")
            // Into Alpha, then Save (past the switch and Cancel).
            driver.press(.enter)
            await driver.waitFor("inner.txt")
            driver.press(.tab, times: 3)
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.saved.map(\.lastPathComponent) == ["Untitled.txt", "Untitled 2.txt"])
            #expect(contents(fixture.url("Alpha/Untitled 2.txt")) == "two")
        }
    }
#endif
