//  🖥️ TUI — A Terminal UI framework for Swift
//  ReferenceFileDocumentExporterTests.swift
//
//  `fileExporter` with a `ReferenceFileDocument`: the save panel, and the
//  document's snapshot written where it says.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

/// A plain-text document that is an object.
final class TextObject: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(bytes: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("Reference file document exporter", .serialized)
struct ReferenceFileDocumentExporterTests {
    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    @Test("A document is saved through its snapshot, as Untitled with its type's extension")
    func savesDocument() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let document = TextObject(text: "draft")
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, document: document,
                    onCompletion: { caller.completed($0) }, onCancellation: { caller.cancelled() }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        #expect(caller.heard == ["completed (presented: false)"])
        #expect(contents(fixture.url("Untitled.txt")) == "draft")
    }

    @Test("The single-type form saves as that type, under the default name")
    func singleType() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let document = TextObject(text: "{}")
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, document: document, contentType: .json,
                    defaultFilename: "data", onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        #expect(caller.saved.map(\.lastPathComponent) == ["data.json"])
    }

    @Test("With no document, the panel is not presented")
    func noDocument() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let none: TextObject? = nil
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(isPresented: caller.binding, document: none) { caller.completed($0) }
                .fileDialogDefaultDirectory(fixture.root)
        }
        #expect(!driver.screen().contains("notes.md"))
    }
}
