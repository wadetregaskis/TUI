//  🖥️ TUI — A Terminal UI framework for Swift
//  DirectoryListingWindowsTests.swift
//
//  A folder read on Windows from its own enumeration: an item another program
//  holds open, one with the hidden attribute, and a junction, each as its row
//  should be.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import Testing
import WinSDK

@testable import TUIFilePanels

@Suite("Directory listing on Windows")
struct DirectoryListingWindowsTests {
    /// A folder of its own, removed after.
    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui-listing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func listed(_ folder: URL) throws -> [String: FileEntry] {
        let entries = try DirectoryListing.read(folder, rule: FileChoiceRule()).get()
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    @Test("A file another program holds open, sharing nothing, still has its size and time")
    func heldOpen() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("held.bin")
        try Data(repeating: 7, count: 1234).write(to: file)
        let handle = file.withUnsafeFileSystemRepresentation { path in
            String(cString: path!).withCString(encodedAs: UTF16.self) {
                CreateFileW($0, GENERIC_READ, 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
            }
        }
        #expect(handle != INVALID_HANDLE_VALUE)
        defer { _ = CloseHandle(handle) }
        let row = try #require(try Self.listed(folder)["held.bin"])
        #expect(row.size == 1234)
        #expect(row.modified != nil)
        #expect(!row.isHidden)
        #expect(!row.isFolder)
    }

    @Test("The hidden attribute hides an item, whatever its name")
    func hiddenAttribute() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("secret.txt")
        try Data("x".utf8).write(to: file)
        let set = file.withUnsafeFileSystemRepresentation { path in
            String(cString: path!).withCString(encodedAs: UTF16.self) {
                SetFileAttributesW($0, DWORD(FILE_ATTRIBUTE_HIDDEN))
            }
        }
        #expect(set)
        #expect(try Self.listed(folder)["secret.txt"]?.isHidden == true)
    }

    @Test("A junction is a link, and opens as the folder it leads to")
    func junction() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Target"), withIntermediateDirectories: false)
        let made = Process()
        made.executableURL = URL(fileURLWithPath: #"C:\Windows\System32\cmd.exe"#)
        made.arguments = ["/d", "/c", "mklink", "/J", "Junction", "Target"]
        made.currentDirectoryURL = folder
        made.standardOutput = FileHandle.nullDevice
        try made.run()
        made.waitUntilExit()
        #expect(made.terminationStatus == 0)
        let rows = try Self.listed(folder)
        #expect(rows["Junction"]?.isSymbolicLink == true)
        #expect(rows["Junction"]?.isFolder == true)
        #expect(rows["Target"]?.isSymbolicLink == false)
    }
}

#endif
