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
import TUITesting

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

    @Test("Loading placeholder appears once the delay has passed, not a moment before")
    func loadingPlaceholderAppearsAfterDelay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }

        let clock = TestClock()
        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule(), clock: clock)
        await settle(until: { clock.sleepers == 1 })
        #expect(clock.sleepers == 1)

        clock.advance(by: FileBrowser.loadingPlaceholderDelay - .milliseconds(1))
        // Turns enough for a woken timer to have run; none is due.
        for _ in 0..<100 { await Task.yield() }
        #expect(!browser.showsLoadingPlaceholder)
        #expect(browser.emptyText.isEmpty)

        clock.advance(by: .milliseconds(1))
        await browser.loadingPlaceholderTask?.value
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

    @Test("Navigating on the way to a loading folder preserves its loading timer")
    func loadingTimerPreservedOnTheWay() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let keepUrl = fixture.url("Alpha")
        let dropUrl = fixture.url("Other")

        let browser = FileBrowser(directory: fixture.root, rule: FileChoiceRule())
        let clock = TestClock()
        let keepTask: Task<Void, Never> = Task { _ = try? await clock.sleep(for: .seconds(10)) }
        let dropTask: Task<Void, Never> = Task { _ = try? await clock.sleep(for: .seconds(10)) }
        browser.folderLoadingTimers[keepUrl.path] = keepTask
        browser.folderLoadingTimers[dropUrl.path] = dropTask

        // Navigating to keepUrl is "on the way"
        browser.keepFolders(onTheWayTo: keepUrl)
        #expect(browser.folderLoadingTimers[keepUrl.path] != nil, "Timer for folder on the way should be preserved")
        #expect(!keepTask.isCancelled)

        // dropUrl is not on the way and should be cancelled
        #expect(browser.folderLoadingTimers[dropUrl.path] == nil, "Timer for unrelated folder should be cancelled")
        #expect(dropTask.isCancelled)

        keepTask.cancel()
    }
}
