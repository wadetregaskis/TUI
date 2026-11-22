//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelShortcutTests.swift
//
//  Windows shortcuts (`.lnk`) in a file panel: followed as a symbolic link is,
//  opened at their target and chosen as it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

#if os(Windows)
import TUICore
import WinSDK
#endif

@testable import TUIFilePanels

@Suite("File panel shortcuts")
struct FilePanelShortcutTests {
    @Test("A row that is a shortcut opens and is chosen as its target, and expands nowhere")
    func entryFollowsItsTarget() {
        let shortcut = URL(fileURLWithPath: "/folder/Docs.lnk")
        let target = URL(fileURLWithPath: "/elsewhere/Docs", isDirectory: true)
        let entry = FileEntry(
            url: shortcut, name: "Docs.lnk", isFolder: true, isHidden: false, isSymbolicLink: false,
            shortcutTarget: target, contentType: .folder, size: nil, modified: nil, sizeText: "--",
            modifiedText: "", kind: "Shortcut", isChoosable: true)
        #expect(entry.openedURL == target)
        #expect(!entry.expandsInPlace)
        #expect(entry.chosenURL(resolvingLinks: true) == target)
        #expect(entry.chosenURL(resolvingLinks: false) == shortcut)
        let folder = FileEntry(
            url: target, name: "Docs", isFolder: true, isHidden: false, isSymbolicLink: false,
            contentType: .folder, size: nil, modified: nil, sizeText: "--", modifiedText: "", kind: "Folder",
            isChoosable: true)
        #expect(folder.openedURL == target && folder.expandsInPlace)
    }

    #if os(Windows)
        /// Makes a shortcut at `path` to `target`, as Explorer would.
        private static func makeShortcut(at path: String, to target: String) throws {
            let saved = WindowsCOM.withApartment { save(path, target) }
            try #require(saved, "could not make \(path)")
        }

        private static func save(_ path: String, _ target: String) -> Bool {
            var clsid = CLSID_ShellLink
            var iid = IID_IShellLinkW
            var made: UnsafeMutableRawPointer?
            guard unsafe CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &made) == S_OK,
                let made = unsafe made
            else { return false }
            let link = unsafe made.assumingMemoryBound(to: IShellLinkW.self)
            defer { _ = unsafe link.pointee.lpVtbl.pointee.Release(link) }
            let wideTarget = Array(target.utf16) + [0]
            guard unsafe link.pointee.lpVtbl.pointee.SetPath(link, wideTarget) == S_OK else { return false }
            var fileIID = IID_IPersistFile
            var persisted: UnsafeMutableRawPointer?
            guard unsafe link.pointee.lpVtbl.pointee.QueryInterface(link, &fileIID, &persisted) == S_OK,
                let persisted = unsafe persisted
            else { return false }
            let file = unsafe persisted.assumingMemoryBound(to: IPersistFile.self)
            defer { _ = unsafe file.pointee.lpVtbl.pointee.Release(file) }
            let widePath = Array(path.utf16) + [0]
            return unsafe file.pointee.lpVtbl.pointee.Save(file, widePath, true) == S_OK
        }

        @Test("A listed shortcut to a folder is a folder that opens at its target; to a file, the file's type")
        func listedShortcuts() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("tui-lnk-\(UUID().uuidString)")
            let target = root.appendingPathComponent("Target", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let note = target.appendingPathComponent("note.txt")
            try Data("hello".utf8).write(to: note)
            let listed = root.appendingPathComponent("Listed", isDirectory: true)
            try FileManager.default.createDirectory(at: listed, withIntermediateDirectories: true)
            try Self.makeShortcut(at: listed.appendingPathComponent("ToFolder.lnk").path, to: target.path)
            try Self.makeShortcut(at: listed.appendingPathComponent("ToNote.lnk").path, to: note.path)
            try Self.makeShortcut(
                at: listed.appendingPathComponent("ToNothing.lnk").path, to: root.appendingPathComponent("gone").path)

            let rule = FileChoiceRule(allowedContentTypes: [.plainText])
            let entries = try await DirectoryListing.load(listed, rule: rule).get()
            func entry(_ name: String) throws -> FileEntry { try #require(entries.first { $0.name == name }) }

            let toFolder = try entry("ToFolder.lnk")
            #expect(toFolder.isFolder && !toFolder.expandsInPlace)
            #expect(toFolder.openedURL.standardizedFileURL.path == target.standardizedFileURL.path)
            #expect(toFolder.fileKind == .alias)

            let toNote = try entry("ToNote.lnk")
            #expect(!toNote.isFolder)
            #expect(toNote.contentType.conforms(to: .plainText))
            #expect(toNote.isChoosable)
            #expect(toNote.chosenURL(resolvingLinks: true).standardizedFileURL.path == note.standardizedFileURL.path)

            // A shortcut whose target is gone is the file it is.
            let toNothing = try entry("ToNothing.lnk")
            #expect(toNothing.shortcutTarget == nil && !toNothing.isFolder)
        }
    #endif
}
