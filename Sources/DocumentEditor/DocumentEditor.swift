//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentEditor.swift
//
//  A small text editor, written as a SwiftUI document app is: one
//  `DocumentGroup`, whose File menu opens and saves. A scene of its own, so an
//  executable of its own, not a page of the Example app. Its only words are the
//  framework's, which are translated.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// A plain-text document, as Apple's documentation writes one.
struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text = ""

    init(text: String = "") {
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

@main
struct DocumentEditor: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextFile()) { file in
            TextEditor(text: file.$document.text)
        }
    }
}
