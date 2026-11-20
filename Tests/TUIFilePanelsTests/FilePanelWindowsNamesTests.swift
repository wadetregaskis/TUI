//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelWindowsNamesTests.swift
//
//  What a file panel refuses, and where it goes, by Windows's rules there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFilePanels
@testable import TUIFoundation

@MainActor
@Suite("File panel names and places on Windows")
struct FilePanelWindowsNamesTests {
    #if os(Windows)
        @Test("A save name Windows would read as a stream, a folder or a device is refused")
        func saveNames() {
            for typed in ["notes:old", #"a\b"#, "notes.", "CON", "nul.txt"] {
                #expect(SaveName.resolve(typed, contentTypes: [.plainText]) == nil, "\(typed)")
            }
            #expect(SaveName.resolve("notes", contentTypes: [.plainText]) == "notes.txt")
        }

        @Test("A new folder's name Windows refuses is refused before anything is made")
        func newFolderNames() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            #expect(throws: CocoaError.self) { try FilePanelNewFolderPrompt<EmptyView>.makeFolder(named: "a:b", in: folder) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }

        @Test("Applications goes to Program Files, which every Windows has")
        func applications() {
            let home = FileManager.default.homeDirectoryForCurrentUser
            #expect(FilePanelCommand.applications.place(home: home) != nil)
        }
    #else
        @Test("Elsewhere a colon is a file's name, as the Finder allows it")
        func colonElsewhere() {
            #expect(SaveName.resolve("notes:old", contentTypes: [.plainText]) == "notes:old.txt")
        }
    #endif
}
