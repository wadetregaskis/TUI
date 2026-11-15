//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentOpeningFocusTests.swift
//
//  Where the focus starts in a document a `DocumentGroup` opens after launch:
//  as in a window's first content, never in a `.searchable`'s field unless the
//  content has nothing else, and on the content's `.defaultFocus` when it has
//  one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIDocuments
@testable import TUIFoundation
import TUISearch
import TUITesting
import TUITextInput
import TUIView

/// What a test reads of the app, and what the app opens: the suite's own, as an
/// `App` is made with no arguments, and reset by each test.
@MainActor
final class OpeningProbe {
    static var current = OpeningProbe()

    /// What F5 opens through `openDocument`.
    var url: URL?
    /// The search field's text.
    var query = ""
    /// How many times the content's button was pressed.
    var pressed = 0
}

/// A document's editor as tuitree's is: a source pane, a control standing in
/// for its table, a search field over both, and F5 to open a file.
private struct SearchingEditor: View {
    enum Field: Hashable { case source, table }

    let file: FileDocumentConfiguration<Note>
    let probe: OpeningProbe
    let defaultsToTable: Bool

    @FocusState private var focus: Field?
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        VStack {
            Text(verbatim: "file=\(file.fileURL?.lastPathComponent ?? "none")")
            TextEditor(text: file.$document.text)
                .frame(height: 3)
                .focused($focus, equals: .source)
            Button("table") { probe.pressed += 1 }
                .focused($focus, equals: .table)
        }
        .searchable(
            text: Binding(get: { probe.query }, set: { probe.query = $0 }), prompt: "Find")
        .defaultFocus($focus, defaultsToTable ? .table : nil)
        .onKeyEvent { event in
            guard event.key == .f5, let url = probe.url else { return false }
            Task { try? await openDocument(at: url) }
            return true
        }
    }
}

/// A `DocumentGroup` of ``SearchingEditor``s.
private struct SearchingApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: Note(text: "")) { file in
            SearchingEditor(file: file, probe: OpeningProbe.current, defaultsToTable: false)
        }
    }
}

/// A `DocumentGroup` of ``SearchingEditor``s whose `.defaultFocus` is the
/// table.
private struct DefaultingApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: Note(text: "")) { file in
            SearchingEditor(file: file, probe: OpeningProbe.current, defaultsToTable: true)
        }
    }
}

@MainActor
@Suite("Where the focus starts in a document opened after launch", .serialized)
struct DocumentOpeningFocusTests {
    /// The app with its first, untitled document drawn.
    private func launched(_ probe: OpeningProbe, defaultsToTable: Bool = false) async throws -> TestApp {
        OpeningProbe.current = probe
        let app =
            defaultsToTable
            ? TestApp(DefaultingApp(), width: 60, height: 16) : TestApp(SearchingApp(), width: 60, height: 16)
        app.advance(by: .zero)
        try await app.wait(for: "file=none", timeout: .seconds(30))
        return app
    }

    /// Opens `probe.url` with F5 and waits until it is drawn.
    private func open(_ name: String, in app: TestApp) async throws {
        app.press(.f5)
        try await app.wait(for: "file=\(name)", timeout: .seconds(30))
        app.advance(by: .zero)
    }

    /// The new document's content chooses where the focus starts as a
    /// window's first content does (`SearchPresentationTests`): the old
    /// document's control held the focus as the manager chose it, and its
    /// replacement must not hand it to the first control of the new one, the
    /// search field drawn above the content.
    @Test("A document opened while the old one's content had the focus starts in the content")
    func openedDocumentStartsInTheContent() async throws {
        let folder = try DocumentFolder()
        let probe = OpeningProbe()
        probe.url = try folder.write("hello", "a.txt")
        let app = try await launched(probe)
        try await open("a.txt", in: app)
        #expect(app.focusedID?.hasPrefix("searchfield-") != true, "\(app.focusedID ?? "nil")")
        app.type("x")
        #expect(probe.query.isEmpty, "typed into the search field: \(probe.query)")
    }

    /// Keys pressed in the old document's source pane put the focus there by
    /// the user's choice; the new document is new content all the same, and its
    /// `.defaultFocus` names where it starts, as a newly opened window's does.
    @Test("A document opened while the old one's source pane had the focus starts on its defaultFocus")
    func openedDocumentHonoursDefaultFocus() async throws {
        let folder = try DocumentFolder()
        let probe = OpeningProbe()
        probe.url = try folder.write("hello", "a.txt")
        let app = try await launched(probe, defaultsToTable: true)
        // The table first, as the default; then into the source, moving its caret: an edit would ask to save first.
        app.press(.space)
        #expect(probe.pressed == 1, "the default focus is on the table at launch")
        app.press(.tab, modifiers: .shift)
        app.press(.right)
        #expect(app.focusedID?.hasPrefix("focused-") == true, "the source pane has the focus")
        try await open("a.txt", in: app)
        app.press(.space)
        #expect(probe.pressed == 2, "the new document's table has the focus: \(app.focusedID ?? "nil")")
        #expect(probe.query.isEmpty, "typed into the search field: \(probe.query)")
    }
}
