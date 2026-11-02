//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIDocuments

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

struct Note: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

let group = DocumentGroup(viewing: Note.self) { _ in Text("Note") }

print("UsesTUIDocuments: \(String(reflecting: type(of: group)))")
