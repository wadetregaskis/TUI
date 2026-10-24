//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PathCompletionTests.swift
//
//  The go-to field: a typed path resolved as a shell resolves one, completed
//  with Tab, and gone to with Return.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@Suite("Path completion")
struct PathCompletionTests {
    @Test("A typed path is the home folder's from ~, absolute from /, else the folder shown's")
    func resolve() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let base = URL(fileURLWithPath: "/tmp/base", isDirectory: true)
        #expect(PathCompletion.resolve("~", relativeTo: base, home: home).path == "/Users/someone")
        #expect(PathCompletion.resolve("~/Documents", relativeTo: base, home: home).path == "/Users/someone/Documents")
        #expect(PathCompletion.resolve("/etc", relativeTo: base, home: home).path == "/etc")
        #expect(PathCompletion.resolve("sub/dir", relativeTo: base, home: home).path == "/tmp/base/sub/dir")
        #expect(PathCompletion.resolve("../up", relativeTo: base, home: home).path == "/tmp/up")
        #expect(PathCompletion.resolve("~other", relativeTo: base, home: home).path == "/tmp/base/~other")
    }

    @Test("Tab completes the one match, with a slash after a folder")
    func completesOne() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let root = fixture.root
        #expect(PathCompletion.complete("Al", relativeTo: root, home: root) == "Alpha/")
        #expect(PathCompletion.complete("Alpha/in", relativeTo: root, home: root) == "Alpha/inner.txt")
        #expect(PathCompletion.complete("~/g", relativeTo: root, home: root) == "~/gamma.pdf")
        #expect(PathCompletion.complete(root.path + "/no", relativeTo: root, home: root) == root.path + "/notes.md")
    }

    @Test("Tab completes as far as several matches share, and leaves the rest")
    func completesShared() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.url("notebook.txt"))
        let root = fixture.root
        #expect(PathCompletion.complete("n", relativeTo: root, home: root) == "note")
        #expect(PathCompletion.complete("note", relativeTo: root, home: root) == "note")
        #expect(PathCompletion.complete("zz", relativeTo: root, home: root) == "zz")
    }

    @Test("Hidden items complete only from a dot; case matters only while it matches")
    func hiddenAndCase() throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let root = fixture.root
        #expect(PathCompletion.complete(".h", relativeTo: root, home: root) == ".hidden")
        #expect(PathCompletion.complete("al", relativeTo: root, home: root) == "Alpha/")
    }
}

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("Go-to field", .serialized)
struct GoToFieldTests {
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    /// The go-to field's text: the line that says "Go to:", from its field's
    /// text to its last letter (the panel's edges and the field's caps
    /// dropped, in whichever control style).
    private func goToLine(_ screen: String) -> String? {
        guard let line = screen.split(separator: "\n").first(where: { $0.contains("Go to:") }) else { return nil }
        return String(line.map { "│▐▌".contains($0) ? " " : $0 }).trimmingCharacters(in: .whitespaces)
    }

    @Test("/ opens the field on the folder shown; Tab completes and Return goes there")
    func typeAndGo() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.character("/"))
        #expect(goToLine(driver.screen())?.hasSuffix("~/") == true)
        driver.press([KeyEvent(key: .character("A")), KeyEvent(key: .tab)])
        #expect(goToLine(driver.screen())?.hasSuffix("~/Alpha/") == true)
        driver.press(.enter)
        let inside = await driver.waitFor("inner.txt")
        #expect(!inside.contains("Go to:"), "the field closes")
        // The folder has the focus again: Return chooses the file under the cursor.
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("Escape closes the field and leaves the panel up")
    func escapeCloses() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.character("/"))
        driver.press(.escape)
        let shown = driver.screen()
        #expect(!shown.contains("Go to:") && shown.contains("notes.md"))
        #expect(caller.heard.isEmpty)
    }

    @Test("A path to nothing leaves the field open")
    func nowhere() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.character("/"))
        driver.press([KeyEvent(key: .character("z")), KeyEvent(key: .enter)])
        #expect(goToLine(driver.screen())?.hasSuffix("~/z") == true)
    }
}
