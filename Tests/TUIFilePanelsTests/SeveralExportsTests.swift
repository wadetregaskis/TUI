//  🖥️ TUI — A Terminal UI framework for Swift
//  SeveralExportsTests.swift
//
//  `fileExporter(items:)` and `fileExporter(documents:)`: the names several
//  files are saved under in the folder chosen, which neither collide with
//  each other nor with what the folder holds already.
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

#if canImport(CoreTransferable)
    import CoreTransferable

    /// Serialized for the reason ``FileImporterPanelTests`` is.
    @MainActor
    @Suite("Exporting several files", .serialized)
    struct SeveralExportsTests {
        private func contents(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
        }

        /// Opens Alpha (the first row), presses Save (past the hidden-files
        /// switch and Cancel), and waits for the writes.
        private func saveIntoAlpha(_ driver: FilePanelDriver<some View>, caller: FileExporterCaller) async {
            await driver.waitFor("notes.md")
            driver.press(.enter)
            await driver.waitFor("inner.txt")
            driver.press(.tab, times: 4)
            driver.press(.enter)
            await settle { !caller.heard.isEmpty }
        }

        /// An exporter of `notes` into a folder chosen, opening on `fixture`'s root.
        private func exporter(
            _ fixture: FilePanelFixture, caller: FileExporterCaller, notes: [ExportedNote]
        ) -> some View {
            Text("Page")
                .fileExporter(isPresented: caller.binding, items: notes, onCompletion: { caller.completedAll($0) })
                .fileDialogDefaultDirectory(fixture.root)
        }

        @Test("Items that suggest one name are saved under it, numbered: note.txt, note 2.txt")
        func itemsShareAName() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            let caller = FileExporterCaller()
            let notes = [ExportedNote(text: "one"), ExportedNote(text: "two")]
            let driver = FilePanelDriver { exporter(fixture, caller: caller, notes: notes) }
            await saveIntoAlpha(driver, caller: caller)
            #expect(caller.failure == nil, "\(String(describing: caller.failure))")
            #expect(caller.saved.map(\.lastPathComponent) == ["note.txt", "note 2.txt"])
            #expect(contents(fixture.url("Alpha/note.txt")) == "one")
            #expect(contents(fixture.url("Alpha/note 2.txt")) == "two")
        }

        @Test("A name the folder has already is numbered past, and the folder's file is kept")
        func nameTakenInFolder() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            try Data("kept".utf8).write(to: fixture.url("Alpha/note.txt"))
            let caller = FileExporterCaller()
            let driver = FilePanelDriver { exporter(fixture, caller: caller, notes: [ExportedNote(text: "new")]) }
            await saveIntoAlpha(driver, caller: caller)
            #expect(caller.failure == nil, "\(String(describing: caller.failure))")
            #expect(caller.saved.map(\.lastPathComponent) == ["note 2.txt"])
            #expect(contents(fixture.url("Alpha/note.txt")) == "kept")
            #expect(contents(fixture.url("Alpha/note 2.txt")) == "new")
        }

        #if canImport(ObjectiveC)
            @Test("Documents saved where an Untitled is already are numbered past it")
            func documentsPastUntitled() async throws {
                let fixture = try FilePanelFixture()
                defer { fixture.remove() }
                try Data("kept".utf8).write(to: fixture.url("Alpha/Untitled.txt"))
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
                await saveIntoAlpha(driver, caller: caller)
                #expect(caller.failure == nil, "\(String(describing: caller.failure))")
                #expect(caller.saved.map(\.lastPathComponent) == ["Untitled 2.txt", "Untitled 3.txt"])
                #expect(contents(fixture.url("Alpha/Untitled.txt")) == "kept")
            }
        #endif
    }
#endif
