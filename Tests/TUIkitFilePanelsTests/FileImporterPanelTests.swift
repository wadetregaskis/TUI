//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileImporterPanelTests.swift
//
//  The open panel, driven through the whole input chain: the keys a user
//  presses, and what the caller hears, in SwiftUI's order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Serialized: each test draws frames until a folder read on another thread
/// shows, and nine of them drawing at once on the main actor took 40 s where
/// each alone takes a fifth of one.
@MainActor
@Suite("File importer panel", .serialized)
struct FileImporterPanelTests {
    /// A panel presented over a page, opening on `fixture`'s root, which is
    /// also its home.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, types: [UTType] = [], multiple: Bool = false
    ) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: multiple),
                    rule: FileChoiceRule(allowedContentTypes: types), title: "Open", confirmationLabel: "Open",
                    startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    @Test("The panel lists the folder: folders first, with a slash, hidden files left out")
    func listsTheFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let shown = await driver.waitFor("notes.md")
        let alpha = try #require(shown.range(of: "Alpha/"))
        let beta = try #require(shown.range(of: "beta.txt"))
        #expect(alpha.lowerBound < beta.lowerBound)
        #expect(shown.contains("linked/"))
        #expect(!shown.contains(".hidden"))
        #expect(shown.contains("~"), "the path bar writes the home folder as ~: \(shown)")
    }

    @Test("Return on a file chooses it, after the binding is cleared")
    func returnChoosesFile() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        // Rows: Alpha/, linked/, beta.txt, …: the cursor starts on the first.
        driver.press(.down, times: 2)
        driver.press(.enter)
        #expect(caller.heard == ["chose (presented: false)"])
        #expect(caller.chosenPaths == [fixture.url("beta.txt").path])
    }

    @Test("Return on a folder opens it; ← goes back up")
    func returnOpensFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        let inside = await driver.waitFor("inner.txt")
        #expect(inside.contains("~/Alpha"))
        #expect(!inside.contains("beta.txt"))
        #expect(caller.heard.isEmpty)
        driver.press(.left)
        let back = await driver.waitFor("beta.txt")
        #expect(!back.contains("inner.txt"))
        // The cursor starts at the top of the folder: Return opens Alpha again.
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("Escape cancels: the binding is cleared and only the cancellation is heard")
    func escapeCancels() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.escape, times: 2)
        #expect(!caller.isPresented)
        #expect(caller.heard == ["cancelled (presented: false)"])
        #expect(!driver.screen().contains("notes.md"))
    }

    @Test("Escape cancels the panel, not a page's own Escape item outside it")
    func escapeBeatsPageItem() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        var pageWentBack = false
        // The Example's pages carry "⎋ back" outside everything they present.
        let driver = FilePanelDriver {
            panel(fixture, caller: caller)
                .statusBarItems {
                    StatusBarItem(shortcut: Shortcut.escape, label: "back") { pageWentBack = true }
                }
        }
        await driver.waitFor("notes.md")
        driver.press(.escape)
        #expect(!pageWentBack)
        #expect(caller.heard == ["cancelled (presented: false)"])
    }

    @Test("A file of a type not allowed cannot be chosen or selected; one of an allowed type is chosen")
    func typesFilterChoices() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, types: [.pdf], multiple: true) }
        await driver.waitFor("notes.md")
        // Alpha/, linked/, then beta.txt: dimmed, but the cursor lands on it.
        // Space does not select it, and Return chooses nothing.
        driver.press(.down, times: 2)
        driver.press(.space)
        driver.press(.enter)
        #expect(caller.heard.isEmpty)
        // gamma.pdf is chosen.
        driver.press(.down)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("gamma.pdf").path])
    }

    @Test("Several files are chosen by selecting each with Space")
    func multipleSelection() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, multiple: true) }
        await driver.waitFor("notes.md")
        driver.press(.down, times: 2)
        driver.press(.space)
        driver.press(.down)
        driver.press(.space)
        driver.press(.enter)
        #expect(Set(caller.chosenPaths) == [fixture.url("beta.txt").path, fixture.url("gamma.pdf").path])
    }

    @Test("A folder type lets the folder shown be chosen with the confirmation button")
    func chooseFolderShown() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, types: [.folder]) }
        await driver.waitFor("notes.md")
        // Tab past the table and the hidden-files switch to Cancel and Open.
        driver.press(.tab, times: 3)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.root.path])
    }

    @Test("A link chosen is the item it leads to")
    func linkResolves() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, types: [.folder]) }
        await driver.waitFor("notes.md")
        // Alpha/, then linked/: select it, then Open (past the switch and Cancel).
        driver.press(.down)
        driver.press(.space)
        driver.press(.tab, times: 3)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha").path])
    }

    @Test("Typing a name's first letters finds it, by the name alone")
    func typeSelect() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        // "g" lands on gamma.pdf, past the folders; Return chooses it.
        driver.press(.character("g"))
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("gamma.pdf").path])
    }

    @Test("The hidden-files switch lists the hidden items, and takes them away again")
    func hiddenSwitch() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        // Tab to the switch, Space to turn it on.
        driver.press(.tab)
        driver.press(.space)
        let shown = await driver.waitFor(".hidden")
        #expect(shown.contains(".hidden"))
        driver.press(.space)
        await settle { !driver.screen().contains(".hidden") }
        #expect(!driver.screen().contains(".hidden"))
    }

    @Test("A panel presented again is a new panel, even from a list row, which keeps its rows' state")
    func presentedAgainFromListRow() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        // A `List` keeps the state of everything in its rows, the sheet's
        // content included: a panel whose folder was its own `@State` came
        // back in the folder it was cancelled in.
        let driver = FilePanelDriver {
            List {
                panel(fixture, caller: caller)
            }
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.escape)
        #expect(caller.heard == ["cancelled (presented: false)"])
        driver.screen()
        caller.isPresented = true
        let shown = await driver.waitFor("notes.md", timeout: .seconds(10))
        #expect(!shown.contains("inner.txt"), "\(shown)")
    }

    @Test("A panel presented again from a list row takes the types its modifier names now")
    func presentedAgainReadsNewTypes() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        var types: [UTType] = [.pdf]
        let driver = FilePanelDriver {
            List {
                panel(fixture, caller: caller, types: types)
            }
        }
        await driver.waitFor("notes.md")
        driver.press(.escape)
        driver.screen()
        // Plain text now: beta.txt, the third row, is chosen.
        types = [.plainText]
        caller.isPresented = true
        await driver.waitFor("notes.md")
        driver.press(.down, times: 2)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("beta.txt").path])
    }

    @Test("~ goes to the home folder")
    func tildeGoesHome() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.character("~"))
        let home = await driver.waitFor("beta.txt")
        #expect(!home.contains("inner.txt"))
    }
}
