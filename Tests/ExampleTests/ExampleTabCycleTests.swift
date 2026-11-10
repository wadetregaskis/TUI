//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleTabCycleTests.swift
//
//  Tab walks a page's focus stops and comes back round, on the Example's
//  pages as they run: in the window, under its bars and menu bar.
//
//  Created by Wade Tregaskis
//  License: MIT

// Only where the package can depend on the app (see Package.swift).
#if canImport(Example)

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("Tab comes back round the Example's pages", .serialized)
struct ExampleTabCycleTests {
    /// The Empty State page has one button, in a page that scrolls at 80×24:
    /// two stops, the button and the page. A Tab from the button reached the
    /// page, and no number of Tabs came back to the button.
    @Test("Two Tabs from the Empty State page's button come back to it")
    func emptyState() {
        let app = TestApp(ExampleApp(), width: 80, height: 24)
        app.press(.character("e"))
        app.press(.enter)
        let once = app.screen.line(containing: "page.contentUnavailable.refreshPressed")
        #expect(once?.contains("1×") == true, "the button holds the focus first: \(app.screen)")
        app.press(.tab, times: 2)
        app.press(.enter)
        let twice = app.screen.line(containing: "page.contentUnavailable.refreshPressed")
        #expect(twice?.contains("2×") == true, "back on the button: \(app.screen)")
    }
}

#endif
