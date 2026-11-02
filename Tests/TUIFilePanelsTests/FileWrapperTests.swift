//  🖥️ TUI — A Terminal UI framework for Swift
//  FileWrapperTests.swift
//
//  `FileWrapper`, by what its callers see. On Apple platforms these run against
//  Foundation's, which keeps their expectations honest; on Linux against TUI's
//  (FileWrapper+Portable.swift). So they name nothing but the type's public
//  API, and never ask a wrapper of one kind for another's contents, which
//  raises an exception in Foundation's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFilePanels

@Suite("FileWrapper")
struct FileWrapperTests {
    /// A folder of the test's own, removed when it is done.
    private final class Folder {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileWrapperTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func url(_ path: String) -> URL { root.appendingPathComponent(path) }

        func write(_ text: String, _ path: String) throws {
            try Data(text.utf8).write(to: url(path))
        }

        func read(_ path: String) throws -> String {
            String(bytes: try Data(contentsOf: url(path)), encoding: .utf8) ?? ""
        }

        func list(_ path: String) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: url(path).path).sorted()
        }
    }

    private func text(_ wrapper: FileWrapper?) -> String? {
        wrapper?.regularFileContents.flatMap { String(bytes: $0, encoding: .utf8) }
    }

    // MARK: - Regular files

    @Test("A regular file holds what it was made with, and has no name until it is given one")
    func regular() {
        let wrapper = FileWrapper(regularFileWithContents: Data("hi".utf8))
        #expect(wrapper.isRegularFile)
        #expect(!wrapper.isDirectory)
        #expect(!wrapper.isSymbolicLink)
        #expect(text(wrapper) == "hi")
        #expect(wrapper.filename == nil)
        #expect(wrapper.preferredFilename == nil)
        wrapper.preferredFilename = "a.txt"
        wrapper.filename = "b.txt"
        #expect(wrapper.preferredFilename == "a.txt")
        #expect(wrapper.filename == "b.txt")
    }

    @Test("Writing a regular file makes it, replaces one that is there, and fails in a folder that is not")
    func writeRegular() throws {
        let folder = try Folder()
        try FileWrapper(regularFileWithContents: Data("one".utf8))
            .write(to: folder.url("f.txt"), options: [], originalContentsURL: nil)
        #expect(try folder.read("f.txt") == "one")
        try FileWrapper(regularFileWithContents: Data("two".utf8))
            .write(to: folder.url("f.txt"), options: [], originalContentsURL: nil)
        #expect(try folder.read("f.txt") == "two")
        try FileWrapper(regularFileWithContents: Data("three".utf8))
            .write(to: folder.url("f.txt"), options: .atomic, originalContentsURL: nil)
        #expect(try folder.read("f.txt") == "three")
        #expect(try folder.list("") == ["f.txt"], "nothing left beside it")
        #expect(throws: (any Error).self) {
            try FileWrapper(regularFileWithContents: Data())
                .write(to: folder.url("missing/f.txt"), options: [], originalContentsURL: nil)
        }
    }

    @Test("A file is read when it is asked for, unless .immediate read it at once")
    func lazyAndImmediate() throws {
        let folder = try Folder()
        try folder.write("first", "f.txt")
        let later = try FileWrapper(url: folder.url("f.txt"), options: [])
        let now = try FileWrapper(url: folder.url("f.txt"), options: .immediate)
        #expect(later.isRegularFile)
        #expect(later.filename == "f.txt")
        #expect(later.preferredFilename == "f.txt")
        try folder.write("second", "f.txt")
        #expect(text(later) == "second")
        #expect(text(now) == "first")
    }

    @Test("Reading what is not there fails as a missing file")
    func readMissing() throws {
        let folder = try Folder()
        #expect {
            try FileWrapper(url: folder.url("nope"), options: [])
        } throws: { error in
            (error as? CocoaError)?.code == .fileReadNoSuchFile
        }
    }

    @Test("read(from:) reads another file into the wrapper")
    func readAgain() throws {
        let folder = try Folder()
        try folder.write("first", "a.txt")
        try folder.write("something else", "b.txt")
        // Foundation's skips a file whose date says it has not changed.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: folder.url("b.txt").path)
        let wrapper = try FileWrapper(url: folder.url("a.txt"), options: .immediate)
        try wrapper.read(from: folder.url("b.txt"), options: .immediate)
        #expect(text(wrapper) == "something else")
    }

    @Test("A wrapper matches the file it was read from")
    func matches() throws {
        let folder = try Folder()
        try folder.write("first", "a.txt")
        let wrapper = try FileWrapper(url: folder.url("a.txt"), options: .immediate)
        #expect(wrapper.matchesContents(of: folder.url("a.txt")))
        #expect(!wrapper.matchesContents(of: folder.url("nope")))
    }

    // MARK: - Directories

    @Test("A directory keeps its children by key, each child's preferred name its key")
    func directoryOfChildren() {
        let child = FileWrapper(regularFileWithContents: Data("c".utf8))
        let wrapper = FileWrapper(directoryWithFileWrappers: ["k": child])
        #expect(wrapper.isDirectory)
        #expect(!wrapper.isRegularFile)
        #expect(wrapper.fileWrappers?.count == 1)
        #expect(wrapper.fileWrappers?["k"] === child)
        #expect(child.preferredFilename == "k")
        #expect(child.filename == nil)
        #expect(wrapper.keyForChildFileWrapper(child) == "k")
    }

    @Test("Adding a name that is taken makes a key of it, as Foundation's does")
    func addRegularFile() {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        #expect(wrapper.addRegularFile(withContents: Data("a".utf8), preferredFilename: "a.txt") == "a.txt")
        let second = wrapper.addRegularFile(withContents: Data("b".utf8), preferredFilename: "a.txt")
        let third = wrapper.addRegularFile(withContents: Data("c".utf8), preferredFilename: "a.txt")
        #expect(second == "1__#$!@%!#__a.txt")
        #expect(third == "2__#$!@%!#__a.txt")
        #expect(text(wrapper.fileWrappers?[second]) == "b")
        #expect(wrapper.fileWrappers?[second]?.preferredFilename == "a.txt")
    }

    @Test("A child is added under its preferred name, and removed")
    func addAndRemove() {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        let child = FileWrapper(regularFileWithContents: Data("z".utf8))
        child.preferredFilename = "z.txt"
        #expect(wrapper.addFileWrapper(child) == "z.txt")
        #expect(wrapper.keyForChildFileWrapper(child) == "z.txt")
        wrapper.removeFileWrapper(child)
        #expect(wrapper.keyForChildFileWrapper(child) == nil)
        #expect(wrapper.fileWrappers?.isEmpty == true)
    }

    @Test("A directory is written as a tree, and read back as one")
    func writeTree() throws {
        let folder = try Folder()
        let inner = FileWrapper(directoryWithFileWrappers: [:])
        inner.addRegularFile(withContents: Data("deep".utf8), preferredFilename: "deep.txt")
        let wrapper = FileWrapper(directoryWithFileWrappers: ["inner": inner])
        wrapper.addRegularFile(withContents: Data("top".utf8), preferredFilename: "top.txt")
        try wrapper.write(to: folder.url("tree"), options: [], originalContentsURL: nil)
        #expect(try folder.list("tree") == ["inner", "top.txt"])
        #expect(try folder.read("tree/inner/deep.txt") == "deep")

        let read = try FileWrapper(url: folder.url("tree"), options: .immediate)
        #expect(read.isDirectory)
        #expect(read.filename == "tree")
        #expect(read.preferredFilename == "tree")
        #expect(read.fileWrappers?.keys.sorted() == ["inner", "top.txt"])
        #expect(read.fileWrappers?["top.txt"]?.filename == "top.txt")
        #expect(text(read.fileWrappers?["inner"]?.fileWrappers?["deep.txt"]) == "deep")
    }

    @Test("A directory over one that is there fails, unless atomically, which replaces it")
    func directoryOverDirectory() throws {
        let folder = try Folder()
        let old = FileWrapper(directoryWithFileWrappers: [:])
        old.addRegularFile(withContents: Data("old".utf8), preferredFilename: "old.txt")
        try old.write(to: folder.url("tree"), options: [], originalContentsURL: nil)
        let new = FileWrapper(directoryWithFileWrappers: [:])
        new.addRegularFile(withContents: Data("new".utf8), preferredFilename: "new.txt")
        #expect {
            try new.write(to: folder.url("tree"), options: [], originalContentsURL: nil)
        } throws: { error in
            (error as? CocoaError)?.code == .fileWriteFileExists
        }
        // What it left there is not asserted: Foundation's removes the directory.
        try new.write(to: folder.url("tree"), options: .atomic, originalContentsURL: nil)
        #expect(try folder.list("tree") == ["new.txt"])
        #expect(try folder.list("") == ["tree"], "nothing left beside it")
    }

    @Test(".withNameUpdating names the children as written, and not the wrapper")
    func nameUpdating() throws {
        let folder = try Folder()
        let child = FileWrapper(regularFileWithContents: Data())
        let wrapper = FileWrapper(directoryWithFileWrappers: ["n.txt": child])
        try wrapper.write(to: folder.url("tree"), options: .withNameUpdating, originalContentsURL: nil)
        #expect(child.filename == "n.txt")
        #expect(wrapper.filename == nil)
    }

    // MARK: - Symbolic links

    @Test("A symbolic link is read as itself, and written with its destination as it stands")
    func symbolicLinks() throws {
        let folder = try Folder()
        try folder.write("target", "f.txt")
        try FileManager.default.createSymbolicLink(
            at: folder.url("link"), withDestinationURL: folder.url("f.txt"))
        let read = try FileWrapper(url: folder.url("link"), options: [])
        #expect(read.isSymbolicLink)
        #expect(!read.isRegularFile)
        #expect(read.symbolicLinkDestinationURL?.lastPathComponent == "f.txt")

        let relative = FileWrapper(symbolicLinkWithDestinationURL: URL(fileURLWithPath: "../rel/t.txt"))
        try relative.write(to: folder.url("link2"), options: [], originalContentsURL: nil)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: folder.url("link2").path) == "../rel/t.txt")
    }

    // MARK: - Attributes

    @Test("A file's permissions travel with the wrapper")
    func permissions() throws {
        let folder = try Folder()
        try folder.write("first", "a.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.url("a.txt").path)
        let wrapper = try FileWrapper(url: folder.url("a.txt"), options: .immediate)
        #expect(wrapper.fileAttributes[FileAttributeKey.posixPermissions.rawValue] != nil)
        try wrapper.write(to: folder.url("b.txt"), options: [], originalContentsURL: nil)
        let written = try FileManager.default.attributesOfItem(atPath: folder.url("b.txt").path)
        #expect((written[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
