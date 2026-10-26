//  🖥️ TUI — A Terminal UI framework for Swift
//  HelpLinkTests.swift
//
//  `HelpLink`: a `?` button that runs its action, or opens its URL through the
//  environment's `openURL`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What the links under test did.
private final class HelpLog: @unchecked Sendable {
    var entries: [String] = []
}

@MainActor
@Suite("HelpLink")
struct HelpLinkTests {
    @Test("An action link draws a ? and runs its action")
    func actionLink() {
        let log = HelpLog()
        let harness = InputChainHarness()
        #expect(harness.frame(HelpLink { log.entries.append("help") }).lines.joined().stripped.contains("?"))
        harness.play([KeyEvent(key: .enter)]) { HelpLink { log.entries.append("help") } }
        #expect(log.entries == ["help"])
    }

    @Test("A destination link opens its URL through the environment's openURL")
    func destinationLink() {
        let log = HelpLog()
        let harness = InputChainHarness()
        let url = URL(string: "https://example.com/help")!
        harness.play([KeyEvent(key: .enter)]) {
            HelpLink(destination: url)
                .environment(\.openURL, OpenURLAction { opened in log.entries.append(opened.absoluteString) })
        }
        #expect(log.entries == ["https://example.com/help"])
    }
}
