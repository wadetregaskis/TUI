//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelAnimatedPreviewTests.swift
//
//  An animated picture selected in a file panel plays in its preview, as the
//  same `Image` plays anywhere else: the Example's bouncing ball, in the list
//  view's pane and the column view's preview column.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanelImages
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUITestSupport

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel animated preview", .serialized)
struct FilePanelAnimatedPreviewTests {
    /// The Example's animated GIF, which the panels' preview was seen not to play.
    private static var bouncingBall: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Example/Resources/bouncing-ball.gif")
    }

    private func panel(_ fixture: FilePanelFixture, caller: FilePanelCaller, mode: FilePanelViewMode) -> some View {
        let store = MockStorageBackend()
        store.setValue(FilePanelPreviewVisibility.shown.rawValue, forKey: FilePanelPreviewVisibility.storageKey(for: nil))
        store.setValue(mode.rawValue, forKey: FilePanelViewMode.storageKey(for: nil))
        return FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() }
        )
        .fileDialogPicturePreviews()
        .defaultAppStorage(store)
    }

    @Test("A selected animated GIF plays in the preview", arguments: [FilePanelViewMode.list, .columns])
    func animatedGIFPlays(mode: FilePanelViewMode) async throws {
        try await ColorDepth.withCurrent(.truecolor) {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            try FileManager.default.copyItem(at: Self.bouncingBall, to: fixture.url("ball.gif"))
            let caller = FilePanelCaller()
            let driver = FilePanelDriver(width: 110, height: 34) { panel(fixture, caller: caller, mode: mode) }
            await driver.waitFor("notes.md")
            // Folders first — Alpha/, linked/ — then ball.gif: ↓ twice, Space selects it.
            driver.press(.down, times: 2)
            driver.press(.space)
            await settle { driver.screen().components(separatedBy: "ball.gif").count - 1 >= 2 }

            // Draws on, the clock moving, until what the preview shows changes:
            // the frames decode on a task, so real time passes between draws too.
            // A still shows at most two pictures — the placeholder and the
            // picture — so a third is a frame played.
            var seenFrames: Set<[String]> = []
            await settle {
                driver.app.advance(by: .milliseconds(50))
                seenFrames.insert(driver.styledRows())
                return seenFrames.count >= 6
            }
            #expect(seenFrames.count >= 6, "the preview never moved past its first frame: \(driver.screen())")
        }
    }

    /// An 8 × 8 red PNG.
    private static let redPicture = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC")!

    @Test("A still picture's preview holds still: the measure the test above relies on", arguments: [FilePanelViewMode.list, .columns])
    func stillPictureHoldsStill(mode: FilePanelViewMode) async throws {
        try await ColorDepth.withCurrent(.truecolor) {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            try Self.redPicture.write(to: fixture.url("ball.png"))
            let caller = FilePanelCaller()
            let driver = FilePanelDriver(width: 110, height: 34) { panel(fixture, caller: caller, mode: mode) }
            await driver.waitFor("notes.md")
            driver.press(.down, times: 2)
            driver.press(.space)
            await settle { driver.screen().components(separatedBy: "ball.png").count - 1 >= 2 }
            var seen: Set<[String]> = [driver.styledRows()]
            for _ in 0..<60 {
                driver.app.advance(by: .milliseconds(50))
                // A budget, sound for an assertion that the still did NOT move.
                await yieldToSpawnedWork()
                seen.insert(driver.styledRows())
            }
            #expect(seen.count < 3, "a still changed \(seen.count - 1) times")
        }
    }
}
