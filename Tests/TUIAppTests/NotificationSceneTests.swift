//  🖥️ TUI — A Terminal UI framework for Swift
//  NotificationSceneTests.swift
//
//  Toasts drawn by the scene: every window's chrome draws the app's
//  notifications over its content, with no host of the app's own.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Notifications drawn by the scene")
struct NotificationSceneTests {
    /// A harness whose environment holds `service`, as a running app's does.
    private func harness(_ service: NotificationService, width: Int = 60, height: Int = 14) -> InputChainHarness {
        InputChainHarness(width: width, height: height) { $0.notificationService = service }
    }

    /// The row and column `text` starts at in `screen`, if it is there.
    private func position(of text: String, in screen: FrameBuffer) -> (row: Int, column: Int)? {
        for (row, line) in screen.lines.enumerated() {
            if let range = line.stripped.range(of: text) {
                return (row, line.stripped.distance(from: line.stripped.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    @Test("A window draws a posted toast with no host added")
    func windowHostsToasts() {
        let service = NotificationService()
        let harness = harness(service)
        service.post("Saved the file")
        // A second in: past the fade-in, on the frame clock the harness stamps.
        harness.now = Int64(MonotonicClock.nowNanoseconds) + 1_000_000_000
        let screen = harness.frame(_WindowChromeHost(content: Text("Page")))
        #expect(screen.lines.contains { $0.stripped.contains("Saved the file") })
    }

    @Test("A toast moves nothing in a page smaller than the window")
    func smallPageStaysCentred() throws {
        let service = NotificationService()
        let harness = harness(service)
        let before = try #require(position(of: "Page", in: harness.frame(_WindowChromeHost(content: Text("Page")))))
        service.post("Saved")
        harness.now = Int64(MonotonicClock.nowNanoseconds) + 1_000_000_000
        let screen = harness.frame(_WindowChromeHost(content: Text("Page")))
        #expect(screen.lines.contains { $0.stripped.contains("Saved") })
        #expect(position(of: "Page", in: screen).map { $0 == before } == true)
    }
}
