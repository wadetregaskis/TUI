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

    /// `file`'s path as Windows writes it.
    private static func nativePath(of file: URL) -> String {
        file.path.replacingOccurrences(of: "/", with: "\\")
    }

    /// Opens the file at `path` for reading, sharing it with no one, as the
    /// system holds `pagefile.sys`: its handle's bits.
    private static func openSharingNothing(_ path: UnsafePointer<UInt16>) -> UInt {
        unsafe UInt(
            bitPattern: CreateFileW(path, GENERIC_READ, 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil))
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
        let bits = unsafe Self.nativePath(of: file).withCString(encodedAs: UTF16.self, Self.openSharingNothing)
        // `INVALID_HANDLE_VALUE`, as its bits.
        #expect(bits != UInt.max)
        defer { _ = unsafe CloseHandle(HANDLE(bitPattern: bits)) }
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
        var file = folder.appendingPathComponent("secret.txt")
        try Data("x".utf8).write(to: file)
        // The attribute, set as Foundation sets it on Windows.
        var values = URLResourceValues()
        values.isHidden = true
        try file.setResourceValues(values)
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
