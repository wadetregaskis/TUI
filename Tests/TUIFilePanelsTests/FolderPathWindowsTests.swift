//  🖥️ TUI — A Terminal UI framework for Swift
//  FolderPathWindowsTests.swift
//
//  A Windows drive's root as a file panel names it, goes up to it, and writes
//  it in its path bar.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)

import Foundation
import Testing

@testable import TUIFilePanels

@Suite("A Windows drive's folders in a file panel")
struct FolderPathWindowsTests {
    private let home = URL(fileURLWithPath: #"C:\Users\Someone"#, isDirectory: true)

    @Test("A drive's root stays its root, and . and .. stay on its drive")
    func standardized() {
        #expect(URL(fileURLWithPath: #"C:\"#).panelStandardized.path == "C:/")
        #expect(URL(fileURLWithPath: #"C:\Users\Someone\.."#).panelStandardized.path == "C:/Users")
        #expect(URL(fileURLWithPath: #"C:\Users\.\Someone"#).panelStandardized.path == "C:/Users/Someone")
        #expect(URL(fileURLWithPath: #"C:\Users\..\.."#).panelStandardized.path == "C:/")
    }

    @Test("Going up stops at the drive's root")
    func parent() {
        #expect(FolderPath.parent(of: URL(fileURLWithPath: #"C:\Users"#))?.path == "C:/")
        #expect(FolderPath.parent(of: URL(fileURLWithPath: #"C:\"#)) == nil)
        #expect(FolderPath.parent(of: URL(fileURLWithPath: #"C:\Users\Someone"#))?.path == "C:/Users")
    }

    @Test("The path bar starts at the drive, and each segment goes to its folder")
    func pathBar() {
        let segments = FilePanelPathSegment.all(of: URL(fileURLWithPath: #"D:\Projects\TUI"#), home: home)
        #expect(segments.map(\.label) == ["D:", "Projects", "TUI"])
        #expect(segments.map(\.path) == ["D:/", "D:/Projects", "D:/Projects/TUI"])
        let root = FilePanelPathSegment.all(of: URL(fileURLWithPath: #"D:\"#), home: home)
        #expect(root.map(\.label) == ["D:"])
        let inHome = FilePanelPathSegment.all(of: URL(fileURLWithPath: #"C:\Users\Someone\Documents"#), home: home)
        #expect(inHome.map(\.label) == ["~", "Documents"])
    }

    @Test("A drive typed alone is its root")
    func bareDrive() {
        #expect(PathCompletion.resolve("D:", relativeTo: home, home: home).path == "D:/")
        #expect(PathCompletion.resolve(#"D:\Projects"#, relativeTo: home, home: home).path == "D:/Projects")
    }

    @Test("A browser at a drive's root is at a root, and goes no higher")
    @MainActor
    func browserAtRoot() throws {
        let browser = FileBrowser(directory: URL(fileURLWithPath: #"C:\"#), rule: FileChoiceRule())
        #expect(browser.directory.path == "C:/")
        #expect(browser.isAtRoot)
        browser.goUp()
        #expect(browser.directory.path == "C:/")
    }
}

#endif
