//  🖥️ TUI — A Terminal UI framework for Swift
//  UmbrellaReexportsFoundationTests.swift
//
//  `import TUI` brings Foundation with it, as `import SwiftUI` does (the
//  owner's answer to A-W1-1, 2026-10-27): this file imports nothing else, so
//  it compiles only while the umbrella re-exports Foundation.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI

@Suite("import TUI brings Foundation")
struct UmbrellaReexportsFoundationTests {
    @Test("A shape's geometry and Foundation's values need no import of their own")
    func foundationInScope() {
        let rect = CGRect(x: 0, y: 0, width: 4, height: 2)
        let url = URL(string: "https://example.com")
        let date = Date(timeIntervalSince1970: 0)
        #expect(rect.width == 4)
        #expect(url?.host == "example.com")
        #expect(date.timeIntervalSince1970 == 0)
    }
}
