//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelLoadingDelayTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("File panel loading placeholder delay", .serialized)
struct FilePanelLoadingDelayTests {
    private func panel(_ root: URL, caller: FilePanelCaller) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: root, homeDirectory: root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() })
    }

    @Test("Fast folder loading does not show Loading placeholder initially")
    func fastFolderLoadingDoesNotShowLoading() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let emptyFolder = fixture.url("EmptyFolder")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        let browser = FileBrowser(directory: emptyFolder, rule: FileChoiceRule())
        // Initially while loading, placeholder text is suppressed during the delay window
        #expect(browser.state == .loading)
        #expect(!browser.showsLoadingPlaceholder)
        #expect(browser.emptyText.isEmpty)

        // Refresh completes fast (< 250ms)
        await browser.refresh()
        #expect(browser.state == .loaded)
        #expect(!browser.showsLoadingPlaceholder)
        #expect(browser.emptyText == LocalizationService.shared.string(for: LocalizationKey.FilePanel.emptyFolder))
    }

    @Test("Opening an empty folder displays empty folder notice without flashing Loading")
    func emptyFolderShowsEmptyNotice() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let emptyFolder = fixture.url("EmptyFolder")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(emptyFolder, caller: caller) }
        let emptyMessage = LocalizationService.shared.string(for: LocalizationKey.FilePanel.emptyFolder)
        let loadingMessage = LocalizationService.shared.string(for: LocalizationKey.FilePanel.loading)
        let shown = await driver.waitFor(emptyMessage)
        #expect(shown.contains(emptyMessage))
        #expect(!shown.contains(loadingMessage))
    }

    @Test("Expanding an empty subfolder does not show a Loading row")
    func expandingEmptySubfolderDoesNotShowLoadingRow() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let emptySub = fixture.url("EmptySub")
        try FileManager.default.createDirectory(at: emptySub, withIntermediateDirectories: true)

        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture.root, caller: caller) }
        await driver.waitFor("notes.md")
        let loadingMessage = LocalizationService.shared.string(for: LocalizationKey.FilePanel.loading)

        // EmptySub sorts before linked/ and notes.md.
        // Down past Alpha/ to EmptySub/
        driver.press(.down)
        driver.press(.right)
        // Draw frames as subfolder load completes
        for _ in 0..<5 {
            driver.app.advance(by: .milliseconds(20))
            #expect(!driver.screen().contains(loadingMessage))
        }
    }

    @Test("Loading placeholder appears after delay if folder is still loading")
    func loadingPlaceholderAppearsAfterDelay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }

        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        #expect(!browser.showsLoadingPlaceholder)
        #expect(browser.emptyText.isEmpty)

        // Wait for the delay window (250ms) to elapse and the task to update
        let deadline = ContinuousClock.now + .seconds(2)
        while !browser.showsLoadingPlaceholder && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(browser.showsLoadingPlaceholder)
        #expect(browser.emptyText == LocalizationService.shared.string(for: LocalizationKey.FilePanel.loading))
    }

    @Test("Subfolder loading does not mark folder as showing loading initially")
    func subfolderLoadingDelay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let emptySubfolder = fixture.url("Alpha/EmptySub")
        try FileManager.default.createDirectory(at: emptySubfolder, withIntermediateDirectories: true)

        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        await browser.refresh()

        #expect(!browser.foldersShowingLoading.contains(emptySubfolder.path))
        await browser.loadFolder(emptySubfolder)
        // Fast load completed, folder was never added to foldersShowingLoading
        #expect(!browser.foldersShowingLoading.contains(emptySubfolder.path))
    }
}
