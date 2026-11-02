//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentFixtures.swift
//
//  The documents, editors and apps the `DocumentGroup` tests drive.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIDocuments
@testable import TUIFilePanels
@testable import TUIFoundation
import TUITesting
import TUIView

#if canImport(Combine)
    import Combine
#endif

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What the apps' views reach, from an `App`, which has nothing to hold it.
final class DocumentProbe: @unchecked Sendable {
    static let shared = DocumentProbe()

    /// What the page's Load button opens.
    var url: URL?
    /// What opening it threw.
    var thrown: (any Error)?
    /// Whether the last `fileWrapper(configuration:)` was told of an existing file.
    var hadExistingFile: Bool?
    /// How many documents `newDocument` has made.
    var made = 0

    func reset() {
        url = nil
        thrown = nil
        hadExistingFile = nil
        made = 0
    }
}

/// A plain-text document, which throws reading the word "corrupt".
struct Note: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text = "new"

    init(text: String = "new") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(bytes: data, encoding: .utf8) ?? ""
        if text == "corrupt" { throw CocoaError(.fileReadCorruptFile) }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        DocumentProbe.shared.hadExistingFile = configuration.existingFile != nil
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The same as an `@Observable` object.
@Observable
final class Sketch: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text = "new"

    /// What the snapshot does not read, so a change to it is no edit.
    var scrollPosition = 0

    init() {}

    init(configuration: ReadConfiguration) throws {
        text = String(bytes: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}

#if canImport(Combine)
    /// The same as SwiftUI's documentation writes one, with `@Published`.
    final class PublishedSketch: ReferenceFileDocument, @unchecked Sendable {
        static var readableContentTypes: [UTType] { [.plainText] }

        @Published var text = "new"

        init() {}

        init(configuration: ReadConfiguration) throws {
            text = String(bytes: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
        }

        func snapshot(contentType: UTType) throws -> String { text }

        func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        }
    }
#endif

/// What a test sees of a value document, and what it does to one.
struct NotePage: View {
    let file: FileDocumentConfiguration<Note>

    @Environment(\.openDocument) private var openDocument
    @Environment(\.newDocument) private var newDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.documentConfiguration) private var configuration

    var body: some View {
        VStack {
            Text(verbatim: "text=\(file.document.text)")
            Text(verbatim: "file=\(file.fileURL?.lastPathComponent ?? "none") editable=\(file.isEditable)")
            Text(verbatim: "env=\(configuration?.fileURL?.lastPathComponent ?? "none") \(configuration?.isEditable == true)")
            Button("change") { file.document.text += "!" }
            Button("load") {
                Task {
                    do {
                        if let url = DocumentProbe.shared.url { try await openDocument(at: url) }
                    } catch {
                        DocumentProbe.shared.thrown = error
                    }
                }
            }
            Button("preset") { newDocument(Note(text: "preset")) }
            Button("leave") { dismiss() }
        }
    }
}

/// What a test sees of a reference document, and what it does to one.
struct SketchPage: View {
    let file: ReferenceFileDocumentConfiguration<Sketch>

    @Environment(\.openDocument) private var openDocument

    var body: some View {
        VStack {
            Text(verbatim: "text=\(file.document.text)")
            Text(verbatim: "file=\(file.fileURL?.lastPathComponent ?? "none") editable=\(file.isEditable)")
            Button("change") { file.document.text += "!" }
            Button("load") {
                Task {
                    if let url = DocumentProbe.shared.url { try? await openDocument(at: url) }
                }
            }
            Button("bound") { file.$document.text.wrappedValue += "?" }
            Button("scroll") { file.document.scrollPosition += 1 }
        }
    }
}

/// A value-document editor.
struct NotesApp: App {
    init() {}
    var body: some Scene {
        DocumentGroup(
            newDocument: {
                DocumentProbe.shared.made += 1
                return Note()
            }()
        ) { file in
            NotePage(file: file)
        }
    }
}

/// What a document app usually is: a text editor, and nothing else.
struct TextEditApp: App {
    init() {}
    var body: some Scene {
        DocumentGroup(newDocument: Note(text: "")) { file in
            TextEditor(text: file.$document.text)
        }
    }
}

/// A value-document viewer.
struct NoteViewerApp: App {
    init() {}
    var body: some Scene {
        DocumentGroup(viewing: Note.self) { file in
            NotePage(file: file)
        }
    }
}

/// A reference-document editor.
struct SketchesApp: App {
    init() {}
    var body: some Scene {
        DocumentGroup(newDocument: { Sketch() }, editor: { file in SketchPage(file: file) })
    }
}

#if canImport(Combine)
    /// A `@Published` document's editor.
    struct PublishedSketchesApp: App {
        init() {}
        var body: some Scene {
            DocumentGroup(
                newDocument: { PublishedSketch() },
                editor: { file in
                    VStack {
                        Text(verbatim: "text=\(file.document.text)")
                        Button("change") { file.document.text += "!" }
                    }
                })
        }
    }
#endif

/// A folder of files for a test, removed when it is done.
final class DocumentFolder {
    let root: URL

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TUIDocuments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Resolved, as the panel standardizes the paths it shows.
        root = base.resolvingSymlinksInPath()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    @discardableResult
    func write(_ text: String, _ name: String) throws -> URL {
        try Data(text.utf8).write(to: url(name))
        return url(name)
    }

    func read(_ name: String) -> String? {
        (try? Data(contentsOf: url(name))).flatMap { String(bytes: $0, encoding: .utf8) }
    }
}

extension TestApp {
    /// The terminal window's title, where a document's name and Edited go: a
    /// title alone makes no top bar.
    var title: String { headless.terminalWindowTitle ?? "" }

    /// Whether the title says the document has unsaved changes.
    var saysEdited: Bool { title.contains("Edited") }

    /// Draws frames until the title says the document has unsaved changes, or
    /// records that it never did.
    func seeEdited(sourceLocation: SourceLocation = #_sourceLocation) async {
        do {
            try await wait(until: { self.saysEdited }, timeout: .seconds(30))
        } catch {
            Issue.record("\(error)\n\(self.title)", sourceLocation: sourceLocation)
        }
    }

    /// The screen, as one string.
    var text: String { screen.lines.joined(separator: "\n") }

    /// Draws frames until the screen shows `text`, or records that it never did.
    func see(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        do {
            try await wait(for: text, timeout: .seconds(30))
        } catch {
            Issue.record("\(error)\n\(self.text)", sourceLocation: sourceLocation)
        }
    }

    /// Clicks `text` where it shows, or records that it does not.
    func tap(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let point = screen.location(of: text) else {
            Issue.record("no \(text) on\n\(self.text)", sourceLocation: sourceLocation)
            return
        }
        click(at: point)
    }

    /// ⌃S, and the other commands' chords: ⌘ answers to Control here.
    func command(_ character: Character, shift: Bool = false) {
        let typed = shift ? Character(character.uppercased()) : character
        press(.character(typed), modifiers: shift ? [.control, .shift] : .control)
    }
}
