//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelPathControlTests.swift
//
//  A file panel's path control: a segment per folder on the way to the one
//  shown, which a click or the keys go to, and what it keeps when narrow.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel path control", .serialized)
struct FilePanelPathControlTests {
    private typealias Segment = FilePanelPathSegment

    private static let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func labels(_ segments: [Segment]) -> [String] { segments.map(\.label) }

    @Test("A folder in the home folder is a path from ~, one outside it from /")
    func segmentsFromHomeOrRoot() {
        let inHome = Segment.all(of: URL(fileURLWithPath: "/Users/someone/Documents/Notes"), home: Self.home)
        #expect(labels(inHome) == ["~", "Documents", "Notes"])
        #expect(inHome.map(\.path) == ["/Users/someone", "/Users/someone/Documents", "/Users/someone/Documents/Notes"])
        #expect(labels(Segment.all(of: Self.home, home: Self.home)) == ["~"])
        let outside = Segment.all(of: URL(fileURLWithPath: "/usr/local/bin"), home: Self.home)
        #expect(labels(outside) == ["/", "usr", "local", "bin"])
        #expect(outside.map(\.path) == ["/", "/usr", "/usr/local", "/usr/local/bin"])
        #expect(labels(Segment.all(of: URL(fileURLWithPath: "/"), home: Self.home)) == ["/"])
        // A folder whose name only begins with the home folder's is outside it.
        #expect(labels(Segment.all(of: URL(fileURLWithPath: "/Users/someoneelse"), home: Self.home)).first == "/")
    }

    @Test("The control's width is the segmented picker's: caps, padded labels, a rule between")
    func widthIsThePickers() {
        let segments = [Segment(label: "~", path: "/a"), Segment(label: "Docs", path: "/a/Docs")]
        // ▐ ~ │ Docs ▌
        #expect(Segment.width(of: segments, controlSize: .regular) == 12)
        // ▐~│Docs▌
        #expect(Segment.width(of: segments, controlSize: .small) == 8)
        // ~│Docs
        #expect(Segment.width(of: segments, controlSize: .mini) == 6)
    }

    @Test("Narrow, the path keeps its first and last segments, with … for the ones between")
    func narrowPathCollapses() {
        let all = Segment.all(
            of: URL(fileURLWithPath: "/Users/someone/Projects/TUI/Sources/TUIFilePanels"), home: Self.home)
        let full = Segment.width(of: all, controlSize: .regular)
        #expect(Segment.fitting(all, width: full, controlSize: .regular) == all)
        // One cell short: the first folder after ~ gives way, and … goes to it.
        let shorter = Segment.fitting(all, width: full - 1, controlSize: .regular)
        #expect(labels(shorter) == ["~", "…", "TUI", "Sources", "TUIFilePanels"])
        #expect(shorter[1].path == "/Users/someone/Projects")
        // Room for the first, the … and the last alone: … goes to Sources.
        let tight = Segment.fitting(all, width: 30, controlSize: .regular)
        #expect(labels(tight) == ["~", "…", "TUIFilePanels"])
        #expect(tight[1].path == "/Users/someone/Projects/TUI/Sources")
        // Narrower: the … and the last; then the last's name shortened.
        #expect(labels(Segment.fitting(all, width: 24, controlSize: .regular)) == ["…", "TUIFilePanels"])
        let shortened = Segment.fitting(all, width: 16, controlSize: .regular)
        #expect(labels(shortened)[0] == "…")
        #expect(Segment.width(of: shortened, controlSize: .regular) <= 16)
        #expect(shortened[1].path == all.last?.path)
    }

    @Test("Narrow, a path of two segments shortens the last rather than hide the first")
    func twoSegmentsKeepTheFirst() {
        let all = Segment.all(of: URL(fileURLWithPath: "/Users/someone/A-rather-long-folder-name"), home: Self.home)
        let fitted = Segment.fitting(all, width: 20, controlSize: .regular)
        #expect(labels(fitted).first == "~")
        #expect(Segment.width(of: fitted, controlSize: .regular) <= 20)
    }

    /// A panel opening on `fixture`'s Alpha folder, its home `fixture`'s root.
    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.url("Alpha"), homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    @Test("A click on a segment goes to its folder")
    func clickGoesThere() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let shown = await driver.waitFor("inner.txt")
        #expect(shown.contains("~ │ Alpha"), "\(shown)")
        #expect(driver.click("~"))
        await driver.waitFor("beta.txt")
        #expect(caller.heard.isEmpty)
    }

    @Test("The control is a Tab stop; ← and Space go to the folder before")
    func keysGoThere() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        await driver.waitFor("inner.txt")
        // Back from the folder's rows past the view switcher to the control,
        // whose cursor starts on the folder shown: ← to ~, Space to go there.
        driver.press(Array(repeating: KeyEvent(key: .tab, shift: true), count: 2))
        driver.press(.left)
        driver.press(.space)
        let home = await driver.waitFor("beta.txt")
        #expect(!home.contains("inner.txt"))
        #expect(caller.heard.isEmpty)
    }
}
