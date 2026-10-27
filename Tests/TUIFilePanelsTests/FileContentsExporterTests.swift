//  🖥️ TUI — A Terminal UI framework for Swift
//  FileContentsExporterTests.swift
//
//  The save panel through the TUI-only exporters every platform has: a
//  value's bytes (`FileExportContents`: `Data`, `String`) and an `Encodable`
//  value (decisions A-O10-1, 2026-10-27).
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

/// Settings, encoded to a file.
private struct Settings: Codable, Equatable {
    var name: String
    var size: Int
}

/// Contents that refuse to be written.
private struct Refusing: FileExportContents {
    struct Refused: Error {}
    func fileData(as contentType: UTType) throws -> Data { throw Refused() }
}

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File exporter for contents and encodable values", .serialized)
struct FileContentsExporterTests {
    private func data(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    @Test("A String is saved as its UTF-8, under the type's extension")
    func savesAString() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, contents: "héllo", contentType: .plainText,
                    defaultFilename: "greeting", onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("greeting"))
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        #expect(caller.saved.map(\.path) == [fixture.url("greeting.txt").path])
        #expect(data(fixture.url("greeting.txt")) == Data("héllo".utf8))
    }

    @Test("Data is saved as it is")
    func savesData() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let bytes = Data([0, 1, 2, 255])
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, contents: bytes, contentType: .data, defaultFilename: "blob",
                    onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        let saved = try #require(caller.saved.first)
        #expect(data(saved) == bytes)
    }

    @Test("An Encodable value is saved as JSON by default, and reads back")
    func savesJSON() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let settings = Settings(name: "Ada", size: 3)
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, encoding: settings, defaultFilename: "settings",
                    onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        #expect(caller.saved.map(\.path) == [fixture.url("settings.json").path])
        let written = try #require(data(fixture.url("settings.json")))
        #expect(try JSONDecoder().decode(Settings.self, from: written) == settings)
    }

    @Test("An Encodable value is saved as a property list where the type is one")
    func encodesPropertyList() throws {
        let settings = Settings(name: "Ada", size: 3)
        let written = try EncodedContents(value: settings).fileData(as: .propertyList)
        #expect(try PropertyListDecoder().decode(Settings.self, from: written) == settings)
        let json = try EncodedContents(value: settings).fileData(as: .json)
        #expect(String(bytes: json, encoding: .utf8)?.contains("\"name\" : \"Ada\"") == true)
    }

    @Test("Contents that cannot be made end the save with their error, and nothing is written")
    func refusalIsTheError() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, contents: Refusing(), contentType: .plainText,
                    defaultFilename: "never", onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
        #expect(caller.saved.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.url("never.txt").path))
    }

    @Test("No contents presents nothing")
    func nilPresentsNothing() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileExporterCaller()
        let driver = FilePanelDriver {
            Text("Page")
                .fileExporter(
                    isPresented: caller.binding, contents: String?.none, contentType: .plainText,
                    onCompletion: { caller.completed($0) }
                )
                .fileDialogDefaultDirectory(fixture.root)
        }
        #expect(!driver.screen().contains("Save As:"))
    }
}
