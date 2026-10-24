//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelOutlineTests.swift
//
//  A file panel's list view as an outline: a folder opens in place, read
//  when it is opened, and its items are chosen like the folder's own.
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

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel outline", .serialized)
struct FilePanelOutlineTests {
    /// A panel over `fixture`'s root, which is also its home.
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller, multiple: Bool = false) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: multiple), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    /// The screen's line holding `text`.
    private func line(_ text: String, in screen: String) -> Substring? {
        screen.split(separator: "\n").first { $0.contains(text) }
    }

    @Test("→ opens a folder in place, read as it opens; its file is chosen with Return")
    func branchOpensInPlace() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let shown = await driver.waitFor("notes.md")
        // Every folder has a triangle; a file has none.
        #expect(line("Alpha/", in: shown)?.contains("▶") == true, "\(shown)")
        #expect(line("beta.txt", in: shown)?.contains("▶") == false)
        #expect(!shown.contains("inner.txt"))
        // The cursor is on Alpha/: → opens it where it is.
        driver.press(.right)
        let open = await driver.waitFor("inner.txt")
        #expect(line("Alpha/", in: open)?.contains("▼") == true, "\(open)")
        #expect(open.contains("↰ ▐ ~ ▌"), "the folder shown is still the root: \(open)")
        let alpha = try #require(open.range(of: "Alpha/"))
        let inner = try #require(open.range(of: "inner.txt"))
        let linked = try #require(open.range(of: "linked/"))
        #expect(alpha.lowerBound < inner.lowerBound && inner.lowerBound < linked.lowerBound)
        // Down to inner.txt, and Return chooses it, from the branch.
        driver.press(.down)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("← goes from a branch's item to its folder, and closes it")
    func leftClosesTheBranch() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.right)
        await driver.waitFor("inner.txt")
        driver.press(.down)
        driver.press(.left)
        driver.press(.left)
        let closed = driver.screen()
        #expect(!closed.contains("inner.txt"), "\(closed)")
        #expect(caller.heard.isEmpty)
        // Return on Alpha/ opens the folder itself, as it always has.
        driver.press(.enter)
        await driver.waitFor("~ │ Alpha")
    }

    @Test("A selection spans the folder and its open branches")
    func selectionSpansBranches() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, multiple: true) }
        await driver.waitFor("notes.md")
        driver.press(.right)
        await driver.waitFor("inner.txt")
        // inner.txt, then past linked/ to beta.txt.
        driver.press(.down)
        driver.press(.space)
        driver.press(.down, times: 2)
        driver.press(.space)
        driver.press(.enter)
        #expect(
            Set(caller.chosenPaths) == [fixture.url("Alpha/inner.txt").path, fixture.url("beta.txt").path])
    }
}
