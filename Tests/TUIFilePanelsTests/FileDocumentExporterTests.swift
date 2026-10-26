//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDocumentExporterTests.swift
//
//  `fileExporter` with a `FileDocument`: the save panel, and the document's
//  file wrapper written where it says.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(ObjectiveC)
    import Foundation
    import Testing
    import UniformTypeIdentifiers

    @testable import TUIApp
    @testable import TUIAppTestSupport
    @testable import TUICore
    @testable import TUIFilePanels
    @testable import TUIFoundation
    @testable import TUITestSupport

    /// A plain-text document, as Apple's documentation writes one.
    struct TextFile: FileDocument {
        static var readableContentTypes: [UTType] { [.plainText] }

        var text = ""

        init(text: String) {
            self.text = text
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            text = String(bytes: data, encoding: .utf8) ?? ""
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(text.utf8))
        }
    }

    /// A document that cannot be written.
    struct BrokenFile: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }

        init() {}

        init(configuration: ReadConfiguration) throws {}

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Serialized for the reason ``FileImporterPanelTests`` is.
    @MainActor
    @Suite("File document exporter", .serialized)
    struct FileDocumentExporterTests {
        private func contents(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
        }

        @Test("A document is saved as Untitled with its type's extension, through its file wrapper")
        func savesDocument() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver {
                Text("Page")
                    .fileExporter(
                        isPresented: caller.binding, document: TextFile(text: "draft"),
                        onCompletion: { caller.completed($0) }, onCancellation: { caller.cancelled() }
                    )
                    .fileDialogDefaultDirectory(fixture.root)
            }
            let shown = await driver.waitFor("notes.md")
            #expect(shown.contains("Untitled"))
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.heard == ["completed (presented: false)"])
            #expect(caller.saved.map(\.path) == [fixture.url("Untitled.txt").path])
            #expect(contents(fixture.url("Untitled.txt")) == "draft")
        }

        @Test("The single-type form saves as that type, under the default name")
        func singleType() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver {
                Text("Page")
                    .fileExporter(
                        isPresented: caller.binding, document: TextFile(text: "{}"), contentType: .json,
                        defaultFilename: "data", onCompletion: { caller.completed($0) }
                    )
                    .fileDialogDefaultDirectory(fixture.root)
            }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.saved.map(\.lastPathComponent) == ["data.json"])
        }

        @Test("A document that cannot be written fails, after the binding is cleared")
        func writeFails() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let driver = FilePanelDriver {
                Text("Page")
                    .fileExporter(isPresented: caller.binding, document: BrokenFile()) { caller.completed($0) }
                    .fileDialogDefaultDirectory(fixture.root)
            }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.heard == ["completed (presented: false)"])
            #expect(caller.failure != nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.url("Untitled.json").path))
        }

        @Test("With no document, the panel is not presented")
        func noDocument() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let none: TextFile? = nil
            let driver = FilePanelDriver {
                Text("Page").fileExporter(isPresented: caller.binding, document: none) { caller.completed($0) }
            }
            #expect(!driver.screen().contains("Save"))
        }

        @Test("Several documents are saved into the folder chosen, Untitled, Untitled 2, …")
        func savesSeveral() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let documents = [TextFile(text: "one"), TextFile(text: "two")]
            let driver = FilePanelDriver {
                Text("Page")
                    .fileExporter(
                        isPresented: caller.binding, documents: documents, contentType: .plainText,
                        onCompletion: { caller.completedAll($0) }
                    )
                    .fileDialogDefaultDirectory(fixture.root)
            }
            await driver.waitFor("notes.md")
            driver.press(.enter)
            await driver.waitFor("inner.txt")
            driver.press(.tab, times: 3)
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
            #expect(caller.saved.map(\.lastPathComponent) == ["Untitled.txt", "Untitled 2.txt"])
            #expect(contents(fixture.url("Alpha/Untitled.txt")) == "one")
        }
    }
#endif
