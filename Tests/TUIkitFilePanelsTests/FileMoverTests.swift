//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileMoverTests.swift
//
//  `fileMover`: choosing a folder in the panel, and the move into it.
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

/// What a mover's caller heard.
@MainActor
final class FileMoverCaller {
    var isPresented = true
    var heard: [String] = []
    var moved: [URL] = []
    var failure: (any Error)?

    var binding: Binding<Bool> {
        Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
    }

    func completed(_ result: Result<[URL], any Error>) {
        heard.append("completed (presented: \(isPresented))")
        switch result {
        case .success(let urls): moved = urls
        case .failure(let error): failure = error
        }
    }

    func cancelled() {
        heard.append("cancelled (presented: \(isPresented))")
    }
}

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File mover", .serialized)
struct FileMoverTests {
    /// A mover of `files`, which opens on the folder that holds the first.
    private func mover(_ files: [URL], caller: FileMoverCaller) -> some View {
        Text("Page").fileMover(
            isPresented: caller.binding, files: files, onCompletion: { caller.completed($0) },
            onCancellation: { caller.cancelled() })
    }

    /// Opens Alpha (the first row) and presses Move (past the hidden-files
    /// switch and Cancel), then waits for the move, which is done off the
    /// main actor.
    private func moveIntoAlpha(_ driver: FilePanelDriver<some View>, caller: FileMoverCaller) async {
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.tab, times: 3)
        driver.press(.enter)
        await settle { !caller.heard.isEmpty }
    }

    @Test("The panel chooses a folder: files are dimmed, and Move moves into the folder shown")
    func movesIntoFolderShown() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        let driver = FilePanelDriver { mover([fixture.url("beta.txt")], caller: caller) }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Move"))
        await moveIntoAlpha(driver, caller: caller)
        #expect(caller.heard == ["completed (presented: false)"])
        #expect(caller.moved.map(\.path) == [fixture.url("Alpha/beta.txt").path])
        #expect(FileManager.default.fileExists(atPath: fixture.url("Alpha/beta.txt").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.url("beta.txt").path))
    }

    @Test("The panel opens on the folder that holds the file")
    func opensOnFilesFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        let driver = FilePanelDriver { mover([fixture.url("Alpha/inner.txt")], caller: caller) }
        let shown = await driver.waitFor("inner.txt", timeout: .seconds(10))
        #expect(shown.contains("inner.txt") && !shown.contains("beta.txt"), "\(shown)")
    }

    @Test("Once a move is made, the panel opens on the folder moved into, not the next file's")
    func opensOnLastDestination() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        var files = [fixture.url("beta.txt")]
        let driver = FilePanelDriver { mover(files, caller: caller) }
        await moveIntoAlpha(driver, caller: caller)
        #expect(caller.moved.map(\.path) == [fixture.url("Alpha/beta.txt").path])
        // A file in the root, moved through the same view: its panel opens in
        // Alpha, where the last went, as a macOS panel opens on the folder
        // used last.
        files = [fixture.url("gamma.pdf")]
        caller.heard = []
        caller.isPresented = true
        let shown = await driver.waitFor("beta.txt", timeout: .seconds(10))
        #expect(shown.contains("inner.txt") && !shown.contains("notes.md"), "\(shown)")
    }

    @Test("The file is the one the binding names when the panel is presented, not when the view first drew")
    func fileReadWhenPresented() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        caller.isPresented = false
        var file: URL?
        let driver = FilePanelDriver {
            Text("Page").fileMover(isPresented: caller.binding, file: file) { caller.completed($0.map { [$0] }) }
        }
        driver.screen()
        file = fixture.url("Alpha/inner.txt")
        driver.screen()
        caller.isPresented = true
        let shown = await driver.waitFor("inner.txt", timeout: .seconds(10))
        #expect(shown.contains("inner.txt") && !shown.contains("beta.txt"), "\(shown)")
    }

    @Test("Several files move together, in order")
    func movesSeveral() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        let files = [fixture.url("beta.txt"), fixture.url("gamma.pdf")]
        let driver = FilePanelDriver { mover(files, caller: caller) }
        await moveIntoAlpha(driver, caller: caller)
        #expect(caller.moved.map(\.path) == [fixture.url("Alpha/beta.txt").path, fixture.url("Alpha/gamma.pdf").path])
    }

    @Test("A name already in the folder fails the move, with the file left where it was")
    func conflictFails() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        try Data("other".utf8).write(to: fixture.url("Alpha/beta.txt"))
        let caller = FileMoverCaller()
        let driver = FilePanelDriver { mover([fixture.url("beta.txt")], caller: caller) }
        await moveIntoAlpha(driver, caller: caller)
        #expect(caller.failure != nil)
        #expect(caller.moved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.url("beta.txt").path))
    }

    @Test("Cancel moves nothing and is heard as a cancellation")
    func cancel() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        let driver = FilePanelDriver { mover([fixture.url("beta.txt")], caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.escape)
        #expect(caller.heard == ["cancelled (presented: false)"])
        #expect(FileManager.default.fileExists(atPath: fixture.url("beta.txt").path))
    }

    @Test("With no files, the panel is not presented")
    func noFiles() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FileMoverCaller()
        let driver = FilePanelDriver {
            Text("Page").fileMover(isPresented: caller.binding, file: nil) { _ in }
        }
        let shown = driver.screen()
        #expect(!shown.contains("Move"))
        #expect(caller.isPresented, "the app's binding is left as it set it")
    }

    @Test("Moving a file to the folder it is in moves nothing, and succeeds")
    func sameFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let result = await FileMove.move([fixture.url("beta.txt")], into: fixture.root)
        #expect((try? result.get())?.map(\.path) == [fixture.url("beta.txt").path])
        #expect(FileManager.default.fileExists(atPath: fixture.url("beta.txt").path))
    }
}
