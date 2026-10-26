//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalFeaturesPublishingTests.swift
//
//  `\.terminalFeatures` is published in halves: what the terminal does with
//  the pointer as the app starts (lane O12), whether it posts notifications
//  as it is named and whether the progress bar shows with every frame (lane
//  GHOSTTY). Each half keeps the other's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

private struct BlankApp: App {
    var body: some Scene {
        WindowGroup { Text("blank") }
    }
}

@MainActor
@Suite("Terminal features published in halves")
struct TerminalFeaturesPublishingTests {
    @Test("A frame's answer on the progress bar keeps what the terminal does with the pointer")
    func progressKeepsPointerAnswers() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(BlankApp())
        harness.tuiContext.terminalFeatures = TerminalFeatures(
            pointerShapes: true, controlPointerShapes: true, postsNotifications: true)
        loop.sendsProgressReports = true
        loop.publishTerminalFeatures(
            ClientCapabilities(
                emojiChrome: false, skinTonesSafe: false, blockElementsFillTheLine: false,
                cornerTrianglesFillTheCell: false, drawsProgressBars: true, mayImproveShortly: false))
        let features = harness.tuiContext.terminalFeatures
        #expect(features.showsProgress)
        #expect(features.postsNotifications)
        #expect(features.pointerShapes)
        #expect(features.controlPointerShapes)
    }

    @Test("Each half's update keeps the other's")
    func halvesKeepEachOther() {
        let pointer = TerminalFeatures.none.withPointerShapes(true, controlPointerShapes: true)
        let both = pointer.withProgress(showsProgress: true, postsNotifications: true)
        #expect(both == TerminalFeatures(
            pointerShapes: true, controlPointerShapes: true, showsProgress: true, postsNotifications: true))
        #expect(both.withPointerShapes(false, controlPointerShapes: false)
            == TerminalFeatures(showsProgress: true, postsNotifications: true))
    }
}
