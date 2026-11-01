//  🖥️ TUI — A Terminal UI framework for Swift
//  SplitViewPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Split View page")
struct SplitViewPageTests {
    @Test("The NavigationSplitView is first, and the HSplitView and VSplitView demo is below it")
    func holdsBothDemos() {
        let app = TestApp(width: 100, height: 40) { SplitViewPage() }
        #expect(app.screen.contains("page.splitView.folders"), "the mail split view fills the first screen")
        #expect(!app.screen.contains("page.splitView.hvSection"), "the other demo is below the fold")

        app.scroll(.down, by: 20, at: CellPoint(x: 5, y: 5))
        #expect(app.screen.contains("page.splitView.hvSection"), "\(app.screen)")
        #expect(app.screen.contains("page.splitView.hvExplain"))
        // The left pane is narrow, and shows the start of its key.
        for pane in ["page.splitView.hv.l", "page.splitView.hv.top", "page.splitView.hv.bottom"] {
            #expect(app.screen.contains(pane), "\(pane) is drawn: \(app.screen)")
        }
    }
}
