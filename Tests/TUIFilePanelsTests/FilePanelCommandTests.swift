//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelCommandTests.swift
//
//  A file panel's Finder chords, pressed through the whole input chain as
//  their Control stand-ins arrive under the default `commandKey` (the owner,
//  2026-10-28).
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
@Suite("File panel chords", .serialized)
struct FilePanelCommandTests {
    /// A panel opening on `start`, or `fixture`'s root, which is its home; to
    /// save where `saves`; its settings in `store` where one is named, else
    /// the driver's, which keeps the preview closed.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, start: URL? = nil, saves: Bool = false,
        store: MockStorageBackend? = nil
    ) -> some View {
        let presenter = FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: saves ? .save(contentTypes: [.plainText]) : .open(allowsMultipleSelection: false),
                    rule: FileChoiceRule(), title: "Open", confirmationLabel: "Open",
                    startDirectory: start ?? fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
        return Group {
            if let store {
                presenter.defaultAppStorage(store)
            } else {
                presenter
            }
        }
    }

    /// The key event `command`'s chord arrives as under the default
    /// `commandKey`, Control: ⇧⌘P as ⌃ and a capital P, as the kitty
    /// keyboard protocol reports it.
    private func chord(_ command: FilePanelCommand) -> KeyEvent {
        command.shortcuts[0].keyEvent(commandKey: .control)!
    }

    @Test("⇧⌘P closes and opens the preview, and the app's storage keeps it; ⌃P, its Shift lost, does nothing")
    func togglesPreview() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let store = MockStorageBackend()
        let driver = FilePanelDriver { panel(fixture, caller: caller, store: store) }
        await driver.waitFor("notes.md")
        await driver.waitFor("No Selection")
        #expect(chord(.togglePreview) == KeyEvent(key: .character("P"), ctrl: true, shift: true))
        driver.press([KeyEvent(key: .character("p"), ctrl: true)])
        #expect(driver.screen().contains("No Selection"))
        driver.press([chord(.togglePreview)])
        await settle { !driver.screen().contains("No Selection") }
        let key = FilePanelPreviewVisibility.storageKey(for: nil)
        #expect(store.entry(forKey: key, as: String.self).value == "hidden")
        driver.press([chord(.togglePreview)])
        await driver.waitFor("No Selection")
        #expect(store.entry(forKey: key, as: String.self).value == "shown")
        #expect(caller.heard.isEmpty)
    }

    @Test("⇧⌘P works from a save panel's name field, which has no use for it")
    func togglesFromNameField() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let store = MockStorageBackend()
        let driver = FilePanelDriver { panel(fixture, caller: caller, saves: true, store: store) }
        await driver.waitFor("notes.md")
        await driver.waitFor("No Selection")
        driver.press([chord(.togglePreview)])
        await settle { !driver.screen().contains("No Selection") }
        // The field still has the keys: a letter is typed into the name.
        driver.press([KeyEvent(key: .character("x"))])
        await settle {
            driver.screen().split(separator: "\n").contains { $0.contains("Save As:") && $0.contains("▐x ") }
        }
    }

    @Test("⌘3 shows the columns and ⌘2 the list, the keys following into each")
    func switchesViews() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let list = await driver.waitFor("notes.md")
        #expect(list.contains("Date Modified"), "\(list)")
        driver.press([chord(.columnsView)])
        await settle { !driver.screen().contains("Date Modified") }
        #expect(
            driver.storage.entry(forKey: FilePanelViewMode.storageKey(for: nil), as: String.self).value == "columns")
        // The keys are in the column: Return opens Alpha/, its first row.
        driver.press(.enter)
        await driver.waitFor("~ │ Alpha")
        driver.press([chord(.listView)])
        await driver.waitFor("Date Modified")
        // And in the table: Return opens inner.txt's folder's first row.
        await driver.waitFor("inner.txt")
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("Alpha/inner.txt").path])
    }

    @Test("⌘↑ goes to the enclosing folder, ⌘↓ opens the folder selected")
    func upAndDown() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, start: fixture.url("Alpha")) }
        await driver.waitFor("inner.txt")
        driver.press([chord(.enclosingFolder)])
        await driver.waitFor("notes.md")
        #expect(!driver.screen().contains("inner.txt"))
        // Alpha/ selected (Space on the first row), ⌘↓ opens it.
        driver.press(.space)
        driver.press([chord(.openSelection)])
        await settle { !driver.screen().contains("notes.md") }
        #expect(driver.screen().contains("inner.txt"))
        #expect(caller.heard.isEmpty)
    }

    @Test("The Go chords go to home and the folders in it, where they exist")
    func goPlaces() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.url("Desktop"), withIntermediateDirectories: true)
        try Data("d".utf8).write(to: fixture.url("Desktop/desk.txt"))
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, start: fixture.url("Alpha")) }
        await driver.waitFor("inner.txt")
        driver.press([chord(.desktop)])
        await driver.waitFor("desk.txt")
        // There is no Documents: the chord does nothing.
        driver.press([chord(.documents)])
        #expect(driver.screen().contains("desk.txt"))
        driver.press([chord(.home)])
        await driver.waitFor("notes.md")
        // ⇧⌘G opens the go-to field, as `/` does.
        driver.press([chord(.goToFolder)])
        await driver.waitFor("Go to:")
        #expect(caller.heard.isEmpty)
    }

    @Test("⇧⌘. shows and hides the hidden files, however the terminal spells it; ⌘. cancels")
    func hiddenFilesAndCancel() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller) }
        let shown = await driver.waitFor("notes.md")
        #expect(!shown.contains(".hidden"))
        // Under the kitty protocol's alternate keys, ⌃>.
        #expect(chord(.toggleHiddenFiles) == KeyEvent(key: .character(">"), ctrl: true))
        driver.press([chord(.toggleHiddenFiles)])
        await driver.waitFor(".hidden")
        // Without them, ⌃. with the Shift bit: not ⌘., which cancels.
        driver.press([KeyEvent(key: .character("."), ctrl: true, shift: true)])
        await settle { !driver.screen().contains(".hidden") }
        #expect(caller.heard.isEmpty)
        driver.press([chord(.cancel)])
        await settle { !caller.heard.isEmpty }
        #expect(caller.heard == ["cancelled (presented: false)"])
    }

    @Test("The status bar names the preview's and the views' chords only where they can arrive")
    func statusItems() {
        let enhanced = FilePanel.statusItems(viewMode: .list, createsFolders: false, chords: .control).map(\.shortcut)
        #expect(enhanced.contains("⌃⇧P"), "\(enhanced)")
        #expect(enhanced.contains("⌃2|⌃3"), "\(enhanced)")
        let legacy = FilePanel.statusItems(viewMode: .list, createsFolders: false, chords: nil).map(\.shortcut)
        #expect(!legacy.contains("⌃⇧P"), "\(legacy)")
        // No stand-in for ⌘, no chords.
        let none = FilePanel.statusItems(viewMode: .list, createsFolders: false, chords: .unavailable).map(\.shortcut)
        #expect(none == legacy)
    }
}
