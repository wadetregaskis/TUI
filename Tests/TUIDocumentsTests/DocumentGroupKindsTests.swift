//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentGroupKindsTests.swift
//
//  `DocumentGroup` as a viewer, and of a `ReferenceFileDocument`.
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

// MARK: - Viewers

extension DocumentSceneTests {
    /// A viewer's window, its panels opening on `folder`.
    private func viewerWindow(_ folder: DocumentFolder) -> TestApp {
        let group = DocumentGroup(viewing: Note.self) { file in NotePage(file: file) }
        return TestApp(width: 90, height: 28) {
            DocumentWindow(makeStore: group.makeStore, isViewer: group.isViewer, content: group.content)
                .fileDialogDefaultDirectory(folder.root)
        }
    }

    @Test("It opens with the panel; cancelling leaves a page that asks again")
    func opensPanel() async throws {
        let folder = try DocumentFolder()
        try folder.write("hello", "a.txt")
        let app = viewerWindow(folder)
        app.advance(by: .zero)
        await app.see("a.txt")
        app.press(.escape)
        await app.see("No document is open.")
        app.tap("Open…")
        await app.see("a.txt")
    }

    @Test("A file chosen is shown read-only, and a write through the binding is ignored")
    func viewsReadOnly() async throws {
        let folder = try DocumentFolder()
        try folder.write("hello", "a.txt")
        let app = viewerWindow(folder)
        app.advance(by: .zero)
        await app.see("a.txt")
        app.press(.down)
        app.press(.enter)
        await app.see("text=hello")
        #expect(app.text.contains("file=a.txt editable=false"), "\(app.text)")
        app.tap("change")
        app.advance(by: .zero)
        #expect(!app.text.contains("text=hello!"))
        #expect(!app.saysEdited)
    }

    @Test("A file that cannot be read says so, and shows nothing")
    func viewerOpenFails() async throws {
        let folder = try DocumentFolder()
        try folder.write("corrupt", "bad.txt")
        let app = viewerWindow(folder)
        app.advance(by: .zero)
        await app.see("bad.txt")
        app.press(.down)
        app.press(.enter)
        await app.see("could not be opened")
        app.press(.enter)
        await app.see("No document is open.")
    }

    @Test("A reference viewer shows an object read-only")
    func referenceViewer() async throws {
        let folder = try DocumentFolder()
        try folder.write("hello", "a.txt")
        let group = DocumentGroup(viewing: Sketch.self) { file in SketchPage(file: file) }
        let app = TestApp(width: 90, height: 28) {
            DocumentWindow(makeStore: group.makeStore, isViewer: group.isViewer, content: group.content)
                .fileDialogDefaultDirectory(folder.root)
        }
        app.advance(by: .zero)
        await app.see("a.txt")
        app.press(.down)
        app.press(.enter)
        await app.see("text=hello")
        #expect(app.text.contains("editable=false"))
        app.tap("bound")
        app.advance(by: .zero)
        #expect(!app.text.contains("text=hello?"), "a viewer's binding ignores writes")
    }
}

// MARK: - Reference documents

extension DocumentSceneTests {
    private func launchedSketches() async -> TestApp {
        let app = TestApp(SketchesApp(), width: 90, height: 28)
        app.advance(by: .zero)
        await app.see("text=new")
        return app
    }

    @Test("A write to an @Observable property the snapshot reads marks it edited")
    func editedByObservation() async throws {
        let app = await launchedSketches()
        app.tap("change")
        await app.see("text=new!")
        await app.seeEdited()
    }

    @Test("A write through $document's binding marks it edited")
    func editedByBinding() async throws {
        let app = await launchedSketches()
        app.tap("bound")
        await app.see("text=new?")
        await app.seeEdited()
    }

    @Test("A write to what the snapshot does not read is no edit")
    func notEdited() async throws {
        let app = await launchedSketches()
        app.tap("scroll")
        app.advance(by: .milliseconds(100))
        app.advance(by: .zero)
        #expect(!app.saysEdited)
    }

    @Test("Saving writes the snapshot, and the watch begins again for the next edit")
    func savesAndWatchesAgain() async throws {
        let folder = try DocumentFolder()
        let app = await launchedSketches()
        DocumentProbe.shared.url = try folder.write("one", "a.txt")
        app.tap("load")
        await app.see("file=a.txt")
        #expect(!app.saysEdited, "\(app.text)")
        app.tap("change")
        await app.seeEdited()
        app.command("s")
        try await app.wait(until: { folder.read("a.txt") == "one!" })
        try await app.wait(until: { !app.saysEdited })
        app.tap("change")
        await app.see("text=one!!")
        await app.seeEdited()
    }

    #if canImport(Combine)
        @Test("A @Published document redraws and counts as edited")
        func published() async throws {
            let app = TestApp(PublishedSketchesApp(), width: 90, height: 28)
            app.advance(by: .zero)
            await app.see("text=new")
            app.tap("change")
            await app.see("text=new!")
            await app.seeEdited()
        }
    #endif
}
