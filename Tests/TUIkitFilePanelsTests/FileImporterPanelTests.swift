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

/// What a presented panel's caller heard.
@MainActor
final class FilePanelCaller {
    var isPresented = true
    /// Each callback, in order, with whether the binding was still true then.
    var heard: [String] = []
    var chosen: [URL] = []

    var binding: Binding<Bool> {
        Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
    }

    func chose(_ urls: [URL]) {
        heard.append("chose (presented: \(isPresented))")
        chosen = urls
    }

    func cancelled() {
        heard.append("cancelled (presented: \(isPresented))")
    }
}

/// Serialized: each test draws frames until a folder read on another thread
/// shows, and nine of them drawing at once on the main actor took 40 s where
/// each alone takes a fifth of one.
@MainActor
@Suite("File importer panel", .serialized)
struct FileImporterPanelTests {
    static let width = 100
    static let height = 30

    /// A panel presented over a page, opening on `fixture`'s root, which is
    /// also its home.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, multiple: Bool = false, types: [UTType] = []
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

    /// The screen a frame draws, overlays (the sheet) composited.
    private func screen(_ harness: InputChainHarness, _ frame: FrameBuffer) -> String {
        frame.compositingOverlays(
            maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette
        ).lines.map(\.stripped).joined(separator: "\n")
    }

    /// Draws frames until the panel shows `text`: the folder is read on
    /// another thread.
    private func waitFor(
        _ text: String, harness: InputChainHarness, _ build: () -> some View
    ) async -> String {
        var last = ""
        await settle {
            last = screen(harness, harness.frame(build()))
            return last.contains(text)
        }
        return last
    }

    /// Presses `keys`, a frame after each.
    private func press(_ keys: [KeyEvent], harness: InputChainHarness, _ build: () -> some View) {
        for key in keys {
            harness.press(key)
            harness.frame(build())
        }
    }

    @Test("The panel lists the folder: folders first, with a slash, hidden files left out")
    func listsTheFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        let shown = await waitFor("notes.md", harness: harness) { panel(fixture, caller: caller) }
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
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        _ = await waitFor("notes.md", harness: harness) { panel(fixture, caller: caller) }
        // Rows: Alpha/, linked/, beta.txt, …: the cursor starts on the first.
        press(
            [KeyEvent(key: .down), KeyEvent(key: .down), KeyEvent(key: .enter)], harness: harness
        ) { panel(fixture, caller: caller) }
        #expect(caller.heard == ["chose (presented: false)"])
        #expect(caller.chosen.map(\.path) == [fixture.url("beta.txt").path])
    }

    @Test("Return on a folder opens it; ← goes back up")
    func returnOpensFolder() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        _ = await waitFor("notes.md", harness: harness) { panel(fixture, caller: caller) }
        press([KeyEvent(key: .enter)], harness: harness) { panel(fixture, caller: caller) }
        let inside = await waitFor("inner.txt", harness: harness) { panel(fixture, caller: caller) }
        #expect(inside.contains("~/Alpha"))
        #expect(!inside.contains("beta.txt"))
        #expect(caller.heard.isEmpty)
        press([KeyEvent(key: .left)], harness: harness) { panel(fixture, caller: caller) }
        let back = await waitFor("beta.txt", harness: harness) { panel(fixture, caller: caller) }
        #expect(!back.contains("inner.txt"))
        // The cursor starts at the top of the folder: Return opens Alpha again.
        press([KeyEvent(key: .enter)], harness: harness) { panel(fixture, caller: caller) }
        _ = await waitFor("inner.txt", harness: harness) { panel(fixture, caller: caller) }
        press([KeyEvent(key: .enter)], harness: harness) { panel(fixture, caller: caller) }
        #expect(caller.chosen.map(\.path) == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("Escape cancels: the binding is cleared and only the cancellation is heard")
    func escapeCancels() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        _ = await waitFor("notes.md", harness: harness) { panel(fixture, caller: caller) }
        press([KeyEvent(key: .escape), KeyEvent(key: .escape)], harness: harness) { panel(fixture, caller: caller) }
        #expect(!caller.isPresented)
        #expect(caller.heard == ["cancelled (presented: false)"])
        #expect(!screen(harness, harness.frame(panel(fixture, caller: caller))).contains("notes.md"))
    }

    @Test("A file of a type not allowed is passed over; one of an allowed type is chosen")
    func typesFilterChoices() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        func build() -> some View { panel(fixture, caller: caller, types: [.pdf]) }
        _ = await waitFor("notes.md", harness: harness) { build() }
        // Alpha/, linked/, then beta.txt — passed over — and gamma.pdf.
        press([KeyEvent(key: .down), KeyEvent(key: .down), KeyEvent(key: .enter)], harness: harness) { build() }
        #expect(caller.chosen.map(\.path) == [fixture.url("gamma.pdf").path])
    }

    @Test("Several files are chosen by selecting each with Space")
    func multipleSelection() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        func build() -> some View { panel(fixture, caller: caller, multiple: true) }
        _ = await waitFor("notes.md", harness: harness) { build() }
        let space = KeyEvent(key: .space)
        press(
            [KeyEvent(key: .down), KeyEvent(key: .down), space, KeyEvent(key: .down), space, KeyEvent(key: .enter)],
            harness: harness
        ) { build() }
        #expect(Set(caller.chosen.map(\.path)) == [fixture.url("beta.txt").path, fixture.url("gamma.pdf").path])
    }

    @Test("A folder type lets the folder shown be chosen with the confirmation button")
    func chooseFolderShown() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        func build() -> some View { panel(fixture, caller: caller, types: [.folder]) }
        _ = await waitFor("notes.md", harness: harness) { build() }
        // Tab past the table and the hidden-files switch to Cancel and Open.
        press(
            [KeyEvent(key: .tab), KeyEvent(key: .tab), KeyEvent(key: .tab), KeyEvent(key: .enter)], harness: harness
        ) { build() }
        #expect(caller.chosen.map(\.path) == [fixture.root.path])
    }

    @Test("A link chosen is the item it leads to")
    func linkResolves() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        func build() -> some View { panel(fixture, caller: caller, types: [.folder]) }
        _ = await waitFor("notes.md", harness: harness) { build() }
        // Alpha/, then linked/: select it, then Open (past the switch and Cancel).
        press(
            [KeyEvent(key: .down), KeyEvent(key: .space), KeyEvent(key: .tab), KeyEvent(key: .tab),
             KeyEvent(key: .tab), KeyEvent(key: .enter)],
            harness: harness
        ) { build() }
        #expect(caller.chosen.map(\.path) == [fixture.url("Alpha").path])
    }

    @Test("~ goes to the home folder")
    func tildeGoesHome() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let harness = InputChainHarness(width: Self.width, height: Self.height)
        let caller = FilePanelCaller()
        _ = await waitFor("notes.md", harness: harness) { panel(fixture, caller: caller) }
        press([KeyEvent(key: .enter)], harness: harness) { panel(fixture, caller: caller) }
        _ = await waitFor("inner.txt", harness: harness) { panel(fixture, caller: caller) }
        press([KeyEvent(key: .character("~"))], harness: harness) { panel(fixture, caller: caller) }
        let home = await waitFor("beta.txt", harness: harness) { panel(fixture, caller: caller) }
        #expect(!home.contains("inner.txt"))
    }
}
